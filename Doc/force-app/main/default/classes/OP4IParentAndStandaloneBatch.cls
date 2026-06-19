global class OP4IParentAndStandaloneBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Set<Id> touchedContractIds = new Set<Id>();
    // FIX: Use a map to avoid duplicate IDs during update
    private Map<Id, OP4I_Entitlement_View__c> allEntitlementsToUpdateMap = new Map<Id, OP4I_Entitlement_View__c>();
    private List<String> emailAddresses;
    private List<String> lstOfContractAssignment;
    private Integer recordsCreated = 0;
    private Integer recordsUpdated = 0;
    private Integer recordsErrored = 0;
    private Integer entitlementsProcessed = 0;
    private Integer entitlementsErrored = 0;
    private List<String> errorDetails = new List<String>();
    public Set<Id> allProductIds = new Set<Id>();
    public Map<Id, String> mapComponentIdToBundleCodeValidPair = new Map<Id, String>();
    private String originalTransactionId;

    global OP4IParentAndStandaloneBatch() {}

    global OP4IParentAndStandaloneBatch(List<String> lstOfContractNumbers, List<String> emails) {
        this.lstOfContractAssignment = lstOfContractNumbers;
        this.emailAddresses = emails;
    }

    public OP4IParentAndStandaloneBatch(List<String> emails) {
        this.emailAddresses = emails;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        this.originalTransactionId = 'BatchStart-' + String.valueOf(Datetime.now().getTime());
        String endCondition;
        if (lstOfContractAssignment != null && !lstOfContractAssignment.isEmpty()) {
            for (String endDigit : lstOfContractAssignment) {
                endCondition = endCondition != null 
                    ? (endCondition + ' OR ContractNumber like \'%' + endDigit + '\'') 
                    : ' ContractNumber like \'%' + endDigit + '\'';
            }
        }
        String query = 'SELECT Id FROM Contract WHERE Migration_Status__c = \'Ready\'';
        query = endCondition != null ? query + ' AND (' + endCondition + ')' : query;
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<Contract> contracts) {
        if (contracts.isEmpty()) return;
        Set<Id> contractIds = new Set<Id>();
        for (Contract c : contracts) contractIds.add(c.Id);

        List<OP4I_Entitlement_View__c> entitlements = [
            SELECT Id, DLIP_Id__c, DLI_Id__c, Account__c, Total_Contract_Months__c, One_Time_Credit__c, Billing_Frequency__c, DLI_Price__c, Subscription_Term__c,
                Associated_OSA__r.SBQQ__RenewalTerm__c, Associated_OSA__r.AccountId, Quantity__c, Start_Date__c, End_Date__c, Associated_OSA__c, Include_in_Select_Bundle__c, Product_Instance__c,
                DLI_Product__r.Product_Type__c, DLIP_Product__r.Product_Type__c, Associated_OSA__r.Shipping_Account__c, OP4I_Deal_Id__c, Account__r.Name, Associated_OSA__r.ContractNumber,
                Processing_Status__c, DLI_Product__r.SBQQ__SubscriptionPricing__c, DLIP_Product__r.SBQQ__SubscriptionPricing__c, Error_Log__c, DLI_Product__r.SBQQ__SubscriptionTerm__c, Deal_Type__c,
                DLI_Product__c, DLI_Product__r.SBQQ__BillingType__c, DLIP_Product__r.SBQQ__BillingType__c, DLI_Product__r.SBQQ__ChargeType__c, DLIP_Product__r.SBQQ__ChargeType__c, CurrencyIsoCode,
                DLIP_Product__c, Entitlement_Id__c, Sale_Price__c, Meter_Type__c, Segment_Index__c, Associated_OSA__r.Migration_Status__c, Support_Level__c, DLIP_Product__r.SBQQ__SubscriptionType__c,
                Associated_OSA__r.Deal_Type__c, Line_of_Business__c, Associated_OSA__r.OSA_Customer_Name__c, DLI_Product__r.SBQQ__SubscriptionType__c, Associated_OSA__r.Processing_Status__c,
                DLI_Product__r.SBQQ__PricingMethod__c, Associated_OSA__r.SBQQ__Quote__c, Parent_Subscription__c, DLIP_Product__r.SBQQ__PricingMethod__c, Additional_Discount__c, Software_License_Term__c, Associated_OSA__r.OSA_Number__c,
                Associated_OSA__r.Line_of_Business__c, Associated_OSA__r.Software_Payment_Terms__c, Associated_OSA__r.BillingFrequency__c, Associated_OSA__r.Software_Days_Payment_Due_Renewal__c,
                Associated_OSA__r.Software_Billing_Frequency_Renewal__c, Renewal_Payment_Terms__c, Renewal_Billing_Frequency__c, Payment_Terms__c, DLI_Product__r.ProductCode, DLIP_Product__r.ProductCode,
                Associated_OSA__r.SBQQ__Opportunity__c
            FROM OP4I_Entitlement_View__c
            WHERE Associated_OSA__c IN :contractIds
              AND (Processing_Status__c = null OR Processing_Status__c = 'Ready')
            ORDER BY DLI_Product__c ASC
        ];

        Set<String> currencySet = new Set<String>();
        Set<Id> productIds = new Set<Id>();
        for (OP4I_Entitlement_View__c e : entitlements) {
            if (e.CurrencyIsoCode != null) currencySet.add(e.CurrencyIsoCode);
            if (e.DLI_Product__c != null) productIds.add(e.DLI_Product__c);
        }
        Map<String, Id> dimensionMap = new Map<String, Id>();
        for (SBQQ__Dimension__c dim : [
            SELECT Id, CurrencyIsoCode, SBQQ__Product__c
            FROM SBQQ__Dimension__c
            WHERE CurrencyIsoCode IN :currencySet AND SBQQ__Product__c IN :productIds
        ]) {
            String key = dim.CurrencyIsoCode + dim.SBQQ__Product__c;
            dimensionMap.put(key, dim.Id);
        }

        //BIZ-69719 : One-time entitlements
        Map<String, List<OP4I_Entitlement_View__c>> splitResult = OP4ISubscriptionMigrationHelper.splitByChargeType(entitlements);
        List<OP4I_Entitlement_View__c> oneTimeEnts = splitResult.get('OneTime') != null ? splitResult.get('OneTime') : new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> nonOneTimeEnts = splitResult.get('Other') != null ? splitResult.get('Other') : new List<OP4I_Entitlement_View__c>();

        Map<String, List<OP4I_Entitlement_View__c>> bundleKeyMap = OP4ISubscriptionMigrationHelper.getBundleKeyMap(nonOneTimeEnts);
        List<OP4I_Entitlement_View__c> standalones = new List<OP4I_Entitlement_View__c>();
        Map<String, List<OP4I_Entitlement_View__c>> parentBundleRowsMap = new Map<String, List<OP4I_Entitlement_View__c>>();
        for (String key : bundleKeyMap.keySet()) {
            List<OP4I_Entitlement_View__c> bundleRows = bundleKeyMap.get(key);
            if (bundleRows.size() == 1) {
                standalones.add(bundleRows[0]);
            } else if (bundleRows.size() > 1) {
                parentBundleRowsMap.put(key, bundleRows);
            }
        }

        //BIZ-69719 : One-time entitlements
        if (!oneTimeEnts.isEmpty()) {
            List<SBQQ__Subscription__c> oneTimeSubs = new List<SBQQ__Subscription__c>();
            for (OP4I_Entitlement_View__c row : oneTimeEnts) {
                SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildOneTimeSub(row);
                oneTimeSubs.add(sub);
            }
            Database.SaveResult[] saveResults = Database.insert(oneTimeSubs, false);
            Integer idx = 0;
            for (OP4I_Entitlement_View__c row : oneTimeEnts) {
                Database.SaveResult sr = saveResults[idx++];
                if (sr.isSuccess()) {
                    recordsCreated++; entitlementsProcessed++;
                } else {
                    recordsErrored++; entitlementsErrored++;
                    errorDetails.add('One-Time OP4I Id ' + row.Id + ': ' + sr.getErrors()[0].getMessage());
                    Nebula.Logger.error('Error inserting one-time subscription for entitlement ' + row.Id + ': ' + sr.getErrors()[0].getMessage());
                }
                allEntitlementsToUpdateMap.put(row.Id, row);
            }
        }

        List<SBQQ__Subscription__c> standaloneSubs = new List<SBQQ__Subscription__c>();
        Map<Id, SBQQ__Subscription__c> entitlementToSub = new Map<Id, SBQQ__Subscription__c>();
        for (OP4I_Entitlement_View__c row : standalones) {
            SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildStandaloneSub(row, dimensionMap);
            standaloneSubs.add(sub);
            entitlementToSub.put(row.Id, sub);
            touchedContractIds.add(row.Associated_OSA__c);
        }
        Database.SaveResult[] srListStandalones = Database.insert(standaloneSubs, false);
        Integer idxS = 0;
        for (OP4I_Entitlement_View__c row : standalones) {
            Database.SaveResult sr = srListStandalones[idxS++];
            if (sr.isSuccess()) {
                recordsCreated++; entitlementsProcessed++;
                row.Parent_Subscription__c = null;
                row.Processing_Status__c = 'Standalone Created';
                row.Error_Log__c = null;
                entitlementToSub.get(row.Id).Id = sr.getId();
            } else {
                recordsErrored++; entitlementsErrored++;
                row.Processing_Status__c = 'Error';
                row.Error_Log__c = sr.getErrors()[0].getMessage();
                errorDetails.add('Standalone OP4I Id ' + row.Id + ': ' + sr.getErrors()[0].getMessage());
            }
            allEntitlementsToUpdateMap.put(row.Id, row);
        }

        for (List<OP4I_Entitlement_View__c> rows : parentBundleRowsMap.values()) {
            for (OP4I_Entitlement_View__c r : rows) {
                if (r.DLIP_Product__c != null) this.allProductIds.add(r.DLIP_Product__c);
                if (r.DLI_Product__c != null) this.allProductIds.add(r.DLI_Product__c);
                if(r.DLIP_Product__c != null && r.DLI_Product__c != null && r.DLIP_Product__c != r.DLI_Product__c){
                    mapComponentIdToBundleCodeValidPair.put(r.DLIP_Product__c, r.DLI_Product__r.ProductCode+'-P');
                    mapComponentIdToBundleCodeValidPair.put(r.DLI_Product__c, r.DLI_Product__r.ProductCode+'-P');
                }
            }
        }
        OP4ISubscriptionMigrationHelper.ProductOptionMaps optionMaps = OP4ISubscriptionMigrationHelper.getProductOptionMaps(this.allProductIds, mapComponentIdToBundleCodeValidPair);
        Map<String, SBQQ__ProductOption__c> productOptionMap = optionMaps.productOptionMap;
        Map<String, Id> productOptionMapNew = optionMaps.optionalConfiguredParentBundleMap;

        Map<String, SBQQ__Subscription__c> parentBundleSubs = new Map<String, SBQQ__Subscription__c>();
        Map<String, List<OP4I_Entitlement_View__c>> keyToRows = new Map<String, List<OP4I_Entitlement_View__c>>();
        for (String key : parentBundleRowsMap.keySet()) {
            List<OP4I_Entitlement_View__c> bundleRows = parentBundleRowsMap.get(key);

            List<OP4I_Entitlement_View__c> entitlementsToUpdate = new List<OP4I_Entitlement_View__c>();
            Set<Contract> contractsToUpdate = new Set<Contract>();
            Integer[] entitlementsProcessedCounter = new Integer[] {0};

            SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildParentBundleSub(
                bundleRows,
                productOptionMap,
                entitlementsToUpdate,
                contractsToUpdate,
                entitlementsProcessedCounter,
                dimensionMap, 
                productOptionMapNew
            );

            parentBundleSubs.put(key, sub);
            keyToRows.put(key, bundleRows);
            touchedContractIds.add(bundleRows[0].Associated_OSA__c);

            for (OP4I_Entitlement_View__c ent : entitlementsToUpdate)
                allEntitlementsToUpdateMap.put(ent.Id, ent);
        }
        List<SBQQ__Subscription__c> parentBundleSubList = new List<SBQQ__Subscription__c>(parentBundleSubs.values());
        Database.SaveResult[] srListParent = Database.insert(parentBundleSubList, false);
        Integer idxP = 0;
        for (String key : parentBundleSubs.keySet()) {
            Database.SaveResult sr = srListParent[idxP++];
            List<OP4I_Entitlement_View__c> bundleRows = keyToRows.get(key);
            if (sr.isSuccess()) {
                recordsCreated += bundleRows.size(); entitlementsProcessed += bundleRows.size();
                Id parentId = sr.getId();
                for (OP4I_Entitlement_View__c row : bundleRows) {
                    row.Parent_Subscription__c = parentId;
                    row.Processing_Status__c = 'Parent/Segment Created';
                    row.Error_Log__c = null;
                    allEntitlementsToUpdateMap.put(row.Id, row);
                }
            } else {
                recordsErrored += bundleRows.size(); entitlementsErrored += bundleRows.size();
                for (OP4I_Entitlement_View__c row : bundleRows) {
                    row.Processing_Status__c = 'Error';
                    row.Error_Log__c = sr.getErrors()[0].getMessage();
                    errorDetails.add('ParentBundle OP4I Id ' + row.Id + ': ' + sr.getErrors()[0].getMessage());
                    allEntitlementsToUpdateMap.put(row.Id, row);
                }
            }
        }

        // FIX: Update only unique entitlements
        if (!allEntitlementsToUpdateMap.isEmpty()) {
            SBQQ.TriggerControl.disable();
            update allEntitlementsToUpdateMap.values();
            SBQQ.TriggerControl.enable();
            recordsUpdated += allEntitlementsToUpdateMap.size();
        }

        OP4ISubscriptionMigrationHelper.updateContracts(allEntitlementsToUpdateMap.values(), 'Parent/Segment Created');
    }

    global void finish(Database.BatchableContext bc) {
        OP4ISubscriptionMigrationHelper.sendSummaryEmail(
            emailAddresses,
            'Parent/Standalone Subscriptions',
            recordsCreated,
            recordsUpdated,
            recordsErrored,
            entitlementsProcessed,
            entitlementsErrored,
            errorDetails
        );
        // Now initiate the segmented bundle/component batch, which will use getSegmentBundleKeyMap internally!
        OP4ISubscriptionMigrationHelper.ProductOptionMaps optionMaps = OP4ISubscriptionMigrationHelper.getProductOptionMaps(this.allProductIds, mapComponentIdToBundleCodeValidPair);
        OP4ISegmentedBundleAndComponentBatch batchableJob = new OP4ISegmentedBundleAndComponentBatch(
            optionMaps.productOptionMap,
            optionMaps.optionalConfiguredParentBundleMap, 
            emailAddresses,
            touchedContractIds
        );
        Database.executeBatch(batchableJob, 1);
    }
}