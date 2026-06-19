/**
* @description       : Handler class for TermQuotesTrigger that implements TriggerFunctionInterface.
*                      This class is registered with the TriggerDispatcher framework and processes all trigger events
*                      (before insert, before update, after insert, after update, before delete, after delete, after undelete)
*                      for the Term_Quote__c object. The handler delegates business logic to TermQuoteTriggerHelper
*                      for code reusability and maintainability. Currently processes term quotes on before insert and
*                      before update to format body content and set the Has_Dynamic_Field__c checkbox based on the parent Quote Term.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
public class TermQuoteTriggerHandler implements TriggerFunctionInterface{
    
    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description Handles the before insert trigger event for Term Quote records.
    *              Processes new term quotes by removing HTML paragraph tags from the body and
    *              setting the Has_Dynamic_Field__c checkbox based on the parent Quote Term's value.
    * @param lstNewObject List of new Term_Quote__c records being inserted
    **/
    public void beforeInsert(List<SObject> lstNewObject){
        List<Term_Quote__c> termQuotes = (List<Term_Quote__c>)lstNewObject;
        TermQuoteTriggerHelper.removeParaTags(termQuotes);
        TermQuoteTriggerHelper.setHasDynamicFieldFromParent(termQuotes);
    }

    /**
    * @description Handles the before update trigger event for Term Quote records.
    *              Processes updated term quotes by removing HTML paragraph tags from the body,
    *              setting the Has_Dynamic_Field__c checkbox based on the parent Quote Term's value,
    *              and setting Modified__c flag when users manually edit the body.
    * @param lstNewObject List of updated Term_Quote__c records
    * @param mapNewObject Map of new Term_Quote__c records
    * @param lstOldObject List of old Term_Quote__c records
    * @param mapOldObject Map of old Term_Quote__c records
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        List<Term_Quote__c> termQuotes = (List<Term_Quote__c>)lstNewObject;
        Map<Id, Term_Quote__c> oldTermQuotesMap = (Map<Id, Term_Quote__c>)mapOldObject;
        
        TermQuoteTriggerHelper.removeParaTags(termQuotes);
        TermQuoteTriggerHelper.setHasDynamicFieldFromParent(termQuotes);
        TermQuoteTriggerHelper.setModifiedFlagForManualEdits(termQuotes, oldTermQuotesMap);
    }

    /**
    * @description Handles the before delete trigger event for Term Quote object.
    * @param lstOldObject List of Term_Quote__c records to be deleted
    * @param mapOldObject Map of old Term_Quote__c records
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
        // No action required for before delete
    }

    /**
    * @description Handles the after insert trigger event for Term Quote object.
    * @param lstNewObject List of new Term_Quote__c records
    * @param mapNewObject Map of new Term_Quote__c records
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        // No action required for after insert
    }

    /**
    * @description Handles the after update trigger event for Term Quote object.
    * @param lstNewObject List of updated Term_Quote__c records
    * @param mapNewObject Map of new Term_Quote__c records
    * @param lstOldObject List of old Term_Quote__c records
    * @param mapOldObject Map of old Term_Quote__c records
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // No action required for after update
    }

    /**
    * @description Handles the after delete trigger event for Term Quote object.
    * @param lstOldObject List of deleted Term_Quote__c records
    * @param mapOldObject Map of old Term_Quote__c records
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // No action required for after delete
    }

    /**
    * @description Handles the after undelete trigger event for Term Quote object.
    * @param lstNewObject List of undeleted Term_Quote__c records
    * @param mapNewObject Map of undeleted Term_Quote__c records
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        // No action required for after undelete
    }
}