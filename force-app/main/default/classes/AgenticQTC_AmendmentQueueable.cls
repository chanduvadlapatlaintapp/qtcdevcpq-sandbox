/**
 * @description Queueable Apex that runs the CPQ ContractAmender callout in the background,
 *              freeing the LWC from the 40–50 s synchronous wait.
 *              On completion or failure, writes the result to AgenticQTC_AmendmentJob__c
 *              so the LWC polling loop can detect it.
 * @author AgenticQTC Team
 * @date 2026-05-05
 * @jira BIZ-AgenticQTC
 */
public without sharing class AgenticQTC_AmendmentQueueable implements Queueable, Database.AllowsCallouts {

    private final Id contractId;
    private final Id jobId;

    public AgenticQTC_AmendmentQueueable(Id contractId, Id jobId) {
        this.contractId = contractId;
        this.jobId      = jobId;
    }

    public void execute(QueueableContext ctx) {
        try {
            // Idempotency: reuse an existing draft amendment quote if one already exists
            List<SBQQ__Quote__c> existing = [
                SELECT Id FROM SBQQ__Quote__c
                WHERE SBQQ__MasterContract__c = :contractId
                AND SBQQ__Status__c = 'Draft'
                AND SBQQ__Type__c = 'Amendment'
                LIMIT 1
            ];

            Id quoteId;
            if (!existing.isEmpty()) {
                quoteId = existing[0].Id;
            } else {
                Map<String, Object> amendmentModel = CPQAmendmentService.amendAndUpdateLines(
                    contractId,
                    new Map<Id, Map<String, Object>>()
                );
                quoteId = CPQAPIUtils.getQuoteId(amendmentModel);
            }

            if (quoteId == null) {
                throw new CPQAmendmentService.CPQAmendmentException(
                    'CPQ ContractAmender returned no quote Id for contract ' + contractId
                );
            }

            update new AgenticQTC_AmendmentJob__c(
                Id       = jobId,
                Status__c   = 'Complete',
                Quote_Id__c = String.valueOf(quoteId)
            );

        } catch (Exception e) {
            Nebula.Logger.error(
                'AgenticQTC_AmendmentQueueable failed for contract ' + contractId
                    + ': ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendmentQueueable')
                .addTag('Amendment')
                .setRecordId(contractId);
            Nebula.Logger.saveLog();

            update new AgenticQTC_AmendmentJob__c(
                Id              = jobId,
                Status__c       = 'Failed',
                Error_Message__c = e.getMessage()?.left(32768)
            );
        }
    }
}