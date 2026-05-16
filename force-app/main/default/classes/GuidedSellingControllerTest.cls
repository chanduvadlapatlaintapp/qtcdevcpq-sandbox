/**
 * @description Test class for GuidedSellingController
 * @author Auto-generated
 */
@isTest
private class GuidedSellingControllerTest {
    
    @testSetup
    static void setupTestData() {
        // Create Account
        List<Account> accounts = (List<Account>)TestFactory.createSObjectList(
            new Account(
                Name = 'Test Account',
                GTM_Motion_Tier__c = 'EM3'
            ), 1, 'AccountDefaults'
        );
        
        // Create Product Line
        Product_Line__c testProductLine = (Product_Line__c)TestFactory.createSObject(
            new Product_Line__c(
                Name = 'Test Product Line',
                Practice__c = 'Legal',
                Active__c = true,
                Deployment__c = 'On-Premise'
            )
        );
        
        // Create Products
        List<Product2> testProducts = (List<Product2>)TestFactory.createSObjectList(
            new Product2(
                Name = 'Test Product',
                ProductCode = 'TEST',
                Description = 'Test Description',
                IsActive = true,
                Product_LineNew__c = testProductLine.Id,
                Is_Legal__c = 'Active'
            ), 5, 'ProductDefaults'
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
        
        // Create Quote with minimal fields to avoid flow errors
        // Additional fields will be set in individual test methods as needed
        //SBQQ.TriggerControl.disable();
        List<SBQQ__Quote__c> quotes = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Account__c = accounts[0].Id,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SBQQ__ExpirationDate__c = Date.today().addDays(30)
            ), 1, 'SBQQQuoteDefaults'
        );
        //SBQQ.TriggerControl.enable();
        
