public class OP4ISubscriptionMigrationHelper {
    // --- Static collections for product options ---
    public static Map<String, SBQQ__ProductOption__c> staticProductOptionMap = new Map<String, SBQQ__ProductOption__c>();
    public static Map<String, Id> staticOptionalConfiguredParentBundleMap = new Map<String, Id>();
    public static Map<String, Id> optionalConfiguredParentBundleMap = staticOptionalConfiguredParentBundleMap;
    public static Id activePBId;
    /**
     * Get ProductOption map for allProductIds.
     * - Returns a new map; does not store in any static variable.
     * - Also returns the optionalConfiguredParentBundleMap as a second map.
     */
    public class ProductOptionMaps {
        public Map<String, SBQQ__ProductOption__c> productOptionMap;
        public Map<String, Id> optionalConfiguredParentBundleMap;
        public ProductOptionMaps(
            Map<String, SBQQ__ProductOption__c> productOptionMap,
            Map<String, Id> optionalConfiguredParentBundleMap
        ) {
            this.productOptionMap = productOptionMap;
            this.optionalConfiguredParentBundleMap = optionalConfiguredParentBundleMap;
        }
    }
    public static Id getCurrentPricebookId(){
        if(activePBId == null){
            List<Pricebook2> pbList = [SELECT Id FROM Pricebook2 WHERE IsActive = true AND Name = :Label.MigrationPriceBookName LIMIT 1];
            
            if (!pbList.isEmpty()) {
                activePBId = pbList[0].Id;
            }
        }
        return activePBId;
        
    }
    /**
     * Build a bundle key map for all entitlements.
     * If DLI_Product__c == DLIP_Product__c, key is DLI_Product__c + Associated_OSA__c + Product_Instance__c + Segment_Index__c.
     * Otherwise, key is DLI_Product__c + Associated_OSA__c + Product_Instance__c.
     */
    public static Map<String, List<OP4I_Entitlement_View__c>> getBundleKeyMap(List<OP4I_Entitlement_View__c> entitlements) {
        Map<String, List<OP4I_Entitlement_View__c>> bundleKeyMap = new Map<String, List<OP4I_Entitlement_View__c>>();
        for (OP4I_Entitlement_View__c row : entitlements) {
            String bundleKey;
            if (row.DLI_Product__c == row.DLIP_Product__c) {
                bundleKey =
                    (row.DLI_Product__c ?? '') + '_' +
                    (row.Associated_OSA__c ?? '') + '_' +
                    (row.Product_Instance__c != null ? String.valueOf(row.Product_Instance__c) : '') + '_' +
                    (row.Segment_Index__c != null ? String.valueOf(row.Segment_Index__c) : '');
            } else {
                bundleKey =
                    (row.DLI_Product__c ?? '') + '_' +
                    (row.Associated_OSA__c ?? '') + '_' +
                    (row.Product_Instance__c != null ? String.valueOf(row.Product_Instance__c) : '');
            }
            if (!bundleKeyMap.containsKey(bundleKey)) {
                bundleKeyMap.put(bundleKey, new List<OP4I_Entitlement_View__c>());
            }
            bundleKeyMap.get(bundleKey).add(row);
        }
        return bundleKeyMap;
    }

    /**
     * Build a segment bundle key map for component entitlements only (DLI != DLIP).
     * The key is DLI_Product__c + '_' + Product_Instance__c + '_' + Segment_Index__c
     */
    public static Map<String, List<OP4I_Entitlement_View__c>> getSegmentBundleKeyMap(List<OP4I_Entitlement_View__c> entitlements) {
        Map<String, List<OP4I_Entitlement_View__c>> segmentKeyMap = new Map<String, List<OP4I_Entitlement_View__c>>();
        for (OP4I_Entitlement_View__c row : entitlements) {
            if (row.DLI_Product__c != row.DLIP_Product__c) {
                String bundleKey =
                    (row.DLI_Product__c ?? '') + '_' +
                    (row.Associated_OSA__c ?? '') + '_' +
                    (row.Product_Instance__c != null ? String.valueOf(row.Product_Instance__c) : '') + '_' +
                    (row.Segment_Index__c != null ? String.valueOf(row.Segment_Index__c) : '');
                if (!segmentKeyMap.containsKey(bundleKey)) {
                    segmentKeyMap.put(bundleKey, new List<OP4I_Entitlement_View__c>());
                }
                segmentKeyMap.get(bundleKey).add(row);
            }
        }
        return segmentKeyMap;
    }
    
    public static Map<String, List<OP4I_Entitlement_View__c>> splitByChargeType(List<OP4I_Entitlement_View__c> entitlements) {
        List<OP4I_Entitlement_View__c> oneTime = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> others = new List<OP4I_Entitlement_View__c>();
    
        for (OP4I_Entitlement_View__c ent : entitlements) {
            if (ent.DLI_Product__r.SBQQ__ChargeType__c == 'One-Time') {
                oneTime.add(ent);
            } else {
                others.add(ent);
            }
        }
    
        return new Map<String, List<OP4I_Entitlement_View__c>>{
            'OneTime' => oneTime,
            'Other'   => others
        };
    }
    
