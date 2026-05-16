/**
* @description Trigger Handler class for OrderTrigger 
* @author Manisha S
* @jira BIZ-66420
**/
public without sharing class OrderProductTriggerHandler implements TriggerFunctionInterface {
    
    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description : This method will handle before insert event of Order object. 
    * @param lstNewObject 
    **/
    public void beforeInsert(List<SObject> lstNewObject){
    }

    /**
    * @description : This method will handle before update event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle before delete event of Order object.
    * @param lstNewObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after insert event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        OrderProductTriggerHelper.updateSegmentedBundleId(lstNewObject);
    }

    /**
    * @description : This method will handle after update event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
      
    }

    /**
    * @description : This method will handle after delete event of Order object.
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after undelete event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
    }

}