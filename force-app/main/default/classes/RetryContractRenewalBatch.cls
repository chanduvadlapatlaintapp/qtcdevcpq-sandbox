/**
 * @author : Ratan Paul
 * @date : 04/02/2025
 * @description : Processes failed contract renewal jobs and updates contract statuses.
*                     Deletes quotes without line items and unchecks related checkboxes.
 * @jira : BIZ-68101
 **/
public class RetryContractRenewalBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable  {

    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    private String query;
    private Integer scopeSize;

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Default Constructor
    **/
    public RetryContractRenewalBatch() {
        this.query = getDefaultQuery();
        this.scopeSize = 1;
    }
    /**
    * @description parameterized Constructor
    * @param query
    * @param scopeSize
    **/
    public RetryContractRenewalBatch(String query, Integer scopeSize) {
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
        RetryContractRenewalBatch obj = new RetryContractRenewalBatch(query, scopeSize);
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
    **/
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query Quotes that need to be processed
        String query = this.query;
        return Database.getQueryLocator(query);
    }

    /**
    * @description execute method
    * @param bc
    * @param scope
    **/
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<SBQQ__RecordJob__c> jobRecords = (List<SBQQ__RecordJob__c>)scope;
        Set<Id> contractIds = new Set<Id>();
        Map<Id, String> contractJobDetails = new Map<Id, String>();

        // Extract contract IDs and store job details
        for (SBQQ__RecordJob__c job : jobRecords) {
            String contractId = job.SBQQ__RecordId__c?.replace('::RenewContract', '')?.trim();
            contractIds.add(contractId);
            contractJobDetails.put(contractId, job.SBQQ__JobDetails__c);
        }

        // Query contracts and their related renewal opportunities and quotes
        List<Contract> contractsToUpdate = getContracts(contractIds);

        List<SBQQ__Quote__c> quotesToDelete = new List<SBQQ__Quote__c>();
        List<Contract> contractsToModify = new List<Contract>();

        // Process each contract and determine necessary updates
        for (Contract con : contractsToUpdate) {

            Boolean isUpdated = false;

            // If the renewal quote exists but has no line items, delete it and uncheck Renewal Quoted
            if (con.SBQQ__RenewalOpportunities__r.size() > 0 &&  con.SBQQ__RenewalOpportunities__r[0].SBQQ__Quotes2__r.size() > 0 && 
                con.SBQQ__RenewalOpportunities__r[0].SBQQ__Quotes2__r[0].SBQQ__LineItems__r.size() == 0 ) {
                quotesToDelete.addAll(con.SBQQ__RenewalOpportunities__r[0].SBQQ__Quotes2__r);
                con.SBQQ__RenewalQuoted__c = false;
                isUpdated = true;
            }

            // If there is no renewal quote but Renewal Quoted is checked, uncheck it
            if (con.SBQQ__RenewalOpportunities__r.size() > 0 &&  con.SBQQ__RenewalOpportunities__r[0].SBQQ__Quotes2__r.size() == 0 
                && con.SBQQ__RenewalQuoted__c == true ) {
                con.SBQQ__RenewalQuoted__c = false;
                isUpdated = true;
            }

            // If there is no renewal opportunity but Renewal Forecast is checked, uncheck it
            if (con.SBQQ__RenewalOpportunities__r.size() == 0 && con.SBQQ__RenewalForecast__c == true) {
                con.SBQQ__RenewalForecast__c = false;
                isUpdated = true;
            }

            if(isUpdated){
                con.Contract_Renewal_Job_Status__c = contractJobDetails.get(con.Id);
                contractsToModify.add(con);
            }
        }

        // Delete renewal quotes if necessary
        List<Database.DeleteResult> results = Database.delete(quotesToDelete, false);
        ResultHandler.logErrors('RetryContractRenewalBatch Delete Quotes', quotesToDelete, results);
        
        // Update modified contracts
        List<Database.SaveResult> saveResults = Database.update(contractsToModify, false);
        ResultHandler.logErrors('RetryContractRenewalBatch Update Contracts', contractsToModify, saveResults);
    }

    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {
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
        // Instantiate the batch class
        RetryContractRenewalBatch batch = new RetryContractRenewalBatch();
        
        // Execute the batch job with a batch size of 1
        Database.executeBatch(batch, 1);  // Adjust batch size if necessary
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /**
    * @description set the default query
    * @return String
    **/
    private String getDefaultQuery() {

        // Set the default query based on the business logic
        String defaultQuery = 'SELECT Id, SBQQ__RecordId__c, SBQQ__JobDetails__c FROM SBQQ__RecordJob__c ' +
               'WHERE SBQQ__JobStatus__c = \'Failed\' ' +
               'AND SBQQ__RecordId__c LIKE \'%RenewContract%\'';
        return defaultQuery;
    }

    /***********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
    * @description getter method for contracts
    * @param contractIds
    * @return List<Contract>
    **/
    private List<Contract> getContracts(Set<Id> contractIds) {
        return [SELECT Id, SBQQ__RenewalQuoted__c, SBQQ__RenewalOpportunity__c, SBQQ__RenewalForecast__c, 
                    (SELECT Id, 
                        (SELECT Id, 
                            (SELECT Id from SBQQ__LineItems__r LIMIT 1) 
                        FROM SBQQ__Quotes2__r LIMIT 1) 
                    FROM SBQQ__RenewalOpportunities__r LIMIT 1) 
                FROM Contract WHERE Id IN :contractIds];
    }
}