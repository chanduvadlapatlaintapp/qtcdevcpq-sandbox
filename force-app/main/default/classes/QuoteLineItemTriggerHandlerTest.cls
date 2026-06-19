/**
 * @description  Test class for QuoteLineItemTriggerHandler. The related trigger is SBQQQuoteLineTrigger.
 * @author       Manisha
 * @date         2025-07-02
 * @jira         N/A
 */
@isTest
public class QuoteLineItemTriggerHandlerTest {

    /***********************************************************************************************
    *
    * Shared Test Data Setup
    *
    ***********************************************************************************************/

    /**
     * @description Inserts shared test data using TestFactory.
     */
    @testSetup
    static void setupTestData() {
        // Bypass Quote flows/triggers so quote lines can be inserted/updated in tests without
        // the Quote automation failing on missing context. Quoteline_Bypass__c stays false so
        // the QuoteLine trigger still fires for the insert/update/delete coverage below.
        insert new Automation_Controls__c(
            SetupOwnerId = UserInfo.getUserId(),
            Active__c = true,
            Bypass_Flows__c = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c = true,
            Quoteline_Bypass__c = false,
            Contract_Bypass__c = true,
            Contractline_Bypass__c = true
        );

        // Create Product
        List<Product2> products = (List<Product2>) TestFactory.createSObjectList(
            new Product2(Name = 'Intapp Risk & Compliance PIN-01670'),
            1,
            'ProductDefaults'
        );

        // Create PricebookEntry for Product
        for (Product2 product : products) {
            TestFactory.createSObjectList(
                new PricebookEntry(Product2Id = product.Id),
                1,
                'PricebookEntryDefaults'
            );
        }

        // Create Account
        List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
            new Account(Name = 'Test Account'),
            1,
            'AccountDefaults'
        );

