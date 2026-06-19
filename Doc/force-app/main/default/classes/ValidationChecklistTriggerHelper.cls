/**
 * @description Helper for Validation_Checklist__c trigger — delegates audit checkbox change
 *              tracking to the FieldHistory framework (BIZ-78152). Captures both the initial
 *              checkbox state on record creation and all subsequent changes.
 * @author      Ratan Paul
 * @date        2026-05-19
 * @jira        BIZ-74558
 */
public with sharing class ValidationChecklistTriggerHelper {

    /***************************************************************************************
    *
    * Private Constants
    *
    ***************************************************************************************/

    private static final String OBJECT_API_NAME = 'Validation_Checklist__c';

    /***************************************************************************************
    *
    * Public Methods
    *
    ***************************************************************************************/

    /**
     * @description Captures initial checkbox values when a Validation Checklist record is
     *              first created. Addresses the standard Salesforce history gap where the
     *              very first check of an audit field is not recorded.
     * @param newRecords List of newly inserted Validation_Checklist__c records (Trigger.new)
     */
    public static void trackInsertHistory(List<SObject> newRecords) {
        FieldHistoryHandler.trackFieldChangesOnInsert(newRecords, OBJECT_API_NAME);
    }

    /**
     * @description Captures checkbox changes on existing Validation Checklist records,
     *              including system reversions (true → false) that indicate automated resets.
     * @param newRecords List of updated records (Trigger.new)
     * @param oldMap     Map of pre-update record snapshots (Trigger.oldMap — typed as Map<Id,Object> per interface)
     */
    public static void trackUpdateHistory(List<SObject> newRecords, Map<Id, Object> oldMap) {
        // Build a Map<Id,SObject> by casting each value individually — a bulk cast of
        // Map<Id,Object> to Map<Id,SObject> fails when the map was constructed in test context
        // (runtime type Map<Id,ANY>); this pattern works in both trigger and test contexts.
        Map<Id, SObject> oldSObjectMap = new Map<Id, SObject>();
        for (Id recId : oldMap.keySet()) {
            oldSObjectMap.put(recId, (SObject) oldMap.get(recId));
        }
        FieldHistoryHandler.trackFieldChanges(newRecords, oldSObjectMap, OBJECT_API_NAME);
    }
}