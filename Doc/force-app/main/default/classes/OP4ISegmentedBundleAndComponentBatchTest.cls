@isTest
private class OP4ISegmentedBundleAndComponentBatchTest {

    @testSetup
    static void setupTestData() {
        List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
            new Account(Name = 'Test Account'),
            1,
            'AccountDefaults'
        );

        // Insert Contract
        Contract osa = new Contract(
            AccountId = accounts[0].Id,
            SBQQ__RenewalTerm__c = 12,
            Migration_Status__c = 'Ready',
            Processing_Status__c = 'Open',
            BillingFrequency__c = 'Annual',
            Deal_Type__c = 'New_Software',
            OSA_Number__c = 'OSA001',
            Line_of_Business__c = 'Intapp',
            OSA_Customer_Name__c = accounts.get(0).Id
        );
        insert osa;

        // Insert Products
        Product2 bundleProduct = new Product2(
            Name = 'Bundle Product',
            SBQQ__SubscriptionPricing__c = 'Fixed',
            SBQQ__SubscriptionTerm__c = 12,
            SBQQ__ChargeType__c = 'Recurring',
            ProductCode = 'ABC',
            SBQQ__BillingType__c = 'Advance',
            IsActive = true
        );
        Product2 componentProduct = new Product2(
            Name = 'Component Product',
            SBQQ__SubscriptionPricing__c = 'Fixed',
            SBQQ__SubscriptionTerm__c = 12,
            SBQQ__ChargeType__c = 'Recurring',
            SBQQ__BillingType__c = 'Advance',
            IsActive = true
        );
        insert new List<Product2>{ bundleProduct, componentProduct };

        // Insert Parent Subscription
        SBQQ__Subscription__c parentSub = new SBQQ__Subscription__c(
            SBQQ__Account__c = accounts[0].Id,
            SBQQ__Contract__c = osa.Id,
            SBQQ__Product__c = bundleProduct.Id,
            SBQQ__Bundle__c = true,
            SBQQ__Quantity__c = 1
        );
        insert parentSub;

        // Insert Entitlement
        OP4I_Entitlement_View__c entitlement = new OP4I_Entitlement_View__c(
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
            Associated_OSA__c = osa.Id,
            Include_in_Select_Bundle__c = true,
            Product_Instance__c = 1234,
            DLI_Product__c = bundleProduct.Id,
            DLIP_Product__c = componentProduct.Id,
            CurrencyIsoCode = 'USD',
            Processing_Status__c = 'Parent/Segment Created',
            Parent_Subscription__c = parentSub.Id,
            Entitlement_Id__c = 5001,
            Sale_Price__c = 1000,
            Segment_Index__c = 1
        );
        insert entitlement;
    }

    @isTest
    static void testBatchExecution() {
        List<OP4I_Entitlement_View__c> ents = [
            SELECT Id,DLI_Product__r.ProductCode, DLIP_Product__c, DLI_Product__c, Associated_OSA__c FROM OP4I_Entitlement_View__c
        ];

        Set<Id> contractIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (OP4I_Entitlement_View__c e : ents) {
            if (e.Associated_OSA__c != null) contractIds.add(e.Associated_OSA__c);
            if (e.DLIP_Product__c != null) productIds.add(e.DLIP_Product__c);
            if (e.DLI_Product__c != null) productIds.add(e.DLI_Product__c);
        }

        Map<Id, String> mapComponentIdToBundleCodeValidPair = new Map<Id, String>();
        String suffixCode = ents.get(0).DLI_Product__r.ProductCode + '-P';

        mapComponentIdToBundleCodeValidPair.put(ents.get(0).DLIP_Product__c, suffixCode);
         mapComponentIdToBundleCodeValidPair.put(ents.get(0).DLI_Product__c, suffixCode);

        OP4ISubscriptionMigrationHelper.ProductOptionMaps optionMaps =
            OP4ISubscriptionMigrationHelper.getProductOptionMaps(productIds, mapComponentIdToBundleCodeValidPair);

        Test.startTest();
        Database.executeBatch(
            new OP4ISegmentedBundleAndComponentBatch(
                optionMaps.productOptionMap,
                optionMaps.optionalConfiguredParentBundleMap,
                new List<String>{'test@email.com'},
                contractIds
            ),
            1
        );
        Test.stopTest();

        List<OP4I_Entitlement_View__c> updated = [
            SELECT Id, Processing_Status__c FROM OP4I_Entitlement_View__c
        ];
        System.assertNotEquals(0, updated.size(), 'Entitlements should have been processed');

        Boolean hasCreated = false;
        for (OP4I_Entitlement_View__c e : updated) {
            if (e.Processing_Status__c != null && e.Processing_Status__c.contains('Created')) {
                hasCreated = true;
                break;
            }
        }
        System.assert(hasCreated, 'At least one entitlement should be marked as created');
    }
}