/**
 * @description  Helper class for QuoteLineItemTriggerHandler. Holds reusable business-logic
 *               routines that operate on SBQQ__QuoteLine__c records in the before-trigger context.
 * @author       Manisha Sharma
 * @jira         BIZ-81462
 */
public without sharing class QuoteLineItemTriggerHelper {

    /**
     * @description BIZ-81462: Renewals must never carry the One-Time Credit twin-field over from
     *              the Subscription, regardless of source system (OP4I or SFDC). Cleared in place
     *              in the before-insert / before-update context - renewals have no Source_System
     *              dependency so the trigger timing is reliable. OP4I amendments are handled
     *              post-build in SingleQuoteDealFactorySupport instead (their source system is not
     *              stamped until after the lines exist).
     * @param newLines Trigger.new collection of SBQQ__QuoteLine__c records.
     */
    public static void clearOneTimeCreditForRenewalLines(List<SBQQ__QuoteLine__c> newLines) {
        if (newLines == null || newLines.isEmpty()) {
            return;
        }

        Set<Id> quoteIds = new Set<Id>();
        for (SBQQ__QuoteLine__c ql : newLines) {
            if (ql.One_Time_Credit__c != null && ql.SBQQ__Quote__c != null) {
                quoteIds.add(ql.SBQQ__Quote__c);
            }
        }
        if (quoteIds.isEmpty()) {
            return;
        }

        Map<Id, SBQQ__Quote__c> parentQuotes = new Map<Id, SBQQ__Quote__c>([
            SELECT Id, SBQQ__Type__c
            FROM SBQQ__Quote__c
            WHERE Id IN :quoteIds
        ]);

        for (SBQQ__QuoteLine__c ql : newLines) {
            if (ql.One_Time_Credit__c == null || ql.SBQQ__Quote__c == null) {
                continue;
            }
            SBQQ__Quote__c parent = parentQuotes.get(ql.SBQQ__Quote__c);
            if (parent != null && parent.SBQQ__Type__c == QuoteConstants.TYPE_RENEWAL) {
                ql.One_Time_Credit__c = null;
            }
        }
    }
}