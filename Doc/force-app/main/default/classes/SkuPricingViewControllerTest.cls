/**
 * @description Test class for SkuPricingViewController.
 *              Covers getPricingData(), savePricingData(), and createPricingRows().
 */
@IsTest
private class SkuPricingViewControllerTest {

    // =========================================================================
    // Test Setup
    // =========================================================================

    /** @description Creates test data for all test methods. */
    @TestSetup
    static void setup() {
        // Tier Based product (gets both Intapp + Block records)
        Product2 tierProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Tier Based Pricing Product',
            ProductCode = 'PV-TIER-001',
            IsActive = true,
            Pricing_Basis__c = 'Tier based',
            Eligible_For_Premium__c = true
        ));

        // Non-Tier product (gets only Intapp records)
        Product2 freeProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Free Pricing Product',
            ProductCode = 'PV-FREE-001',
            IsActive = true,
            Pricing_Basis__c = 'Free',
            Eligible_For_Premium__c = false
        ));

        // Pricebook matching the controller constant
        Pricebook2 fy26Pb = new Pricebook2(Name = 'FY26_All_Products', IsActive = true);
        insert fy26Pb;

        // Intapp Pricing records for the tier product
        List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
        intappRecords.add(new Intapp_Pricing__c(
            Product__c         = tierProduct.Id,
            Product_Code__c    = 'PV-TIER-001',
            Meter_Type__c      = 'Named Users',
            CurrencyIsoCode    = 'USD',
            Tier__c            = 'EM1',
            Price__c           = 100.00,
            Price_Book__c      = fy26Pb.Id,
            Legal_Sales__c     = true,
            A_C_Sales__c       = false,
            FS_Sales__c        = false,
            Corporate_Sales__c = false,
            Ops_Only__c        = false
        ));
        intappRecords.add(new Intapp_Pricing__c(
            Product__c         = tierProduct.Id,
            Product_Code__c    = 'PV-TIER-001',
            Meter_Type__c      = 'Named Users',
            CurrencyIsoCode    = 'USD',
            Tier__c            = 'Tier (none)',
            Price__c           = 50.00,
            Price_Book__c      = fy26Pb.Id,
            Legal_Sales__c     = true,
            A_C_Sales__c       = false,
            FS_Sales__c        = false,
            Corporate_Sales__c = false,
            Ops_Only__c        = false
        ));
        insert intappRecords;

        // Block Pricing record for the tier product
        Block_Pricing__c blockRec = new Block_Pricing__c(
            Product__c                  = tierProduct.Id,
            Block_Pricing_Meter_Type__c = 'Named Users',
            CurrencyIsoCode             = 'USD',
            Tier_Name__c                = 'EM1',
            Price__c                    = 100.00,
            Type__c                     = 'GTM Motion Tier',
            Active__c                   = true
        );
        insert blockRec;

        // Quantity-based product
        Product2 qtyProduct = (Product2) TestFactory.createSObject(new Product2(
            Name = 'Quantity Based Pricing Product',
            ProductCode = 'PV-QTY-001',
            IsActive = true,
            Pricing_Basis__c = 'Quantity based',
            Eligible_For_Premium__c = false
        ));

        // Employee Compliance Block Pricing records for the quantity product
        List<Block_Pricing__c> ecRecords = new List<Block_Pricing__c>();
        ecRecords.add(new Block_Pricing__c(
            Product__c                  = qtyProduct.Id,
            Product_Code__c             = 'PV-QTY-001',
            Block_Pricing_Meter_Type__c = 'Employees',
            CurrencyIsoCode             = 'USD',
            Lower_Bound__c              = 0,
            Upper_Bound__c              = 100,
            Price__c                    = 38.00,
            Type__c                     = 'Employee Compliance',
            Active__c                   = true
        ));
        ecRecords.add(new Block_Pricing__c(
            Product__c                  = qtyProduct.Id,
            Product_Code__c             = 'PV-QTY-001',
            Block_Pricing_Meter_Type__c = 'Employees',
            CurrencyIsoCode             = 'USD',
            Lower_Bound__c              = 101,
            Upper_Bound__c              = 300,
            Price__c                    = 24.00,
            Type__c                     = 'Employee Compliance',
            Active__c                   = true
        ));
        ecRecords.add(new Block_Pricing__c(
            Product__c                  = qtyProduct.Id,
            Product_Code__c             = 'PV-QTY-001',
            Block_Pricing_Meter_Type__c = 'Employees',
            CurrencyIsoCode             = 'GBP',
            Lower_Bound__c              = 0,
            Upper_Bound__c              = 100,
            Price__c                    = 29.90,
            Type__c                     = 'Employee Compliance',
            Active__c                   = true
        ));
        ecRecords.add(new Block_Pricing__c(
            Product__c                  = qtyProduct.Id,
            Product_Code__c             = 'PV-QTY-001',
            Block_Pricing_Meter_Type__c = 'Employees',
            CurrencyIsoCode             = 'GBP',
            Lower_Bound__c              = 101,
            Upper_Bound__c              = 300,
            Price__c                    = 18.90,
            Type__c                     = 'Employee Compliance',
            Active__c                   = true
        ));
        insert ecRecords;
    }

    // =========================================================================
    // Helper Methods
    // =========================================================================

    /** @description Returns the tier-based pricing product from test setup. @return Product2 tier product */
    private static Product2 getTierProduct() {
        return [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PV-TIER-001' LIMIT 1];
    }

    private static Product2 getFreeProduct() {
        return [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PV-FREE-001' LIMIT 1];
    }

    private static String buildNewRowJson(String meterType, Boolean legalSales) {
        SkuPricingViewController.PricingRowWrapper row = new SkuPricingViewController.PricingRowWrapper();
        row.meterType      = meterType;
        row.legalSales     = legalSales;
        row.acSales        = false;
        row.fsSales        = false;
        row.corporateSales = false;
        row.opsOnly        = false;
        row.cells = new List<SkuPricingViewController.PriceCellWrapper>();

        // Add one cell with a price (USD / EM1)
        SkuPricingViewController.PriceCellWrapper cell = new SkuPricingViewController.PriceCellWrapper();
        cell.currencyCode = 'USD';
        cell.tier         = 'EM1';
        cell.price        = 200.00;
        row.cells.add(cell);

        // Add one None-tier cell
        SkuPricingViewController.PriceCellWrapper noneCell = new SkuPricingViewController.PriceCellWrapper();
        noneCell.currencyCode = 'USD';
        noneCell.tier         = 'None';
        noneCell.price        = 75.00;
        row.cells.add(noneCell);

        return JSON.serialize(new List<SkuPricingViewController.PricingRowWrapper>{ row });
    }

    // =========================================================================
    // Tests: getPricingData
    // =========================================================================

    /** @description Verifies getPricingData returns product code and pricing rows for tier-based product. */
    @IsTest
    static void testGetPricingData() {
        Product2 prod = getTierProduct();

        Test.startTest();
        SkuPricingViewController.PricingDataResult result =
            SkuPricingViewController.getPricingData(prod.Id);
        Test.stopTest();

        System.assertEquals('PV-TIER-001', result.productCode, 'Product code should match');
        System.assert(!result.rows.isEmpty(), 'Should have at least one row');

        // Find the Named Users row
        SkuPricingViewController.PricingRowWrapper namedRow = null;
        for (SkuPricingViewController.PricingRowWrapper row : result.rows) {
            if (row.meterType == 'Named Users') {
                namedRow = row;
                break;
            }
        }
        System.assertNotEquals(null, namedRow, 'Should find Named Users row');
        System.assertEquals(true, namedRow.legalSales, 'Legal Sales should be true');
        System.assertEquals(24, namedRow.cells.size(), 'Should have 24 cells (4 currencies x 6 tiers)');
    }

    /** @description Verifies getPricingData returns empty rows when product has no pricing records. */
    @IsTest
    static void testGetPricingDataNoRecords() {
        Product2 prod = getFreeProduct();

        Test.startTest();
        SkuPricingViewController.PricingDataResult result =
            SkuPricingViewController.getPricingData(prod.Id);
        Test.stopTest();

        System.assertEquals('PV-FREE-001', result.productCode, 'Product code should match');
        System.assertEquals(0, result.rows.size(), 'Should have no rows');
    }

    // =========================================================================
    // Tests: savePricingData
    // =========================================================================

    /** @description Verifies savePricingData persists price and sales channel updates to Intapp Pricing. */
    @IsTest
    static void testSavePricingData() {
        Product2 prod = getTierProduct();

        // Get current data
        SkuPricingViewController.PricingDataResult data =
            SkuPricingViewController.getPricingData(prod.Id);

        // Modify the checkbox and price
        SkuPricingViewController.PricingRowWrapper row = data.rows[0];
        row.acSales = true;
        for (SkuPricingViewController.PriceCellWrapper cell : row.cells) {
            if (cell.intappId != null && cell.tier == 'EM1') {
                cell.price = 150.00;
                break;
            }
        }

        String rowsJson = JSON.serialize(data.rows);

        Test.startTest();
        SkuPricingViewController.savePricingData(prod.Id, rowsJson);
        Test.stopTest();

        // Verify updates persisted
        Intapp_Pricing__c updated = [
            SELECT Price__c, A_C_Sales__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-TIER-001' AND Tier__c = 'EM1'
            LIMIT 1
        ];
        System.assertEquals(150.00, updated.Price__c, 'Price should be updated');
        System.assertEquals(true, updated.A_C_Sales__c, 'A&C Sales should be updated');
    }

    // =========================================================================
    // Tests: createPricingRows
    // =========================================================================

    /** @description Verifies createPricingRows creates Intapp and Block records for tier-based product. */
    @IsTest
    static void testCreatePricingRowsTierBased() {
        Product2 prod = getTierProduct();
        // Use 'Lawyers' — valid value for Block_Pricing_Meter_Type__c (restricted picklist)
        String newRowsJson = buildNewRowJson('Lawyers', true);

        Test.startTest();
        SkuPricingViewController.createPricingRows(prod.Id, newRowsJson);
        Test.stopTest();

        // Verify Intapp records created
        List<Intapp_Pricing__c> intappRecs = [
            SELECT Name, Meter_Type__c, CurrencyIsoCode, Tier__c, Price__c,
                   Legal_Sales__c, Premium_price__c, Product_Code__c, Price_book_rule__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-TIER-001' AND Meter_Type__c = 'Lawyers'
        ];
        System.assertEquals(2, intappRecs.size(), 'Should create 2 Intapp records (2 cells with prices)');

        // Verify EM1 record
        Intapp_Pricing__c em1Rec = null;
        for (Intapp_Pricing__c r : intappRecs) {
            if (r.Tier__c == 'EM1') { em1Rec = r; break; }
        }
        System.assertNotEquals(null, em1Rec, 'Should find EM1 record');
        System.assertEquals(200.00, em1Rec.Price__c, 'Price should be 200');
        System.assertEquals(true, em1Rec.Legal_Sales__c, 'Legal Sales should be true');
        System.assertEquals('PV-TIER-001', em1Rec.Product_Code__c, 'Product Code should match');
        // Premium: 200 * 1.2 = 240.00
        System.assertEquals(240.00, em1Rec.Premium_price__c, 'Premium price should be 1.2x');
        // Name format: FY26-ProductCode-MeterType-Currency-OP4I-Tier
        System.assertEquals('FY26-PV-TIER-001-Lawyers-USD-Legal-EM1', em1Rec.Name,
            'Intapp Name should follow FY26-ProductCode-MeterType-Currency-OP4I-Tier');
        // Price book rule should be populated
        System.assertEquals('FY26_All_Products', em1Rec.Price_book_rule__c,
            'Price_book_rule__c should be set to pricebook name');

        // Verify None-tier record uses 'Tier (none)'
        Intapp_Pricing__c noneRec = null;
        for (Intapp_Pricing__c r : intappRecs) {
            if (r.Tier__c == 'Tier (none)') { noneRec = r; break; }
        }
        System.assertNotEquals(null, noneRec, 'Should find Tier (none) record');
        System.assertEquals(75.00, noneRec.Price__c, 'None-tier price should be 75');

        // Verify Block records created (Tier Based product)
        List<Block_Pricing__c> blockRecs = [
            SELECT Block_Pricing_Meter_Type__c, CurrencyIsoCode, Tier_Name__c, Price__c,
                   Type__c, Active__c
            FROM Block_Pricing__c
            WHERE Product__c = :prod.Id AND Block_Pricing_Meter_Type__c = 'Lawyers'
        ];
        System.assertEquals(2, blockRecs.size(), 'Should create 2 Block records');

        // Verify Block None-tier has null Tier_Name__c
        Block_Pricing__c blockNone = null;
        for (Block_Pricing__c b : blockRecs) {
            if (b.Tier_Name__c == null) { blockNone = b; break; }
        }
        System.assertNotEquals(null, blockNone, 'Should find Block record with null tier');
        System.assertEquals(75.00, blockNone.Price__c, 'Block None price should be 75');
        System.assertEquals('GTM Motion Tier', blockNone.Type__c, 'Type should be GTM Motion Tier');
        System.assertEquals(true, blockNone.Active__c, 'Block should be active');
    }

    /** @description Verifies createPricingRows creates only Intapp records for non-tier-based product. */
    @IsTest
    static void testCreatePricingRowsNonTierBased() {
        Product2 prod = getFreeProduct();
        // 'Lawyers' is valid for both Intapp (non-restricted) and Block (restricted) picklists
        String newRowsJson = buildNewRowJson('Lawyers', false);

        Test.startTest();
        SkuPricingViewController.createPricingRows(prod.Id, newRowsJson);
        Test.stopTest();

        // Verify Intapp records created
        List<Intapp_Pricing__c> intappRecs = [
            SELECT Id FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-FREE-001' AND Meter_Type__c = 'Lawyers'
        ];
        System.assertEquals(2, intappRecs.size(), 'Should create 2 Intapp records');

        // Verify NO Block records created (non-Tier Based)
        List<Block_Pricing__c> blockRecs = [
            SELECT Id FROM Block_Pricing__c
            WHERE Product__c = :prod.Id AND Block_Pricing_Meter_Type__c = 'Lawyers'
        ];
        System.assertEquals(0, blockRecs.size(), 'Should NOT create Block records for non-Tier Based product');
    }

    /** @description Verifies createPricingRows populates GearsetExternalId on Intapp and Block records. */
    @IsTest
    static void testCreatePricingRowsGearsetExternalIds() {
        Product2 prod = getTierProduct();
        // Use 'Fee Earners' — valid for Block_Pricing_Meter_Type__c restricted picklist
        String newRowsJson = buildNewRowJson('Fee Earners', true);

        Test.startTest();
        SkuPricingViewController.createPricingRows(prod.Id, newRowsJson);
        Test.stopTest();

        // Verify GearsetExternalId populated on Intapp records
        List<Intapp_Pricing__c> intappRecs = [
            SELECT Id, GearsetExternalId__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-TIER-001' AND Meter_Type__c = 'Fee Earners'
        ];
        System.assert(!intappRecs.isEmpty(), 'Should have created Intapp records');
        for (Intapp_Pricing__c r : intappRecs) {
            System.assertNotEquals(null, r.GearsetExternalId__c,
                'GearsetExternalId should be populated on Intapp record');
        }

        // Verify GearsetExternalId populated on Block records
        List<Block_Pricing__c> blockRecs = [
            SELECT Id, GearsetExternalId__c
            FROM Block_Pricing__c
            WHERE Product__c = :prod.Id AND Block_Pricing_Meter_Type__c = 'Fee Earners'
        ];
        System.assert(!blockRecs.isEmpty(), 'Should have created Block records');
        for (Block_Pricing__c b : blockRecs) {
            System.assertNotEquals(null, b.GearsetExternalId__c,
                'GearsetExternalId should be populated on Block record');
        }
    }

    /** @description Verifies createPricingRows skips cells with null price. */
    @IsTest
    static void testCreatePricingRowsNullCellsSkipped() {
        Product2 prod = getFreeProduct();

        // Build row with one null-price cell
        SkuPricingViewController.PricingRowWrapper row = new SkuPricingViewController.PricingRowWrapper();
        row.meterType      = 'Revenue';
        row.legalSales     = false;
        row.acSales        = false;
        row.fsSales        = false;
        row.corporateSales = false;
        row.opsOnly        = false;
        row.cells = new List<SkuPricingViewController.PriceCellWrapper>();

        // Cell with price
        SkuPricingViewController.PriceCellWrapper cell1 = new SkuPricingViewController.PriceCellWrapper();
        cell1.currencyCode = 'USD';
        cell1.tier         = 'EM1';
        cell1.price        = 300.00;
        row.cells.add(cell1);

        // Cell without price (should be skipped)
        SkuPricingViewController.PriceCellWrapper cell2 = new SkuPricingViewController.PriceCellWrapper();
        cell2.currencyCode = 'GBP';
        cell2.tier         = 'EM1';
        cell2.price        = null;
        row.cells.add(cell2);

        String json = JSON.serialize(new List<SkuPricingViewController.PricingRowWrapper>{ row });

        Test.startTest();
        SkuPricingViewController.createPricingRows(prod.Id, json);
        Test.stopTest();

        // Only 1 record should be created (null-price cell skipped)
        List<Intapp_Pricing__c> recs = [
            SELECT Id FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-FREE-001' AND Meter_Type__c = 'Revenue'
        ];
        System.assertEquals(1, recs.size(), 'Should only create records for cells with prices');
    }

    /** @description Verifies createPricingRows throws AuraHandledException when FY26 pricebook not found. */
    @IsTest
    static void testCreatePricingRowsNoPricebook() {
        Product2 prod = getFreeProduct();

        // Delete the FY26 pricebook
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'FY26_All_Products' LIMIT 1];
        delete pb;

        String newRowsJson = buildNewRowJson('Named Users', false);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            SkuPricingViewController.createPricingRows(prod.Id, newRowsJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException when pricebook not found');
    }

    // =========================================================================
    // Tests: deletePricingByMeterType
    // =========================================================================

    /** @description Verifies deletePricingByMeterType removes Intapp and Block records for the meter type. */
    @IsTest
    static void testDeletePricingByMeterType() {
        Product2 prod = getTierProduct();

        // Verify records exist before delete
        List<Intapp_Pricing__c> intappBefore = [
            SELECT Id FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-TIER-001' AND Meter_Type__c = 'Named Users'
        ];
        List<Block_Pricing__c> blockBefore = [
            SELECT Id FROM Block_Pricing__c
            WHERE Product__c = :prod.Id AND Block_Pricing_Meter_Type__c = 'Named Users'
        ];
        System.assert(!intappBefore.isEmpty(), 'Should have Intapp records before delete');
        System.assert(!blockBefore.isEmpty(), 'Should have Block records before delete');

        Test.startTest();
        SkuPricingViewController.deletePricingByMeterType(prod.Id, 'Named Users');
        Test.stopTest();

        // Verify records deleted
        List<Intapp_Pricing__c> intappAfter = [
            SELECT Id FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-TIER-001' AND Meter_Type__c = 'Named Users'
        ];
        List<Block_Pricing__c> blockAfter = [
            SELECT Id FROM Block_Pricing__c
            WHERE Product__c = :prod.Id AND Block_Pricing_Meter_Type__c = 'Named Users'
        ];
        System.assertEquals(0, intappAfter.size(), 'Intapp records should be deleted');
        System.assertEquals(0, blockAfter.size(), 'Block records should be deleted');
    }

    /** @description Verifies deletePricingByMeterType does not throw when meter type has no records. */
    @IsTest
    static void testDeletePricingByMeterTypeNoRecords() {
        Product2 prod = getTierProduct();

        // Delete a meter type that doesn't exist — should not throw
        Test.startTest();
        SkuPricingViewController.deletePricingByMeterType(prod.Id, 'Nonexistent Meter Type');
        Test.stopTest();

        // Original records should be untouched
        List<Intapp_Pricing__c> intappRemaining = [
            SELECT Id FROM Intapp_Pricing__c
            WHERE Product_Code__c = 'PV-TIER-001' AND Meter_Type__c = 'Named Users'
        ];
        System.assert(!intappRemaining.isEmpty(), 'Named Users records should be untouched');
    }

    /** @description Verifies deletePricingByMeterType throws for null productId or blank meterType. */
    @IsTest
    static void testDeletePricingByMeterTypeNullParams() {
        Product2 prod = getTierProduct();

        // Null productId
        Boolean exThrown = false;
        try {
            SkuPricingViewController.deletePricingByMeterType(null, 'Named Users');
        } catch (AuraHandledException e) {
            exThrown = true;
        }
        System.assert(exThrown, 'Should throw when productId is null');

        // Blank meterType
        exThrown = false;
        try {
            SkuPricingViewController.deletePricingByMeterType(prod.Id, '');
        } catch (AuraHandledException e) {
            exThrown = true;
        }
        System.assert(exThrown, 'Should throw when meterType is blank');
    }

    // =========================================================================
    // Tests: Quantity Based Pricing (Employee Compliance)
    // =========================================================================

    /** @description Returns the quantity-based pricing product from test setup. @return Product2 quantity product */
    private static Product2 getQtyProduct() {
        return [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PV-QTY-001' LIMIT 1];
    }

    /** @description Verifies that getQuantityPricingData returns meter type groups and quantity bands. */
    @IsTest
    static void testGetQuantityPricingData() {
        Product2 prod = getQtyProduct();

        Test.startTest();
        SkuPricingViewController.QuantityPricingResult result =
            SkuPricingViewController.getQuantityPricingData(prod.Id);
        Test.stopTest();

        System.assertEquals('PV-QTY-001', result.productCode, 'Product code should match');
        System.assertEquals(1, result.meterTypes.size(), 'Should have 1 meter type group (Employees)');

        SkuPricingViewController.QuantityMeterTypeGroup grp = result.meterTypes[0];
        System.assertEquals('Employees', grp.meterType, 'Meter type should be Employees');
        System.assertEquals(2, grp.bands.size(), 'Should have 2 quantity bands');

        // Verify first band (0–100)
        SkuPricingViewController.QuantityBandRow band1 = grp.bands[0];
        System.assertEquals(0, band1.lowerBound, 'First band lower bound should be 0');
        System.assertEquals(100, band1.upperBound, 'First band upper bound should be 100');
        System.assertEquals(4, band1.cells.size(), 'Each band should have 4 currency cells');

        // Verify USD cell price in first band
        SkuPricingViewController.QuantityPriceCell usdCell = null;
        for (SkuPricingViewController.QuantityPriceCell c : band1.cells) {
            if (c.currencyCode == 'USD') { usdCell = c; break; }
        }
        System.assertNotEquals(null, usdCell, 'Should have USD cell');
        System.assertEquals(38.00, usdCell.price, 'USD price should be 38.00');
        System.assertNotEquals(null, usdCell.blockId, 'Block Id should be populated');

        // Verify GBP cell price in first band
        SkuPricingViewController.QuantityPriceCell gbpCell = null;
        for (SkuPricingViewController.QuantityPriceCell c : band1.cells) {
            if (c.currencyCode == 'GBP') { gbpCell = c; break; }
        }
        System.assertNotEquals(null, gbpCell, 'Should have GBP cell');
        System.assertEquals(29.90, gbpCell.price, 'GBP price should be 29.90');

        // EUR and AUD should have null prices (no records created)
        SkuPricingViewController.QuantityPriceCell eurCell = null;
        for (SkuPricingViewController.QuantityPriceCell c : band1.cells) {
            if (c.currencyCode == 'EUR') { eurCell = c; break; }
        }
        System.assertNotEquals(null, eurCell, 'Should have EUR cell');
        System.assertEquals(null, eurCell.price, 'EUR price should be null (no record)');
    }

    /** @description Verifies that getQuantityPricingData returns empty meter types when no records exist. */
    @IsTest
    static void testGetQuantityPricingDataNoRecords() {
        Product2 prod = getFreeProduct();

        Test.startTest();
        SkuPricingViewController.QuantityPricingResult result =
            SkuPricingViewController.getQuantityPricingData(prod.Id);
        Test.stopTest();

        System.assertEquals('PV-FREE-001', result.productCode, 'Product code should match');
        System.assertEquals(0, result.meterTypes.size(), 'Should have no meter type groups');
    }

    /** @description Verifies that saveQuantityPricingData persists price updates to Block records. */
    @IsTest
    static void testSaveQuantityPricingData() {
        Product2 prod = getQtyProduct();

        // Get current data
        SkuPricingViewController.QuantityPricingResult data =
            SkuPricingViewController.getQuantityPricingData(prod.Id);

        // Update the first band's USD price from 38 to 42
        SkuPricingViewController.QuantityMeterTypeGroup grp = data.meterTypes[0];
        for (SkuPricingViewController.QuantityPriceCell c : grp.bands[0].cells) {
            if (c.currencyCode == 'USD') {
                c.price = 42.00;
                break;
            }
        }

        String rowsJson = JSON.serialize(data.meterTypes);

        Test.startTest();
        SkuPricingViewController.saveQuantityPricingData(prod.Id, rowsJson);
        Test.stopTest();

        // Verify price updated
        Block_Pricing__c updated = [
            SELECT Price__c FROM Block_Pricing__c
            WHERE Product_Code__c = 'PV-QTY-001'
              AND Type__c = 'Employee Compliance'
              AND CurrencyIsoCode = 'USD'
              AND Lower_Bound__c = 0
            LIMIT 1
        ];
        System.assertEquals(42.00, updated.Price__c, 'Price should be updated to 42.00');
    }

    /** @description Verifies that deleteQuantityPricingByMeterType removes Employee Compliance Block records. */
    @IsTest
    static void testDeleteQuantityPricingByMeterType() {
        Product2 prod = getQtyProduct();

        // Verify records exist
        List<Block_Pricing__c> before = [
            SELECT Id FROM Block_Pricing__c
            WHERE Product_Code__c = 'PV-QTY-001'
              AND Type__c = 'Employee Compliance'
              AND Block_Pricing_Meter_Type__c = 'Employees'
        ];
        System.assertEquals(4, before.size(), 'Should have 4 EC records before delete');

        Test.startTest();
        SkuPricingViewController.deleteQuantityPricingByMeterType(prod.Id, 'Employees');
        Test.stopTest();

        List<Block_Pricing__c> after = [
            SELECT Id FROM Block_Pricing__c
            WHERE Product_Code__c = 'PV-QTY-001'
              AND Type__c = 'Employee Compliance'
              AND Block_Pricing_Meter_Type__c = 'Employees'
        ];
        System.assertEquals(0, after.size(), 'All EC records should be deleted');
    }
}