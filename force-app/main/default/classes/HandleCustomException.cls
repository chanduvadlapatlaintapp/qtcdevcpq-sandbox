public class HandleCustomException extends Exception {
    // Log Exception in Error Log object. 
    public static String exceptionType;
    public static String exceptionMessage;
    public static void logException(Exception exceptn){
        try {
            String stackTrace = exceptn.getStackTraceString().substringBefore('\n');
            String className  = stackTrace.substringAfter('.').substringBefore('.'); 
            String methodName = stackTrace.substringBefore(':').substringAfter(className).substringAfter('.');
            
            //Governer Limit of executingQuery 
            String queryLimit = '1. SOQL Queries used / SOQL Queries allowed: ' + Limits.getQueries() + '/' + Limits.getLimitQueries();
            String dmLimit = '2. Number of records queried so far /  Number allowed: ' + Limits.getDmlRows() + '/' + Limits.getLimitDmlRows();
            String dmlStat = '3. Number of DML statements used so far / Number allowed: ' +  Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements();   
            String cpuT = '4. Amount of CPU time (in ms) used so far / CPU usage time (in ms) allowed: ' + Limits.getCpuTime() + '/' + Limits.getLimitCpuTime();
            exceptionType = exceptn.getTypeName();
            exceptionMessage = exceptn.getMessage();
            //Log information in object
            Error_Log__c errLog = new Error_Log__c();
            errLog.Govt_Limit_in_Executing_Code__c = String.format('{0}\n{1}\n{2}\n{3}',new List<string>{queryLimit, dmLimit,dmlStat,cpuT});
            errLog.Exception_Message__c = exceptn.getMessage();
            errLog.Exception_Type__c = exceptn.getTypeName();
            errLog.Line_Number__c = exceptn.getLineNumber();
            errLog.StackTrace__c = exceptn.getStackTraceString();
            errLog.MethodName__c=methodName;
            errLog.ClassName__c=className;
            database.insert(errLog);            
        } finally {
            
        }            
    }
    
    public static void logDatabaseErrors(Database.SaveResult[] errList){
        try {
            List<Error_Log__c> errorLogList = new List<Error_Log__c>();
            for (Database.SaveResult sr : errList){
            if(sr.isSuccess()){
                  // Operation was successful, so get the ID of the record that was processed
                  System.debug('Record Create/Update was Successful' + sr.getId());
            }
            else {
                  // Operation failed, so get all errors                
                  for(Database.Error err : sr.getErrors()) { 
                  Error_Log__c errLog = new Error_Log__c();
                  errLog.Exception_Message__c = err.getMessage();
                  errLog.StackTrace__c = string.valueof(err.getFields());  
                  errorLogList.add(errLog);
                  }
                 }
            }
            
            if(!errorLogList.IsEmpty())
            {
            database.insert(errorLogList);
            }  
        }
        finally {
            
        } 
    }

    public static void logDatabaseDeleteErrors(Database.DeleteResult[] errList, String className, String methodName){
        try {
            List<Error_Log__c> errorLogList = new List<Error_Log__c>();
            for (Database.DeleteResult  sr : errList){
                if(sr.isSuccess()){
                    // Operation was successful, so get the ID of the record that was processed
                    System.debug('Record Create/Update was Successful' + sr.getId());
                }
                else {
                    // Operation failed, so get all errors                
                    for(Database.Error err : sr.getErrors()) { 
                        Error_Log__c errLog = new Error_Log__c();
                        errLog.Exception_Message__c = err.getMessage();
                        errLog.StackTrace__c = string.valueof(err.getFields());  
                        errLog.ClassName__c = className;
                        errLog.MethodName__c = methodName;
                        errorLogList.add(errLog);
                    }
                }
            }
            if(!errorLogList.IsEmpty()) {
                database.insert(errorLogList);
            }  
        } finally {} 
    }
    
    public static void logDatabaseErrorsForEntitlements(Database.SaveResult[] errList,Map<String,sObject> sourceToChildObjectMap){
        try {
            List<Error_Log__c> errorLogList = new List<Error_Log__c>(); 
            List<Contract> contractList = [Select Id,ContractNumber FROM Contract WHERE ID IN: sourceToChildObjectMap.keyset() LIMIT 1];         
            for (Database.SaveResult sr : errList){
                if(sr.isSuccess()){
                    // Operation was successful, so get the ID of the record that was processed
                    System.debug('Record Create/Update was Successful' + sr.getId());
                } else {
                    // Operation failed, so get all errors                
                    for(Database.Error err : sr.getErrors()) {                                        
                        Error_Log__c errLog = new Error_Log__c();
                        errLog.Exception_Message__c = err.getMessage();
                        errLog.StackTrace__c = 'Contract Number :' + (contractList.isEmpty() == false ? contractList[0].ContractNumber : sourceToChildObjectMap.keyset().toString());  
                        errorLogList.add(errLog);
                    }
                }
            }
            
            if(!errorLogList.IsEmpty()){
                database.insert(errorLogList);
            }              
        } catch (Exception pEx) {
            system.debug('exception in Error log--->'+pEx.getMessage());
        }
    }
    
    public static map<string,string> logMigrationDatabaseError(
        Database.SaveResult[] errList,
        Map<String,sObject> sourceToChildObjectMap,
        string keyFields,
        list<sobject> sobjectList
    ){
        map<string,string> resultMap = new map<string,string>();
        try {
            List<Error_Log__c> errorLogList = new List<Error_Log__c>(); 
            List<Contract> contractList = [Select Id,ContractNumber FROM Contract WHERE ID IN: sourceToChildObjectMap.keyset() LIMIT 1];         
            integer index = 0;
            
            for (Database.SaveResult sr : errList){
                if(sr.isSuccess()){
                    // Operation was successful, so get the ID of the record that was processed
                    System.debug('Record Create/Update was Successful' + sr.getId());
                } else {
                    // Operation failed, so get all errors   
                    string errorMessage;             
                    for(Database.Error err : sr.getErrors()) {                                        
                        Error_Log__c errLog = new Error_Log__c();
                        errLog.Exception_Message__c = err.getMessage();
                        errorMessage = errorMessage != null? '\n'+ err.getMessage() : err.getMessage();
                        errLog.StackTrace__c = 'Contract Number :' + (contractList.isEmpty() == false ? contractList[0].ContractNumber : sourceToChildObjectMap.keyset().toString());  
                        errorLogList.add(errLog);
                    }
                    //log error to the specific record
                    if(errorMessage != null && keyFields != null) {
                        string key = getKey(keyFields,sobjectList[index]);
                        resultMap.put(key,errorMessage);
                    }
                }
                index++;
            }
            
            if(!errorLogList.IsEmpty()){
                database.insert(errorLogList);
            }     
                   
        } catch (Exception pEx) {
            system.debug('exception in Error log--->'+pEx.getMessage());
        }
        return resultMap;  
    }

    public static string getKey(string keyFields, Sobject sobjectRecord){
        string key;
        for (string keyField : keyFields.split(',')) {
            string fieldValue = string.valueOf(sobjectRecord.get(keyField));
            key = key != null? key + '-' + fieldValue : fieldValue;
        }
        return key;
    }
}