    public static SBQQ__Subscription__c buildOneTimeSub(OP4I_Entitlement_View__c entitlement) {
        Nebula.Logger.info('Building one-time subscription for entitlement: ' + entitlement.Id);
        SBQQ__Subscription__c sub = new SBQQ__Subscription__c();
        sub.SBQQ__Account__c = entitlement.Account__c;
        sub.SBQQ__Product__c = entitlement.DLI_Product__c;
        sub.SBQQ__Contract__c = entitlement.Associated_OSA__c;
        sub.CurrencyIsoCode = entitlement.CurrencyIsoCode;
        sub.SBQQ__Quantity__c = entitlement.Quantity__c;
        sub.SBQQ__ListPrice__c = entitlement.Sale_Price__c;
        sub.SBQQ__CustomerPrice__c = entitlement.Sale_Price__c;
        sub.SBQQ__RegularPrice__c = entitlement.Sale_Price__c;
        sub.SBQQ__NetPrice__c = entitlement.Sale_Price__c;
        sub.SBQQ__SubscriptionType__c = 'One-Time';
        sub.SBQQ__ProductSubscriptionType__c = 'One-Time';
        sub.SBQQ__SubscriptionPricing__c = 'One-Time';
        sub.SBQQ__ProrateMultiplier__c = 1.0;
        sub.SBQQ__SubscriptionStartDate__c = entitlement.Start_Date__c;
        sub.SBQQ__SubscriptionEndDate__c = entitlement.End_Date__c;
        sub.DLI_Id__c = entitlement.DLI_Id__c;
        sub.DLIP_Id__c = entitlement.DLIP_Id__c;
        sub.Entitlement_Id__c = entitlement.Entitlement_Id__c;
        sub.DLIP_Product_Type__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.Product_Type__c : null;
        sub.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c;
        sub.SBQQ__ChargeType__c = (entitlement.DLI_Product__r != null) ? entitlement.DLI_Product__r.SBQQ__ChargeType__c : null;
        sub.SBQQ__BillingType__c = (entitlement.DLI_Product__r != null) ? entitlement.DLI_Product__r.SBQQ__BillingType__c : null;
        sub.Support_Level__c = entitlement.Support_Level__c;
        sub.Per_Integrations__c = entitlement.Meter_Type__c;
        sub.SBQQ__SegmentStartDate__c = entitlement.Start_Date__c;
        sub.SBQQ__SegmentEndDate__c = entitlement.End_Date__c;
        sub.OP4I_Entitlement_Id__c = entitlement.Id;
        return sub;
    }

    public static ProductOptionMaps getProductOptionMaps(Set<Id> allProductIds, Map<Id, String> mapComponentIdToBundleCodeValidPair) {
        Map<String, SBQQ__ProductOption__c> productOptionMap = new Map<String, SBQQ__ProductOption__c>();
        Map<String, Id> optionalToConfiguredParentBundleMap = new Map<String, Id>();

        if (allProductIds == null || allProductIds.isEmpty()) {
            System.debug('OP4I_OPT_MAP[empty-input]: getProductOptionMaps called with empty input');
            return new ProductOptionMaps(productOptionMap, optionalToConfiguredParentBundleMap);
        }

        System.debug('OP4I_OPT_MAP[allProductIds]: ' + allProductIds);

        List<SBQQ__ProductOption__c> options = [
            SELECT Id, SBQQ__ConfiguredSKU__c, SBQQ__OptionalSKU__c,
                SBQQ__ConfiguredSKU__r.Parent_Of_Bundle__c,
                SBQQ__ConfiguredSKU__r.ProductCode
            FROM SBQQ__ProductOption__c
            WHERE SBQQ__ConfiguredSKU__c IN :allProductIds
            OR SBQQ__OptionalSKU__c IN :allProductIds
        ];

        System.debug('OP4I_OPT_MAP[query]: Queried ' + options.size() + ' SBQQ__ProductOption__c records for ' + allProductIds.size() + ' product ids');

        for (SBQQ__ProductOption__c opt : options) {
            Id optionalSkuId = opt.SBQQ__OptionalSKU__c;
            Id configuredSkuId = opt.SBQQ__ConfiguredSKU__c;

            System.debug('OP4I_OPT_MAP[option-loop]: option.Id=' + opt.Id + ', configuredSkuId=' + configuredSkuId + ', optionalSkuId=' + optionalSkuId);

            if (optionalSkuId != null && configuredSkuId != null) {
                String key = String.valueOf(configuredSkuId) + '|' + String.valueOf(optionalSkuId);

                Boolean isParentOfBundle = opt.SBQQ__ConfiguredSKU__r != null ? opt.SBQQ__ConfiguredSKU__r.Parent_Of_Bundle__c : false;
                String productCode = opt.SBQQ__ConfiguredSKU__r != null ? opt.SBQQ__ConfiguredSKU__r.ProductCode : null;

                System.debug('OP4I_OPT_MAP[isParentOfBundle]: OptionId=' + opt.Id + ', isParentOfBundle=' + isParentOfBundle + ', productCode=' + productCode);

                if (isParentOfBundle == true && productCode != null && productCode.contains('-P') 
                    && mapComponentIdToBundleCodeValidPair.containsKey(optionalSkuId) && mapComponentIdToBundleCodeValidPair.get(optionalSkuId) == productCode) {
                    optionalToConfiguredParentBundleMap.put(optionalSkuId +''+productCode, configuredSkuId);
                    System.debug('OP4I_OPT_MAP[append-optional]: Appended optional SKU ' + optionalSkuId + ' -> configured SKU ' + configuredSkuId);
                    
                    productOptionMap.put(key, opt);
                }
                System.debug('OP4I_OPT_MAP[append-option]: Appended product option for key ' + key + ', id ' + opt.Id);
            } else {
                System.debug('OP4I_OPT_MAP[skipped-option]: option.Id=' + opt.Id + ' skipped due to null configuredSkuId or optionalSkuId');
            }
        }

        System.debug('OP4I_OPT_MAP[productOptionMap-keys]: ' + productOptionMap.keySet());
        System.debug('OP4I_OPT_MAP[optionalToConfiguredParentBundleMap-keys]: ' + optionalToConfiguredParentBundleMap.keySet());

        return new ProductOptionMaps(productOptionMap, optionalToConfiguredParentBundleMap);
    }

