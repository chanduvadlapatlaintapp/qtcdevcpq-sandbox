@IsTest
private class SkuProductControllerTest {

    @TestSetup
    static void setupTestData() {
        Product_Line__c productLine = new Product_Line__c(
            Name = 'Test Product Line',
            Active__c = true,
            Deployment__c = 'Cloud',
            Practice__c = 'DealCloud'
        );
        insert productLine;

        Item_Master_Product__c itemMaster = new Item_Master_Product__c(
            Name = 'IMP-SKUTEST001',
            Item_Name__c = 'Test Item Master For SKU',
            Active__c = true,
            Product_LineNew__c = productLine.Id
        );
        insert itemMaster;

        Product2 product = new Product2(
            Name = 'Existing Test Product',
            ProductCode = 'ETP-001',
            IsActive = true,
            Product_LineNew__c = productLine.Id,
            Item_Master_Product__c = itemMaster.Id
        );
        insert product;
    }

    @IsTest
    static void testCreateStandaloneSku() {
        Product_Line__c pl = [SELECT Id FROM Product_Line__c LIMIT 1];

        Map<String, Object> productFields = new Map<String, Object>{
            'Name' => 'New SKU Product',
            'ProductCode' => 'NSKU-001',
            'IsActive' => true,
            'Product_LineNew__c' => pl.Id,
            'Product_Type__c' => 'Software'
        };

        Map<String, Object> itemMasterFields = new Map<String, Object>{
            'Name' => 'IMP-NEWSKU001',
            'Item_Name__c' => 'New SKU Item Master',
            'Active__c' => true,
            'Product_LineNew__c' => pl.Id
        };

        Test.startTest();
        Id productId = SkuProductController.createStandaloneSku(productFields, itemMasterFields);
        Test.stopTest();

        System.assertNotEquals(null, productId, 'Product should be created');

        Product2 createdProduct = [SELECT Id, Name, ProductCode, Item_Master_Product__c FROM Product2 WHERE Id = :productId];
        System.assertEquals('New SKU Product', createdProduct.Name);
        System.assertEquals('NSKU-001', createdProduct.ProductCode);
        System.assertNotEquals(null, createdProduct.Item_Master_Product__c, 'Item Master should be linked');
    }

