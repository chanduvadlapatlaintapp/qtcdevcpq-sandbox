/**
* @description Service class for Renewal Quote Creation logic
* @author Sahal Mohamed
* @changelog BIZ-82935: Removed handleRenewalPauseContract gate — Renewal Hold is now managed at Opportunity level post-quote
**/
public with sharing class RenewalQuoteCreationService {
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
    * @description determines whether a renewal quote or opportunity should be created for a contract based on its end date, 
    *              renewal status, and associated opportunity stage, and updates the contract accordingly in the Salesforce database.
    * @param renewalContract Contract
    **/
    public static void checkRenewalQuoteCreation(Contract renewalContract) {
        Nebula.Logger.debug('Checking renewal quote creation for contract ' + renewalContract.Id)
            .addTag('RenewalQuoteCreationService')
            .addTag('AutoRenewal')
            .setRecordId(renewalContract.Id);
        
        List<Contract> renewalQuoteContractsToUpdate = new List<Contract>();
        List<Contract> renewalOppContractsToUpdate = new List<Contract>();
        
        // BIZ-82935: Renewal Hold moved to Opportunity level. Nothing blocks Renewal Opp creation
        // except the Exclude from Auto-Renewal flag. Always process normally.
        processNormalRenewalContract(renewalContract, renewalQuoteContractsToUpdate, renewalOppContractsToUpdate);

        updateContracts(renewalQuoteContractsToUpdate, 'renewal quote');
        updateContracts(renewalOppContractsToUpdate, 'renewal opportunity');
    }
    
    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /**
    * @description processes normal renewal contracts without pause
    * @param renewalContract Contract
    * @param renewalQuoteContractsToUpdate List<Contract>
    * @param renewalOppContractsToUpdate List<Contract>
    **/
    private static void processNormalRenewalContract(Contract renewalContract, List<Contract> renewalQuoteContractsToUpdate, List<Contract> renewalOppContractsToUpdate) {
        if (renewalContract.Deal_Type__c != ContractConstants.DEAL_TYPE_ADD_ON) {
            processStandardContract(renewalContract, renewalQuoteContractsToUpdate, renewalOppContractsToUpdate);
        } else {
            processAddOnContract(renewalContract, renewalOppContractsToUpdate);
        }
    }
    
    /**
    * @description processes standard contracts (non-add-on)
    * @param renewalContract Contract
    * @param renewalQuoteContractsToUpdate List<Contract>
    * @param renewalOppContractsToUpdate List<Contract>
    **/
    private static void processStandardContract(Contract renewalContract, List<Contract> renewalQuoteContractsToUpdate, List<Contract> renewalOppContractsToUpdate) {
        if (shouldCreateRenewalQuote(renewalContract)) {
            Contract contractRecord = new Contract(
                Id = renewalContract.Id,
                SBQQ__RenewalQuoted__c = true,
                SBQQ__RenewalTerm__c = 12,
                Contract_Renewal_Job_Status__c = ContractConstants.CONTRACT_JOB_STATUS_AUTOMATION_INITIATED
            );
            renewalQuoteContractsToUpdate.add(contractRecord);
        } else {
            Contract contractRecord = new Contract(
                Id = renewalContract.Id,
                SBQQ__RenewalForecast__c = true,
                SBQQ__RenewalTerm__c = 12
            );
            renewalOppContractsToUpdate.add(contractRecord);
        }
    }
    
    /**
    * @description processes add-on contracts
    * @param renewalContract Contract
    * @param renewalOppContractsToUpdate List<Contract>
    **/
    private static void processAddOnContract(Contract renewalContract, List<Contract> renewalOppContractsToUpdate) {
        Contract contractRecord = new Contract(
            Id = renewalContract.Id,
            SBQQ__RenewalForecast__c = true,
            SBQQ__RenewalTerm__c = 12,
            Contract_Renewal_Job_Status__c = ContractConstants.CONTRACT_JOB_STATUS_MIGRATES_ISSUE
        );
        renewalOppContractsToUpdate.add(contractRecord);
    }
    
    /**
    * @description determines if a renewal quote should be created
    * @param renewalContract Contract
    * @return Boolean
    **/
    private static Boolean shouldCreateRenewalQuote(Contract renewalContract) {
        Date currentDate = Date.today();
        Date proformaInvoicedate = renewalContract.EndDate.addDays(-90);
        Boolean isWithinProformaWindow = currentDate >= proformaInvoicedate;
        Boolean isNotAlreadyQuoted = renewalContract.SBQQ__RenewalQuoted__c == false;
        
        return isWithinProformaWindow && isNotAlreadyQuoted && isRenewalOpportunityValid(renewalContract);
    }
    
    /**
    * @description checks if renewal opportunity is valid for quote creation
    * @param renewalContract Contract
    * @return Boolean
    **/
    private static Boolean isRenewalOpportunityValid(Contract renewalContract) {
        if (renewalContract.SBQQ__RenewalOpportunity__c == null) {
            return true;
        }
        
        String stageName = renewalContract.SBQQ__RenewalOpportunity__r.StageName;
        Boolean isClosed = renewalContract.SBQQ__RenewalOpportunity__r.IsClosed;
        
        Boolean isValidStage = (!isClosed || stageName == OpportunityConstants.STAGE_CLOSED_WON) &&
                              stageName != OpportunityConstants.STAGE_CLOSED_LOST &&
                              stageName != OpportunityConstants.STAGE_PENDING_CANCELLATION &&
                              stageName != OpportunityConstants.STAGE_CLOSED_SUPERSEDED;
                              
        return isValidStage;
    }
    
    /**
    * @description updates contracts and handles exceptions
    * @param contractsToUpdate List<Contract>
    * @param updateType String
    **/
    private static void updateContracts(List<Contract> contractsToUpdate, String updateType) {
        if (!contractsToUpdate.isEmpty()) {
            Nebula.Logger.info('Updating ' + contractsToUpdate.size() + ' contracts for ' + updateType + ' creation')
                .addTag('RenewalQuoteCreationService')
                .addTag('AutoRenewal')
                .addTag('DML_Update');
            try {
                update contractsToUpdate;
            } catch (Exception e) {
                Nebula.Logger.error('Exception occurred while updating contracts for ' + updateType + 's: ' + e.getMessage())
                    .addTag('RenewalQuoteCreationService')
                    .addTag('AutoRenewal')
                    .addTag('DML_Update')
                    .addTag('Error')
                    .setExceptionDetails(e);
                throw e;
            }
        }
    }
    
    /***********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
    * @description Retrieves a list of renewable subscriptions associated with the given contract IDs.
    * @param contractIds A set of contract IDs to filter the subscriptions.
    * @return A list of SBQQ__Subscription__c records that are renewable.
    **/
    public static List<SBQQ__Subscription__c> getRenewableSubscriptions(Set<Id> contractIds){
        Nebula.Logger.debug('Querying renewable subscriptions for ' + contractIds.size() + ' contracts')
            .addTag('RenewalQuoteCreationService')
            .addTag('AutoRenewal');
        List<SBQQ__Subscription__c> subscriptions = [SELECT Id, SBQQ__Contract__c, SBQQ__Contract__r.Exclude_from_Auto_Renewal__c 
                FROM SBQQ__Subscription__c 
                WHERE SBQQ__Contract__c IN :contractIds
                  AND SBQQ__SubscriptionType__c <> :SubscriptionConstants.SUBSCRIPTIONTYPE_ONETIME 
                  AND SBQQ__SubscriptionType__c <> :SubscriptionConstants.SUBSCRIPTIONTYPE_EVERGREEN];
        Nebula.Logger.debug('Found ' + subscriptions.size() + ' renewable subscriptions')
            .addTag('RenewalQuoteCreationService')
            .addTag('AutoRenewal');
        return subscriptions;
    }

    /**
    * @description Retrieves a list of open NYMY opportunities associated with the given contract IDs.
    * @param contractIds A set of contract IDs to filter the opportunities.
    * @return A list of Opportunity records that are open NYMY opportunities.
    **/
    public static List<Opportunity> getOpenNYMYOpportunities(Set<Id> contractIds){
        return [SELECT Id 
                FROM Opportunity 
                WHERE Associated_Contract_OSA__c IN :contractIds
                      AND Deal_Type__c = :OpportunityConstants.DEAL_TYPE_NYMY
                      AND StageName <> :OpportunityConstants.STAGE_CLOSED_WON 
                      AND StageName <> :OpportunityConstants.STAGE_CLOSED_LOST];
    }
    
   	/**
    * @description Returns a map of Contract Id → Max Segment Index
    * @param contractIds A set of contract IDs
    * @return Map<Id, Integer> of max segment index per contract
    **/
    public static Map<Id, Integer> getMaxSegments(Set<Id> contractIds) {
        Map<Id, Integer> results = new Map<Id, Integer>();
        
        for (AggregateResult ar : [
            SELECT SBQQ__Contract__c contractId, MAX(SBQQ__SegmentIndex__c) maxSeg
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c IN :contractIds
            AND SBQQ__SubscriptionType__c <> :SubscriptionConstants.SUBSCRIPTIONTYPE_ONETIME 
            AND SBQQ__SubscriptionType__c <> :SubscriptionConstants.SUBSCRIPTIONTYPE_EVERGREEN
            GROUP BY SBQQ__Contract__c
        ]) {
            results.put((Id) ar.get('contractId'), Integer.valueOf(ar.get('maxSeg')));
        }
        return results;
    }
}