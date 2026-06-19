@isTest 
private class OP4IParentAndStandaloneBatchTest {

    @testSetup
    static void setupTestData() {
        // Create Account
        Account acct = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account'
            ), 'AccountDefaults'
        );

        // Create contract
        Contract contract = new Contract(
            AccountId = acct.Id,
            StartDate = Date.today(),
            EndDate = Date.today().addMonths(12),
            Migration_Status__c = 'Ready'
        );
        insert contract;

        // Create parent and child products
        Product2 parentProduct = new Product2(
            Name = 'Parent Product',
            ProductCode = 'PB-P',
            Parent_Of_Bundle__c = true,
            SBQQ__SubscriptionType__c = 'Renewable',
            SBQQ__SubscriptionPricing__c = 'Fixed',
            SBQQ__SubscriptionTerm__c = 12,
            SBQQ__ChargeType__c = 'Recurring',
            SBQQ__BillingType__c = 'Advance',
            IsActive = true
        );
        Product2 childProduct = new Product2(
            Name = 'Optional Product',
            ProductCode = 'OPT',
            SBQQ__SubscriptionType__c = 'Renewable',
            SBQQ__SubscriptionPricing__c = 'Fixed',
            SBQQ__SubscriptionTerm__c = 12,
            SBQQ__ChargeType__c = 'One-Time',
            IsActive = true
        );
        insert new List<Product2>{ parentProduct, childProduct };

        // Create product option relationship
        insert new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = parentProduct.Id,
            SBQQ__OptionalSKU__c = childProduct.Id,
            SBQQ__Number__c = 1
        );

        // Create dimensions (needed for subscriptions)
        insert new List<SBQQ__Dimension__c>{
            new SBQQ__Dimension__c(SBQQ__Product__c = parentProduct.Id, CurrencyIsoCode = 'USD'),
            new SBQQ__Dimension__c(SBQQ__Product__c = childProduct.Id, CurrencyIsoCode = 'USD')
        };

        // Create entitlements (standalone and child under parent)
        List<OP4I_Entitlement_View__c> ents = new List<OP4I_Entitlement_View__c>{
            new OP4I_Entitlement_View__c(
                Account__c = acct.Id,
                Associated_OSA__c = contract.Id,
                DLI_Product__c = parentProduct.Id,
                DLIP_Product__c = parentProduct.Id,
                Quantity__c = 1,
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addMonths(12),
                DLI_Price__c = 500,
                CurrencyIsoCode = 'USD',
                DLIP_Id__c = 1101,
                DLI_Id__c = 1102,
                Entitlement_Id__c = 1103,
                Subscription_Term__c = 12
            ),
            new OP4I_Entitlement_View__c(
                Account__c = acct.Id,
                Associated_OSA__c = contract.Id,
                DLI_Product__c = childProduct.Id,
                Quantity__c = 1,
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addMonths(12),
                DLI_Price__c = 100,
                CurrencyIsoCode = 'USD',
                DLIP_Id__c = 2101,
                DLI_Id__c = 2101,
                Entitlement_Id__c = 2103,
                OP4I_Deal_Id__c = 'DEAL123'
            )
        };
        insert ents;
        
        // Additional setup to trigger size == 1 and size > 1 paths
        
        // Shared parent for group
        Product2 sharedParent = new Product2(
            Name = 'Shared Parent',
            ProductCode = 'SHARED-P',
            Parent_Of_Bundle__c = true,
            SBQQ__SubscriptionType__c = 'Renewable',
            SBQQ__SubscriptionPricing__c = 'Fixed',
            SBQQ__SubscriptionTerm__c = 12,
            SBQQ__ChargeType__c = 'Recurring',
            SBQQ__BillingType__c = 'Advance',
            IsActive = true
        );
        Product2 sharedChild = new Product2(
            Name = 'Shared Child',
            ProductCode = 'SHARED-C',
            SBQQ__SubscriptionType__c = 'Renewable',
            SBQQ__SubscriptionPricing__c = 'Fixed',
            SBQQ__SubscriptionTerm__c = 12,
            SBQQ__ChargeType__c = 'Recurring',
            SBQQ__BillingType__c = 'Advance',
            IsActive = true
        );
        insert new List<Product2>{ sharedParent, sharedChild };
        
        // Product option relationship
        insert new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = sharedParent.Id,
            SBQQ__OptionalSKU__c = sharedChild.Id,
            SBQQ__Number__c = 2
        );
        
        // Dimensions for these new products
        insert new List<SBQQ__Dimension__c>{
            new SBQQ__Dimension__c(SBQQ__Product__c = sharedParent.Id, CurrencyIsoCode = 'USD'),
            new SBQQ__Dimension__c(SBQQ__Product__c = sharedChild.Id, CurrencyIsoCode = 'USD')
        };
        
        // One entitlement that is standalone (triggers size == 1)
        OP4I_Entitlement_View__c standaloneEntitlement = new OP4I_Entitlement_View__c(
            Account__c = acct.Id,
            Associated_OSA__c = contract.Id,
            DLI_Product__c = sharedParent.Id,
            DLIP_Product__c = null,
            Quantity__c = 1,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(12),
            DLI_Price__c = 750,
            CurrencyIsoCode = 'USD',
            DLIP_Id__c = 3101,
            DLI_Id__c = 3102,
            Entitlement_Id__c = 3103,
            Subscription_Term__c = 12
        );
        
        // Two entitlements that share the same key (triggers size > 1)
        OP4I_Entitlement_View__c groupedEnt1 = new OP4I_Entitlement_View__c(
            Account__c = acct.Id,
            Associated_OSA__c = contract.Id,
            DLI_Product__c = sharedParent.Id,
            DLIP_Product__c = sharedChild.Id,
            Quantity__c = 2,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(12),
            DLI_Price__c = 1000,
            CurrencyIsoCode = 'USD',
            DLIP_Id__c = 4101,
            DLI_Id__c = 4102,
            Entitlement_Id__c = 4103,
            Subscription_Term__c = 12
        );
        OP4I_Entitlement_View__c groupedEnt2 = groupedEnt1.clone(false, true, false, false);
        groupedEnt2.DLIP_Id__c = 4201;
        groupedEnt2.DLI_Id__c = 4202;
        groupedEnt2.Entitlement_Id__c = 4203;
        
        insert new List<OP4I_Entitlement_View__c>{ standaloneEntitlement, groupedEnt1, groupedEnt2 };

        // *** NEW: One-time entitlement to cover oneTimeSubs insert block ***
        OP4I_Entitlement_View__c oneTimeEntitlement = new OP4I_Entitlement_View__c(
            Account__c = acct.Id,
            Associated_OSA__c = contract.Id,
            DLI_Product__c = parentProduct.Id,
            Quantity__c = 1,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(1),
            DLI_Price__c = 300,
            CurrencyIsoCode = 'USD',
            DLIP_Id__c = 5101,
            DLI_Id__c = 5102,
            Entitlement_Id__c = 5103,
            Subscription_Term__c = 1
        );
        insert oneTimeEntitlement;
    }

    @isTest
    static void testParentAndStandaloneBatch() {
        // Validate data inserted correctly
        List<Contract> contracts = [SELECT Id FROM Contract WHERE Migration_Status__c = 'Ready'];
        System.assert(!contracts.isEmpty(), 'Contract should exist');

        List<OP4I_Entitlement_View__c> entitlements = [SELECT Id FROM OP4I_Entitlement_View__c];
        System.assert(entitlements.size() > 0, 'Entitlements should be created');

        Test.startTest();
        OP4IParentAndStandaloneBatch batch = new OP4IParentAndStandaloneBatch(new List<String>{'test@example.com'});
        Database.executeBatch(batch, 200);
        Test.stopTest();
    }
    
    @isTest
    static void testParentAndStandaloneBatch_Other() {
        List<String> contractEndings = new List<String>{'12345'}; // this covers the endDigit loop
        List<String> emails = new List<String>{'test@example.com'};
    
        Test.startTest();
        OP4IParentAndStandaloneBatch batch = new OP4IParentAndStandaloneBatch(contractEndings, emails);
        Database.executeBatch(batch, 200);
        Test.stopTest();
    }
}