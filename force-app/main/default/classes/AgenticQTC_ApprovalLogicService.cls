/**
 * @description Evaluates whether any quote lines on an amendment require approval.
 *              Approval is required when a new product is added (priorQty = 0) or
 *              when quantity is decreased below the prior amount.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_ApprovalLogicService {

    private static final String ERR_QUOTE_REQUIRED = 'Quote ID is required';
    private static final String LABEL_NEW_PRODUCT = 'New product added';
    private static final String LABEL_UNKNOWN_PRODUCT = 'Unknown Product';

    /**
     * @description Evaluates all quote lines on an amendment quote for approval requirements.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return ApprovalSummary with counts and reasons
     */
    @AuraEnabled
    public static ApprovalSummary evaluateQuoteApproval(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        List<SBQQ__QuoteLine__c> lines = [
            SELECT Id, SBQQ__Quantity__c, SBQQ__PriorQuantity__c, SBQQ__ProductName__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 50000
        ];

        ApprovalSummary summary = new ApprovalSummary();
        summary.totalLines = lines.size();
        summary.linesRequiringApproval = 0;
        summary.reasons = new List<String>();
        summary.anyApprovalRequired = false;

        for (SBQQ__QuoteLine__c line : lines) {
            Decimal qty = line.SBQQ__Quantity__c != null ? line.SBQQ__Quantity__c : 0;
            Decimal priorQty = line.SBQQ__PriorQuantity__c != null ? line.SBQQ__PriorQuantity__c : 0;
            String productName = String.isNotBlank(line.SBQQ__ProductName__c)
                ? line.SBQQ__ProductName__c
                : LABEL_UNKNOWN_PRODUCT;

            Boolean needsApproval = false;
            if (priorQty == 0) {
                needsApproval = true;
                summary.reasons.add(productName + ': ' + LABEL_NEW_PRODUCT);
            } else if (qty < priorQty) {
                needsApproval = true;
                summary.reasons.add(productName + ': Quantity decreased from ' + priorQty.intValue() + ' to ' + qty.intValue());
            }

            if (needsApproval) {
                summary.linesRequiringApproval++;
                summary.anyApprovalRequired = true;
            }
        }

        return summary;
    }

    /**
     * @description DTO summarising the approval evaluation for a quote's amendment lines.
     */
    public class ApprovalSummary {
        @AuraEnabled public Integer totalLines;
        @AuraEnabled public Integer linesRequiringApproval;
        @AuraEnabled public Boolean anyApprovalRequired;
        @AuraEnabled public List<String> reasons;
    }

    /**
     * @description Returns all pending Salesforce Approval Process workitems for a quote.
     *              Queries ProcessInstance + ProcessInstanceWorkitem, then fetches User titles.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of ApprovalItem DTOs with approver name, title, reason, and rule name
     */
    @AuraEnabled
    public static List<ApprovalItem> getRunningApprovals(String quoteId) {
        System.debug('### getRunningApprovals INPUT — quoteId: ' + quoteId);

        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        // Actor is polymorphic — cannot use WITH SECURITY_ENFORCED with Actor.Name traversal.
        // Fetch actor names/titles separately via User query instead.
        List<ProcessInstance> instances = [
            SELECT Id, ProcessDefinition.Name,
                   (SELECT Id, ActorId, OriginalActorId
                    FROM Workitems)
            FROM ProcessInstance
            WHERE TargetObjectId = :quoteId
            AND Status IN ('Pending', 'Started')
            WITH SECURITY_ENFORCED
        ];

        System.debug('### getRunningApprovals — ProcessInstance records found: ' + instances.size());

        Set<Id> actorIds = new Set<Id>();
        for (ProcessInstance pi : instances) {
            System.debug('### ProcessInstance — Id: ' + pi.Id
                + ' | ProcessDefinition.Name: ' + (pi.ProcessDefinition != null ? pi.ProcessDefinition.Name : 'null')
                + ' | Workitems count: ' + pi.Workitems.size());
            for (ProcessInstanceWorkitem wi : pi.Workitems) {
                System.debug('### Workitem — Id: ' + wi.Id + ' | ActorId: ' + wi.ActorId + ' | OriginalActorId: ' + wi.OriginalActorId);
                if (wi.ActorId != null) actorIds.add(wi.ActorId);
            }
        }

        System.debug('### getRunningApprovals — actorIds to fetch: ' + actorIds);

        Map<Id, User> userMap = new Map<Id, User>();
        if (!actorIds.isEmpty()) {
            userMap = new Map<Id, User>([
                SELECT Id, Name, Title FROM User WHERE Id IN :actorIds WITH SECURITY_ENFORCED
            ]);
        }

        System.debug('### getRunningApprovals — Users fetched: ' + userMap.size());
        for (User u : userMap.values()) {
            System.debug('### User — Id: ' + u.Id + ' | Name: ' + u.Name + ' | Title: ' + u.Title);
        }

        List<ApprovalItem> items = new List<ApprovalItem>();
        for (ProcessInstance pi : instances) {
            String processName = pi.ProcessDefinition != null ? pi.ProcessDefinition.Name : 'Approval Process';
            for (ProcessInstanceWorkitem wi : pi.Workitems) {
                ApprovalItem item = new ApprovalItem();
                User actor = userMap.get(wi.ActorId);
                item.approverName  = actor != null && String.isNotBlank(actor.Name) ? actor.Name : 'Approver';
                item.approverTitle = actor != null && actor.Title != null ? actor.Title : '';
                item.reason   = processName;
                item.ruleName = processName;
                List<String> words = item.approverName.split(' ');
                item.initials = words.size() >= 2
                    ? (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase()
                    : item.approverName.substring(0, 1).toUpperCase();
                System.debug('### ApprovalItem built — approverName: ' + item.approverName
                    + ' | approverTitle: ' + item.approverTitle
                    + ' | reason: ' + item.reason
                    + ' | ruleName: ' + item.ruleName
                    + ' | initials: ' + item.initials);
                items.add(item);
            }
        }

        System.debug('### getRunningApprovals OUTPUT — total items returned: ' + items.size());
        return items;
    }

    public class ApprovalItem {
        @AuraEnabled public String approverName;
        @AuraEnabled public String approverTitle;
        @AuraEnabled public String reason;
        @AuraEnabled public String ruleName;
        @AuraEnabled public String initials;
    }
}