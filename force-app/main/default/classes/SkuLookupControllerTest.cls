@IsTest
private class SkuLookupControllerTest {

    @TestSetup
    static void setupTestData() {
        Product_Line__c productLine = new Product_Line__c(
            Name = 'Test Product Line',
            Active__c = true,
            Deployment__c = 'Cloud',
            Practice__c = 'DealCloud'
        );
        insert productLine;

        Product_Rollup__c productRollup = new Product_Rollup__c(
            Name = 'Test Rollup',
            Product_Line__c = productLine.Id
        );
        insert productRollup;

        Item_Master_Product__c itemMaster = new Item_Master_Product__c(
            Name = 'IMP-TEST001',
            Item_Name__c = 'Test Item Master',
            Active__c = true,
            Product_LineNew__c = productLine.Id
        );
        insert itemMaster;

        Product2 product = new Product2(
            Name = 'Test SKU Product',
            ProductCode = 'TST-001',
            IsActive = true,
            Product_LineNew__c = productLine.Id,
            Item_Master_Product__c = itemMaster.Id
        );
        insert product;

        Id stdPricebookId = Test.getStandardPricebookId();

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true,
            UseStandardPrice = false
        );
        insert pbe;
    }

    @IsTest
    static void testSearchProducts() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProducts('Test SKU');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find at least one product');
        System.assertEquals('Test SKU Product', results[0].title, 'Product name should match');
    }

    @IsTest
    static void testSearchProductsShortTerm() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProducts('T');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for short search terms');
    }

    @IsTest
    static void testSearchProductsBlankTerm() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProducts('');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for blank search terms');
    }

    @IsTest
    static void testSearchProductsByCode() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProducts('TST-001');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find product by code');
    }

    @IsTest
    static void testSearchProductLines() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProductLines('Test Product');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find at least one product line');
        System.assertEquals('Test Product Line', results[0].title, 'Product line name should match');
    }

    @IsTest
    static void testSearchProductLinesShortTerm() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProductLines('T');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for short search terms');
    }

    @IsTest
    static void testSearchPricebooks() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchPricebooks('Standard');
        Test.stopTest();

        // Standard pricebook may or may not match depending on org setup
        System.assertNotEquals(null, results, 'Should return a non-null list');
    }

    @IsTest
    static void testSearchPricebooksShortTerm() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchPricebooks('S');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for short search terms');
    }

    @IsTest
    static void testSearchProductRollups() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProductRollups('Test Rollup');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find at least one product rollup');
        System.assertEquals('Test Rollup', results[0].title, 'Product rollup name should match');
    }

    @IsTest
    static void testSearchProductRollupsShortTerm() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchProductRollups('T');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for short search terms');
    }

    @IsTest
    static void testSearchItemMasterProducts() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchItemMasterProducts('IMP-TEST');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find at least one item master');
        System.assertEquals('IMP-TEST001', results[0].title, 'Item master name should match');
    }

    @IsTest
    static void testSearchItemMasterProductsByItemName() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchItemMasterProducts('Test Item');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find item master by item name');
    }

    @IsTest
    static void testSearchItemMasterProductsShortTerm() {
        Test.startTest();
        List<SkuLookupController.LookupResult> results = SkuLookupController.searchItemMasterProducts('I');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for short search terms');
    }
}