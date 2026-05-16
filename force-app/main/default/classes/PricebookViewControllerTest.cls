/**
 * @description Test class for PricebookViewController.
 *              Validates the Pricebook View data retrieval, vertical-based
 *              meter type filtering, Legal meter type merge logic, and grouping.
 */
@IsTest
private class PricebookViewControllerTest {

    // =========================================================================
    // Test Setup
    // =========================================================================

    @TestSetup
    static void setup() {
        // Create Product Lines with Active__c = true (required by Product_LineNew__c lookup filter)
        Product_Line__c productLine = new Product_Line__c(
            Name = 'Intake',
            Practice__c = 'Risk & Compliance',
            Active__c = true
        );
        insert productLine;

        Product_Line__c productLine2 = new Product_Line__c(
            Name = 'DealCloud Core',
            Practice__c = 'DealCloud',
            Active__c = true
        );
        insert productLine2;

        // Create products using direct insert (avoid TestFactory default conflicts)
        // Product 1: Active for Legal, Restricted for Accounting
        Product2 product1 = new Product2(
            Name = 'Intapp Intake',
            ProductCode = 'PBV-001',
            IsActive = true,
            Product_LineNew__c = productLine.Id,
            Is_Legal__c = 'Active',
            Is_Accounting__c = 'Restricted',
            Is_Consulting__c = 'Unavailable',
            Is_IBA__c = 'Unavailable',
            Is_PCM__c = 'Unavailable',
            Is_Real_Assets__c = 'Unavailable',
            Iss_Corporate__c = 'Unavailable',
            Pricing_Basis__c = 'Tier based'
        );
        insert product1;

        // Product 2: Active for Legal only
        Product2 product2 = new Product2(
            Name = 'Intapp Conflicts',
            ProductCode = 'PBV-002',
            IsActive = true,
            Product_LineNew__c = productLine.Id,
            Is_Legal__c = 'Active',
            Is_Accounting__c = 'Unavailable',
            Is_Consulting__c = 'Unavailable',
            Is_IBA__c = 'Unavailable',
            Is_PCM__c = 'Unavailable',
            Is_Real_Assets__c = 'Unavailable',
            Iss_Corporate__c = 'Unavailable',
            Pricing_Basis__c = 'Quantity based'
        );
        insert product2;

        // Product 3: Inactive product in same BU
        Product2 product3 = new Product2(
            Name = 'Inactive Product',
            ProductCode = 'PBV-003',
            IsActive = false,
            Product_LineNew__c = productLine.Id,
            Is_Legal__c = 'Active',
            Is_Accounting__c = 'Unavailable',
            Is_Consulting__c = 'Unavailable',
            Is_IBA__c = 'Unavailable',
            Is_PCM__c = 'Unavailable',
            Is_Real_Assets__c = 'Unavailable',
            Iss_Corporate__c = 'Unavailable',
            Pricing_Basis__c = 'Free'
        );
        insert product3;

        // Product 4: Different BU, Restricted for Legal, Active for Consulting
        Product2 product4 = new Product2(
            Name = 'DealCloud Product',
            ProductCode = 'PBV-004',
            IsActive = true,
            Product_LineNew__c = productLine2.Id,
            Is_Legal__c = 'Restricted',
            Is_Accounting__c = 'Unavailable',
            Is_Consulting__c = 'Active',
            Is_IBA__c = 'Unavailable',
            Is_PCM__c = 'Unavailable',
            Is_Real_Assets__c = 'Unavailable',
            Iss_Corporate__c = 'Unavailable',
            Pricing_Basis__c = 'Other/Mixed'
        );
        insert product4;

        // Product 5: Active for Legal in same BU, NO Block Pricing GTM records (Intapp Pricing fallback)
        Product2 product5 = new Product2(
            Name = 'Intapp Compliance',
            ProductCode = 'PBV-005',
            IsActive = true,
            Product_LineNew__c = productLine.Id,
            Pricing_Basis__c = 'Tier based',
            Is_Legal__c = 'Active',
            Is_Accounting__c = 'Unavailable',
            Is_Consulting__c = 'Unavailable',
            Is_IBA__c = 'Unavailable',
            Is_PCM__c = 'Unavailable',
            Is_Real_Assets__c = 'Unavailable',
            Iss_Corporate__c = 'Unavailable'
        );
        insert product5;

        // Create Meter Type records (Block_Pricing__c, Type = 'Meter Type')
        List<Block_Pricing__c> meterTypeRecords = new List<Block_Pricing__c>();

        // Product 1: Legal=Lawyers (same for both currencies), Accounting=Employees
        meterTypeRecords.add(new Block_Pricing__c(
            Product__c = product1.Id,
            Product_Code__c = 'PBV-001',
            Type__c = 'Meter Type',
            Active__c = true,
            Legal_meter_type_USD_AUD__c = 'Lawyers',
            Legal__c = 'Lawyers',
            meter_type_Accounting__c = 'Employees'
        ));

        // Product 2: Legal has different meter types per currency (merge scenario)
        meterTypeRecords.add(new Block_Pricing__c(
            Product__c = product2.Id,
            Product_Code__c = 'PBV-002',
            Type__c = 'Meter Type',
            Active__c = true,
            Legal_meter_type_USD_AUD__c = 'Lawyers',
            Legal__c = 'Named Users'
        ));

        // Product 4: Consulting=Fee Earners, Legal=Revenue
        meterTypeRecords.add(new Block_Pricing__c(
            Product__c = product4.Id,
            Product_Code__c = 'PBV-004',
            Type__c = 'Meter Type',
            Active__c = true,
            meter_type_Consulting__c = 'Fee Earners',
            Legal_meter_type_USD_AUD__c = 'Revenue',
            Legal__c = 'Revenue'
        ));

        // Product 5: Legal=Lawyers (same for both currencies)
        meterTypeRecords.add(new Block_Pricing__c(
            Product__c = product5.Id,
            Product_Code__c = 'PBV-005',
            Type__c = 'Meter Type',
            Active__c = true,
            Legal_meter_type_USD_AUD__c = 'Lawyers',
            Legal__c = 'Lawyers'
        ));

        insert meterTypeRecords;

        // Create Block Pricing records (GTM Motion Tier) for product1 — Lawyers meter type
        List<Block_Pricing__c> pricingRecords = new List<Block_Pricing__c>();
        pricingRecords.add(new Block_Pricing__c(
            Product__c = product1.Id,
            Product_Code__c = 'PBV-001',
            Block_Pricing_Meter_Type__c = 'Lawyers',
            Type__c = 'GTM Motion Tier',
            Active__c = true,
            Tier_Name__c = 'EM1',
            Price__c = 30.00
        ));
        pricingRecords.add(new Block_Pricing__c(
            Product__c = product1.Id,
            Product_Code__c = 'PBV-001',
            Block_Pricing_Meter_Type__c = 'Lawyers',
            Type__c = 'GTM Motion Tier',
            Active__c = true,
            Tier_Name__c = 'EM2',
            Price__c = 30.00
        ));
        pricingRecords.add(new Block_Pricing__c(
            Product__c = product1.Id,
            Product_Code__c = 'PBV-001',
            Block_Pricing_Meter_Type__c = 'Lawyers',
            Type__c = 'GTM Motion Tier',
            Active__c = true,
            Tier_Name__c = 'EM3',
            Price__c = 36.00
        ));

        // Product 1 also has Employees meter type pricing (for Accounting vertical)
        pricingRecords.add(new Block_Pricing__c(
            Product__c = product1.Id,
            Product_Code__c = 'PBV-001',
            Block_Pricing_Meter_Type__c = 'Employees',
            Type__c = 'GTM Motion Tier',
            Active__c = true,
            Tier_Name__c = 'EM1',
            Price__c = 15.00
        ));

        // Product 2 — Lawyers pricing (USD)
        pricingRecords.add(new Block_Pricing__c(
            Product__c = product2.Id,
            Product_Code__c = 'PBV-002',
            Block_Pricing_Meter_Type__c = 'Lawyers',
            Type__c = 'GTM Motion Tier',
            Active__c = true,
            Tier_Name__c = 'EM1',
            Price__c = 18.00
        ));

        // Product 2 — Named Users pricing in GBP (for GBP/EUR Legal merge test)
        pricingRecords.add(new Block_Pricing__c(
            Product__c = product2.Id,
            Product_Code__c = 'PBV-002',
            Block_Pricing_Meter_Type__c = 'Named Users',
            Type__c = 'GTM Motion Tier',
            Active__c = true,
            CurrencyIsoCode = 'GBP',
            Tier_Name__c = 'EM1',
            Price__c = 22.00
        ));

        insert pricingRecords;

        // Create Pricebook for Intapp Pricing fallback
        Pricebook2 intappPB = new Pricebook2(
            Name = 'FY26_All_Products',
            IsActive = true
        );
        insert intappPB;

        // Create Intapp Pricing records for Product 5 (no Block Pricing GTM records)
        List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
        intappRecords.add(new Intapp_Pricing__c(
            Product_Code__c = 'PBV-005',
            Price_Book__c = intappPB.Id,
            Meter_Type__c = 'Lawyers',
            CurrencyIsoCode = 'USD',
            Tier__c = 'EM1',
            Price__c = 45.00
        ));
        intappRecords.add(new Intapp_Pricing__c(
            Product_Code__c = 'PBV-005',
            Price_Book__c = intappPB.Id,
            Meter_Type__c = 'Lawyers',
            CurrencyIsoCode = 'USD',
            Tier__c = 'Tier (none)',
            Price__c = 25.00
        ));
        insert intappRecords;
    }

