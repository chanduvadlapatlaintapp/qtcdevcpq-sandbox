/**
* @description       : Handler class for QuoteTermTrigger that implements TriggerFunctionInterface.
*                      This class is registered with the TriggerDispatcher framework and processes all trigger events
*                      (before insert, before update, after insert, after update, before delete, after delete, after undelete)
*                      for the SBQQ__QuoteTerm__c object. The handler delegates business logic to QuoteTermTriggerHelper
*                      for code reusability and maintainability. Currently processes quote terms on before insert and
*                      before update to format body content and identify dynamic fields.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
public class QuoteTermTriggerHandler implements TriggerFunctionInterface{
    
    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description Handles the before insert trigger event for Quote Term records.
    *              Processes new quote terms by removing HTML paragraph tags from the body and
    *              setting the Has_Dynamic_Field__c checkbox based on dynamic field detection.
    * @param lstNewObject List of new SBQQ__QuoteTerm__c records being inserted
    * @example Triggered when a new quote term is created and saved to the database.
    **/
    public void beforeInsert(List<SObject> lstNewObject){
        List<SBQQ__QuoteTerm__c> quoteTerms = (List<SBQQ__QuoteTerm__c>)lstNewObject;
        QuoteTermTriggerHelper.removeParaTags(quoteTerms);
        QuoteTermTriggerHelper.setHasDynamicField(quoteTerms);
    }

    /**
    * @description Handles the before update trigger event for Quote Term records.
    *              Processes updated quote terms by removing HTML paragraph tags from the body and
    *              setting the Has_Dynamic_Field__c checkbox based on dynamic field detection.
    *              This ensures the Has_Dynamic_Field__c field is kept in sync with the body content on every update.
    * @param lstNewObject List of updated SBQQ__QuoteTerm__c records with new field values
    * @param mapNewObject Map<Id, SObject> of updated records keyed by record Id
    * @param lstOldObject List of SBQQ__QuoteTerm__c records with old field values before the update
    * @param mapOldObject Map<Id, SObject> of old records keyed by record Id before the update
    * @example Triggered when an existing quote term is modified and saved to the database.
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        List<SBQQ__QuoteTerm__c> quoteTerms = (List<SBQQ__QuoteTerm__c>)lstNewObject;
        QuoteTermTriggerHelper.removeParaTags(quoteTerms);
        QuoteTermTriggerHelper.setHasDynamicField(quoteTerms);
    }

    /**
    * @description Handles the before delete trigger event for Quote Term records.
    *              Currently no business logic is implemented for delete operations.
    * @param lstOldObject List of SBQQ__QuoteTerm__c records that will be deleted
    * @param mapOldObject Map<Id, SObject> of records that will be deleted, keyed by record Id
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
        // No action required for before delete
    }

    /**
    * @description Handles the after insert trigger event for Quote Term records.
    *              Currently no business logic is implemented for after insert operations.
    * @param lstNewObject List of newly inserted SBQQ__QuoteTerm__c records
    * @param mapNewObject Map<Id, SObject> of newly inserted records keyed by record Id
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        // No action required for after insert
    }

    /**
    * @description Handles the after update trigger event for Quote Term records.
    *              Currently no business logic is implemented for after update operations.
    * @param lstNewObject List of updated SBQQ__QuoteTerm__c records with new field values
    * @param mapNewObject Map<Id, SObject> of updated records keyed by record Id
    * @param lstOldObject List of SBQQ__QuoteTerm__c records with old field values before the update
    * @param mapOldObject Map<Id, SObject> of old records keyed by record Id before the update
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // No action required for after update
    }

    /**
    * @description Handles the after delete trigger event for Quote Term records.
    *              Currently no business logic is implemented for after delete operations.
    * @param lstOldObject List of deleted SBQQ__QuoteTerm__c records
    * @param mapOldObject Map<Id, SObject> of deleted records keyed by record Id
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // No action required for after delete
    }

    /**
    * @description Handles the after undelete trigger event for Quote Term records.
    *              Currently no business logic is implemented for after undelete operations.
    * @param lstNewObject List of undeleted SBQQ__QuoteTerm__c records
    * @param mapNewObject Map<Id, SObject> of undeleted records keyed by record Id
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        // No action required for after undelete
    }

}