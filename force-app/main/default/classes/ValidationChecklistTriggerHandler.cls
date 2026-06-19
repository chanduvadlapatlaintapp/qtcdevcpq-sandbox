/**
 * @description Trigger handler for Validation_Checklist__c. Implements TriggerFunctionInterface
 *              and wires afterInsert / afterUpdate into the FieldHistory tracking framework
 *              so all audit checkbox changes — including the initial record creation — are
 *              captured in Field_History__c with the acting user and timestamp.
 * @author      Ratan Paul
 * @date        2026-05-19
 * @jira        BIZ-74558
 * @see         ValidationChecklistTriggerHelper
 * @see         FieldHistoryHandler
 */
public with sharing class ValidationChecklistTriggerHandler implements TriggerFunctionInterface {

    /***************************************************************************************
    *
    * Trigger Handler Methods — Before Context
    *
    ***************************************************************************************/

    /**
     * @description Before insert — no logic required for history tracking.
     * @param lstNewObject Trigger.new
     */
    public void beforeInsert(List<SObject> lstNewObject) {}

    /**
     * @description Before update — no logic required for history tracking.
     * @param lstNewObject Trigger.new
     * @param mapNewObject Trigger.newMap
     * @param lstOldObject Trigger.old
     * @param mapOldObject Trigger.oldMap
     */
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject,
                             List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
     * @description Before delete — no logic required for history tracking.
     * @param lstOldObject Trigger.old
     * @param mapOldObject Trigger.oldMap
     */
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject) {}

    /***************************************************************************************
    *
    * Trigger Handler Methods — After Context
    *
    ***************************************************************************************/

    /**
     * @description After insert — captures the initial state of all tracked audit checkboxes.
     *              Addresses the gap where standard Salesforce field history misses the very
     *              first value set on record creation.
     * @param lstNewObject Trigger.new
     * @param mapNewObject Trigger.newMap
     */
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {
        ValidationChecklistTriggerHelper.trackInsertHistory(lstNewObject);
    }

    /**
     * @description After update — captures checkbox changes including system reversions
     *              (true → false) so the cause of blank audit fields can be determined.
     * @param lstNewObject Trigger.new
     * @param mapNewObject Trigger.newMap
     * @param lstOldObject Trigger.old
     * @param mapOldObject Trigger.oldMap
     */
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject,
                            List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
        ValidationChecklistTriggerHelper.trackUpdateHistory(lstNewObject, mapOldObject);
    }

    /**
     * @description After delete — no logic required for history tracking.
     * @param lstOldObject Trigger.old
     * @param mapOldObject Trigger.oldMap
     */
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
     * @description After undelete — no logic required for history tracking.
     * @param lstNewObject Trigger.new
     * @param mapNewObject Trigger.newMap
     */
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {}
}