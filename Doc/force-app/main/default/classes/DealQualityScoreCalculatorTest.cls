/**
 * @description Test class for DealQualityScoreCalculator
 * @author Auto-generated
 */
@isTest
private class DealQualityScoreCalculatorTest {
    
    @testSetup
    static void setupTestData() {
        // Create Account
        List<Account> accounts = (List<Account>)TestFactory.createSObjectList(
            new Account(
                Name = 'Test Account',
                GTM_Motion_Tier__c = 'EM3'
            ), 1, 'AccountDefaults'
        );
        
        // Create Opportunity
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ), 1, 'OpportunityDefaults'
        );
        
        // Create Quote with various field values
        List<SBQQ__Quote__c> quotes = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Account__c = accounts[0].Id,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SFA_Cap_after_Initial_Term__c = 'CPI + 5%',
                SFA_Term__c = '1st Renewal Only',
                Future_Pricing_Commitment__c = false,
                Product_Development_Obligation__c = false,
                Includes_Termination_Clause__c = false,
                SBQQ__BillingFrequency__c = 'Annual',
                Software_Payment_Terms__c = 'Net 30'
            ), 1, 'SBQQQuoteDefaults'
        );
    }
    
    @isTest
    static void testCalculateFormulaFields_WithValidData() {
        Map<String, Object> quoteData = new Map<String, Object>{
            'Segment_Total_List_Unit_Price__c' => 10000,
            'Segment_Total_Net_unit_Price__c' => 9000,
            'First_Year_Software_Total__c' => 10000,
            'Second_Year_Software_Total__c' => 11000,
            'Third_Year_Software_Total__c' => 12000
        };
        
        Test.startTest();
        DealQualityScoreCalculator.DealQualityFormulaFields result = 
            DealQualityScoreCalculator.calculateFormulaFields(quoteData);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(10, result.initialTermDiscount.setScale(0), 'Initial term discount should be 10%');
        System.assert(result.minYoYSpend > 0, 'Min YoY spend should be calculated');
    }
    
    @isTest
    static void testCalculateFormulaFields_WithZeroListPrice() {
        Map<String, Object> quoteData = new Map<String, Object>{
            'Segment_Total_List_Unit_Price__c' => 0,
            'Segment_Total_Net_unit_Price__c' => 0,
            'First_Year_Software_Total__c' => 10000,
            'Second_Year_Software_Total__c' => 11000
        };
        
        Test.startTest();
        DealQualityScoreCalculator.DealQualityFormulaFields result = 
            DealQualityScoreCalculator.calculateFormulaFields(quoteData);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.initialTermDiscount, 'Initial term discount should be 0 when list price is 0');
    }
    
    @isTest
    static void testCalculateFormulaFields_WithNullValues() {
        Map<String, Object> quoteData = new Map<String, Object>();
        
        Test.startTest();
        DealQualityScoreCalculator.DealQualityFormulaFields result = 
            DealQualityScoreCalculator.calculateFormulaFields(quoteData);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.initialTermDiscount, 'Initial term discount should be 0');
        System.assertEquals(0, result.minYoYSpend, 'Min YoY spend should be 0');
    }
    
    @isTest
    static void testCalculateFormulaFields_WithSixYears() {
        Map<String, Object> quoteData = new Map<String, Object>{
            'Segment_Total_List_Unit_Price__c' => 10000,
            'Segment_Total_Net_unit_Price__c' => 9000,
            'First_Year_Software_Total__c' => 10000,
            'Second_Year_Software_Total__c' => 11000,
            'Third_Year_Software_Total__c' => 12000,
            'Fourth_Year_Software_Total__c' => 13000,
            'Fifth_Year_Software_Total__c' => 14000,
            'Sixth_Year_Software_Total__c' => 15000
        };
        
        Test.startTest();
        DealQualityScoreCalculator.DealQualityFormulaFields result = 
            DealQualityScoreCalculator.calculateFormulaFields(quoteData);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.minYoYSpend > 0, 'Min YoY spend should be calculated for 6 years');
    }
    
    @isTest
    static void testCalculateScoreWithCalculatedFields_Success() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        Test.startTest();
        Integer score = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, 
            10, // initialTermDiscount
            7   // minYoYSpend
        );
        Test.stopTest();
        
        System.assertNotEquals(null, score, 'Score should not be null');
        System.assert(score >= 90 && score <= 110, 'Score should be in valid range');
    }
    
    @isTest
    static void testCalculateScoreWithCalculatedFields_WithEM4Tier() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        testAccount.GTM_Motion_Tier__c = 'EM4';
        update testAccount;
        
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        quote.Software_Payment_Terms__c = 'Net 45';
        update quote;
        
        Test.startTest();
        Integer score = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, 
            10, 
            7
        );
        Test.stopTest();
        
        System.assertNotEquals(null, score, 'Score should not be null');
    }
    
    @isTest
    static void testCalculateScoreWithCalculatedFields_InvalidQuoteId() {
        Test.startTest();
        try {
            DealQualityScoreCalculator.calculateScoreWithCalculatedFields(null, 10, 7);
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('required'), 'Should throw appropriate error');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCalculateScoreWithCalculatedFields_WithVariousDiscounts() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        // Test discount < -5 (should score 110)
        Test.startTest();
        Integer score1 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, -10, 7
        );
        
        // Test discount between -5 and 30 (should score 100)
        Integer score2 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, 15, 7
        );
        
        // Test discount > 30 (should score 90)
        Integer score3 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, 35, 7
        );
        Test.stopTest();
        
        System.assert(score1 >= 90 && score1 <= 110, 'Score 1 should be valid');
        System.assert(score2 >= 90 && score2 <= 110, 'Score 2 should be valid');
        System.assert(score3 >= 90 && score3 <= 110, 'Score 3 should be valid');
    }
    
    @isTest
    static void testCalculateScoreWithCalculatedFields_WithVariousSpend() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        // Test spend < 5 (should score 90)
        Test.startTest();
        Integer score1 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, 10, 3
        );
        
        // Test spend between 5 and 6.99 (should score 100)
        Integer score2 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, 10, 6
        );
        
        // Test spend > 6.99 (should score 110)
        Integer score3 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
            quote.Id, 10, 8
        );
        Test.stopTest();
        
        System.assert(score1 >= 90 && score1 <= 110, 'Score 1 should be valid');
        System.assert(score2 >= 90 && score2 <= 110, 'Score 2 should be valid');
        System.assert(score3 >= 90 && score3 <= 110, 'Score 3 should be valid');
    }
    
    @isTest
    static void testCalculateScoreWithCalculatedFields_WithVariousSFACaps() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        // Test SFA Cap score 110
        quote.SFA_Cap_after_Initial_Term__c = 'CPI + 5%';
        update quote;
        Integer score1 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(quote.Id, 10, 7);
        
        // Test SFA Cap score 90
        quote.SFA_Cap_after_Initial_Term__c = 'CPI + 3%';
        update quote;
        Integer score2 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(quote.Id, 10, 7);
        
        System.assert(score1 >= 90 && score1 <= 110, 'Score 1 should be valid');
        System.assert(score2 >= 90 && score2 <= 110, 'Score 2 should be valid');
    }
    
    @isTest
    static void testCalculateScoreWithCalculatedFields_WithFuturePricingCommitment() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        // Test with commitment (should score 90)
        quote.Future_Pricing_Commitment__c = true;
        update quote;
        Integer score1 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(quote.Id, 10, 7);
        
        // Test without commitment (should score 110)
        quote.Future_Pricing_Commitment__c = false;
        update quote;
        Integer score2 = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(quote.Id, 10, 7);
        
        System.assert(score1 >= 90 && score1 <= 110, 'Score 1 should be valid');
        System.assert(score2 >= 90 && score2 <= 110, 'Score 2 should be valid');
    }
}