    // =========================================================================
    // getBusinessUnits Tests
    // =========================================================================

    @IsTest
    static void testGetBusinessUnits() {
        Test.startTest();
        List<String> businessUnits = PricebookViewController.getBusinessUnits();
        Test.stopTest();

        System.assertNotEquals(0, businessUnits.size(),
            'Should return at least one business unit');
        System.assert(businessUnits.contains('Risk & Compliance'),
            'Should contain Risk & Compliance');
        System.assert(businessUnits.contains('DealCloud'),
            'Should contain DealCloud');
    }

    // =========================================================================
    // getVerticals Tests
    // =========================================================================

    @IsTest
    static void testGetVerticals() {
        Test.startTest();
        List<String> verticals = PricebookViewController.getVerticals();
        Test.stopTest();

        System.assertEquals(7, verticals.size(), 'Should return 7 verticals');
        System.assertEquals('Legal', verticals[0], 'First vertical should be Legal');
        System.assertEquals('Corporate', verticals[6], 'Last vertical should be Corporate');
    }

    // =========================================================================
    // getFilterPicklistValues Tests
    // =========================================================================

    @IsTest
    static void testGetFilterPicklistValues() {
        Test.startTest();
        Map<String, List<String>> result = PricebookViewController.getFilterPicklistValues();
        Test.stopTest();

        System.assert(result.containsKey('productTypes'),
            'Should contain productTypes key');
        System.assert(result.containsKey('pricingBases'),
            'Should contain pricingBases key');

        // Test data has Pricing Basis values: Tier based, Quantity based, Free, Other/Mixed
        List<String> pricingBases = result.get('pricingBases');
        System.assert(pricingBases.size() > 0,
            'Should return at least one pricing basis value');
        System.assert(pricingBases.contains('Tier based'),
            'Should contain Tier based');
    }