        // Create Opportunity
        List<Opportunity> opportunities = (List<Opportunity>) TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ),
            1,
            'OpportunityDefaults'
        );

        // Create Quotes for Opportunities
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
        for (Opportunity opp : opportunities) {
            quotes.addAll((List<SBQQ__Quote__c>) TestFactory.createSObjectList(
                new SBQQ__Quote__c(
                    SBQQ__Primary__c = true,
                    SBQQ__Opportunity2__c = opp.Id
                ),
                1,
                'SBQQQuoteDefaults'
            ));
        }

        // Create a Quote Line for each Quote
        for (SBQQ__Quote__c quote : quotes) {
            Product2 prod = products[0];

            SBQQ__QuoteLine__c parentQL = (SBQQ__QuoteLine__c) TestFactory.createSObject(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = quote.Id,
                    SBQQ__Product__c = prod.Id,
                    SBQQ__Quantity__c = 1,
                    SBQQ__CustomerPrice__c = 100,
                    Line_Item_Key__c = 'PARENT_KEY'
                ),
                'SBQQQuoteLineDefaults'
            );
        }
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/

    /**
     * @description Tests insert, update, delete, and undelete operations on SBQQ__QuoteLine__c.
     */
    @isTest
    static void testInsertUpdateDeleteQuoteLine() {
        // Get inserted Quote Line
        SBQQ__QuoteLine__c qli = getInsertedQuoteLine();

        // Update operation
        qli.SBQQ__Quantity__c = 10;
        update qli;

        // Delete operation
        delete qli;

        // Undelete operation (covers afterUnDelete)
        undelete qli;
    }

    /***********************************************************************************************
    *
    * BIZ-81462 - One-Time Credit clearing
    *
    * Rule: blank OTC for renewals (OP4I and SFDC) and for OP4I amendments only.
    *   - Renewals          -> cleared in-place by the QuoteLine before-insert/before-update gate
    *                          (QuoteLineItemTriggerHandler.clearOneTimeCreditForRenewalLines).
    *   - OP4I amendments   -> cleared post-build by
    *                          SingleQuoteDealFactorySupport.clearOneTimeCreditForAmendmentQuotes.
    *   - SFDC amendments   -> kept.
    *
    ***********************************************************************************************/

    private static final Decimal OTC_VALUE = 1500;
    private static Id cachedProductId;
    private static Id cachedOpportunityId;

    /**
     * @description Renewal (OP4I) line -> OTC cleared on insert by the trigger gate.
     */
    @isTest
    static void renewalOtcClearedForOp4iOnInsert() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_RENEWAL, 'OP4I');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        System.assertEquals(null, reloadOtc(ql.Id), 'OTC should be cleared on an OP4I renewal line.');
    }

    /**
     * @description Renewal (SFDC) line -> OTC cleared on insert by the trigger gate.
     */
    @isTest
    static void renewalOtcClearedForSfdcOnInsert() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_RENEWAL, 'SFDC');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        System.assertEquals(null, reloadOtc(ql.Id), 'OTC should be cleared on an SFDC renewal line.');
    }

    /**
     * @description Renewal line -> OTC re-populated on update is cleared again by the gate.
     */
    @isTest
    static void renewalOtcClearedOnUpdate() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_RENEWAL, 'SFDC');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);
        insert ql; // cleared at insert

        ql.One_Time_Credit__c = OTC_VALUE; // simulate later (re)population

        Test.startTest();
        update ql;
        Test.stopTest();

        System.assertEquals(null, reloadOtc(ql.Id), 'OTC re-populated on a renewal line should be cleared again.');
    }

    /**
     * @description Renewal gate must NOT touch amendment lines (handled post-build instead).
     */
    @isTest
    static void renewalGateIgnoresAmendment() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_AMENDMENT, 'OP4I');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        System.assertEquals(OTC_VALUE, reloadOtc(ql.Id), 'Renewal gate should leave amendment-line OTC untouched.');
    }

    /**
     * @description OP4I amendment -> OTC cleared by the post-build amendment clear.
     */
    @isTest
    static void amendmentOtcClearedForOp4i() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_AMENDMENT, 'OP4I');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);
        insert ql; // renewal gate leaves it (not a renewal)

        Test.startTest();
        SingleQuoteDealFactorySupport.clearOneTimeCreditForAmendmentQuotes(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(null, reloadOtc(ql.Id), 'OTC should be cleared for an OP4I amendment.');
    }

    /**
     * @description SFDC amendment -> OTC preserved by the post-build amendment clear.
     */
    @isTest
    static void amendmentOtcPreservedForSfdc() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_AMENDMENT, 'SFDC');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);
        insert ql;

        Test.startTest();
        SingleQuoteDealFactorySupport.clearOneTimeCreditForAmendmentQuotes(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(OTC_VALUE, reloadOtc(ql.Id), 'OTC should be preserved for an SFDC amendment.');
    }

    /**
     * @description Non-amendment quote -> post-build amendment clear must not touch OTC.
     */
    @isTest
    static void amendmentClearIgnoresNonAmendment() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_QUOTE, 'OP4I');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);
        insert ql;

        Test.startTest();
        SingleQuoteDealFactorySupport.clearOneTimeCreditForAmendmentQuotes(new Set<Id>{ quote.Id });
        Test.stopTest();

        System.assertEquals(OTC_VALUE, reloadOtc(ql.Id), 'OTC should be preserved for non-amendment quotes.');
    }

    /***********************************************************************************************
    *
    * Getter Methods for Shared Data
    *
    ***********************************************************************************************/

    /**
     * @description Retrieves an inserted Quote Line from the database.
     */
    private static SBQQ__QuoteLine__c getInsertedQuoteLine() {
        return [
            SELECT Id, SBQQ__Quantity__c
            FROM SBQQ__QuoteLine__c
            LIMIT 1
        ];
    }

    /**
     * @description Creates a new SBQQ__Quote__c with the given Type and Source_System for OTC tests.
     */
    private static SBQQ__Quote__c createQuote(String quoteType, String sourceSystem) {
        if (cachedOpportunityId == null) {
            cachedOpportunityId = [SELECT Id FROM Opportunity LIMIT 1].Id;
        }
        return (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = cachedOpportunityId,
                SBQQ__Type__c = quoteType,
                Source_System__c = sourceSystem
            ),
            'SBQQQuoteDefaults'
        );
    }

    /**
     * @description Builds (does not insert) a quote line with the given OTC value.
     */
    private static SBQQ__QuoteLine__c buildOtcQuoteLine(Id quoteId, Decimal otc) {
        if (cachedProductId == null) {
            cachedProductId = [SELECT Id FROM Product2 LIMIT 1].Id;
        }
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = cachedProductId,
            SBQQ__Quantity__c = 1,
            SBQQ__CustomerPrice__c = 100,
            One_Time_Credit__c = otc
        );
    }

    /**
     * @description Reloads the One_Time_Credit__c value for a quote line from the database.
     */
    private static Decimal reloadOtc(Id quoteLineId) {
        return [
            SELECT One_Time_Credit__c FROM SBQQ__QuoteLine__c WHERE Id = :quoteLineId
        ].One_Time_Credit__c;
    }
}