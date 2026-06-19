/**
* @description       : This class is a handler class for ItemMasterProductTrigger.
**/
public without sharing class ItemMasterProductTriggerHandler implements TriggerFunctionInterface {
    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description : This method will handle before insert event of Item Master Product object. 
    * @param lstNewObject 
    **/
    public static void beforeInsert(List<SObject> lstNewObject){
        // Handles additional Item Master Product processing before the records are inserted, passing null for old records as this is an insert
        ItemMasterProductTriggerHelper.validateItemMasterName((List<Item_Master_Product__c>)lstNewObject, null);
    }

    /**
    * @description : This method will handle before update event of Item Master Product object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public static void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // Handles additional quote processing for the update, comparing the old and new records
        ItemMasterProductTriggerHelper.validateItemMasterName((List<Item_Master_Product__c>)lstNewObject, (Map<Id, Item_Master_Product__c>)mapOldObject);
    }

    /**
    * @description : This method will handle before delete event of Item Master Product object.
    * @param lstNewObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
    }
    
    /**
    * @description : This method will handle after insert event of Item Master Product object. 
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public static void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        // Handles additional Item Master Product processing after the records are inserted
        ItemMasterProductTriggerHelper.publishItemMasterProductsAfterInsert((List<Item_Master_Product__c>)lstNewObject);
    }

    /**
    * @description : This method will handle after update event of Item Master Product object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public static void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // Handles additional quote processing for the update, comparing the old and new records
        ItemMasterProductTriggerHelper.publishItemMasterProductsAfterUpdate((List<Item_Master_Product__c>)lstNewObject, (Map<Id, Item_Master_Product__c>)mapOldObject);
    }

    /**
    * @description : This method will handle after delete event of Item Master Product object.
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstNewObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after undelete event of Item Master Product object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
    }
}