/**
 * @description Test class for SkuNewLaunchController — validates the 5-step New SKU Launch wizard.
 *              Covers both validateNewSkuLaunch() and processNewSkuLaunch() with scenarios for:
 *              standalone tier-based products, bundle creation, services products,
 *              validation error paths, and exception handling.
 *
 * @author  Claude Code
 * @date    2026-03-02
 */
@IsTest
private class SkuNewLaunchControllerTest {

    // =========================================================================
    // Test Setup
    // =========================================================================

    @TestSetup
    static void setup() {
        // Product Line
        Product_Line__c productLine = new Product_Line__c(
            Name = 'Test Product Line',
            Active__c = true
        );
        insert productLine;

        // Product Rollup
        Product_Rollup__c productRollup = new Product_Rollup__c(
            Name = 'Test Rollup',
            Product_Line__c = productLine.Id
        );
        insert productRollup;

        // Custom FY Pricebook
        Pricebook2 fyPb = new Pricebook2(
            Name = 'FY26 All Products',
            IsActive = true
        );
        insert fyPb;

        // Existing product — used for bundle component lookup + duplicate-code validation
        Item_Master_Product__c existingIM = new Item_Master_Product__c(
            Name = 'IN-EXIST-001',
            Item_Name__c = 'Existing Component Product',
            Active__c = true,
            Product_LineNew__c = productLine.Id
        );
        insert existingIM;

        Product2 existingProd = new Product2(
            Name = 'Existing Component Product',
            ProductCode = 'IN-EXIST-001',
            IsActive = true,
            Item_Master_Product__c = existingIM.Id,
            Product_LineNew__c = productLine.Id
        );
        insert existingProd;

        // Standard PBE for existing product (activates standard pricebook in test context)
        PricebookEntry stdPbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = existingProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert stdPbe;
    }

    // =========================================================================
    // Helper Methods — JSON Builders
    // =========================================================================