    /**
     * Update Contracts' StartDate, EndDate, and Migration_Status__c for provided contractIds.
     */
    public static void updateContracts(List<OP4I_Entitlement_View__c> entitlements, String migrationStatus) {
        if (entitlements == null || entitlements.isEmpty()) return;
    
        Set<Id> contractIds = new Set<Id>();
        Map<Id, List<OP4I_Entitlement_View__c>> contractToEntsMap = new Map<Id, List<OP4I_Entitlement_View__c>>();
    
        for (OP4I_Entitlement_View__c ent : entitlements) {
            if (ent.Associated_OSA__c == null) continue;
    
            contractIds.add(ent.Associated_OSA__c);
            if (!contractToEntsMap.containsKey(ent.Associated_OSA__c)) {
                contractToEntsMap.put(ent.Associated_OSA__c, new List<OP4I_Entitlement_View__c>());
            }
            contractToEntsMap.get(ent.Associated_OSA__c).add(ent);
        }

        Map<Id, AggregateResult> contractAgg = new Map<Id, AggregateResult>();
        for (AggregateResult ar : [
            SELECT Associated_OSA__c contractId,
                   MIN(Start_Date__c) minStart,
                   MAX(End_Date__c) maxEnd
            FROM OP4I_Entitlement_View__c
            WHERE Associated_OSA__c IN :contractIds
            GROUP BY Associated_OSA__c
        ]) {
            contractAgg.put((Id)ar.get('contractId'), ar);
        }
    
        Id activePriceBookId = getCurrentPricebookId();
        List<Contract> contractToUpdate = new List<Contract>();
    
        for (Id cid : contractAgg.keySet()) {
            AggregateResult ar = contractAgg.get(cid);
            List<OP4I_Entitlement_View__c> ents = contractToEntsMap.get(cid);
    
            OP4I_Entitlement_View__c ent = ents != null && !ents.isEmpty() ? ents[0] : null;
    
            Contract c = new Contract(
                Id = cid,
                StartDate = (Date)ar.get('minStart'),
                EndDate = (Date)ar.get('maxEnd'),
                Migration_Status__c = migrationStatus
            );
    
            if (ent != null) {
                c.Shipping_Account__c = ent.Associated_OSA__r?.OSA_Customer_Name__c;
                c.OSA_Number__c = ent.Associated_OSA__r?.ContractNumber;
                c.Line_of_Business__c = ent.Line_of_Business__c;
                c.CurrencyIsoCode = ent.CurrencyIsoCode;
                if(ent.Associated_OSA__r.SBQQ__Quote__c != null){
                    c.Legacy_Quote_Id__c = ent.Associated_OSA__r.SBQQ__Quote__c;
                    c.SBQQ__Quote__c = null;
                }
                if(ent.Associated_OSA__r.SBQQ__Opportunity__c != null){
                    c.SBQQ__Opportunity__c = null;
                }
                c.SBQQ__RenewalPricebookId__c = activePriceBookId;
                c.SBQQ__AmendmentPricebookId__c = activePriceBookId;
                c.SBQQ__RenewalTerm__c = 12;
                c.Deal_Type__c = ent.Deal_Type__c;
    
                if (ent.Associated_OSA__r?.Deal_Type__c == 'Renewal') {
                    c.Software_Payment_Terms__c = ent.Renewal_Payment_Terms__c;
                    c.BillingFrequency__c = ent.Renewal_Billing_Frequency__c;
                } else {
                    c.Software_Payment_Terms__c = ent.Payment_Terms__c;
                    c.BillingFrequency__c = ent.Billing_Frequency__c;
                }
            }
    
            contractToUpdate.add(c);
        }
    
        if (!contractToUpdate.isEmpty()) {
            try {
                SBQQ.TriggerControl.disable();
                update contractToUpdate;
                SBQQ.TriggerControl.enable();
            } catch (Exception ex) {}
        }
    } 
    /**
     * Build a standalone SBQQ__Subscription__c from an entitlement.
     */
    public static SBQQ__Subscription__c buildStandaloneSub(OP4I_Entitlement_View__c row, Map<String, Id> dimensionMap) {
        SBQQ__Subscription__c sub = new SBQQ__Subscription__c();
        sub.SBQQ__Account__c = row.Account__c;
        sub.SBQQ__Contract__c = row.Associated_OSA__c;
        sub.SBQQ__Product__c = row.DLI_Product__c;
        sub.SBQQ__Bundle__c = false;
        sub.Parent_Of_Bundle__c = false;
        sub.CPQ_Option_Type__c = null;
        sub.SBQQ__SubscriptionStartDate__c = row.Start_Date__c;
        sub.SBQQ__SubscriptionEndDate__c = row.End_Date__c;
        sub.SBQQ__Quantity__c = row.Quantity__c;
        sub.SBQQ__RenewalQuantity__c = row.Quantity__c;
        sub.SBQQ__ListPrice__c = row.DLI_Price__c;
        sub.SBQQ__NetPrice__c = row.DLI_Price__c - (row.Additional_Discount__c != null ? row.Additional_Discount__c : 0);
        sub.SBQQ__RegularPrice__c = row.DLI_Price__c;
        sub.SBQQ__CustomerPrice__c = row.DLI_Price__c;
        sub.SBQQ__AdditionalDiscountAmount__c = row.Additional_Discount__c;
        sub.Support_Level__c = row.Support_Level__c;
        sub.Per_Integrations__c = row.Meter_Type__c;
        sub.CurrencyIsoCode = row.CurrencyIsoCode;
        sub.SBQQ__SegmentKey__c = sub.SBQQ__Product__c + '|' + String.valueOf(row.Product_Instance__c);
        if (row.Segment_Index__c != null)
            sub.SBQQ__SegmentLabel__c = 'Year  ' + row.Segment_Index__c;
        sub.SBQQ__SegmentQuantity__c = row.Quantity__c;
        sub.SBQQ__ProrateMultiplier__c = row.Subscription_Term__c;
        sub.SBQQ__SegmentIndex__c = row.Segment_Index__c;
        sub.SBQQ__SegmentStartDate__c = row.Start_Date__c;
        sub.SBQQ__SegmentEndDate__c = row.End_Date__c;
        if (row.DLI_Product__r != null) {
            sub.SBQQ__BillingType__c             = row.DLI_Product__r.SBQQ__BillingType__c;
            sub.SBQQ__ChargeType__c              = row.DLI_Product__r.SBQQ__ChargeType__c;
            sub.SBQQ__SubscriptionPricing__c     = row.DLI_Product__r.SBQQ__SubscriptionPricing__c;
            sub.SBQQ__ProductSubscriptionType__c = row.DLI_Product__r.SBQQ__SubscriptionType__c;
            sub.SBQQ__SubscriptionType__c        = row.DLI_Product__r.SBQQ__SubscriptionType__c;
            sub.SBQQ__PricingMethod__c           = row.DLI_Product__r.SBQQ__PricingMethod__c;
            if (row.DLI_Product__r.SBQQ__ChargeType__c != 'One-Time' && row.CurrencyIsoCode != null && row.DLI_Product__c != null) {
                String key = row.CurrencyIsoCode + row.DLI_Product__c;
                sub.SBQQ__Dimension__c = (dimensionMap != null) ? dimensionMap.get(key) : null;
            }
        }
        sub.DLI_Id__c = row.DLI_Id__c;
        sub.DLIP_Id__c = row.DLIP_Id__c;
        sub.Entitlement_Id__c = row.Entitlement_Id__c;
        sub.DLIP_Product_Type__c = (row.DLIP_Product__r != null) ? row.DLIP_Product__r.Product_Type__c : null;
        sub.OP4I_Entitlement_Id__c = row.Id;
        sub.Originating_Deal_ID__c = row.OP4I_Deal_Id__c;
        sub.SBQQ__Number__c = Integer.valueOf(row.Segment_Index__c);
        sub.DLI_Price__c  = row.Sale_Price__c;
        return sub;
    }

