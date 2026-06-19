/**
* @description       : This class is a handler class for AddressTrigger.
* @author            : Pankaj Kumar
* @last modified on  : 09-11-2023
* @last modified by  : Pankaj Kumar
* Modifications Log
* Ver   Date         Author         Modification
* 1.0   07-07-2023   Pankaj Kumar   Initial Version
**/
public without sharing class AddressTriggerHandler implements TriggerFunctionInterface {

    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    public static Boolean beforeInsertFirstRun = true;
    public static Boolean beforeUpdateFirstRun = true;
    public static Boolean afterInsertFirstRun = true;
    public static Boolean afterUpdateFirstRun = true;


    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description : Handles before insert event of Address__c. 
    *                No business logic previously; kept as no-op to match prior behavior.
    * @param lstNewObject 
    **/    
    public void beforeInsert(List<SObject> lstNewObject){
        if(beforeInsertFirstRun){
            beforeInsertFirstRun = false; 
        }
    }

    /**
    * @description : Handles before update event of Address__c.
    *                Delegates to AddressTriggerHelper.addressStatusInactive(newList, oldMap, false)
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/    
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        if(beforeUpdateFirstRun){
	        AddressTriggerHelper.addressStatusInactive(
	            (List<Address__c>)lstNewObject,
	            (Map<Id, Address__c>)mapOldObject,
	            false
	        );
		    beforeUpdateFirstRun = false;
	    }
    }

    /**
    * @description : Handles before delete event of Address__c.
    *                No logic required; retained as no-op.
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
        // No-op
    }

    /**
    * @description : Handles after insert event of Address__c.
    *                Calls helper methods in the same order as legacy handler.
    * @param lstNewObject 
    * @param mapNewObject 
    **/    
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        if(afterInsertFirstRun){
            afterInsertFirstRun = false;
	        List<Address__c> newAddressList = (List<Address__c>)lstNewObject;
	        AddressTriggerHelper.addressNameUpdate(newAddressList, null, true);
	        AddressTriggerHelper.defaultAddressPopulation(newAddressList, null, true);
	        AddressTriggerHelper.defaultAddressDeselection(newAddressList, null, true);
	    }
    }

    /**
    * @description : Handles after update event of Address__c. 
    *                Fixes original bug (checked wrong first-run flag) and delegates to helpers.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/    
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        if(afterUpdateFirstRun){
            afterUpdateFirstRun = false;
            List<Address__c> newAddressList = (List<Address__c>)lstNewObject;
            Map<Id, Address__c> oldMap = (Map<Id, Address__c>)mapOldObject;

            AddressTriggerHelper.addressNameUpdate(newAddressList, oldMap, false);
            AddressTriggerHelper.defaultAddressPopulation(newAddressList, oldMap, false);
            AddressTriggerHelper.defaultAddressDeselection(newAddressList, oldMap, false);
            AddressTriggerHelper.updateOrders(newAddressList, oldMap);
        }
    }   

    /**
    * @description : Handles after delete event of Address__c.
    *                No logic required; retained as no-op.
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // No-op
    }

    /**
    * @description : Handles after undelete event of Address__c.
    *                No logic required; retained as no-op.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        // No-op
    }

}