/**
 * @description Trigger handler for sbaa__Approval__c. Implements TriggerFunctionInterface
 *              and delegates all business logic to ApprovalTriggerHelper.
 * @author      Business Applications
 * @date        2026-05-15
 * @jira        BIZ-73147
 **/
public with sharing class ApprovalTriggerHandler implements TriggerFunctionInterface {

    /***********************************************************************************************
    *
    * Before Trigger Methods
    *
    ***********************************************************************************************/

    /**
     * @description Stamps Approval_Requested__c on records inserted with status Requested.
     * @param newRecords  Records being inserted.
     **/
    public void beforeInsert(List<SObject> newRecords) {
        ApprovalTriggerHelper.stampRequestedTimestamp((List<SBAA__Approval__c>) newRecords, null);
    }

    /**
     * @description Stamps Approval_Requested__c and Approval_Received__c on status transitions.
     * @param newRecords  Updated records.
     * @param newMap      Map of updated records by Id.
     * @param oldRecords  Previous state of records.
     * @param oldMap      Map of previous record state by Id.
     **/
    public void beforeUpdate(List<SObject> newRecords, Map<Id, Object> newMap,
                             List<Object> oldRecords, Map<Id, Object> oldMap) {
        ApprovalTriggerHelper.stampRequestedTimestamp(
            (List<SBAA__Approval__c>) newRecords,
            (Map<Id, SBAA__Approval__c>) oldMap
        );
        ApprovalTriggerHelper.stampReceivedTimestamp(
            (List<SBAA__Approval__c>) newRecords,
            (Map<Id, SBAA__Approval__c>) oldMap
        );
    }

    /**
     * @description No action on before delete.
     * @param oldRecords  Records being deleted.
     * @param oldMap      Map of records being deleted by Id.
     **/
    public void beforeDelete(List<SObject> oldRecords, Map<Id, Object> oldMap) {}

    /***********************************************************************************************
    *
    * After Trigger Methods
    *
    ***********************************************************************************************/

    /**
     * @description Publishes approval records for downstream processing after insert.
     * @param newRecords  Newly inserted records.
     * @param newMap      Map of newly inserted records by Id.
     **/
    public void afterInsert(List<SObject> newRecords, Map<Id, Object> newMap) {
        ApprovalTriggerHelper.publishApprovalRecords(newRecords);
    }

    /**
     * @description Publishes approval records where a relevant field changed after update.
     * @param newRecords  Updated records.
     * @param newMap      Map of updated records by Id.
     * @param oldRecords  Previous state of records.
     * @param oldMap      Map of previous record state by Id.
     **/
    public void afterUpdate(List<SObject> newRecords, Map<Id, Object> newMap,
                            List<Object> oldRecords, Map<Id, Object> oldMap) {
        ApprovalTriggerHelper.publishChangedApprovalRecords(
            (List<SBAA__Approval__c>) newRecords,
            (Map<Id, SBAA__Approval__c>) oldMap
        );
    }

    /**
     * @description No action on after delete.
     * @param oldRecords  Records that were deleted.
     * @param oldMap      Map of deleted records by Id.
     **/
    public void afterDelete(List<Object> oldRecords, Map<Id, Object> oldMap) {}

    /**
     * @description No action on after undelete.
     * @param newRecords  Records that were undeleted.
     * @param newMap      Map of undeleted records by Id.
     **/
    public void afterUnDelete(List<SObject> newRecords, Map<Id, Object> newMap) {}
}