    /**
     * Build a parent bundle SBQQ__Subscription__c for the given bundleRows.
     * Uses optionalToConfiguredParentBundleMap (optional SKU -> configured SKU) to select the parent bundle product.
     * Sets bundleSub.Parent_Of_Bundle__c according to whether a bundle product was found.
     */
    public static SBQQ__Subscription__c buildParentBundleSub(
        List<OP4I_Entitlement_View__c> bundleRows,
        Map<String, SBQQ__ProductOption__c> productOptionMap, // still required for compatibility
        List<OP4I_Entitlement_View__c> entitlementsToUpdate,
        Set<Contract> contractsToUpdate,
        Integer[] entitlementsProcessedCounter,
        Map<String, Id> dimensionMap,
        Map<String, Id> optionalConfiguredParentBundleMapNew
    ) {
        if (bundleRows == null || bundleRows.isEmpty()) return null;
        OP4I_Entitlement_View__c primary = bundleRows[0];

        // Default to using DLI_Product__c
        Id selectedBundleProdId = primary.DLI_Product__c;
        Boolean isParentOfBundle = false;

        // Use the static optionalConfiguredParentBundleMap if available and a mapping exists for this optional SKU
        if (
            optionalConfiguredParentBundleMapNew != null &&
            primary.DLI_Product__c != null &&
            optionalConfiguredParentBundleMapNew.containsKey(primary.DLI_Product__c+''+primary.DLI_Product__r.ProductCode+'-P')
        ) {
            Id configuredSkuId = optionalConfiguredParentBundleMapNew.get(primary.DLI_Product__c+''+primary.DLI_Product__r.ProductCode+'-P');
            if (configuredSkuId != null) {
                selectedBundleProdId = configuredSkuId;
                isParentOfBundle = true;
            }
        }

        Date startDate = primary.Start_Date__c, endDate = primary.End_Date__c;
        for (OP4I_Entitlement_View__c row : bundleRows) {
            if (row.Start_Date__c != null && (startDate == null || row.Start_Date__c < startDate)) startDate = row.Start_Date__c;
            if (row.End_Date__c != null && (endDate == null || row.End_Date__c > endDate)) endDate = row.End_Date__c;
        }
        SBQQ__Subscription__c bundleSub = new SBQQ__Subscription__c();
        bundleSub.SBQQ__Account__c                = primary.Account__c;
        bundleSub.Originating_Deal_ID__c          = primary.OP4I_Deal_Id__c;
        bundleSub.SBQQ__Contract__c               = primary.Associated_OSA__c;
        bundleSub.SBQQ__Product__c                = selectedBundleProdId;
        bundleSub.SBQQ__Quantity__c               = 1;
        bundleSub.SBQQ__RenewalQuantity__c        = 1;
        bundleSub.SBQQ__NetPrice__c               = 0;
        bundleSub.SBQQ__ListPrice__c              = 0;
        bundleSub.SBQQ__RegularPrice__c           = 0;
        bundleSub.SBQQ__CustomerPrice__c          = 0;
        bundleSub.DLI_Price__c                    = null;
        if (primary.DLI_Product__r != null) {
            bundleSub.SBQQ__SubscriptionPricing__c     = primary.DLI_Product__r.SBQQ__SubscriptionPricing__c;
            bundleSub.SBQQ__ProductSubscriptionType__c = primary.DLI_Product__r.SBQQ__SubscriptionType__c;
            bundleSub.SBQQ__SubscriptionType__c        = primary.DLI_Product__r.SBQQ__SubscriptionType__c;
            bundleSub.SBQQ__ChargeType__c              = primary.DLI_Product__r.SBQQ__ChargeType__c;
            bundleSub.SBQQ__BillingType__c             = primary.DLI_Product__r.SBQQ__BillingType__c;
            bundleSub.SBQQ__PricingMethod__c           = primary.DLI_Product__r.SBQQ__PricingMethod__c;
        }
        bundleSub.SBQQ__SubscriptionStartDate__c    = startDate;
        bundleSub.SBQQ__SubscriptionEndDate__c      = endDate;
        bundleSub.DLI_Id__c                        = primary.DLI_Id__c;
        bundleSub.DLIP_Id__c                       = primary.DLIP_Id__c;
        bundleSub.Entitlement_Id__c                = primary.Entitlement_Id__c;
        bundleSub.DLIP_Product_Type__c             = (primary.DLIP_Product__r != null) ? primary.DLIP_Product__r.Product_Type__c : null;
        bundleSub.SBQQ__SegmentIndex__c            = null;
        bundleSub.SBQQ__SegmentKey__c              = null;
        bundleSub.SBQQ__SegmentLabel__c            = null;
        bundleSub.SBQQ__SegmentQuantity__c         = null;
        bundleSub.SBQQ__SegmentStartDate__c        = null;
        bundleSub.SBQQ__SegmentEndDate__c          = null;
        bundleSub.SBQQ__ProrateMultiplier__c       = null;
        bundleSub.SBQQ__Dimension__c               = null;
        bundleSub.CurrencyIsoCode                  = primary.CurrencyIsoCode;
        bundleSub.Support_Level__c                 = null;
        bundleSub.Per_Integrations__c              = null;
        bundleSub.SBQQ__Bundle__c                  = true;
        bundleSub.Parent_Of_Bundle__c              = isParentOfBundle;
        bundleSub.CPQ_Option_Type__c               = null;
        bundleSub.OP4I_Entitlement_Id__c = primary.Id;
        for (OP4I_Entitlement_View__c entitlement : bundleRows) {
            entitlement.Processing_Status__c = 'Parent Subscription Created';
            entitlementsToUpdate.add(entitlement);
            if (entitlement.Associated_OSA__r != null) {
                entitlement.Associated_OSA__r.Processing_Status__c = 'Parent Subscription Created';
                contractsToUpdate.add(entitlement.Associated_OSA__r);
            }
            if (entitlementsProcessedCounter != null && entitlementsProcessedCounter.size() > 0)
                entitlementsProcessedCounter[0]++;
        }
        return bundleSub;
    }

