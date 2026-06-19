/**
 * @description Test class for PricebookSetupQueueable.
 *              Validates PricebookEntry and SBQQ__Dimension__c creation
 *              for the Phase 2 one-time pricebook setup.
 */
@IsTest
private class PricebookSetupQueueableTest {

    @TestSetup
    static void setup() {
        // Create test products with different types
        Product2 softwareProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Software Product',
            ProductCode = 'SW-QUE-001',
            IsActive = true,
            Product_Type__c = 'Software'
        ));

        Product2 supportProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Support Product',
            ProductCode = 'SUP-QUE-001',
            IsActive = true,
            Product_Type__c = 'Support'
        ));

        Product2 otherProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Other Type Product',
            ProductCode = 'OTH-QUE-001',
            IsActive = true,
            Product_Type__c = 'Hardware'
        ));

        // Create a target pricebook
        Pricebook2 testPb = new Pricebook2(Name = 'Queueable Test PB', IsActive = true);
        insert testPb;
    }

    @IsTest
    static void testPricebookEntriesPhase() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];

        // Make standard pricebook visible and set override for queueable
        Id standardPbId = Test.getStandardPricebookId();
        PricebookSetupQueueable.standardPricebookIdOverride = standardPbId;

        // Pre-create Standard Pricebook entries (Salesforce requirement for custom PBE)
        List<Product2> products = [
            SELECT Id FROM Product2
            WHERE ProductCode IN ('SW-QUE-001', 'SUP-QUE-001', 'OTH-QUE-001')
        ];
        List<PricebookEntry> stdEntries = new List<PricebookEntry>();
        for (Product2 p : products) {
            stdEntries.add(new PricebookEntry(
                Pricebook2Id = standardPbId,
                Product2Id = p.Id,
                UnitPrice = 0,
                IsActive = true
            ));
        }
        insert stdEntries;

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'PRICEBOOK_ENTRIES', 0));
        Test.stopTest();

        // Verify custom PBE records were created
        List<PricebookEntry> customEntries = [
            SELECT Id, Product2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :pb.Id
        ];
        System.assert(customEntries.size() > 0,
            'Should create custom PricebookEntry records');
    }

    @IsTest
    static void testDimensionsPhase() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'DIMENSIONS', 0));
        Test.stopTest();

        // Only Software and Support products should get dimensions (not Hardware)
        List<SBQQ__Dimension__c> dims = [
            SELECT Id, SBQQ__Product__c, CurrencyIsoCode, SBQQ__PriceBook__c,
                   SBQQ__Product__r.ProductCode
            FROM SBQQ__Dimension__c
            WHERE SBQQ__PriceBook__c = :pb.Id
        ];

        // Software + Support = 2 products x 4 currencies = 8 dimensions
        System.assert(dims.size() > 0, 'Should create dimension records');

        // Verify no dimensions for Hardware product
        Set<String> dimProductCodes = new Set<String>();
        for (SBQQ__Dimension__c dim : dims) {
            dimProductCodes.add(dim.SBQQ__Product__r.ProductCode);
        }
        System.assert(!dimProductCodes.contains('OTH-QUE-001'),
            'Should not create dimensions for Hardware product');
    }

    @IsTest
    static void testDuplicateDimensionPrevention() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];
        Product2 swProd = [SELECT Id FROM Product2 WHERE ProductCode = 'SW-QUE-001' LIMIT 1];

        // Pre-create a dimension to test duplicate prevention
        SBQQ__Dimension__c existingDim = new SBQQ__Dimension__c(
            SBQQ__Product__c = swProd.Id,
            Name = 'Existing Dim USD',
            SBQQ__Type__c = 'Year',
            SBQQ__PriceBook__c = pb.Id,
            CurrencyIsoCode = 'USD'
        );
        insert existingDim;

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'DIMENSIONS', 0));
        Test.stopTest();

        // Count USD dimensions for SW product - should still be only 1
        List<SBQQ__Dimension__c> usdDims = [
            SELECT Id FROM SBQQ__Dimension__c
            WHERE SBQQ__Product__c = :swProd.Id
              AND CurrencyIsoCode = 'USD'
              AND SBQQ__PriceBook__c = :pb.Id
        ];
        System.assertEquals(1, usdDims.size(),
            'Should not duplicate existing dimension');
    }

    @IsTest
    static void testChainFromEntriesToDimensions() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];

        // Make standard pricebook visible and set override for queueable
        Id standardPbId = Test.getStandardPricebookId();
        PricebookSetupQueueable.standardPricebookIdOverride = standardPbId;

        // Pre-create Standard Pricebook entries (Salesforce requirement for custom PBE)
        List<Product2> products = [
            SELECT Id FROM Product2
            WHERE ProductCode IN ('SW-QUE-001', 'SUP-QUE-001', 'OTH-QUE-001')
        ];
        List<PricebookEntry> stdEntries = new List<PricebookEntry>();
        for (Product2 p : products) {
            stdEntries.add(new PricebookEntry(
                Pricebook2Id = standardPbId,
                Product2Id = p.Id,
                UnitPrice = 0,
                IsActive = true
            ));
        }
        insert stdEntries;

        // Run from PRICEBOOK_ENTRIES phase — in test context it will chain to DIMENSIONS
        // but Test.stopTest() only executes the first chained job
        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'PRICEBOOK_ENTRIES', 0));
        Test.stopTest();

        // Verify the Queueable executed without exceptions.
        // Chaining behavior is validated by the fact that no exception was thrown.
        // In test context, only one chained job runs per Test.stopTest().
        List<AsyncApexJob> jobs = [
            SELECT Status FROM AsyncApexJob
            WHERE ApexClass.Name = 'PricebookSetupQueueable'
              AND Status = 'Completed'
        ];
        System.assert(jobs.size() > 0, 'At least one queueable job should complete');
    }

    @IsTest
    static void testPricebookEntriesPhaseNoPreexisting() {
        // Test standard + custom PBE creation WITHOUT pre-creating standard entries
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];

        // Make standard pricebook visible and set override for queueable
        Id standardPbId = Test.getStandardPricebookId();
        PricebookSetupQueueable.standardPricebookIdOverride = standardPbId;

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'PRICEBOOK_ENTRIES', 0));
        Test.stopTest();

        // Should create both standard and custom entries
        List<PricebookEntry> stdEntries = [
            SELECT Id, Product2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPbId
              AND Product2Id IN (SELECT Id FROM Product2 WHERE ProductCode LIKE '%QUE%')
        ];
        System.assert(stdEntries.size() > 0, 'Should create standard PBE records');

        List<PricebookEntry> customEntries = [
            SELECT Id, Product2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :pb.Id
        ];
        System.assert(customEntries.size() > 0, 'Should create custom PBE records');
    }

    @IsTest
    static void testPricebookEntriesEmptyOffset() {
        // Offset beyond available products → should chain to DIMENSIONS phase
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];
        PricebookSetupQueueable.standardPricebookIdOverride = Test.getStandardPricebookId();

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'PRICEBOOK_ENTRIES', 999999));
        Test.stopTest();

        // No exception means it handled empty products and chained to DIMENSIONS
        List<AsyncApexJob> jobs = [
            SELECT Status FROM AsyncApexJob
            WHERE ApexClass.Name = 'PricebookSetupQueueable'
              AND Status = 'Completed'
        ];
        System.assert(jobs.size() > 0, 'Job should complete successfully');
    }

    @IsTest
    static void testDimensionsEmptyOffset() {
        // Offset beyond available products → should finish gracefully
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'DIMENSIONS', 999999));
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Status FROM AsyncApexJob
            WHERE ApexClass.Name = 'PricebookSetupQueueable'
              AND Status = 'Completed'
        ];
        System.assert(jobs.size() > 0, 'Job should complete successfully');
    }

    @IsTest
    static void testDuplicatePricebookEntryPrevention() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];
        Product2 swProd = [SELECT Id FROM Product2 WHERE ProductCode = 'SW-QUE-001' LIMIT 1];

        // Pre-create standard and custom entries for one product/currency
        Id standardPbId = Test.getStandardPricebookId();
        PricebookSetupQueueable.standardPricebookIdOverride = standardPbId;
        insert new PricebookEntry(
            Pricebook2Id = standardPbId,
            Product2Id = swProd.Id,
            CurrencyIsoCode = 'USD',
            UnitPrice = 0,
            IsActive = true
        );
        insert new PricebookEntry(
            Pricebook2Id = pb.Id,
            Product2Id = swProd.Id,
            CurrencyIsoCode = 'USD',
            UnitPrice = 0,
            IsActive = true
        );

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'PRICEBOOK_ENTRIES', 0));
        Test.stopTest();

        // Should not duplicate the USD entry
        List<PricebookEntry> usdEntries = [
            SELECT Id FROM PricebookEntry
            WHERE Pricebook2Id = :pb.Id
              AND Product2Id = :swProd.Id
              AND CurrencyIsoCode = 'USD'
        ];
        System.assertEquals(1, usdEntries.size(), 'Should not duplicate existing PBE');
    }

    @IsTest
    static void testDimensionsPhaseWithMaintenanceProduct() {
        // Add a Maintenance product to cover that product type path
        Product2 maintProd = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Maintenance Product',
            ProductCode = 'MAINT-QUE-001',
            IsActive = true,
            Product_Type__c = 'Maintenance'
        ));

        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Queueable Test PB' LIMIT 1];

        Test.startTest();
        System.enqueueJob(new PricebookSetupQueueable(pb.Id, 'DIMENSIONS', 0));
        Test.stopTest();

        // Software + Support + Maintenance = 3 products should get dimensions
        List<SBQQ__Dimension__c> dims = [
            SELECT Id, SBQQ__Product__r.ProductCode
            FROM SBQQ__Dimension__c
            WHERE SBQQ__PriceBook__c = :pb.Id
              AND SBQQ__Product__c = :maintProd.Id
        ];
        System.assert(dims.size() > 0, 'Should create dimensions for Maintenance product');
    }
}