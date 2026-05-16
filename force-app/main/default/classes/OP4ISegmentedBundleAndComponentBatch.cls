global class OP4ISegmentedBundleAndComponentBatch implements Database.Batchable<SObject>, Database.Stateful {
    private List<String> emailAddresses;
    private Set<Id> touchedContractIds = new Set<Id>();
    // FIX: Use a map instead of a list to avoid duplicate IDs during update
    private Map<Id, OP4I_Entitlement_View__c> entitlementsToUpdateMap = new Map<Id, OP4I_Entitlement_View__c>();
    private Integer recordsCreated = 0;
    private Integer recordsUpdated = 0;
    private Integer recordsErrored = 0;
    private Integer entitlementsProcessed = 0;
    private Integer entitlementsErrored = 0;
    private List<String> errorDetails = new List<String>();
    public Map<String, SBQQ__ProductOption__c> productOptionMap;
    public Map<String, Id> optionalConfiguredParentBundleMap;
    private Set<Id> touchedContractIdsFromParent = new Set<Id>();
    private String originalTransactionId;

    public OP4ISegmentedBundleAndComponentBatch(Map<String, SBQQ__ProductOption__c> productOptionMap,
        Map<String, Id> optionalConfiguredParentBundleMap,List<String> emails, Set<Id> touchedContractIdsFromParent) {
        this.productOptionMap = productOptionMap;
        this.optionalConfiguredParentBundleMap = optionalConfiguredParentBundleMap;
        this.emailAddresses = emails;
        this.touchedContractIdsFromParent = touchedContractIdsFromParent;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = 'BatchStart-' + String.valueOf(Datetime.now().getTime());
        return Database.getQueryLocator([SELECT Id from Contract WHERE Id IN: touchedContractIdsFromParent]);
    }

    global void execute(Database.BatchableContext bc, List<Contract> lstContracts) {
        
        List<OP4I_Entitlement_View__c> rows	= [
            SELECT Id, DLIP_Id__c, DLI_Id__c, Account__c, Total_Contract_Months__c, One_Time_Credit__c, Billing_Frequency__c, DLI_Price__c, Subscription_Term__c,
                Associated_OSA__r.SBQQ__RenewalTerm__c, Associated_OSA__r.AccountId, Quantity__c, Start_Date__c, End_Date__c, Associated_OSA__c, Include_in_Select_Bundle__c, Product_Instance__c,
                DLI_Product__r.Product_Type__c, DLIP_Product__r.Product_Type__c, Associated_OSA__r.Shipping_Account__c, OP4I_Deal_Id__c, Account__r.Name, Associated_OSA__r.ContractNumber,
                Processing_Status__c, DLI_Product__r.SBQQ__SubscriptionPricing__c, DLIP_Product__r.SBQQ__SubscriptionPricing__c, Error_Log__c, DLI_Product__r.SBQQ__SubscriptionTerm__c, Deal_Type__c,
                DLI_Product__c, Associated_OSA__r.SBQQ__Quote__c, DLI_Product__r.SBQQ__BillingType__c, DLIP_Product__r.SBQQ__BillingType__c, DLI_Product__r.SBQQ__ChargeType__c, DLIP_Product__r.SBQQ__ChargeType__c, CurrencyIsoCode,
                DLIP_Product__c, Entitlement_Id__c, Sale_Price__c, Meter_Type__c, Segment_Index__c, Associated_OSA__r.Migration_Status__c, Support_Level__c, DLIP_Product__r.SBQQ__SubscriptionType__c,
                Associated_OSA__r.Deal_Type__c, Line_of_Business__c, Associated_OSA__r.OSA_Customer_Name__c, DLI_Product__r.SBQQ__SubscriptionType__c, Associated_OSA__r.Processing_Status__c,
                DLI_Product__r.SBQQ__PricingMethod__c, Parent_Subscription__c, DLIP_Product__r.SBQQ__PricingMethod__c, Additional_Discount__c, Software_License_Term__c, Associated_OSA__r.OSA_Number__c,
                Associated_OSA__r.Line_of_Business__c, Associated_OSA__r.Software_Payment_Terms__c, Associated_OSA__r.BillingFrequency__c, Associated_OSA__r.Software_Days_Payment_Due_Renewal__c,
                Associated_OSA__r.Software_Billing_Frequency_Renewal__c, Renewal_Payment_Terms__c, Renewal_Billing_Frequency__c, Payment_Terms__c,  DLI_Product__r.ProductCode, DLIP_Product__r.ProductCode,
                Associated_OSA__r.SBQQ__Opportunity__c
            FROM OP4I_Entitlement_View__c
            WHERE /*Processing_Status__c = 'Parent/Segment Created'
                  AND*/ Parent_Subscription__c != null
                  AND Associated_OSA__c IN: lstContracts
            ORDER BY DLI_Product__c ASC
        ];
        
        
        if (rows.isEmpty()) return;

        Set<Id> allProductIds = new Set<Id>();
        Map<Id, String> mapComponentIdToBundleCodeValidPair = new Map<Id, String>();
        Set<String> currencySet = new Set<String>();
        for (OP4I_Entitlement_View__c row : rows) {
            if (row.DLIP_Product__c != null) allProductIds.add(row.DLIP_Product__c);
            if (row.DLI_Product__c != null) allProductIds.add(row.DLI_Product__c);
            if (row.CurrencyIsoCode != null) currencySet.add(row.CurrencyIsoCode);
            if(row.DLIP_Product__c != null && row.DLI_Product__c != null  && row.DLIP_Product__c != row.DLI_Product__c){
                mapComponentIdToBundleCodeValidPair.put(row.DLIP_Product__c, row.DLI_Product__r.ProductCode+'-P');
                mapComponentIdToBundleCodeValidPair.put(row.DLI_Product__c, row.DLI_Product__r.ProductCode+'-P');
            }
        }
        OP4ISubscriptionMigrationHelper.ProductOptionMaps optionMaps = OP4ISubscriptionMigrationHelper.getProductOptionMaps(allProductIds, mapComponentIdToBundleCodeValidPair);
        Map<String, SBQQ__ProductOption__c> productOptionMap = optionMaps.productOptionMap;
        Map<String, Id> dimensionMap = new Map<String, Id>();
        for (SBQQ__Dimension__c dim : [
            SELECT Id, CurrencyIsoCode, SBQQ__Product__c
            FROM SBQQ__Dimension__c
            WHERE CurrencyIsoCode IN :currencySet AND SBQQ__Product__c IN :allProductIds
        ]) {
            String key = dim.CurrencyIsoCode + dim.SBQQ__Product__c;
            dimensionMap.put(key, dim.Id);
        }
        Map<String, Id> productPricebookEntryMap = new Map<String, Id>();
        Map<String, Date> mapOfContractToEndDate = new Map<String, Date>();
        // Now, for component/child lookup, use Parent_Subscription__c for mapOfDateToQLE key
        Map<String, SBQQ__Subscription__c> mapOfDateToQLE = new Map<String, SBQQ__Subscription__c>();

        Map<String, List<OP4I_Entitlement_View__c>> segmentKeyMap =
            OP4ISubscriptionMigrationHelper.getSegmentBundleKeyMap(rows);

        List<SBQQ__Subscription__c> segSubs = new List<SBQQ__Subscription__c>();
        Map<String, Id> segmentKeyToSubscriptionId = new Map<String, Id>();

        // 1. Create one segmented bundle subscription per group (per segment key)
        for (String segmentKey : segmentKeyMap.keySet()) {
            List<OP4I_Entitlement_View__c> groupedEntitlements = segmentKeyMap.get(segmentKey);
            if (groupedEntitlements == null || groupedEntitlements.isEmpty()) continue;

            OP4I_Entitlement_View__c firstRow = groupedEntitlements[0];
            system.debug('=====groupedEntitlements='+groupedEntitlements);
            SBQQ__Subscription__c segSub = OP4ISubscriptionMigrationHelper.buildSegmentedBundleSub(
                firstRow,
                null,
                dimensionMap,
                productPricebookEntryMap,
                mapOfContractToEndDate,
                mapOfDateToQLE,
                productOptionMap,
                optionalConfiguredParentBundleMap
            );
            segSubs.add(segSub);
            
            for (OP4I_Entitlement_View__c e : groupedEntitlements) {
                if (e.Associated_OSA__c != null) touchedContractIds.add(e.Associated_OSA__c);
            }
        }
        system.debug('===segSubs=='+segSubs);
        Database.SaveResult[] srListSeg = Database.insert(segSubs, false);
        Integer idxSeg = 0;
        for (String segmentKey : segmentKeyMap.keySet()) {
            Database.SaveResult sr = srListSeg[idxSeg++];
            if (sr.isSuccess()) {
                segmentKeyToSubscriptionId.put(segmentKey, sr.getId());
                for (OP4I_Entitlement_View__c row : segmentKeyMap.get(segmentKey)) {
                    recordsCreated++; entitlementsProcessed++;
                    row.Processing_Status__c = 'Segment Created';
                    row.Error_Log__c = null;
                    entitlementsToUpdateMap.put(row.Id, row); // Use Map for deduplication
                }
            } else {
                for (Database.Error err : sr.getErrors()) {
                    System.debug('Status Code: ' + err.getStatusCode());
                    System.debug('Message: ' + err.getMessage());
                    System.debug('Fields: ' + err.getFields()); // If error is field-specific
                }
                for (OP4I_Entitlement_View__c row : segmentKeyMap.get(segmentKey)) {
                    recordsErrored++; entitlementsErrored++;
                    row.Processing_Status__c = 'Error';
                    row.Error_Log__c = sr.getErrors()[0].getMessage();
                    errorDetails.add('SegmentedBundle OP4I Id ' + row.Id + ': ' + sr.getErrors()[0].getMessage());
                    entitlementsToUpdateMap.put(row.Id, row);
                }
            }
        } 

        // 3. For each entitlement, create its component (child) subscription, parented to the group's bundle sub
        List<SBQQ__Subscription__c> componentSubs = new List<SBQQ__Subscription__c>();
        // Build a lookup map for Parent_Subscription__c to the just-inserted segmented bundle sub IDs
        Map<String, SBQQ__Subscription__c> parentSubLookup = new Map<String, SBQQ__Subscription__c>();
        idxSeg = 0;
        for (String segmentKey : segmentKeyMap.keySet()) {
           If(srListSeg != null){
            Database.SaveResult sr = srListSeg[idxSeg++];
            if (sr.isSuccess()) {
                SBQQ__Subscription__c stub = new SBQQ__Subscription__c();
                stub.Id = sr.getId();
                parentSubLookup.put(segmentKey, stub);
            }
           } 
        }
        system.debug('===142===segmentKeyMap=='+segmentKeyMap);
        for (String segmentKey : segmentKeyMap.keySet()) {
            system.debug('===144===segmentKey=='+segmentKey);
            SBQQ__Subscription__c parentSub = parentSubLookup.get(segmentKey);
            system.debug('===144===segmentKeyMap.get(segmentKey)=='+segmentKeyMap.get(segmentKey));
            for (OP4I_Entitlement_View__c row : segmentKeyMap.get(segmentKey)) {
                Map<String, SBQQ__Subscription__c> childMapOfDateToQLE = new Map<String, SBQQ__Subscription__c>();
                if(row.Parent_Subscription__c != null && parentSub != null){
                    childMapOfDateToQLE.put(row.Parent_Subscription__c, parentSub);
                }
                SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildComponentSub(
                    row,
                    null,
                    dimensionMap,
                    productPricebookEntryMap,
                    mapOfContractToEndDate,
                    mapOfDateToQLE,
                    productOptionMap,
                    optionalConfiguredParentBundleMap
                );
                componentSubs.add(sub);
                if (row.Associated_OSA__c != null) touchedContractIds.add(row.Associated_OSA__c);
            }
        }
        system.debug('===componentSubs=='+componentSubs);
        Database.SaveResult[] srListComp = Database.insert(componentSubs, false);
        Integer idxComp = 0;
        for (String segmentKey : segmentKeyMap.keySet()) {
            for (OP4I_Entitlement_View__c row : segmentKeyMap.get(segmentKey)) {
                Database.SaveResult sr = srListComp[idxComp++];
                if (sr.isSuccess()) {
                    recordsCreated++; entitlementsProcessed++;
                    row.Processing_Status__c = 'Child Subscription Created';
                    row.Error_Log__c = null;
                    entitlementsToUpdateMap.put(row.Id, row);
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug('Status Code: ' + err.getStatusCode());
                        System.debug('Message: ' + err.getMessage());
                        System.debug('Fields: ' + err.getFields()); // If error is field-specific
                    }
                    recordsErrored++; entitlementsErrored++;
                    row.Processing_Status__c = 'Error';
                    row.Error_Log__c = sr.getErrors()[0].getMessage();
                    errorDetails.add('Component OP4I Id ' + row.Id + ': ' + sr.getErrors()[0].getMessage());
                    entitlementsToUpdateMap.put(row.Id, row);
                }
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        
        // FIX: Update only unique entitlements
        if (!entitlementsToUpdateMap.isEmpty()) {
            SBQQ.TriggerControl.disable();
            update entitlementsToUpdateMap.values();
            SBQQ.TriggerControl.enable();
            recordsUpdated += entitlementsToUpdateMap.size();
        }
        // touchedContractIds contract FOR UPDATE 
        OP4ISubscriptionMigrationHelper.updateContracts(entitlementsToUpdateMap.values(), 'Migrated');
        
        OP4ISubscriptionMigrationHelper.sendSummaryEmail(
            emailAddresses,
            'Segmented Bundle & Component Subscriptions',
            recordsCreated,
            recordsUpdated,
            recordsErrored,
            entitlementsProcessed,
            entitlementsErrored,
            errorDetails
        );
    }
}