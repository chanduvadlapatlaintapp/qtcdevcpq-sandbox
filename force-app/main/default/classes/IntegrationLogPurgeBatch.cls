global class IntegrationLogPurgeBatch implements Database.Batchable<sObject>, Schedulable{
    
    global Database.QueryLocator start(Database.BatchableContext bc){
        Date sevenDaysAgo = System.today().addDays(-7);
        return Database.getQueryLocator([SELECT Id FROM Integration_Log__c WHERE CreatedDate < :sevenDaysAgo]);
    }
    global void execute(Database.BatchableContext bc, List<Integration_Log__c> lstIntegrationLog) {
        try{
            if(!lstIntegrationLog.isEmpty() && lstIntegrationLog.size()>0){    
                delete lstIntegrationLog;
            }
        }catch(Exception e){
            System.debug('An error occurred while deleting Integration Logs: ' + e.getMessage());
        }
    }
    global void finish(Database.BatchableContext bc) {
        
    }
    global void execute(SchedulableContext sc) {
        // Schedule the batch to run daily at midnight
        String cronLabel = System.Label.DeleteIntegrationLogsCronExpr; // Fire at midnight every day
        System.schedule('IntegrationLogPurgeBatchJob', cronLabel, new IntegrationLogPurgeBatch());
    }
}