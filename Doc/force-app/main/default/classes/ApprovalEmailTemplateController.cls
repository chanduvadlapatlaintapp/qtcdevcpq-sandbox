/**
 * @description Controller class for fetching prior approval comments and next approver name for a quote.
 * @author Manisha
 * @jira BIZ-68135
**/
public class ApprovalEmailTemplateController {

    /***********************************************************************************************
    *
    * Instance Variables
    *
    ***********************************************************************************************/
    public Id quoteId { get; set; }
    public Id approvalId { get; set; }

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
     * @description Returns list of prior approved comments for a given quote.
     *              Filters approvals with status 'Approved' and orders them chronologically.
     *
     * @return List<sbaa__Approval__c> - List of approved approval records for the quote.
     */
    public List<sbaa__Approval__c> getPriorApprovals() {
        if (quoteId == null) {
            return new List<sbaa__Approval__c>();
        }
        
        return [
            SELECT Id, sbaa__CommentsLong__c, sbaa__AssignedTo__r.Name, CreatedDate 
            FROM sbaa__Approval__c 
            WHERE Quote__c = :quoteId 
            AND sbaa__Status__c =: ApprovalConstants.STATUS_APPROVED
            ORDER BY CreatedDate ASC
        ];
    }

    /**
     * @description Returns the name of the next approver in the approval chain for the quote.
     *              Finds the next approval step with status 'Assigned' that is greater than the current.
     *
     * @return String - Name of the next approver or null if none found.
     */
    public String getNextApproverName() {
        if (approvalId == null) {
            return null;
        }
        // Fetch current approval to get chain and step
        sbaa__Approval__c currentApproval = [
            SELECT Id, sbaa__ApprovalChain__c, sbaa__ApprovalStep__c
            FROM sbaa__Approval__c
            WHERE Id = :approvalId
            LIMIT 1
        ];
        
        // Query next approval in line based on step order
        List<sbaa__Approval__c> nextApprovals = [
            SELECT sbaa__AssignedTo__r.Name, sbaa__ApprovalStep__c
            FROM sbaa__Approval__c
            WHERE sbaa__ApprovalChain__c = :currentApproval.sbaa__ApprovalChain__c
            AND sbaa__Status__c =: ApprovalConstants.STATUS_ASSIGNED
            AND sbaa__ApprovalStep__c > :currentApproval.sbaa__ApprovalStep__c
            AND Quote__c = :quoteId
            ORDER BY sbaa__ApprovalStep__c ASC
            LIMIT 1
        ];
        
        if (!nextApprovals.isEmpty()) {
            return nextApprovals[0].sbaa__AssignedTo__r.Name;
        }
        
        return null;
    }
}