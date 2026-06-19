@IsTest
private class SkuBundleControllerTest {

    @TestSetup
    static void setup() {
        // Create a component product
        Product2 component = new Product2(
            Name = 'Component Product',
            ProductCode = 'COMP-001',
            IsActive = true
        );
        insert component;
    }

    @IsTest
    static void testCreateBundleSku() {
        Product2 component = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-001' LIMIT 1];

        Map<String, Object> productFields = new Map<String, Object>{
            'Name' => 'Test Bundle',
            'ProductCode' => 'BDL-001',
            'IsActive' => true
        };

        Map<String, Object> itemMasterFields = new Map<String, Object>{
            'Name' => 'Test Bundle IM',
            'Item_Name__c' => 'Test Bundle Item',
            'Active__c' => true
        };

        List<Map<String, Object>> componentRows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'SBQQ__OptionalSKU__c' => component.Id,
                'SBQQ__Number__c' => 10,
                'SBQQ__Quantity__c' => 1,
                'SBQQ__Required__c' => true,
                'SBQQ__Selected__c' => true,
                'SBQQ__Type__c' => 'Component'
            }
        };

        Test.startTest();
        Id bundleId = SkuBundleController.createBundleSku(productFields, itemMasterFields, componentRows);
        Test.stopTest();

        System.assertNotEquals(null, bundleId, 'Bundle Id should not be null');

        Product2 bundle = [SELECT Parent_Of_Bundle__c, SBQQ__ConfigurationType__c FROM Product2 WHERE Id = :bundleId];
        System.assertEquals(true, bundle.Parent_Of_Bundle__c, 'Should be marked as bundle parent');
        System.assertEquals('Allowed', bundle.SBQQ__ConfigurationType__c, 'Config type should be Allowed');

        List<SBQQ__ProductOption__c> options = [SELECT Id FROM SBQQ__ProductOption__c WHERE SBQQ__ConfiguredSKU__c = :bundleId];
        System.assertEquals(1, options.size(), 'Should have 1 product option');
    }

    @IsTest
    static void testCreateBundleSkuNoComponents() {
        Map<String, Object> productFields = new Map<String, Object>{
            'Name' => 'Empty Bundle',
            'ProductCode' => 'BDL-002',
            'IsActive' => true
        };

        Map<String, Object> itemMasterFields = new Map<String, Object>{
            'Name' => 'Empty Bundle IM',
            'Item_Name__c' => 'Empty Bundle Item',
            'Active__c' => true
        };

        Test.startTest();
        Id bundleId = SkuBundleController.createBundleSku(productFields, itemMasterFields, null);
        Test.stopTest();

        System.assertNotEquals(null, bundleId, 'Bundle Id should not be null');
    }

    @IsTest
    static void testGetProductOptions() {
        // Create a bundle first
        Product2 component = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-001' LIMIT 1];

        Product2 bundle = new Product2(Name = 'Bundle For Options', ProductCode = 'BDL-OPT', IsActive = true, Parent_Of_Bundle__c = true);
        insert bundle;

        SBQQ__ProductOption__c opt = new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = bundle.Id,
            SBQQ__OptionalSKU__c = component.Id,
            SBQQ__Number__c = 10,
            SBQQ__Quantity__c = 1
        );
        insert opt;

        Test.startTest();
        List<SBQQ__ProductOption__c> results = SkuBundleController.getProductOptions(bundle.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 option');
    }

    @IsTest
    static void testSaveProductOptions() {
        Product2 component = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-001' LIMIT 1];
        Product2 bundle = new Product2(Name = 'Bundle Save', ProductCode = 'BDL-SAVE', IsActive = true, Parent_Of_Bundle__c = true);
        insert bundle;

        SBQQ__ProductOption__c opt = new SBQQ__ProductOption__c(
            SBQQ__OptionalSKU__c = component.Id,
            SBQQ__Number__c = 20,
            SBQQ__Quantity__c = 2
        );

        String json = JSON.serialize(new List<SBQQ__ProductOption__c>{ opt });

        Test.startTest();
        List<SBQQ__ProductOption__c> results = SkuBundleController.saveProductOptions(json, bundle.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return saved options');
        System.assertEquals(bundle.Id, results[0].SBQQ__ConfiguredSKU__c, 'Should be linked to bundle');
    }

    @IsTest
    static void testSearchComponentProducts() {
        Test.startTest();
        List<Product2> results = SkuBundleController.searchComponentProducts('Component');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find component product');
    }

    @IsTest
    static void testSearchComponentProductsShortTerm() {
        Test.startTest();
        List<Product2> results = SkuBundleController.searchComponentProducts('C');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for short search');
    }

    @IsTest
    static void testDeleteProductOptions() {
        Product2 component = [SELECT Id FROM Product2 WHERE ProductCode = 'COMP-001' LIMIT 1];
        Product2 bundle = new Product2(Name = 'Bundle Del', ProductCode = 'BDL-DEL', IsActive = true);
        insert bundle;

        SBQQ__ProductOption__c opt = new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = bundle.Id,
            SBQQ__OptionalSKU__c = component.Id,
            SBQQ__Number__c = 10,
            SBQQ__Quantity__c = 1
        );
        insert opt;

        Test.startTest();
        SkuBundleController.deleteProductOptions(new List<Id>{ opt.Id });
        Test.stopTest();

        List<SBQQ__ProductOption__c> remaining = [SELECT Id FROM SBQQ__ProductOption__c WHERE Id = :opt.Id];
        System.assertEquals(0, remaining.size(), 'Option should be deleted');
    }

    @IsTest
    static void testDeleteProductOptionsEmptyList() {
        Test.startTest();
        SkuBundleController.deleteProductOptions(new List<Id>());
        SkuBundleController.deleteProductOptions(null);
        Test.stopTest();
    }
}