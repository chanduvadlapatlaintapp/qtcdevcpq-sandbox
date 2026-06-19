/**
 * @description Queueable that processes contract cancellation/supersession after a delay,
 *              allowing CPQ to terminate subscriptions before the partial-cancellation guard runs.
 *              Enqueued from OrderTriggerHelper when an RMA order is contracted.
 * @author Sahal Mohamed
 * @jira BIZ-69730
 */
public inherited sharing class ContractStatusQueueable implements Queueable {

    public static final String ACTION_CANCELLATION = 'CANCELLATION';
    public static final String ACTION_SUPERSESSION = 'SUPERSESSION';

    private Map<Id, Id> contractIdToAccountId;
    private String action;

    /**
     * @description Constructor
     * @param contractIdToAccountId Map of Contract Id to Account Id (accountId is unused for SUPERSESSION)
     * @param action ACTION_CANCELLATION or ACTION_SUPERSESSION
     */
    public ContractStatusQueueable(Map<Id, Id> contractIdToAccountId, String action) {
        this.contractIdToAccountId = contractIdToAccountId;
        this.action = action;
    }

    /***********************************************************************************************
     *
     * Queueable execute
     *
     ***********************************************************************************************/

    public void execute(QueueableContext ctx) {
        Set<Id> contractIds = contractIdToAccountId.keySet();

        Nebula.Logger.info('ContractStatusQueueable.execute – starting ' + action + ' for contracts: ' + contractIds)
            .addTag('ContractStatusQueueable')
            .addTag(action);

        Map<Id, Boolean> activeSubsMap = queryActiveRecurringSubscriptions(contractIds);

        Set<Id> readyContractIds = new Set<Id>();
        Set<Id> skippedContractIds = new Set<Id>();

        for (Id contractId : contractIds) {
            if (activeSubsMap.containsKey(contractId) && activeSubsMap.get(contractId)) {
                skippedContractIds.add(contractId);
            } else {
                readyContractIds.add(contractId);
            }
        }

        if (!skippedContractIds.isEmpty()) {
            Nebula.Logger.warn('ContractStatusQueueable – skipped ' + skippedContractIds.size()
                    + ' contract(s) with active recurring subscriptions: ' + skippedContractIds)
                .addTag('ContractStatusQueueable')
                .addTag(action)
                .addTag('PartialCancellation');
        }

        if (readyContractIds.isEmpty()) {
            Nebula.Logger.saveLog();
            return;
        }

        if (action == ACTION_CANCELLATION) {
            processCancellation(readyContractIds);
        } else {
            processSupersession(readyContractIds);
        }

        Nebula.Logger.saveLog();
    }

    /***********************************************************************************************
     *
     * Private – action processors
     *
     ***********************************************************************************************/

    /**
     * @description Full cancellation: update contract status, close NYMY/Renewal opps, lapse account.
     */
    private void processCancellation(Set<Id> readyContractIds) {
        List<Contract> contractsToUpdate = new List<Contract>();
        for (Id contractId : readyContractIds) {
            contractsToUpdate.add(new Contract(
                Id = contractId,
                Status = ContractConstants.STATUS_CANCELLED_LAPSED,
                AccountId = contractIdToAccountId.get(contractId)
            ));
        }

        List<Opportunity> oppsToClose = ContractUtil.getNymyAndRenewalOpportunitiesFromContracts(Pluck.ids(contractsToUpdate));
        for (Opportunity opp : oppsToClose) {
            opp.StageName = OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED;
        }

        Map<Id, Integer> accountActiveContractCountMap = ContractUtil.getActiveContractCountOnAccount(
            Pluck.ids(Contract.AccountId, contractsToUpdate)
        );

        Map<Id, String> currentContractStatuses = new Map<Id, String>();
        for (Contract c : [SELECT Id, Status FROM Contract WHERE Id IN :readyContractIds]) {
            currentContractStatuses.put(c.Id, c.Status);
        }

        Map<Id, Integer> contractsBeingCancelledPerAccount = new Map<Id, Integer>();
        for (Contract contract : contractsToUpdate) {
            if (currentContractStatuses.get(contract.Id) != ContractConstants.STATUS_INFORCE) {
                continue;
            }
            Integer current = contractsBeingCancelledPerAccount.containsKey(contract.AccountId)
                ? contractsBeingCancelledPerAccount.get(contract.AccountId) : 0;
            contractsBeingCancelledPerAccount.put(contract.AccountId, current + 1);
        }

        Map<Id, Account> accountsToCancel = new Map<Id, Account>();
        for (Contract contract : contractsToUpdate) {
            Integer activeCount = accountActiveContractCountMap.containsKey(contract.AccountId)
                ? accountActiveContractCountMap.get(contract.AccountId) : 0;
            Integer beingCancelled = contractsBeingCancelledPerAccount.containsKey(contract.AccountId)
                ? contractsBeingCancelledPerAccount.get(contract.AccountId) : 0;

            if ((activeCount - beingCancelled) < 1) {
                accountsToCancel.put(contract.AccountId, new Account(
                    Id = contract.AccountId,
                    Type = AccountConstants.TYPE_CLIENT_LAPSED
                ));
            }
        }

        Savepoint sp = Database.setSavepoint();
        try {
            update contractsToUpdate;
            update oppsToClose;
            update accountsToCancel.values();

            Nebula.Logger.info('ContractStatusQueueable – CANCELLATION DML succeeded for contracts: ' + readyContractIds)
                .addTag('ContractStatusQueueable')
                .addTag('CANCELLATION');
        } catch (Exception e) {
            Database.rollback(sp);
            Nebula.Logger.error('ContractStatusQueueable.processCancellation – rolled back all DML', e)
                .addTag('ContractStatusQueueable')
                .addTag('CANCELLATION')
                .addTag('RolledBack');
        }
    }

    /**
     * @description Supersession: update contract status, close NYMY/Renewal opps.
     */
    private void processSupersession(Set<Id> readyContractIds) {
        List<Contract> contractsToUpdate = new List<Contract>();
        for (Id contractId : readyContractIds) {
            contractsToUpdate.add(new Contract(
                Id = contractId,
                Status = ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT
            ));
        }

        List<Opportunity> oppsToClose = ContractUtil.getNymyAndRenewalOpportunitiesFromContracts(Pluck.ids(contractsToUpdate));
        for (Opportunity opp : oppsToClose) {
            opp.StageName = OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            update contractsToUpdate;
            update oppsToClose;

            Nebula.Logger.info('ContractStatusQueueable – SUPERSESSION DML succeeded for contracts: ' + readyContractIds)
                .addTag('ContractStatusQueueable')
                .addTag('SUPERSESSION');
        } catch (Exception e) {
            Database.rollback(sp);
            Nebula.Logger.error('ContractStatusQueueable.processSupersession – rolled back all DML', e)
                .addTag('ContractStatusQueueable')
                .addTag('SUPERSESSION')
                .addTag('RolledBack');
        }
    }

    /***********************************************************************************************
     *
     * Private – subscription query
     *
     ***********************************************************************************************/

    /**
     * @description Returns a map indicating whether each contract still has active (non-terminated)
     *              recurring subscriptions. One-time and Evergreen subs are excluded — Evergreen subs
     *              never receive a TerminatedDate by design and must not block cancellation.
     */
    private Map<Id, Boolean> queryActiveRecurringSubscriptions(Set<Id> contractIds) {
        Map<Id, Boolean> result = new Map<Id, Boolean>();
        for (Id contractId : contractIds) {
            result.put(contractId, false);
        }

        for (AggregateResult ar : [
            SELECT SBQQ__Contract__c contractId
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c IN :contractIds
              AND SBQQ__SubscriptionType__c != :SubscriptionConstants.SUBSCRIPTIONTYPE_ONETIME
              AND SBQQ__SubscriptionType__c != :SubscriptionConstants.SUBSCRIPTIONTYPE_EVERGREEN
              AND SBQQ__TerminatedDate__c = null
            GROUP BY SBQQ__Contract__c
        ]) {
            result.put((Id) ar.get('contractId'), true);
        }

        return result;
    }
}