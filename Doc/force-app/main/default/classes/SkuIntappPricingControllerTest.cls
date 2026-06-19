@IsTest
private class SkuIntappPricingControllerTest {

    @TestSetup
    static void setup() {
        Product2 product = new Product2(
            Name = 'Test Intapp Pricing Product',
            ProductCode = 'IP-TEST-001',
            IsActive = true
        );
        insert product;

        // Price_Book__c is a lookup to Pricebook2
        Id stdPbId = Test.getStandardPricebookId();

        Intapp_Pricing__c ip = new Intapp_Pricing__c(
            Product__c = product.Id,
            Price__c = 500.00,
            Premium_price__c = 450.00,
            Product_Code__c = 'IP-TEST-001',
            Tier__c = 'Tier A',
            Price_Book__c = stdPbId
        );
        insert ip;
    }

    @IsTest
    static void testGetIntappPricingByProduct() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IP-TEST-001' LIMIT 1];

        Test.startTest();
        List<Intapp_Pricing__c> results = SkuIntappPricingController.getIntappPricingByProduct(prod.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return pricing records');
        System.assertEquals(prod.Id, results[0].Product__c, 'Product should match');
    }

    @IsTest
    static void testSaveIntappPricingRecords() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IP-TEST-001' LIMIT 1];

        Intapp_Pricing__c newRec = new Intapp_Pricing__c(
            Price__c = 600.00,
            Premium_price__c = 550.00,
            Product_Code__c = 'IP-NEW-001',
            Tier__c = 'Tier A',
            Price_Book__c = Test.getStandardPricebookId()
        );

        String recordsJson = JSON.serialize(new List<Intapp_Pricing__c>{ newRec });

        Test.startTest();
        List<Intapp_Pricing__c> results = SkuIntappPricingController.saveIntappPricingRecords(recordsJson, prod.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return saved records');
        System.assertNotEquals(null, results[0].Id, 'Record should have been inserted');
    }

    @IsTest
    static void testSaveIntappPricingRecordsUpdate() {
        Intapp_Pricing__c existing = [SELECT Id, Price__c FROM Intapp_Pricing__c LIMIT 1];
        existing.Price__c = 750.00;
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IP-TEST-001' LIMIT 1];

        String recordsJson = JSON.serialize(new List<Intapp_Pricing__c>{ existing });

        Test.startTest();
        List<Intapp_Pricing__c> results = SkuIntappPricingController.saveIntappPricingRecords(recordsJson, prod.Id);
        Test.stopTest();

        Intapp_Pricing__c updated = [SELECT Price__c FROM Intapp_Pricing__c WHERE Id = :existing.Id];
        System.assertEquals(750.00, updated.Price__c, 'Price should be updated');
    }

    @IsTest
    static void testDeleteIntappPricingRecords() {
        Intapp_Pricing__c existing = [SELECT Id FROM Intapp_Pricing__c LIMIT 1];

        Test.startTest();
        SkuIntappPricingController.deleteIntappPricingRecords(new List<Id>{ existing.Id });
        Test.stopTest();

        List<Intapp_Pricing__c> remaining = [SELECT Id FROM Intapp_Pricing__c WHERE Id = :existing.Id];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    @IsTest
    static void testDeleteIntappPricingRecordsEmptyList() {
        Test.startTest();
        SkuIntappPricingController.deleteIntappPricingRecords(new List<Id>());
        SkuIntappPricingController.deleteIntappPricingRecords(null);
        Test.stopTest();
    }

    @IsTest
    static void testGetIntappPricingPicklists() {
        Test.startTest();
        Map<String, List<SkuIntappPricingController.PicklistOption>> picklists =
            SkuIntappPricingController.getIntappPricingPicklists();
        Test.stopTest();

        System.assertNotEquals(null, picklists, 'Picklists should not be null');
    }
}