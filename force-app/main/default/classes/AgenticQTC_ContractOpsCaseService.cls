/**
 * @description Creates and manages Contract Operations cases for amendments
 *              that require approval review. Prevents duplicate cases for the
 *              same contract amendment.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_ContractOpsCaseService {

    private static final String ERR_QUOTE_REQUIRED = 'Quote ID is required';
    private static final String CASE_SUBJECT_PREFIX = 'AgenticQTC Amendment - ';
    private static final String CASE_ORIGIN = 'Agentic QTC';
    private static final String QUEUE_PATTERN = '%Contract%Ops%';
    private static final String LABEL_UNKNOWN_CONTRACT = 'Unknown';

    /**
     * @description Creates a Contract Ops case for an amendment requiring approval.
     *              Returns the existing case Id if one already exists.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param accountId The Account record Id
     * @param contractNumber The contract number for the subject line
     * @return The Case record Id
     */
    @AuraEnabled
    public static String createContractOpsCase(String quoteId, String accountId, String contractNumber) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        String safeContractNum = String.isNotBlank(contractNumber)
            ? String.escapeSingleQuotes(contractNumber)
            : LABEL_UNKNOWN_CONTRACT;

        String subjectPattern = '%' + CASE_SUBJECT_PREFIX + safeContractNum + '%';
        List<Case> existingCases = [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Subject LIKE :subjectPattern
            AND Status != 'Closed'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existingCases.isEmpty()) {
            return existingCases[0].Id;
        }

        AgenticQTC_ApprovalLogicService.ApprovalSummary approval =
            AgenticQTC_ApprovalLogicService.evaluateQuoteApproval(quoteId);

        String description = 'Amendment requires Contract Ops review.\n\n';
        description += 'Quote: ' + quoteId + '\n';
        description += 'Contract: ' + safeContractNum + '\n\n';
        description += 'Reasons:\n';
        if (approval.reasons != null) {
            for (String reason : approval.reasons) {
                description += '• ' + reason + '\n';
            }
        }

        Case newCase = new Case(
            Subject = CASE_SUBJECT_PREFIX + safeContractNum,
            Description = description,
            Status = 'New',
            Priority = 'Medium',
            AccountId = accountId,
            Origin = CASE_ORIGIN
        );

        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND Name LIKE :QUEUE_PATTERN
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!queues.isEmpty()) {
            newCase.OwnerId = queues[0].Id;
        }

        insert newCase;
        return newCase.Id;
    }
}