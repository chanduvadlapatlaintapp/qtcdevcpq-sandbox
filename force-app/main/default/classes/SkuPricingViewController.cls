/**
 * @description Controller for the Update Pricing matrix view in the SKU Management App.
 *              Combines Intapp_Pricing__c (matched by Product Code + FY26_All_Products pricebook)
 *              and Block_Pricing__c (Type = GTM Motion Tier, linked via Product lookup) into a
 *              pivoted matrix keyed by Meter Type × Currency × Tier.
 */
public with sharing class SkuPricingViewController {

    private static final List<String> CURRENCIES = new List<String>{'USD', 'GBP', 'EUR', 'AUD'};
    private static final List<String> TIERS      = new List<String>{'EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'};
    private static final String NONE_TIER_INTAPP  = 'Tier (none)';
    private static final String PRICEBOOK_NAME    = 'FY26_All_Products';
    private static final String PRICEBOOK_CODE    = 'FY26';
    private static final String TIER_BASED           = 'Tier based';
    private static final String EMPLOYEE_COMPLIANCE  = 'Employee Compliance';
    private static final String QUANTITY_BASED       = 'Quantity based';

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * @description Returns a pivoted pricing matrix for the given product.
     *              Rows correspond to Meter Types; columns to 5 pricebook checkboxes
     *              + 24 price cells (4 currencies x 6 tiers).
     * @param productId Product2 record Id
     * @return PricingDataResult containing productCode and list of PricingRowWrapper
     */
    @AuraEnabled
    public static PricingDataResult getPricingData(Id productId) {
        try {
            Product2 prod = [SELECT ProductCode FROM Product2 WHERE Id = :productId LIMIT 1];
            String productCode = prod.ProductCode;

            // Intapp Pricing: matched by product code + FY26_All_Products pricebook
            List<Intapp_Pricing__c> intappRecs = [
                SELECT Id, Meter_Type__c, CurrencyIsoCode, Tier__c, Price__c,
                       Legal_Sales__c, A_C_Sales__c, FS_Sales__c, Corporate_Sales__c, Ops_Only__c
                FROM Intapp_Pricing__c
                WHERE Product_Code__c = :productCode
                  AND Price_Book__r.Name = :PRICEBOOK_NAME
                ORDER BY Meter_Type__c, CurrencyIsoCode
            ];

            // Block Pricing: linked via Product lookup, Type = GTM Motion Tier
            List<Block_Pricing__c> blockRecs = [
                SELECT Id, Block_Pricing_Meter_Type__c, CurrencyIsoCode, Tier_Name__c, Price__c
                FROM Block_Pricing__c
                WHERE Product__c = :productId
                  AND Type__c = 'GTM Motion Tier'
                ORDER BY Block_Pricing_Meter_Type__c, CurrencyIsoCode, Tier_Name__c
            ];

            // Build maps: meterType → currency → tier → record
            Map<String, Map<String, Map<String, Intapp_Pricing__c>>> intappMap = buildIntappMap(intappRecs);
            Map<String, Map<String, Map<String, Block_Pricing__c>>>  blockMap  = buildBlockMap(blockRecs);

            // Union of all meter types, sorted
            Set<String> allMeterTypes = new Set<String>();
            allMeterTypes.addAll(intappMap.keySet());
            allMeterTypes.addAll(blockMap.keySet());
            List<String> sortedMeterTypes = new List<String>(allMeterTypes);
            sortedMeterTypes.sort();

            List<PricingRowWrapper> rows = new List<PricingRowWrapper>();
            for (String mt : sortedMeterTypes) {
                rows.add(buildRow(mt, intappMap, blockMap));
            }

            PricingDataResult result = new PricingDataResult();
            result.productCode = productCode;
            result.rows = rows;
            return result;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Creates new pricing rows for a product. Inserts Intapp_Pricing__c records
     *              for all cells with a price, and Block_Pricing__c records only for Tier Based products.
     *              Populates Gearset External IDs after insert.
     * @param productId Product2 record Id
     * @param newRowsJson JSON string of List<PricingRowWrapper> (new rows only)
     */
    @AuraEnabled
    public static void createPricingRows(Id productId, String newRowsJson) {
        try {
            // Query product details
            Product2 prod = [
                SELECT ProductCode, Pricing_Basis__c, Eligible_For_Premium__c
                FROM Product2
                WHERE Id = :productId
                LIMIT 1
            ];

            // Find the FY26_All_Products pricebook
            List<Pricebook2> pbs = [
                SELECT Id FROM Pricebook2
                WHERE Name = :PRICEBOOK_NAME AND IsActive = true
                LIMIT 1
            ];
            if (pbs.isEmpty()) {
                throw new AuraHandledException('Pricebook "' + PRICEBOOK_NAME + '" not found.');
            }
            Id pricebookId = pbs[0].Id;

            // Deserialize rows (reuses existing PricingRowWrapper)
            List<PricingRowWrapper> newRows = (List<PricingRowWrapper>) JSON.deserialize(
                newRowsJson, List<PricingRowWrapper>.class
            );

            // Determine whether this product is Tier Based (case-insensitive)
            Boolean isTierBased = TIER_BASED.equalsIgnoreCase(prod.Pricing_Basis__c);

            // Build Intapp_Pricing__c + Block_Pricing__c records
            List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
            List<Block_Pricing__c>  blockRecords  = new List<Block_Pricing__c>();

            for (PricingRowWrapper row : newRows) {
                if (row.cells == null) continue;

                // Derive OP4I pricebook abbreviation for the Name field
                String op4iAbbrev = deriveOp4iAbbrev(row);

                for (PriceCellWrapper cell : row.cells) {
                    if (cell.price == null) continue;

                    String intappTier = (cell.tier == 'None') ? NONE_TIER_INTAPP : cell.tier;

                    // Build Intapp Pricing Name: FY26-ProductCode-MeterType-Currency-OP4I-Tier
                    String intappName = PRICEBOOK_CODE + '-' + prod.ProductCode + '-' +
                                        row.meterType + '-' + cell.currencyCode +
                                        (String.isNotBlank(op4iAbbrev) ? '-' + op4iAbbrev : '') +
                                        '-' + intappTier;

                    Intapp_Pricing__c intapp = new Intapp_Pricing__c(
                        Name               = intappName,
                        Product__c         = productId,
                        Product_Code__c    = prod.ProductCode,
                        Meter_Type__c      = row.meterType,
                        CurrencyIsoCode    = cell.currencyCode,
                        Tier__c            = intappTier,
                        Price__c           = cell.price,
                        Price_Book__c      = pricebookId,
                        Price_book_rule__c = PRICEBOOK_NAME,
                        Legal_Sales__c     = row.legalSales,
                        A_C_Sales__c       = row.acSales,
                        FS_Sales__c        = row.fsSales,
                        Corporate_Sales__c = row.corporateSales,
                        Ops_Only__c        = row.opsOnly
                    );

                    // Premium Price: 1.2 × Standard Price if product is eligible
                    if (prod.Eligible_For_Premium__c == true && cell.price > 0) {
                        intapp.Premium_price__c = (cell.price * 1.2).setScale(2, RoundingMode.HALF_UP);
                    }

                    intappRecords.add(intapp);

                    // Block_Pricing__c — only for Tier Based products
                    if (isTierBased) {
                        blockRecords.add(new Block_Pricing__c(
                            Product__c                  = productId,
                            Product_Code__c             = prod.ProductCode,
                            Block_Pricing_Meter_Type__c = row.meterType,
                            CurrencyIsoCode             = cell.currencyCode,
                            Tier_Name__c                = (cell.tier == 'None') ? null : cell.tier,
                            Price__c                    = cell.price,
                            Type__c                     = 'GTM Motion Tier',
                            Active__c                   = true,
                            Fiscal_Year__c              = PRICEBOOK_CODE,
                            Price_Book__c               = pricebookId,
                            Lower_Bound__c              = 0,
                            Upper_Bound__c              = 999999999
                        ));
                    }
                }
            }

            // Insert records
            if (!intappRecords.isEmpty()) insert intappRecords;
            if (!blockRecords.isEmpty())  insert blockRecords;

            // Populate Gearset External IDs (same pattern as PricebookWizardController)
            populateIntappGearsetExternalIds(intappRecords);
            populateBlockGearsetExternalIds(blockRecords);

            // Sync GearsetExternalId onto in-memory records (populate helpers update DB
            // via new SObject instances, leaving the original list field null) then capture
            for (Intapp_Pricing__c rec : intappRecords) {
                if (rec.Id != null) rec.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(rec.Id);
            }
            StagingCaptureService.capture(intappRecords, 'Intapp_Pricing__c', 'Create');
            for (Block_Pricing__c rec : blockRecords) {
                if (rec.Id != null) rec.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(rec.Id);
            }
            StagingCaptureService.capture(blockRecords, 'Block_Pricing__c', 'Create');

        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Saves pricing changes to both Intapp_Pricing__c (price + checkboxes)
     *              and Block_Pricing__c (price only).
     * @param productId Product2 record Id (used to derive product code for Intapp lookup)
     * @param rowsJson JSON string of List<PricingRowWrapper>
     */
    @AuraEnabled
    public static void savePricingData(Id productId, String rowsJson) {
        try {
            Product2 prod = [SELECT ProductCode FROM Product2 WHERE Id = :productId LIMIT 1];
            String productCode = prod.ProductCode;

            List<PricingRowWrapper> rows = (List<PricingRowWrapper>) JSON.deserialize(
                rowsJson, List<PricingRowWrapper>.class
            );

            // Index rows and build price-by-id maps
            Set<String> meterTypes = new Set<String>();
            Map<String, PricingRowWrapper> rowByMeterType = new Map<String, PricingRowWrapper>();
            Map<String, Decimal> priceByIntappId = new Map<String, Decimal>();
            Map<String, Decimal> priceByBlockId  = new Map<String, Decimal>();

            for (PricingRowWrapper row : rows) {
                meterTypes.add(row.meterType);
                rowByMeterType.put(row.meterType, row);
                for (PriceCellWrapper cell : row.cells) {
                    if (String.isNotBlank(cell.intappId)) priceByIntappId.put(cell.intappId, cell.price);
                    if (String.isNotBlank(cell.blockId))  priceByBlockId.put(cell.blockId,  cell.price);
                }
            }

            // Query all Intapp records for the affected meter types and apply changes
            List<Intapp_Pricing__c> intappToUpdate = [
                SELECT Id, Meter_Type__c, Price__c, Premium_price__c,
                       Legal_Sales__c, A_C_Sales__c, FS_Sales__c, Corporate_Sales__c, Ops_Only__c,
                       GearsetExternalId__c
                FROM Intapp_Pricing__c
                WHERE Product_Code__c = :productCode
                  AND Price_Book__r.Name = :PRICEBOOK_NAME
                  AND Meter_Type__c IN :meterTypes
            ];

            for (Intapp_Pricing__c r : intappToUpdate) {
                PricingRowWrapper row = rowByMeterType.get(r.Meter_Type__c);
                if (row != null) {
                    r.Legal_Sales__c    = row.legalSales;
                    r.A_C_Sales__c      = row.acSales;
                    r.FS_Sales__c       = row.fsSales;
                    r.Corporate_Sales__c = row.corporateSales;
                    r.Ops_Only__c       = row.opsOnly;
                }
                if (priceByIntappId.containsKey(r.Id)) {
                    r.Price__c = priceByIntappId.get(r.Id);
                    // Auto-sync Premium Price: 1.2 × Standard Price (only if Premium already exists)
                    if (r.Premium_price__c != null && r.Price__c != null) {
                        r.Premium_price__c = r.Price__c * 1.2;
                    }
                }
            }

            // Build Block Pricing update list — query first to get GearsetExternalId__c
            List<Block_Pricing__c> blockToUpdate = new List<Block_Pricing__c>();
            if (!priceByBlockId.isEmpty()) {
                blockToUpdate = [
                    SELECT Id, GearsetExternalId__c FROM Block_Pricing__c
                    WHERE Id IN :priceByBlockId.keySet()
                ];
                for (Block_Pricing__c rec : blockToUpdate) {
                    rec.Price__c = priceByBlockId.get(rec.Id);
                }
            }

            if (!intappToUpdate.isEmpty()) update intappToUpdate;
            if (!blockToUpdate.isEmpty())  update blockToUpdate;
            StagingCaptureService.capture(intappToUpdate, 'Intapp_Pricing__c', 'Update');
            StagingCaptureService.capture(blockToUpdate, 'Block_Pricing__c', 'Update');

        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes all Intapp_Pricing__c and Block_Pricing__c records
     *              for a specific product + meter type combination.
     * @param productId Product2 record Id
     * @param meterType Meter type value to delete (e.g. 'Named Users')
     */
    @AuraEnabled
    public static void deletePricingByMeterType(Id productId, String meterType) {
        try {
            if (productId == null) {
                throw new AuraHandledException('Product Id is required.');
            }
            if (String.isBlank(meterType)) {
                throw new AuraHandledException('Meter Type is required.');
            }

            Product2 prod = [SELECT ProductCode FROM Product2 WHERE Id = :productId LIMIT 1];
            String productCode = prod.ProductCode;

            // Delete Intapp Pricing records
            List<Intapp_Pricing__c> intappToDelete = [
                SELECT Id, GearsetExternalId__c FROM Intapp_Pricing__c
                WHERE Product_Code__c = :productCode
                  AND Meter_Type__c = :meterType
                  AND Price_Book__r.Name = :PRICEBOOK_NAME
            ];

            // Delete Block Pricing records
            List<Block_Pricing__c> blockToDelete = [
                SELECT Id, GearsetExternalId__c FROM Block_Pricing__c
                WHERE Product__c = :productId
                  AND Block_Pricing_Meter_Type__c = :meterType
                  AND Type__c = 'GTM Motion Tier'
            ];

            if (!intappToDelete.isEmpty()) {
                delete intappToDelete;
                StagingCaptureService.captureDeletes(intappToDelete, 'Intapp_Pricing__c');
            }
            if (!blockToDelete.isEmpty()) {
                delete blockToDelete;
                StagingCaptureService.captureDeletes(blockToDelete, 'Block_Pricing__c');
            }

            Nebula.Logger.info(
                'Deleted pricing for meter type "' + meterType + '": ' +
                intappToDelete.size() + ' Intapp, ' + blockToDelete.size() + ' Block records'
            ).addTag('SkuPricingView').setRecordId(productId);
            Nebula.Logger.saveLog();
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (DmlException e) {
            Nebula.Logger.error(e.getMessage()).addTag('SkuPricingView');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('SkuPricingView');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Quantity Based Pricing API
    // =========================================================================

    /**
     * @description Returns quantity-based pricing data for a product.
     *              Groups Block_Pricing__c records (Type = Employee Compliance)
     *              by Meter Type, then pivots into bands (Lower/Upper Bound) × 4 currencies.
     * @param productId Product2 record Id
     * @return QuantityPricingResult containing productCode and meter type groups
     */
    @AuraEnabled
    public static QuantityPricingResult getQuantityPricingData(Id productId) {
        try {
            Product2 prod = [SELECT ProductCode FROM Product2 WHERE Id = :productId LIMIT 1];
            String productCode = prod.ProductCode;

            List<Block_Pricing__c> recs = [
                SELECT Id, Block_Pricing_Meter_Type__c, CurrencyIsoCode,
                       Lower_Bound__c, Upper_Bound__c, Price__c
                FROM Block_Pricing__c
                WHERE Product_Code__c = :productCode
                  AND Type__c = :EMPLOYEE_COMPLIANCE
                ORDER BY Block_Pricing_Meter_Type__c, Lower_Bound__c, CurrencyIsoCode
            ];

            // Build nested map: meterType → bandKey → currency → record
            Map<String, Map<String, Map<String, Block_Pricing__c>>> dataMap =
                new Map<String, Map<String, Map<String, Block_Pricing__c>>>();

            // Track ordered band keys per meter type
            Map<String, List<String>> orderedBands = new Map<String, List<String>>();
            Map<String, Map<String, Decimal[]>> bandBounds = new Map<String, Map<String, Decimal[]>>();

            for (Block_Pricing__c r : recs) {
                String mt = r.Block_Pricing_Meter_Type__c;
                String bandKey = String.valueOf(r.Lower_Bound__c) + '_' + String.valueOf(r.Upper_Bound__c);
                String curr = r.CurrencyIsoCode;

                if (!dataMap.containsKey(mt)) {
                    dataMap.put(mt, new Map<String, Map<String, Block_Pricing__c>>());
                    orderedBands.put(mt, new List<String>());
                    bandBounds.put(mt, new Map<String, Decimal[]>());
                }
                if (!dataMap.get(mt).containsKey(bandKey)) {
                    dataMap.get(mt).put(bandKey, new Map<String, Block_Pricing__c>());
                    orderedBands.get(mt).add(bandKey);
                    bandBounds.get(mt).put(bandKey, new Decimal[]{ r.Lower_Bound__c, r.Upper_Bound__c });
                }
                dataMap.get(mt).get(bandKey).put(curr, r);
            }

            // Build result
            List<String> sortedMeterTypes = new List<String>(dataMap.keySet());
            sortedMeterTypes.sort();

            List<QuantityMeterTypeGroup> groups = new List<QuantityMeterTypeGroup>();
            for (String mt : sortedMeterTypes) {
                QuantityMeterTypeGroup grp = new QuantityMeterTypeGroup();
                grp.meterType = mt;
                grp.bands = new List<QuantityBandRow>();

                for (String bandKey : orderedBands.get(mt)) {
                    Decimal[] bounds = bandBounds.get(mt).get(bandKey);
                    QuantityBandRow band = new QuantityBandRow();
                    band.lowerBound = bounds[0];
                    band.upperBound = bounds[1];
                    band.bandLabel = formatBound(bounds[0]) + ' – ' + formatBound(bounds[1]);
                    band.cells = new List<QuantityPriceCell>();

                    for (String curr : CURRENCIES) {
                        QuantityPriceCell cell = new QuantityPriceCell();
                        cell.currencyCode = curr;
                        if (dataMap.get(mt).get(bandKey).containsKey(curr)) {
                            Block_Pricing__c rec = dataMap.get(mt).get(bandKey).get(curr);
                            cell.blockId = rec.Id;
                            cell.price = rec.Price__c;
                        }
                        band.cells.add(cell);
                    }
                    grp.bands.add(band);
                }
                groups.add(grp);
            }

            QuantityPricingResult result = new QuantityPricingResult();
            result.productCode = productCode;
            result.meterTypes = groups;
            return result;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Saves price changes to quantity-based Block_Pricing__c records.
     * @param productId Product2 record Id
     * @param rowsJson JSON string of List<QuantityMeterTypeGroup>
     */
    @AuraEnabled
    public static void saveQuantityPricingData(Id productId, String rowsJson) {
        try {
            List<QuantityMeterTypeGroup> groups = (List<QuantityMeterTypeGroup>) JSON.deserialize(
                rowsJson, List<QuantityMeterTypeGroup>.class
            );

            // Collect blockId → price from all cells
            Map<Id, Decimal> priceByBlockId = new Map<Id, Decimal>();
            for (QuantityMeterTypeGroup grp : groups) {
                if (grp.bands == null) continue;
                for (QuantityBandRow band : grp.bands) {
                    if (band.cells == null) continue;
                    for (QuantityPriceCell cell : band.cells) {
                        if (String.isNotBlank(cell.blockId)) {
                            priceByBlockId.put(cell.blockId, cell.price);
                        }
                    }
                }
            }

            if (priceByBlockId.isEmpty()) return;

            // Query and update
            List<Block_Pricing__c> toUpdate = [
                SELECT Id, Price__c, GearsetExternalId__c FROM Block_Pricing__c
                WHERE Id IN :priceByBlockId.keySet()
            ];

            for (Block_Pricing__c rec : toUpdate) {
                rec.Price__c = priceByBlockId.get(rec.Id);
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
                StagingCaptureService.capture(toUpdate, 'Block_Pricing__c', 'Update');
            }

            Nebula.Logger.info(
                'Saved quantity pricing: ' + toUpdate.size() + ' Block_Pricing__c records updated'
            ).addTag('SkuPricingView').setRecordId(productId);
            Nebula.Logger.saveLog();

        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes all Employee Compliance Block_Pricing__c records
     *              for a specific product + meter type combination.
     * @param productId Product2 record Id
     * @param meterType Meter type value to delete (e.g. 'Employees')
     */
    @AuraEnabled
    public static void deleteQuantityPricingByMeterType(Id productId, String meterType) {
        try {
            if (productId == null) {
                throw new AuraHandledException('Product Id is required.');
            }
            if (String.isBlank(meterType)) {
                throw new AuraHandledException('Meter Type is required.');
            }

            Product2 prod = [SELECT ProductCode FROM Product2 WHERE Id = :productId LIMIT 1];
            String productCode = prod.ProductCode;

            List<Block_Pricing__c> toDelete = [
                SELECT Id, GearsetExternalId__c FROM Block_Pricing__c
                WHERE Product_Code__c = :productCode
                  AND Block_Pricing_Meter_Type__c = :meterType
                  AND Type__c = :EMPLOYEE_COMPLIANCE
            ];

            if (!toDelete.isEmpty()) {
                delete toDelete;
                StagingCaptureService.captureDeletes(toDelete, 'Block_Pricing__c');
            }

            Nebula.Logger.info(
                'Deleted quantity pricing for meter type "' + meterType + '": ' +
                toDelete.size() + ' Block_Pricing__c records'
            ).addTag('SkuPricingView').setRecordId(productId);
            Nebula.Logger.saveLog();

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (DmlException e) {
            Nebula.Logger.error(e.getMessage()).addTag('SkuPricingView');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('SkuPricingView');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Private Helpers
    // =========================================================================

    /**
     * @description Builds a nested map of Intapp_Pricing__c records keyed by meter type, currency, and tier.
     * @param recs List of Intapp_Pricing__c records
     * @return Map of meterType -> currency -> tier -> Intapp_Pricing__c
     */
    private static Map<String, Map<String, Map<String, Intapp_Pricing__c>>> buildIntappMap(
            List<Intapp_Pricing__c> recs) {
        Map<String, Map<String, Map<String, Intapp_Pricing__c>>> m =
            new Map<String, Map<String, Map<String, Intapp_Pricing__c>>>();
        for (Intapp_Pricing__c r : recs) {
            String mt   = r.Meter_Type__c;
            String curr = r.CurrencyIsoCode;
            String tier = (r.Tier__c == null || r.Tier__c == NONE_TIER_INTAPP) ? 'None' : r.Tier__c;
            if (!m.containsKey(mt))         m.put(mt, new Map<String, Map<String, Intapp_Pricing__c>>());
            if (!m.get(mt).containsKey(curr)) m.get(mt).put(curr, new Map<String, Intapp_Pricing__c>());
            m.get(mt).get(curr).put(tier, r);
        }
        return m;
    }

    /**
     * @description Builds a nested map of Block_Pricing__c records keyed by meter type, currency, and tier.
     * @param recs List of Block_Pricing__c records
     * @return Map of meterType -> currency -> tier -> Block_Pricing__c
     */
    private static Map<String, Map<String, Map<String, Block_Pricing__c>>> buildBlockMap(
            List<Block_Pricing__c> recs) {
        Map<String, Map<String, Map<String, Block_Pricing__c>>> m =
            new Map<String, Map<String, Map<String, Block_Pricing__c>>>();
        for (Block_Pricing__c r : recs) {
            String mt   = r.Block_Pricing_Meter_Type__c;
            String curr = r.CurrencyIsoCode;
            String tier = (r.Tier_Name__c == null) ? 'None' : r.Tier_Name__c;
            if (!m.containsKey(mt))         m.put(mt, new Map<String, Map<String, Block_Pricing__c>>());
            if (!m.get(mt).containsKey(curr)) m.get(mt).put(curr, new Map<String, Block_Pricing__c>());
            m.get(mt).get(curr).put(tier, r);
        }
        return m;
    }

    /**
     * @description Builds a single pricing row for a meter type from Intapp and Block pricing maps.
     * @param mt Meter type for the row
     * @param intappMap Nested map of Intapp_Pricing__c records
     * @param blockMap Nested map of Block_Pricing__c records
     * @return PricingRowWrapper with OP4I checkboxes and 24 price cells
     */
    private static PricingRowWrapper buildRow(
            String mt,
            Map<String, Map<String, Map<String, Intapp_Pricing__c>>> intappMap,
            Map<String, Map<String, Map<String, Block_Pricing__c>>>  blockMap) {

        PricingRowWrapper row = new PricingRowWrapper();
        row.meterType = mt;
        row.cells = new List<PriceCellWrapper>();

        // Derive checkbox values from the first available Intapp record for this meter type
        if (intappMap.containsKey(mt)) {
            Boolean found = false;
            for (String curr : intappMap.get(mt).keySet()) {
                if (found) break;
                for (String tier : intappMap.get(mt).get(curr).keySet()) {
                    Intapp_Pricing__c r = intappMap.get(mt).get(curr).get(tier);
                    row.legalSales     = r.Legal_Sales__c;
                    row.acSales        = r.A_C_Sales__c;
                    row.fsSales        = r.FS_Sales__c;
                    row.corporateSales = r.Corporate_Sales__c;
                    row.opsOnly        = r.Ops_Only__c;
                    found = true;
                    break;
                }
            }
        }

        // Build 24 price cells: 4 currencies x 6 tiers
        for (String curr : CURRENCIES) {
            for (String tier : TIERS) {
                PriceCellWrapper cell = new PriceCellWrapper();
                cell.currencyCode = curr;
                cell.tier     = tier;

                Boolean hasIntapp = intappMap.containsKey(mt) && intappMap.get(mt).containsKey(curr)
                        && intappMap.get(mt).get(curr).containsKey(tier);
                Boolean hasBlock  = blockMap.containsKey(mt)  && blockMap.get(mt).containsKey(curr)
                        && blockMap.get(mt).get(curr).containsKey(tier);

                if (hasIntapp) {
                    Intapp_Pricing__c r = intappMap.get(mt).get(curr).get(tier);
                    cell.intappId = r.Id;
                    cell.price    = r.Price__c;
                }
                if (hasBlock) {
                    Block_Pricing__c r = blockMap.get(mt).get(curr).get(tier);
                    cell.blockId = r.Id;
                    if (cell.price == null) cell.price = r.Price__c;
                }

                row.cells.add(cell);
            }
        }

        return row;
    }

    /**
     * @description Formats a numeric bound value with comma separators and no decimals.
     *              e.g. 1000 → "1,000"; 999999 → "999,999"
     */
    private static String formatBound(Decimal val) {
        if (val == null) return '0';
        Long intVal = val.longValue();
        String raw = String.valueOf(intVal);
        // Insert commas for thousands
        String result = '';
        Integer count = 0;
        for (Integer i = raw.length() - 1; i >= 0; i--) {
            if (count > 0 && Math.mod(count, 3) == 0) {
                result = ',' + result;
            }
            result = raw.substring(i, i + 1) + result;
            count++;
        }
        return result;
    }

    /**
     * @description Derives the OP4I pricebook abbreviation for the record Name field.
     *              Uses the first checked pricebook checkbox: Legal→"Legal", AC→"AC",
     *              FS→"FS", Corporate→"Corporate", Ops Only→"Ops Only".
     * @param row The PricingRowWrapper with checkbox values
     * @return Abbreviation string, or empty string if none checked
     */
    private static String deriveOp4iAbbrev(PricingRowWrapper row) {
        if (row.legalSales == true)     return 'Legal';
        if (row.acSales == true)        return 'AC';
        if (row.fsSales == true)        return 'FS';
        if (row.corporateSales == true) return 'Corporate';
        if (row.opsOnly == true)        return 'Ops Only';
        return '';
    }

    // =========================================================================
    // Gearset External ID Helpers
    // =========================================================================

    /**
     * @description Populates GearsetExternalId__c on successfully-inserted Intapp_Pricing__c records.
     *              Uses reversed record Id to match Gearset cross-org convention.
     * @param records The inserted Intapp_Pricing__c records
     */
    private static void populateIntappGearsetExternalIds(List<Intapp_Pricing__c> records) {
        List<Intapp_Pricing__c> toUpdate = new List<Intapp_Pricing__c>();
        for (Intapp_Pricing__c rec : records) {
            if (rec.Id != null) {
                toUpdate.add(new Intapp_Pricing__c(
                    Id = rec.Id,
                    GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(rec.Id)
                ));
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    /**
     * @description Populates GearsetExternalId__c on successfully-inserted Block_Pricing__c records.
     *              Uses reversed record Id to match Gearset cross-org convention.
     * @param records The inserted Block_Pricing__c records
     */
    private static void populateBlockGearsetExternalIds(List<Block_Pricing__c> records) {
        List<Block_Pricing__c> toUpdate = new List<Block_Pricing__c>();
        for (Block_Pricing__c rec : records) {
            if (rec.Id != null) {
                toUpdate.add(new Block_Pricing__c(
                    Id = rec.Id,
                    GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(rec.Id)
                ));
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    // =========================================================================
    // Inner Classes
    // =========================================================================

    /**
     * @description Result wrapper for getPricingData with product code and pivoted pricing rows.
     */
    public class PricingDataResult {
        @AuraEnabled public String productCode;
        @AuraEnabled public List<PricingRowWrapper> rows;
    }

    /**
     * @description Row wrapper for a meter type with OP4I checkboxes and price cells.
     */
    public class PricingRowWrapper {
        @AuraEnabled public String  meterType;
        @AuraEnabled public Boolean legalSales;
        @AuraEnabled public Boolean acSales;
        @AuraEnabled public Boolean fsSales;
        @AuraEnabled public Boolean corporateSales;
        @AuraEnabled public Boolean opsOnly;
        @AuraEnabled public List<PriceCellWrapper> cells;
    }

    /**
     * @description Cell wrapper for a single price in the matrix (currency x tier).
     */
    public class PriceCellWrapper {
        @AuraEnabled public String  currencyCode;
        @AuraEnabled public String  tier;
        @AuraEnabled public String  intappId;
        @AuraEnabled public String  blockId;
        @AuraEnabled public Decimal price;
    }

    // Quantity-based pricing wrapper classes

    /**
     * @description Result wrapper for getQuantityPricingData.
     */
    public class QuantityPricingResult {
        @AuraEnabled public String productCode;
        @AuraEnabled public List<QuantityMeterTypeGroup> meterTypes;
    }

    /**
     * @description Group of quantity bands for a single meter type.
     */
    public class QuantityMeterTypeGroup {
        @AuraEnabled public String meterType;
        @AuraEnabled public List<QuantityBandRow> bands;
    }

    /**
     * @description Row for a quantity band with price cells per currency.
     */
    public class QuantityBandRow {
        @AuraEnabled public Decimal lowerBound;
        @AuraEnabled public Decimal upperBound;
        @AuraEnabled public String  bandLabel;
        @AuraEnabled public List<QuantityPriceCell> cells;
    }

    /**
     * @description Cell wrapper for a single quantity-based price.
     */
    public class QuantityPriceCell {
        @AuraEnabled public String  currencyCode;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String  blockId;
    }
}