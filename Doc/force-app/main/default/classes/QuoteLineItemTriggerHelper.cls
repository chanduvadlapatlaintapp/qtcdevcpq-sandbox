/**
 * @description  Helper class for QuoteLineItemTriggerHandler. Holds reusable
 *               business-logic routines that operate on SBQQ__QuoteLine__c records.
 * @author       Manisha Sharma
 * @jira         BIZ-81462
 */
public without sharing class QuoteLineItemTriggerHelper {

    @TestVisible
    private static final String SOURCE_SYSTEM_SFDC = 'SFDC';

    /**
     * @description BIZ-81462: SBQQ twin-field copy carries One_Time_Credit__c from
     *              Subscription onto both Amendment and Renewal quote lines. Carry-over
     *              is only allowed for SFDC-sourced Amendments. Clear the value on insert when:
     *                - The parent quote is an Amendment whose Source_System__c is not strictly 'SFDC', OR
     *                - The parent quote is a Renewal (regardless of source system).
     *              New-business and Migration quote lines are not affected (no Subscription
     *              propagation path, so any OTC value is intentional user input).
     * @param newLines Trigger.new collection of SBQQ__QuoteLine__c records.
     */
    public static void gateOneTimeCreditForAmendments(List<SBQQ__QuoteLine__c> newLines) {
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
            SELECT Id, SBQQ__Type__c, Source_System__c
            FROM SBQQ__Quote__c
            WHERE Id IN :quoteIds
        ]);

        for (SBQQ__QuoteLine__c ql : newLines) {
            if (ql.One_Time_Credit__c == null || ql.SBQQ__Quote__c == null) {
                continue;
            }
            SBQQ__Quote__c parent = parentQuotes.get(ql.SBQQ__Quote__c);
            if (parent == null) {
                continue;
            }
            Boolean isAmendment = parent.SBQQ__Type__c == QuoteConstants.TYPE_AMENDMENT;
            Boolean isRenewal = parent.SBQQ__Type__c == QuoteConstants.TYPE_RENEWAL;
            Boolean isSfdcSourced = parent.Source_System__c == SOURCE_SYSTEM_SFDC;
            // Only SFDC-sourced amendments are allowed to carry OTC over from Subscription.
            // Non-SFDC amendments and all renewals must have the propagated value cleared.
            if ((isAmendment && !isSfdcSourced) || isRenewal) {
                ql.One_Time_Credit__c = null;
            }
        }
    }
}