/**
 * @description       : Integration Utility class for SingleQuoteSingleDealController
 * @author            : Snehalkumar Choudhary 
**/
public with sharing class IntegrationUtility {
    public static void publishEligibleSobjectRecords(List<sObject>sObjectList,Map<Id,sObject>sObjectOldMap, String sObjectName) {
        system.debug('In Int Util1' +Userinfo.getUserEmail());
        List<Field_Tracking__mdt> fieldTrackingList = new List<Field_Tracking__mdt>();
        List<Field_Tracking__mdt> lstAllFieldTracking = Field_Tracking__mdt.getAll().values();
        
        for(Field_Tracking__mdt oFieldTracking : lstAllFieldTracking){
            if(oFieldTracking.Object_Name__c.equalsIgnoreCase(sObjectName)){
                fieldTrackingList.add(oFieldTracking);
            }
        }
        
        Schema.SObjectType sObjectType  = ((SObject)Type.forName(sObjectName).newInstance()).getSObjectType();
        List<sObject> sObjectEligibleList = new List<sObject>();
        List<OpportunityLineItem> updateOli = new List <OpportunityLineItem> ();
        for (sObject recordNew : sObjectList) {
            String recordId = (string)recordNew.get('Id');
            sObject recordOld = sObjectOldMap != null && sObjectOldMap.containsKey(recordId)? sObjectOldMap.get(recordId) : sObjectType.newSObject();
            if (isChanged(recordNew,recordOld,fieldTrackingList)) {
                if(sObjectName == 'OpportunityLineItem'){
                    OpportunityLineItem oli = (OpportunityLineItem) recordNew;
                    if(oli.Opportunity_Prod_Updated__c == false){
                 		oli.Opportunity_Prod_Updated__c = true;
                    	updateOli.add(oli);
                    }
                }else{
                  system.debug('In loop Int Util2' +Userinfo.getUserEmail());
                  sObjectEligibleList.add(recordNew);
                }
            }
        }
        if(updateOli.size() > 0){
        	update updateOli;
        }
        
        //check if any record matches the criteria
        if (sObjectEligibleList.size() > 0) {
            //BIZ-65768 Start
            if(sObjectName == 'OpportunityLineItem'){
                publishsObjectRecords(sObjectEligibleList,sObjectName,'Update');
            }else{
            	publishsObjectRecords(sObjectEligibleList,sObjectName);
            }
            //BIZ-65768 End
        }
    }
     
    public static void publishsObjectRecords(List<sObject> lstOfsObjects, String sObjectName){  
        publishsObjectRecords(lstOfsObjects, sObjectName,null);
    }
    
    public static void publishsObjectRecords(List<sObject> lstOfsObjects, String sObjectName,String eventName){ 
        Data_Migration_Settings__c migrationSettings = Data_Migration_Settings__c.getInstance();    
        List<List<sObject>> lstOfsObjectPayLoad = new List<List<sObject>>();
        List<sObject> sObjectUpdateList = new List<sObject>();
        Generic_Key_Value_Setting__mdt configurableMetadata = Generic_Key_Value_Setting__mdt.getInstance('Payload_Max_Size'); 
        Integer payLoadsize = Integer.valueOf(configurableMetadata.Value__c);
        
        for(sObject sObj : lstOfsObjects) {
            if((JSON.serialize(sObjectUpdateList)).length() < payLoadsize){
                system.debug('sObjectUpdateList size check' +(JSON.serialize(sObjectUpdateList)).length());                            
                sObjectUpdateList.add(sObj); 
            } else {
                system.debug('sObjectUpdateList add in List of List'); 
                lstOfsObjectPayLoad.add(sObjectUpdateList);
                sObjectUpdateList = new List<sObject>();
                sObjectUpdateList.add(sObj);
            }    
        }
        
        if(!sObjectUpdateList.isEmpty()) {
            lstOfsObjectPayLoad.add(sObjectUpdateList);
        }
        
        system.debug('lstOfsObjectPayLoad size' + lstOfsObjectPayLoad.size());
        system.debug('instance lstOfsObjectPayLoad' + lstOfsObjectPayLoad);
        
        if(!lstOfsObjectPayLoad.isEmpty()){
            List<DealEvent__e> lstOfDealEvents = new List<DealEvent__e>();
            Map<string, object> payLoad = new Map<string, object>();
            
            for(List<sObject> lstOfsObjectsUpd : lstOfsObjectPayLoad){ 
                payLoad.put('objectName', sObjectName);
                payLoad.put('body', lstOfsObjectsUpd);
                if (string.isNotblank(eventName)) {
                    payLoad.put('event', eventName);
                }
                DealEvent__e dealEvent = new DealEvent__e();
                dealEvent.Object_Name__c = sObjectName;
                dealEvent.Payload__c = JSON.serialize(payLoad);
                system.debug('dealEvent.Payload__c--->' + dealEvent.Payload__c);
                lstOfDealEvents.add(dealEvent);
            }
            if((migrationSettings.Data_Migration_User_Email__c == null && !migrationSettings.Turn_Off_Platform_Events__c) ||
                  (migrationSettings.Data_Migration_User_Email__c != null && Userinfo.getUserEmail() != migrationSettings.Data_Migration_User_Email__c)){           
            List<Database.SaveResult> results = EventBus.publish(lstOfDealEvents);
            }
        }
        
    }

    public static void publishsObjectRecord(sObject objRecord, String sObjectName){
        List<sObject> lstOfsObjects = new List<sObject>();
        lstOfsObjects.add(objRecord);
        publishsObjectRecords(lstOfsObjects, sObjectName);
    }
    
    public static boolean isChanged(Sobject recordNew, Sobject recordOld, List<Field_Tracking__mdt> fieldTrackingList) {
        for (Field_Tracking__mdt fieldTracking : fieldTrackingList) {
            if (recordNew.get(fieldTracking.Field_Api_Name__c) != recordOld.get(fieldTracking.Field_Api_Name__c)){
                return true;
            }
        }
        
        return false;
    }
}