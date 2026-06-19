public class DealEventTriggerHandler {
    public class PayloadWrapper{
        public string objectName;
        public string quiddity;
        public string className;
        public string functionName;
        public string functionality;
        public string payload;
        public string recordId;
        public Id payloadCreatedBy;
        
        public payloadWrapper(string sObjectName, string sQuiddity, string sClassName,
                              string sFunctionName, string sFunctionality, string sPayload, string sRecordId, Id spayloadCreatedBy){
                                  this.objectName = sObjectName;
                                  this.quiddity = sQuiddity;
                                  this.className = sClassName;
                                  this.functionName = sFunctionName;
                                  this.functionality = sFunctionality;
                                  this.payload = sPayload;
                                  this.recordId = sRecordId;
                                  this.payloadCreatedBy = spayloadCreatedBy;
                              }
    }
    public static void processEventForLogging(List<DealEvent__e> eventList){
        List<payloadWrapper> lstpayloadWrapper = new List<payloadWrapper>();
        List<String> lstids = new List<String>();
        String id;
        String createdById;
        if(!eventList.isEmpty()){
            String quiddity = String.valueOf(Request.getCurrent().getQuiddity());
            for(DealEvent__e oEvent : eventList){
                Map<String, Object> payloadMap = (Map<String, Object>)JSON.deserializeUntyped(oEvent.Payload__c);
                List<Object> body = (List<Object>)payloadMap.get('body');
                if (!body.isEmpty() && body.size()>0) {
                    Map<String, Object> bodyMap = (Map<String, Object>)body[0];
                    createdById = (String)bodyMap.get('CreatedById');
                }
                String functionality = oEvent.Object_Name__c+' Sync';
                Integer startIndex = oEvent.Payload__c.indexOf('/sobjects/');
                if (startIndex != -1) {
                    startIndex += '/sobjects/'.length(); // Move the index to the end of '/sobjects/'
                    Integer endIndex = oEvent.Payload__c.indexOf('"', startIndex); // Finding the end of the URL
                    if (endIndex != -1) {
                        String url = oEvent.Payload__c.substring(startIndex, endIndex);
                        // Splitting the URL by '/' and getting the last element as the ID
                        String[] urlParts = url.split('/');
                        lstids.add(urlParts[urlParts.size() - 1]);
                    }
                }       
                id = lstids.size()>1 ?'Multiple Records' : lstids[0];
                
                lstpayloadWrapper.add(new payloadWrapper(oEvent.Object_Name__c, quiddity, DealEventTriggerHandler.class.getName(),
                                                         'processEventForLogging', functionality, oEvent.Payload__c, id, createdById));
            }
            if(!lstpayloadWrapper.isEmpty() && lstpayloadWrapper.size()>0){
                IntegrationLogUtility.logIntegration(lstpayloadWrapper);
            }
        }
        system.debug('List lstpayloadWrapper - '+lstpayloadWrapper);
    }
}