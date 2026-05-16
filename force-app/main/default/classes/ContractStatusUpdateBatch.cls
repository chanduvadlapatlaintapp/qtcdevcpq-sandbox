/**
 * @description Batch class to close Renewal and NYMY Opportunities on Cancelled/Superseded Contracts
 * BIZ-69730: Opportunities should only be closed when ALL recurring subscriptions are terminated
 * 
 * This batch:
 * 1. Queries contracts flagged with Pending_Opp_Closure__c = true
 * 2. Validates that all recurring subscriptions are terminated
 * 3. Closes related NYMY and Renewal opportunities to "Closed - Should Never have been opened"
 * 4. Resets the Pending_Opp_Closure__c flag after processing
 * 
 * @author Sahal Mohamed
 * @jira BIZ-69730
 */
public class ContractStatusUpdateBatch implements Database.Batchable<SObject>, Schedulable {
    
    private String query;
    
    /**
     * @description Default constructor - processes all contracts pending opportunity closure
     */
    public ContractStatusUpdateBatch() {
        this.query = 'SELECT Id, Status, AccountId ' +
                     'FROM Contract ' +
                     'WHERE Pending_Opp_Closure__c = true ' +
                     'ORDER BY CreatedDate ASC';
    }
    
    /**
     * @description Constructor with custom query for testing
     * @param customQuery SOQL query to use
     */
    public ContractStatusUpdateBatch(String customQuery) {
        this.query = customQuery;
    }
    
    /**
     * @description Schedulable execute method
     * @param sc SchedulableContext
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new ContractStatusUpdateBatch(), 50);
    }
    
    /**
     * @description Start method to get contracts pending opportunity closure
     * @param bc BatchableContext
     * @return Database.QueryLocator
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Nebula.Logger.info('ContractStatusUpdateBatch started - processing contracts pending opportunity closure');
        Nebula.Logger.saveLog();
        return Database.getQueryLocator(query);
    }
    
    /**
     * @description Execute method to process contracts and close related opportunities
     * @param bc BatchableContext
     * @param scope List of Contracts to process
     */
    public void execute(Database.BatchableContext bc, List<Contract> scope) {
        Set<Id> contractIds = new Set<Id>();
        List<Contract> contractsToResetFlag = new List<Contract>();
        List<Opportunity> oppsToClose = new List<Opportunity>();
        
        for (Contract con : scope) {
            contractIds.add(con.Id);
        }
        
        // BIZ-69730: Get contracts where ALL recurring subscriptions are terminated
        Set<Id> eligibleContractIds = ContractSubscriptionService.getContractsWithAllSubscriptionsTerminated(contractIds);
        
        // Log contracts that were skipped due to active subscriptions
        Set<Id> skippedContractIds = new Set<Id>(contractIds);
        skippedContractIds.removeAll(eligibleContractIds);
        if (!skippedContractIds.isEmpty()) {
            Nebula.Logger.info('Skipping opportunity closure for contracts with active subscriptions: ' + skippedContractIds);
            // Keep the flag set for skipped contracts - they'll be processed in next batch run
        }
        
        if (eligibleContractIds.isEmpty()) {
            Nebula.Logger.info('No eligible contracts to process in this batch (all have active subscriptions)');
            Nebula.Logger.saveLog();
            return;
        }
        
        // Get NYMY and Renewal opportunities to close for eligible contracts
        oppsToClose = ContractUtil.getNymyAndRenewalOpportunitiesFromContracts(eligibleContractIds);
        
        if (oppsToClose.isEmpty()) {
            Nebula.Logger.info('No open NYMY/Renewal opportunities found for eligible contracts');
        } else {
            for (Opportunity opp : oppsToClose) {
                opp.StageName = OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED;
            }
            Nebula.Logger.info('Closing ' + oppsToClose.size() + ' NYMY/Renewal opportunities');
        }
        
        // Prepare to reset the flag for processed contracts
        for (Id contractId : eligibleContractIds) {
            Contract con = new Contract(
                Id = contractId,
                Pending_Opp_Closure__c = false
            );
            contractsToResetFlag.add(con);
        }
        
        // Update opportunities and reset contract flags
        try {
            if (!oppsToClose.isEmpty()) {
                update oppsToClose;
                Nebula.Logger.info('Successfully closed ' + oppsToClose.size() + ' opportunities');
            }
            
            if (!contractsToResetFlag.isEmpty()) {
                update contractsToResetFlag;
                Nebula.Logger.info('Reset Pending_Opp_Closure__c flag for ' + contractsToResetFlag.size() + ' contracts');
            }
        } catch (Exception e) {
            Nebula.Logger.error('Error in ContractStatusUpdateBatch.execute', e);
        }
        
        Nebula.Logger.saveLog();
    }
    
    /**
     * @description Finish method
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        Nebula.Logger.info('ContractStatusUpdateBatch completed');
        Nebula.Logger.saveLog();
    }
}