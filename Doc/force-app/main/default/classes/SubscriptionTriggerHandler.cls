/**
* @description       : This class is a handler class for SubscriptionTrigger.
*              	   	   Specifically, it handles updating segmented bundle relationships, filtering and publishing 
*              	   	   eligible subscription records, and integrating with external systems. It also processes 
*              	   	   subscription events based on changes in key fields such as contract number and entitlement ID.
* @author            : Ratan Paul
* @last modified on  : 06-23-2025
* @last modified by  : Sonali Kakade
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   04-30-2025   Ratan Paul        Initial Version via BIZ-68140
* 2.0   06-23-2025   Sonali Kakade     Updated for BIZ-67339 to implement trigger framework and moved the logic to SubscriptionTriggerHelper class
**/
public class SubscriptionTriggerHandler implements TriggerFunctionInterface {

    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description : This method will handle before insert event of Subscription object. 
    * @author Sonali Kakade | 23-06-2025 
    * @param lstNewObject 
    **/
    public void beforeInsert(List<SObject> lstNewObject) {
        SubscriptionTriggerHelper.populateOriginalOpportunityProduct((List<SBQQ__Subscription__c>)lstNewObject);
    }

    /**
    * @description : This method will handle before update event of Subscription object.
    * @author Sonali Kakade | 23-06-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
    * @description : This method will handle before delete event of Subscription object.
    * @author Sonali Kakade | 23-06-2025 
    * @param lstNewObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
    * @description : This method will handle after insert event of Subscription object.
    * @author Sonali Kakade | 23-06-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {
        SubscriptionTriggerHelper.subscriptionAfterInsert((List<SBQQ__Subscription__c>)lstNewObject);
    }

    /**
    * @description : This method will handle after update event of Subscription object.
    * @author Sonali Kakade | 23-06-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
        SubscriptionTriggerHelper.subscriptionAfterUpdate((List<SBQQ__Subscription__c>)lstNewObject, (Map<Id, SBQQ__Subscription__c>)mapOldObject);
    }

    /**
    * @description : This method will handle after delete event of Subscription object.
    * @author Sonali Kakade | 23-06-2025 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
    * @description : This method will handle after undelete event of Subscription object.
    * @author Sonali Kakade | 23-06-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {}
}