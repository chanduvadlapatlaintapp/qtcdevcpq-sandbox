/**
 * @description Class to get all pending approvals for a user, to be displayed in a ListView
 */
public with sharing class ApprovalRequestController {
    /***********************************************************************************************
    *
    * Public getters
    *
    ***********************************************************************************************/
    /**
     * @description string Domain
     */
    public String domain{
        get{
            return URL.getOrgDomainUrl().toExternalForm();
        }
        set;
    }
    
    /**
     * @description Get All Pending Approvals for a given User
     * @return List of Approval Wrapper
     */
    public List<ApprovalWrapper> approvalRequests { 
        get {
            if (usrId != null) {
                return getApprovalRequests(usrId); // call the existing static method
            }
            return new List<ApprovalWrapper>();
        }
        private set;
    }

    /**
     * @description string UserId
     */
    public Id usrId{ get; set; }
    
    /***********************************************************************************************
    *
    * Public methods
    *
    ***********************************************************************************************/
    /***
     * @description Get all relevant UserIds from Approvals
     * @return Set of Ids
     */
    public static Set<Id> getRelevantUserIdsFromApprovals() {
        Set<Id> userIds = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();

        for (sbaa__Approval__c approval : ApprovalSelector.getOpenApprovals()) {
            if (approval.sbaa__Approver__r?.sbaa__User__r != null) {
                userIds.add(approval.sbaa__Approver__r.sbaa__User__r.Id);
            }
            if (approval.sbaa__DelegatedApprover__r?.sbaa__User__r != null) {
                userIds.add(approval.sbaa__DelegatedApprover__r.sbaa__User__r.Id);
            }
            if (approval.sbaa__AssignedGroupId__c != null) {
                groupIds.add(approval.sbaa__AssignedGroupId__c);
            }
        }

        if (!groupIds.isEmpty()) {
            for (GroupMember gm : getGroupMembers(groupIds)) {
                if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
                    userIds.add(gm.UserOrGroupId);
                }
            }
        }

        return userIds;
    }


    /**
     * @description Get Pending Approvals for a given User
     * @param userId User Id
     * @return List of Approval Wrapper
     */
    public static List<ApprovalWrapper> getApprovalRequests(Id userId) {
        // Get group Ids the user belongs to
        Set<Id> userGroupIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :userId
        ]) {
            userGroupIds.add(gm.GroupId);
        }

        // Query Approval records

        // Build wrapper list
        List<ApprovalWrapper> results = new List<ApprovalWrapper>();
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        Date todayDate = Date.today();
        
        for (sbaa__Approval__c app : getMatchingApprovals(userId, userGroupIds)) {
            ApprovalWrapper wrapper = new ApprovalWrapper();
            
            wrapper.actionLink = baseUrl + '/' + app.Id;
            wrapper.quoteName = app.Quote__r.Name;
            wrapper.quoteNumberLink = app.Quote__c != null ? baseUrl + '/' + app.Quote__c : null;
            wrapper.quoteOwnerName = app.Quote__r.OP4I_Deal_Owner__c;
            wrapper.opportunityName = app.Quote__r.SBQQ__Opportunity2__r.Name;
            wrapper.opportunityLink = app.Quote__r.SBQQ__Opportunity2__r != null ? baseUrl + '/' + app.Quote__r.SBQQ__Opportunity2__c : null;
            wrapper.accountName = app.Quote__r.SBQQ__Account__r.Name;
            wrapper.accountLink = app.Quote__r.SBQQ__Account__c != null ? baseUrl + '/' + app.Quote__r.SBQQ__Account__c : null;
            wrapper.approvalRequestNotes = app.Quote__r.Approval_Request_Notes__c;//Use Note from Quote instead of from Approval
            //wrapper.status = app.sbaa__Status__c;
            //wrapper.createdDate = app.createdDate != null ? app.createdDate : null;
            wrapper.daysSinceRequested = app.createdDate.date().daysBetween(todayDate);
            results.add(wrapper);
        }
        
        return results;
    }

    /***********************************************************************************************
     * 
     * Data Getters
     * 
     * ***********************************************************************************************/
    /**
     * @description Get Group Members for a given set of Group Ids
     * @param groupIds Set of Group Ids
     * @return List of GroupMember
     */
    private static List<GroupMember> getGroupMembers(Set<Id> groupIds) {
        return [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :groupIds
        ];
    }

    /**
     * @description Get Matching Approvals for a given User Id and Group Ids
     * @param userId User Id
     * @param userGroupIds Set of Group Ids
     * @return List of sbaa__Approval__c
     */
    private static List<sbaa__Approval__c> getMatchingApprovals(Id userId, Set<Id> userGroupIds) {
        return [
            SELECT Id,
                   Name,
                   sbaa__Approver__c,
                   sbaa__DelegatedApprover__c,
                   sbaa__AssignedGroupId__c,
                   //sbaa__Status__c,
                   CreatedDate,
            	   Quote__r.Approval_Request_Notes__c,
                   Quote__c,
                   Quote__r.Name,
                   Quote__r.OP4I_Deal_Owner__c,
                   Quote__r.SBQQ__Account__r.Id,
                   Quote__r.SBQQ__Account__r.Name,
            	   Quote__r.SBQQ__Opportunity2__r.Id,
                   Quote__r.SBQQ__Opportunity2__r.Name
            FROM sbaa__Approval__c
            WHERE Quote__c != null
            AND (NOT Quote__r.Opportunity_Stage__c Like '%Closed%')
            AND sbaa__Status__c = :ApprovalConstants.STATUS_REQUESTED
              AND (
                  sbaa__Approver__r.sbaa__User__r.Id = :userId OR
                  sbaa__DelegatedApprover__r.sbaa__User__r.Id = :userId OR
                  sbaa__AssignedGroupId__c IN :userGroupIds
              )
        ];
    }

    /***********************************************************************************************
    *
    * Wrapper Classes
    *
    ***********************************************************************************************/
    /**
     * @description Wrapper class for Approvals
     */
    public class ApprovalWrapper {
        /**
         * @description Action Link
         */
        public String actionLink { get; set; }
        /**
         * @description Quote Name
         */
        public String quoteName { get; set; }
        /**
         * @description Quote Number Link
         */
        public String quoteNumberLink { get; set; }
        /**
         * @description Quote Owner Name 
         */
        public String quoteOwnerName { get; set; }
        /**
         * @description Opportunity Name
         */
        public String opportunityName { get; set; }
        /**
         * @description Opportunity Link
         */
        public String opportunityLink { get; set; }
        /**
         * @description account Name
         */
        public String accountName { get; set; }
        /**
         * @description account Link
         */
        public String accountLink { get; set; }
        /**
         * @description Approval Request Notes
         */
        public String approvalRequestNotes { get; set; }
        /**
         * @description number of days since the approval request was created
         */
        public Integer daysSinceRequested { get; set; }
    }

}