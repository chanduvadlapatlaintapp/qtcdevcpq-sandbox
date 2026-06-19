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
     * @description Returns all pending SBAA Advanced Approvals for a quote.
     *              Queries sbaa__Approval__c records in 'Assigned' or 'Requested'
     *              status, then projects each onto the ApprovalItem DTO that the
     *              LWC consumes. Intapp uses SBAA exclusively for quote approvals
     *              — standard Salesforce Approval Processes are not in play here,
     *              so ProcessInstance is intentionally NOT queried.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of ApprovalItem DTOs with approver name, title, reason, and rule name
     */
    @AuraEnabled
    public static List<ApprovalItem> getRunningApprovals(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        List<sbaa__Approval__c> approvals = [
            SELECT Id, sbaa__Rule__c, sbaa__Approver__c
            FROM sbaa__Approval__c
            WHERE Quote__c = :quoteId
              AND sbaa__Status__c IN ('Assigned', 'Requested')
            WITH SECURITY_ENFORCED
            ORDER BY sbaa__ApprovalStep__c ASC NULLS LAST
        ];

        return buildItemsFromApprovals(approvals);
    }

    public class ApprovalItem {
        @AuraEnabled public String approverName;
        @AuraEnabled public String approverTitle;
        @AuraEnabled public String reason;
        @AuraEnabled public String ruleName;
        @AuraEnabled public String initials;
        // Human-readable list of the SBAA conditions that caused this rule to
        // fire. Retained for backwards compatibility and unit-test coverage;
        // the LWC reads `description` instead for the hover popover.
        @AuraEnabled public String conditionDescription;
        // sbaa__AdvancedCondition__c boolean expression from the rule (e.g.
        // "1 AND 2 AND (3 OR 4)"). Retained on the DTO for callers that still
        // want the raw expression — no longer surfaced in the LWC popover.
        @AuraEnabled public String advancedCondition;
        // Author-written explanation of why this rule fires, sourced from
        // sbaa__ApprovalRule__c.Approval_Description__c. The LWC popover shows
        // this prose so reviewers see the business reason in plain language
        // instead of the raw field/operator/value conditions.
        @AuraEnabled public String description;
    }

    // ─────────────────────────────────────────────────────────────────────
    // SBAA Advanced Approvals preview
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @description Previews which Advanced Approvals rules WOULD fire if the
     *              quote were submitted now. Wraps sbaa.ApprovalAPI.preview()
     *              and projects each match onto the ApprovalItem DTO so the
     *              same LWC bindings can render preview and live approvals.
     * @param quoteId The SBQQ__Quote__c recordId
     * @return List of ApprovalItem DTOs for each matching rule
     */
    @AuraEnabled
    public static List<ApprovalItem> previewApprovals(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        List<sbaa__Approval__c> matched;
        try {
            matched = sbaa.ApprovalAPI.preview(quoteId, sbaa__Approval__c.Quote__c);
        } catch (Exception e) {
            // SBAA throws when any matching rule has unresolved approver data.
            throw new AuraHandledException('Approval preview failed: ' + e.getMessage());
        }

        return buildItemsFromApprovals(matched);
    }

    /**
     * @description Submits the quote into SBAA Advanced Approvals. Wraps
     *              sbaa.ApprovalAPI.submit() so the LWC can trigger the same
     *              flow that the standard quote page's "Submit for Approval"
     *              button uses, without leaving the editor.
     * @param quoteId The SBQQ__Quote__c record Id
     */
    @AuraEnabled
    public static void submitForApproval(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }
        try {
            sbaa.ApprovalAPI.submit(quoteId, sbaa__Approval__c.Quote__c);
        } catch (Exception e) {
            throw new AuraHandledException('Submit for approval failed: ' + e.getMessage());
        }
    }

    /**
     * @description Shared projection pipeline for sbaa__Approval__c records — used
     *              both by getRunningApprovals (live state from DB) and by
     *              previewApprovals (predicted state from sbaa.ApprovalAPI.preview()).
     *              Collects the rule/approver Ids referenced by the approvals,
     *              queries the lookup maps, and delegates to buildPreviewItems for
     *              the final DTO projection.
     */
    @TestVisible
    private static List<ApprovalItem> buildItemsFromApprovals(List<sbaa__Approval__c> approvals) {
        if (approvals == null || approvals.isEmpty()) {
            return new List<ApprovalItem>();
        }

        Set<Id> ruleIds = new Set<Id>();
        Set<Id> approverIds = new Set<Id>();
        for (sbaa__Approval__c a : approvals) {
            if (a.sbaa__Rule__c != null) ruleIds.add(a.sbaa__Rule__c);
            if (a.sbaa__Approver__c != null) approverIds.add(a.sbaa__Approver__c);
        }

        Map<Id, sbaa__ApprovalRule__c> ruleMap = new Map<Id, sbaa__ApprovalRule__c>([
            SELECT Id, Name, sbaa__ApprovalChain__r.Name,
                   sbaa__AdvancedCondition__c
            FROM sbaa__ApprovalRule__c
            WHERE Id IN :ruleIds
            WITH SECURITY_ENFORCED
        ]);
        Map<Id, sbaa__Approver__c> approverMap = new Map<Id, sbaa__Approver__c>([
            SELECT Id, Name, sbaa__User__r.Name, sbaa__User__r.Title
            FROM sbaa__Approver__c
            WHERE Id IN :approverIds
            WITH SECURITY_ENFORCED
        ]);
        Map<Id, String> conditionsByRule = buildConditionDescriptions(ruleIds);

        return buildPreviewItems(approvals, ruleMap, approverMap, conditionsByRule);
    }

    /**
     * @description Queries sbaa__ApprovalCondition__c rows for the given rule
     *              Ids and folds each rule's conditions into a single multi-line
     *              string keyed by rule Id. Each line reads as
     *              "<Tested Field> <operator> <value>" — used as the hover
     *              tooltip on the reason cell so the user can see what
     *              field/value combo actually triggered the rule.
     */
    @TestVisible
    private static Map<Id, String> buildConditionDescriptions(Set<Id> ruleIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (ruleIds == null || ruleIds.isEmpty()) return result;

        List<sbaa__ApprovalCondition__c> conditions = [
            SELECT sbaa__ApprovalRule__c, sbaa__TestedField__c, sbaa__Operator__c, sbaa__FilterValue__c, sbaa__Index__c
            FROM sbaa__ApprovalCondition__c
            WHERE sbaa__ApprovalRule__c IN :ruleIds
            WITH SECURITY_ENFORCED
            ORDER BY sbaa__ApprovalRule__c, sbaa__Index__c NULLS LAST
        ];

        Map<Id, List<String>> linesByRule = new Map<Id, List<String>>();
        for (sbaa__ApprovalCondition__c c : conditions) {
            if (!linesByRule.containsKey(c.sbaa__ApprovalRule__c)) {
                linesByRule.put(c.sbaa__ApprovalRule__c, new List<String>());
            }
            linesByRule.get(c.sbaa__ApprovalRule__c).add(formatCondition(c));
        }
        for (Id ruleId : linesByRule.keySet()) {
            result.put(ruleId, String.join(linesByRule.get(ruleId), '\n'));
        }
        return result;
    }

    @TestVisible
    private static String formatCondition(sbaa__ApprovalCondition__c c) {
        String field = String.isNotBlank(c.sbaa__TestedField__c) ? humanizeApiName(c.sbaa__TestedField__c) : '(field)';
        String op    = String.isNotBlank(c.sbaa__Operator__c) ? c.sbaa__Operator__c : '=';
        String value = String.isNotBlank(c.sbaa__FilterValue__c) ? c.sbaa__FilterValue__c : '(blank)';
        // Prepend "<index>\t" so the LWC popover can render the SBAA index
        // alongside each condition without re-parsing the field expression.
        // The leading "?" stands in when an index is missing on the record.
        String idx = c.sbaa__Index__c != null ? String.valueOf(c.sbaa__Index__c.intValue()) : '?';
        return idx + '\t' + field + ' ' + op + ' ' + value;
    }

    @TestVisible
    private static String humanizeApiName(String apiName) {
        if (String.isBlank(apiName)) return '';
        String cleaned = apiName.endsWith('__c') ? apiName.substring(0, apiName.length() - 3) : apiName;
        return cleaned.replace('_', ' ');
    }

    @TestVisible
    private static List<ApprovalItem> buildPreviewItems(
        List<sbaa__Approval__c> matched,
        Map<Id, sbaa__ApprovalRule__c> ruleMap,
        Map<Id, sbaa__Approver__c> approverMap,
        Map<Id, String> conditionsByRule
    ) {
        List<ApprovalItem> items = new List<ApprovalItem>();
        for (sbaa__Approval__c a : matched) {
            sbaa__ApprovalRule__c rule = ruleMap.get(a.sbaa__Rule__c);
            sbaa__Approver__c approver = approverMap.get(a.sbaa__Approver__c);

            String approverName = resolveApproverName(approver);
            String approverTitle = resolveApproverTitle(approver);
            String ruleFullName = rule != null && String.isNotBlank(rule.Name) ? rule.Name : 'Approval Required';

            // SBAA rule names follow "<Category> - <Approver Role>". The
            // category alone is enough for the reason column, but ruleName
            // carries the FULL rule name so the user can see exactly which
            // rule fired (not just the category prefix).
            String reasonText = ruleFullName;
            if (ruleFullName.contains(' - ')) {
                reasonText = ruleFullName.split(' - ', 2)[0].trim();
            }

            ApprovalItem item = new ApprovalItem();
            item.approverName = approverName;
            item.approverTitle = approverTitle;
            item.reason = reasonText;
            item.ruleName = ruleFullName;
            item.initials = buildInitials(approverName);
            item.conditionDescription = (conditionsByRule != null && a.sbaa__Rule__c != null)
                ? conditionsByRule.get(a.sbaa__Rule__c)
                : null;
            item.advancedCondition = rule != null && String.isNotBlank(rule.sbaa__AdvancedCondition__c)
                ? rule.sbaa__AdvancedCondition__c.trim()
                : null;
            items.add(item);
        }
        return items;
    }

    @TestVisible
    private static String resolveApproverName(sbaa__Approver__c approver) {
        if (approver == null) return 'Approver';
        if (approver.sbaa__User__r != null && String.isNotBlank(approver.sbaa__User__r.Name)) {
            return approver.sbaa__User__r.Name;
        }
        return String.isNotBlank(approver.Name) ? approver.Name : 'Approver';
    }

    @TestVisible
    private static String resolveApproverTitle(sbaa__Approver__c approver) {
        if (approver != null && approver.sbaa__User__r != null && approver.sbaa__User__r.Title != null) {
            return approver.sbaa__User__r.Title;
        }
        return '';
    }

    @TestVisible
    private static String buildInitials(String name) {
        if (String.isBlank(name)) return '?';
        List<String> words = name.split(' ');
        return words.size() >= 2
            ? (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase()
            : name.substring(0, 1).toUpperCase();
    }
}