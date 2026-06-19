/********************************************************************************
*  Name             :  ContentFilesTriggerHelper
*  Author           :  Ratan Paul
*  Description      :  Helper class for ContentFilesTriggerHandler.
*                      Contains business logic for ContentDocumentLink trigger events.
*  Change history   :
*  Date             Author              Description
*  06/05/26         Ratan Paul          Initial version via BIZ-81572
********************************************************************************/
public with sharing class ContentFilesTriggerHelper {

    /**
     * @description Prevents deletion of files linked to Contract Executed quotes.
     *              Called from ContentFilesTriggerHandler.beforeDelete().
     *              All other quote statuses (including Pending Closure) are permitted.
     * @param cdlList List of ContentDocumentLink records being deleted.
     */
    public static void blockDeleteOnContractExecutedQuotes(List<ContentDocumentLink> cdlList) {
        // Collect LinkedEntityIds that belong to SBQQ__Quote__c records
        Set<Id> quoteIds = new Set<Id>();
        for (ContentDocumentLink cdl : cdlList) {
            if (cdl.LinkedEntityId != null
                    && cdl.LinkedEntityId.getSObjectType() == SBQQ__Quote__c.SObjectType) {
                quoteIds.add(cdl.LinkedEntityId);
            }
        }

        if (quoteIds.isEmpty()) {
            return;
        }

        // Query only quotes in Contract Executed status
        Map<Id, SBQQ__Quote__c> contractExecutedQuotes = new Map<Id, SBQQ__Quote__c>([
            SELECT Id
            FROM SBQQ__Quote__c
            WHERE Id IN :quoteIds
              AND Quote_Stage__c = :QuoteConstants.STATUS_CONTRACT_EXECUTED
        ]);

        if (contractExecutedQuotes.isEmpty()) {
            return;
        }

        // Block deletion on any CDL linked to a Contract Executed quote
        for (ContentDocumentLink cdl : cdlList) {
            if (contractExecutedQuotes.containsKey(cdl.LinkedEntityId)) {
                cdl.addError('Files cannot be deleted from a Contract Executed quote.');
            }
        }
    }
}