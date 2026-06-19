/**
 * @description Test class for OsaSubscriptionSummaryController
 * @author      Satyanarayana Pusuluri
 * @date        2026-05-29
 * @jira        BIZ-81899
 */
@IsTest
private class OsaSubscriptionSummaryControllerTest {

    @TestSetup
    static void setup() {
        // Bypass flows and triggers to avoid Quote After Insert-Update failures in test context
        insert new Automation_Controls__c(
            SetupOwnerId      = UserInfo.getUserId(),
            Active__c         = true,
            Bypass_Flows__c   = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c   = true,
            Quoteline_Bypass__c = true
        );

        // Account
        Account acct = (Account) TestFactory.createSObject(
            new Account(Name = 'OSA Test Account', BillingCountry = 'United States')
        );

        // Opportunity
        Opportunity opp = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                AccountId   = acct.Id,
                Name        = 'OSA Test Opp',
                StageName   = 'Prospecting',
                CloseDate   = Date.today().addDays(30)
            )
        );

        // Product
        Product2 prod = (Product2) TestFactory.createSObject(
            new Product2(
                Name        = 'OSA Test Product',
                ProductCode = 'OSA-TEST-001',
                IsActive    = true
            )
        );

        // Quote
        SBQQ__Quote__c quote = (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Account__c                    = acct.Id,
                SBQQ__Opportunity2__c               = opp.Id,
                SBQQ__Type__c                       = 'Quote',
                SBQQ__Status__c                     = 'Draft',
                SBQQ__StartDate__c                  = Date.newInstance(2025, 10, 1),
                SBQQ__PricebookId__c                = Test.getStandardPricebookId(),
                Total_Subscription_Fees_Year_1__c   = 2032800,
                Total_Subscription_Fees_2nd_Year__c = 2263839.90,
                Total_Subscription_Fees_3rd_Year__c = 2601120,
                Total_Subscription_Fees_4th_Year__c = 0,
                Total_Subscription_Fees_5th_Year__c = 0,
                Total_Subscription_Fees_6th_Year__c = 0
            )
        );

        // Segment 1 line
        TestFactory.createSObject(new SBQQ__QuoteLine__c(
            SBQQ__Quote__c         = quote.Id,
            SBQQ__Product__c       = prod.Id,
            SBQQ__SegmentIndex__c  = 1,
            SBQQ__CustomerPrice__c = 7.49,
            SBQQ__Quantity__c      = 3000,
            Support_Level__c       = 'Premium'
        ));

        // Segment 2 line
        TestFactory.createSObject(new SBQQ__QuoteLine__c(
            SBQQ__Quote__c         = quote.Id,
            SBQQ__Product__c       = prod.Id,
            SBQQ__SegmentIndex__c  = 2,
            SBQQ__CustomerPrice__c = 7.87,
            SBQQ__Quantity__c      = 3000,
            Support_Level__c       = 'Premium'
        ));

        // Adjustment line (null segment index)
        TestFactory.createSObject(new SBQQ__QuoteLine__c(
            SBQQ__Quote__c         = quote.Id,
            SBQQ__Product__c       = prod.Id,
            SBQQ__SegmentIndex__c  = null,
            SBQQ__CustomerPrice__c = 15216.68,
            SBQQ__Quantity__c      = 1,
            Support_Level__c       = 'Standard'
        ));
    }

    @IsTest
    static void testGetOsaSummary_returnsAllSegments() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];

        Test.startTest();
        OsaSubscriptionSummaryController.OsaSummaryWrapper result =
            OsaSubscriptionSummaryController.getOsaSummary(quote.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Wrapper should not be null');
        System.assertEquals(7, result.segments.size(), 'Should have 7 groups: ADJ + 6 segments');
        System.assertEquals(
            2032800 + 2263839.90 + 2601120,
            result.netSubscriptionFees,
            'Net fees should sum Year 1 + Year 2 + Year 3'
        );
    }

    @IsTest
    static void testGetOsaSummary_segment1HasLines() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];

        Test.startTest();
        OsaSubscriptionSummaryController.OsaSummaryWrapper result =
            OsaSubscriptionSummaryController.getOsaSummary(quote.Id);
        Test.stopTest();

        // First group = Adjustments (null), second = Segment 1
        OsaSubscriptionSummaryController.SegmentGroup seg1 = result.segments[1];
        System.assertEquals(1, (Integer) seg1.segmentIndex, 'Segment index should be 1');
        System.assertEquals(1, seg1.lines.size(), 'Segment 1 should have 1 line');
        System.assertEquals(2032800, seg1.yearTotal, 'Year 1 total should match Quote field');
        System.assertNotEquals(null, seg1.lineSubtotal, 'Line subtotal should be populated');
    }

    @IsTest
    static void testGetOsaSummary_adjustmentGroup() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];

        Test.startTest();
        OsaSubscriptionSummaryController.OsaSummaryWrapper result =
            OsaSubscriptionSummaryController.getOsaSummary(quote.Id);
        Test.stopTest();

        OsaSubscriptionSummaryController.SegmentGroup adj = result.segments[0];
        System.assertEquals(null, adj.segmentIndex, 'Adjustment group index should be null');
        System.assertEquals(1, adj.lines.size(), 'Should have 1 adjustment line');
    }

    @IsTest
    static void testGetOsaSummary_emptySegmentsReturn() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        SBQQ__Quote__c quote = (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Account__c     = acct.Id,
                SBQQ__Opportunity2__c = opp.Id,
                SBQQ__Type__c        = 'Quote',
                SBQQ__Status__c      = 'Draft',
                SBQQ__StartDate__c   = Date.newInstance(2025, 10, 1),
                SBQQ__PricebookId__c = Test.getStandardPricebookId()
            )
        );

        Test.startTest();
        OsaSubscriptionSummaryController.OsaSummaryWrapper result =
            OsaSubscriptionSummaryController.getOsaSummary(quote.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Wrapper should not be null for quote with no lines');
        System.assertEquals(0, result.netSubscriptionFees, 'Net fees should be 0 with no year totals');
        System.assertEquals(6, result.segments.size(), 'Should have 6 segments with no lines');
    }
}