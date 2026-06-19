/**
* @description       : This class is a handler class for Ghost_Ghost_QuoteLine_Reconciliation__cLine_Rec_Trigger.
* @author            : Ratan Paul
* @last modified on  : 09-09-2025
* @last modified by  : Ratan Paul
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   09-09-2025   Ratan Paul   Initial Version via BIZ-73446
**/
public without sharing class Ghost_QuoteLine_Rec_TriggerHandler implements TriggerFunctionInterface{  
	/***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description : This method will handle before insert event of Ghost_QuoteLine_Reconciliation__c object. 
    * @author Ratan Paul | 09-09-2025
    * @param lstNewObject 
    **/
    public void beforeInsert(List<SObject> lstNewObject){
       
    }

    /**
    * @description : This method will handle before update event of Ghost_QuoteLine_Reconciliation__c object.
    * @author Ratan Paul | 09-09-2025
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        
    }

    /**
    * @description : This method will handle before delete event of Ghost_QuoteLine_Reconciliation__c object.
    * @author Ratan Paul | 09-09-2025
    * @param lstNewObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after insert event of Ghost_QuoteLine_Reconciliation__c object.
    * @author Ratan Paul | 09-09-2025
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        Ghost_QuoteLine_Rec_TriggerHelper.updateOppLines((List<Ghost_QuoteLine_Reconciliation__c>)lstNewObject);
    }

    /**
    * @description : This method will handle after update event of Ghost_QuoteLine_Reconciliation__c object.
    * @author Ratan Paul | 09-09-2025
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
       
    }

    /**
    * @description : This method will handle after delete event of Ghost_QuoteLine_Reconciliation__c object.
    * @author Ratan Paul | 09-09-2025
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after undelete event of Ghost_QuoteLine_Reconciliation__c object.
    * @author Ratan Paul | 09-09-2025
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
    }

}