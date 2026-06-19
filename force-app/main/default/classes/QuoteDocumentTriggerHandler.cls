/**
* @description This class is a handler class for QuoteDocumentTrigger.
**/
public class QuoteDocumentTriggerHandler implements TriggerFunctionInterface {
    
    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description This method will handle before insert event of Quote Document object.   
    * @param lstNewObject 
    **/
    public void beforeInsert(List<SObject> lstNewObject) {
        QuoteDocumentTriggerHelper.validateQuoteDocumentNameLength((List<SBQQ__QuoteDocument__c>)lstNewObject); //BIZ-67071
    }

    /**
    * @description This method will handle before update event of Quote Document object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
    * @description This method will handle before delete event of Quote Document object. 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
    * @description This method will handle after insert event of Quote Document object. 
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {}

    /**
    * @description This method will handle after update event of Quote Document object. 
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
        QuoteDocumentTriggerHelper.publishApprovedOSA((List<SBQQ__QuoteDocument__c>)lstNewObject, (Map<Id, SBQQ__QuoteDocument__c>)mapOldObject);
    }

    /**
    * @description This method will handle after delete event of Quote Document object.
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
    * @description This method will handle after undelete event of Quote Document object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {}
 }