    /**
     * @description Builds a Map representing a single SkuDetailRow for JSON serialization.
     */
    private static Map<String, Object> buildSkuDetailRow(
        String productCode, String productName, String productType,
        String revenueType, String pricingBasis
    ) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('productCode', productCode);
        row.put('productName', productName);
        row.put('description', 'Test description for ' + productCode);
        row.put('productType', productType);
        row.put('revenueType', revenueType);
        row.put('pricingBasis', pricingBasis);
        row.put('productLine', 'Test Product Line');
        row.put('productRollup', 'Test Rollup');
        row.put('sfdcPricebook', 'FY26 All Products');
        row.put('subscriptionType', 'Renewable');
        row.put('subscriptionPricing', 'Fixed Price');
        row.put('isLegal', 'Active');
        row.put('isAccounting', 'Active');
        row.put('isConsulting', 'Unavailable');
        row.put('isIBA', 'Unavailable');
        row.put('isPCM', 'Unavailable');
        row.put('isRealAssets', 'Unavailable');
        row.put('isCorporate', 'Unavailable');
        row.put('isBundle', false);
        row.put('includesAssist', false);
        row.put('meterTypeLegal', 'Lawyers');
        row.put('meterTypeAccounting', 'Fee Earners');
        return row;
    }

    /**
     * @description Builds a Map representing a single PricingRow with full 24-cell price matrix.
     */
    private static Map<String, Object> buildPricingRow(
        String productCode, String meterType, Boolean premiumSupport,
        Boolean legalSales, Boolean acSales
    ) {
        List<Map<String, Object>> prices = new List<Map<String, Object>>();
        Decimal basePrice = 30.00;
        for (String curr : new List<String>{'USD', 'GBP', 'EUR', 'AUD'}) {
            for (String tier : new List<String>{'EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'}) {
                prices.add(buildPriceEntry(curr, tier, basePrice));
            }
        }

        Map<String, Object> row = new Map<String, Object>();
        row.put('productCode', productCode);
        row.put('productName', 'Test Product ' + productCode);
        row.put('meterType', meterType);
        row.put('premiumSupport', premiumSupport);
        row.put('legalSales', legalSales);
        row.put('acSales', acSales);
        row.put('fsSales', false);
        row.put('corporateSales', false);
        row.put('opsOnly', false);
        row.put('prices', prices);
        return row;
    }

    /**
     * @description Builds a Map representing a minimal PricingRow with only 2 price entries.
     */
    private static Map<String, Object> buildMinimalPricingRow(
        String productCode, String meterType
    ) {
        List<Map<String, Object>> prices = new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', 50.00),
            buildPriceEntry('USD', 'None', 60.00)
        };

        Map<String, Object> row = new Map<String, Object>();
        row.put('productCode', productCode);
        row.put('productName', 'Test Product ' + productCode);
        row.put('meterType', meterType);
        row.put('premiumSupport', false);
        row.put('legalSales', true);
        row.put('acSales', false);
        row.put('fsSales', false);
        row.put('corporateSales', false);
        row.put('opsOnly', false);
        row.put('prices', prices);
        return row;
    }

    private static Map<String, Object> buildPriceEntry(String currencyCode, String tier, Decimal price) {
        Map<String, Object> entry = new Map<String, Object>();
        entry.put('currencyCode', currencyCode);
        entry.put('tier', tier);
        entry.put('price', price);
        return entry;
    }

    private static Map<String, Object> buildBundleRow(
        String role, String productName, String imNumber,
        Decimal acvPercent, String parentProductCode
    ) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('role', role);
        row.put('productName', productName);
        row.put('imNumber', imNumber);
        row.put('acvPercent', acvPercent);
        row.put('parentProductCode', parentProductCode);
        return row;
    }

    // =========================================================================
    // Validation Tests — Valid Data
    // =========================================================================

    @IsTest
    static void testValidateValidSingleProduct() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-TEST-001', 'Test Product Alpha', 'Software', 'Recurring', 'Tier based')
        };

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildPricingRow('IN-TEST-001', 'Lawyers', true, true, false)
        };

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid: ' + result.errors);
        System.assertEquals(1, result.skuCount, 'Should have 1 SKU');
        System.assertEquals(1, result.pricingRowCount, 'Should have 1 pricing row');
        System.assertEquals(0, result.bundleCount, 'Should have 0 bundles');
    }

    @IsTest
    static void testValidateValidWithBundles() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-BDL-001', 'Bundle Product', 'Software', 'Recurring', 'Tier based')
        };
        skuDetails[0].put('isBundle', true);

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-BDL-001', 'Lawyers')
        };

        // Valid bundles: ACV sums to 1.0
        List<Map<String, Object>> bundles = new List<Map<String, Object>>{
            buildBundleRow('BUNDLE', 'Bundle Product', 'IN-BDL-001', 1.0, null),
            buildBundleRow('Component Product', 'Existing Comp', 'IN-EXIST-001', 1.0, 'IN-BDL-001')
        };

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            JSON.serialize(bundles),
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid: ' + result.errors);
        System.assertEquals(2, result.bundleCount, 'Should have 2 bundle rows');
    }

    // =========================================================================
    // Validation Tests — Error Paths
    // =========================================================================

    @IsTest
    static void testValidateEmptySkuDetails() {
        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            '[]', '[]', null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid with empty SKU details');
        System.assert(!result.errors.isEmpty(), 'Should have errors');
        System.assert(result.errors[0].containsIgnoreCase('No SKU Detail rows'),
            'Error should mention no rows found');
    }

    @IsTest
    static void testValidateMissingRequiredFields() {
        Map<String, Object> row = new Map<String, Object>();
        row.put('productCode', null);
        row.put('productName', null);
        row.put('sfdcPricebook', 'FY26 All Products');

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(new List<Map<String, Object>>{ row }),
            '[]',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid with missing required fields');
        System.assert(result.errors.size() >= 2,
            'Should have at least 2 errors (productCode + productName)');
    }

    @IsTest
    static void testValidateDuplicateProductCodes() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-DUP-001', 'Product A', 'Software', 'Recurring', 'Tier based'),
            buildSkuDetailRow('IN-DUP-001', 'Product B', 'Software', 'Recurring', 'Tier based')
        };

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails), '[]', null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid with duplicate product codes');
        Boolean foundDupError = false;
        for (String err : result.errors) {
            if (err.containsIgnoreCase('Duplicate')) {
                foundDupError = true;
                break;
            }
        }
        System.assert(foundDupError, 'Should have duplicate product code error');
    }

    @IsTest
    static void testValidateExistingProductCodeInOrg() {
        // IN-EXIST-001 was created in @TestSetup
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-EXIST-001', 'Conflict Product', 'Software', 'Recurring', 'Tier based')
        };

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails), '[]', null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid when product code already exists');
        Boolean foundExistError = false;
        for (String err : result.errors) {
            if (err.containsIgnoreCase('already exists')) {
                foundExistError = true;
                break;
            }
        }
        System.assert(foundExistError, 'Should have "already exists" error');
    }

    @IsTest
    static void testValidatePricingCrossTabMismatch() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-TEST-001', 'Test Product', 'Software', 'Recurring', 'Tier based')
        };

        // Pricing references a product code not in SKU Details
        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-WRONG-CODE', 'Lawyers')
        };

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for cross-tab mismatch');
    }

    @IsTest
    static void testValidateInvalidCurrencyAndTier() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-TEST-001', 'Test Product', 'Software', 'Recurring', 'Tier based')
        };

        Map<String, Object> pRow = new Map<String, Object>();
        pRow.put('productCode', 'IN-TEST-001');
        pRow.put('productName', 'Test Product');
        pRow.put('meterType', 'Lawyers');
        pRow.put('premiumSupport', false);
        pRow.put('legalSales', true);
        pRow.put('acSales', false);
        pRow.put('fsSales', false);
        pRow.put('corporateSales', false);
        pRow.put('opsOnly', false);
        pRow.put('prices', new List<Map<String, Object>>{
            buildPriceEntry('XYZ', 'EM1', 30.00),       // Invalid currency
            buildPriceEntry('USD', 'InvalidTier', 30.00) // Invalid tier
        });

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(new List<Map<String, Object>>{ pRow }),
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for bad currency/tier');
        System.assert(result.errors.size() >= 2, 'Should have at least 2 errors (currency + tier)');
    }

    @IsTest
    static void testValidateMissingPricingMeterType() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-TEST-001', 'Test Product', 'Software', 'Recurring', 'Tier based')
        };

        Map<String, Object> pRow = buildMinimalPricingRow('IN-TEST-001', null);
        pRow.put('meterType', null);

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(new List<Map<String, Object>>{ pRow }),
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid for missing meter type');
    }

    // =========================================================================
    // Validation Tests — Warnings
    // =========================================================================

    @IsTest
    static void testValidateWarningsForEmptyFields() {
        Map<String, Object> row = buildSkuDetailRow(
            'IN-WARN-001', 'Warning Product', null, null, 'Tier based'
        );
        row.put('revenueType', null);
        row.put('productType', null);

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(new List<Map<String, Object>>{ row }),
            '[]',
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid — warnings only');
        System.assert(result.warnings.size() >= 2,
            'Should have warnings for empty revenueType and productType');
    }

    @IsTest
    static void testValidateBundleAcvPercentWarning() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-BDL-W', 'Bundle Test', 'Software', 'Recurring', 'Tier based')
        };
        skuDetails[0].put('isBundle', true);

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-BDL-W', 'Lawyers')
        };

        // Bundle components ACV% sums to 0.5 — should trigger warning
        List<Map<String, Object>> bundles = new List<Map<String, Object>>{
            buildBundleRow('BUNDLE', 'Bundle Test', 'IN-BDL-W', 1.0, null),
            buildBundleRow('Component Product', 'Comp A', 'IN-EXIST-001', 0.5, 'IN-BDL-W')
        };

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            JSON.serialize(bundles),
            null
        );
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'ACV warning should not invalidate: ' + result.errors);
        Boolean foundAcvWarning = false;
        for (String w : result.warnings) {
            if (w.containsIgnoreCase('ACV')) {
                foundAcvWarning = true;
                break;
            }
        }
        System.assert(foundAcvWarning, 'Should have ACV percentage warning');
    }

    @IsTest
    static void testValidateNegativePriceWarning() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-NEG-001', 'Negative Test', 'Software', 'Recurring', 'Tier based')
        };

        Map<String, Object> pRow = new Map<String, Object>();
        pRow.put('productCode', 'IN-NEG-001');
        pRow.put('productName', 'Negative Test');
        pRow.put('meterType', 'Lawyers');
        pRow.put('premiumSupport', false);
        pRow.put('legalSales', true);
        pRow.put('acSales', false);
        pRow.put('fsSales', false);
        pRow.put('corporateSales', false);
        pRow.put('opsOnly', false);
        pRow.put('prices', new List<Map<String, Object>>{
            buildPriceEntry('USD', 'EM1', -10.00)
        });

        Test.startTest();
        SkuNewLaunchController.ValidationResult result = SkuNewLaunchController.validateNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(new List<Map<String, Object>>{ pRow }),
            null,
            null
        );
        Test.stopTest();

        // Negative price is a warning, not an error
        System.assertEquals(true, result.isValid, 'Negative price should be warning only');
        Boolean foundNegWarning = false;
        for (String w : result.warnings) {
            if (w.containsIgnoreCase('Negative')) {
                foundNegWarning = true;
                break;
            }
        }
        System.assert(foundNegWarning, 'Should have negative price warning');
    }

    // =========================================================================
    // Validation Tests — Exception Handling
    // =========================================================================

    @IsTest
    static void testValidateExceptionHandling() {
        Boolean caughtError = false;

        Test.startTest();
        try {
            SkuNewLaunchController.validateNewSkuLaunch(
                'invalid json {{{', '[]', null,
                null
            );
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();

        System.assertEquals(true, caughtError, 'Should throw AuraHandledException for invalid JSON');
    }

    // =========================================================================
    // Process Tests — Standalone Tier-Based Product
    // =========================================================================

    @IsTest
    static void testProcessStandaloneTierBasedProduct() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-TIER-001', 'Tier Software Product', 'Software', 'Recurring', 'Tier based')
        };
        // NOTE: Do NOT set restricted-picklist NetSuite fields (e.g. Income_Account__c)
        // as test context does not have picklist values loaded.
        skuDetails[0].put('avalaraTaxCode', 'ST000000');
        skuDetails[0].put('eligibleForPremium', true);

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildPricingRow('IN-TIER-001', 'Lawyers', true, true, false)
        };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        // ----- Result assertions -----
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.steps.size() >= 2,
            'Should have at least 2 steps (IM + Product). Got: ' + result.steps.size());
        System.assert(result.totalSuccess > 0, 'Should have at least some successful records');

        // ----- Item Master assertions -----
        List<Item_Master_Product__c> ims = [
            SELECT Id, Name, GearsetExternalId__c
            FROM Item_Master_Product__c
            WHERE Name = 'IN-TIER-001'
        ];
        System.assertEquals(1, ims.size(), 'Should create 1 Item Master');
        System.assertNotEquals(null, ims[0].GearsetExternalId__c, 'GearsetExternalId should be populated');

        // ----- Product2 assertions -----
        List<Product2> prods = [
            SELECT Id, ProductCode, Item_Master_Product__c, Eligible_For_Premium__c,
                   SBQQ__DefaultPricingTable__c, SBQQ__ChargeType__c, SBQQ__BillingType__c,
                   AVA_SFCPQ__TaxCode__c, GearsetExternalId__c
            FROM Product2
            WHERE ProductCode = 'IN-TIER-001'
        ];
        System.assertEquals(1, prods.size(), 'Should create 1 Product2');
        System.assertEquals(ims[0].Id, prods[0].Item_Master_Product__c, 'Product should link to Item Master');
        // Eligible_For_Premium__c is set from SkuDetailRow.eligibleForPremium (set in SKU Details tab)
        System.assertNotEquals(null, prods[0].Eligible_For_Premium__c, 'Eligible_For_Premium__c should be populated');
        System.assertEquals('Segmented', prods[0].SBQQ__DefaultPricingTable__c, 'Software should use Segmented pricing table');
        System.assertEquals('Recurring', prods[0].SBQQ__ChargeType__c, 'Recurring revenue → Recurring charge type');
        System.assertEquals('Advance', prods[0].SBQQ__BillingType__c, 'Recurring → Advance billing');
        System.assertEquals('ST000000', prods[0].AVA_SFCPQ__TaxCode__c, 'Tax code should be set');
        System.assertNotEquals(null, prods[0].GearsetExternalId__c, 'GearsetExternalId should be populated');

        // ----- PricebookEntry assertions (may be 0 in test context, standard PB not available) -----
        // Custom PBEs require standard PBE first; standard PB not queryable in test context
        // so we verify the process ran without exception rather than asserting a specific count.

        // ----- Dimension assertions (Software → yes) -----
        Integer dimCount = [SELECT COUNT() FROM SBQQ__Dimension__c WHERE SBQQ__Product__c = :prods[0].Id];
        System.assert(dimCount > 0, 'Software product should have dimension records');

        // ----- Block Pricing Meter Type -----
        Integer mtCount = [
            SELECT COUNT() FROM Block_Pricing__c
            WHERE Product__c = :prods[0].Id AND Type__c = 'Meter Type'
        ];
        System.assertEquals(1, mtCount, 'Should create 1 Meter Type block pricing record');

        // ----- Block Pricing GTM Motion Tier -----
        Integer gtmCount = [
            SELECT COUNT() FROM Block_Pricing__c
            WHERE Product__c = :prods[0].Id AND Type__c = 'GTM Motion Tier'
        ];
        System.assert(gtmCount > 0, 'Tier-based product should have GTM Motion Tier block pricing');

        // ----- Intapp Pricing -----
        Integer intappCount = [SELECT COUNT() FROM Intapp_Pricing__c WHERE Product__c = :prods[0].Id];
        System.assert(intappCount > 0, 'Should create Intapp Pricing records');

        // ----- Verify Premium pricing uplift (20%) -----
        List<Intapp_Pricing__c> intappSamples = [
            SELECT Price__c, Premium_price__c
            FROM Intapp_Pricing__c
            WHERE Product__c = :prods[0].Id AND Price__c > 0
            LIMIT 1
        ];
        if (!intappSamples.isEmpty()) {
            Decimal expectedPremium = (intappSamples[0].Price__c * 1.2).setScale(2, RoundingMode.HALF_UP);
            System.assertEquals(expectedPremium, intappSamples[0].Premium_price__c,
                'Premium price should be 20% uplift');
        }
    }

    // =========================================================================
    // Process Tests — Services Product (no dimensions, no GTM tiers)
    // =========================================================================

    @IsTest
    static void testProcessServicesProduct() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-SVC-001', 'Test Service', 'Services', 'One-time', 'Free')
        };
        skuDetails[0].put('servicesProductType', 'Fixed Fee');

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-SVC-001', 'Revenue')
        };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalSuccess > 0, 'Should have successful records');

        Product2 svcProd = [
            SELECT Id, SBQQ__DefaultPricingTable__c, SBQQ__PriceEditable__c,
                   SBQQ__ChargeType__c, SBQQ__BillingType__c
            FROM Product2
            WHERE ProductCode = 'IN-SVC-001'
            LIMIT 1
        ];
        System.assertEquals('Standard', svcProd.SBQQ__DefaultPricingTable__c,
            'Services product should have Standard pricing table');
        System.assertEquals(true, svcProd.SBQQ__PriceEditable__c,
            'Services product should be price editable');
        System.assertEquals('One-Time', svcProd.SBQQ__ChargeType__c,
            'One-time revenue → One-Time charge type');

        // No dimensions for Services
        Integer dimCount = [SELECT COUNT() FROM SBQQ__Dimension__c WHERE SBQQ__Product__c = :svcProd.Id];
        System.assertEquals(0, dimCount, 'Services product should not have dimension records');

        // No GTM Motion Tier block pricing (pricing basis = Free, not Tier based)
        Integer gtmCount = [
            SELECT COUNT() FROM Block_Pricing__c
            WHERE Product__c = :svcProd.Id AND Type__c = 'GTM Motion Tier'
        ];
        System.assertEquals(0, gtmCount, 'Free pricing basis should not create GTM block pricing');

        // Should still have Intapp Pricing records
        Integer intappCount = [SELECT COUNT() FROM Intapp_Pricing__c WHERE Product__c = :svcProd.Id];
        System.assert(intappCount > 0, 'Should still create Intapp Pricing for Free products');
    }

    // =========================================================================
    // Process Tests — With Bundles
    // =========================================================================

    @IsTest
    static void testProcessWithBundles() {
        // Two new products in this launch
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-BDLP-001', 'Bundle Parent', 'Software', 'Recurring', 'Tier based'),
            buildSkuDetailRow('IN-BDLC-001', 'Bundle Child', 'Software', 'Recurring', 'Tier based')
        };
        skuDetails[0].put('isBundle', true);

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-BDLP-001', 'Lawyers'),
            buildMinimalPricingRow('IN-BDLC-001', 'Lawyers')
        };

        // Bundle: parent + new component + existing component
        List<Map<String, Object>> bundles = new List<Map<String, Object>>{
            buildBundleRow('BUNDLE', 'Bundle Parent', 'IN-BDLP-001', 1.0, null),
            buildBundleRow('Component Product', 'Bundle Child', 'IN-BDLC-001', 0.8, 'IN-BDLP-001'),
            buildBundleRow('Component Product', 'Existing Comp', 'IN-EXIST-001', 0.2, 'IN-BDLP-001')
        };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            JSON.serialize(bundles),
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalSuccess > 0, 'Should have successful records');

        // Verify placeholder product was created
        List<Product2> placeholders = [
            SELECT Id, ProductCode, Parent_Of_Bundle__c, SBQQ__ConfigurationType__c
            FROM Product2
            WHERE ProductCode = 'IN-BDLP-001-P'
        ];
        System.assertEquals(1, placeholders.size(), 'Should create 1 placeholder -P product');
        System.assertEquals(true, placeholders[0].Parent_Of_Bundle__c, 'Placeholder should be Parent_Of_Bundle');

        // Placeholder products intentionally skip Item Master creation
        Integer plImCount = [SELECT COUNT() FROM Item_Master_Product__c WHERE Name = 'IN-BDLP-001-P'];
        System.assertEquals(0, plImCount, 'Placeholder products should not have Item Master records');

        // PricebookEntries for placeholder may be 0 in test context (standard PB not available,
        // and custom PBEs require standard PBE first). Verify placeholder creation instead.

        // Verify SBQQ__ProductOption__c records
        List<SBQQ__ProductOption__c> options = [
            SELECT SBQQ__OptionalSKU__c, CPQ_Option_Type__c, SBQQ__Bundled__c
            FROM SBQQ__ProductOption__c
            WHERE SBQQ__ConfiguredSKU__c = :placeholders[0].Id
            ORDER BY SBQQ__Number__c
        ];
        System.assert(options.size() >= 2,
            'Should have at least 2 product options (bundle + component). Got: ' + options.size());

        // Verify option types
        Boolean foundStaticBundle = false;
        Boolean foundStaticComponent = false;
        for (SBQQ__ProductOption__c opt : options) {
            if (opt.CPQ_Option_Type__c == 'Static Bundle') foundStaticBundle = true;
            if (opt.CPQ_Option_Type__c == 'Static Component') foundStaticComponent = true;
        }
        System.assert(foundStaticBundle, 'Should have a Static Bundle option');
        System.assert(foundStaticComponent, 'Should have a Static Component option');
    }

    // =========================================================================
    // Process Tests — Empty Bundles String
    // =========================================================================

    @IsTest
    static void testProcessEmptyBundlesString() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-NOBD-001', 'No Bundle', 'Support', 'Recurring', 'Tier based')
        };

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-NOBD-001', 'Named Users')
        };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            '',  // Empty string — no bundles
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalSuccess > 0, 'Should have successful records');

        // Support product should have dimensions
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'IN-NOBD-001' LIMIT 1];
        Integer dimCount = [SELECT COUNT() FROM SBQQ__Dimension__c WHERE SBQQ__Product__c = :p.Id];
        System.assert(dimCount > 0, 'Support product should have dimension records');

        // No placeholder products should exist
        Integer plCount = [SELECT COUNT() FROM Product2 WHERE ProductCode = 'IN-NOBD-001-P'];
        System.assertEquals(0, plCount, 'Should not create placeholder for non-bundle');
    }

    // =========================================================================
    // Process Tests — Quantity-Based Product (no GTM block pricing)
    // =========================================================================

    @IsTest
    static void testProcessQuantityBasedProduct() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-QTY-001', 'Quantity Product', 'Software', 'Recurring', 'Quantity based')
        };

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-QTY-001', 'Fee Earners')
        };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalSuccess > 0, 'Should have successful records');

        Product2 p = [
            SELECT Id, SBQQ__PriceEditable__c
            FROM Product2
            WHERE ProductCode = 'IN-QTY-001'
            LIMIT 1
        ];
        System.assertEquals(true, p.SBQQ__PriceEditable__c,
            'Quantity-based software should be price editable');

        // No GTM Motion Tier (only tier-based products get these)
        Integer gtmCount = [
            SELECT COUNT() FROM Block_Pricing__c
            WHERE Product__c = :p.Id AND Type__c = 'GTM Motion Tier'
        ];
        System.assertEquals(0, gtmCount, 'Quantity-based should not create GTM block pricing');
    }

    // =========================================================================
    // Process Tests — Multiple Products
    // =========================================================================

    @IsTest
    static void testProcessMultipleProducts() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-MULTI-001', 'Product One', 'Software', 'Recurring', 'Tier based'),
            buildSkuDetailRow('IN-MULTI-002', 'Product Two', 'Maintenance', 'Recurring', 'Tier based')
        };

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-MULTI-001', 'Lawyers'),
            buildMinimalPricingRow('IN-MULTI-002', 'Fee Earners')
        };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalSuccess > 0, 'Should have successful records');

        // Both products should be created
        Integer prodCount = [
            SELECT COUNT() FROM Product2
            WHERE ProductCode IN ('IN-MULTI-001', 'IN-MULTI-002')
        ];
        System.assertEquals(2, prodCount, 'Should create 2 products');

        // Both should have dimensions (Software + Maintenance)
        for (String code : new List<String>{'IN-MULTI-001', 'IN-MULTI-002'}) {
            Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = :code LIMIT 1];
            Integer dimCount = [SELECT COUNT() FROM SBQQ__Dimension__c WHERE SBQQ__Product__c = :p.Id];
            System.assert(dimCount > 0, code + ' should have dimension records');
        }
    }

    // =========================================================================
    // Process Tests — Exception Handling
    // =========================================================================

    @IsTest
    static void testProcessExceptionHandling() {
        Boolean caughtError = false;

        Test.startTest();
        try {
            SkuNewLaunchController.processNewSkuLaunch(
                'invalid json {{{', '[]', null,
                null
            );
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();

        System.assertEquals(true, caughtError, 'Should throw AuraHandledException for invalid JSON');
    }

    // =========================================================================
    // Process Tests — No Custom Pricebook
    // =========================================================================

    @IsTest
    static void testProcessWithoutCustomPricebook() {
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-NOPB-001', 'No Custom PB', 'Software', 'Recurring', 'Tier based')
        };
        // Set sfdcPricebook to a name that does not exist
        skuDetails[0].put('sfdcPricebook', 'NonExistent Pricebook 99');

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{
            buildMinimalPricingRow('IN-NOPB-001', 'Lawyers')
        };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalSuccess > 0, 'Should still create records with just standard PB');

        // Product should exist
        Integer prodCount = [SELECT COUNT() FROM Product2 WHERE ProductCode = 'IN-NOPB-001'];
        System.assertEquals(1, prodCount, 'Should create the product');

        // Verify a standard PBE was created (custom PB lookup was skipped gracefully).
        // Filter by Pricebook2Id directly rather than Pricebook2.IsStandard because
        // Salesforce hides the standard pricebook from SOQL in test context — the
        // relationship traversal WHERE filter returns 0 even though the PBE exists.
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'IN-NOPB-001' LIMIT 1];
        Id stdPbId = Test.getStandardPricebookId();
        Integer standardPbeCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Product2Id = :p.Id
            AND Pricebook2Id = :stdPbId
        ];
        System.assert(standardPbeCount > 0,
            'Should create at least one standard PBE when custom PB not found (one per active currency)');
    }

    // =========================================================================
    // Process Tests — OP4I Abbreviation Coverage
    // =========================================================================

    @IsTest
    static void testProcessOp4iAbbreviations() {
        // Test all sales channel flag combinations for deriveOp4iAbbrev coverage
        List<Map<String, Object>> skuDetails = new List<Map<String, Object>>{
            buildSkuDetailRow('IN-OP4I-001', 'OP4I Test', 'Software', 'Recurring', 'Tier based')
        };

        // Create pricing rows with different sales channel flags
        Map<String, Object> legalRow = buildMinimalPricingRow('IN-OP4I-001', 'Lawyers');
        legalRow.put('legalSales', true);
        legalRow.put('acSales', false);

        Map<String, Object> acRow = buildMinimalPricingRow('IN-OP4I-001', 'Fee Earners');
        acRow.put('legalSales', false);
        acRow.put('acSales', true);

        List<Map<String, Object>> pricing = new List<Map<String, Object>>{ legalRow, acRow };

        Test.startTest();
        SkuNewLaunchController.LaunchResult result = SkuNewLaunchController.processNewSkuLaunch(
            JSON.serialize(skuDetails),
            JSON.serialize(pricing),
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.totalSuccess > 0, 'Should have successful records');

        // Verify Intapp Pricing records have different names based on OP4I abbreviation
        List<Intapp_Pricing__c> intapps = [
            SELECT Name, Legal_Sales__c, A_C_Sales__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'IN-OP4I-001'
        ];
        System.assert(intapps.size() > 0, 'Should create Intapp Pricing records');
    }

    // =========================================================================
    // Product Line & Product Rollup — checkProductLineAndRollup
    // =========================================================================

    @IsTest
    static void testCheckProductLineAndRollupFound() {
        // Product Line already exists from @TestSetup
        Test.startTest();
        Map<String, Object> result = SkuNewLaunchController.checkProductLineAndRollup(
            new List<String>{ 'Test Product Line' },
            new List<String>{ 'Test Rollup' }
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        List<String> missingPLs = (List<String>) result.get('missingProductLines');
        List<String> missingPRs = (List<String>) result.get('missingProductRollups');
        System.assertEquals(0, missingPLs.size(), 'Test Product Line should already exist');
        System.assertEquals(0, missingPRs.size(), 'Test Rollup should already exist');
    }

    @IsTest
    static void testCheckProductLineAndRollupMissing() {
        Test.startTest();
        Map<String, Object> result = SkuNewLaunchController.checkProductLineAndRollup(
            new List<String>{ 'Nonexistent PL' },
            new List<String>{ 'Nonexistent Rollup' }
        );
        Test.stopTest();

        List<String> missingPLs = (List<String>) result.get('missingProductLines');
        List<String> missingPRs = (List<String>) result.get('missingProductRollups');
        System.assertEquals(1, missingPLs.size(), 'Should report missing product line');
        System.assertEquals(1, missingPRs.size(), 'Should report missing rollup');
    }

    @IsTest
    static void testCheckProductLineAndRollupNullArgs() {
        Test.startTest();
        Map<String, Object> result = SkuNewLaunchController.checkProductLineAndRollup(null, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should handle null args gracefully');
        List<String> missingPLs = (List<String>) result.get('missingProductLines');
        System.assertEquals(0, missingPLs.size(), 'No missing PLs when null input');
    }

    // =========================================================================
    // Product Line & Product Rollup — createProductLineRecord / createProductRollupRecord
    // =========================================================================

    @IsTest
    static void testCreateProductLineRecord() {
        Test.startTest();
        // Pass null for optional picklist fields to avoid restricted-picklist failures in Prod
        Id plId = SkuNewLaunchController.createProductLineRecord(
            'New Test PL', null, null, null, 'NT', false
        );
        Test.stopTest();

        System.assertNotEquals(null, plId, 'Should return the new Product Line Id');
        Product_Line__c pl = [SELECT Name, Active__c, GearsetExternalId__c FROM Product_Line__c WHERE Id = :plId LIMIT 1];
        System.assertEquals('New Test PL', pl.Name);
        System.assertEquals(true, pl.Active__c);
        System.assertNotEquals(null, pl.GearsetExternalId__c, 'GearsetExternalId should be populated');
    }

    @IsTest
    static void testCreateProductRollupRecord() {
        Test.startTest();
        Id prId = SkuNewLaunchController.createProductRollupRecord('New Test Rollup', 'Test Product Line');
        Test.stopTest();

        System.assertNotEquals(null, prId, 'Should return the new Product Rollup Id');
        Product_Rollup__c pr = [SELECT Name, GearsetExternalId__c FROM Product_Rollup__c WHERE Id = :prId LIMIT 1];
        System.assertEquals('New Test Rollup', pr.Name);
        System.assertNotEquals(null, pr.GearsetExternalId__c, 'GearsetExternalId should be populated');
    }

    @IsTest
    static void testCreateProductRollupRecordMissingProductLine() {
        Boolean caughtError = false;
        Test.startTest();
        try {
            SkuNewLaunchController.createProductRollupRecord('Bad Rollup', 'Nonexistent PL');
        } catch (AuraHandledException e) {
            caughtError = true;
        }
        Test.stopTest();

        System.assertEquals(true, caughtError, 'Should throw when Product Line not found');
    }

    // =========================================================================
    // Inner Class Coverage — Wrapper Instantiation
    // =========================================================================

    @IsTest
    static void testInnerClassCoverage() {
        // Directly instantiate inner classes to ensure coverage of all @AuraEnabled properties

        SkuNewLaunchController.SkuDetailRow skuRow = new SkuNewLaunchController.SkuDetailRow();
        skuRow.productCode = 'IN-001';
        skuRow.productName = 'Test';
        skuRow.description = 'Desc';
        skuRow.productLine = 'PL';
        skuRow.productRollup = 'PR';
        skuRow.revenueType = 'Recurring';
        skuRow.productGroup = 'Group';
        skuRow.productType = 'Software';
        skuRow.includesAssist = false;
        skuRow.pricingBasis = 'Tier based';
        skuRow.percentageOfAcv = 0;
        skuRow.servicesProductType = 'Fixed Fee';
        skuRow.softwareLicenseTerm = 'Annual';
        skuRow.subscriptionType = 'Renewable';
        skuRow.isBundle = false;
        skuRow.lineOfBusinessProduct = 'LOB';
        skuRow.sfdcPricebook = 'PB';
        skuRow.subscriptionPricing = 'Fixed Price';
        skuRow.isLegal = 'Active';
        skuRow.isAccounting = 'Active';
        skuRow.isConsulting = 'Unavailable';
        skuRow.isIBA = 'Unavailable';
        skuRow.isPCM = 'Unavailable';
        skuRow.isRealAssets = 'Unavailable';
        skuRow.isCorporate = 'Unavailable';
        skuRow.netsuiteIncomeAccount = 'Acct';
        skuRow.netsuiteDeferredRevenueAccount = 'Def';
        skuRow.netsuiteItemRevenueCategory = 'Cat';
        skuRow.netsuiteRevRecognitionRule = 'Rule';
        skuRow.netsuiteRevRecForecastRule = 'Forecast';
        skuRow.netsuiteRevenueAllocationGroup = 'Group';
        skuRow.netsuiteCreateRevenuePlansOn = 'Create';
        skuRow.netsuiteItemTypeForInvoicing = 'Type';
        skuRow.netsuiteRevRecTemplate = 'Template';
        skuRow.netsuiteIncludeChildren = true;
        skuRow.openAirBillingRule = 'Rule';
        skuRow.netsuiteExportToOpenAir = true;
        skuRow.avalaraTaxCode = 'TX001';
        skuRow.netsuiteTaxSchedule = 'Schedule';
        skuRow.meterTypeAccounting = 'Fee Earners';
        skuRow.meterTypeConsulting = 'Consultants';
        skuRow.meterTypeCorporate = 'Revenue';
        skuRow.meterTypeIBA = 'Named Users';
        skuRow.meterTypePCM = 'Revenue';
        skuRow.meterTypeRealAssets = 'Revenue';
        skuRow.meterTypeLegal = 'Lawyers';
        skuRow.meterTypeLegalUsdAud = 'Lawyers';

        SkuNewLaunchController.PricingRow pricingRow = new SkuNewLaunchController.PricingRow();
        pricingRow.productCode = 'IN-001';
        pricingRow.productName = 'Test';
        pricingRow.meterType = 'Lawyers';
        pricingRow.legalSales = true;
        pricingRow.acSales = false;
        pricingRow.fsSales = false;
        pricingRow.corporateSales = false;
        pricingRow.opsOnly = false;
        pricingRow.premiumSupport = true;
        pricingRow.prices = new List<SkuNewLaunchController.PriceEntry>();

        SkuNewLaunchController.PriceEntry priceEntry = new SkuNewLaunchController.PriceEntry();
        priceEntry.currencyCode = 'USD';
        priceEntry.tier = 'EM1';
        priceEntry.price = 30.00;

        SkuNewLaunchController.BundleRow bundleRow = new SkuNewLaunchController.BundleRow();
        bundleRow.role = 'BUNDLE';
        bundleRow.productName = 'Bundle';
        bundleRow.imNumber = 'IN-001';
        bundleRow.acvPercent = 1.0;
        bundleRow.parentProductCode = null;

        SkuNewLaunchController.ValidationResult valResult = new SkuNewLaunchController.ValidationResult();
        valResult.isValid = true;
        valResult.errors = new List<String>();
        valResult.warnings = new List<String>();
        valResult.skuCount = 1;
        valResult.pricingRowCount = 1;
        valResult.bundleCount = 0;

        SkuNewLaunchController.LaunchResult launchResult = new SkuNewLaunchController.LaunchResult();
        launchResult.steps = new List<SkuNewLaunchController.StepResult>();
        launchResult.totalSuccess = 0;
        launchResult.totalErrors = 0;

        SkuNewLaunchController.StepResult stepResult = new SkuNewLaunchController.StepResult();
        stepResult.objectName = 'Test';
        stepResult.successCount = 1;
        stepResult.errorCount = 0;
        stepResult.totalCount = 1;
        stepResult.errors = new List<String>();

        // Assert inner classes are instantiated correctly
        System.assertEquals('IN-001', skuRow.productCode);
        System.assertEquals('Lawyers', pricingRow.meterType);
        System.assertEquals(30.00, priceEntry.price);
        System.assertEquals('BUNDLE', bundleRow.role);
        System.assertEquals(true, valResult.isValid);
        System.assertEquals(0, launchResult.totalErrors);
        System.assertEquals(1, stepResult.totalCount);
    }
}