/**
* @description       : Test class for SubscriptionTriggerHelper.
*                      Covers the BIZ-82910 sync gate fix (Retrigger_OP4I_Sync__c bypass),
*                      exclusion rules (Static Bundle, Parent_Of_Bundle__c), and
*                      populateOriginalOpportunityProduct edge cases.
* @author            : Satyanarayana Pusuluri
* @last modified on  : 06-01-2026
* @last modified by  : Satyanarayana Pusuluri
* Modifications Log
* Ver   Date          Author                    Modification
* 1.0   06-01-2026   Satyanarayana Pusuluri    Initial Version via BIZ-82910
**/
@isTest
public class SubscriptionTriggerHelperTest {

    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/

    /**
    * @description Creates shared test data: Account, Product, Opportunity, two Contracts
    *              (one Quote-linked for normal QTC path, one quote-less for migrated path),
    *              and one baseline Subscription per contract.
    **/
    @testSetup
    static void setup() {
        Account acc = (Account)TestFactory.createSObject(
            new Account(Name = 'Test Account BIZ-82910'), 'AccountDefaults');

        Product2 prod = (Product2)TestFactory.createSObject(
            new Product2(Name = 'Test Product BIZ-82910'), 'ProductDefaults');

        Opportunity opp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name       = 'Test Opportunity BIZ-82910',
                StageName  = 'Prospecting',
                CloseDate  = Date.today().addMonths(1),
                AccountId  = acc.Id
            ), 'OpportunityDefaults');

        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Account__c       = acc.Id,
                SBQQ__SubscriptionTerm__c = 12,
                SBQQ__Opportunity2__c  = opp.Id
            ), 'SBQQQuoteDefaults');

        Test.startTest();

        // Contract WITH a linked Quote (standard QTC path — OP4I_Contract_Number__c will populate)
        Contract contractWithQuote = (Contract)TestFactory.buildSObject(
            new Contract(
                Name               = 'Contract With Quote',
                AccountId          = acc.Id,
                SBQQ__Quote__c     = quote.Id,
                SBQQ__Opportunity__c = opp.Id,
                EndDate            = Date.today().addDays(365),
                SBQQ__RenewalTerm__c = 12,
                Subsidiary__c      = '01:200 Integration Appliance (US)',
                OP4I_Error__c      = '111'
            )
        );
        insert contractWithQuote;

        // Contract WITHOUT a Quote (QTC-migrated path — OP4I_Contract_Number__c stays null)
        Contract migratedContract = (Contract)TestFactory.buildSObject(
            new Contract(
                Name               = 'Migrated Contract BIZ-82910',
                AccountId          = acc.Id,
                EndDate            = Date.today().addDays(365),
                SBQQ__RenewalTerm__c = 12,
                Subsidiary__c      = '01:200 Integration Appliance (US)'
            )
        );
        insert migratedContract;

        // Normal subscription — has OP4I_Contract_Number__c and OP4I_Entitlement_Id__c
        SBQQ__Subscription__c normalSub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c              = acc.Id,
                SBQQ__Contract__c             = contractWithQuote.Id,
                SBQQ__Product__c              = prod.Id,
                SBQQ__Quantity__c             = 5,
                SBQQ__SubscriptionType__c     = 'Evergreen',
                SBQQ__ProductSubscriptionType__c = 'Evergreen',
                OP4I_Contract_Number__c       = 'CN-001',
                OP4I_Entitlement_Id__c        = '12345',
                Parent_Of_Bundle__c           = false,
                Retrigger_OP4I_Sync__c        = false
            )
        );
        insert normalSub;

        // Migrated subscription — OP4I_Contract_Number__c is null (no Quote on contract)
        SBQQ__Subscription__c migratedSub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c              = acc.Id,
                SBQQ__Contract__c             = migratedContract.Id,
                SBQQ__Product__c              = prod.Id,
                SBQQ__Quantity__c             = 3,
                SBQQ__SubscriptionType__c     = 'Evergreen',
                SBQQ__ProductSubscriptionType__c = 'Evergreen',
                OP4I_Contract_Number__c       = null,
                Parent_Of_Bundle__c           = false,
                Retrigger_OP4I_Sync__c        = false
            )
        );
        insert migratedSub;

        Test.stopTest();
    }

    /***********************************************************************************************
    *
    * Test Methods — subscriptionAfterUpdate / BIZ-82910 sync gate
    *
    ***********************************************************************************************/

    /**
    * @description BIZ-82910 core fix: a QTC-migrated subscription with null
    *              OP4I_Contract_Number__c must pass the sync gate when
    *              Retrigger_OP4I_Sync__c is set to true.
    *              Previously this record was hard-blocked by the SOQL WHERE clause.
    **/
    @isTest
    static void testAfterUpdate_RetriggerEnabled_NullContractNumber_PassesGate() {
        SBQQ__Subscription__c migratedSub = getMigratedSubscription();
        System.assertEquals(null, migratedSub.OP4I_Contract_Number__c,
            'Precondition: OP4I_Contract_Number__c must be null for migrated subscription');

        Test.startTest();
        migratedSub.Retrigger_OP4I_Sync__c = true;
        update migratedSub;
        Test.stopTest();

        SBQQ__Subscription__c result = getSubscriptionById(migratedSub.Id);
        System.assertEquals(null, result.OP4I_Contract_Number__c,
            'OP4I_Contract_Number__c should remain null for migrated subscription');
        System.assertEquals(true, result.Retrigger_OP4I_Sync__c,
            'Retrigger_OP4I_Sync__c should be true — record passed the sync gate without error');
    }

    /**
    * @description A migrated subscription (null OP4I_Contract_Number__c) with
    *              Retrigger_OP4I_Sync__c = false must remain excluded from the sync gate.
    *              Both conditions must be absent for the record to be blocked.
    **/
    @isTest
    static void testAfterUpdate_RetriggerDisabled_NullContractNumber_ExcludedFromGate() {
        SBQQ__Subscription__c migratedSub = getMigratedSubscription();

        Test.startTest();
        migratedSub.SBQQ__Quantity__c = 10;
        migratedSub.Retrigger_OP4I_Sync__c = false;
        update migratedSub;
        Test.stopTest();

        SBQQ__Subscription__c result = getSubscriptionById(migratedSub.Id);
        System.assertEquals(null, result.OP4I_Contract_Number__c,
            'OP4I_Contract_Number__c should remain null');
        System.assertEquals(false, result.Retrigger_OP4I_Sync__c,
            'Retrigger_OP4I_Sync__c should remain false — record excluded from sync gate');
    }

    /**
    * @description Regression: a normal subscription with OP4I_Contract_Number__c populated
    *              and OP4I_Entitlement_Id__c set must continue to pass the sync gate
    *              without any change to existing behaviour.
    **/
    @isTest
    static void testAfterUpdate_NormalSubscription_ContractNumber_PassesGate() {
        SBQQ__Subscription__c normalSub = getNormalSubscription();

        Test.startTest();
        normalSub.SBQQ__Quantity__c = 8;
        update normalSub;
        Test.stopTest();

        SBQQ__Subscription__c result = [
            SELECT Id, OP4I_Contract_Number__c, OP4I_Entitlement_Id__c
              FROM SBQQ__Subscription__c
             WHERE Id = :normalSub.Id
        ];
        System.assertNotEquals(null, result.OP4I_Contract_Number__c,
            'OP4I_Contract_Number__c should remain populated for normal subscription');
        System.assertEquals('12345', result.OP4I_Entitlement_Id__c,
            'OP4I_Entitlement_Id__c should be unchanged');
    }

    /**
    * @description Verifies that Retrigger_OP4I_Sync__c = true combined with an existing
    *              OP4I_Contract_Number__c both satisfy the gate (OR condition).
    **/
    @isTest
    static void testAfterUpdate_RetriggerAndContractNumber_BothSatisfyGate() {
        SBQQ__Subscription__c normalSub = getNormalSubscription();

        Test.startTest();
        normalSub.Retrigger_OP4I_Sync__c = true;
        update normalSub;
        Test.stopTest();

        SBQQ__Subscription__c result = getSubscriptionById(normalSub.Id);
        System.assertNotEquals(null, result.OP4I_Contract_Number__c,
            'OP4I_Contract_Number__c should remain populated');
        System.assertEquals(true, result.Retrigger_OP4I_Sync__c,
            'Retrigger_OP4I_Sync__c should be true — both conditions satisfy the OR gate');
    }

    /**
    * @description Verifies that a subscription with Parent_Of_Bundle__c = true is excluded
    *              from the sync gate even when Retrigger_OP4I_Sync__c = true.
    **/
    @isTest
    static void testAfterUpdate_ParentOfBundle_AlwaysExcluded() {
        Account acc    = [SELECT Id FROM Account LIMIT 1];
        Product2 prod  = [SELECT Id FROM Product2 LIMIT 1];
        Contract con   = getMigratedContract();

        SBQQ__Subscription__c bundleParent = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c              = acc.Id,
                SBQQ__Contract__c             = con.Id,
                SBQQ__Product__c              = prod.Id,
                SBQQ__Quantity__c             = 1,
                SBQQ__SubscriptionType__c     = 'Evergreen',
                SBQQ__ProductSubscriptionType__c = 'Evergreen',
                Parent_Of_Bundle__c           = true,
                Retrigger_OP4I_Sync__c        = false
            )
        );
        insert bundleParent;

        Test.startTest();
        bundleParent.Retrigger_OP4I_Sync__c = true;
        update bundleParent;
        Test.stopTest();

        SBQQ__Subscription__c result = [
            SELECT Id, Parent_Of_Bundle__c, Retrigger_OP4I_Sync__c
              FROM SBQQ__Subscription__c
             WHERE Id = :bundleParent.Id
        ];
        System.assertEquals(true, result.Parent_Of_Bundle__c,
            'Parent_Of_Bundle__c subscription must always be excluded from sync gate');
        System.assertEquals(true, result.Retrigger_OP4I_Sync__c,
            'Retrigger_OP4I_Sync__c should be persisted on the record even though gate blocks it');
    }

    /**
    * @description Verifies that a Static Bundle subscription is excluded from the sync gate
    *              even when Retrigger_OP4I_Sync__c = true.
    **/
    @isTest
    static void testAfterUpdate_StaticBundle_AlwaysExcluded() {
        Account acc    = [SELECT Id FROM Account LIMIT 1];
        Product2 prod  = [SELECT Id FROM Product2 LIMIT 1];
        Contract con   = getMigratedContract();

        SBQQ__Subscription__c staticBundle = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c              = acc.Id,
                SBQQ__Contract__c             = con.Id,
                SBQQ__Product__c              = prod.Id,
                SBQQ__Quantity__c             = 1,
                SBQQ__SubscriptionType__c     = 'Evergreen',
                SBQQ__ProductSubscriptionType__c = 'Evergreen',
                CPQ_Option_Type__c            = 'Static Bundle',
                Parent_Of_Bundle__c           = false,
                Retrigger_OP4I_Sync__c        = false
            )
        );
        insert staticBundle;

        Test.startTest();
        staticBundle.Retrigger_OP4I_Sync__c = true;
        update staticBundle;
        Test.stopTest();

        SBQQ__Subscription__c result = [
            SELECT Id, CPQ_Option_Type__c
              FROM SBQQ__Subscription__c
             WHERE Id = :staticBundle.Id
        ];
        System.assertEquals('Static Bundle', result.CPQ_Option_Type__c,
            'Static Bundle subscriptions must always be excluded from sync gate');
    }

    /***********************************************************************************************
    *
    * Test Methods — populateOriginalOpportunityProduct
    *
    ***********************************************************************************************/

    /**
    * @description Verifies that Original_Opportunity_Product__c is populated on insert
    *              when the subscription has a QuoteLine linked to an OpportunityLineItem.
    **/
    @isTest
    static void testPopulateOriginalOpportunityProduct_QuoteLineMatched() {
        Account acc   = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        Contract con  = [SELECT Id FROM Contract WHERE SBQQ__Quote__c != null LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Id standardPricebookId = Test.getStandardPricebookId();
        opp.Pricebook2Id = standardPricebookId;
        update opp;

        PricebookEntry pbe = (PricebookEntry)TestFactory.createSObject(
            new PricebookEntry(
                Product2Id   = prod.Id,
                Pricebook2Id = standardPricebookId,
                UnitPrice    = 100
            ), 'PricebookEntryDefaults'
        );

        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];

        SBQQ__QuoteLine__c quoteLine = (SBQQ__QuoteLine__c)TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c        = quote.Id,
                SBQQ__Quantity__c     = 1,
                SBQQ__Product__c      = prod.Id,
                SBQQ__CustomerPrice__c = 100
            )
        );

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId    = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100,
            SBQQ__QuoteLine__c = quoteLine.Id
        );
        insert oli;

        Test.startTest();
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c  = acc.Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Product__c  = prod.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__QuoteLine__c = quoteLine.Id
            )
        );
        insert sub;
        Test.stopTest();

        SBQQ__Subscription__c result = [
            SELECT Id, Original_Opportunity_Product__c
              FROM SBQQ__Subscription__c
             WHERE Id = :sub.Id
        ];
        System.assertEquals(oli.Id, result.Original_Opportunity_Product__c,
            'Original_Opportunity_Product__c should be stamped from the matching OpportunityLineItem');
    }

    /**
    * @description Verifies that Original_Opportunity_Product__c remains null when the
    *              subscription has no SBQQ__QuoteLine__c (early-return branch).
    **/
    @isTest
    static void testPopulateOriginalOpportunityProduct_NoQuoteLine_RemainsNull() {
        Account acc   = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        Contract con  = getMigratedContract();

        Test.startTest();
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c  = acc.Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Product__c  = prod.Id,
                SBQQ__Quantity__c = 2
            )
        );
        insert sub;
        Test.stopTest();

        SBQQ__Subscription__c result = [
            SELECT Id, Original_Opportunity_Product__c
              FROM SBQQ__Subscription__c
             WHERE Id = :sub.Id
        ];
        System.assertEquals(null, result.Original_Opportunity_Product__c,
            'Original_Opportunity_Product__c must remain null when no QuoteLine is present');
    }

    /***********************************************************************************************
    *
    * Getters
    *
    ***********************************************************************************************/

    /**
    * @description Returns the migrated subscription (OP4I_Contract_Number__c = null).
    * @return SBQQ__Subscription__c
    **/
    private static SBQQ__Subscription__c getMigratedSubscription() {
        return [
            SELECT Id, OP4I_Contract_Number__c, Retrigger_OP4I_Sync__c,
                   Parent_Of_Bundle__c, SBQQ__Quantity__c
              FROM SBQQ__Subscription__c
             WHERE SBQQ__Contract__r.Name = 'Migrated Contract BIZ-82910'
             LIMIT 1
        ];
    }

    /**
    * @description Returns the normal subscription (OP4I_Contract_Number__c populated).
    * @return SBQQ__Subscription__c
    **/
    private static SBQQ__Subscription__c getNormalSubscription() {
        return [
            SELECT Id, OP4I_Contract_Number__c, Retrigger_OP4I_Sync__c,
                   OP4I_Entitlement_Id__c, SBQQ__Quantity__c
              FROM SBQQ__Subscription__c
             WHERE OP4I_Contract_Number__c != null
             LIMIT 1
        ];
    }

    /**
    * @description Returns the migrated contract (no Quote link).
    * @return Contract
    **/
    private static Contract getMigratedContract() {
        return [SELECT Id FROM Contract WHERE Name = 'Migrated Contract BIZ-82910' LIMIT 1];
    }

    /**
    * @description Fetches a subscription by Id with key BIZ-82910 fields.
    * @param subscriptionId Id of the record to query
    * @return SBQQ__Subscription__c
    **/
    private static SBQQ__Subscription__c getSubscriptionById(Id subscriptionId) {
        return [
            SELECT Id, OP4I_Contract_Number__c, Retrigger_OP4I_Sync__c, Parent_Of_Bundle__c
              FROM SBQQ__Subscription__c
             WHERE Id = :subscriptionId
        ];
    }
}