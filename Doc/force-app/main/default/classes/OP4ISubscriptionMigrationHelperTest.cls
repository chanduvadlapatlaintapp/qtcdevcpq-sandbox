@isTest
private class OP4ISubscriptionMigrationHelperTest {
    
    @testSetup
    static void setupTestData() {
        List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
            new Account(Name = 'Test Account'),
            1,
            'AccountDefaults'
        );
        
        List<Contract> contracts = (List<Contract>) TestFactory.createSObjectList(
            new Contract(
                AccountId = accounts[0].Id,
                SBQQ__RenewalTerm__c = 12,
                Migration_Status__c = 'Ready',
                Processing_Status__c = 'Open',
                BillingFrequency__c = 'Annual',
                Deal_Type__c = 'New_Software',
                OSA_Number__c = 'OSA001',
                Line_of_Business__c = 'Intapp',
                OSA_Customer_Name__c = accounts[0].Id
            ),
            1,
            'ContractDefaults'
        );
        
        List<Product2> products = (List<Product2>) TestFactory.createSObjectList(
            new Product2(
                Name = 'Bundle Product',
                SBQQ__SubscriptionPricing__c = 'Fixed',
                SBQQ__SubscriptionTerm__c = 12,
                SBQQ__ChargeType__c = 'Recurring',
                SBQQ__BillingType__c = 'Advance',
                IsActive = true
            ),
            1,
            'ProductDefaults'
        );
        Product2 bundleProduct = products[0];
        
        Product2 componentProduct = (Product2) TestFactory.buildSObject(
            new Product2(
                Name = 'Component Product',
                SBQQ__SubscriptionPricing__c = 'Fixed',
                SBQQ__SubscriptionTerm__c = 12,
                SBQQ__ChargeType__c = 'Recurring',
                SBQQ__BillingType__c = 'Advance',
                IsActive = true
            ),
            'ProductDefaults'
        );
        insert componentProduct;
        
