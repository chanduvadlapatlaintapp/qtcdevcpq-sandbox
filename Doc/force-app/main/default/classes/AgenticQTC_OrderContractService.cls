/**
 * @description Service for order-related operations on amendment quotes.
 *              Handles closing opportunities as Won to trigger CPQ order creation.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_OrderContractService {

    private static final String ERR_QUOTE_REQUIRED = 'Quote ID is required';
    private static final String ERR_OPP_REQUIRED = 'Opportunity ID is required';
    private static final String STAGE_CLOSED_WON = 'Closed Won';

    /**
     * @description Closes the opportunity associated with a quote as "Closed Won",
     *              which triggers the CPQ order creation process.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return The quote Id for confirmation
     */
    @AuraEnabled
    public static String createOrderFromQuote(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        SBQQ__Quote__c quote = [
            SELECT Id, Name, SBQQ__Account__c, SBQQ__Opportunity2__c,
                   SBQQ__MasterContract__c, SBQQ__StartDate__c,
                   SBQQ__MasterContract__r.ContractNumber
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (quote.SBQQ__Opportunity2__c != null) {
            Opportunity opp = new Opportunity(
                Id = quote.SBQQ__Opportunity2__c,
                StageName = STAGE_CLOSED_WON
            );
            update opp;
        }

        return quote.Id;
    }

    /**
     * @description Closes an opportunity as "Closed Won" directly.
     * @param opportunityId The Opportunity record Id
     */
    @AuraEnabled
    public static void closeWonOpportunity(String opportunityId) {
        if (String.isBlank(opportunityId)) {
            throw new AuraHandledException(ERR_OPP_REQUIRED);
        }
        Opportunity opp = new Opportunity(Id = opportunityId, StageName = STAGE_CLOSED_WON);
        update opp;
    }
}