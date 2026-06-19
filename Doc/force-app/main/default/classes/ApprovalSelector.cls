/**
 * @description Selector class for Approvals
 */
public inherited sharing class ApprovalSelector {
    
    /***********************************************************************************************
     *
     * Public methods
     *
     ***********************************************************************************************/
    /**
     * @description Get all open approvals
     * @return List of sbaa__Approval__c
     */
    public static List<sbaa__Approval__c> getOpenApprovals() {
        return [SELECT sbaa__Approver__r.sbaa__User__r.Id,
                        sbaa__DelegatedApprover__r.sbaa__User__r.Id,
                        sbaa__AssignedGroupId__c
                FROM sbaa__Approval__c
                WHERE sbaa__Status__c = :ApprovalConstants.STATUS_REQUESTED];
    }
}