        List<SBQQ__Subscription__c> parentSubs = (List<SBQQ__Subscription__c>) TestFactory.createSObjectList(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = accounts[0].Id,
                SBQQ__Contract__c = contracts[0].Id,
                SBQQ__Product__c = bundleProduct.Id,
                SBQQ__Bundle__c = true,
                SBQQ__Quantity__c = 1
            ),
            1,
            'SBQQSubScriptionDefaults'
        );
        
        insert new List<OP4I_Entitlement_View__c>{
            (OP4I_Entitlement_View__c) TestFactory.buildSObject(
                new OP4I_Entitlement_View__c(
                    DLIP_Id__c = 101,
                    DLI_Id__c = 201,
                    Account__c = accounts[0].Id,
                    Total_Contract_Months__c = 12,
                    Billing_Frequency__c = 'Annual',
                    DLI_Price__c = 1000,
                    Subscription_Term__c = 12,
                    Quantity__c = 10,
                    Start_Date__c = Date.today(),
                    End_Date__c = Date.today().addMonths(12),
                    Associated_OSA__c = contracts[0].Id,
                    Include_in_Select_Bundle__c = true,
                    Product_Instance__c = 1234,
                    DLI_Product__c = bundleProduct.Id,
                    DLIP_Product__c = componentProduct.Id,
                    CurrencyIsoCode = 'USD',
                    Processing_Status__c = 'Parent/Segment Created',
                    Parent_Subscription__c = parentSubs[0].Id,
                    Entitlement_Id__c = 5001,
                    Sale_Price__c = 1000,
                    Segment_Index__c = 1
                )
            )
	     };
    }
    
    
    private static OP4I_Entitlement_View__c getSampleEntitlement() {
        return [
            SELECT Id, DLIP_Id__c, DLI_Id__c, Account__c, Total_Contract_Months__c, One_Time_Credit__c, Billing_Frequency__c, DLI_Price__c, Subscription_Term__c,
            Associated_OSA__r.SBQQ__RenewalTerm__c, Associated_OSA__r.AccountId, Quantity__c, Start_Date__c, End_Date__c, Associated_OSA__c, Include_in_Select_Bundle__c, Product_Instance__c,
            DLI_Product__r.Product_Type__c, DLIP_Product__r.Product_Type__c, Associated_OSA__r.Shipping_Account__c, OP4I_Deal_Id__c, Account__r.Name, Associated_OSA__r.ContractNumber,
            Processing_Status__c, DLI_Product__r.SBQQ__SubscriptionPricing__c, DLIP_Product__r.SBQQ__SubscriptionPricing__c, Error_Log__c, DLI_Product__r.SBQQ__SubscriptionTerm__c, Deal_Type__c,
            DLI_Product__c, DLI_Product__r.SBQQ__BillingType__c, DLIP_Product__r.SBQQ__BillingType__c, DLI_Product__r.SBQQ__ChargeType__c, DLIP_Product__r.SBQQ__ChargeType__c, CurrencyIsoCode,
            DLIP_Product__c, Entitlement_Id__c, Sale_Price__c, Meter_Type__c, Segment_Index__c, Associated_OSA__r.Migration_Status__c, Support_Level__c, DLIP_Product__r.SBQQ__SubscriptionType__c,
            Associated_OSA__r.Deal_Type__c, Line_of_Business__c, Associated_OSA__r.OSA_Customer_Name__c, DLI_Product__r.SBQQ__SubscriptionType__c, Associated_OSA__r.Processing_Status__c,
            DLI_Product__r.SBQQ__PricingMethod__c, Parent_Subscription__c, DLIP_Product__r.SBQQ__PricingMethod__c, Additional_Discount__c, Software_License_Term__c, Associated_OSA__r.OSA_Number__c,
            Associated_OSA__r.Line_of_Business__c, Associated_OSA__r.Software_Payment_Terms__c, Associated_OSA__r.BillingFrequency__c, Associated_OSA__r.Software_Days_Payment_Due_Renewal__c,
            Associated_OSA__r.Software_Billing_Frequency_Renewal__c, Renewal_Payment_Terms__c, Renewal_Billing_Frequency__c, Payment_Terms__c,  DLI_Product__r.ProductCode, DLIP_Product__r.ProductCode,
                Associated_OSA__r.SBQQ__Opportunity__c
            FROM OP4I_Entitlement_View__c
            LIMIT 1
        ];
    }
    
    static testMethod void testBuildOneTimeSub() {
        OP4I_Entitlement_View__c ent = getSampleEntitlement();
        SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildOneTimeSub(ent);
    }
    
    static testMethod void testBuildStandaloneSub() {
        OP4I_Entitlement_View__c ent = getSampleEntitlement();
        SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildStandaloneSub(ent, new Map<String, Id>());
        System.assertEquals(ent.DLI_Product__c, sub.SBQQ__Product__c);
    }
    
    static testMethod void testGetBundleKeyMap() {
        List<OP4I_Entitlement_View__c> entitlements = new List<OP4I_Entitlement_View__c>{ getSampleEntitlement() };
            Map<String, List<OP4I_Entitlement_View__c>> result = OP4ISubscriptionMigrationHelper.getBundleKeyMap(entitlements);
        System.assert(result.size() > 0);
    }
    
    static testMethod void testGetSegmentBundleKeyMap() {
        List<OP4I_Entitlement_View__c> entitlements = new List<OP4I_Entitlement_View__c>{ getSampleEntitlement() };
            Map<String, List<OP4I_Entitlement_View__c>> result = OP4ISubscriptionMigrationHelper.getSegmentBundleKeyMap(entitlements);
        System.assert(result.size() > 0);
    }
    
    static testMethod void testSplitByChargeType() {
        List<OP4I_Entitlement_View__c> entitlements = new List<OP4I_Entitlement_View__c>{ getSampleEntitlement() };
            Map<String, List<OP4I_Entitlement_View__c>> result = OP4ISubscriptionMigrationHelper.splitByChargeType(entitlements);
        System.assert(result.containsKey('OneTime'));
        System.assert(result.containsKey('Other'));
    }
    
    static testMethod void testBuildParentBundleSub() {
        List<OP4I_Entitlement_View__c> entList = new List<OP4I_Entitlement_View__c>{ getSampleEntitlement() };
            List<OP4I_Entitlement_View__c> entsToUpdate = new List<OP4I_Entitlement_View__c>();
        Set<Contract> contracts = new Set<Contract>();
        Integer[] counter = new Integer[] { 0 };
            SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildParentBundleSub(entList, new Map<String, SBQQ__ProductOption__c>(), entsToUpdate, contracts, counter, new Map<String, Id>(), new Map<String, Id>());
        System.assertNotEquals(null, sub);
    }
    
    static testMethod void testBuildSegmentedBundleSub() {
        OP4I_Entitlement_View__c ent = getSampleEntitlement();
        SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildSegmentedBundleSub(ent, null, new Map<String, Id>(), new Map<String, Id>(), new Map<String, Date>(), new Map<String, SBQQ__Subscription__c>(), new Map<String, SBQQ__ProductOption__c>(), new Map<String, Id>());
        System.assertNotEquals(null, sub);
    }
    
    static testMethod void testBuildComponentSub() {
        OP4I_Entitlement_View__c ent = getSampleEntitlement();
        SBQQ__Subscription__c sub = OP4ISubscriptionMigrationHelper.buildComponentSub(ent, null, new Map<String, Id>(), new Map<String, Id>(), new Map<String, Date>(), new Map<String, SBQQ__Subscription__c>(), new Map<String, SBQQ__ProductOption__c>(), new Map<String, Id>());
        System.assertNotEquals(null, sub);
    }
    
    static testMethod void testSendSummaryEmail() {
        Test.startTest();
        OP4ISubscriptionMigrationHelper.sendSummaryEmail(
            new List<String>{'test@example.com'},
            'TestBatch',
            5, 3, 1, 10, 2,
            new List<String>{'Error in entitlement 001', 'Another error'}
        );
        Test.stopTest();
    }
}