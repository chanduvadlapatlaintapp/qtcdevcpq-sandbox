/**
 * @description Controller for the New SKU Launch wizard in the SKU Management App.
 *              Provides validate + process methods for a 6-step wizard:
 *              Step 1 - Excel upload (client-side SheetJS parsing)
 *              Step 2 - SKU Details review
 *              Step 3 - Pricing review
 *              Step 4 - Bundles review
 *              Step 5 - Quote Terms review
 *              Step 6 - Launch & Results
 *
 *              The process method creates records sequentially across 10+ objects:
 *              Item_Master_Product__c -> Product2 -> PricebookEntry -> SBQQ__Dimension__c
 *              -> Block_Pricing__c (Meter Type + GTM Motion Tier) -> Intapp_Pricing__c
 *              -> Bundle placeholders + SBQQ__ProductOption__c
 *              -> SBQQ__QuoteTerm__c + SBQQ__TermCondition__c
 *
 * @author  Claude Code
 * @date    2026-03-02
 */
public with sharing class SkuNewLaunchController {

    // =========================================================================
    // Constants
    // =========================================================================

    private static final List<String> CURRENCIES = new List<String>{'USD', 'GBP', 'EUR', 'AUD'};
    private static final List<String> TIERS      = new List<String>{'EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'};

    /** Captures the real error message before AuraHandledException sanitizes it — readable in test assertions. */
    @TestVisible private static String lastTestDiagnostic = '';
    private static final String NONE_TIER_INTAPP  = 'Tier (none)';
    private static final String TIER_BASED        = 'Tier based';

    private static final Set<String> DIMENSION_PRODUCT_TYPES = new Set<String>{
        'Software', 'Support', 'Maintenance'
    };

    private static final Set<String> VALID_CURRENCIES = new Set<String>{'USD', 'GBP', 'EUR', 'AUD'};
    private static final Set<String> VALID_TIERS      = new Set<String>{'EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'};

    private static final String LAWYERS_FEE_EARNERS      = 'Lawyers/Fee Earners';
    private static final String LAWYERS_METER_TYPE        = 'Lawyers';
    private static final String FEE_EARNERS_METER_TYPE    = 'Fee Earners';
    private static final Set<String> LAWYERS_CURRENCIES   = new Set<String>{'USD', 'AUD'};
    private static final Set<String> FEE_EARNERS_CURRENCIES = new Set<String>{'EUR', 'GBP'};

    // =========================================================================
    // Public Methods — Product Line & Product Rollup Resolution
    // =========================================================================

    /**
     * @description Checks which Product Lines and Product Rollups from the parsed data
     *              already exist in the org. Returns lists of missing names so the LWC
     *              can prompt the user to create them.
     * @param productLineNames List of Product Line names from the Excel upload
     * @param productRollupNames List of Product Rollup names from the Excel upload
     * @return Map with missingProductLines, missingProductRollups, and existingProductLines
     */
    @AuraEnabled
    public static Map<String, Object> checkProductLineAndRollup(
        List<String> productLineNames, List<String> productRollupNames
    ) {
        Map<String, Object> result = new Map<String, Object>();

        // Check Product Lines
        Set<String> existingPLNames = new Set<String>();
        List<Map<String, String>> existingPLList = new List<Map<String, String>>();
        if (productLineNames != null && !productLineNames.isEmpty()) {
            for (Product_Line__c pl : [
                SELECT Id, Name FROM Product_Line__c WHERE Name IN :productLineNames
            ]) {
                existingPLNames.add(pl.Name);
            }
        }

        // Also get ALL active Product Lines for the dropdown
        for (Product_Line__c pl : [
            SELECT Id, Name FROM Product_Line__c WHERE Active__c = true ORDER BY Name
        ]) {
            existingPLList.add(new Map<String, String>{ 'name' => pl.Name, 'id' => pl.Id });
            existingPLNames.add(pl.Name); // Ensure the full set is captured
        }

        List<String> missingPLs = new List<String>();
        if (productLineNames != null) {
            for (String name : productLineNames) {
                if (!existingPLNames.contains(name)) {
                    missingPLs.add(name);
                }
            }
        }

        // Check Product Rollups
        Set<String> existingPRNames = new Set<String>();
        if (productRollupNames != null && !productRollupNames.isEmpty()) {
            for (Product_Rollup__c pr : [
                SELECT Id, Name FROM Product_Rollup__c WHERE Name IN :productRollupNames
            ]) {
                existingPRNames.add(pr.Name);
            }
        }

        List<String> missingPRs = new List<String>();
        if (productRollupNames != null) {
            for (String name : productRollupNames) {
                if (!existingPRNames.contains(name)) {
                    missingPRs.add(name);
                }
            }
        }

        result.put('missingProductLines', missingPLs);
        result.put('missingProductRollups', missingPRs);
        result.put('existingProductLines', existingPLList);

        return result;
    }

    /**
     * @description Creates a new Product_Line__c record with the given attributes.
     *              Sets Active__c = true and populates GearsetExternalId__c after insert.
     * @param name Product Line name
     * @param productFamily Simple_Product_Line__c picklist value
     * @param deployment Deployment__c picklist value
     * @param businessUnit Practice__c picklist value
     * @param impPrefix IMP_prefix__c text value
     * @param cloudAddendumRequired Cloud_Addendum_Required__c boolean
     * @return The Id of the created Product Line
     */
    @AuraEnabled
    public static Id createProductLineRecord(
        String name, String productFamily, String deployment,
        String businessUnit, String impPrefix, Boolean cloudAddendumRequired
    ) {
        try {
            Product_Line__c pl = new Product_Line__c();
            pl.Name = name;
            pl.Active__c = true;
            if (String.isNotBlank(productFamily))  pl.Simple_Product_Line__c = productFamily;
            if (String.isNotBlank(deployment))      pl.Deployment__c = deployment;
            if (String.isNotBlank(businessUnit))    pl.Practice__c = businessUnit;
            if (String.isNotBlank(impPrefix))       pl.IMP_prefix__c = impPrefix;
            pl.Cloud_Addendum_Required__c = (cloudAddendumRequired == true);

            insert pl;

            // Update GearsetExternalId (reversed to match Gearset convention)
            pl.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(pl.Id);
            update pl;
            StagingCaptureService.capture(new List<Product_Line__c>{ pl }, 'Product_Line__c', 'Create');

            Nebula.Logger.info('Created Product Line: ' + name + ' (Id: ' + pl.Id + ')')
                .addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();

            return pl.Id;

        } catch (Exception e) {
            Nebula.Logger.error('Failed to create Product Line "' + name + '": ' + e.getMessage())
                .addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Creates a new Product_Rollup__c record linked to a Product Line.
     *              Populates GearsetExternalId__c after insert.
     * @param name Product Rollup name
     * @param productLineName Name of the Product Line to link to
     * @return The Id of the created Product Rollup
     */
    @AuraEnabled
    public static Id createProductRollupRecord(String name, String productLineName) {
        try {
            // Look up the Product Line by name
            List<Product_Line__c> pls = [
                SELECT Id FROM Product_Line__c WHERE Name = :productLineName LIMIT 1
            ];
            if (pls.isEmpty()) {
                throw new AuraHandledException(
                    'Product Line "' + productLineName + '" not found. Please create it first.'
                );
            }

            Product_Rollup__c pr = new Product_Rollup__c();
            pr.Name = name;
            pr.Product_Line__c = pls[0].Id;

            insert pr;

            // Update GearsetExternalId (reversed to match Gearset convention)
            pr.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(pr.Id);
            update pr;
            StagingCaptureService.capture(new List<Product_Rollup__c>{ pr }, 'Product_Rollup__c', 'Create');

            Nebula.Logger.info('Created Product Rollup: ' + name + ' (Id: ' + pr.Id + ')')
                .addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();

            return pr.Id;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('Failed to create Product Rollup "' + name + '": ' + e.getMessage())
                .addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Public Methods — Product Code Auto-Generation
    // =========================================================================

    /**
     * @description For any SkuDetailRow with a blank productCode, generates a product code
     *              using the standard 'PIN-' prefix and the next incremental number after
     *              the last created Item_Master_Product__c. Format: PIN-{5-digit number}
     *              e.g., after "PIN-02135" the next generated code is "PIN-02136".
     *              If multiple rows need codes they are assigned sequentially.
     *              The prefix is always 'PIN-' regardless of the Product Line.
     * @param skuDetailsJson JSON string of List<SkuDetailRow>
     * @return Map with: updatedSkuDetails (List), generatedCount (Integer),
     *         generatedCodes (List of {productName, generatedCode} maps)
     */
    @AuraEnabled
    public static Map<String, Object> generateMissingProductCodes(String skuDetailsJson) {
        try {
            List<SkuDetailRow> skuDetails = (List<SkuDetailRow>) JSON.deserialize(
                skuDetailsJson, List<SkuDetailRow>.class
            );

            // Identify rows with blank product codes
            List<Integer> missingIndices = new List<Integer>();
            for (Integer i = 0; i < skuDetails.size(); i++) {
                if (String.isBlank(skuDetails[i].productCode)) {
                    missingIndices.add(i);
                }
            }

            if (missingIndices.isEmpty()) {
                return new Map<String, Object>{
                    'updatedSkuDetails' => skuDetails,
                    'generatedCount'    => 0,
                    'generatedCodes'    => new List<Map<String, String>>()
                };
            }

            // Determine the starting number from the last created Item Master Product.
            // Names follow the pattern PIN-{digits} (e.g., PIN-02135).
            // Extract the numeric suffix and increment from there.
            Integer lastNumber = 0;
            List<Item_Master_Product__c> lastImp = [
                SELECT Name FROM Item_Master_Product__c
                WHERE Name LIKE 'PIN-%'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!lastImp.isEmpty()) {
                String numPart = lastImp[0].Name.substringAfterLast('-');
                if (String.isNotBlank(numPart) && numPart.isNumeric()) {
                    lastNumber = Integer.valueOf(numPart);
                }
            }

            // Build a map of product line name → IMP prefix for display purposes
            Set<String> productLineNames = new Set<String>();
            for (Integer idx : missingIndices) {
                if (String.isNotBlank(skuDetails[idx].productLine)) {
                    productLineNames.add(skuDetails[idx].productLine);
                }
            }
            Map<String, String> plImpPrefixMap = new Map<String, String>();
            if (!productLineNames.isEmpty()) {
                for (Product_Line__c pl : [SELECT Name, IMP_prefix__c FROM Product_Line__c WHERE Name IN :productLineNames]) {
                    plImpPrefixMap.put(pl.Name, String.isNotBlank(pl.IMP_prefix__c) ? pl.IMP_prefix__c : 'GE');
                }
            }

            // Generate codes sequentially for each row missing a product code
            Integer nextNumber = lastNumber + 1;
            List<Map<String, String>> generatedCodes = new List<Map<String, String>>();
            for (Integer idx : missingIndices) {
                SkuDetailRow row = skuDetails[idx];
                String paddedNum = String.valueOf(nextNumber).leftPad(5, '0');
                String generatedCode = 'PIN-' + paddedNum;
                // Derive the IMP code using the product line prefix (e.g., CO-02136)
                String impPrefix = plImpPrefixMap.containsKey(row.productLine)
                    ? plImpPrefixMap.get(row.productLine) : 'GE';
                String impCode = impPrefix + '-' + paddedNum;
                // productCode = IMP code (display + all SF records except im.Name)
                // pinCode = PIN code (used only for im.Name on Item_Master_Product__c)
                row.productCode = impCode;
                row.pinCode = generatedCode;
                generatedCodes.add(new Map<String, String>{
                    'productName'   => row.productName,
                    'generatedCode' => generatedCode,
                    'impCode'       => impCode
                });
                nextNumber++;
            }

            Nebula.Logger.info('Auto-generated ' + missingIndices.size() + ' product code(s) for rows missing a Product Code / Item Master Number.')
                .addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();

            return new Map<String, Object>{
                'updatedSkuDetails' => skuDetails,
                'generatedCount'    => missingIndices.size(),
                'generatedCodes'    => generatedCodes
            };

        } catch (Exception e) {
            Nebula.Logger.error('generateMissingProductCodes failed: ' + e.getMessage())
                .addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Public Methods — Validation
    // =========================================================================

    /**
     * @description Validates the parsed Excel data before processing. Checks required fields,
     *              duplicate product codes, cross-tab consistency, and governor limit guards.
     * @param skuDetailsJson JSON string of List<SkuDetailRow> from SKU Details tab
     * @param pricingJson JSON string of List<PricingRow> from Pricing tab
     * @param bundlesJson JSON string of List<BundleRow> from Bundles tab (nullable)
     * @param quoteTermsJson JSON string of List<QuoteTermRow> from Quote Terms tab (nullable)
     * @return ValidationResult with errors, warnings, and record counts
     */
    @AuraEnabled
    public static ValidationResult validateNewSkuLaunch(
        String skuDetailsJson, String pricingJson, String bundlesJson, String quoteTermsJson
    ) {
        try {
            ValidationResult result = new ValidationResult();
            result.isValid = true;
            result.errors = new List<String>();
            result.warnings = new List<String>();

            // Deserialize payloads
            List<SkuDetailRow> skuDetails = (List<SkuDetailRow>) JSON.deserialize(
                skuDetailsJson, List<SkuDetailRow>.class
            );
            List<PricingRow> pricingRows = (List<PricingRow>) JSON.deserialize(
                pricingJson, List<PricingRow>.class
            );
            List<BundleRow> bundleRows = String.isNotBlank(bundlesJson)
                ? (List<BundleRow>) JSON.deserialize(bundlesJson, List<BundleRow>.class)
                : new List<BundleRow>();

            result.skuCount = skuDetails.size();
            result.pricingRowCount = pricingRows.size();
            result.bundleCount = bundleRows.size();

            if (skuDetails.isEmpty()) {
                result.isValid = false;
                result.errors.add('No SKU Detail rows found. At least one product is required.');
                return result;
            }

            // ----- Validate SKU Details -----
            Set<String> productCodes = new Set<String>();
            for (Integer i = 0; i < skuDetails.size(); i++) {
                SkuDetailRow row = skuDetails[i];
                Integer rowNum = i + 1;

                if (String.isBlank(row.productCode)) {
                    result.errors.add('SKU row ' + rowNum + ': Product Code is required.');
                    result.isValid = false;
                } else if (productCodes.contains(row.productCode)) {
                    result.errors.add('SKU row ' + rowNum + ': Duplicate Product Code "' + row.productCode + '".');
                    result.isValid = false;
                } else {
                    productCodes.add(row.productCode);
                }

                if (String.isBlank(row.productName)) {
                    result.errors.add('SKU row ' + rowNum + ': Product Name is required.');
                    result.isValid = false;
                }

                if (String.isBlank(row.revenueType)) {
                    result.warnings.add('SKU row ' + rowNum + ': Revenue Type is empty.');
                }

                if (String.isBlank(row.productType)) {
                    result.warnings.add('SKU row ' + rowNum + ': Product Type is empty.');
                }

                if (result.errors.size() >= 30) {
                    result.errors.add('Too many errors. Showing first 30 only.');
                    break;
                }
            }

            // Check for existing product codes in org (Item Master Name uniqueness)
            if (!productCodes.isEmpty()) {
                List<Item_Master_Product__c> existing = [
                    SELECT Name FROM Item_Master_Product__c WHERE Name IN :productCodes
                ];
                for (Item_Master_Product__c im : existing) {
                    result.errors.add('Product Code "' + im.Name + '" already exists in the org.');
                    result.isValid = false;
                }
            }

            // Build name → productCode maps for resolving placeholder product codes server-side.
            // itemMasterName is the shared key across tabs (Pricing/QuoteTerms store it as productName).
            // productName is a fallback for questionnaires that omit the Item Master Name column.
            Map<String, String> validateByItemMasterName = new Map<String, String>();
            Map<String, String> validateByProductName    = new Map<String, String>();
            for (SkuDetailRow sd : skuDetails) {
                if (String.isNotBlank(sd.productCode)) {
                    if (String.isNotBlank(sd.itemMasterName)) {
                        validateByItemMasterName.put(sd.itemMasterName.toLowerCase(), sd.productCode);
                    }
                    if (String.isNotBlank(sd.productName)) {
                        validateByProductName.put(sd.productName.toLowerCase(), sd.productCode);
                    }
                }
            }

            // ----- Validate Pricing (cross-tab) -----
            for (Integer i = 0; i < pricingRows.size(); i++) {
                PricingRow row = pricingRows[i];
                Integer rowNum = i + 1;

                // Resolve placeholder product codes ("leave blank, system created.") by name.
                // The Pricing tab's productName comes from "Item Master Name" — use that first.
                String effectivePricingCode = row.productCode;
                if (String.isBlank(effectivePricingCode) || effectivePricingCode.containsIgnoreCase('leave blank')) {
                    String lookupName = String.isNotBlank(row.productName) ? row.productName.toLowerCase() : '';
                    effectivePricingCode = validateByItemMasterName.get(lookupName);
                    if (String.isBlank(effectivePricingCode)) {
                        effectivePricingCode = validateByProductName.get(lookupName);
                    }
                }

                if (String.isBlank(effectivePricingCode)) {
                    result.errors.add('Pricing row ' + rowNum + ': Product Code is required.');
                    result.isValid = false;
                } else if (!productCodes.contains(effectivePricingCode)) {
                    result.errors.add('Pricing row ' + rowNum + ': Product Code "' + effectivePricingCode + '" not found in SKU Details tab.');
                    result.isValid = false;
                }

                if (String.isBlank(row.meterType)) {
                    result.errors.add('Pricing row ' + rowNum + ': Meter Type is required.');
                    result.isValid = false;
                }

                // Validate individual price entries
                if (row.prices != null) {
                    for (PriceEntry pe : row.prices) {
                        if (pe.price != null && pe.price < 0) {
                            result.warnings.add('Pricing row ' + rowNum + ': Negative price ' + pe.price +
                                ' for ' + pe.currencyCode + '/' + pe.tier + '.');
                        }
                        if (String.isNotBlank(pe.currencyCode) && !VALID_CURRENCIES.contains(pe.currencyCode)) {
                            result.errors.add('Pricing row ' + rowNum + ': Invalid currency "' + pe.currencyCode + '".');
                            result.isValid = false;
                        }
                        if (String.isNotBlank(pe.tier) && !VALID_TIERS.contains(pe.tier)) {
                            result.errors.add('Pricing row ' + rowNum + ': Invalid tier "' + pe.tier + '".');
                            result.isValid = false;
                        }
                    }
                }

                if (result.errors.size() >= 30) {
                    result.errors.add('Too many errors. Showing first 30 only.');
                    break;
                }
            }

            // ----- Validate Bundles -----
            if (!bundleRows.isEmpty()) {
                // Check ACV percentage sums per parent
                Map<String, Decimal> componentAcvTotals = new Map<String, Decimal>();
                for (BundleRow br : bundleRows) {
                    if (br.role != 'BUNDLE' && String.isNotBlank(br.parentProductCode)) {
                        Decimal total = componentAcvTotals.containsKey(br.parentProductCode)
                            ? componentAcvTotals.get(br.parentProductCode) : 0;
                        total += (br.acvPercent != null ? br.acvPercent : 0);
                        componentAcvTotals.put(br.parentProductCode, total);
                    }
                }

                for (String parentCode : componentAcvTotals.keySet()) {
                    Decimal total = componentAcvTotals.get(parentCode);
                    // Accept both 0-1 scale and 0-100 scale
                    if (total != 1.0 && total != 100 && Math.abs(total - 1.0) > 0.01 && Math.abs(total - 100) > 1) {
                        result.warnings.add('Bundle "' + parentCode + '": Component ACV% sums to ' +
                            total + ' (expected 1.0 or 100).');
                    }
                }
            }

            // ----- Validate Quote Terms -----
            List<QuoteTermRow> quoteTermRows = String.isNotBlank(quoteTermsJson)
                ? (List<QuoteTermRow>) JSON.deserialize(quoteTermsJson, List<QuoteTermRow>.class)
                : new List<QuoteTermRow>();
            result.quoteTermCount = quoteTermRows.size();

            // Build productName -> productCode map so quote term rows with blank/placeholder
            // product codes (e.g. "leave blank, system created.") can be resolved by name.
            Map<String, String> qtValidateNameToCode = new Map<String, String>();
            for (SkuDetailRow sd : skuDetails) {
                if (String.isNotBlank(sd.productName) && String.isNotBlank(sd.productCode)) {
                    qtValidateNameToCode.put(sd.productName, sd.productCode);
                }
            }

            for (Integer i = 0; i < quoteTermRows.size(); i++) {
                QuoteTermRow row = quoteTermRows[i];
                Integer rowNum = i + 1;

                String resolvedQtCode = row.productCode;
                if (String.isBlank(resolvedQtCode) || resolvedQtCode.containsIgnoreCase('leave blank')) {
                    resolvedQtCode = qtValidateNameToCode.get(row.productName);
                }

                if (String.isBlank(resolvedQtCode)) {
                    result.errors.add('Quote Term row ' + rowNum + ': Product Code is missing and could not be resolved from Product Name "' + row.productName + '".');
                    result.isValid = false;
                } else if (!productCodes.contains(resolvedQtCode)) {
                    result.errors.add('Quote Term row ' + rowNum + ': Product Code "' + resolvedQtCode + '" not found in SKU Details tab.');
                    result.isValid = false;
                }

                if (String.isBlank(row.body)) {
                    result.errors.add('Quote Term row ' + rowNum + ': Quote term body text is required.');
                    result.isValid = false;
                }

                if (result.errors.size() >= 30) {
                    result.errors.add('Too many errors. Showing first 30 only.');
                    break;
                }
            }

            // ----- Governor limit guard -----
            Integer estimatedRecords = skuDetails.size() * 2; // IM + Product2
            estimatedRecords += skuDetails.size() * 8;        // PBEs (4 currencies × 2 pricebooks)
            estimatedRecords += skuDetails.size() * 4;        // Dimensions (worst case)
            for (PricingRow pr : pricingRows) {
                if (pr.prices != null) {
                    estimatedRecords += pr.prices.size() * 2; // Block_Pricing + Intapp_Pricing
                }
            }
            estimatedRecords += quoteTermRows.size() * 3;     // QuoteTerm + 2 TermConditions each

            if (estimatedRecords > 8000) {
                result.isValid = false;
                result.errors.add('Estimated record count (' + estimatedRecords +
                    ') exceeds safe DML limits. Please reduce the number of products per upload.');
            }

            return result;

        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Public Methods — Processing
    // =========================================================================

    /**
     * @description Processes the validated data and creates all Salesforce records sequentially.
     *              Each step depends on prior steps (IDs from earlier inserts feed later records).
     *              Uses partial success (Database.insert(records, false)) for each DML batch.
     * @param skuDetailsJson JSON string of List<SkuDetailRow>
     * @param pricingJson JSON string of List<PricingRow>
     * @param bundlesJson JSON string of List<BundleRow> (nullable)
     * @param quoteTermsJson JSON string of List<QuoteTermRow> (nullable)
     * @return LaunchResult with per-step success/error counts
     */
    @AuraEnabled
    public static LaunchResult processNewSkuLaunch(
        String skuDetailsJson, String pricingJson, String bundlesJson, String quoteTermsJson
    ) {
        try {
            LaunchResult result = new LaunchResult();
            result.steps = new List<StepResult>();
            result.totalSuccess = 0;
            result.totalErrors = 0;
            result.createdProducts = new List<CreatedProduct>();

            // Deserialize payloads
            List<SkuDetailRow> skuDetails = (List<SkuDetailRow>) JSON.deserialize(
                skuDetailsJson, List<SkuDetailRow>.class
            );
            List<PricingRow> pricingRows = (List<PricingRow>) JSON.deserialize(
                pricingJson, List<PricingRow>.class
            );
            List<BundleRow> bundleRows = String.isNotBlank(bundlesJson)
                ? (List<BundleRow>) JSON.deserialize(bundlesJson, List<BundleRow>.class)
                : new List<BundleRow>();

            // Resolve any pricing rows whose productCode is still a placeholder
            // ("leave blank, system created.") — safety net in case the LWC propagation step
            // couldn't resolve the code (e.g. unusual questionnaire column layouts).
            // itemMasterName is the shared key: Pricing tab stores it as productName.
            Map<String, String> processByItemMasterName = new Map<String, String>();
            Map<String, String> processByProductName    = new Map<String, String>();
            for (SkuDetailRow sd : skuDetails) {
                if (String.isNotBlank(sd.productCode)) {
                    if (String.isNotBlank(sd.itemMasterName)) {
                        processByItemMasterName.put(sd.itemMasterName.toLowerCase(), sd.productCode);
                    }
                    if (String.isNotBlank(sd.productName)) {
                        processByProductName.put(sd.productName.toLowerCase(), sd.productCode);
                    }
                }
            }
            for (PricingRow pr : pricingRows) {
                if (String.isBlank(pr.productCode) || pr.productCode.containsIgnoreCase('leave blank')) {
                    if (String.isNotBlank(pr.productName)) {
                        String lookupName = pr.productName.toLowerCase();
                        String resolved = processByItemMasterName.get(lookupName);
                        if (String.isBlank(resolved)) {
                            resolved = processByProductName.get(lookupName);
                        }
                        if (String.isNotBlank(resolved)) {
                            pr.productCode = resolved;
                        }
                    }
                }
            }

            // Index pricing rows by product code
            Map<String, List<PricingRow>> pricingByProduct = new Map<String, List<PricingRow>>();
            for (PricingRow pr : pricingRows) {
                if (!pricingByProduct.containsKey(pr.productCode)) {
                    pricingByProduct.put(pr.productCode, new List<PricingRow>());
                }
                pricingByProduct.get(pr.productCode).add(pr);
            }

            // Resolve Product Line and Product Rollup names to Ids
            Set<String> productLineNames = new Set<String>();
            Set<String> productRollupNames = new Set<String>();
            for (SkuDetailRow row : skuDetails) {
                if (String.isNotBlank(row.productLine)) productLineNames.add(row.productLine);
                if (String.isNotBlank(row.productRollup)) productRollupNames.add(row.productRollup);
            }

            Map<String, Id> productLineMap = new Map<String, Id>();
            Map<String, String> productLineImpPrefixMap = new Map<String, String>();
            if (!productLineNames.isEmpty()) {
                for (Product_Line__c pl : [SELECT Id, Name, IMP_prefix__c FROM Product_Line__c WHERE Name IN :productLineNames]) {
                    productLineMap.put(pl.Name, pl.Id);
                    productLineImpPrefixMap.put(pl.Name, String.isNotBlank(pl.IMP_prefix__c) ? pl.IMP_prefix__c : 'GE');
                }
            }

            Map<String, Id> productRollupMap = new Map<String, Id>();
            if (!productRollupNames.isEmpty()) {
                for (Product_Rollup__c pr : [SELECT Id, Name FROM Product_Rollup__c WHERE Name IN :productRollupNames]) {
                    productRollupMap.put(pr.Name, pr.Id);
                }
            }

            // =====================================================================
            // STEP 1: Create Item_Master_Product__c records
            // =====================================================================

            // Build picklist label → API value map so users can enter labels in Excel
            Map<String, Map<String, String>> picklistLabelMap = getPicklistLabelToValueMap();

            List<Item_Master_Product__c> itemMasters = new List<Item_Master_Product__c>();

            for (SkuDetailRow row : skuDetails) {
                Item_Master_Product__c im = new Item_Master_Product__c();
                // Product Item Name (Name): use pinCode for auto-generated rows (PIN-02136),
                // fall back to productCode for user-provided codes
                im.Name = String.isNotBlank(row.pinCode) ? row.pinCode : row.productCode;
                // Intapp Item Master Number (Text) uses the product line's IMP prefix (e.g., CO-02136)
                String impPrefix = productLineImpPrefixMap.containsKey(row.productLine)
                    ? productLineImpPrefixMap.get(row.productLine) : 'GE';
                String impNumSuffix = row.productCode.contains('-')
                    ? row.productCode.substringAfterLast('-') : row.productCode;
                im.Intapp_Item_Master_Number_Text__c = impPrefix + '-' + impNumSuffix;
                im.Item_Name__c = row.productName;
                im.Description__c = row.description;
                im.Revenue_Type__c = resolvePicklistValue(picklistLabelMap, 'Revenue_Type__c', row.revenueType);
                im.Active__c = true;

                // Product Line lookup
                if (String.isNotBlank(row.productLine) && productLineMap.containsKey(row.productLine)) {
                    im.Product_LineNew__c = productLineMap.get(row.productLine);
                }

                // Bundle flag
                if (row.isBundle == true) {
                    im.Static_Bundle__c = true;
                }

                // NetSuite fields — resolve labels to API values via picklist describe
                if (String.isNotBlank(row.netsuiteIncomeAccount))            im.Income_Account__c = resolvePicklistValue(picklistLabelMap, 'Income_Account__c', row.netsuiteIncomeAccount);
                if (String.isNotBlank(row.netsuiteDeferredRevenueAccount))   im.Deferred_Revenue_Account__c = resolvePicklistValue(picklistLabelMap, 'Deferred_Revenue_Account__c', row.netsuiteDeferredRevenueAccount);
                if (String.isNotBlank(row.netsuiteItemRevenueCategory))      im.Item_Revenue_Category__c = resolvePicklistValue(picklistLabelMap, 'Item_Revenue_Category__c', row.netsuiteItemRevenueCategory);
                if (String.isNotBlank(row.netsuiteRevRecognitionRule))        im.Revenue_Recognition_Rule__c = resolvePicklistValue(picklistLabelMap, 'Revenue_Recognition_Rule__c', row.netsuiteRevRecognitionRule);
                if (String.isNotBlank(row.netsuiteRevRecForecastRule))        im.Rev_Rec_Forecast_Rule__c = resolvePicklistValue(picklistLabelMap, 'Rev_Rec_Forecast_Rule__c', row.netsuiteRevRecForecastRule);
                if (String.isNotBlank(row.netsuiteRevenueAllocationGroup))   im.Revenue_Allocation_Group__c = resolvePicklistValue(picklistLabelMap, 'Revenue_Allocation_Group__c', row.netsuiteRevenueAllocationGroup);
                if (String.isNotBlank(row.netsuiteCreateRevenuePlansOn))     im.Create_Revenue_Plans_On__c = resolvePicklistValue(picklistLabelMap, 'Create_Revenue_Plans_On__c', row.netsuiteCreateRevenuePlansOn);
                if (String.isNotBlank(row.netsuiteItemTypeForInvoicing))     im.NetSuite_Item_Type_For_Invoicing__c = resolvePicklistValue(picklistLabelMap, 'NetSuite_Item_Type_For_Invoicing__c', row.netsuiteItemTypeForInvoicing);
                if (String.isNotBlank(row.netsuiteRevRecTemplate))           im.NetSuite_Revenue_Recognition_Template__c = resolvePicklistValue(picklistLabelMap, 'NetSuite_Revenue_Recognition_Template__c', row.netsuiteRevRecTemplate);
                if (row.netsuiteIncludeChildren != null)                        im.NetSuite_Include_Children__c = row.netsuiteIncludeChildren;
                if (String.isNotBlank(row.openAirBillingRule))               im.OpenAir_Billing_Rule__c = resolvePicklistValue(picklistLabelMap, 'OpenAir_Billing_Rule__c', row.openAirBillingRule);
                if (row.netsuiteExportToOpenAir != null)                     im.NetSuite_Export_to_OpenAir__c = row.netsuiteExportToOpenAir;
                if (String.isNotBlank(row.avalaraTaxCode))                   im.TaxCode__c = resolvePicklistValue(picklistLabelMap, 'TaxCode__c', row.avalaraTaxCode);
                if (String.isNotBlank(row.netsuiteTaxSchedule))              im.NetSuite_Tax_Schedule__c = resolvePicklistValue(picklistLabelMap, 'NetSuite_Tax_Schedule__c', row.netsuiteTaxSchedule);
                if (row.triggerToNetsuite != null)                        im.Trigger_to_NS__c = row.triggerToNetsuite;
                // FY26 questionnaire additions
                if (String.isNotBlank(row.netsuiteType))                 im.NetSuite_Type__c = resolvePicklistValue(picklistLabelMap, 'NetSuite_Type__c', row.netsuiteType);
                if (String.isNotBlank(row.netsuiteSubType))              im.NetSuite_SubType__c = resolvePicklistValue(picklistLabelMap, 'NetSuite_SubType__c', row.netsuiteSubType);
                if (row.netsuiteCanBeFulfilled != null)                  im.NetSuite_Can_be_fulfilled__c = row.netsuiteCanBeFulfilled;
                if (String.isNotBlank(row.netsuiteBillingSchedule))      im.NetSuite_Billing_Schedule__c = resolvePicklistValue(picklistLabelMap, 'NetSuite_Billing_Schedule__c', row.netsuiteBillingSchedule);
                if (row.netsuiteDirectRevenuePosting != null)            im.NetSuite_Direct_Revenue_Posting__c = row.netsuiteDirectRevenuePosting;
                if (String.isNotBlank(row.netsuiteAllocationType))       im.NetSuite_Allocation_Type__c = resolvePicklistValue(picklistLabelMap, 'NetSuite_Allocation_Type__c', row.netsuiteAllocationType);
                if (row.syncNetsuite != null)                            im.Sync_NetSuite__c = row.syncNetsuite;
                if (row.exemptFromMagicScript != null)               im.Exempt_from_Magic_Script__c = row.exemptFromMagicScript;

                itemMasters.add(im);
            }

            StepResult imStep = performPartialInsert(itemMasters, 'Item_Master_Product__c');
            result.steps.add(imStep);
            result.totalSuccess += imStep.successCount;
            result.totalErrors += imStep.errorCount;

            // Abort early if IMP creation failed — no point continuing
            if (imStep.errorCount > 0) {
                List<String> allErrors = new List<String>();
                for (StepResult s : result.steps) { allErrors.addAll(s.errors); }
                String imAbortMsg = 'Launch aborted: ' + imStep.errorCount + ' Item Master error(s). No records were created.\n' +
                    String.join(allErrors, '\n');
                if (Test.isRunningTest()) { lastTestDiagnostic = '[IM_ABORT] ' + imAbortMsg; }
                throw new AuraHandledException(imAbortMsg);
            }


            // =====================================================================
            // STEP 2: Create Product2 records (linked to Item Masters)
            // =====================================================================

            List<Product2> productsToInsert = new List<Product2>();
            List<Integer> productToSkuIndex = new List<Integer>(); // tracks which skuDetails row each product maps to

            for (Integer i = 0; i < skuDetails.size(); i++) {
                SkuDetailRow row = skuDetails[i];
                Item_Master_Product__c im = itemMasters[i];

                // Skip if Item Master insert failed
                if (im.Id == null) continue;

                Product2 p = new Product2();
                p.Name = row.productName;
                p.ProductCode = row.productCode;
                p.Description = row.description;
                p.IsActive = true;
                p.Item_Master_Product__c = im.Id;

                // Lookups
                if (String.isNotBlank(row.productLine) && productLineMap.containsKey(row.productLine)) {
                    p.Product_LineNew__c = productLineMap.get(row.productLine);
                }
                if (String.isNotBlank(row.productRollup) && productRollupMap.containsKey(row.productRollup)) {
                    p.ProductRollup__c = productRollupMap.get(row.productRollup);
                }

                // Core fields
                p.Product_Group__c = row.productGroup;
                p.Product_Type__c = row.productType;
                p.Includes_Assist__c = (row.includesAssist == true);
                p.Eligible_For_Premium__c = (row.eligibleForPremium == true);
                p.Pricing_Basis__c = row.pricingBasis;
                p.Services_Product_Type__c = row.servicesProductType;
                p.Product_License_Type__c = row.softwareLicenseTerm;
                p.SBQQ__SubscriptionType__c = row.subscriptionType;
                p.Revenue_Type__c = row.revenueType;
                p.Line_of_Business_Product__c = row.lineOfBusinessProduct;

                // Percentage of ACV — normalise 0–1 scale (e.g. 0.32) to 0–100 (e.g. 32)
                if (row.percentageOfAcv != null) {
                    p.Percentage_of_ACV__c = row.percentageOfAcv <= 1
                        ? row.percentageOfAcv * 100
                        : row.percentageOfAcv;
                }

                // Subscription Pricing (default to Fixed Price for non-discount types)
                p.SBQQ__SubscriptionPricing__c = String.isNotBlank(row.subscriptionPricing)
                    ? row.subscriptionPricing : 'Fixed Price';

                // Sub-vertical picklist fields (Active / Restricted / Unavailable)
                p.Is_Legal__c = row.isLegal;
                p.Is_Accounting__c = row.isAccounting;
                p.Is_Consulting__c = row.isConsulting;
                p.Is_IBA__c = row.isIBA;
                p.Is_PCM__c = row.isPCM;
                p.Is_Real_Assets__c = row.isRealAssets;
                p.Iss_Corporate__c = row.isCorporate;

                // Tax code
                if (String.isNotBlank(row.avalaraTaxCode)) {
                    p.AVA_SFCPQ__TaxCode__c = row.avalaraTaxCode;
                    p.SBQQ__TaxCode__c = row.avalaraTaxCode;
                }

                // --- Derived CPQ fields ---

                // Default Pricing Table
                if (row.productType == 'Software') {
                    p.SBQQ__DefaultPricingTable__c = 'Segmented';
                } else {
                    p.SBQQ__DefaultPricingTable__c = 'Standard';
                }

                // Price Editable (Services, or Quantity-based / Other-Mixed software)
                if (row.productType == 'Services' ||
                    row.pricingBasis == 'Quantity based' ||
                    row.pricingBasis == 'Other/Mixed') {
                    p.SBQQ__PriceEditable__c = true;
                }

                // Charge Type / Billing Type / Subscription Term from Revenue Type
                if (row.revenueType == 'Recurring') {
                    p.SBQQ__ChargeType__c = 'Recurring';
                    p.SBQQ__BillingType__c = 'Advance';
                    p.SBQQ__SubscriptionTerm__c = 1;
                } else if (row.revenueType == 'One-time') {
                    p.SBQQ__ChargeType__c = 'One-Time';
                }

                // Guided Selling Type: 'Services' for Services/Services Discount, 'Software' for all others
                if (row.productType == 'Services' || row.productType == 'Services Discount') {
                    p.Guided_Selling_Type__c = 'Services';
                } else {
                    p.Guided_Selling_Type__c = 'Software';
                }

                // Bundle flags
                if (row.isBundle == true) {
                    p.SBQQ__Component__c = true;
                    p.Bundle_Product__c = true;
                }

                productsToInsert.add(p);
                productToSkuIndex.add(i);
            }

            StepResult prodStep = performPartialInsert(productsToInsert, 'Product2');
            result.steps.add(prodStep);
            result.totalSuccess += prodStep.successCount;
            result.totalErrors += prodStep.errorCount;

            // =====================================================================
            // STEP 3: GearsetExternalId__c on Item Masters and Products
            // =====================================================================

            List<SObject> gearsetUpdates = new List<SObject>();
            for (Item_Master_Product__c im : itemMasters) {
                if (im.Id != null) {
                    gearsetUpdates.add(new Item_Master_Product__c(
                        Id = im.Id,
                        GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(im.Id)
                    ));
                }
            }
            for (Product2 p : productsToInsert) {
                if (p.Id != null) {
                    gearsetUpdates.add(new Product2(
                        Id = p.Id,
                        GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(p.Id)
                    ));
                }
            }
            if (!gearsetUpdates.isEmpty()) {
                Database.update(gearsetUpdates, false);
            }

            // Sync GearsetExternalId onto in-memory lists (gearsetUpdates used new SObject instances)
            // then capture Item Masters and Products created in this launch
            for (Item_Master_Product__c im : itemMasters) {
                if (im.Id != null) im.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(im.Id);
            }
            for (Product2 p : productsToInsert) {
                if (p.Id != null) p.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(p.Id);
            }
            StagingCaptureService.capture(itemMasters, 'Item_Master_Product__c', 'Create');
            StagingCaptureService.capture(productsToInsert, 'Product2', 'Create');

            // Build productCode -> Product2 map (only successful inserts)
            Map<String, Product2> productByCode = new Map<String, Product2>();
            for (Integer j = 0; j < productsToInsert.size(); j++) {
                Product2 p = productsToInsert[j];
                if (p.Id != null) {
                    Integer skuIdx = productToSkuIndex[j];
                    productByCode.put(skuDetails[skuIdx].productCode, p);
                }
            }

            // Populate createdProducts for post-launch navigation
            for (String code : productByCode.keySet()) {
                Product2 p = productByCode.get(code);
                CreatedProduct cp = new CreatedProduct();
                cp.productId = p.Id;
                cp.productCode = p.ProductCode;
                cp.productName = p.Name;
                result.createdProducts.add(cp);
            }

            // Build productCode -> SkuDetailRow map
            Map<String, SkuDetailRow> detailByCode = new Map<String, SkuDetailRow>();
            for (SkuDetailRow row : skuDetails) {
                detailByCode.put(row.productCode, row);
            }

            // =====================================================================
            // STEP 4: PricebookEntry records (Standard PB first, then Custom PB)
            // =====================================================================

            // Resolve pricebook from first SKU detail row (all rows share the same pricebook)
            String sfdcPricebookName = skuDetails[0].sfdcPricebook;
            String fiscalYear = '';

            // Standard Pricebook — query normally; fall back to Test.getStandardPricebookId()
            // when running tests because Salesforce hides the standard pricebook from SOQL
            // in test context, causing the standard PBE insert to be skipped and all
            // subsequent custom PBEs to fail with "Before creating a custom price, create a
            // standard price."
            Id standardPbId;
            List<Pricebook2> standardPbs = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            if (!standardPbs.isEmpty()) {
                standardPbId = standardPbs[0].Id;
            } else if (Test.isRunningTest()) {
                standardPbId = Test.getStandardPricebookId();
            }

            Id customPbId = null;
            if (String.isNotBlank(sfdcPricebookName)) {
                // Try exact name match first
                List<Pricebook2> customPbs = [
                    SELECT Id, Name FROM Pricebook2
                    WHERE Name = :sfdcPricebookName AND IsActive = true
                    LIMIT 1
                ];

                // If not found, try replacing spaces ↔ underscores (common mismatch)
                if (customPbs.isEmpty()) {
                    String altName = sfdcPricebookName.contains('_')
                        ? sfdcPricebookName.replace('_', ' ')
                        : sfdcPricebookName.replace(' ', '_');
                    customPbs = [
                        SELECT Id, Name FROM Pricebook2
                        WHERE Name = :altName AND IsActive = true
                        LIMIT 1
                    ];
                    if (!customPbs.isEmpty()) {
                        Nebula.Logger.info('Pricebook matched with alternate name "' + altName +
                            '" (original: "' + sfdcPricebookName + '")').addTag('SkuNewLaunch');
                    }
                }

                if (!customPbs.isEmpty()) {
                    customPbId = customPbs[0].Id;
                    fiscalYear = extractFiscalYearCode(customPbs[0].Name);
                } else {
                    Nebula.Logger.warn('Pricebook "' + sfdcPricebookName +
                        '" not found. Intapp Pricing records will not have a Price Book assigned.')
                        .addTag('SkuNewLaunch');
                }
            }

            // Resolve which currencies are active in this org.
            // Single-currency orgs can only use the org default (typically USD);
            // attempting to insert records with other CurrencyIsoCodes would cause DML
            // errors that roll back the entire launch.
            List<String> effectiveCurrencies = getEffectiveCurrencies();
            Set<String> effectiveCurrencySet = new Set<String>(effectiveCurrencies);

            // Standard PBEs (must exist before custom PBEs)
            if (standardPbId != null) {
                List<PricebookEntry> stdPbeList = new List<PricebookEntry>();
                for (String code : productByCode.keySet()) {
                    Product2 p = productByCode.get(code);
                    for (String curr : effectiveCurrencies) {
                        stdPbeList.add(new PricebookEntry(
                            Pricebook2Id = standardPbId,
                            Product2Id = p.Id,
                            CurrencyIsoCode = curr,
                            UnitPrice = 0,
                            IsActive = true
                        ));
                    }
                }

                StepResult stdPbeStep = performPartialInsert(stdPbeList, 'PricebookEntry (Standard)');
                result.steps.add(stdPbeStep);
                result.totalSuccess += stdPbeStep.successCount;
                result.totalErrors += stdPbeStep.errorCount;
                populateGearsetExternalIds(stdPbeList);
                for (PricebookEntry pbe : stdPbeList) {
                    if (pbe.Id != null) pbe.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(pbe.Id);
                }
                StagingCaptureService.capture(stdPbeList, 'PricebookEntry', 'Create');
            }

            // Custom PBEs
            if (customPbId != null) {
                List<PricebookEntry> customPbeList = new List<PricebookEntry>();
                for (String code : productByCode.keySet()) {
                    Product2 p = productByCode.get(code);
                    for (String curr : effectiveCurrencies) {
                        customPbeList.add(new PricebookEntry(
                            Pricebook2Id = customPbId,
                            Product2Id = p.Id,
                            CurrencyIsoCode = curr,
                            UnitPrice = 0,
                            IsActive = true
                        ));
                    }
                }

                StepResult customPbeStep = performPartialInsert(customPbeList, 'PricebookEntry (Custom)');
                result.steps.add(customPbeStep);
                result.totalSuccess += customPbeStep.successCount;
                result.totalErrors += customPbeStep.errorCount;
                populateGearsetExternalIds(customPbeList);
                for (PricebookEntry pbe : customPbeList) {
                    if (pbe.Id != null) pbe.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(pbe.Id);
                }
                StagingCaptureService.capture(customPbeList, 'PricebookEntry', 'Create');
            }

            // =====================================================================
            // STEP 5: SBQQ__Dimension__c (Software/Maintenance/Support only)
            // =====================================================================

            // Use resolved pricebook name for Dimension Name (if pricebook was found)
            String pbNameForDim = 'Standard';
            if (customPbId != null) {
                // Fetch the actual pricebook name from the resolved Id
                List<Pricebook2> resolvedPb = [SELECT Name FROM Pricebook2 WHERE Id = :customPbId LIMIT 1];
                if (!resolvedPb.isEmpty()) {
                    pbNameForDim = resolvedPb[0].Name;
                }
            }

            // SBQQ__Dimension__c is pricebook-scoped: skip entirely when no pricebook was resolved.
            // Without a pricebook, there is no fiscal year context and CPQ rejects un-associated dims.
            List<SBQQ__Dimension__c> dimensions = new List<SBQQ__Dimension__c>();

            if (customPbId != null) {
                for (String code : productByCode.keySet()) {
                    SkuDetailRow detail = detailByCode.get(code);
                    Product2 p = productByCode.get(code);

                    if (detail != null && DIMENSION_PRODUCT_TYPES.contains(detail.productType)) {
                        for (String curr : effectiveCurrencies) {
                            SBQQ__Dimension__c dim = new SBQQ__Dimension__c(
                                Name = pbNameForDim + ' Annual ' + curr,
                                SBQQ__Product__c = p.Id,
                                SBQQ__Type__c = 'Year',
                                CurrencyIsoCode = curr,
                                SBQQ__PriceBook__c = customPbId
                            );
                            dimensions.add(dim);
                        }
                    }
                }

                if (!dimensions.isEmpty()) {
                    StepResult dimStep = performPartialInsert(dimensions, 'SBQQ__Dimension__c');
                    result.steps.add(dimStep);
                    result.totalSuccess += dimStep.successCount;
                    result.totalErrors += dimStep.errorCount;
                }
            }

            // =====================================================================
            // STEP 6: Block_Pricing__c — Meter Type (1 per product)
            // Skipped when no pricebook was resolved: Fiscal_Year__c would be blank,
            // which Prod triggers reject. Meter-type records belong to a pricebook context.
            // =====================================================================

            List<Block_Pricing__c> meterTypeBps = new List<Block_Pricing__c>();

            if (customPbId != null) {
            for (String code : productByCode.keySet()) {
                Product2 p = productByCode.get(code);
                SkuDetailRow detail = detailByCode.get(code);

                Block_Pricing__c mtBp = new Block_Pricing__c(
                    Product__c = p.Id,
                    Product_Code__c = code,
                    Type__c = 'Meter Type',
                    Active__c = true,
                    Fiscal_Year__c = fiscalYear,
                    Price_Book__c = customPbId
                );

                // Set sub-vertical meter types (populated by LWC from Pricing tab data).
                // For the Legal fields, 'Lawyers/Fee Earners' is not a valid picklist value:
                //   Legal__c              (GBP & EUR) → resolves to 'Fee Earners'
                //   Legal_meter_type_USD_AUD__c (USD & AUD) → resolves to 'Lawyers'
                if (detail != null) {
                    if (String.isNotBlank(detail.meterTypeAccounting))   mtBp.meter_type_Accounting__c = detail.meterTypeAccounting;
                    if (String.isNotBlank(detail.meterTypeConsulting))   mtBp.meter_type_Consulting__c = detail.meterTypeConsulting;
                    if (String.isNotBlank(detail.meterTypeCorporate))    mtBp.meter_type_Corporate__c = detail.meterTypeCorporate;
                    if (String.isNotBlank(detail.meterTypeIBA))          mtBp.meter_type_IBA__c = detail.meterTypeIBA;
                    if (String.isNotBlank(detail.meterTypePCM))          mtBp.meter_type_PCM__c = detail.meterTypePCM;
                    if (String.isNotBlank(detail.meterTypeRealAssets))   mtBp.meter_type_RealAssets__c = detail.meterTypeRealAssets;
                    if (String.isNotBlank(detail.meterTypeLegal)) {
                        mtBp.Legal__c = LAWYERS_FEE_EARNERS.equalsIgnoreCase(detail.meterTypeLegal)
                            ? FEE_EARNERS_METER_TYPE   // GBP/EUR → Fee Earners
                            : detail.meterTypeLegal;
                    }
                    if (String.isNotBlank(detail.meterTypeLegalUsdAud)) {
                        mtBp.Legal_meter_type_USD_AUD__c = LAWYERS_FEE_EARNERS.equalsIgnoreCase(detail.meterTypeLegalUsdAud)
                            ? LAWYERS_METER_TYPE        // USD/AUD → Lawyers
                            : detail.meterTypeLegalUsdAud;
                    }
                }

                meterTypeBps.add(mtBp);
            }

            if (!meterTypeBps.isEmpty()) {
                StepResult mtStep = performPartialInsert(meterTypeBps, 'Block_Pricing__c (Meter Type)');
                result.steps.add(mtStep);
                result.totalSuccess += mtStep.successCount;
                result.totalErrors += mtStep.errorCount;
            }
            } // end if (customPbId != null) — Meter Type Block_Pricing__c

            // =====================================================================
            // STEP 7: Block_Pricing__c — GTM Motion Tier (per Product × Meter × Tier × Currency)
            // Skipped when no pricebook was resolved (same reason as Meter Type above).
            // =====================================================================

            Map<String, Pricing_Tier_Configuration__mdt> tierConfigMap = getTierConfigMap();
            List<Block_Pricing__c> gtmTierBps = new List<Block_Pricing__c>();

            if (customPbId != null) for (PricingRow pr : pricingRows) {
                Product2 prod = productByCode.get(pr.productCode);
                if (prod == null || pr.prices == null) continue;

                SkuDetailRow detail = detailByCode.get(pr.productCode);
                Boolean isTierBased = (detail != null && TIER_BASED.equalsIgnoreCase(detail.pricingBasis));
                if (!isTierBased) continue;

                for (PriceEntry pe : pr.prices) {
                    if (pe.price == null) continue;
                    if (!effectiveCurrencySet.contains(pe.currencyCode)) continue;

                    String effectiveMt = effectiveMeterType(pr.meterType, pe.currencyCode);

                    Block_Pricing__c bp = new Block_Pricing__c(
                        Product__c = prod.Id,
                        Product_Code__c = pr.productCode,
                        Block_Pricing_Meter_Type__c = effectiveMt,
                        CurrencyIsoCode = pe.currencyCode,
                        Tier_Name__c = (pe.tier == 'None' ? null : pe.tier),
                        Price__c = pe.price,
                        Type__c = 'GTM Motion Tier',
                        Active__c = true,
                        Fiscal_Year__c = fiscalYear,
                        Price_Book__c = customPbId
                    );

                    // Auto-fill bounds from Pricing Tier Configuration metadata
                    String configKey = (pe.tier != null ? pe.tier : '') + '|' + effectiveMt;
                    if (tierConfigMap.containsKey(configKey)) {
                        Pricing_Tier_Configuration__mdt config = tierConfigMap.get(configKey);
                        bp.Lower_Bound__c = config.Lower_Bound__c;
                        bp.Upper_Bound__c = config.Upper_Bound__c;
                    } else {
                        bp.Lower_Bound__c = 1;
                        bp.Upper_Bound__c = 999999999;
                    }

                    gtmTierBps.add(bp);
                }
            }

            if (!gtmTierBps.isEmpty()) {
                StepResult gtmStep = performPartialInsert(gtmTierBps, 'Block_Pricing__c (GTM Motion Tier)');
                result.steps.add(gtmStep);
                result.totalSuccess += gtmStep.successCount;
                result.totalErrors += gtmStep.errorCount;
            }

            // =====================================================================
            // STEP 8: Reflect Eligible_For_Premium__c in local map for Intapp Pricing step
            // (Premium flag is now set during Product2 creation from SKU Details tab)
            // =====================================================================

            for (String code : productByCode.keySet()) {
                SkuDetailRow detail = detailByCode.get(code);
                if (detail != null && detail.eligibleForPremium == true) {
                    productByCode.get(code).Eligible_For_Premium__c = true;
                }
            }

            // =====================================================================
            // STEP 9: Bundle creation (placeholder -P products + SBQQ__ProductOption__c)
            // =====================================================================

            if (!bundleRows.isEmpty()) {
                createBundleRecords(
                    bundleRows, productByCode, detailByCode,
                    productLineMap, standardPbId, customPbId, result
                );
            }

            // =====================================================================
            // STEP 10: Intapp_Pricing__c (per Product × Meter × Tier × Currency × OP4I Pricebook)
            // =====================================================================

            List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
            String pricebookRuleName = String.isNotBlank(sfdcPricebookName) ? sfdcPricebookName : '';

            // Intapp_Pricing__c requires Price_book_rule__c — skip if no custom pricebook was resolved
            for (PricingRow pr : (customPbId != null ? pricingRows : new List<PricingRow>())) {
                Product2 prod = productByCode.get(pr.productCode);
                if (prod == null || pr.prices == null) continue;

                for (PriceEntry pe : pr.prices) {
                    if (pe.price == null) continue;
                    if (!effectiveCurrencySet.contains(pe.currencyCode)) continue;

                    String intappTier = (pe.tier == 'None') ? NONE_TIER_INTAPP : pe.tier;
                    String effectiveMt = effectiveMeterType(pr.meterType, pe.currencyCode);

                    // Derive OP4I pricebook abbreviation for Name
                    String op4iAbbrev = deriveOp4iAbbrev(pr);

                    // Auto-generate Name: FY-ProductCode-MeterType-Currency-OP4I-Tier
                    String intappName = fiscalYear + '-' + pr.productCode + '-' +
                        effectiveMt + '-' + pe.currencyCode;
                    if (String.isNotBlank(op4iAbbrev)) {
                        intappName += '-' + op4iAbbrev;
                    }
                    intappName += '-' + intappTier;
                    // Truncate to 80 chars (Salesforce Name field limit)
                    if (intappName.length() > 80) {
                        intappName = intappName.substring(0, 80);
                    }

                    Intapp_Pricing__c intapp = new Intapp_Pricing__c(
                        Name               = intappName,
                        Product__c         = prod.Id,
                        Product_Code__c    = pr.productCode,
                        Meter_Type__c      = effectiveMt,
                        CurrencyIsoCode    = pe.currencyCode,
                        Tier__c            = intappTier,
                        Price__c           = pe.price,
                        Price_Book__c      = customPbId,
                        Price_book_rule__c = pricebookRuleName,
                        Legal_Sales__c     = (pr.legalSales == true),
                        A_C_Sales__c       = (pr.acSales == true),
                        FS_Sales__c        = (pr.fsSales == true),
                        Corporate_Sales__c = (pr.corporateSales == true),
                        Ops_Only__c        = (pr.opsOnly == true)
                    );

                    // Premium pricing: 20% uplift
                    if (prod.Eligible_For_Premium__c == true && pe.price > 0) {
                        intapp.Premium_price__c = (pe.price * 1.2).setScale(2, RoundingMode.HALF_UP);
                    }

                    intappRecords.add(intapp);
                }
            }

            if (!intappRecords.isEmpty()) {
                StepResult intappStep = performPartialInsert(intappRecords, 'Intapp_Pricing__c');
                result.steps.add(intappStep);
                result.totalSuccess += intappStep.successCount;
                result.totalErrors += intappStep.errorCount;
            }

            // =====================================================================
            // STEP 11: SBQQ__QuoteTerm__c + SBQQ__TermCondition__c
            // =====================================================================

            List<QuoteTermRow> quoteTermRows = String.isNotBlank(quoteTermsJson)
                ? (List<QuoteTermRow>) JSON.deserialize(quoteTermsJson, List<QuoteTermRow>.class)
                : new List<QuoteTermRow>();

            List<SBQQ__QuoteTerm__c> quoteTermsToInsert = new List<SBQQ__QuoteTerm__c>();
            List<String> quoteTermProductCodes = new List<String>(); // parallel list tracking product code per term

            // Build productName -> productCode map so quote term rows with blank/placeholder
            // product codes (e.g. "leave blank, system created.") resolve to the generated code.
            Map<String, String> qtNameToCode = new Map<String, String>();
            for (String code : detailByCode.keySet()) {
                SkuDetailRow sd = detailByCode.get(code);
                if (String.isNotBlank(sd.productName)) {
                    qtNameToCode.put(sd.productName, code);
                }
            }

            if (!quoteTermRows.isEmpty()) {
                for (QuoteTermRow qtRow : quoteTermRows) {
                    String resolvedCode = qtRow.productCode;
                    if (String.isBlank(resolvedCode) || resolvedCode.containsIgnoreCase('leave blank')) {
                        resolvedCode = qtNameToCode.get(qtRow.productName);
                    }

                    Product2 prod = productByCode.get(resolvedCode);
                    if (prod == null) continue;

                    String descSuffix = qtRow.termNumber != null ? String.valueOf(qtRow.termNumber) : '1';

                    SBQQ__QuoteTerm__c qt = new SBQQ__QuoteTerm__c(
                        SBQQ__Body__c           = qtRow.body,
                        SBQQ__ConditionsMet__c  = 'All',
                        SBQQ__Active__c         = true,
                        SBQQ__Status__c         = 'Approved',
                        SBQQ__PrintOrder__c     = 300,
                        Term_Category__c        = 'Product',
                        Description__c          = qtRow.productName + ' (' + resolvedCode + ') - ' + descSuffix
                    );

                    quoteTermsToInsert.add(qt);
                    quoteTermProductCodes.add(resolvedCode);
                }

                if (!quoteTermsToInsert.isEmpty()) {
                    StepResult qtStep = performPartialInsert(quoteTermsToInsert, 'SBQQ__QuoteTerm__c');
                    result.steps.add(qtStep);
                    result.totalSuccess += qtStep.successCount;
                    result.totalErrors += qtStep.errorCount;

                    // Populate GearsetExternalId__c on QuoteTerms before creating TermConditions
                    // so the Term_Condition_Before_Insert_Update Flow generates a unique
                    // GearsetExternalId per TermCondition (formula: QuoteTerm.GearsetExternalId + field + index).
                    // Without this, all QuoteTerms have null GearsetExternalId at TC insert time,
                    // causing the Flow to generate duplicate values across multiple QuoteTerms.
                    populateGearsetExternalIds(quoteTermsToInsert);

                    // Create SBQQ__TermCondition__c records (2 per successfully inserted term)
                    List<SBQQ__TermCondition__c> termConditions = new List<SBQQ__TermCondition__c>();

                    for (Integer i = 0; i < quoteTermsToInsert.size(); i++) {
                        SBQQ__QuoteTerm__c qt = quoteTermsToInsert[i];
                        if (qt.Id == null) continue; // Skip failed inserts

                        String prodCode = quoteTermProductCodes[i];

                        // Condition 1: Exclude_Product_Specific_Language__c equals false
                        termConditions.add(new SBQQ__TermCondition__c(
                            SBQQ__QuoteTerm__c      = qt.Id,
                            SBQQ__TestedField__c    = 'Exclude_Product_Specific_Language__c',
                            SBQQ__Operator__c       = 'equals',
                            SBQQ__Value__c          = 'false',
                            SBQQ__Index__c          = 10
                        ));

                        // Condition 2: master_product_pins contains product code
                        termConditions.add(new SBQQ__TermCondition__c(
                            SBQQ__QuoteTerm__c      = qt.Id,
                            SBQQ__TestedField__c    = 'master_product_pins_from_all_quote_lines__c',
                            SBQQ__Operator__c       = 'contains',
                            SBQQ__Value__c          = prodCode,
                            SBQQ__Index__c          = 20
                        ));
                    }

                    if (!termConditions.isEmpty()) {
                        StepResult tcStep = performPartialInsert(termConditions, 'SBQQ__TermCondition__c');
                        result.steps.add(tcStep);
                        result.totalSuccess += tcStep.successCount;
                        result.totalErrors += tcStep.errorCount;
                    }

                    // GearsetExternalId on term conditions
                    populateGearsetExternalIds(quoteTermsToInsert);
                    populateGearsetExternalIds(termConditions);

                    // Sync GearsetExternalId onto in-memory quote term records then capture
                    // (SBQQ__TermCondition__c is not in OBJECT_REGISTRY — no capture needed)
                    for (SBQQ__QuoteTerm__c qt : quoteTermsToInsert) {
                        if (qt.Id != null) qt.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(qt.Id);
                    }
                    StagingCaptureService.capture(quoteTermsToInsert, 'SBQQ__QuoteTerm__c', 'Create');
                }
            }

            // =====================================================================
            // STEP 12: GearsetExternalId__c on all remaining created records
            // =====================================================================

            populateGearsetExternalIds(meterTypeBps);
            populateGearsetExternalIds(gtmTierBps);
            populateGearsetExternalIds(intappRecords);

            // Atomic guard — if any step produced errors, abort before staging capture
            if (result.totalErrors > 0) {
                List<String> allErrors = new List<String>();
                for (StepResult s : result.steps) { allErrors.addAll(s.errors); }
                String totalErrMsg = 'Launch aborted: ' + result.totalErrors + ' error(s) occurred. No records were created.\n' +
                    String.join(allErrors, '\n');
                if (Test.isRunningTest()) { lastTestDiagnostic = '[TOTAL_ERRORS] steps=' + JSON.serialize(result.steps) + ' | ' + totalErrMsg; }
                throw new AuraHandledException(totalErrMsg);
            }

            // Sync GearsetExternalId onto in-memory records then capture
            for (Block_Pricing__c rec : meterTypeBps) {
                if (rec.Id != null) rec.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(rec.Id);
            }
            StagingCaptureService.capture(meterTypeBps, 'Block_Pricing__c', 'Create');
            for (Block_Pricing__c rec : gtmTierBps) {
                if (rec.Id != null) rec.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(rec.Id);
            }
            StagingCaptureService.capture(gtmTierBps, 'Block_Pricing__c', 'Create');
            for (Intapp_Pricing__c rec : intappRecords) {
                if (rec.Id != null) rec.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(rec.Id);
            }
            StagingCaptureService.capture(intappRecords, 'Intapp_Pricing__c', 'Create');

            // Log completion
            Nebula.Logger.info(
                'New SKU Launch complete. Total success: ' + result.totalSuccess +
                ', Total errors: ' + result.totalErrors
            ).addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            String exMsg = e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString();
            if (Test.isRunningTest()) { lastTestDiagnostic = '[EXCEPTION] ' + exMsg; }
            Nebula.Logger.error('New SKU Launch failed: ' + e.getMessage() +
                '\n' + e.getStackTraceString()
            ).addTag('SkuNewLaunch');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Private Methods — Bundle Creation
    // =========================================================================

    /**
     * @description Creates bundle placeholder products (-P suffix), PricebookEntries,
     *              and SBQQ__ProductOption__c records for bundle parent + children.
     */
    private static void createBundleRecords(
        List<BundleRow> bundleRows,
        Map<String, Product2> productByCode,
        Map<String, SkuDetailRow> detailByCode,
        Map<String, Id> productLineMap,
        Id standardPbId,
        Id customPbId,
        LaunchResult result
    ) {
        // Group by parent product code
        Map<String, List<BundleRow>> bundlesByParent = new Map<String, List<BundleRow>>();
        Set<String> componentLookupCodes = new Set<String>();

        for (BundleRow br : bundleRows) {
            String parentCode = (br.role == 'BUNDLE') ? br.imNumber : br.parentProductCode;
            if (String.isBlank(parentCode)) continue;

            if (!bundlesByParent.containsKey(parentCode)) {
                bundlesByParent.put(parentCode, new List<BundleRow>());
            }
            bundlesByParent.get(parentCode).add(br);

            // Collect component codes for bulk lookup of existing products
            if (br.role != 'BUNDLE' && String.isNotBlank(br.imNumber)) {
                if (!productByCode.containsKey(br.imNumber)) {
                    componentLookupCodes.add(br.imNumber);
                }
            }
        }

        // Bulk query for existing component products (not in this launch)
        // Uses without-sharing CatalogQuery so Product2 records are visible
        // regardless of org-level sharing rules on the catalog object.
        // Also strips invisible Unicode characters (U+200B etc.) that Excel may embed in cells.
        Set<String> cleanedLookupCodes = new Set<String>();
        for (String code : componentLookupCodes) {
            cleanedLookupCodes.add(code.replaceAll('[^\\x20-\\x7E]', '').trim());
        }
        Map<String, Id> existingComponentMap = new CatalogQuery().getProductIdsByCode(cleanedLookupCodes);

        // Only create bundle placeholders for products where isBundle = true
        List<String> bundleParentCodes = new List<String>();
        for (String parentCode : bundlesByParent.keySet()) {
            SkuDetailRow parentDetail = detailByCode.get(parentCode);
            if (parentDetail != null && parentDetail.isBundle == true) {
                bundleParentCodes.add(parentCode);
            }
        }

        // Create placeholder -P Product2 records (no Item Master for placeholders)
        List<Product2> placeholderProducts = new List<Product2>();
        List<String> placeholderParentCodes = new List<String>();

        for (String parentCode : bundleParentCodes) {
            SkuDetailRow parentDetail = detailByCode.get(parentCode);
            Product2 parentProduct = productByCode.get(parentCode);

            Product2 plProd = new Product2(
                Name = (parentDetail != null ? parentDetail.productName : parentCode) + ' Bundle',
                ProductCode = parentCode + '-P',
                IsActive = true,
                Parent_Of_Bundle__c = true,
                SBQQ__ConfigurationType__c = 'Allowed'
            );

            if (parentDetail != null) {
                plProd.Product_Type__c = parentDetail.productType;
                if (String.isNotBlank(parentDetail.productLine) && productLineMap.containsKey(parentDetail.productLine)) {
                    plProd.Product_LineNew__c = productLineMap.get(parentDetail.productLine);
                }
            }

            placeholderProducts.add(plProd);
            placeholderParentCodes.add(parentCode);
        }

        StepResult plProdStep = performPartialInsert(placeholderProducts, 'Product2 (Placeholder)');
        result.steps.add(plProdStep);
        result.totalSuccess += plProdStep.successCount;
        result.totalErrors += plProdStep.errorCount;

        // PricebookEntries for placeholder products — Standard PBEs first
        List<String> plEffectiveCurrencies = getEffectiveCurrencies();
        if (standardPbId != null) {
            List<PricebookEntry> plStdPbes = new List<PricebookEntry>();
            for (Product2 plProd : placeholderProducts) {
                if (plProd.Id == null) continue;
                for (String curr : plEffectiveCurrencies) {
                    plStdPbes.add(new PricebookEntry(
                        Pricebook2Id = standardPbId,
                        Product2Id = plProd.Id,
                        CurrencyIsoCode = curr,
                        UnitPrice = 0,
                        IsActive = true
                    ));
                }
            }
            if (!plStdPbes.isEmpty()) {
                Database.insert(plStdPbes, false);
            }
        }

        // Custom PBEs for placeholders
        if (customPbId != null && !placeholderProducts.isEmpty()) {
            List<PricebookEntry> plCustomPbes = new List<PricebookEntry>();
            for (Product2 plProd : placeholderProducts) {
                if (plProd.Id == null) continue;
                for (String curr : plEffectiveCurrencies) {
                    plCustomPbes.add(new PricebookEntry(
                        Pricebook2Id = customPbId,
                        Product2Id = plProd.Id,
                        CurrencyIsoCode = curr,
                        UnitPrice = 0,
                        IsActive = true
                    ));
                }
            }
            if (!plCustomPbes.isEmpty()) {
                Database.insert(plCustomPbes, false);
            }
        }

        // GearsetExternalIds for placeholder Products (reversed to match Gearset convention)
        List<SObject> plGearsetUpdates = new List<SObject>();
        for (Product2 plProd : placeholderProducts) {
            if (plProd.Id != null) {
                plGearsetUpdates.add(new Product2(
                    Id = plProd.Id,
                    GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(plProd.Id)
                ));
            }
        }
        if (!plGearsetUpdates.isEmpty()) {
            Database.update(plGearsetUpdates, false);
        }

        // Build placeholder parentCode -> Product2 map
        Map<String, Product2> placeholderByParent = new Map<String, Product2>();
        for (Integer j = 0; j < placeholderProducts.size(); j++) {
            Product2 plProd = placeholderProducts[j];
            if (plProd.Id != null) {
                placeholderByParent.put(placeholderParentCodes[j], plProd);
            }
        }

        // Create SBQQ__ProductOption__c records
        List<SBQQ__ProductOption__c> productOptions = new List<SBQQ__ProductOption__c>();
        List<String> missingComponentWarnings = new List<String>();

        for (String parentCode : bundlesByParent.keySet()) {
            Product2 placeholderProd = placeholderByParent.get(parentCode);
            if (placeholderProd == null) continue;

            List<BundleRow> components = bundlesByParent.get(parentCode);
            Integer optionNumber = 1;

            for (BundleRow br : components) {
                Id optionalSkuId = null;
                String optionType = null;
                Boolean isBundled = false;

                if (br.role == 'BUNDLE') {
                    // The bundle product itself as a "Static Bundle" option
                    Product2 bundleProd = productByCode.get(br.imNumber);
                    if (bundleProd != null) {
                        optionalSkuId = bundleProd.Id;
                    }
                    optionType = 'Static Bundle';
                    isBundled = false;
                } else {
                    // Component product as a "Static Component" option
                    // Clean invisible Unicode chars (e.g. zero-width spaces from Excel)
                    String cleanCode = br.imNumber.replaceAll('[^\\x20-\\x7E]', '').trim();
                    Product2 componentProd = productByCode.get(cleanCode);
                    if (componentProd == null) {
                        // Look up existing product
                        optionalSkuId = existingComponentMap.get(cleanCode);
                    } else {
                        optionalSkuId = componentProd.Id;
                    }
                    optionType = 'Static Component';
                    isBundled = true;
                }

                if (optionalSkuId != null) {
                    SBQQ__ProductOption__c opt = new SBQQ__ProductOption__c(
                        SBQQ__ConfiguredSKU__c = placeholderProd.Id,
                        SBQQ__OptionalSKU__c = optionalSkuId,
                        SBQQ__Bundled__c = isBundled,
                        SBQQ__Number__c = optionNumber++,
                        SBQQ__Selected__c = true,
                        SBQQ__Required__c = true,
                        SBQQ__Quantity__c = 1,
                        CPQ_Option_Type__c = optionType
                    );
                    // Populate Revenue Allocation % on component product options from the Bundles tab
                    // Normalise: questionnaire accepts both 0–1 scale (0.32) and 0–100 scale (32)
                    if (br.role != 'BUNDLE' && br.acvPercent != null) {
                        opt.Revenue_Allocation__c = br.acvPercent <= 1
                            ? br.acvPercent * 100
                            : br.acvPercent;
                    }
                    productOptions.add(opt);
                } else if (br.role != 'BUNDLE') {
                    // Component product not found in this launch or in the org — surface a warning
                    String cleanCode2 = br.imNumber.replaceAll('[^\\x20-\\x7E]', '').trim();
                    String label = String.isNotBlank(br.productName) ? br.productName : cleanCode2;
                    missingComponentWarnings.add(
                        'WARNING: Component "' + label + '" (' + cleanCode2 + ') not found in org — ' +
                        'ensure the product exists before launching this bundle.'
                    );
                }
            }
        }

        if (!productOptions.isEmpty()) {
            StepResult optStep = performPartialInsert(productOptions, 'SBQQ__ProductOption__c');
            result.steps.add(optStep);
            result.totalSuccess += optStep.successCount;
            result.totalErrors += optStep.errorCount;

            // Update GearsetExternalId on Product Options
            populateGearsetExternalIds(productOptions);
        }

        // Surface missing component warnings as a blocking error so the atomic guard rolls back
        if (!missingComponentWarnings.isEmpty()) {
            StepResult warnStep = new StepResult();
            warnStep.objectName = 'Bundle Component Warnings';
            warnStep.successCount = 0;
            warnStep.errorCount = missingComponentWarnings.size();
            warnStep.totalCount = missingComponentWarnings.size();
            warnStep.errors = missingComponentWarnings;
            result.steps.add(warnStep);
            result.totalErrors += missingComponentWarnings.size();
        }
    }

    // =========================================================================
    // Without-Sharing Catalog Queries
    // =========================================================================

    /**
     * @description Inner class that runs WITHOUT sharing so catalog objects like
     *              Product2 are always visible regardless of org sharing rules.
     *              Use only for read-only catalog lookups (never for user data).
     */
    private without sharing class CatalogQuery {
        Map<String, Id> getProductIdsByCode(Set<String> productCodes) {
            Map<String, Id> result = new Map<String, Id>();
            if (productCodes == null || productCodes.isEmpty()) return result;
            for (Product2 p : [
                SELECT Id, ProductCode FROM Product2
                WHERE ProductCode IN :productCodes AND IsActive = true
            ]) {
                result.put(p.ProductCode, p.Id);
            }
            return result;
        }
    }

    // =========================================================================
    // Private Helper Methods — Picklist Label Resolution
    // =========================================================================

    /** NetSuite picklist fields on Item_Master_Product__c that need label-to-value translation */
    private static final List<String> NETSUITE_PICKLIST_FIELDS = new List<String>{
        'Income_Account__c', 'Deferred_Revenue_Account__c', 'Item_Revenue_Category__c',
        'Revenue_Recognition_Rule__c', 'Rev_Rec_Forecast_Rule__c', 'Revenue_Allocation_Group__c',
        'Create_Revenue_Plans_On__c', 'NetSuite_Item_Type_For_Invoicing__c',
        'NetSuite_Revenue_Recognition_Template__c', 'OpenAir_Billing_Rule__c',
        'TaxCode__c', 'NetSuite_Tax_Schedule__c', 'Revenue_Type__c'
    };

    /**
     * @description Builds a map of picklist label → API value for NetSuite fields on
     *              Item_Master_Product__c. Allows users to enter human-readable labels
     *              in the Excel questionnaire (e.g., "Sales" instead of "4000").
     *              Also maps API values to themselves for pass-through compatibility.
     * @return Map<fieldApiName, Map<lowercaseInput, apiValue>>
     */
    private static Map<String, Map<String, String>> getPicklistLabelToValueMap() {
        Map<String, Map<String, String>> fieldToLabelMap = new Map<String, Map<String, String>>();

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Item_Master_Product__c.fields.getMap();

        for (String fieldName : NETSUITE_PICKLIST_FIELDS) {
            Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
            if (field == null) continue;

            Map<String, String> labelToValue = new Map<String, String>();
            for (Schema.PicklistEntry ple : field.getDescribe().getPicklistValues()) {
                if (ple.isActive()) {
                    // Map both label and API value (case-insensitive) to the API value
                    labelToValue.put(ple.getLabel().toLowerCase().trim(), ple.getValue());
                    labelToValue.put(ple.getValue().toLowerCase().trim(), ple.getValue());
                }
            }
            fieldToLabelMap.put(fieldName, labelToValue);
        }

        return fieldToLabelMap;
    }

    /**
     * @description Translates a picklist label to its API value using a pre-built label map.
     *              Falls back to the original input value if no matching label or API value is found,
     *              allowing Salesforce to surface the standard validation error.
     * @param labelMap The label-to-value map from getPicklistLabelToValueMap()
     * @param fieldName The API name of the picklist field
     * @param inputValue The value from the Excel (could be label or API value)
     * @return The resolved API value, or the original input if no match
     */
    private static String resolvePicklistValue(
        Map<String, Map<String, String>> labelMap, String fieldName, String inputValue
    ) {
        if (String.isBlank(inputValue)) return inputValue;

        Map<String, String> labelToValue = labelMap.get(fieldName);
        if (labelToValue == null) return inputValue;

        String resolved = labelToValue.get(inputValue.toLowerCase().trim());
        return resolved != null ? resolved : inputValue;
    }

    // =========================================================================
    // Private Helper Methods
    // =========================================================================

    /**
     * @description Performs a partial success insert and collects results.
     * @param records List of SObjects to insert
     * @param objectName Display name for the step result
     * @return StepResult with success/error counts and error messages
     */
    private static StepResult performPartialInsert(List<SObject> records, String objectName) {
        StepResult step = new StepResult();
        step.objectName = objectName;
        step.successCount = 0;
        step.errorCount = 0;
        step.totalCount = records.size();
        step.errors = new List<String>();

        if (records.isEmpty()) {
            return step;
        }

        Database.SaveResult[] results = Database.insert(records, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                step.successCount++;
            } else {
                step.errorCount++;
                for (Database.Error err : results[i].getErrors()) {
                    if (step.errors.size() < 10) {
                        step.errors.add(objectName + ' row ' + (i + 1) + ': ' + err.getMessage());
                    }
                }
            }
        }

        return step;
    }

    /**
     * @description Populates GearsetExternalId__c on successfully-inserted records.
     *              Sets each record's GearsetExternalId__c to reverse(record Id) to
     *              match the Gearset convention for cross-org record matching.
     * @param records The inserted records (must all be same SObject type)
     */
    private static void populateGearsetExternalIds(List<SObject> records) {
        if (records == null || records.isEmpty()) return;

        List<SObject> toUpdate = new List<SObject>();
        Schema.SObjectType objType = records[0].getSObjectType();

        for (SObject rec : records) {
            if (rec.Id != null) {
                SObject updateRec = objType.newSObject(rec.Id);
                updateRec.put('GearsetExternalId__c', StagingCaptureService.buildGearsetExternalId(rec.Id));
                toUpdate.add(updateRec);
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    /**
     * @description Queries all Pricing_Tier_Configuration__mdt records and returns
     *              a map keyed by "TierName|MeterType" for auto-filling bounds on Block_Pricing__c.
     * @return Map of configuration key to metadata record
     */
    private static Map<String, Pricing_Tier_Configuration__mdt> getTierConfigMap() {
        Map<String, Pricing_Tier_Configuration__mdt> configMap = new Map<String, Pricing_Tier_Configuration__mdt>();
        for (Pricing_Tier_Configuration__mdt config : [
            SELECT Tier__c, Meter_Type__c, Lower_Bound__c, Upper_Bound__c
            FROM Pricing_Tier_Configuration__mdt
        ]) {
            String key = config.Tier__c + '|' + config.Meter_Type__c;
            configMap.put(key, config);
        }
        return configMap;
    }

    /**
     * @description Extracts fiscal year code from a pricebook name (e.g., 'FY26' from 'FY26 All Products').
     * @param pricebookName The full pricebook name
     * @return Fiscal year code (e.g., 'FY26'), or empty string if not found
     */
    private static String extractFiscalYearCode(String pricebookName) {
        if (String.isBlank(pricebookName)) return '';
        Pattern fyPattern = Pattern.compile('(FY\\d{2})');
        Matcher m = fyPattern.matcher(pricebookName);
        if (m.find()) {
            return m.group(1);
        }
        // Fallback: use portion before first space or underscore
        Integer spaceIdx = pricebookName.indexOf(' ');
        Integer underIdx = pricebookName.indexOf('_');
        Integer idx = -1;
        if (spaceIdx > 0 && underIdx > 0) {
            idx = Math.min(spaceIdx, underIdx);
        } else if (spaceIdx > 0) {
            idx = spaceIdx;
        } else if (underIdx > 0) {
            idx = underIdx;
        }
        return idx > 0 ? pricebookName.substring(0, idx) : pricebookName;
    }

    /**
     * @description Derives OP4I pricebook abbreviation from a PricingRow's sales channel flags.
     * @param row PricingRow with boolean flags
     * @return Abbreviation string for the Intapp_Pricing__c Name
     */
    private static String deriveOp4iAbbrev(PricingRow row) {
        if (row.legalSales == true)     return 'Legal';
        if (row.acSales == true)        return 'AC';
        if (row.fsSales == true)        return 'FS';
        if (row.corporateSales == true) return 'Corporate';
        if (row.opsOnly == true)        return 'Ops Only';
        return '';
    }

    /**
     * @description Resolves the effective meter type for a given currency when the source
     *              meter type is 'Lawyers/Fee Earners'. USD and AUD use 'Lawyers';
     *              EUR and GBP use 'Fee Earners'. All other meter types are returned unchanged.
     * @param meterType   The meter type value from the pricing row
     * @param currencyCode The ISO currency code for the price entry
     * @return The effective meter type to use on the pricing record
     */
    private static String effectiveMeterType(String meterType, String currencyCode) {
        if (LAWYERS_FEE_EARNERS.equalsIgnoreCase(meterType)) {
            if (LAWYERS_CURRENCIES.contains(currencyCode))    return LAWYERS_METER_TYPE;
            if (FEE_EARNERS_CURRENCIES.contains(currencyCode)) return FEE_EARNERS_METER_TYPE;
        }
        return meterType;
    }

    /**
     * @description Returns the list of currency ISO codes to use when creating multi-currency
     *              records (PricebookEntries, Dimensions, etc.). In a single-currency org,
     *              only the org's default currency is returned so DML operations do not fail
     *              on inactive currencies. In a multi-currency org all four standard currencies
     *              are returned.
     * @return List of active ISO currency codes to use for record creation
     */
    private static List<String> getEffectiveCurrencies() {
        if (!UserInfo.isMultiCurrencyOrganization()) {
            return new List<String>{ UserInfo.getDefaultCurrency() };
        }
        return CURRENCIES;
    }

    // =========================================================================
    // Inner Classes — Wrapper Types
    // =========================================================================

    /**
     * @description Parsed row from the SKU Details Excel tab (one per product).
     *              Contains all 43+ columns mapped from the questionnaire.
     */
    public class SkuDetailRow {
        // Core identification
        @AuraEnabled public String productCode;              // IMP code using product line prefix (e.g., CO-02129) — used for display and all SF records
        @AuraEnabled public String pinCode;                  // PIN-based code for im.Name only (auto-generated rows, e.g., PIN-02129)
        @AuraEnabled public String itemMasterName;           // "Item Master Name" column — shared key across tabs, used for cross-tab code resolution
        @AuraEnabled public String productName;              // "Product Name (Col F)" — display name for Product2.Name
        @AuraEnabled public String description;

        // Lookups (resolved by name)
        @AuraEnabled public String productLine;              // Product_Line__c Name
        @AuraEnabled public String productRollup;            // Product_Rollup__c Name

        // Product fields
        @AuraEnabled public String revenueType;              // Recurring / One-time
        @AuraEnabled public String productGroup;             // Picklist
        @AuraEnabled public String productType;              // Software / Maintenance / Support / Services
        @AuraEnabled public Boolean includesAssist;
        @AuraEnabled public Boolean eligibleForPremium;      // Moved from Pricing tab to SKU Details
        @AuraEnabled public String pricingBasis;             // Tier based / Quantity based / Free / % of ACV / Other/Mixed
        @AuraEnabled public Decimal percentageOfAcv;         // Only when Pricing Basis = '% of ACV'
        @AuraEnabled public String servicesProductType;      // Fixed Fee / T&M
        @AuraEnabled public String softwareLicenseTerm;      // Product_License_Type__c
        @AuraEnabled public String subscriptionType;         // SBQQ__SubscriptionType__c
        @AuraEnabled public Boolean isBundle;                // Bundle_Product__c / SBQQ__Component__c
        @AuraEnabled public String lineOfBusinessProduct;
        @AuraEnabled public String sfdcPricebook;            // SFDC Pricebook name (for PBE creation)
        @AuraEnabled public String subscriptionPricing;      // SBQQ__SubscriptionPricing__c

        // Sub-vertical fields (Active / Restricted / Unavailable)
        @AuraEnabled public String isLegal;
        @AuraEnabled public String isAccounting;
        @AuraEnabled public String isConsulting;
        @AuraEnabled public String isIBA;
        @AuraEnabled public String isPCM;
        @AuraEnabled public String isRealAssets;
        @AuraEnabled public String isCorporate;

        // NetSuite / Financial fields
        @AuraEnabled public String netsuiteIncomeAccount;
        @AuraEnabled public String netsuiteDeferredRevenueAccount;
        @AuraEnabled public String netsuiteItemRevenueCategory;
        @AuraEnabled public String netsuiteRevRecognitionRule;
        @AuraEnabled public String netsuiteRevRecForecastRule;
        @AuraEnabled public String netsuiteRevenueAllocationGroup;
        @AuraEnabled public String netsuiteCreateRevenuePlansOn;
        @AuraEnabled public String netsuiteItemTypeForInvoicing;
        @AuraEnabled public String netsuiteRevRecTemplate;
        @AuraEnabled public Boolean netsuiteIncludeChildren;
        @AuraEnabled public String openAirBillingRule;
        @AuraEnabled public Boolean netsuiteExportToOpenAir;
        @AuraEnabled public String avalaraTaxCode;
        @AuraEnabled public String netsuiteTaxSchedule;
        @AuraEnabled public Boolean triggerToNetsuite;       // Trigger_to_NS__c on Item Master
        // FY26 questionnaire additions — Item_Master_Product__c fields
        @AuraEnabled public String netsuiteType;                // NetSuite_Type__c
        @AuraEnabled public String netsuiteSubType;             // NetSuite_SubType__c
        @AuraEnabled public Boolean netsuiteCanBeFulfilled;     // NetSuite_Can_be_fulfilled__c
        @AuraEnabled public String netsuiteBillingSchedule;     // NetSuite_Billing_Schedule__c
        @AuraEnabled public Boolean exemptFromMagicScript;      // Exempt_from_Magic_Script__c
        @AuraEnabled public Boolean netsuiteDirectRevenuePosting; // NetSuite_Direct_Revenue_Posting__c
        @AuraEnabled public String netsuiteAllocationType;      // NetSuite_Allocation_Type__c
        @AuraEnabled public Boolean syncNetsuite;               // Sync_NetSuite__c
        @AuraEnabled public String deploymentType;              // Deployment_Type__c (display/reference)
        @AuraEnabled public String productFamily;               // Product family (display/reference)
        @AuraEnabled public String businessUnit;                // Business unit (display/reference)
        @AuraEnabled public String op4iPricebook;               // OP4I Pricebook(s) (display/reference)

        // Meter type mapping per sub-vertical (populated by LWC from Pricing tab data)
        @AuraEnabled public String meterTypeAccounting;
        @AuraEnabled public String meterTypeConsulting;
        @AuraEnabled public String meterTypeCorporate;
        @AuraEnabled public String meterTypeIBA;
        @AuraEnabled public String meterTypePCM;
        @AuraEnabled public String meterTypeRealAssets;
        @AuraEnabled public String meterTypeLegal;
        @AuraEnabled public String meterTypeLegalUsdAud;
    }

    /**
     * @description Parsed row from the Pricing Excel tab (one per product × meter type).
     *              Contains OP4I pricebook flags and a list of price entries (tier × currency).
     */
    public class PricingRow {
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String meterType;

        // OP4I pricebook flags (marked with "x" in Excel)
        @AuraEnabled public Boolean legalSales;
        @AuraEnabled public Boolean acSales;
        @AuraEnabled public Boolean fsSales;
        @AuraEnabled public Boolean corporateSales;
        @AuraEnabled public Boolean opsOnly;

        // Premium Support flag
        @AuraEnabled public Boolean premiumSupport;

        // Price entries: up to 24 (6 tiers × 4 currencies)
        @AuraEnabled public List<PriceEntry> prices;
    }

    /**
     * @description Single price cell from the pricing matrix (one tier × currency).
     */
    public class PriceEntry {
        @AuraEnabled public String currencyCode;    // USD / GBP / EUR / AUD
        @AuraEnabled public String tier;            // EM1-EM5 / None
        @AuraEnabled public Decimal price;
    }

    /**
     * @description Parsed row from the Bundles Allocations Excel tab.
     *              Role determines whether it's a bundle parent or component child.
     */
    public class BundleRow {
        @AuraEnabled public String role;                 // 'BUNDLE' or 'Component Product'
        @AuraEnabled public String productName;
        @AuraEnabled public String imNumber;              // Product Code (Item Master Number)
        @AuraEnabled public Decimal acvPercent;           // Allocation percentage
        @AuraEnabled public String parentProductCode;     // Which bundle parent this component belongs to
    }

    /**
     * @description Parsed row from the Quote Terms Excel tab (one per product × quote term).
     *              Within bundles, only Static Components (not the Static Bundle product)
     *              should have quote terms.
     */
    public class QuoteTermRow {
        @AuraEnabled public String productCode;       // IM Number (e.g., IN-02128)
        @AuraEnabled public String productName;
        @AuraEnabled public String body;              // Quote term body text
        @AuraEnabled public Integer termNumber;       // Sequence number within the product
    }

    // =========================================================================
    // Inner Classes — Result Types
    // =========================================================================

    /**
     * @description Result from validation. Contains errors, warnings, and summary counts.
     */
    public class ValidationResult {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public Integer skuCount;
        @AuraEnabled public Integer pricingRowCount;
        @AuraEnabled public Integer bundleCount;
        @AuraEnabled public Integer quoteTermCount;
    }

    /**
     * @description Result from processNewSkuLaunch. Contains per-step results and totals.
     */
    public class LaunchResult {
        @AuraEnabled public List<StepResult> steps;
        @AuraEnabled public Integer totalSuccess;
        @AuraEnabled public Integer totalErrors;
        @AuraEnabled public List<CreatedProduct> createdProducts;
    }

    /**
     * @description Summary of a successfully created Product2 record for post-launch navigation.
     */
    public class CreatedProduct {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
    }

    /**
     * @description Result from a single DML step (one object type insertion).
     */
    public class StepResult {
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<String> errors;
    }
}