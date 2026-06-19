@IsTest
private class SkuBlockPricingControllerTest {

    @TestSetup
    static void setup() {
        Product2 product = new Product2(
            Name = 'Test Block Pricing Product',
            ProductCode = 'BP-TEST-001',
            IsActive = true
        );
        insert product;

        Block_Pricing__c bp = new Block_Pricing__c(
            Product__c = product.Id,
            Block_Pricing_Meter_Type__c = 'Named Users',
            Active__c = true,
            Price__c = 100.00,
            Tier_Name__c = 'EM1'
        );
        insert bp;
    }

    @IsTest
    static void testGetMeterTypeRecords() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'BP-TEST-001' LIMIT 1];

        Test.startTest();
        List<Block_Pricing__c> results = SkuBlockPricingController.getMeterTypeRecords(prod.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return block pricing records');
        System.assertEquals(prod.Id, results[0].Product__c, 'Product should match');
    }

    @IsTest
    static void testSaveMeterTypeRecords() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'BP-TEST-001' LIMIT 1];

        Block_Pricing__c newRec = new Block_Pricing__c(
            Block_Pricing_Meter_Type__c = 'Lawyers',
            Active__c = true,
            Price__c = 200.00
        );

        String recordsJson = JSON.serialize(new List<Block_Pricing__c>{ newRec });

        Test.startTest();
        List<Block_Pricing__c> results = SkuBlockPricingController.saveMeterTypeRecords(recordsJson, prod.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return saved records');
        System.assertNotEquals(null, results[0].Id, 'Record should have been inserted');
        System.assertEquals(prod.Id, results[0].Product__c, 'Product should be set');
    }

    @IsTest
    static void testSaveMeterTypeRecordsUpdate() {
        Block_Pricing__c existing = [SELECT Id, Price__c FROM Block_Pricing__c LIMIT 1];
        existing.Price__c = 150.00;

        String recordsJson = JSON.serialize(new List<Block_Pricing__c>{ existing });
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'BP-TEST-001' LIMIT 1];

        Test.startTest();
        List<Block_Pricing__c> results = SkuBlockPricingController.saveMeterTypeRecords(recordsJson, prod.Id);
        Test.stopTest();

        Block_Pricing__c updated = [SELECT Price__c FROM Block_Pricing__c WHERE Id = :existing.Id];
        System.assertEquals(150.00, updated.Price__c, 'Price should be updated');
    }

    @IsTest
    static void testDeleteBlockPricingRecords() {
        Block_Pricing__c existing = [SELECT Id FROM Block_Pricing__c LIMIT 1];

        Test.startTest();
        SkuBlockPricingController.deleteBlockPricingRecords(new List<Id>{ existing.Id });
        Test.stopTest();

        List<Block_Pricing__c> remaining = [SELECT Id FROM Block_Pricing__c WHERE Id = :existing.Id];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    @IsTest
    static void testDeleteBlockPricingRecordsEmptyList() {
        Test.startTest();
        SkuBlockPricingController.deleteBlockPricingRecords(new List<Id>());
        SkuBlockPricingController.deleteBlockPricingRecords(null);
        Test.stopTest();
        // Should not throw
    }

    @IsTest
    static void testGetTierConfiguration() {
        // Pricing_Tier_Configuration__mdt is custom metadata - may not exist in test context
        Test.startTest();
        SkuBlockPricingController.TierConfig config = SkuBlockPricingController.getTierConfiguration('Tier 1', 'Named Users');
        Test.stopTest();
        // Result depends on metadata records in org
    }

    @IsTest
    static void testGetTierConfigurationBlankInputs() {
        Test.startTest();
        SkuBlockPricingController.TierConfig config1 = SkuBlockPricingController.getTierConfiguration('', 'Named Users');
        SkuBlockPricingController.TierConfig config2 = SkuBlockPricingController.getTierConfiguration('Tier 1', '');
        SkuBlockPricingController.TierConfig config3 = SkuBlockPricingController.getTierConfiguration(null, null);
        Test.stopTest();

        System.assertEquals(null, config1, 'Should return null for blank tier');
        System.assertEquals(null, config2, 'Should return null for blank meter type');
        System.assertEquals(null, config3, 'Should return null for null inputs');
    }

    @IsTest
    static void testGetBlockPricingPicklists() {
        Test.startTest();
        Map<String, List<SkuBlockPricingController.PicklistOption>> picklists =
            SkuBlockPricingController.getBlockPricingPicklists();
        Test.stopTest();

        System.assertNotEquals(null, picklists, 'Picklists should not be null');
        System.assert(picklists.containsKey('Block_Pricing_Meter_Type__c'), 'Should contain meter type picklist');
    }

    @IsTest
    static void testGetMeterTypeRecord() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'BP-TEST-001' LIMIT 1];

        // Create a record with Type__c = 'Meter Type'
        Block_Pricing__c meterTypeRec = new Block_Pricing__c(
            Product__c = prod.Id,
            Block_Pricing_Meter_Type__c = 'Named Users',
            Type__c = 'Meter Type',
            Active__c = true,
            Price__c = 50.00
        );
        insert meterTypeRec;

        Test.startTest();
        Block_Pricing__c result = SkuBlockPricingController.getMeterTypeRecord(prod.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a record');
        System.assertEquals(meterTypeRec.Id, result.Id, 'Should return the Meter Type record');
    }

    @IsTest
    static void testGetMeterTypeRecordNotFound() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'BP-TEST-001' LIMIT 1];

        // No record with Type__c = 'Meter Type' exists (setup data has no Type__c set)
        // Delete existing records to ensure clean state
        delete [SELECT Id FROM Block_Pricing__c WHERE Product__c = :prod.Id AND Type__c = 'Meter Type'];

        Test.startTest();
        Block_Pricing__c result = SkuBlockPricingController.getMeterTypeRecord(prod.Id);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no Meter Type record exists');
    }

    @IsTest
    static void testSaveMeterTypeRecordsWithTierConfig() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'BP-TEST-001' LIMIT 1];

        // Create a new record with Tier_Name__c and Block_Pricing_Meter_Type__c set
        // to exercise the tier config auto-fill path
        Block_Pricing__c newRec = new Block_Pricing__c(
            Block_Pricing_Meter_Type__c = 'Named Users',
            Tier_Name__c = 'EM1',
            Active__c = true,
            Price__c = 300.00
        );

        String recordsJson = JSON.serialize(new List<Block_Pricing__c>{ newRec });

        Test.startTest();
        List<Block_Pricing__c> results = SkuBlockPricingController.saveMeterTypeRecords(recordsJson, prod.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return saved records');
        System.assertNotEquals(null, results[0].Id, 'Record should have been inserted');
        System.assertEquals(prod.Id, results[0].Product__c, 'Product should be set');
    }

    @IsTest
    static void testGetMeterTypeRecordsEmpty() {
        // Query for a product with no block pricing records
        Product2 emptyProd = new Product2(
            Name = 'Empty Product',
            ProductCode = 'BP-EMPTY-001',
            IsActive = true
        );
        insert emptyProd;

        Test.startTest();
        List<Block_Pricing__c> results = SkuBlockPricingController.getMeterTypeRecords(emptyProd.Id);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty list');
    }
}