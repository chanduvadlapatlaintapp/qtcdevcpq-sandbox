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
        // BIZ-81462: Bypass Quote flows/triggers so amendment quotes can be inserted without
        // the "Quote After Insert-Update" flow failing on missing amendment context.
        // Quoteline_Bypass__c stays false so the QuoteLine trigger (and OTC gating) still fires.
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
    * BIZ-81462 - One-Time Credit amendment twin-field gating
    *
    ***********************************************************************************************/

    private static final Decimal OTC_VALUE = 1500;
    private static Id cachedProductId;
    private static Id cachedOpportunityId;

    /**
     * @description Amendment + Source_System = SFDC -> OTC must be preserved on insert.
     */
    @isTest
    static void otcPreservedForSfdcAmendment() {
        SBQQ__Quote__c quote = createAmendmentTestQuote(QuoteConstants.TYPE_AMENDMENT, 'SFDC');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [
            SELECT One_Time_Credit__c FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id
        ];
        System.assertEquals(
            OTC_VALUE,
            reloaded.One_Time_Credit__c,
            'OTC should be preserved for an SFDC-sourced amendment.'
        );
    }

    /**
     * @description Amendment + Source_System = OP4I -> OTC must be cleared on insert.
     */
    @isTest
    static void otcClearedForOp4iAmendment() {
        SBQQ__Quote__c quote = createAmendmentTestQuote(QuoteConstants.TYPE_AMENDMENT, 'OP4I');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [
            SELECT One_Time_Credit__c FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id
        ];
        System.assertEquals(
            null,
            reloaded.One_Time_Credit__c,
            'OTC should be cleared for a non-SFDC amendment.'
        );
    }

    /**
     * @description Amendment + Source_System = null -> strict-match rule clears OTC.
     */
    @isTest
    static void otcClearedForAmendmentWithNullSourceSystem() {
        SBQQ__Quote__c quote = createAmendmentTestQuote(QuoteConstants.TYPE_AMENDMENT, null);
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [
            SELECT One_Time_Credit__c FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id
        ];
        System.assertEquals(
            null,
            reloaded.One_Time_Credit__c,
            'OTC should be cleared when Source_System__c is null (strict SFDC match).'
        );
    }

    /**
     * @description Renewal + Source_System = SFDC -> OTC must be cleared (renewals never carry OTC).
     */
    @isTest
    static void otcClearedForSfdcRenewal() {
        SBQQ__Quote__c quote = createAmendmentTestQuote(QuoteConstants.TYPE_RENEWAL, 'SFDC');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [
            SELECT One_Time_Credit__c FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id
        ];
        System.assertEquals(
            null,
            reloaded.One_Time_Credit__c,
            'OTC should be cleared on renewal quote lines regardless of source system.'
        );
    }

    /**
     * @description Renewal + Source_System = OP4I -> OTC must be cleared.
     */
    @isTest
    static void otcClearedForOp4iRenewal() {
        SBQQ__Quote__c quote = createAmendmentTestQuote(QuoteConstants.TYPE_RENEWAL, 'OP4I');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [
            SELECT One_Time_Credit__c FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id
        ];
        System.assertEquals(
            null,
            reloaded.One_Time_Credit__c,
            'OTC should be cleared on renewal quote lines regardless of source system.'
        );
    }

    /**
     * @description Non-amendment, non-renewal quote -> gating must not touch OTC even if source is OP4I.
     */
    @isTest
    static void otcPreservedForNonAmendmentQuote() {
        SBQQ__Quote__c quote = createAmendmentTestQuote(QuoteConstants.TYPE_QUOTE, 'OP4I');
        SBQQ__QuoteLine__c ql = buildOtcQuoteLine(quote.Id, OTC_VALUE);

        Test.startTest();
        insert ql;
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [
            SELECT One_Time_Credit__c FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id
        ];
        System.assertEquals(
            OTC_VALUE,
            reloaded.One_Time_Credit__c,
            'OTC should be preserved for non-amendment quotes regardless of source system.'
        );
    }

    /**
     * @description Bulk insert across mixed quotes -> per-line gating applied correctly.
     */
    @isTest
    static void otcGatedPerLineInBulk() {
        SBQQ__Quote__c sfdcAmendment = createAmendmentTestQuote(QuoteConstants.TYPE_AMENDMENT, 'SFDC');
        SBQQ__Quote__c op4iAmendment = createAmendmentTestQuote(QuoteConstants.TYPE_AMENDMENT, 'OP4I');
        SBQQ__Quote__c renewal = createAmendmentTestQuote(QuoteConstants.TYPE_RENEWAL, 'OP4I');

        // Small bulk loop - the helper is verifiably bulk-safe (single SOQL with IN clause);
        // a larger loop just stresses unrelated ACV/OLI services and trips CPU limits.
        Integer linesPerQuote = 5;
        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();
        for (Integer i = 0; i < linesPerQuote; i++) {
            lines.add(buildOtcQuoteLine(sfdcAmendment.Id, OTC_VALUE));
            lines.add(buildOtcQuoteLine(op4iAmendment.Id, OTC_VALUE));
            lines.add(buildOtcQuoteLine(renewal.Id, OTC_VALUE));
        }

        Test.startTest();
        insert lines;
        Test.stopTest();

        Map<Id, SBQQ__QuoteLine__c> reloaded = new Map<Id, SBQQ__QuoteLine__c>([
            SELECT Id, SBQQ__Quote__c, One_Time_Credit__c
            FROM SBQQ__QuoteLine__c
            WHERE Id IN :lines
        ]);

        Integer cleared = 0;
        Integer preserved = 0;
        for (SBQQ__QuoteLine__c ql : reloaded.values()) {
            if (ql.SBQQ__Quote__c == sfdcAmendment.Id) {
                System.assertEquals(OTC_VALUE, ql.One_Time_Credit__c, 'SFDC amendment line should be preserved.');
                preserved++;
            } else {
                // Both OP4I amendment and renewal lines should be cleared.
                System.assertEquals(null, ql.One_Time_Credit__c, 'OP4I amendment & renewal lines should be cleared.');
                cleared++;
            }
        }
        System.assertEquals(linesPerQuote, preserved, 'Expected preserved SFDC-amendment lines = linesPerQuote.');
        System.assertEquals(linesPerQuote * 2, cleared, 'Expected cleared OP4I-amendment + renewal lines = linesPerQuote * 2.');
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
     * @description Creates a new SBQQ__Quote__c with the given Type and Source_System for OTC gating tests.
     */
    private static SBQQ__Quote__c createAmendmentTestQuote(String quoteType, String sourceSystem) {
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
     *              Caches Product Id at class level so bulk tests don't blow the SOQL limit.
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
}