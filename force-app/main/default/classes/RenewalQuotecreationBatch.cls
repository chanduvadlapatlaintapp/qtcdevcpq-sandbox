/**
* @description Batch class for Creating Renewal Quotes.
* @author Suresh Somu
* @jira BIZ-68091
**/
public without sharing class RenewalQuotecreationBatch implements Database.Batchable<sObject>, Schedulable, Database.Stateful {

    private String originalTransactionId;

    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    private String query;
    private Integer scopeSize;
    private Date currentDate = Date.today();

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Default Constructor
    **/
    public RenewalQuotecreationBatch() {
        this.query = getDefaultQuery();
        this.scopeSize = 1;
    }

    /**
    * @description parameterized Constructor
    * @param query
    * @param scopeSize
    **/
    public RenewalQuotecreationBatch(String query, Integer scopeSize) {
        // Set the query and scope size
        this.query = query ?? getDefaultQuery();
        this.scopeSize = scopeSize ?? 1;
    }

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
    * @description Method that can be used to override the query and scope size
    * @param query
    * @param scopeSize
    **/
    public void executeBatch(String query, Integer scopeSize) {
        RenewalQuotecreationBatch obj = new RenewalQuotecreationBatch(query, scopeSize);
        Database.executeBatch(obj, scopeSize);
    }

    /***********************************************************************************************
    *
    * Batch Methods
    *
    ***********************************************************************************************/
    /**
    * @description start method
    * @param bc
    * @return Database.QueryLocator
    */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Each batchable method runs in a separate transaction,
        // so store the first transaction ID to later relate the other transactions
        this.originalTransactionId = Nebula.Logger.getTransactionId();
        
        Nebula.Logger.info('Starting RenewalQuotecreationBatch with scope size: ' + this.scopeSize)
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal');
        Nebula.Logger.debug('Query being executed: ' + this.query)
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal');
        
        // Query Quotes that need to be processed
        String query = this.query;
        Database.QueryLocator queryLocator = Database.getQueryLocator(query);
        
        Nebula.Logger.info('Query executed successfully, starting batch processing')
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal');
        Nebula.Logger.saveLog();
        return queryLocator;
    }

    /**
    * @description execute method
    * @param bc
    * @param renewalContracts
    **/
    public void execute(Database.BatchableContext bc, List<Contract> renewalContracts) {
        // One-time call (per transaction) to set the parent log
        Nebula.Logger.setParentLogTransactionId(this.originalTransactionId);
        
        Nebula.Logger.info('Processing batch of ' + renewalContracts.size() + ' renewal contracts')
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal');

        Map<Id, Contract> mapOfContracts = new Map<ID, Contract>();
        Set<Id> setOfProcessedContractIds = new Set<ID>();
        // Process each renewal Contract
        for (Contract renewalContract : renewalContracts) {
			mapOfContracts.put(renewalContract.Id, renewalContract);
        }
        
        List<SBQQ__Subscription__c> renewableSubscriptions = RenewalQuoteCreationService.getRenewableSubscriptions(mapOfContracts.keySet());
        Nebula.Logger.debug('Processing ' + renewableSubscriptions.size() + ' renewable subscriptions')
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal');

        for(SBQQ__Subscription__c subscription : renewableSubscriptions){
            // Added SBQQ__Contract__r.Exclude_from_Auto_Renewal__c check as part of BIZ-72045
            if(!setOfProcessedContractIds.contains(subscription.SBQQ__Contract__c) && !subscription.SBQQ__Contract__r.Exclude_from_Auto_Renewal__c){
                Contract renewalContract = mapOfContracts.get(subscription.SBQQ__Contract__c);
                Date opportunityRenewalDate = renewalContract.EndDate.addDays(-395);

                Nebula.Logger.debug('Evaluating contract ' + renewalContract.Id +
                    ': EndDate=' + renewalContract.EndDate +
                    ', StartDate=' + renewalContract.StartDate +
                    ', opportunityRenewalDate=' + opportunityRenewalDate +
                    ', currentDate=' + currentDate)
                    .addTag('RenewalQuotecreationBatch')
                    .addTag('AutoRenewal')
                    .setRecordId(renewalContract.Id);

                // Create renewal when there are 395 days or fewer remaining until contract end date,
                // even if the contract has not yet started (BIZ-68091)
                Boolean shouldCreateRenewal = (currentDate >= opportunityRenewalDate);

                if (!shouldCreateRenewal) {
                    Nebula.Logger.debug('Skipping contract ' + renewalContract.Id + ' - not within 395 days of end date (renewal date threshold: ' + opportunityRenewalDate + ')')
                        .addTag('RenewalQuotecreationBatch')
                        .addTag('AutoRenewal')
                        .setRecordId(renewalContract.Id);
                }

                if (shouldCreateRenewal) {
                    Nebula.Logger.info('Contract ' + renewalContract.Id + ' qualifies for renewal - within 395 days of end date (EndDate: ' + renewalContract.EndDate + ', threshold: ' + opportunityRenewalDate + ')')
                        .addTag('RenewalQuotecreationBatch')
                        .addTag('AutoRenewal')
                        .setRecordId(renewalContract.Id);
                    RenewalQuoteCreationService.checkRenewalQuoteCreation(renewalContract);
                }
                setOfProcessedContractIds.add(subscription.SBQQ__Contract__c);
            } else {
                Nebula.Logger.debug('Skipping subscription ' + subscription.Id + ' - contract already processed or excluded from auto renewal')
                    .addTag('RenewalQuotecreationBatch')
                    .addTag('AutoRenewal')
                    .setRecordId(subscription.SBQQ__Contract__c);
            }
        }
        
        Nebula.Logger.saveLog();
    }

    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {
        // The finish method runs in yet-another transaction, so set the parent log again
        Nebula.Logger.setParentLogTransactionId(this.originalTransactionId);
        
        AsyncApexJob job = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedDate, CompletedDate
                           FROM AsyncApexJob WHERE Id = :bc.getJobId()];
        
        Nebula.Logger.info('RenewalQuotecreationBatch completed. Status: ' + job.Status + ', Items Processed: ' + job.JobItemsProcessed + '/' + job.TotalJobItems + ', Errors: ' + job.NumberOfErrors)
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal');
        
        if (job.NumberOfErrors > 0) {
            Nebula.Logger.error('Batch completed with ' + job.NumberOfErrors + ' errors')
                .addTag('RenewalQuotecreationBatch')
                .addTag('AutoRenewal')
                .addTag('BatchError');
        }
        
        Nebula.Logger.info('Finishing running RenewalQuotecreationBatch')
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal');
        Nebula.Logger.saveLog();
    }

    /***********************************************************************************************
    *
    * Schedulable Methods
    *
    ***********************************************************************************************/
    /**
    * @description execute method
    * @param sc
    **/
    public void execute(SchedulableContext sc) {
        Nebula.Logger.info('Scheduled execution of RenewalQuotecreationBatch triggered')
            .addTag('RenewalQuotecreationBatch')
            .addTag('AutoRenewal')
            .addTag('Scheduled');
        Nebula.Logger.saveLog();
        // Execute the batch job
        executeBatch(this.query, this.scopeSize);
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ************************************************************************************************ 
    /**
    * @description set the default query
    * @return String
    **/
    private String getDefaultQuery() {

        // Set the default query based on the business logic
        String defaultQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                              'Status, SBQQ__RenewalOpportunity__c,SBQQ__RenewalTerm__c, ' +
            				  'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c,SBQQ__RenewalOpportunity__r.StageName, SBQQ__RenewalOpportunity__r.IsClosed, ' +
                              'Deal_Type__c, Is_Migrated_Contract__c, ' + // BIZ-82935: Renewals_Pause__c removed — hold managed at Opportunity level
                              'Consolidated_Quote__c, Consolidated_Quote__r.SBQQ__Opportunity2__r.StageName ' +
                              'FROM Contract ' +
                              'WHERE Subsidiary__c != null AND SBQQ__RenewalQuoted__c = false ' +
                              ' AND Status != \''+ContractConstants.STATUS_CANCELLED_LAPSED+'\'' +
                              ' AND Status != \''+ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT+'\'' +
                              ' AND (SBQQ__RenewalForecast__c = false OR SBQQ__Evergreen__c = false) '+
                              ' AND Deal_Type__c != \''+ContractConstants.DEAL_TYPE_PARTNER_FEE+'\'' +
                              ' AND (Deal_Type__c != \''+ContractConstants.DEAL_TYPE_ADD_ON+'\' OR Is_Migrated_Contract__c = false)' +
                              ' AND (Consolidated_Quote__c = null OR Consolidated_Quote__r.SBQQ__Opportunity2__r.StageName != \''+OpportunityConstants.STAGE_CLOSED_WON+'\')' +
                              ' AND Id IN (SELECT SBQQ__Contract__c FROM SBQQ__Subscription__c)';
        return defaultQuery;
    }
}