        /**
     * Build a segmented bundle subscription for a single row (used in segment bundle batching).
     * Accepts productOptionMap and optionalConfiguredParentBundleMap as arguments.
     */
    public static SBQQ__Subscription__c buildSegmentedBundleSub(
        OP4I_Entitlement_View__c entitlement,
        Id bundleProdId,
        Map<String, Id> dimentionMap,
        Map<String, Id> productPricebookEntryMap,
        Map<String, Date> mapOfContractToEndDate,
        Map<String, SBQQ__Subscription__c> mapOfDateToQLE,
        Map<String, SBQQ__ProductOption__c> productOptionMap,
        Map<String, Id> optionalConfiguredParentBundleMap 
    ) {
        SBQQ__Subscription__c sub = new SBQQ__Subscription__c();
        sub.SBQQ__Account__c = entitlement.Account__c;
        sub.Originating_Deal_ID__c = entitlement.OP4I_Deal_Id__c;
        sub.SBQQ__Contract__c = entitlement.Associated_OSA__c;
        sub.SBQQ__Product__c = (bundleProdId != null) ? bundleProdId : entitlement.DLI_Product__c;
        sub.SBQQ__Quantity__c = entitlement.Quantity__c;
        sub.SBQQ__RenewalQuantity__c = entitlement.Quantity__c;
        sub.SBQQ__NetPrice__c = entitlement.DLI_Price__c;
        sub.SBQQ__ListPrice__c = entitlement.DLI_Price__c;
        sub.SBQQ__RegularPrice__c = entitlement.DLI_Price__c;
        sub.SBQQ__CustomerPrice__c = entitlement.DLI_Price__c;
        sub.DLI_Price__c = entitlement.DLI_Price__c;
        sub.SBQQ__Number__c = (entitlement.Segment_Index__c != null) ? Integer.valueOf(entitlement.Segment_Index__c) : null;
        
        if (entitlement.DLI_Product__r != null) {
            sub.SBQQ__SubscriptionPricing__c     = entitlement.DLI_Product__r.SBQQ__SubscriptionPricing__c;
            sub.SBQQ__ProductSubscriptionType__c = entitlement.DLI_Product__r.SBQQ__SubscriptionType__c;
            sub.SBQQ__SubscriptionType__c        = entitlement.DLI_Product__r.SBQQ__SubscriptionType__c;
            sub.SBQQ__ChargeType__c              = entitlement.DLI_Product__r.SBQQ__ChargeType__c;
            sub.SBQQ__BillingType__c             = entitlement.DLI_Product__r.SBQQ__BillingType__c;
            
            if (entitlement.DLI_Product__r.SBQQ__ChargeType__c != 'One-Time' && entitlement.CurrencyIsoCode != null && entitlement.DLI_Product__c != null) {
                String key = entitlement.CurrencyIsoCode + entitlement.DLI_Product__c;
                sub.SBQQ__Dimension__c = (dimentionMap != null) ? dimentionMap.get(key) : null;
            }
        }
        
        sub.SBQQ__SubscriptionStartDate__c = entitlement.Start_Date__c;
        sub.SBQQ__SubscriptionEndDate__c = (mapOfContractToEndDate != null && entitlement.Associated_OSA__c != null) ?
            mapOfContractToEndDate.get(entitlement.Associated_OSA__c) : entitlement.End_Date__c;
        sub.DLI_Id__c = entitlement.DLI_Id__c;
        sub.DLIP_Id__c = entitlement.DLIP_Id__c;
        sub.Entitlement_Id__c = entitlement.Entitlement_Id__c;
        sub.DLIP_Product_Type__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.Product_Type__c : null;
        sub.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c;
        sub.CurrencyIsoCode = entitlement.CurrencyIsoCode;
        sub.Support_Level__c = entitlement.Support_Level__c;
        sub.Per_Integrations__c = entitlement.Meter_Type__c;
        sub.SBQQ__Bundle__c = true;
        sub.Parent_Of_Bundle__c = false;
        sub.CPQ_Option_Type__c = 'Static Bundle';
        
        if (entitlement.Segment_Index__c != null) {
            String key = sub.CurrencyIsoCode + sub.SBQQ__Product__c;
            if (entitlement.DLI_Product__r != null && entitlement.DLI_Product__r.SBQQ__ChargeType__c != 'One-Time') {
                sub.SBQQ__Dimension__c = (dimentionMap != null) ? dimentionMap.get(key) : null;
            }
            sub.SBQQ__SegmentKey__c = sub.SBQQ__Product__c + '|' + String.valueOf(entitlement.Product_Instance__c);
            sub.SBQQ__SegmentLabel__c = 'Year  ' + entitlement.Segment_Index__c;
            sub.SBQQ__SegmentQuantity__c = entitlement.Quantity__c;
            sub.SBQQ__SegmentStartDate__c = entitlement.Start_Date__c;
            sub.SBQQ__SegmentEndDate__c = entitlement.End_Date__c;
        }
        
        sub.SBQQ__ProrateMultiplier__c = entitlement.Subscription_Term__c;
        sub.SBQQ__RootId__c = entitlement.Parent_Subscription__c;
        sub.SBQQ__RequiredById__c = entitlement.Parent_Subscription__c;
        
        if (entitlement.Parent_Subscription__c != null && mapOfDateToQLE != null && mapOfDateToQLE.containsKey(entitlement.Parent_Subscription__c)) {
            SBQQ__Subscription__c parentSub = mapOfDateToQLE.get(entitlement.Parent_Subscription__c);
            if (parentSub != null && parentSub.SBQQ__Product__c != null) {
                sub.SBQQ__RequiredByProduct__c = parentSub.SBQQ__Product__c;
            }
        }
        
        if (entitlement.DLI_Product__c != null && entitlement.DLIP_Product__c != null
            && optionalConfiguredParentBundleMap != null && productOptionMap != null) {
                
                Id configuredParentId = optionalConfiguredParentBundleMap.get(entitlement.DLI_Product__c+''+entitlement.DLI_Product__r.ProductCode+'-P');
                
                if (configuredParentId != null) {
                    String optionKey = configuredParentId + '|' + entitlement.DLI_Product__c;
                    if (productOptionMap.containsKey(optionKey)) {
                        SBQQ__ProductOption__c option = productOptionMap.get(optionKey);
                        sub.SBQQ__ProductOption__c = option.Id;
                    }
                }
            }
        
        sub.SBQQ__PricingMethod__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.SBQQ__PricingMethod__c : null;
        sub.OP4I_Entitlement_Id__c = entitlement.Id;
        //Add List Price derivation here as well
        if (entitlement.Additional_Discount__c != null) {
            sub.SBQQ__AdditionalDiscountAmount__c = entitlement.Additional_Discount__c;
        }
        return sub;
    }

