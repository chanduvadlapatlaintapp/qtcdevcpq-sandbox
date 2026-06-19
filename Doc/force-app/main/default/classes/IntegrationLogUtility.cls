public class IntegrationLogUtility {
    public static void logIntegration(List<DealEventTriggerHandler.payloadWrapper> lstPayloadWrapper){
        List<Integration_Log__c> lstIntegartionLog = new List<Integration_Log__c>();
        if(!lstPayloadWrapper.isEmpty()){
            for(DealEventTriggerHandler.payloadWrapper oPayload : lstPayloadWrapper){
                lstIntegartionLog.add(new Integration_Log__c(Object_Name__c = oPayload.objectName, Class_Name__c = oPayload.className, Function_Name__c = oPayload.functionName, 
                                                             Functionality__c = oPayload.functionality, Payload__c = oPayload.payload , 
                                                             Quiddity__c = oPayload.quiddity, Payload_RecordId__c = oPayload.recordId, Payload_Created_By__c = oPayload.payloadCreatedBy));
            }
            try{
                insert lstIntegartionLog;
            }catch(Exception e){
                System.debug('Error occurred while inserting Integration Logs: ' + e.getMessage());
            }
        }
    }
}