    @IsTest
    static void testCreateStandaloneSkuDuplicateItemMasterName() {
        Map<String, Object> productFields = new Map<String, Object>{
            'Name' => 'Dup SKU Product',
            'ProductCode' => 'DUP-001',
            'IsActive' => true
        };

        Map<String, Object> itemMasterFields = new Map<String, Object>{
            'Name' => 'IMP-SKUTEST001',
            'Item_Name__c' => 'Duplicate Name Test',
            'Active__c' => true
        };

        Test.startTest();
        try {
            SkuProductController.createStandaloneSku(productFields, itemMasterFields);
            System.assert(false, 'Should have thrown exception for duplicate name');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already exists') || e.getMessage().length() > 0,
                'Should get a meaningful error message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetSkuDetails() {
        Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Existing Test Product' LIMIT 1];

        Test.startTest();
        SkuProductController.SkuWrapper wrapper = SkuProductController.getSkuDetails(product.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper.product, 'Product should be returned');
        System.assertEquals('Existing Test Product', wrapper.product.Name);
        System.assertNotEquals(null, wrapper.itemMaster, 'Item Master should be returned');
        System.assertEquals('IMP-SKUTEST001', wrapper.itemMaster.Name);
    }

    @IsTest
    static void testGetSkuDetailsNotFound() {
        Test.startTest();
        try {
            SkuProductController.getSkuDetails('01t000000000000AAA');
            System.assert(false, 'Should throw exception for non-existent product');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().length() > 0, 'Should get an error message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateSku() {
        Product2 product = [SELECT Id, Item_Master_Product__c FROM Product2 WHERE Name = 'Existing Test Product' LIMIT 1];

        Map<String, Object> productFields = new Map<String, Object>{
            'Description' => 'Updated description',
            'IsActive' => true
        };

        Map<String, Object> itemMasterFields = new Map<String, Object>{
            'Item_Name__c' => 'Updated Item Name',
            'Active__c' => true
        };

        Test.startTest();
        SkuProductController.updateSku(productFields, itemMasterFields, product.Id, product.Item_Master_Product__c);
        Test.stopTest();

        Product2 updatedProduct = [SELECT Description FROM Product2 WHERE Id = :product.Id];
        System.assertEquals('Updated description', updatedProduct.Description);

        Item_Master_Product__c updatedImp = [SELECT Item_Name__c FROM Item_Master_Product__c WHERE Id = :product.Item_Master_Product__c];
        System.assertEquals('Updated Item Name', updatedImp.Item_Name__c);
    }

    @IsTest
    static void testUpdateSkuExcludesItemMasterName() {
        Product2 product = [SELECT Id, Item_Master_Product__c FROM Product2 WHERE Name = 'Existing Test Product' LIMIT 1];

        Map<String, Object> productFields = new Map<String, Object>();
        Map<String, Object> itemMasterFields = new Map<String, Object>{
            'Name' => 'SHOULD-BE-REMOVED',
            'Item_Name__c' => 'Updated via Name Exclusion Test'
        };

        Test.startTest();
        SkuProductController.updateSku(productFields, itemMasterFields, product.Id, product.Item_Master_Product__c);
        Test.stopTest();

        Item_Master_Product__c imp = [SELECT Name, Item_Name__c FROM Item_Master_Product__c WHERE Id = :product.Item_Master_Product__c];
        System.assertEquals('IMP-SKUTEST001', imp.Name, 'Name should not have changed');
        System.assertEquals('Updated via Name Exclusion Test', imp.Item_Name__c);
    }

    @IsTest
    static void testSearchProductsForUpdate() {
        Test.startTest();
        List<Product2> results = SkuProductController.searchProductsForUpdate('Existing Test');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find matching product');
        System.assertEquals('Existing Test Product', results[0].Name);
    }

    @IsTest
    static void testSearchProductsForUpdateShortTerm() {
        Test.startTest();
        List<Product2> results = SkuProductController.searchProductsForUpdate('E');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for short terms');
    }

    @IsTest
    static void testIsItemMasterNameAvailable() {
        Test.startTest();
        Boolean availableNew = SkuProductController.isItemMasterNameAvailable('IMP-BRAND-NEW-NAME');
        Boolean availableExisting = SkuProductController.isItemMasterNameAvailable('IMP-SKUTEST001');
        Boolean availableBlank = SkuProductController.isItemMasterNameAvailable('');
        Test.stopTest();

        System.assertEquals(true, availableNew, 'New name should be available');
        System.assertEquals(false, availableExisting, 'Existing name should not be available');
        System.assertEquals(false, availableBlank, 'Blank name should not be available');
    }

    @IsTest
    static void testGetProductPicklistValues() {
        Test.startTest();
        Map<String, List<SkuProductController.PicklistOption>> result = SkuProductController.getProductPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('Product_Type__c'), 'Should contain Product_Type__c picklist');
    }

    @IsTest
    static void testGetItemMasterPicklistValues() {
        Test.startTest();
        Map<String, List<SkuProductController.PicklistOption>> result = SkuProductController.getItemMasterPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    // =========================================================================
    // Tests for searchProductsFiltered (Update Tab Redesign)
    // =========================================================================

    @IsTest
    static void testSearchProductsFilteredByName() {
        Test.startTest();
        List<SkuProductController.SkuWrapper> results =
            SkuProductController.searchProductsFiltered('Existing', null, null, null);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find matching products');
        System.assertNotEquals(null, results[0].product, 'Wrapper should contain product');
        System.assertEquals('Existing Test Product', results[0].product.Name);
    }

    @IsTest
    static void testSearchProductsFilteredByCode() {
        Test.startTest();
        List<SkuProductController.SkuWrapper> results =
            SkuProductController.searchProductsFiltered(null, 'ETP', null, null);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find by code');
    }

    @IsTest
    static void testSearchProductsFilteredByActive() {
        Test.startTest();
        List<SkuProductController.SkuWrapper> results =
            SkuProductController.searchProductsFiltered(null, null, null, 'true');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a list');
        for (SkuProductController.SkuWrapper w : results) {
            System.assertEquals(true, w.product.IsActive, 'All results should be active');
        }
    }

    @IsTest
    static void testSearchProductsFilteredNoFilters() {
        Test.startTest();
        List<SkuProductController.SkuWrapper> results =
            SkuProductController.searchProductsFiltered(null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a list');
    }

    @IsTest
    static void testSearchProductsFilteredWithItemMaster() {
        Test.startTest();
        List<SkuProductController.SkuWrapper> results =
            SkuProductController.searchProductsFiltered('Existing', null, null, null);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find products');
        System.assertNotEquals(null, results[0].itemMaster, 'Should include Item Master');
        System.assertEquals('IMP-SKUTEST001', results[0].itemMaster.Name);
    }

    // =========================================================================
    // Tests for bulkUpdateSkus (Update Tab Redesign)
    // =========================================================================

    @IsTest
    static void testBulkUpdateSkus() {
        Product2 product = [SELECT Id, Item_Master_Product__c FROM Product2 WHERE Name = 'Existing Test Product' LIMIT 1];

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Map<String, Object> row = new Map<String, Object>();
        row.put('productId', product.Id);
        row.put('itemMasterId', product.Item_Master_Product__c);
        row.put('productFields', new Map<String, Object>{ 'Description' => 'Bulk updated description' });
        row.put('itemMasterFields', new Map<String, Object>{ 'Item_Name__c' => 'Bulk updated item name' });
        rows.add(row);

        Test.startTest();
        SkuProductController.bulkUpdateSkus(JSON.serialize(rows));
        Test.stopTest();

        Product2 updated = [SELECT Description FROM Product2 WHERE Id = :product.Id];
        System.assertEquals('Bulk updated description', updated.Description);

        Item_Master_Product__c updatedImp = [SELECT Item_Name__c FROM Item_Master_Product__c WHERE Id = :product.Item_Master_Product__c];
        System.assertEquals('Bulk updated item name', updatedImp.Item_Name__c);
    }

    @IsTest
    static void testBulkUpdateSkusExcludesItemMasterName() {
        Product2 product = [SELECT Id, Item_Master_Product__c FROM Product2 WHERE Name = 'Existing Test Product' LIMIT 1];

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Map<String, Object> row = new Map<String, Object>();
        row.put('productId', product.Id);
        row.put('itemMasterId', product.Item_Master_Product__c);
        row.put('productFields', new Map<String, Object>());
        row.put('itemMasterFields', new Map<String, Object>{ 'Name' => 'SHOULD-NOT-CHANGE', 'Item_Name__c' => 'Bulk test' });
        rows.add(row);

        Test.startTest();
        SkuProductController.bulkUpdateSkus(JSON.serialize(rows));
        Test.stopTest();

        Item_Master_Product__c imp = [SELECT Name, Item_Name__c FROM Item_Master_Product__c WHERE Id = :product.Item_Master_Product__c];
        System.assertEquals('IMP-SKUTEST001', imp.Name, 'Name should not change');
        System.assertEquals('Bulk test', imp.Item_Name__c);
    }

    @IsTest
    static void testBulkUpdateSkusProductOnly() {
        Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Existing Test Product' LIMIT 1];

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Map<String, Object> row = new Map<String, Object>();
        row.put('productId', product.Id);
        row.put('itemMasterId', null);
        row.put('productFields', new Map<String, Object>{ 'Description' => 'Product-only update' });
        row.put('itemMasterFields', null);
        rows.add(row);

        Test.startTest();
        SkuProductController.bulkUpdateSkus(JSON.serialize(rows));
        Test.stopTest();

        Product2 updated = [SELECT Description FROM Product2 WHERE Id = :product.Id];
        System.assertEquals('Product-only update', updated.Description);
    }

    // =========================================================================
    // bulkCreateStandaloneSkus Tests
    // =========================================================================

    @IsTest
    static void testBulkCreateStandaloneSkus() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Integer i = 1; i <= 3; i++) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('productFields', new Map<String, Object>{
                'Name' => 'Bulk SKU ' + i,
                'ProductCode' => 'BULK-' + i,
                'IsActive' => true
            });
            row.put('itemMasterFields', new Map<String, Object>{
                'Name' => 'IMP-BULK' + i
            });
            rows.add(row);
        }

        Test.startTest();
        List<Id> createdIds = SkuProductController.bulkCreateStandaloneSkus(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(3, createdIds.size(), 'Should return 3 created Product Ids');

        List<Product2> products = [SELECT Id, Name, ProductCode, Item_Master_Product__c FROM Product2 WHERE Id IN :createdIds ORDER BY Name];
        System.assertEquals(3, products.size(), 'Should find 3 products');
        for (Product2 p : products) {
            System.assertNotEquals(null, p.Item_Master_Product__c, 'Product should be linked to Item Master');
        }

        Set<Id> imIds = new Set<Id>();
        for (Product2 p : products) {
            imIds.add(p.Item_Master_Product__c);
        }
        List<Item_Master_Product__c> itemMasters = [SELECT Id, Name FROM Item_Master_Product__c WHERE Id IN :imIds];
        System.assertEquals(3, itemMasters.size(), 'Should find 3 Item Masters');
    }

    @IsTest
    static void testBulkCreateStandaloneSkusSingleRow() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Map<String, Object> row = new Map<String, Object>();
        row.put('productFields', new Map<String, Object>{
            'Name' => 'Single Bulk SKU',
            'ProductCode' => 'SINGLE-BULK-001',
            'IsActive' => true
        });
        row.put('itemMasterFields', new Map<String, Object>{
            'Name' => 'IMP-SINGLEBULK001'
        });
        rows.add(row);

        Test.startTest();
        List<Id> createdIds = SkuProductController.bulkCreateStandaloneSkus(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(1, createdIds.size(), 'Should return 1 created Product Id');
        Product2 p = [SELECT Id, Name, Item_Master_Product__c FROM Product2 WHERE Id = :createdIds[0]];
        System.assertEquals('Single Bulk SKU', p.Name);
        System.assertNotEquals(null, p.Item_Master_Product__c);
    }

    @IsTest
    static void testBulkCreateStandaloneSkusDuplicateName() {
        // Use existing Item Master Name from test setup: IMP-SKUTEST001
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Map<String, Object> row = new Map<String, Object>();
        row.put('productFields', new Map<String, Object>{
            'Name' => 'Dup SKU',
            'ProductCode' => 'DUP-001'
        });
        row.put('itemMasterFields', new Map<String, Object>{
            'Name' => 'IMP-SKUTEST001'
        });
        rows.add(row);

        Test.startTest();
        try {
            SkuProductController.bulkCreateStandaloneSkus(JSON.serialize(rows));
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Error message should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testBulkCreateStandaloneSkusDuplicateWithinBatch() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Integer i = 0; i < 2; i++) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('productFields', new Map<String, Object>{
                'Name' => 'Dup Batch SKU ' + i,
                'ProductCode' => 'DUPBATCH-' + i
            });
            row.put('itemMasterFields', new Map<String, Object>{
                'Name' => 'IMP-SAMENAME'
            });
            rows.add(row);
        }

        Test.startTest();
        try {
            SkuProductController.bulkCreateStandaloneSkus(JSON.serialize(rows));
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Error message should not be null');
        }
        Test.stopTest();
    }
}