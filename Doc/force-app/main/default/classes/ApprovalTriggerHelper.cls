/**
 * @description Helper class for ApprovalTrigger. Contains all business logic
 *              for the sbaa__Approval__c trigger, keeping the handler thin.
 * @author      Business Applications
 * @date        2026-05-15
 * @jira        BIZ-73147
 **/
public with sharing class ApprovalTriggerHelper {

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
     * @description Stamps Approval_Requested__c when sbaa__Status__c transitions to Requested.
     *              Pass a null oldMap on insert (all records are treated as status-changed).
     * @param newList  Records being inserted or updated.
     * @param oldMap   Previous state of records; null on insert.
     **/
    public static void stampRequestedTimestamp(List<SBAA__Approval__c> newList,
                                               Map<Id, SBAA__Approval__c> oldMap) {
        for (SBAA__Approval__c rec : newList) {
            Boolean statusChanged = oldMap == null
                || rec.sbaa__Status__c != oldMap.get(rec.Id).sbaa__Status__c;
            if (statusChanged && rec.sbaa__Status__c == ApprovalConstants.STATUS_REQUESTED) {
                rec.Approval_Requested__c = DateTime.now();
            }
        }
    }

    /**
     * @description Stamps Approval_Received__c when sbaa__Status__c transitions to Approved.
     * @param newList  Records being updated.
     * @param oldMap   Previous state of records.
     **/
    public static void stampReceivedTimestamp(List<SBAA__Approval__c> newList,
                                              Map<Id, SBAA__Approval__c> oldMap) {
        for (SBAA__Approval__c rec : newList) {
            if (rec.sbaa__Status__c != oldMap.get(rec.Id).sbaa__Status__c
                && rec.sbaa__Status__c == ApprovalConstants.STATUS_APPROVED) {
                rec.Approval_Received__c = DateTime.now();
            }
        }
    }

    /**
     * @description Publishes all approval record Ids for downstream processing (after insert).
     * @param newRecords  Newly inserted sbaa__Approval__c records.
     **/
    public static void publishApprovalRecords(List<SObject> newRecords) {
        QuoteTriggerHelper.publishApprovalRecords(Pluck.ids((List<SBAA__Approval__c>) newRecords));
    }

    /**
     * @description Publishes approval record Ids where a relevant field changed (after update).
     * @param newList  Updated records.
     * @param oldMap   Previous state of records.
     **/
    public static void publishChangedApprovalRecords(List<SBAA__Approval__c> newList,
                                                     Map<Id, SBAA__Approval__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (SBAA__Approval__c rec : newList) {
            SBAA__Approval__c old = oldMap.get(rec.Id);
            if ((rec.OP4I_System_Id__c != null || rec.OP4I_Error__c != null)
                && (rec.sbaa__AssignedTo__c    != old.sbaa__AssignedTo__c
                 || rec.sbaa__ApprovedBy__c    != old.sbaa__ApprovedBy__c
                 || rec.sbaa__Status__c        != old.sbaa__Status__c
                 || rec.sbaa__CommentsLong__c  != old.sbaa__CommentsLong__c)) {
                ids.add(rec.Id);
            }
        }
        QuoteTriggerHelper.publishApprovalRecords(ids);
    }
}