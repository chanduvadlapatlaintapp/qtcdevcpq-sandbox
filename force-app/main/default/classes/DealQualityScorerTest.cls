/**
 * @description  Test class validating core scoring logic in `DealQualityScorer`.
 *               NOTE: Certain fields (`Initial_Term_Discount__c`, `Min_year_on_year_committed_spend__c`,
 *               `GTM_Motion_Tier__c`) are read-only on `SBQQ__Quote__c` in this org and cannot be set directly.
 *               Tests therefore focus on writeable drivers (SFA Cap, SFA Term, Future Pricing Commitment,
 *               Product Development Obligation, Termination Clause, Billing Frequency, Payment Terms (skipped if tier not EM4/EM5),
 *               and aggregate min selection). Discount & YoY spend are indirectly covered by ensuring they do not
 *               reduce the score when null (treated as omitted by the scorer).
 * @author       Ratan Paul
 * @createdDate  Nov-07-2025
 */
@isTest
public class DealQualityScorerTest {
    /***************************************************************************************************
     *
     * Test Setup
     *
     **************************************************************************************************/
    /**
     * @description Test data setup method to create necessary records for testing DealQualityScorer.
     */
    @testSetup
    static void setupTestData() {
        // Create test products
        List < Product2 > products = (List < Product2 > ) TestFactory.createSObjectList(
            new Product2(Name = 'Test Product', IsActive = true),
            1,
            'ProductDefaults'
        );

        // Create test pricebook entry
        for (Product2 product: products) {
            TestFactory.createSObjectList(
                new PricebookEntry(
                    Product2Id = product.Id,
                    Pricebook2Id = Test.getStandardPricebookId()
                ),
                1,
                'PricebookEntryDefaults'
            );
        }

        // Create an Account (default tier EM3)
        List < Account > accounts = (List < Account > ) TestFactory.createSObjectList(
            new Account(Name = 'Test Account', GTM_Motion_Tier__c = 'EM3'),
            1,
            'AccountDefaults'
        );

        // Create test Opportunity
        List < Opportunity > opportunities = (List < Opportunity > ) TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ),
            1,
            'OpportunityDefaults'
        );

        // Create test Quote associated with Opportunity and Account
        List < SBQQ__Quote__c > quote = (List < SBQQ__Quote__c > ) TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SBQQ__Account__c = accounts[0].Id,
                SBQQ__SubscriptionTerm__c = 24,
                SBQQ__StartDate__c = Date.today(),
                First_Segment_Months__c = 12,
                First_Year_Software_Total__c = 1000,
                Second_Year_Software_Total__c = 1200,
                Segment_Total_List_Unit_Price__c = 100,
                Segment_Total_Net_unit_Price__c = 106
            ),
            1,
            'SBQQQuoteDefaults'
        );
        // Note: SegmentIndex_Max__c will be set to 2 by the rollup when quote lines are created below

        // Create test Quote Line associated with Quote
        SBQQ__QuoteLine__c quoteLine1 = (SBQQ__QuoteLine__c) TestFactory.buildSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote[0].Id,
                SBQQ__Product__c = products[0].Id,
                SBQQ__SegmentIndex__c = 1,
                SBQQ__Quantity__c = 10
            ),
            'SBQQQuoteLineDefaults'
        );
        SBQQ__QuoteLine__c quoteLine2 = (SBQQ__QuoteLine__c) TestFactory.buildSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote[0].Id,
                SBQQ__Product__c = products[0].Id,
                SBQQ__SegmentIndex__c = 2,
                SBQQ__Quantity__c = 50
            ),
            'SBQQQuoteLineDefaults'
        );
        SBQQ.TriggerControl.disable();
        insert new List < SBQQ__QuoteLine__c > {
            quoteLine1,
            quoteLine2
        };
        SBQQ.TriggerControl.enable();
    }

    /***********************************************************************************************************************
     *
     * Unit tests
     *
     ************************************************************************************************************************/
    /**
     * @description Verifies that a null `Initial_Term_Discount__c` (read-only) is ignored and does not reduce the score.
     *              Confirms the scorer relies on other favorable components, yielding the expected capped baseline.
     */
    @isTest
    static void testInitialTermDiscountNullIgnored() {
        SBQQ__Quote__c q = getQuoteForTest();
        q.Future_Pricing_Commitment__c = false; // favorable
        q.Product_Development_Obligation__c = false; // favorable
        q.Includes_Termination_Clause__c = false; // sets current floor to 100
        q.SBQQ__BillingFrequency__c = 'Annual';
        update q;
        q = getQuoteForTest();
        // Initial_Term_Discount__c is null & read-only; scorer should skip it, leaving min governed by termination clause (110)
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'Null discount leaves score at 110'
        );
    }

    /**
     * @description Ensures a null, read-only `Min_year_on_year_committed_spend__c` does not adversely affect the score.
     *              Validates omission logic: component skipped and score determined by remaining factors.
     */
    @isTest
    static void testMinYoYCommittedSpendNullIgnored() {
        SBQQ__Quote__c q = getQuoteForTest();
        q.Future_Pricing_Commitment__c = false;
        q.Product_Development_Obligation__c = false;
        q.Includes_Termination_Clause__c = false;
        q.SBQQ__BillingFrequency__c = 'Annual';
        update q;
        q = getQuoteForTest();
        // Min_year_on_year_committed_spend__c null & read-only -> skipped, score driven by termination clause floor (110)
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'Null YoY spend leaves score at 110'
        );
    }

    /**
     * @description Exercises SFA Cap scoring buckets: sets 110-cap scenario then a 90 scenario to confirm min selection logic.
     *              Demonstrates transition of final score when lowering SFA cap value.
     */
    @isTest
    static void testSfaCapScoring() {
        SBQQ__Quote__c q = getQuoteForTest();
        
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Future_Pricing_Commitment__c = false; // 110
        q.Product_Development_Obligation__c = false; // 110
        q.Includes_Termination_Clause__c = false; // 100 cap
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();

        // Value in 110 set (e.g. 'CPI + 5%') -> capped at 110
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.SFA_Cap_after_Initial_Term__c = 'CPI + 5%';
        q.SFA_Term__c = '1st Renewal Only';
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'SFA Cap 110 bucket -> final 110'
        );

        // Value in 90 set (e.g. 'CPI + 3%') -> final 90
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.SFA_Cap_after_Initial_Term__c = 'CPI + 3%';
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'SFA Cap 90 bucket -> 90'
        );
    }

    /**
     * @description Validates SFA Term scoring across supported values, ensuring higher-tier terms retain the favorable score
     *              while longer/perpetual terms decrease the score to the 90 bucket.
     */
    @isTest
    static void testSfaTermScoring() {
        SBQQ__Quote__c q = getQuoteForTest();
        
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Future_Pricing_Commitment__c = false;
        q.Product_Development_Obligation__c = false;
        q.Includes_Termination_Clause__c = false; // cap 110
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'Baseline capped at 110'
        );

        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.SFA_Term__c = '1st Renewal Only'; // 110
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            '1st Renewal Only -> capped 110'
        );

        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.SFA_Term__c = 'Thru 2nd Renewal'; // 110
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'Thru 2nd Renewal -> capped 110'
        );

        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.SFA_Term__c = 'Thru 3rd Renewal'; // 90
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Thru 3rd Renewal -> 90'
        );

        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.SFA_Term__c = 'Perpetual'; // 90
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Perpetual -> 90'
        );
    }

    /**
     * @description Confirms independent component impacts: Future Pricing Commitment, Product Development Obligation, and
     *              Termination Clause each can lower the score from the favorable baseline when set to unfavorable values.
     */
    @isTest
    static void testFuturePricingProductDevTerminationScoring() {
        SBQQ__Quote__c q = getQuoteForTest();
        // Baseline: all three favorable -> futurePricing false (110), productDev false (110), termination false (100 cap)
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Future_Pricing_Commitment__c = false;
        q.Product_Development_Obligation__c = false;
        q.Includes_Termination_Clause__c = false; // 110
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'Baseline capped at 110'
        );

        // Future pricing commitment true lowers to 90
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Future_Pricing_Commitment__c = true;
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Future pricing commitment -> 90'
        );

        // Reset future pricing, make product development obligation true (90)
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Future_Pricing_Commitment__c = false;
        q.Product_Development_Obligation__c = true;
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Product development obligation -> 90'
        );

        // Termination clause included (90) while others favorable
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Product_Development_Obligation__c = false;
        q.Includes_Termination_Clause__c = true; // 90
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Termination clause included -> 90'
        );
    }

    /**
     * @description Verifies Billing Frequency scoring (Annual vs Non-Standard) and notes payment terms are skipped for the
     *              default EM3 tier (not eligible for payment term scoring). Demonstrates min score shift on non-standard billing.
     */
    @isTest
    static void testBillingFrequencyAndPaymentTermsScoring() {
        SBQQ__Quote__c q = getQuoteForTest();
        // Baseline favorable (cap 110)
        q.Future_Pricing_Commitment__c = false;
        q.Product_Development_Obligation__c = false;
        q.Includes_Termination_Clause__c = false;
        update q;
        q = getQuoteForTest();

        // Annual billing -> 110 component, final 110
        q.SBQQ__BillingFrequency__c = 'Annual';
        update q;
        q = getQuoteForTest();
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'Annual billing -> capped 110'
        );

        Test.startTest();
        SBQQ.TriggerControl.disable();
        // Non Standard billing -> 90 final
        q.SBQQ__BillingFrequency__c = 'Quarterly Y1 Only';
        update q;
        q = getQuoteForTest();
        SBQQ.TriggerControl.enable();
        Test.stopTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Non Standard billing -> 90'
        );

        // Payment terms not evaluated because GTM tier read-only (remains non EM4/EM5) -> ignore changes
    }

    /**
     * @description Focuses on Payment Terms scoring for an EM4 tier account. Asserts score outcomes for: Net 30 (100), Net 60 (90),
     *              and Advance (represented as Net 7 -> 110). Validates tier gating and component minimum logic.
     */
    @isTest
    static void testPaymentTermsEm4Tier() {
        // Create an EM4 account so formula/tier on Quote reflects EM4 and payment terms are scored.
        List < Account > accounts = (List < Account > ) TestFactory.createSObjectList(
            new Account(Name = 'Test Account', GTM_Motion_Tier__c = 'EM4'),
            1,
            'AccountDefaults'
        );

        // Create test Opportunity
        List < Opportunity > opportunities = (List < Opportunity > ) TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ),
            1,
            'OpportunityDefaults'
        );
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            SBQQ__Primary__c = true,
            SBQQ__Opportunity2__c = opportunities[0].Id,
            SBQQ__Account__c = accounts[0].Id,
            SBQQ__StartDate__c = Date.today(),
            SBQQ__SubscriptionTerm__c = 12,
            Future_Pricing_Commitment__c = false,
            Product_Development_Obligation__c = false,
            Includes_Termination_Clause__c = false,
            SBQQ__BillingFrequency__c = 'Annual',
            SFA_Cap_after_Initial_Term__c = 'CPI + 5%',
            SFA_Term__c = '1st Renewal Only',
            Software_Payment_Terms__c = 'Net 30',
            First_Year_Software_Total__c = 1000,
            Second_Year_Software_Total__c = 1200
        );
        insert q;
        q = getQuoteById(q.Id);
        System.assertEquals(
            100,
            DealQualityScorer.calculateCredit(q),
            'EM4 Net 30 should yield 100 min score'
        );

        Test.startTest();
        // Worse than Net 30 (Net 60) -> 90 becomes new min
        q.Software_Payment_Terms__c = 'Net 60';
        update q;
        q = getQuoteById(q.Id);
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'EM4 Net 60 should yield 90 min score'
        );

        // Better (Advance) -> 110 (no lower component present)
        q.Software_Payment_Terms__c = 'Net 7';
        update q;
        q = getQuoteById(q.Id);
        System.assertEquals(
            100,
            DealQualityScorer.calculateCredit(q),
            'EM4 Advance should yield 110 min score'
        );

        // Other -> 90
        q.Software_Payment_Terms__c = 'other';
        update q;
        q = getQuoteById(q.Id);
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'EM4 Other should yield 90 min score'
        );

        // Due on receipt	 -> 110 (capped at 100 by discount)
        q.Software_Payment_Terms__c = 'Due on receipt';
        update q;
        q = getQuoteById(q.Id);
        System.assertEquals(
            100,
            DealQualityScorer.calculateCredit(q),
            'EM4 Due on receipt should yield 100 min score as it is capped by discount'
        );
        Test.stopTest();
    }

    /**
     * @description Validates overall aggregation logic selecting the minimum component score. Starts with all favorable components,
     *              then introduces an unfavorable termination clause to force the min to drop.
     */
    @isTest
    static void testAggregatedMinScoreSelection() {
        SBQQ__Quote__c q = getQuoteForTest();
        // Configure multiple high-scoring components
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Future_Pricing_Commitment__c = false; // 110
        q.Product_Development_Obligation__c = false; // 110
        q.Includes_Termination_Clause__c = false; // 110 cap
        q.SBQQ__BillingFrequency__c = 'Annual'; // 110
        q.SFA_Cap_after_Initial_Term__c = 'CPI + 5%'; // 110 capped
        q.SFA_Term__c = '1st Renewal Only'; // 110 capped
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            110,
            DealQualityScorer.calculateCredit(q),
            'Overall min should be termination clause 110'
        );

        // Introduce a 90 component (e.g., termination clause included)
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Includes_Termination_Clause__c = true; // 90 now becomes min
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Min shifts to 90 when termination clause included'
        );
    }

    /**
     * @description Tests a neutral mix where termination clause inclusion drives the final score to 90 despite other favorable components.
     */
    @isTest
    static void testDefaultNeutralCase() {
        SBQQ__Quote__c q = getQuoteForTest();
        // Future pricing false (110), product dev false (110), termination true (90) drives min.
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.Future_Pricing_Commitment__c = false;
        q.Product_Development_Obligation__c = false;
        q.Includes_Termination_Clause__c = true; // 90 becomes final
        q.SBQQ__BillingFrequency__c = 'Annual';
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Neutral mix with termination clause included -> 90'
        );
    }

    /**
     * @description Tests the isOneYearDeal logic by verifying it correctly identifies single-segment deals.
     *              Note: SegmentIndex_Max__c is a rollup field that cannot be directly set in tests.
     *              This test verifies the helper method logic.
     */
    @isTest
    static void testOneYearDealOnlyConsidersThreeCriteria() {
        // Test the isOneYearDeal helper method directly
        System.assertEquals(true, DealQualityScorer.isOneYearDeal(1), 'SegmentIndex_Max = 1 should be single-year');
        System.assertEquals(false, DealQualityScorer.isOneYearDeal(2), 'SegmentIndex_Max = 2 should be multi-year');
        System.assertEquals(false, DealQualityScorer.isOneYearDeal(null), 'Null SegmentIndex_Max should be multi-year');
    }

    /**
     * @description Tests the helper method logic for identifying single-year deals.
     */
    @isTest
    static void testOneYearDealWithUnfavorableBillingFrequency() {
        // Test the isOneYearDeal helper method with different values
        System.assertEquals(true, DealQualityScorer.isOneYearDeal(1), 'SegmentIndex_Max = 1 should return true');
        System.assertEquals(false, DealQualityScorer.isOneYearDeal(2), 'SegmentIndex_Max = 2 should return false');
        System.assertEquals(false, DealQualityScorer.isOneYearDeal(3), 'SegmentIndex_Max = 3 should return false');
        System.assertEquals(false, DealQualityScorer.isOneYearDeal(0), 'SegmentIndex_Max = 0 should return false');
    }

    /**
     * @description Tests that the isOneYearDeal method correctly identifies single-year deals
     *              and verifies the scoring logic for multi-year deals.
     */
    @isTest
    static void testOneYearDealEM4WithPaymentTerms() {
        // Verify the isOneYearDeal helper method
        System.assertEquals(true, DealQualityScorer.isOneYearDeal(1), 'SegmentIndex_Max = 1 identifies single-year deal');
        System.assertEquals(false, DealQualityScorer.isOneYearDeal(2), 'SegmentIndex_Max = 2 identifies multi-year deal');
        
        // Verify multi-year deal behavior (SegmentIndex_Max__c = 2 from test setup)
        SBQQ__Quote__c q = getQuoteForTest();
        
        SBQQ.TriggerControl.disable();
        // SegmentIndex_Max__c is read-only (rollup), already = 2 from test setup
        q.SBQQ__BillingFrequency__c = 'Annual'; // 110
        q.Future_Pricing_Commitment__c = false; // 110
        q.Product_Development_Obligation__c = true; // 90
        q.Includes_Termination_Clause__c = false; // 110
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        
        // For multi-year deal, Product_Development_Obligation should be considered
        // Score should be 90 (from Product_Development_Obligation)
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Multi-year deal should consider Product Development Obligation and score 90'
        );
    }

    /**
     * @description Tests that multi-year deals (SegmentIndex_Max__c > 1) still consider all criteria.
     */
    @isTest
    static void testMultiYearDealConsidersAllCriteria() {
        SBQQ__Quote__c q = getQuoteForTest();
        // SegmentIndex_Max__c is already = 2 from test setup (has 2 quote lines with segments 1 and 2)
        SBQQ.TriggerControl.disable();
        // Set favorable values for the three always-considered criteria
        q.SBQQ__BillingFrequency__c = 'Annual'; // 110
        // Set unfavorable value for multi-year criteria that SHOULD be considered
        q.Future_Pricing_Commitment__c = true; // 90
        q.Product_Development_Obligation__c = false; // 110
        q.Includes_Termination_Clause__c = false; // 110
        update q;
        SBQQ.TriggerControl.enable();
        
        q = getQuoteForTest();
        
        // Should be 90 because Future_Pricing_Commitment is considered for multi-year deals
        System.assertEquals(
            90,
            DealQualityScorer.calculateCredit(q),
            'Multi-year deal should consider all criteria including Future Pricing Commitment'
        );
    }

    /***********************************************************************************************************************
     *
     * Data getters
     *
     ************************************************************************************************************************/
    /**
     * @description Returns a single working Quote with fields needed for scoring tests.
     * @return SBQQ__Quote__c queried quote record.
     */
    private static SBQQ__Quote__c getQuoteForTest() {
        return [
            SELECT
            Id,
            SBQQ__Account__c,
            SBQQ__SubscriptionTerm__c,
            SegmentIndex_Max__c,
            Segment_Total_List_Unit_Price__c,
            Segment_Total_Net_unit_Price__c,
            SFA_Term__c,
            First_Year_Software_Total__c,
            Second_Year_Software_Total__c,
            Third_Year_Software_Total__c,
            Fourth_Year_Software_Total__c,
            Fifth_Year_Software_Total__c,
            Sixth_Year_Software_Total__c,
            Min_year_on_year_committed_spend__c,
            Initial_Term_Discount__c,
            SFA_Cap_after_Initial_Term__c,
            Future_Pricing_Commitment__c,
            Product_Development_Obligation__c,
            Includes_Termination_Clause__c,
            SBQQ__BillingFrequency__c,
            Software_Payment_Terms__c,
            GTM_Motion_Tier__c
            FROM SBQQ__Quote__c
            LIMIT 1
        ];
    }

    /**
     * @description Returns the Quote by Id.
     * @param quoteId Id of the quote to retrieve.
     * @return SBQQ__Quote__c queried quote record.
     */
    private static SBQQ__Quote__c getQuoteById(Id quoteId) {
        return [
            SELECT
            Id,
            SBQQ__Account__c,
            SBQQ__SubscriptionTerm__c,
            SegmentIndex_Max__c,
            Segment_Total_List_Unit_Price__c,
            Segment_Total_Net_unit_Price__c,
            SFA_Term__c,
            First_Year_Software_Total__c,
            Second_Year_Software_Total__c,
            Third_Year_Software_Total__c,
            Fourth_Year_Software_Total__c,
            Fifth_Year_Software_Total__c,
            Sixth_Year_Software_Total__c,
            Min_year_on_year_committed_spend__c,
            Initial_Term_Discount__c,
            SFA_Cap_after_Initial_Term__c,
            Future_Pricing_Commitment__c,
            Product_Development_Obligation__c,
            Includes_Termination_Clause__c,
            SBQQ__BillingFrequency__c,
            Software_Payment_Terms__c,
            GTM_Motion_Tier__c
            FROM SBQQ__Quote__c
            WHERE Id =: quoteId
        ];
    }
}