    // =========================================================================
    // getPricebookViewData — Business Unit Mode Tests
    // =========================================================================

    @IsTest
    static void testGetDataByBusinessUnit_ActiveOnly() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.totalProducts > 0,
            'Should have at least one product');
        System.assert(result.groups.size() > 0,
            'Should have at least one vertical group');

        // Verify Legal group exists (single flat sub-group sorted by Pricing Basis)
        Boolean hasLegalGroup = false;
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                hasLegalGroup = true;
                System.assert(grp.productCount > 0,
                    'Legal group should have products');
                System.assertEquals(1, grp.subGroups.size(),
                    'Should have exactly one flat sub-group');
                PricebookViewController.PricebookViewSubGroup sg = grp.subGroups[0];
                System.assert(sg.rows.size() > 0,
                    'Sub-group should have rows');
                PricebookViewController.PricebookViewRow firstRow = sg.rows[0];
                System.assertNotEquals(null, firstRow.productId,
                    'Row should have productId');
                System.assertNotEquals(null, firstRow.productCode,
                    'Row should have productCode');
                System.assertEquals(24, firstRow.prices.size(),
                    'Row should have 24 price cells');
            }
        }
        System.assert(hasLegalGroup, 'Should have Legal group');
    }

    @IsTest
    static void testGetDataByBusinessUnit_SingleRowPerVertical() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        // Each product should have exactly 1 row per vertical group
        // product1 appears in Legal (Active) and Accounting (Restricted)
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                // Count rows per product in this sub-group
                Map<String, Integer> productRowCounts = new Map<String, Integer>();
                for (PricebookViewController.PricebookViewRow row : sg.rows) {
                    Integer count = productRowCounts.containsKey(row.productId)
                        ? productRowCounts.get(row.productId) + 1 : 1;
                    productRowCounts.put(row.productId, count);
                }
                for (String productId : productRowCounts.keySet()) {
                    System.assertEquals(1, productRowCounts.get(productId),
                        'Each product should have exactly 1 row per sub-group (' +
                        grp.groupName + '/' + sg.status + ')');
                }
            }
        }
    }

    @IsTest
    static void testGetDataByBusinessUnit_CorrectMeterTypePerVertical() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        // product1: Legal should show "Lawyers", Accounting should show "Employees"
        Product2 product1 = [SELECT Id FROM Product2 WHERE ProductCode = 'PBV-001'];

        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                for (PricebookViewController.PricebookViewRow row : sg.rows) {
                    if (row.productId == product1.Id) {
                        if (grp.groupName == 'Legal') {
                            System.assertEquals('Lawyers', row.meterType,
                                'Legal vertical should show Lawyers meter type');
                        } else if (grp.groupName == 'Accounting') {
                            System.assertEquals('Employees', row.meterType,
                                'Accounting vertical should show Employees meter type');
                        }
                    }
                }
            }
        }
    }

    @IsTest
    static void testGetDataByBusinessUnit_IncludesAccountingRestricted() {
        // With productStatus='All', Product 1 (Is_Accounting__c='Restricted')
        // should appear under the Accounting vertical group
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'All', null, null
            );
        Test.stopTest();

        Boolean hasAccountingGroup = false;
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Accounting') {
                hasAccountingGroup = true;
                System.assertEquals(1, grp.subGroups.size(),
                    'Should have exactly one flat sub-group');
                System.assert(grp.subGroups[0].rows.size() > 0,
                    'Sub-group should contain Product 1 (Restricted for Accounting)');
            }
        }
        System.assert(hasAccountingGroup,
            'Should have Accounting group when filter is All (product1 Is_Accounting__c=Restricted)');
    }

    @IsTest
    static void testGetDataByBusinessUnit_InactiveOnly() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Inactive', null, null
            );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // product3 is inactive with Is_Legal__c = Active
        System.assert(result.totalProducts > 0,
            'Should find the inactive product');
    }

    @IsTest
    static void testGetDataByBusinessUnit_All() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'All', null, null
            );
        Test.stopTest();

        // Should find both active and inactive products
        System.assert(result.totalProducts >= 3,
            'Should find active and inactive products in All mode');
    }

    @IsTest
    static void testGetDataByBusinessUnit_NoMatch() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Nonexistent BU', 'Active', null, null
            );
        Test.stopTest();

        System.assertEquals(0, result.totalProducts,
            'Should return zero products for non-matching BU');
        System.assertEquals(0, result.groups.size(),
            'Should return zero groups for non-matching BU');
    }

    // =========================================================================
    // getPricebookViewData — Vertical Mode Tests
    // =========================================================================

    @IsTest
    static void testGetDataByVertical_Legal() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'vertical', 'Legal', 'Active', null, null
            );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.totalProducts > 0,
            'Should find products with Legal = Active');

        // Grouped by Business Unit; productStatus='Active' excludes Product 4
        // (Is_Legal__c='Restricted'), so only Risk & Compliance BU should appear
        Boolean hasRiskCompliance = false;
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Risk & Compliance') {
                hasRiskCompliance = true;
                System.assertEquals(1, grp.subGroups.size(),
                    'Should have exactly one flat sub-group');
                System.assert(grp.subGroups[0].rows.size() > 0,
                    'Sub-group should have rows');
            }
        }
        System.assert(hasRiskCompliance,
            'Should have Risk & Compliance group');
    }

    @IsTest
    static void testGetDataByVertical_Consulting() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'vertical', 'Consulting', 'Active', null, null
            );
        Test.stopTest();

        // Only product4 has Consulting = Active
        System.assert(result.totalProducts > 0,
            'Should find at least one product with Consulting = Active');

        // Verify the meter type is Fee Earners
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                for (PricebookViewController.PricebookViewRow row : sg.rows) {
                    if (row.productCode == 'PBV-004') {
                        System.assertEquals('Fee Earners', row.meterType,
                            'Consulting vertical for PBV-004 should show Fee Earners');
                    }
                }
            }
        }
    }

    @IsTest
    static void testGetDataByVertical_NoMatch() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'vertical', 'PCM', 'Active', null, null
            );
        Test.stopTest();

        // No products have PCM = Active or Restricted
        System.assertEquals(0, result.totalProducts,
            'Should return zero products for PCM vertical');
    }

    // =========================================================================
    // Legal Meter Type Merge Tests
    // =========================================================================

    @IsTest
    static void testLegalMerge_SameMeterType() {
        // product1 has Legal_meter_type_USD_AUD__c = Lawyers AND Legal__c = Lawyers (same)
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        Product2 product1 = [SELECT Id FROM Product2 WHERE ProductCode = 'PBV-001'];

        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                    for (PricebookViewController.PricebookViewRow row : sg.rows) {
                        if (row.productId == product1.Id) {
                            System.assertEquals('Lawyers', row.meterType,
                                'When both Legal meter types are the same, display single value');
                        }
                    }
                }
            }
        }
    }

    @IsTest
    static void testLegalMerge_DifferentMeterTypes() {
        // product2 has Legal_meter_type_USD_AUD__c = Lawyers, Legal__c = Named Users (different)
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        Product2 product2 = [SELECT Id FROM Product2 WHERE ProductCode = 'PBV-002'];

        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                    for (PricebookViewController.PricebookViewRow row : sg.rows) {
                        if (row.productId == product2.Id) {
                            System.assertEquals('Lawyers / Named Users', row.meterType,
                                'When Legal meter types differ, display "TypeA / TypeB"');
                        }
                    }
                }
            }
        }
    }

    @IsTest
    static void testLegalMerge_DifferentMeterTypes_PricingPerCurrency() {
        // product2: USD/AUD should use Lawyers pricing, GBP/EUR should use Named Users pricing
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        Product2 product2 = [SELECT Id FROM Product2 WHERE ProductCode = 'PBV-002'];

        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                    for (PricebookViewController.PricebookViewRow row : sg.rows) {
                        if (row.productId == product2.Id) {
                            // Check USD_EM1 price comes from Lawyers (18.00)
                            PricebookViewController.PriceCell usdCell = row.prices[0];
                            System.assertEquals('USD', usdCell.currencyCode,
                                'First cell should be USD');
                            System.assertEquals(18.00, usdCell.price,
                                'USD price should come from Lawyers meter type');

                            // Find GBP_EM1 cell (index 6: after 6 USD cells)
                            PricebookViewController.PriceCell gbpCell = row.prices[6];
                            System.assertEquals('GBP', gbpCell.currencyCode,
                                'Cell at index 6 should be GBP');
                            System.assertEquals(22.00, gbpCell.price,
                                'GBP price should come from Named Users meter type');
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // Pricing Data Tests
    // =========================================================================

    @IsTest
    static void testPricingDataIncludedInRows() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        // Find product1 row in Legal group with Lawyers pricing
        Boolean foundPricingRow = false;
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                    for (PricebookViewController.PricebookViewRow row : sg.rows) {
                        if (row.productCode == 'PBV-001' && row.meterType == 'Lawyers') {
                            foundPricingRow = true;
                            System.assertEquals(24, row.prices.size(),
                                'Should have 24 price cells');
                            // Check first cell (USD_EM1) has price
                            PricebookViewController.PriceCell firstCell = row.prices[0];
                            System.assertEquals('USD', firstCell.currencyCode,
                                'First cell should be USD');
                            System.assertEquals('EM1', firstCell.tier,
                                'First cell should be EM1');
                            System.assertEquals(30.00, firstCell.price,
                                'EM1 price should be 30.00');
                        }
                    }
                }
            }
        }
        System.assert(foundPricingRow,
            'Should find a row for PBV-001 with Lawyers meter type in Legal group');
    }

    @IsTest
    static void testRowKey_UniquePerSubGroup() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        // Row keys must be unique within each sub-group (LWC for:each scope)
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                Set<String> rowKeys = new Set<String>();
                for (PricebookViewController.PricebookViewRow row : sg.rows) {
                    System.assert(!rowKeys.contains(row.rowKey),
                        'Row key should be unique within sub-group (' +
                        grp.groupName + '/' + sg.status + '): ' + row.rowKey);
                    rowKeys.add(row.rowKey);
                }
            }
        }
    }

    // =========================================================================
    // Pricing Basis Tests
    // =========================================================================

    @IsTest
    static void testPricingBasisIncludedInRows() {
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        Product2 product1 = [SELECT Id FROM Product2 WHERE ProductCode = 'PBV-001'];

        Boolean foundRow = false;
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                    for (PricebookViewController.PricebookViewRow row : sg.rows) {
                        if (row.productId == product1.Id) {
                            foundRow = true;
                            System.assertEquals('Tier based', row.pricingBasis,
                                'Pricing Basis should be populated from Product2.Pricing_Basis__c');
                        }
                    }
                }
            }
        }
        System.assert(foundRow, 'Should find product1 row in Legal group');
    }

    // =========================================================================
    // Intapp Pricing Fallback Tests
    // =========================================================================

    @IsTest
    static void testIntappPricingFallback() {
        // Product5 has no Block Pricing GTM records — should fall back to Intapp Pricing
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        Product2 product5 = [SELECT Id FROM Product2 WHERE ProductCode = 'PBV-005'];

        Boolean foundRow = false;
        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                    for (PricebookViewController.PricebookViewRow row : sg.rows) {
                        if (row.productId == product5.Id) {
                            foundRow = true;
                            System.assertEquals('Lawyers', row.meterType,
                                'Meter type should come from Meter Type record');

                            // Check USD_EM1 price from Intapp Pricing (45.00)
                            PricebookViewController.PriceCell usdEm1 = row.prices[0];
                            System.assertEquals('USD', usdEm1.currencyCode);
                            System.assertEquals('EM1', usdEm1.tier);
                            System.assertEquals(45.00, usdEm1.price,
                                'USD EM1 price should come from Intapp Pricing');

                            // Check USD_None price from Intapp Pricing (25.00)
                            PricebookViewController.PriceCell usdNone = row.prices[5];
                            System.assertEquals('USD', usdNone.currencyCode);
                            System.assertEquals('None', usdNone.tier);
                            System.assertEquals(25.00, usdNone.price,
                                'USD None price should come from Intapp Pricing (Tier (none) normalized)');
                        }
                    }
                }
            }
        }
        System.assert(foundRow, 'Should find product5 row in Legal group with Intapp Pricing data');
    }

    @IsTest
    static void testIntappPricingFallback_BlockProductsUnaffected() {
        // Product1 has Block Pricing GTM records — should NOT use Intapp Pricing
        Test.startTest();
        PricebookViewController.PricebookViewResult result =
            PricebookViewController.getPricebookViewData(
                'businessUnit', 'Risk & Compliance', 'Active', null, null
            );
        Test.stopTest();

        Product2 product1 = [SELECT Id FROM Product2 WHERE ProductCode = 'PBV-001'];

        for (PricebookViewController.PricebookViewGroup grp : result.groups) {
            if (grp.groupName == 'Legal') {
                for (PricebookViewController.PricebookViewSubGroup sg : grp.subGroups) {
                    for (PricebookViewController.PricebookViewRow row : sg.rows) {
                        if (row.productId == product1.Id) {
                            // USD_EM1 should still be 30.00 from Block Pricing, NOT Intapp
                            PricebookViewController.PriceCell usdEm1 = row.prices[0];
                            System.assertEquals(30.00, usdEm1.price,
                                'Product1 should still use Block Pricing (30.00), not Intapp');
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // Error Handling Tests
    // =========================================================================

    @IsTest
    static void testGetData_BlankFilterMode() {
        Boolean caughtException = false;
        Test.startTest();
        try {
            PricebookViewController.getPricebookViewData('', 'Legal', 'Active', null, null);
        } catch (AuraHandledException e) {
            caughtException = true;
            System.assert(e.getMessage().contains('required'),
                'Error should mention required fields');
        }
        Test.stopTest();
        System.assert(caughtException,
            'Should throw exception for blank filter mode');
    }

    @IsTest
    static void testGetData_BlankFilterValue() {
        Boolean caughtException = false;
        Test.startTest();
        try {
            PricebookViewController.getPricebookViewData('vertical', '', 'Active', null, null);
        } catch (AuraHandledException e) {
            caughtException = true;
        }
        Test.stopTest();
        System.assert(caughtException,
            'Should throw exception for blank filter value');
    }

    @IsTest
    static void testGetData_InvalidVertical() {
        Boolean caughtException = false;
        Test.startTest();
        try {
            PricebookViewController.getPricebookViewData('vertical', 'InvalidVertical', 'Active', null, null);
        } catch (AuraHandledException e) {
            caughtException = true;
            System.assert(e.getMessage().contains('Invalid vertical'),
                'Error should mention invalid vertical');
        }
        Test.stopTest();
        System.assert(caughtException,
            'Should throw exception for invalid vertical name');
    }

    // =========================================================================
    // Inner Class Coverage Tests
    // =========================================================================

    @IsTest
    static void testInnerClassInstantiation() {
        // Ensure all inner classes can be instantiated
        PricebookViewController.PricebookViewResult viewResult = new PricebookViewController.PricebookViewResult();
        viewResult.groups = new List<PricebookViewController.PricebookViewGroup>();
        viewResult.totalProducts = 0;

        PricebookViewController.PricebookViewGroup grp = new PricebookViewController.PricebookViewGroup();
        grp.groupName = 'Test';
        grp.groupKey = 'test';
        grp.productCount = 0;
        grp.subGroups = new List<PricebookViewController.PricebookViewSubGroup>();

        PricebookViewController.PricebookViewSubGroup sg = new PricebookViewController.PricebookViewSubGroup();
        sg.status = 'Active';
        sg.rows = new List<PricebookViewController.PricebookViewRow>();

        PricebookViewController.PricebookViewRow row = new PricebookViewController.PricebookViewRow();
        row.productId = null;
        row.productCode = 'TEST';
        row.productName = 'Test Product';
        row.productLine = 'Test Line';
        row.productType = 'Software';
        row.pricingBasis = 'Tier based';
        row.meterType = 'Lawyers';
        row.rowKey = 'test_key';
        row.prices = new List<PricebookViewController.PriceCell>();

        PricebookViewController.PriceCell cell = new PricebookViewController.PriceCell();
        cell.key = 'USD_EM1';
        cell.currencyCode = 'USD';
        cell.tier = 'EM1';
        cell.price = 25.00;

        row.prices.add(cell);
        sg.rows.add(row);
        grp.subGroups.add(sg);
        viewResult.groups.add(grp);

        System.assertEquals(1, viewResult.groups.size(), 'Should have one group');
        System.assertEquals('Test', viewResult.groups[0].groupName, 'Group name should match');
    }
}