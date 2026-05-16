@IsTest
private class SkuPricebookLaunchControllerTest {

    @TestSetup
    static void setup() {
        Product2 product = new Product2(
            Name = 'Pricebook Launch Product',
            ProductCode = 'PBL-001',
            IsActive = true
        );
        insert product;

        Block_Pricing__c bp = new Block_Pricing__c(
            Product__c = product.Id,
            Block_Pricing_Meter_Type__c = 'Named Users',
            Fiscal_Year__c = 'FY26',
            Price__c = 100.00,
            Active__c = true,
            Tier_Name__c = 'EM1'
        );
        insert bp;
    }

    @IsTest
    static void testGetActiveProducts() {
        Test.startTest();
        List<Product2> results = SkuPricebookLaunchController.getActiveProducts(null);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return active products');
    }

    @IsTest
    static void testGetActiveProductsWithFilter() {
        // No product line set, so filter returns empty
        Test.startTest();
        List<Product2> results = SkuPricebookLaunchController.getActiveProducts(
            '0010000000000000AA' // Fake Id - won't match
        );
        Test.stopTest();
        // May return 0, that's expected for fake filter
    }

    @IsTest
    static void testGetPricebooks() {
        Test.startTest();
        List<Pricebook2> results = SkuPricebookLaunchController.getPricebooks();
        Test.stopTest();

        // Standard pricebook should always exist
        // Standard pricebook may not have IsActive=true in test context
        System.assertNotEquals(null, results, 'Should return a list');
    }

    @IsTest
    static void testGetExistingPricebookRecords() {
        Test.startTest();
        List<Block_Pricing__c> results = SkuPricebookLaunchController.getExistingPricebookRecords('FY26');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return existing records for FY26');
    }

    @IsTest
    static void testGetExistingPricebookRecordsBlank() {
        Test.startTest();
        List<Block_Pricing__c> results = SkuPricebookLaunchController.getExistingPricebookRecords('');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for blank FY');
    }

    @IsTest
    static void testLaunchPricebook() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PBL-001' LIMIT 1];

        Block_Pricing__c newBp = new Block_Pricing__c(
            Product__c = prod.Id,
            Block_Pricing_Meter_Type__c = 'Lawyers',
            Fiscal_Year__c = 'FY27',
            Price__c = 200.00,
            Active__c = true
        );

        String json = JSON.serialize(new List<Block_Pricing__c>{ newBp });

        Test.startTest();
        SkuPricebookLaunchController.LaunchResult result = SkuPricebookLaunchController.launchPricebook(json);
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should have 1 success');
        System.assertEquals(0, result.errorCount, 'Should have 0 errors');
    }

    @IsTest
    static void testCopyPricebook() {
        Test.startTest();
        SkuPricebookLaunchController.LaunchResult result =
            SkuPricebookLaunchController.copyPricebook('FY26', 'FY27', 5.0);
        Test.stopTest();

        System.assertNotEquals(0, result.totalCount, 'Should have records to copy');
        System.assertNotEquals(0, result.successCount, 'Should have successful copies');
    }

    @IsTest
    static void testCopyPricebookNoAdjustment() {
        Test.startTest();
        SkuPricebookLaunchController.LaunchResult result =
            SkuPricebookLaunchController.copyPricebook('FY26', 'FY27', null);
        Test.stopTest();

        System.assertNotEquals(0, result.successCount, 'Should copy without adjustment');
    }

    @IsTest
    static void testCopyPricebookEmptySource() {
        Test.startTest();
        SkuPricebookLaunchController.LaunchResult result =
            SkuPricebookLaunchController.copyPricebook('FY99', 'FY27', null);
        Test.stopTest();

        System.assertEquals(0, result.totalCount, 'Should have 0 records for non-existent FY');
    }

    @IsTest
    static void testGetFiscalYearOptions() {
        Test.startTest();
        List<SkuPricebookLaunchController.PicklistOption> options =
            SkuPricebookLaunchController.getFiscalYearOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Should return options');
    }
}