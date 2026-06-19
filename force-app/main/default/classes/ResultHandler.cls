/**
 * @author : Sahal Mohamed
 * @date : 02/10/2025
 * @description : a generic class for handling error logging
**/

public without sharing class ResultHandler {
  
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description : takes save results and a list and logs any records that were not sucessfully updated
    * @param processName - name of the process
    * @param records - records need to be processed
    * @param results
    * @return Set<Id> - returns a set of ids of records that failed
    */
    public static Set<Id> logErrors (
        String processName,
        List<sObject> records, 
        List<Database.SaveResult> results) {

        List<Error_Log__c> errors = new List<Error_Log__c>();
        Set<Id> failedRecordIds = new Set<Id>();

        String objectName = records.size() > 0 ? 
            records[0].Id?.getSObjectType().getDescribe().getName() : null;

        // check for any errors and log them
        for (Integer i = 0; i < records.size(); i++) {

            SObject record = records[i];
            Database.SaveResult saveResult = results[i];

            if (!saveResult.isSuccess()) {

                String errMessage = saveResult.getErrors()[0].getMessage();

                Error_Log__c error = new Error_Log__c(
                    Process__c = processName,
                    Sobject_Id__c = record.Id,
                    Sobject_Name__c = objectName,
                    Exception_Message__c = errMessage
                );

                failedRecordIds.add(record.Id);
                errors.add(error);
            }
        }

        // log the errors
        if (errors.size() > 0) {

            insert errors;
        }

        return failedRecordIds;
    }

    /**
    * @description : takes save results and a list and logs any records that were not sucessfully inserted
    * @param processName - name of the process
    * @param records - records need to be processed
    * @param results
    * @return boolean - returns a boolean noting whether errors were present or not
    */
    public static boolean logErrorsAtFuture (
        String processName,
        List<sObject> records, 
        List<Database.SaveResult> results) {

        Map<Id, String> errors = new Map<Id, String>();

        String objectName = records.size() > 0 ? 
            records[0].Id?.getSObjectType().getDescribe().getName() : null;

        // check for any errors and log them
        for (Integer i = 0; i < records.size(); i++) {

            SObject record = records[i];
            Database.SaveResult saveResult = results[i];

            if (!saveResult.isSuccess()) {

                String errMessage = saveResult.getErrors()[0].getMessage();
                errors.put(record.Id, errMessage);

            }
        }

        // log the errors
        if (errors.size() > 0) {

            logErrorsAtFuture(processName, errors, objectName);
        }

        return (errors.size() > 0);
    }

    /**
    * @description : takes save results and a list and logs any records that were not sucessfully updated
    * @param processName - name of the process
    * @param records - records need to be processed
    * @param results
    * @return boolean - returns a boolean noting whether errors were present or not
    */
    public static boolean logErrors (
        String processName,
        List<sObject> records, 
        List<Database.UpsertResult> results) {

        List<Error_Log__c> errors = new List<Error_Log__c>();

        String objectName = records.size() > 0 ? 
            records[0].Id?.getSObjectType().getDescribe().getName() : null;

        // check for any errors and log them
        for (Integer i = 0; i < records.size(); i++) {

            SObject record = records[i];
            Database.UpsertResult saveResult = results[i];

            if (!saveResult.isSuccess()) {

                String errMessage = saveResult.getErrors()[0].getMessage();

                Error_Log__c error = new Error_Log__c(
                    Process__c = processName,
                    Sobject_Id__c = record.Id,
                    Sobject_Name__c = objectName,
                    Exception_Message__c = errMessage
                );

                errors.add(error);
            }
        }

        // log the errors
        if (errors.size() > 0) {

            insert errors;
        }

        return (errors.size() > 0);
    }
    
    /**
    * @description : takes save results and a list and logs any records that were not sucessfully updated
    * @param processName - name of the process
    * @param records - records need to be processed
    * @param results
    * @return boolean - returns a boolean noting whether errors were present or not
    */
    public static boolean logErrorsAtFuture (
        String processName,
        List<sObject> records, 
        List<Database.UpsertResult> results) {

        Map<Id, String> errors = new Map<Id, String>();

        String objectName = records.size() > 0 ? 
            records[0].Id?.getSObjectType().getDescribe().getName() : null;

        // check for any errors and log them
        for (Integer i = 0; i < records.size(); i++) {

            SObject record = records[i];
            Database.UpsertResult saveResult = results[i];

            if (!saveResult.isSuccess()) {

                String errMessage = saveResult.getErrors()[0].getMessage();
                errors.put(record.Id, errMessage);

            }
        }

        // log the errors
        if (errors.size() > 0) {

            logErrorsAtFuture(processName, errors, objectName);
        }

        return (errors.size() > 0);
    }

    /**
    * @description Insert errors into error log if any while sending emails.
      * @param processName - name of the process
      * @param results
      * @return boolean - returns a boolean noting whether errors were present or not
      */
      public static boolean logErrors(String processName, List<Messaging.sendEmailResult> results) {
          
        List<Error_Log__c> errors = new List<Error_Log__c>();
        for ( Messaging.sendEmailResult result : results ) {
            if ( !result.isSuccess () ) {
                
                String errMessage = result.getErrors ()[0].getMessage();
                Error_Log__c error = new Error_Log__c(
                    Process__c = processName,
                    Sobject_Name__c = 'Messaging.SendEmailResult',
                    Exception_Message__c = errMessage
                );

                errors.add(error);
            }
        }

        // log the errors
        if (errors.size() > 0) {

            insert errors;
        }

        return (errors.size() > 0);  
    }
  
    /**
    * @description : takes save results and a list and logs any records that were not sucessfully deleted
    * @param processName - name of the process
    * @param records - records need to be processed
    * @param results
    * @return boolean - returns a boolean noting whether errors were present or not
    */
    public static boolean logErrors (
        String processName,
        List<sObject> records, 
        List<Database.DeleteResult> results) {

        List<Error_Log__c> errors = new List<Error_Log__c>();

        String objectName = records.size() > 0 ? 
            records[0].Id.getSObjectType().getDescribe().getName() : null;

        // check for any errors and log them
        for (Integer i = 0; i < records.size(); i++) {

            SObject record = records[i];
            Database.DeleteResult saveResult = results[i];

            if (!saveResult.isSuccess()) {

                String errMessage = saveResult.getErrors()[0].getMessage();

                Error_Log__c error = new Error_Log__c(
                    Process__c = processName,
                    Sobject_Id__c = record.Id,
                    Sobject_Name__c = objectName,
                    Exception_Message__c = errMessage
                );

                errors.add(error);
            }
        }

        // log the errors
        if (errors.size() > 0) {

            insert errors;
        }

        return (errors.size() > 0);
    }    

    /**
    * @description : takes save results and a list and logs any records that were not sucessfully deleted
    * @param processName - name of the process
    * @param records - records need to be processed
    * @param results
    * @return boolean - returns a boolean noting whether errors were present or not
    */
    public static boolean logErrorsAtFuture (
        String processName,
        List<sObject> records, 
        List<Database.DeleteResult> results) {

        Map<Id, String> errors = new Map<Id, String>();

        String objectName = records.size() > 0 ? 
            records[0].Id?.getSObjectType().getDescribe().getName() : null;

        // check for any errors and log them
        for (Integer i = 0; i < records.size(); i++) {

            SObject record = records[i];
            Database.DeleteResult saveResult = results[i];

            if (!saveResult.isSuccess()) {

                String errMessage = saveResult.getErrors()[0].getMessage();
                errors.put(record.Id, errMessage);

            }
        }

        // log the errors
        if (errors.size() > 0) {

            logErrorsAtFuture(processName, errors, objectName);
        }

        return (errors.size() > 0);
    }
    
    /**
    * @description : logs error in a future transaction- used for error logging of Aura enabled Methods
    * @param processName - name of the process
    * @param errorMessage - Error Message
    */
    @future
    public static void logErrorsAtFuture(String processName, String errorMessage) {
        List<Error_Log__c> errorsToLog = new List<Error_Log__c>();
            Error_Log__c error = new Error_Log__c(
                Process__c = processName,
                Exception_Message__c = errorMessage
            );
        insert error;
    }


    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/    

    /**
    * @description : logs error in a future transaction- used for error logging of setup objects
    * @param processName - name of the process
    * @param errors - map with record id as key and error as value
    * @param objectName
    */
    @future
    private static void logErrorsAtFuture(String processName, Map<Id, String> errors, String objectName) {
        List<Error_Log__c> errorsToLog = new List<Error_Log__c>();
        for(Id recordId : errors.keySet()) {
            Error_Log__c error = new Error_Log__c(
                Process__c = processName,
                Sobject_Id__c = recordId,
                Sobject_Name__c = objectName,
                Exception_Message__c = errors.get(recordId)
            );
            errorsToLog.add(error);
        }
        insert errorsToLog;
    }

}