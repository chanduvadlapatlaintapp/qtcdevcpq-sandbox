/**
* @description       : This class is a handler class for QuoteTrigger.
* @author            : Pooja Hemrajani
* @last modified on  : 03-20-2025
* @last modified by  : Pooja Hemrajani
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   03-20-2025   Pooja Hemrajani   Initial Version via BIZ-66415
**/
public without sharing class QuoteTriggerHandler implements TriggerFunctionInterface{
    
    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description : This method will handle before insert event of Quote object. 
    * @author Pooja Hemrajani | 25-03-2025 
    * @param lstNewObject 
    **/
    public void beforeInsert(List<SObject> lstNewObject){
        //Commented whole method since whole functionality was commented already commented
        //Processes the records before insert by invoking the processRecordsBeforeInsert method in QuoteTriggerHelper
        //QuoteTriggerHelper.processRecordsBeforeInsert((List<SBQQ__Quote__c>)lstNewObject);
        
        // Handles additional quote processing before the records are inserted, passing null for old records as this is an insert
        QuoteTriggerHelper.handleQuoteProcessing((List<SBQQ__Quote__c>)lstNewObject, null);
        
        // Populates Custom Master Term on the quote
        QuoteTriggerHelper.populateCustomMasterTerm((List<SBQQ__Quote__c>)lstNewObject);
        
        //Set Pause Quote Payload field to true if it is a ghost Quote
        QuoteTriggerHelper.setPauseQuotePayload((List<SBQQ__Quote__c>)lstNewObject);
        
        // Populate subsidiary via BIZ-74967
        SubsidiaryService.updateSubsidiary(Trigger.new, null);
        
        // Calculate YoY Uplift with one-time credits
        QuoteTriggerHelper.calculateYoYUplift((List<SBQQ__Quote__c>)lstNewObject);
    }

    /**
    * @description : This method will handle before update event of Quote object.
    * @author Pooja Hemrajani | 25-03-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // Processes the records before update by comparing old and new values of SBQQ__Quote__c objects
        QuoteTriggerHelper.processRecordsBeforeUpdate((Map<Id, SBQQ__Quote__c>)mapOldObject, (Map<Id, SBQQ__Quote__c>)mapNewObject);
        
        // Handles additional quote processing for the update, comparing the old and new records
        QuoteTriggerHelper.handleQuoteProcessing((List<SBQQ__Quote__c>)lstNewObject, (Map<Id, SBQQ__Quote__c>)mapOldObject);
        
        // Resets approval status on the quote
        QuoteTriggerHelper.resetApprovalStatus((List<SBQQ__Quote__c>)lstNewObject, (Map<Id, SBQQ__Quote__c>)mapOldObject);
        
        // Populates Custom Master Term on the quote
        QuoteTriggerHelper.populateCustomMasterTerm((List<SBQQ__Quote__c>)lstNewObject);
        
        // Populate subsidiary via BIZ-74967
        SubsidiaryService.updateSubsidiary(Trigger.new, (Map<Id, SBQQ__Quote__c>)mapOldObject);
        // Set Opportunity Deal Quality Score
        QuoteTriggerHelper.updateOppDealQualityScore((List<SBQQ__Quote__c>)lstNewObject, (Map<Id, SBQQ__Quote__c>)mapOldObject);
        
        // Calculate YoY Uplift with one-time credits
        QuoteTriggerHelper.calculateYoYUplift((List<SBQQ__Quote__c>)lstNewObject);
    }

    /**
    * @description : This method will handle before delete event of Quote object.
    * @author Pooja Hemrajani | 25-03-2025 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after insert event of Quote object.
    * @author Pooja Hemrajani | 25-03-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        // Publishes eligible records (for integration) after quote records are inserted
        QuoteTriggerHelper.publishEligibleQuotes((List<SBQQ__Quote__c>)lstNewObject, null);
    }

    /**
    * @description : This method will handle after update event of Quote object.
    * @author Pooja Hemrajani | 25-03-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        // Publishes eligible records (for integration) after quote records are updated
        QuoteTriggerHelper.publishEligibleQuotes((List<SBQQ__Quote__c>)lstNewObject, (Map<Id, SBQQ__Quote__c>)mapOldObject);
        
        // Adds quote terms when quotes transition to 'Finalize OSA' or when dynamic fields change
        QuoteTermService.addQuoteTerms((List<SBQQ__Quote__c>)lstNewObject, (Map<Id, SBQQ__Quote__c>)mapOldObject);
        
        // Synchronizes approval records for quotes that have changed during the update
        QuoteTriggerHelper.syncApprovalRecordsForChangedQuotes((List<SBQQ__Quote__c>)lstNewObject, (Map<Id, SBQQ__Quote__c>)mapOldObject);
    }

    /**
    * @description : This method will handle after delete event of Quote object.
    * @author Pooja Hemrajani | 25-03-2025 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after undelete event of Quote object.
    * @author Pooja Hemrajani | 25-03-2025 
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
    }

}