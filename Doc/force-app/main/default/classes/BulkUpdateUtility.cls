/**
* @description Utility class for performing bulk operations
* @jira BIZ-68197
**/
public with sharing class BulkUpdateUtility implements Database.Batchable<sObject>, Database.Stateful {
    
    /***********************************************************************************************
    *
    * Props
    *
    ***********************************************************************************************/

    private String query;
    private static Integer defaultBatchSize = 200; // default batch size
    private Map<String,Object> fieldsToUpdate { get; set; } // field api name to data

    private DateTime startTime = System.now(); // capture the start time of the job
    private Integer numberOfErrors = 0; // stores the number of total errors
    private String firstError; // stores the first error message the batch hits

    /***********************************************************************************************
    *
    * Constructor
    *
    ***********************************************************************************************/
    /**
    * @description parameterized constructor to pass the query
    * @param query
    **/
    public BulkUpdateUtility (String query) {
        this.query = query;
    }

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
    * @description Runs the query passed in by the user/class (no validation is performed on the query string)
    * @param query
    **/
    public static void runUpdate (String query) {

        if (query == null) { return; }

        BulkUpdateUtility.runUpdate( query, null, defaultBatchSize );
    }

    /**
    * @description Runs the query passed in by the user/class and updates the fields in the map with the given value
    * @param query
    * @param fieldsToUpdate
    **/
    public static void runUpdate (String query, Map<String,Object> fieldsToUpdate) {

        if (query == null || fieldsToUpdate == null) { return; }
        BulkUpdateUtility.runUpdate( query, fieldsToUpdate, defaultBatchSize );
    }

    /**
    * @description Runs the query passed in by the user/class, updates the fields in the map and adjusts batch size
    * @param query
    * @param fieldsToUpdate
    * @param batchSize
    **/
    public static void runUpdate (String query, Map<String,Object> fieldsToUpdate, Integer batchSize) {

        if (query == null || batchSize == null) { return; }

        BulkUpdateUtility theBatch = new BulkUpdateUtility(query);
        theBatch.fieldsToUpdate = fieldsToUpdate; //doesnt matter if this is null
        
        Database.executeBatch( theBatch,  batchSize ); //run this bad boy
    }

    /***********************************************************************************************
    *
    * Batch Methods
    *
    ***********************************************************************************************/
    /**
    * @description batch start method
    * @param bc
    * @return Database.QueryLocator
    **/
    public Database.QueryLocator start (Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }

    /***********************************************************************************************
    *
    * NOTE : Depending on the query, we may hit governor limits and/or other errors since we 
    * we trust the user to provide the proper data for execution.  If there are any errors
    * updating the actual records, they will be logged in the System Message object.
    *
    ***********************************************************************************************/
    /**
    * @description batch execute method
    * @param bc
    * @param records    
    **/
    public void execute (Database.BatchableContext bc, List<sObject> records) {

        // check to see if the user gave us a field => value mapping
        if (this.fieldsToUpdate != null) {

            for (sObject record : records) {

                // use the map to populate all the fields with the provided values
                for (String field : this.fieldsToUpdate.keySet()) {

                    record.put( field, this.fieldsToUpdate.get(field) );
                }
            }
        }

        // run updates for ALL records && check the results
        List<Database.SaveResult> results = Database.update( records, false );
        this.handleResults(records, results);
    }
    
    /**
    * @description batch finish method
    * @param bc
    **/
    public void finish (Database.BatchableContext bc) {

        if (this.numberOfErrors > 0) {

            System.debug('The BulkUpdateUtility failed to Update '+ this.numberOfErrors +' record(s).');
            System.debug('First error : ' + this.firstError);
        }
    }	

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /**
    * @description this handles the results of the data update and logs error records
    * @param records
    * @param results
    **/
    private void handleResults (List<sObject> records, List<Database.SaveResult> results) {

        List<Error_Log__c> errors = new List<Error_Log__c>();

        String objectName = records.size() > 0 ? 
            records[0].Id.getSObjectType().getDescribe().getName() : null;

        // check for any errors and log them
        for (Integer i = 0; i < records.size(); i++) {

            SObject record = records[i];
            Database.SaveResult saveResult = results[i];

            if (!saveResult.isSuccess()) {

                this.numberOfErrors++; // counts the number of errors 

                String errMessage = saveResult.getErrors()[0].getMessage();

                Error_Log__c error = new Error_Log__c(
                    Process__c = 'BulkUpdateUtility @ ' + startTime,
                    Sobject_Id__c = record.Id,
                    Sobject_Name__c = objectName,
                    Exception_Message__c = errMessage
                );

                errors.add(error);

                // just save the first error so that we dont explode
                if (this.firstError == null) {

                    this.firstError = 'First error : ' + errMessage;
                }
            }
        }

        // log the errors
        if (errors.size() > 0) {

            insert errors;
        }
    }

    /***********************************************************************************************
    *
    * EXAMPLE: Map is a String to Object so that any data type can be passed in
    *
    ***********************************************************************************************/

    //Map<String, Object> fieldMap = new Map<String, Object>{
    //	'Title' => 'New Title 5',
    //	'HasOptedOutOfEmail' => true
    //};

    //BulkUpdateUtility.runUpdate('Select Id From Contact Limit 10', fieldMap, 50);

}