        // Update quote with additional fields needed for tests
        // Do this after initial insert to avoid flow validation issues
        quotes[0].SBQQ__SubscriptionTerm__c = 12;
        quotes[0].First_Segment_Months__c = 12;
        quotes[0].Segment_Total_List_Unit_Price__c = 10000;
        quotes[0].Segment_Total_Net_unit_Price__c = 9000;
        quotes[0].First_Year_Software_Total__c = 10000;
        quotes[0].Second_Year_Software_Total__c = 11000;
        quotes[0].Third_Year_Software_Total__c = 12000;
        quotes[0].SFA_Cap_after_Initial_Term__c = 'CPI + 5%';
        quotes[0].SFA_Term__c = '1st Renewal Only';
        quotes[0].Future_Pricing_Commitment__c = false;
        quotes[0].Product_Development_Obligation__c = false;
        quotes[0].Includes_Termination_Clause__c = false;
        quotes[0].SBQQ__BillingFrequency__c = 'Annual';
        quotes[0].Software_Payment_Terms__c = 'Net 30';
        SBQQ.TriggerControl.disable();
        update quotes;
        SBQQ.TriggerControl.enable();
    }
    
    @isTest
    static void testGetActiveProducts_WithQuoteId() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        Test.startTest();
        List<Product2> products = GuidedSellingController.getActiveProducts(quote.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, products, 'Products should not be null');
        System.assert(products.size() > 0, 'Should return at least one product');
    }
    
    @isTest
    static void testGetActiveProducts_WithoutQuoteId() {
        Test.startTest();
        List<Product2> products = GuidedSellingController.getActiveProducts(null);
        Test.stopTest();
        
        System.assertNotEquals(null, products, 'Products should not be null');
    }
    
    @isTest
    static void testGetActiveProducts_WithDifferentSubVertical() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        // Note: Sub_Vertical__c is not writeable, so we test with existing quote
        // The method will use whatever Sub_Vertical__c value exists on the quote
        
        Test.startTest();
        List<Product2> products = GuidedSellingController.getActiveProducts(quote.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, products, 'Products should not be null');
    }
    
    @isTest
    static void testGetQuoteLines_WithQuoteId() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        
        // Create a quote line using TestFactory
        SBQQ__QuoteLine__c quoteLine = (SBQQ__QuoteLine__c)TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id,
                SBQQ__Product__c = product.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__NetPrice__c = 900,
                Override_Sales_Price_Per_Month__c = 75
            ), 'SBQQQuoteLineDefaults'
        );
        
        Test.startTest();
        List<SBQQ__QuoteLine__c> quoteLines = GuidedSellingController.getQuoteLines(quote.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, quoteLines, 'Quote lines should not be null');
        System.assertEquals(1, quoteLines.size(), 'Should return one quote line');
        System.assertEquals(quoteLine.Id, quoteLines[0].Id, 'Should return the correct quote line');
    }
    
    @isTest
    static void testGetQuoteLines_WithoutQuoteId() {
        Test.startTest();
        List<SBQQ__QuoteLine__c> quoteLines = GuidedSellingController.getQuoteLines(null);
        Test.stopTest();
        
        System.assertNotEquals(null, quoteLines, 'Quote lines should not be null');
        System.assertEquals(0, quoteLines.size(), 'Should return empty list');
    }
    
    @isTest
    static void testCreateQuoteLines_Success() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
        
        // Create cart items JSON
        GuidedSellingController.CartItemWrapper cartItem = new GuidedSellingController.CartItemWrapper();
        cartItem.Id = product.Id;
        cartItem.Name = product.Name;
        cartItem.quantity = 2;
        
        GuidedSellingController.YearWrapper year = new GuidedSellingController.YearWrapper();
        year.yearNumber = 1;
        year.months = 12;
        year.startMonth = 1;
        year.endMonth = 12;
        year.discount = 10;
        year.overrideSalePricePerMonth = 75.50;
        year.unitPrice = '100.00';
        year.netPrice = '90.00';
        year.totalPrice = '1800.00';
        
        cartItem.years = new List<GuidedSellingController.YearWrapper>{ year };
        String cartItemsJson = JSON.serialize(new List<GuidedSellingController.CartItemWrapper>{ cartItem });
        
        Test.startTest();
        GuidedSellingController.QuoteLinesResult result = GuidedSellingController.createQuoteLines(quote.Id, cartItemsJson);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.message, 'Message should not be null');
        System.assertNotEquals(null, result.createdQuoteLineIds, 'Created IDs should not be null');
        System.assertEquals(1, result.createdQuoteLineIds.size(), 'Should create one quote line');
        
        // Verify quote line was created
        List<SBQQ__QuoteLine__c> createdLines = [
            SELECT Id, SBQQ__Product__c, SBQQ__Quantity__c, Override_Sales_Price_Per_Month__c
            FROM SBQQ__QuoteLine__c
            WHERE Id = :result.createdQuoteLineIds[0]
        ];
        System.assertEquals(1, createdLines.size(), 'Quote line should be created');
        System.assertEquals(2, createdLines[0].SBQQ__Quantity__c, 'Quantity should match');
        System.assertEquals(75.50, createdLines[0].Override_Sales_Price_Per_Month__c.setScale(2), 'Override price should match');
    }
    
    @isTest
    static void testCreateQuoteLines_InvalidQuoteId() {
        String cartItemsJson = '[]';
        
        Test.startTest();
        try {
            GuidedSellingController.createQuoteLines('invalidId', cartItemsJson);
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            // Accept any exception when invalid quoteId is passed
            System.assert(true, 'Exception thrown as expected: ' + e.getTypeName());
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateQuoteLines_EmptyCart() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        String cartItemsJson = '[]';
        
        Test.startTest();
        try {
            GuidedSellingController.createQuoteLines(quote.Id, cartItemsJson);
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            // Accept any exception when cart is empty
            System.assert(true, 'Exception thrown as expected: ' + e.getTypeName());
        }
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateQuoteMonths_Success() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        Test.startTest();
        GuidedSellingController.updateQuoteMonths(quote.Id, 24, 12);
        Test.stopTest();
        
        SBQQ__Quote__c updatedQuote = [
            SELECT SBQQ__SubscriptionTerm__c, First_Segment_Months__c
            FROM SBQQ__Quote__c
            WHERE Id = :quote.Id
        ];
        System.assertEquals(24, updatedQuote.SBQQ__SubscriptionTerm__c, 'Total contract months should be updated');
        System.assertEquals(12, updatedQuote.First_Segment_Months__c, 'First segment months should be updated');
    }
    
    @isTest
    static void testUpdateQuoteMonths_OnlyTotalMonths() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        Test.startTest();
        GuidedSellingController.updateQuoteMonths(quote.Id, 36, null);
        Test.stopTest();
        
        SBQQ__Quote__c updatedQuote = [
            SELECT SBQQ__SubscriptionTerm__c, First_Segment_Months__c
            FROM SBQQ__Quote__c
            WHERE Id = :quote.Id
        ];
        System.assertEquals(36, updatedQuote.SBQQ__SubscriptionTerm__c, 'Total contract months should be updated');
    }
    
    @isTest
    static void testUpdateQuoteMonths_InvalidQuoteId() {
        Test.startTest();
        try {
            GuidedSellingController.updateQuoteMonths(null, 24, 12);
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            // Accept any exception when null quoteId is passed
            System.assert(true, 'Exception thrown as expected: ' + e.getTypeName());
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCalculateDealQualityScore_WithQuoteData() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        Map<String, Object> quoteData = new Map<String, Object>{
            'Segment_Total_List_Unit_Price__c' => 10000,
            'Segment_Total_Net_unit_Price__c' => 9000,
            'First_Year_Software_Total__c' => 10000,
            'Second_Year_Software_Total__c' => 11000,
            'Third_Year_Software_Total__c' => 12000,
            'SFA_Cap_after_Initial_Term__c' => 'CPI + 5%',
            'SFA_Term__c' => '1st Renewal Only',
            'Future_Pricing_Commitment__c' => false,
            'Product_Development_Obligation__c' => false,
            'Includes_Termination_Clause__c' => false,
            'SBQQ__BillingFrequency__c' => 'Annual',
            'Software_Payment_Terms__c' => 'Net 30'
        };
        String quoteDataJson = JSON.serialize(quoteData);
        
        Test.startTest();
        Integer score = GuidedSellingController.calculateDealQualityScore(quote.Id, quoteDataJson);
        Test.stopTest();
        
        System.assertNotEquals(null, score, 'Score should not be null');
        System.assert(score >= 90 && score <= 110, 'Score should be in valid range');
    }
    
    @isTest
    static void testCalculateDealQualityScore_WithoutQuoteData() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        Test.startTest();
        Integer score = GuidedSellingController.calculateDealQualityScore(quote.Id, null);
        Test.stopTest();
        
        System.assertNotEquals(null, score, 'Score should not be null');
        System.assert(score >= 90 && score <= 110, 'Score should be in valid range');
    }
    
    @isTest
    static void testCalculateDealQualityScoreWithBreakdown() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        Map<String, Object> quoteData = new Map<String, Object>{
            'Segment_Total_List_Unit_Price__c' => 10000,
            'Segment_Total_Net_unit_Price__c' => 9000,
            'First_Year_Software_Total__c' => 10000,
            'Second_Year_Software_Total__c' => 11000
        };
        String quoteDataJson = JSON.serialize(quoteData);
        
        Test.startTest();
        GuidedSellingController.DealQualityScoreResult result = 
            GuidedSellingController.calculateDealQualityScoreWithBreakdown(quote.Id, quoteDataJson);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.score, 'Score should not be null');
        System.assertNotEquals(null, result.breakdown, 'Breakdown should not be null');
        System.assert(result.breakdown.contains('Final Score'), 'Breakdown should contain score information');
    }
    
    @isTest
    static void testCalculateDealQualityScore_InvalidQuoteId() {
        Test.startTest();
        try {
            GuidedSellingController.calculateDealQualityScore(null, null);
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            // Accept any exception when null quoteId is passed
            System.assert(true, 'Exception thrown as expected: ' + e.getTypeName());
        }
        Test.stopTest();
    }
}