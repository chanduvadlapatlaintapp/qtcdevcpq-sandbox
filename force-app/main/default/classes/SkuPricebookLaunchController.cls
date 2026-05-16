/**
 * @description Controller for Pricebook Launch (bulk Block_Pricing__c and
 *              Intapp_Pricing__c creation) in the SKU Management App.
 *              Supports FR-7 (Pricebook Launch).
 *              Block_Pricing__c (GTM Motion Tier) is created only for
 *              Tier based products. Intapp_Pricing__c is created for all
 *              products regardless of pricing basis.
 */
public with sharing class SkuPricebookLaunchController {

    private static final String TIER_BASED = 'Tier based';

    /**
     * @description Gets active products, optionally filtered by Product Line.
     * @param productLineFilter Optional Product_LineNew__c Id filter
     * @return List of active Product2 records
     */
    @AuraEnabled(cacheable=true)
    public static List<Product2> getActiveProducts(Id productLineFilter) {
        if (productLineFilter != null) {
            return [
                SELECT Id, Name, ProductCode, Product_Type__c,
                       Pricing_Basis__c, Eligible_For_Premium__c,
                       Product_LineNew__c, Product_LineNew__r.Name
                FROM Product2
                WHERE IsActive = true AND Product_LineNew__c = :productLineFilter
                ORDER BY Name ASC
                LIMIT 500
            ];
        }
        return [
            SELECT Id, Name, ProductCode, Product_Type__c,
                   Pricing_Basis__c,
                   Product_LineNew__c, Product_LineNew__r.Name
            FROM Product2
            WHERE IsActive = true
            ORDER BY Name ASC
            LIMIT 500
        ];
    }

    /**
     * @description Gets active Pricebook2 records.
     * @return List of active pricebooks
     */
    @AuraEnabled(cacheable=true)
    public static List<Pricebook2> getPricebooks() {
        return [
            SELECT Id, Name, IsActive
            FROM Pricebook2
            WHERE IsActive = true
            ORDER BY Name ASC
        ];
    }

    /**
     * @description Gets existing Block_Pricing__c for a pricebook and fiscal year.
     * @param pricebookId Pricebook2 Id (not directly on Block_Pricing__c, used for context)
     * @param fiscalYear Fiscal year value
     * @return List of existing Block_Pricing__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Block_Pricing__c> getExistingPricebookRecords(String fiscalYear) {
        if (String.isBlank(fiscalYear)) {
            return new List<Block_Pricing__c>();
        }
        return [
            SELECT Id, Product__c, Product__r.Name, Product__r.ProductCode,
                   Block_Pricing_Meter_Type__c, Fiscal_Year__c, Price__c,
                   Tier_Name__c, Active__c, CurrencyIsoCode
            FROM Block_Pricing__c
            WHERE Fiscal_Year__c = :fiscalYear
            ORDER BY Product__r.Name
            LIMIT 2000
        ];
    }

    /**
     * @description Bulk creates pricing records using partial success.
     *              Block_Pricing__c (GTM Motion Tier) — Tier based products only.
     *              Intapp_Pricing__c — all products regardless of pricing basis.
     * @param recordsJson JSON string of Block_Pricing__c records
     * @return LaunchResult with success/error counts split by record type
     */
    @AuraEnabled
    public static LaunchResult launchPricebook(String recordsJson) {
        try {
            List<Block_Pricing__c> records = (List<Block_Pricing__c>) JSON.deserialize(
                recordsJson, List<Block_Pricing__c>.class
            );

            // ── 1. Look up Pricing_Basis__c and ProductCode for each product ──
            Set<Id> productIds = new Set<Id>();
            for (Block_Pricing__c r : records) {
                if (r.Product__c != null) productIds.add(r.Product__c);
            }
            Map<Id, Product2> productMap = new Map<Id, Product2>([
                SELECT Id, ProductCode, Pricing_Basis__c, Eligible_For_Premium__c
                FROM Product2
                WHERE Id IN :productIds
            ]);

            // ── 2. Block_Pricing__c — Tier based only ──
            List<Block_Pricing__c> blockRecords = new List<Block_Pricing__c>();
            for (Block_Pricing__c r : records) {
                Product2 prod = productMap.get(r.Product__c);
                if (prod != null && TIER_BASED.equalsIgnoreCase(prod.Pricing_Basis__c)) {
                    blockRecords.add(r);
                }
            }

            // ── 3. Intapp_Pricing__c — all products ──
            List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
            for (Block_Pricing__c r : records) {
                Product2 prod = productMap.get(r.Product__c);
                String productCode = (prod != null && String.isNotBlank(prod.ProductCode))
                    ? prod.ProductCode : '';
                String meterType = String.isNotBlank(r.Block_Pricing_Meter_Type__c)
                    ? r.Block_Pricing_Meter_Type__c : 'Users';
                String fy = String.isNotBlank(r.Fiscal_Year__c) ? r.Fiscal_Year__c : '';

                String intappName = fy + '-' + productCode + '-' + meterType;
                if (String.isNotBlank(r.CurrencyIsoCode)) {
                    intappName += '-' + r.CurrencyIsoCode;
                }
                if (String.isNotBlank(r.Tier_Name__c)) {
                    intappName += '-' + r.Tier_Name__c;
                }
                if (intappName.length() > 80) {
                    intappName = intappName.substring(0, 80);
                }

                Intapp_Pricing__c intapp = new Intapp_Pricing__c(
                    Name            = intappName,
                    Product__c      = r.Product__c,
                    Product_Code__c = productCode,
                    Meter_Type__c   = meterType,
                    Price__c        = r.Price__c,
                    Tier__c         = r.Tier_Name__c,
                    Price_Book__c   = r.Price_Book__c
                );
                if (prod != null && prod.Eligible_For_Premium__c == true
                        && r.Price__c != null && r.Price__c > 0) {
                    intapp.Premium_price__c = (r.Price__c * 1.2).setScale(2, RoundingMode.HALF_UP);
                }
                intappRecords.add(intapp);
            }

            // ── 4. Insert both with partial success ──
            LaunchResult lr = new LaunchResult();
            lr.errors = new List<String>();

            Integer blockSuccess = 0, blockErrors = 0;
            if (!blockRecords.isEmpty()) {
                Database.SaveResult[] blockResults = Database.insert(blockRecords, false);
                for (Integer i = 0; i < blockResults.size(); i++) {
                    if (blockResults[i].isSuccess()) {
                        blockSuccess++;
                    } else {
                        blockErrors++;
                        for (Database.Error err : blockResults[i].getErrors()) {
                            if (lr.errors.size() < 10) {
                                lr.errors.add('[Block Pricing] Row ' + (i + 1) + ': ' + err.getMessage());
                            }
                        }
                    }
                }
            }

            Integer intappSuccess = 0, intappErrors = 0;
            if (!intappRecords.isEmpty()) {
                Database.SaveResult[] intappResults = Database.insert(intappRecords, false);
                for (Integer i = 0; i < intappResults.size(); i++) {
                    if (intappResults[i].isSuccess()) {
                        intappSuccess++;
                    } else {
                        intappErrors++;
                        for (Database.Error err : intappResults[i].getErrors()) {
                            if (lr.errors.size() < 10) {
                                lr.errors.add('[Intapp Pricing] Row ' + (i + 1) + ': ' + err.getMessage());
                            }
                        }
                    }
                }
            }

            lr.blockPricingCount  = blockSuccess;
            lr.intappPricingCount = intappSuccess;
            lr.successCount       = blockSuccess + intappSuccess;
            lr.errorCount         = blockErrors  + intappErrors;
            lr.totalCount         = blockRecords.size() + intappRecords.size();
            return lr;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Copies pricing records from one fiscal year to another
     *              with optional price adjustment percentage.
     *              Block_Pricing__c — Tier based products only.
     *              Intapp_Pricing__c — all products regardless of pricing basis.
     * @param sourceFY Source fiscal year
     * @param targetFY Target fiscal year
     * @param adjustPct Price adjustment percentage (e.g. 5 for 5% increase)
     * @return LaunchResult with success/error counts split by record type
     */
    @AuraEnabled
    public static LaunchResult copyPricebook(String sourceFY, String targetFY, Decimal adjustPct) {
        try {
            List<Block_Pricing__c> sourceRecords = [
                SELECT Product__c, Product_Code__c,
                       Block_Pricing_Meter_Type__c, Active__c,
                       CurrencyIsoCode, Price__c, Tier_Name__c, Type__c,
                       Price_Book__c, Lower_Bound__c, Upper_Bound__c,
                       Legal__c, Legal_meter_type_USD_AUD__c,
                       meter_type_Accounting__c, meter_type_Consulting__c,
                       meter_type_Corporate__c, meter_type_IBA__c,
                       meter_type_PCM__c, meter_type_RealAssets__c
                FROM Block_Pricing__c
                WHERE Fiscal_Year__c = :sourceFY
            ];

            if (sourceRecords.isEmpty()) {
                LaunchResult lr = new LaunchResult();
                lr.successCount       = 0;
                lr.errorCount         = 0;
                lr.totalCount         = 0;
                lr.blockPricingCount  = 0;
                lr.intappPricingCount = 0;
                lr.errors = new List<String>{ 'No records found for source fiscal year: ' + sourceFY };
                return lr;
            }

            // ── 1. Look up Pricing_Basis__c for each product ──
            Set<Id> productIds = new Set<Id>();
            for (Block_Pricing__c r : sourceRecords) {
                if (r.Product__c != null) productIds.add(r.Product__c);
            }
            Map<Id, Product2> productMap = new Map<Id, Product2>([
                SELECT Id, ProductCode, Pricing_Basis__c, Eligible_For_Premium__c
                FROM Product2
                WHERE Id IN :productIds
            ]);

            Decimal multiplier = (adjustPct != null) ? (1 + (adjustPct / 100)) : 1;

            // ── 2. Block_Pricing__c — Tier based only ──
            List<Block_Pricing__c> blockRecords = new List<Block_Pricing__c>();
            for (Block_Pricing__c src : sourceRecords) {
                Product2 prod = productMap.get(src.Product__c);
                if (prod == null || !TIER_BASED.equalsIgnoreCase(prod.Pricing_Basis__c)) continue;

                Block_Pricing__c clone = src.clone(false, true, false, false);
                clone.Fiscal_Year__c = targetFY;
                if (clone.Price__c != null && adjustPct != null) {
                    clone.Price__c = (clone.Price__c * multiplier).setScale(2, RoundingMode.HALF_UP);
                }
                blockRecords.add(clone);
            }

            // ── 3. Intapp_Pricing__c — all products ──
            List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
            for (Block_Pricing__c src : sourceRecords) {
                Product2 prod = productMap.get(src.Product__c);
                String productCode = String.isNotBlank(src.Product_Code__c)
                    ? src.Product_Code__c
                    : (prod != null && String.isNotBlank(prod.ProductCode) ? prod.ProductCode : '');
                String meterType = String.isNotBlank(src.Block_Pricing_Meter_Type__c)
                    ? src.Block_Pricing_Meter_Type__c : 'Users';

                Decimal adjustedPrice = src.Price__c;
                if (adjustedPrice != null && adjustPct != null) {
                    adjustedPrice = (adjustedPrice * multiplier).setScale(2, RoundingMode.HALF_UP);
                }

                String intappName = targetFY + '-' + productCode + '-' + meterType;
                if (String.isNotBlank(src.CurrencyIsoCode)) {
                    intappName += '-' + src.CurrencyIsoCode;
                }
                if (String.isNotBlank(src.Tier_Name__c)) {
                    intappName += '-' + src.Tier_Name__c;
                }
                if (intappName.length() > 80) {
                    intappName = intappName.substring(0, 80);
                }

                Intapp_Pricing__c intapp = new Intapp_Pricing__c(
                    Name            = intappName,
                    Product__c      = src.Product__c,
                    Product_Code__c = productCode,
                    Meter_Type__c   = meterType,
                    Price__c        = adjustedPrice,
                    Tier__c         = src.Tier_Name__c,
                    Price_Book__c   = src.Price_Book__c,
                    CurrencyIsoCode = src.CurrencyIsoCode
                );
                if (prod != null && prod.Eligible_For_Premium__c == true
                        && adjustedPrice != null && adjustedPrice > 0) {
                    intapp.Premium_price__c = (adjustedPrice * 1.2).setScale(2, RoundingMode.HALF_UP);
                }
                intappRecords.add(intapp);
            }

            // ── 4. Insert both with partial success ──
            LaunchResult lr = new LaunchResult();
            lr.errors = new List<String>();

            Integer blockSuccess = 0, blockErrors = 0;
            if (!blockRecords.isEmpty()) {
                Database.SaveResult[] blockResults = Database.insert(blockRecords, false);
                for (Integer i = 0; i < blockResults.size(); i++) {
                    if (blockResults[i].isSuccess()) {
                        blockSuccess++;
                    } else {
                        blockErrors++;
                        for (Database.Error err : blockResults[i].getErrors()) {
                            if (lr.errors.size() < 10) {
                                lr.errors.add('[Block Pricing] Row ' + (i + 1) + ': ' + err.getMessage());
                            }
                        }
                    }
                }
            }

            Integer intappSuccess = 0, intappErrors = 0;
            if (!intappRecords.isEmpty()) {
                Database.SaveResult[] intappResults = Database.insert(intappRecords, false);
                for (Integer i = 0; i < intappResults.size(); i++) {
                    if (intappResults[i].isSuccess()) {
                        intappSuccess++;
                    } else {
                        intappErrors++;
                        for (Database.Error err : intappResults[i].getErrors()) {
                            if (lr.errors.size() < 10) {
                                lr.errors.add('[Intapp Pricing] Row ' + (i + 1) + ': ' + err.getMessage());
                            }
                        }
                    }
                }
            }

            lr.blockPricingCount  = blockSuccess;
            lr.intappPricingCount = intappSuccess;
            lr.successCount       = blockSuccess + intappSuccess;
            lr.errorCount         = blockErrors  + intappErrors;
            lr.totalCount         = blockRecords.size() + intappRecords.size();
            return lr;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Returns Fiscal Year picklist values from Block_Pricing__c.
     * @return List of PicklistOption
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFiscalYearOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Block_Pricing__c.fields.getMap();
        if (fieldMap.containsKey('Fiscal_Year__c')) {
            for (Schema.PicklistEntry entry : fieldMap.get('Fiscal_Year__c').getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
                }
            }
        }
        return options;
    }

    // =========================================================================
    // Inner Classes
    // =========================================================================

    public class LaunchResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer blockPricingCount;
        @AuraEnabled public Integer intappPricingCount;
        @AuraEnabled public List<String> errors;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}