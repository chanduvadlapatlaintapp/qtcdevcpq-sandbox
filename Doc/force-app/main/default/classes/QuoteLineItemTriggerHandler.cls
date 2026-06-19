/**
 * @description       : This class is a handler class for QuoteLineTrigger.
 * @author            : Pooja Hemrajani
 **/
public without sharing class QuoteLineItemTriggerHandler implements TriggerFunctionInterface {

    /**
     * @description - This method is invoked before inserting new QuoteLine records.
     *                Calculates ACV Change values directly on trigger records (no DML needed).
     * @param lstNewObject - List of new QuoteLine records being inserted.
     **/
    public void beforeInsert(List<SObject> lstNewObject) {
        // Calculate ACV Change values for new quote lines (before-context - modifies records directly)
        ACVChangeCalculationService.calculateACVChange(
            (List<SBQQ__QuoteLine__c>)lstNewObject,
            null
        );

        // BIZ-81462: Limit One-Time Credit twin-field carry-over to SFDC-sourced amendments only.
        QuoteLineItemTriggerHelper.gateOneTimeCreditForAmendments((List<SBQQ__QuoteLine__c>)lstNewObject);
    }

    /**
     * @description - beforeUpdate method is invoked before updating existing QuoteLine records.
     *                Calculates ACV Change values directly on trigger records (no DML needed).
     * @param lstNewObject - List of new QuoteLine records being updated.
     * @param mapNewObject - Map of new QuoteLine records with Id as key.
     * @param lstOldObject - List of old QuoteLine records before update.
     * @param mapOldObject - Map of old QuoteLine records with Id as key.
     */
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
        // Calculate ACV Change values for updated quote lines (before-context - modifies records directly)
        ACVChangeCalculationService.calculateACVChange(
            (List<SBQQ__QuoteLine__c>)lstNewObject,
            (Map<Id, SBQQ__QuoteLine__c>)mapOldObject
        );
    }

    /**
     * @description - beforeDelete method is invoked before deleting QuoteLine records.
     * @param lstOldObject - List of old QuoteLine records being deleted.
     * @param mapOldObject - Map of old QuoteLine records with Id as key.
     */
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject) {
        // No implementation needed at this time.
    }

    /**
     * @description - afterInsert method is invoked after inserting new QuoteLine records.
     *                Syncs ACV Change values to related OpportunityLineItems.
     * @param lstNewObject - List of new QuoteLine records being inserted.
     * @param mapNewObject - Map of new QuoteLine records with Id as key.
     */
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {
        // Sync ACV Change values to OpportunityLineItems (requires after-context for DML)
        ACVChangeCalculationService.syncOpportunityLineItems(
            (List<SBQQ__QuoteLine__c>)lstNewObject
        );
    }

    /**
     * @description - afterUpdate method is invoked after updating existing QuoteLine records.
     *                Syncs ACV Change values to related OpportunityLineItems.
     * @param lstNewObject - List of new QuoteLine records being updated.
     * @param mapNewObject - Map of new QuoteLine records with Id as key.
     * @param lstOldObject - List of old QuoteLine records before update.
     * @param mapOldObject - Map of old QuoteLine records with Id as key.
     **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
        // Sync ACV Change values to OpportunityLineItems (requires after-context for DML)
        ACVChangeCalculationService.syncOpportunityLineItems(
            (List<SBQQ__QuoteLine__c>)lstNewObject
        );
    }

    /**
     * @description - afterDelete method is invoked after deleting QuoteLine records.
     * @param lstOldObject - List of old QuoteLine records being deleted.
     * @param mapOldObject - Map of old QuoteLine records with Id as key.
     */
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
    }

    /**
     * @description - afterUnDelete method is invoked after restoring deleted QuoteLine records.
     * @param lstNewObject - List of new QuoteLine records being restored.
     * @param mapNewObject - Map of new QuoteLine records with Id as key.
     */
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {
        // No implementation needed at this time.
    }
}