    /**
     * Build a child/component subscription for a single entitlement row.
     * Accepts productOptionMap and optionalConfiguredParentBundleMap as arguments.
     */
    public static SBQQ__Subscription__c buildComponentSub(
        OP4I_Entitlement_View__c entitlement,
        Id parentSubscriptionId,
        Map<String, Id> dimentionMap,
        Map<String, Id> productPricebookEntryMap,
        Map<String, Date> mapOfContractToEndDate,
        Map<String, SBQQ__Subscription__c> mapOfDateToQLE,
        Map<String, SBQQ__ProductOption__c> productOptionMap,
        Map<String, Id> optionalConfiguredParentBundleMap
    ) {
        SBQQ__Subscription__c subscriptionChild = new SBQQ__Subscription__c();
        subscriptionChild.SBQQ__Account__c = entitlement.Account__c;
        subscriptionChild.Originating_Deal_ID__c = entitlement.OP4I_Deal_Id__c;
        subscriptionChild.SBQQ__Contract__c = entitlement.Associated_OSA__c;
        subscriptionChild.SBQQ__RootId__c = entitlement.Parent_Subscription__c;
        subscriptionChild.SBQQ__Product__c = entitlement.DLIP_Product__c;
        subscriptionChild.SBQQ__Number__c = (entitlement.Segment_Index__c != null) ? Integer.valueOf(entitlement.Segment_Index__c) : null;
        subscriptionChild.SBQQ__Quantity__c = entitlement.Quantity__c;
        subscriptionChild.SBQQ__RenewalQuantity__c = entitlement.Quantity__c;
        
        // Hardcoded pricing fields
        subscriptionChild.SBQQ__ListPrice__c = 0;
        subscriptionChild.SBQQ__CustomerPrice__c = 0;
        subscriptionChild.SBQQ__NetPrice__c = 0;
        subscriptionChild.SBQQ__RegularPrice__c = 0;
        subscriptionChild.DLI_Price__c = null;
        
        if (entitlement.Additional_Discount__c != null)
            subscriptionChild.SBQQ__AdditionalDiscountAmount__c = entitlement.Additional_Discount__c;
        
        subscriptionChild.SBQQ__PricingMethod__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.SBQQ__PricingMethod__c : null;
        subscriptionChild.SBQQ__SubscriptionPricing__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.SBQQ__SubscriptionPricing__c : null;
        subscriptionChild.SBQQ__ProductSubscriptionType__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.SBQQ__SubscriptionType__c : null;
        subscriptionChild.SBQQ__SubscriptionType__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.SBQQ__SubscriptionType__c : null;
        subscriptionChild.SBQQ__SubscriptionStartDate__c = entitlement.Start_Date__c;
        subscriptionChild.SBQQ__SubscriptionEndDate__c = (mapOfContractToEndDate != null && entitlement.Associated_OSA__c != null) ?
            mapOfContractToEndDate.get(entitlement.Associated_OSA__c) : entitlement.End_Date__c;
        subscriptionChild.SBQQ__RequiredById__c = entitlement.Parent_Subscription__c;
        subscriptionChild.SBQQ__RequiredByProduct__c = null;
        
        subscriptionChild.DLI_Id__c = entitlement.DLI_Id__c;
        subscriptionChild.DLIP_Id__c = entitlement.DLIP_Id__c;
        subscriptionChild.Entitlement_Id__c = entitlement.Entitlement_Id__c;
        subscriptionChild.DLIP_Product_Type__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.Product_Type__c : null;
        subscriptionChild.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c;
        subscriptionChild.SBQQ__ChargeType__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.SBQQ__ChargeType__c : null;
        subscriptionChild.SBQQ__BillingType__c = (entitlement.DLIP_Product__r != null) ? entitlement.DLIP_Product__r.SBQQ__BillingType__c : null;
        subscriptionChild.Support_Level__c = entitlement.Support_Level__c;
        subscriptionChild.Per_Integrations__c = entitlement.Meter_Type__c;
        subscriptionChild.CurrencyIsoCode = entitlement.CurrencyIsoCode;
        
        if (entitlement.Segment_Index__c != null) {
            String key = subscriptionChild.CurrencyIsoCode + subscriptionChild.SBQQ__Product__c;
            if (entitlement.DLIP_Product__r != null && entitlement.DLIP_Product__r.SBQQ__ChargeType__c != 'One-Time') {
                subscriptionChild.SBQQ__Dimension__c = (dimentionMap != null) ? dimentionMap.get(key) : null;
            }
            subscriptionChild.SBQQ__SegmentKey__c = subscriptionChild.SBQQ__Product__c + '|' + String.valueOf(entitlement.Product_Instance__c);
            subscriptionChild.SBQQ__SegmentLabel__c = 'Year  ' + entitlement.Segment_Index__c;
            subscriptionChild.SBQQ__SegmentQuantity__c = entitlement.Quantity__c;
            subscriptionChild.SBQQ__SegmentStartDate__c = entitlement.Start_Date__c;
            subscriptionChild.SBQQ__SegmentEndDate__c = entitlement.End_Date__c;
        }
        
        subscriptionChild.SBQQ__ProrateMultiplier__c = entitlement.Subscription_Term__c;
        
        if (entitlement.Parent_Subscription__c != null && mapOfDateToQLE != null && mapOfDateToQLE.containsKey(entitlement.Parent_Subscription__c)) {
            SBQQ__Subscription__c parentSub = mapOfDateToQLE.get(entitlement.Parent_Subscription__c);
            if (parentSub != null && parentSub.SBQQ__Product__c != null) {
                subscriptionChild.SBQQ__RequiredByProduct__c = parentSub.SBQQ__Product__c;
            }
        }
        
        if (entitlement.DLI_Product__c != null && entitlement.DLIP_Product__c != null
            && optionalConfiguredParentBundleMap != null && productOptionMap != null) {
                
                Id configuredParentId = optionalConfiguredParentBundleMap.get(entitlement.DLIP_Product__c+''+entitlement.DLI_Product__r.ProductCode+'-P');
                
                if (configuredParentId != null) {
                    String optionKey = configuredParentId + '|' + entitlement.DLIP_Product__c;
                    if (productOptionMap.containsKey(optionKey)) {
                        SBQQ__ProductOption__c option = productOptionMap.get(optionKey);
                        subscriptionChild.SBQQ__ProductOption__c = option.Id;
                    }
                }
            }
        
        subscriptionChild.SBQQ__Bundle__c = true;
        subscriptionChild.CPQ_Option_Type__c = 'Static Component';
        subscriptionChild.OP4I_Entitlement_Id__c = entitlement.Id;
        return subscriptionChild;
    }

    /**
     * Send a summary email at the end of batch job.
     */
    public static void sendSummaryEmail(
        List<String> emailAddresses,
        String batchName,
        Integer recordsCreated,
        Integer recordsUpdated,
        Integer recordsErrored,
        Integer entitlementsProcessed,
        Integer entitlementsErrored,
        List<String> errorDetails
    ) {
        if(emailAddresses == null || emailAddresses.isEmpty()) return;
        String subject = batchName + ' Migration Summary';
        String body = 'Migration Process Summary for ' + batchName + ':\n\n';
        body += 'Number of Subscriptions Created: ' + recordsCreated + '\n';
        body += 'Number of Contracts Updated: ' + recordsUpdated + '\n';
        body += 'Number of OP4I Entitlement View Records Processed Successfully: ' + entitlementsProcessed + '\n';
        body += 'Number of OP4I Entitlement View Records Errored: ' + entitlementsErrored + '\n';
        body += 'Number of Errors: ' + recordsErrored + '\n\n';
        if (!errorDetails.isEmpty()) {
            body += 'Error Details:\n';
            body += String.join(errorDetails, '\n');
        }
        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(emailAddresses);
            mail.setSubject(subject);
            mail.setPlainTextBody(body);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch(Exception e) {}
    }
}