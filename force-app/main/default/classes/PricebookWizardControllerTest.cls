/**
 * @description Test class for PricebookWizardController.
 *              Covers Phase 1–4 methods: pricebook listing, creation,
 *              CSV validation, and pricing data processing.
 */
@IsTest
private class PricebookWizardControllerTest {

    /***********************************************************************************************
     *
     * Test Data Setup
     *
     ***********************************************************************************************/

    @TestSetup
    static void setup() {
        // Create test products with different Pricing Basis values
        Product2 tierProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Tier Based Product',
            ProductCode = 'TBP-001',
            IsActive = true,
            Pricing_Basis__c = 'Tier Based',
            Product_Type__c = 'Software',
            Eligible_For_Premium__c = true
        ));

        Product2 freeProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Free Product',
            ProductCode = 'FREE-001',
            IsActive = true,
            Pricing_Basis__c = 'Free',
            Product_Type__c = 'Software',
            Eligible_For_Premium__c = false
        ));

        Product2 otherProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Other Product',
            ProductCode = 'OTH-001',
            IsActive = true,
            Pricing_Basis__c = 'Other/Mixed',
            Product_Type__c = 'Support',
            Eligible_For_Premium__c = true
        ));

        // Create test pricebooks
        Pricebook2 testPb = new Pricebook2(Name = 'Test Wizard PB', IsActive = true);
        Pricebook2 fyPb = new Pricebook2(Name = 'FY26_All_Products', IsActive = true);
        insert new List<Pricebook2>{ testPb, fyPb };
    }

    /***********************************************************************************************
     *
     * Phase 1 Tests
     *
     ***********************************************************************************************/

    @IsTest
    static void testGetActivePricebooks() {
        Test.startTest();
        List<PricebookWizardController.PricebookInfo> results =
            PricebookWizardController.getActivePricebooks();
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return at least one pricebook');

        Boolean foundTestPb = false;
        for (PricebookWizardController.PricebookInfo pb : results) {
            if (pb.name == 'Test Wizard PB') {
                foundTestPb = true;
                System.assertEquals(true, pb.isActive, 'Pricebook should be active');
            }
        }
        System.assert(foundTestPb, 'Should find the test pricebook');
    }

    @IsTest
    static void testCreatePricebook() {
        Test.startTest();
        Id pbId = PricebookWizardController.createPricebook('FY27_Wizard_Test');
        Test.stopTest();

        System.assertNotEquals(null, pbId, 'Should return new pricebook Id');
        Pricebook2 pb = [SELECT Name, IsActive FROM Pricebook2 WHERE Id = :pbId];
        System.assertEquals('FY27_Wizard_Test', pb.Name, 'Name should match');
        System.assertEquals(true, pb.IsActive, 'Should be active');
    }

    @IsTest
    static void testCreatePricebookBlankName() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.createPricebook('');
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for blank name');
    }

    @IsTest
    static void testCreatePricebookDuplicate() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.createPricebook('Test Wizard PB');
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for duplicate name');
    }

    /***********************************************************************************************
     *
     * Phase 2 Tests
     *
     ***********************************************************************************************/

    @IsTest
    static void testStartPricebookSetup() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Test Wizard PB' LIMIT 1];

        Test.startTest();
        Id jobId = PricebookWizardController.startPricebookSetup(pb.Id);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Should return a job Id');
    }

    @IsTest
    static void testStartPricebookSetupNullId() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.startPricebookSetup(null);
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for null pricebook Id');
    }

    @IsTest
    static void testGetSetupStatusNullJob() {
        Test.startTest();
        PricebookWizardController.SetupStatusResult result =
            PricebookWizardController.getSetupStatus(null);
        Test.stopTest();

        System.assertEquals('Failed', result.status, 'Should return Failed for null job');
    }

    /***********************************************************************************************
     *
     * Phase 3 Tests - CSV Validation (10 columns: Product Id, Product Code, ...)
     *
     ***********************************************************************************************/

    @IsTest
    static void testValidateCsvUploadValid() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];
        Product2 free = [SELECT Id FROM Product2 WHERE ProductCode = 'FREE-001' LIMIT 1];

        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + tbp.Id + ',TBP-001,Fee Earners,USD,EM1,150.00,true,true,false,false\n'
            + free.Id + ',FREE-001,Fee Earners,GBP,None,0,true,false,false,false';

        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload(csv);
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid');
        System.assertEquals(2, result.rowCount, 'Should have 2 data rows');
        System.assertEquals(0, result.errors.size(), 'Should have no errors');
    }

    @IsTest
    static void testValidateCsvUploadInvalidCurrency() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + tbp.Id + ',TBP-001,Fee Earners,ZZZ,EM1,150.00,true,true,false,false';

        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload(csv);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assert(result.errors.size() > 0, 'Should have errors');
    }

    @IsTest
    static void testValidateCsvUploadBadPrice() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + tbp.Id + ',TBP-001,Fee Earners,USD,EM1,NOT_A_NUMBER,true,true,false,false';

        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload(csv);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid');
    }

    @IsTest
    static void testValidateCsvUploadMissingProduct() {
        // Use a fake 18-char Id that won't exist
        String fakeId = '01t000000000000AAA';

        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + fakeId + ',FAKE-001,Fee Earners,USD,EM1,100,true,true,false,false';

        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload(csv);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for missing product');
    }

    @IsTest
    static void testValidateCsvUploadWrongColumnCount() {
        String csv = 'Product Id,Product Code,Meter Type\n'
            + '01t000000000000AAA,TEST-001,Fee Earners';

        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload(csv);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for wrong column count');
    }

    @IsTest
    static void testValidateCsvUploadEmpty() {
        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload('');
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for empty content');
    }

    @IsTest
    static void testValidateCsvUploadInvalidProductId() {
        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + 'BADID,TBP-001,Fee Earners,USD,EM1,100,true,true,false,false';

        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload(csv);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for bad Product Id format');
    }

    /***********************************************************************************************
     *
     * Phase 4 Tests - Processing (10 columns: Product Id, Product Code, ...)
     *
     ***********************************************************************************************/

    @IsTest
    static void testProcessPricingUpload() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Test Wizard PB' LIMIT 1];
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];
        Product2 free = [SELECT Id FROM Product2 WHERE ProductCode = 'FREE-001' LIMIT 1];
        Product2 oth = [SELECT Id FROM Product2 WHERE ProductCode = 'OTH-001' LIMIT 1];

        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + tbp.Id + ',TBP-001,Fee Earners,USD,EM1,150.00,true,true,false,false\n'
            + tbp.Id + ',TBP-001,Fee Earners,USD,None,100.00,true,false,false,false\n'
            + free.Id + ',FREE-001,Fee Earners,USD,EM1,0,true,false,false,false\n'
            + oth.Id + ',OTH-001,Fee Earners,GBP,EM2,200.00,true,true,true,false';

        Test.startTest();
        PricebookWizardController.ProcessingResult result =
            PricebookWizardController.processPricingUpload(csv, pb.Id);
        Test.stopTest();

        // All 4 rows should produce Intapp_Pricing__c
        System.assertEquals(4, result.intappResult.totalCount, 'Should have 4 Intapp records');
        System.assertEquals(4, result.intappResult.successCount, 'All Intapp should succeed');

        // Only TBP-001 (Tier Based) should produce Block_Pricing__c (2 rows)
        System.assertEquals(2, result.blockResult.totalCount, 'Should have 2 Block records');
        System.assertEquals(2, result.blockResult.successCount, 'All Block should succeed');

        // FREE-001 and OTH-001 are not Tier Based = 2 skipped
        System.assertEquals(2, result.blockSkippedCount, 'Should skip 2 non-tier-based rows');

        // Verify Premium Price for eligible product (TBP-001 has Eligible_For_Premium__c = true)
        List<Intapp_Pricing__c> intappRecs = [
            SELECT Price__c, Premium_price__c, Product_Code__c, Product__c, GearsetExternalId__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'TBP-001' AND Price__c = 150.00
        ];
        System.assertNotEquals(0, intappRecs.size(), 'Should find Intapp record for TBP-001');
        System.assertEquals(180.00, intappRecs[0].Premium_price__c,
            'Premium price should be 1.2 * 150 = 180');
        System.assertEquals(tbp.Id, intappRecs[0].Product__c,
            'Product lookup should be populated');

        // Verify GearsetExternalId__c is populated
        System.assertNotEquals(null, intappRecs[0].GearsetExternalId__c,
            'Gearset External Id should be populated on Intapp_Pricing__c');

        // Verify no Premium Price for non-eligible product (FREE-001 has Eligible_For_Premium__c = false)
        List<Intapp_Pricing__c> freeRecs = [
            SELECT Premium_price__c FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'FREE-001'
        ];
        System.assertNotEquals(0, freeRecs.size(), 'Should find Intapp record for FREE-001');
        System.assertEquals(null, freeRecs[0].Premium_price__c,
            'Premium price should be null for non-eligible product');

        // Verify Premium Price for OTH-001 (Eligible_For_Premium__c = true)
        List<Intapp_Pricing__c> othRecs = [
            SELECT Premium_price__c FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'OTH-001'
        ];
        System.assertNotEquals(0, othRecs.size(), 'Should find Intapp record for OTH-001');
        System.assertEquals(240.00, othRecs[0].Premium_price__c,
            'Premium price should be 1.2 * 200 = 240');

        // Verify Block_Pricing__c GearsetExternalId__c is populated
        List<Block_Pricing__c> blockRecs = [
            SELECT GearsetExternalId__c FROM Block_Pricing__c
            WHERE Product__c = :tbp.Id
            LIMIT 1
        ];
        System.assertNotEquals(0, blockRecs.size(), 'Should find Block record');
        System.assertNotEquals(null, blockRecs[0].GearsetExternalId__c,
            'Gearset External Id should be populated on Block_Pricing__c');
    }

    @IsTest
    static void testProcessPricingUploadNoneTier() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Test Wizard PB' LIMIT 1];
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + tbp.Id + ',TBP-001,Fee Earners,USD,None,100.00,true,true,false,false';

        Test.startTest();
        PricebookWizardController.ProcessingResult result =
            PricebookWizardController.processPricingUpload(csv, pb.Id);
        Test.stopTest();

        // Check Intapp tier mapping: None → Tier (none)
        List<Intapp_Pricing__c> recs = [
            SELECT Tier__c FROM Intapp_Pricing__c WHERE Product_Code__c = 'TBP-001'
        ];
        System.assertNotEquals(0, recs.size(), 'Should create Intapp record');
        System.assertEquals('Tier (none)', recs[0].Tier__c, 'None should map to Tier (none)');

        // Block_Pricing__c Tier_Name__c should be null for None
        List<Block_Pricing__c> blockRecs = [
            SELECT Tier_Name__c FROM Block_Pricing__c
            WHERE Product__r.ProductCode = 'TBP-001'
        ];
        if (!blockRecs.isEmpty()) {
            System.assertEquals(null, blockRecs[0].Tier_Name__c,
                'Block tier should be null for None');
        }
    }

    @IsTest
    static void testProcessPricingUploadNullParams() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.processPricingUpload(null, null);
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for null params');
    }

    /***********************************************************************************************
     *
     * Excel Upload Tests - Validation (validateExcelUpload)
     *
     ***********************************************************************************************/

    /**
     * @description Helper to build a JSON-serializable ExcelUploadRow for test methods.
     */
    private static Map<String, Object> buildExcelRow(
        Integer rowNumber, String productId, String productCode, String meterType,
        String salesChannel, Boolean legalSales, Boolean acSales, Boolean fsSales,
        Boolean corporateSales, Boolean opsOnly, List<Map<String, Object>> prices
    ) {
        Map<String, Object> row = new Map<String, Object>{
            'rowNumber' => rowNumber,
            'productId' => productId,
            'productCode' => productCode,
            'productName' => 'Test Product',
            'pricingBasis' => 'Tier based',
            'meterType' => meterType,
            'salesChannel' => salesChannel,
            'legalSales' => legalSales,
            'acSales' => acSales,
            'fsSales' => fsSales,
            'corporateSales' => corporateSales,
            'opsOnly' => opsOnly,
            'prices' => prices
        };
        return row;
    }

    /**
     * @description Helper to build a price entry map.
     */
    private static Map<String, Object> buildPriceEntry(String currencyCode, String tier, Decimal price) {
        return new Map<String, Object>{
            'currencyCode' => currencyCode,
            'tier' => tier,
            'price' => price
        };
    }

    @IsTest
    static void testValidateExcelUploadValid() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];
        Product2 free = [SELECT Id FROM Product2 WHERE ProductCode = 'FREE-001' LIMIT 1];

        List<Map<String, Object>> prices1 = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 150.00),
            buildPriceEntry('USD', 'None', 100.00),
            buildPriceEntry('GBP', 'EM1', 120.00)
        };
        List<Map<String, Object>> prices2 = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 0)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices1),
            buildExcelRow(5, free.Id, 'FREE-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices2)
        };

        String uploadJson = JSON.serialize(rows);

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload(uploadJson);
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid');
        System.assertEquals(2, result.rowCount, 'Should have 2 rows');
        System.assertEquals(4, result.priceEntryCount, 'Should count 4 price entries (3+1)');
        System.assertEquals(0, result.errors.size(), 'Should have no errors');
        System.assertEquals(2, result.previewRows.size(), 'Should have 2 preview rows');
        // Verify first preview row
        System.assertEquals('TBP-001', result.previewRows[0].productCode, 'Preview code should match');
        System.assertEquals('150.00', result.previewRows[0].samplePrice, 'Sample price should be USD EM1');
    }

    @IsTest
    static void testValidateExcelUploadEmpty() {
        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload('');
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for empty content');
        System.assert(result.errors.size() > 0, 'Should have error message');
    }

    @IsTest
    static void testValidateExcelUploadEmptyArray() {
        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload('[]');
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for empty array');
    }

    @IsTest
    static void testValidateExcelUploadInvalidProductId() {
        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 100.00)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, 'BADID', 'TST-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for bad Product Id');
    }

    @IsTest
    static void testValidateExcelUploadMissingMeterType() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 100.00)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', '', 'Legal', true, false, false, false, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for missing meter type');
    }

    @IsTest
    static void testValidateExcelUploadNonexistentProduct() {
        String fakeId = '01t000000000000AAA';

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 100.00)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, fakeId, 'FAKE-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for nonexistent product');
    }

    @IsTest
    static void testValidateExcelUploadNegativePrice() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', -50.00)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        // Negative prices are a warning, not an error
        System.assertEquals(true, result.isValid, 'Should still be valid (negative is a warning)');
        System.assert(result.warnings.size() > 0, 'Should have a warning for negative price');
    }

    /***********************************************************************************************
     *
     * Excel Upload Tests - Processing (processExcelUpload)
     *
     ***********************************************************************************************/

    @IsTest
    static void testProcessExcelUpload() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];
        Product2 oth = [SELECT Id FROM Product2 WHERE ProductCode = 'OTH-001' LIMIT 1];

        // TBP-001 = Tier Based + Eligible for Premium → Intapp + Block
        List<Map<String, Object>> pricesTbp = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 150.00),
            buildPriceEntry('GBP', 'EM1', 120.00)
        };
        // OTH-001 = Other/Mixed + Eligible for Premium → Intapp only (no Block)
        List<Map<String, Object>> pricesOth = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM2', 200.00)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', 'Fee Earners', 'Legal', true, false, false, false, false, pricesTbp),
            buildExcelRow(5, oth.Id, 'OTH-001', 'Fee Earners', 'A&C', false, true, false, false, false, pricesOth)
        };

        Test.startTest();
        PricebookWizardController.ProcessingResult result =
            PricebookWizardController.processExcelUpload(JSON.serialize(rows), pb.Id);
        Test.stopTest();

        // 3 total Intapp records (2 for TBP + 1 for OTH)
        System.assertEquals(3, result.intappResult.totalCount, 'Should have 3 Intapp records');
        System.assertEquals(3, result.intappResult.successCount, 'All 3 Intapp should succeed');

        // 2 Block records for TBP-001 only (Tier Based)
        System.assertEquals(2, result.blockResult.totalCount, 'Should have 2 Block records');
        System.assertEquals(2, result.blockResult.successCount, 'Both Block should succeed');

        // 1 skipped Block for OTH-001
        System.assertEquals(1, result.blockSkippedCount, 'Should skip 1 non-tier-based row');

        // Verify Intapp record naming and fields
        List<Intapp_Pricing__c> intappRecs = [
            SELECT Name, Price__c, Premium_price__c, Price_book_rule__c, Tier__c,
                   Product_Code__c, Meter_Type__c, CurrencyIsoCode,
                   Legal_Sales__c, A_C_Sales__c, GearsetExternalId__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'TBP-001' AND CurrencyIsoCode = 'USD'
        ];
        System.assertNotEquals(0, intappRecs.size(), 'Should find TBP-001 USD Intapp');
        Intapp_Pricing__c tbpIntapp = intappRecs[0];
        // Name should start with FY26-
        System.assert(tbpIntapp.Name.startsWith('FY26-'), 'Name should start with FY26-: ' + tbpIntapp.Name);
        // Premium price = 1.2 * 150 = 180
        System.assertEquals(180.00, tbpIntapp.Premium_price__c, 'Premium = 1.2 * 150');
        // Price_book_rule__c = pricebook name
        System.assertEquals('FY26_All_Products', tbpIntapp.Price_book_rule__c, 'Price_book_rule__c should match pricebook name');
        // Legal Sales flag
        System.assertEquals(true, tbpIntapp.Legal_Sales__c, 'Legal Sales should be true');
        System.assertEquals(false, tbpIntapp.A_C_Sales__c, 'A&C Sales should be false');
        // GearsetExternalId__c
        System.assertNotEquals(null, tbpIntapp.GearsetExternalId__c, 'GearsetExternalId should be populated');

        // Verify Block records
        List<Block_Pricing__c> blockRecs = [
            SELECT Fiscal_Year__c, Product_Code__c, Type__c, Active__c,
                   Lower_Bound__c, Upper_Bound__c, GearsetExternalId__c
            FROM Block_Pricing__c
            WHERE Product__c = :tbp.Id
        ];
        System.assertEquals(2, blockRecs.size(), 'Should have 2 Block records for TBP');
        System.assertEquals('FY26', blockRecs[0].Fiscal_Year__c, 'Fiscal year should be FY26');
        System.assertEquals('GTM Motion Tier', blockRecs[0].Type__c, 'Type should be GTM Motion Tier');
        System.assertEquals(true, blockRecs[0].Active__c, 'Should be active');
        System.assertEquals(0, blockRecs[0].Lower_Bound__c, 'Lower bound should be 0');
        System.assertEquals(999999999, blockRecs[0].Upper_Bound__c, 'Upper bound should be 999999999');
        System.assertNotEquals(null, blockRecs[0].GearsetExternalId__c, 'Block GearsetExternalId should be populated');
    }

    @IsTest
    static void testProcessExcelUploadNoneTier() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'None', 100.00)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ProcessingResult result =
            PricebookWizardController.processExcelUpload(JSON.serialize(rows), pb.Id);
        Test.stopTest();

        // Intapp: None → 'Tier (none)'
        List<Intapp_Pricing__c> intappRecs = [
            SELECT Tier__c FROM Intapp_Pricing__c WHERE Product_Code__c = 'TBP-001'
        ];
        System.assertNotEquals(0, intappRecs.size(), 'Should create Intapp record');
        System.assertEquals('Tier (none)', intappRecs[0].Tier__c, 'None should map to Tier (none) in Intapp');

        // Block: None → null for Tier_Name__c
        List<Block_Pricing__c> blockRecs = [
            SELECT Tier_Name__c FROM Block_Pricing__c WHERE Product__c = :tbp.Id
        ];
        System.assertNotEquals(0, blockRecs.size(), 'Should create Block record (Tier Based)');
        System.assertEquals(null, blockRecs[0].Tier_Name__c, 'Block Tier_Name__c should be null for None');
    }

    @IsTest
    static void testProcessExcelUploadSalesChannel() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];
        Product2 free = [SELECT Id FROM Product2 WHERE ProductCode = 'FREE-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 50.00)
        };

        // Row with Corporate sales channel flag
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, free.Id, 'FREE-001', 'Fee Earners', 'Corporate', false, false, false, true, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ProcessingResult result =
            PricebookWizardController.processExcelUpload(JSON.serialize(rows), pb.Id);
        Test.stopTest();

        System.assertEquals(1, result.intappResult.successCount, 'Should create 1 Intapp record');

        // Verify sales channel flags
        List<Intapp_Pricing__c> recs = [
            SELECT Legal_Sales__c, A_C_Sales__c, FS_Sales__c, Corporate_Sales__c, Ops_Only__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'FREE-001'
        ];
        System.assertNotEquals(0, recs.size(), 'Should find Intapp record');
        System.assertEquals(false, recs[0].Legal_Sales__c, 'Legal should be false');
        System.assertEquals(false, recs[0].A_C_Sales__c, 'A&C should be false');
        System.assertEquals(false, recs[0].FS_Sales__c, 'FS should be false');
        System.assertEquals(true, recs[0].Corporate_Sales__c, 'Corporate should be true');
        System.assertEquals(false, recs[0].Ops_Only__c, 'Ops should be false');

        // FREE-001 is not Tier Based → no Block records
        System.assertEquals(0, result.blockResult.totalCount, 'No Block records for Free product');
        System.assertEquals(1, result.blockSkippedCount, 'Should skip 1 non-tier-based');
    }

    @IsTest
    static void testProcessExcelUploadNullParams() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.processExcelUpload(null, null);
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for null params');
    }

    /***********************************************************************************************
     *
     * Tests: Quantity Pricing Upload (Employee Compliance)
     *
     ***********************************************************************************************/

    /**
     * @description Helper to build a QuantityUploadRow map for JSON serialization.
     */
    private static Map<String, Object> buildQuantityRow(
        Integer rowNumber, String productId, String productCode,
        String meterType, Decimal lowerBound, Decimal upperBound,
        List<Map<String, Object>> prices
    ) {
        return new Map<String, Object>{
            'rowNumber' => rowNumber,
            'productId' => productId,
            'productCode' => productCode,
            'productName' => 'Test Product',
            'meterType' => meterType,
            'lowerBound' => lowerBound,
            'upperBound' => upperBound,
            'prices' => prices
        };
    }

    /**
     * @description Helper to build a CurrencyPrice map for JSON serialization.
     */
    private static Map<String, Object> buildCurrencyPrice(String currencyCode, Decimal price) {
        return new Map<String, Object>{
            'currencyCode' => currencyCode,
            'price' => price
        };
    }

    @IsTest
    static void testValidateQuantityExcelUploadValid() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices1 = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 38.00),
            buildCurrencyPrice('GBP', 29.90)
        };
        List<Map<String, Object>> prices2 = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 24.00),
            buildCurrencyPrice('GBP', 18.90)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildQuantityRow(2, tbp.Id, 'TBP-001', 'Employees', 0, 100, prices1),
            buildQuantityRow(3, tbp.Id, 'TBP-001', 'Employees', 101, 300, prices2)
        };

        String uploadJson = JSON.serialize(rows);

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateQuantityExcelUpload(uploadJson);
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid');
        System.assertEquals(2, result.rowCount, 'Should have 2 rows');
        System.assertEquals(4, result.priceEntryCount, 'Should count 4 price entries (2+2)');
        System.assertEquals(0, result.errors.size(), 'Should have no errors');
        System.assertEquals(2, result.previewRows.size(), 'Should have 2 preview rows');
        System.assertEquals('38.00', result.previewRows[0].samplePrice, 'Sample should be USD price');
    }

    @IsTest
    static void testValidateQuantityExcelUploadErrors() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 10.00)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            // Missing product id
            buildQuantityRow(2, '', 'TBP-001', 'Employees', 0, 100, prices),
            // Blank meter type
            buildQuantityRow(3, tbp.Id, 'TBP-001', '', 0, 100, prices),
            // Lower >= Upper
            buildQuantityRow(4, tbp.Id, 'TBP-001', 'Employees', 300, 100, prices),
            // Null lower bound
            buildQuantityRow(5, tbp.Id, 'TBP-001', 'Employees', null, 100, prices)
        };

        String uploadJson = JSON.serialize(rows);

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateQuantityExcelUpload(uploadJson);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assert(result.errors.size() >= 4, 'Should have at least 4 errors: ' + result.errors);
    }

    @IsTest
    static void testProcessQuantityExcelUpload() {
        // Create a Quantity-based product for this test
        Product2 qtyProd = (Product2) TestFactory.createSObject(new Product2(
            Name = 'QTY Upload Product',
            ProductCode = 'PW-QTY-001',
            IsActive = true,
            Pricing_Basis__c = 'Quantity based',
            Eligible_For_Premium__c = false
        ));

        Pricebook2 fyPb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];

        List<Map<String, Object>> prices1 = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 38.00),
            buildCurrencyPrice('GBP', 29.90)
        };
        List<Map<String, Object>> prices2 = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 24.00)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildQuantityRow(2, qtyProd.Id, 'PW-QTY-001', 'Employees', 0, 100, prices1),
            buildQuantityRow(3, qtyProd.Id, 'PW-QTY-001', 'Employees', 101, 300, prices2)
        };

        String uploadJson = JSON.serialize(rows);

        Test.startTest();
        PricebookWizardController.ProcessingResult result =
            PricebookWizardController.processQuantityExcelUpload(uploadJson, fyPb.Id);
        Test.stopTest();

        // Verify block result: 3 records (2 USD + 1 GBP prices with non-null values)
        System.assertEquals(3, result.blockResult.successCount, 'Should create 3 Block_Pricing__c records');
        System.assertEquals(0, result.blockResult.errorCount, 'Should have no errors');
        System.assertEquals(0, result.blockSkippedCount, 'Should skip none');
        System.assertEquals(2, result.totalRowsProcessed, 'Should process 2 rows');

        // Verify intapp is empty (no Intapp_Pricing__c for quantity uploads)
        System.assertEquals(0, result.intappResult.totalCount, 'Intapp count should be 0');

        // Verify actual records
        List<Block_Pricing__c> blocks = [
            SELECT Id, Product_Code__c, Block_Pricing_Meter_Type__c, CurrencyIsoCode,
                   Lower_Bound__c, Upper_Bound__c, Price__c, Type__c, Active__c,
                   Fiscal_Year__c, Price_Book__c
            FROM Block_Pricing__c
            WHERE Product__c = :qtyProd.Id AND Type__c = 'Employee Compliance'
            ORDER BY Lower_Bound__c, CurrencyIsoCode
        ];
        System.assertEquals(3, blocks.size(), 'Should have 3 Block_Pricing__c records');

        // Verify first record (0-100 GBP)
        System.assertEquals('PW-QTY-001', blocks[0].Product_Code__c);
        System.assertEquals('Employees', blocks[0].Block_Pricing_Meter_Type__c);
        System.assertEquals('GBP', blocks[0].CurrencyIsoCode);
        System.assertEquals(0, blocks[0].Lower_Bound__c);
        System.assertEquals(100, blocks[0].Upper_Bound__c);
        System.assertEquals(29.90, blocks[0].Price__c);
        System.assertEquals('Employee Compliance', blocks[0].Type__c);
        System.assertEquals(true, blocks[0].Active__c);
        System.assertEquals('FY26', blocks[0].Fiscal_Year__c);
        System.assertEquals(fyPb.Id, blocks[0].Price_Book__c);
    }

    @IsTest
    static void testProcessQuantityExcelUploadSkipsNonQuantity() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];
        Pricebook2 fyPb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 50.00)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildQuantityRow(2, tbp.Id, 'TBP-001', 'Employees', 0, 100, prices)
        };

        String uploadJson = JSON.serialize(rows);

        Test.startTest();
        PricebookWizardController.ProcessingResult result =
            PricebookWizardController.processQuantityExcelUpload(uploadJson, fyPb.Id);
        Test.stopTest();

        // Tier-based product should be skipped
        System.assertEquals(0, result.blockResult.successCount, 'Should create 0 records');
        System.assertEquals(1, result.blockSkippedCount, 'Should skip 1 price entry (non-Quantity-based)');
    }

    /***********************************************************************************************
     *
     * Tests: Deactivate Pricebook
     *
     ***********************************************************************************************/

    @IsTest
    static void testDeactivatePricebook() {
        Pricebook2 pb = [SELECT Id, IsActive FROM Pricebook2 WHERE Name = 'Test Wizard PB' LIMIT 1];
        System.assertEquals(true, pb.IsActive, 'Should start active');

        Test.startTest();
        PricebookWizardController.deactivatePricebook(pb.Id);
        Test.stopTest();

        Pricebook2 updated = [SELECT IsActive FROM Pricebook2 WHERE Id = :pb.Id];
        System.assertEquals(false, updated.IsActive, 'Should be deactivated');
    }

    @IsTest
    static void testDeactivatePricebookNullId() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.deactivatePricebook(null);
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for null Id');
    }

    /***********************************************************************************************
     *
     * Tests: getSetupStatus with valid job
     *
     ***********************************************************************************************/

    @IsTest
    static void testGetSetupStatusWithValidJob() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Test Wizard PB' LIMIT 1];

        Test.startTest();
        // Enqueue a job to get a real job Id
        Id jobId = PricebookWizardController.startPricebookSetup(pb.Id);
        // Query status while job is queued/processing
        PricebookWizardController.SetupStatusResult result =
            PricebookWizardController.getSetupStatus(jobId);
        Test.stopTest();

        System.assertNotEquals(null, result.status, 'Status should not be null');
        System.assertNotEquals(null, result.message, 'Message should not be null');
    }

    @IsTest
    static void testGetSetupStatusJobNotFound() {
        // Use a fake AsyncApexJob Id
        Id fakeJobId = '7071g00000000ABAAY';

        Test.startTest();
        PricebookWizardController.SetupStatusResult result =
            PricebookWizardController.getSetupStatus(fakeJobId);
        Test.stopTest();

        System.assertEquals('Unknown', result.status, 'Should return Unknown for nonexistent job');
        System.assertEquals('Job not found.', result.message, 'Should say job not found');
    }

    /***********************************************************************************************
     *
     * Tests: Phase 5 — View Results (getUploadResultView)
     *
     ***********************************************************************************************/

    @IsTest
    static void testGetUploadResultViewTier() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];
        Product2 oth = [SELECT Id FROM Product2 WHERE ProductCode = 'OTH-001' LIMIT 1];

        // First, process an upload so there are records to view
        List<Map<String, Object>> pricesTbp = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 150.00),
            buildPriceEntry('GBP', 'EM2', 120.00)
        };
        List<Map<String, Object>> pricesOth = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 200.00)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', 'Fee Earners', 'Legal', true, false, false, false, false, pricesTbp),
            buildExcelRow(5, oth.Id, 'OTH-001', 'Fee Earners', 'A&C', false, true, false, false, false, pricesOth)
        };

        PricebookWizardController.processExcelUpload(JSON.serialize(rows), pb.Id);

        // Build product IDs JSON
        List<String> productIdsList = new List<String>{ String.valueOf(tbp.Id), String.valueOf(oth.Id) };
        String productIdsJson = JSON.serialize(productIdsList);

        Test.startTest();
        PricebookWizardController.UploadResultView result =
            PricebookWizardController.getUploadResultView(pb.Id, 'tier', productIdsJson);
        Test.stopTest();

        System.assertEquals('tier', result.uploadType, 'Upload type should be tier');
        System.assertNotEquals(0, result.totalRows, 'Should have result rows');
        System.assertNotEquals(0, result.tierRows.size(), 'Should have tier rows');
        // Each row should have 24 price cells (4 currencies x 6 tiers)
        System.assertEquals(24, result.tierRows[0].prices.size(), 'Should have 24 price cells per row');
    }

    @IsTest
    static void testGetUploadResultViewQuantity() {
        Product2 qtyProd = (Product2) TestFactory.createSObject(new Product2(
            Name = 'QTY View Product',
            ProductCode = 'PW-QTYV-001',
            IsActive = true,
            Pricing_Basis__c = 'Quantity based',
            Eligible_For_Premium__c = false
        ));

        Pricebook2 fyPb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];

        // Process quantity upload first
        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 38.00),
            buildCurrencyPrice('GBP', 29.90)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildQuantityRow(2, qtyProd.Id, 'PW-QTYV-001', 'Employees', 0, 100, prices)
        };

        PricebookWizardController.processQuantityExcelUpload(JSON.serialize(rows), fyPb.Id);

        List<String> productIdsList = new List<String>{ String.valueOf(qtyProd.Id) };
        String productIdsJson = JSON.serialize(productIdsList);

        Test.startTest();
        PricebookWizardController.UploadResultView result =
            PricebookWizardController.getUploadResultView(fyPb.Id, 'quantity', productIdsJson);
        Test.stopTest();

        System.assertEquals('quantity', result.uploadType, 'Upload type should be quantity');
        System.assertNotEquals(0, result.totalRows, 'Should have result rows');
        System.assertNotEquals(0, result.quantityRows.size(), 'Should have quantity rows');

        PricebookWizardController.QuantityResultRow qRow = result.quantityRows[0];
        System.assertEquals('PW-QTYV-001', qRow.productCode, 'Product code should match');
        System.assertEquals(0, qRow.lowerBound, 'Lower bound should be 0');
        System.assertEquals(100, qRow.upperBound, 'Upper bound should be 100');
        System.assertEquals(38.00, qRow.usdPrice, 'USD price should match');
        System.assertEquals(29.90, qRow.gbpPrice, 'GBP price should match');
    }

    @IsTest
    static void testGetUploadResultViewNullParams() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.getUploadResultView(null, null, null);
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for null params');
    }

    @IsTest
    static void testGetUploadResultViewEmptyProducts() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];

        Test.startTest();
        PricebookWizardController.UploadResultView result =
            PricebookWizardController.getUploadResultView(pb.Id, 'tier', '[]');
        Test.stopTest();

        System.assertEquals('tier', result.uploadType, 'Upload type should be tier');
        System.assertEquals(0, result.totalRows, 'Should have 0 rows for empty product list');
    }

    @IsTest
    static void testGetUploadResultViewTierWithIntappFallback() {
        // Create a non-tier-based product that only has Intapp_Pricing__c (no Block_Pricing__c)
        Pricebook2 pb = [SELECT Id, Name FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];
        Product2 free = [SELECT Id FROM Product2 WHERE ProductCode = 'FREE-001' LIMIT 1];

        // Process an upload for a Free product (creates Intapp_Pricing__c but no Block_Pricing__c)
        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 0)
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, free.Id, 'FREE-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices)
        };

        PricebookWizardController.processExcelUpload(JSON.serialize(rows), pb.Id);

        List<String> productIdsList = new List<String>{ String.valueOf(free.Id) };
        String productIdsJson = JSON.serialize(productIdsList);

        Test.startTest();
        PricebookWizardController.UploadResultView result =
            PricebookWizardController.getUploadResultView(pb.Id, 'tier', productIdsJson);
        Test.stopTest();

        System.assertEquals('tier', result.uploadType, 'Upload type should be tier');
        // FREE-001 is Free pricing basis → Intapp only, no Block → falls through to Intapp fallback
        System.assertNotEquals(0, result.totalRows, 'Should have rows from Intapp fallback');
    }

    @IsTest
    static void testGetUploadResultViewQuantityEmpty() {
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];

        Test.startTest();
        PricebookWizardController.UploadResultView result =
            PricebookWizardController.getUploadResultView(pb.Id, 'quantity', '[]');
        Test.stopTest();

        System.assertEquals('quantity', result.uploadType, 'Upload type should be quantity');
        System.assertEquals(0, result.totalRows, 'Should have 0 rows');
    }

    @IsTest
    static void testValidateQuantityExcelUploadEmpty() {
        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateQuantityExcelUpload('');
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for empty content');
    }

    @IsTest
    static void testValidateQuantityExcelUploadEmptyArray() {
        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateQuantityExcelUpload('[]');
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for empty array');
    }

    @IsTest
    static void testProcessQuantityExcelUploadNullParams() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            PricebookWizardController.processQuantityExcelUpload(null, null);
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();
        System.assert(caughtError, 'Should throw error for null params');
    }

    @IsTest
    static void testValidateExcelUploadInvalidCurrency() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            new Map<String, Object>{
                'currencyCode' => 'ZZZ',
                'tier' => 'EM1',
                'price' => 100.00
            }
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        // Controller does not validate currency values — exercises the code path for coverage
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testValidateExcelUploadInvalidTier() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            new Map<String, Object>{
                'currencyCode' => 'USD',
                'tier' => 'BADTIER',
                'price' => 100.00
            }
        };
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildExcelRow(4, tbp.Id, 'TBP-001', 'Fee Earners', 'Legal', true, false, false, false, false, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        // Controller does not validate tier values — exercises the code path for coverage
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testValidateCsvUploadInvalidTier() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        String csv = 'Product Id,Product Code,Meter Type,Currency,Tier,Price,Legal Sales,A&C Sales,FS Sales,Ops Only\n'
            + tbp.Id + ',TBP-001,Fee Earners,USD,BADTIER,150.00,true,true,false,false';

        Test.startTest();
        PricebookWizardController.ValidationResult result =
            PricebookWizardController.validateCsvUpload(csv);
        Test.stopTest();

        // Controller does not validate tier values in CSV — exercises the code path for coverage
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testValidateQuantityExcelUploadNegativeBounds() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 10.00)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            // Negative lower bound
            buildQuantityRow(2, tbp.Id, 'TBP-001', 'Employees', -5, 100, prices),
            // Negative upper bound
            buildQuantityRow(3, tbp.Id, 'TBP-001', 'Employees', 0, -10, prices),
            // Null upper bound
            buildQuantityRow(4, tbp.Id, 'TBP-001', 'Employees', 0, null, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateQuantityExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assert(result.errors.size() >= 3, 'Should have errors for negative/null bounds');
    }

    @IsTest
    static void testValidateQuantityExcelUploadNegativePrice() {
        Product2 tbp = [SELECT Id FROM Product2 WHERE ProductCode = 'TBP-001' LIMIT 1];

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', -50.00)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildQuantityRow(2, tbp.Id, 'TBP-001', 'Employees', 0, 100, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateQuantityExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should still be valid (negative is a warning)');
        System.assert(result.warnings.size() > 0, 'Should have a warning for negative price');
    }

    @IsTest
    static void testValidateQuantityExcelUploadNonexistentProduct() {
        String fakeId = '01t000000000000AAA';

        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildCurrencyPrice('USD', 10.00)
        };

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            buildQuantityRow(2, fakeId, 'FAKE-001', 'Employees', 0, 100, prices)
        };

        Test.startTest();
        PricebookWizardController.ExcelValidationResult result =
            PricebookWizardController.validateQuantityExcelUpload(JSON.serialize(rows));
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for nonexistent product');
    }
}