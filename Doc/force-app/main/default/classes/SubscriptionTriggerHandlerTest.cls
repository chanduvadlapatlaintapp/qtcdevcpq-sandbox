/**
* @description       : This class is a Test class for SubscriptionTriggerHandler and SubscriptionTriggerHelper.
* @author            : Manisha Sharma
* @last modified on  : 04-25-2025
* @last modified by  : Sonali Kakade
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   04-25-2025   Manisha Sharma    Initial Version for BIZ-68140
* 2.0   06-23-2025   Sonali Kakade     Updated for BIZ-67339
**/

@isTest
public class SubscriptionTriggerHandlerTest {
    
    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/
    /**
    * @description Inserts required test data: Account, Opportunity, Quote, Contract, and Subscription
    **/
    @testSetup 
    static void setup() {
        // Create an Account
        Account acc = (Account)TestFactory.createSObject(
            new Account(Name = 'test acc1'), 'AccountDefaults');

        // Create a Product
        Product2 prodObj = (Product2)TestFactory.createSObject(
            new Product2(Name = 'Intapp Risk & Compliance PIN-01670'), 'ProductDefaults');

        // Create an Opportunity
        Opportunity oppObj = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = acc.Id
            ), 'OpportunityDefaults');
        

        // Create a Quote
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = acc.Id,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = oppObj.Id
            ), 'SBQQQuoteDefaults');
        
        Test.startTest();

        // Create a Contract
        Contract con = (Contract)TestFactory.buildSObject(
            new Contract(
                Name = 'Test Contract',
                EndDate = Date.today().addDays(395),
                SBQQ__Quote__c = newQuote.Id,
                OP4I_Error__c = '111',
                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = oppObj.Id,
                AccountId = acc.Id,
                Subsidiary__c = '01:200 Integration Appliance (US)'
            )
        );
        insert con;

        // Create a Subscription
        SBQQ__Subscription__c subscription = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Quantity__c = 12,
                SBQQ__Account__c = acc.Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Product__c = prodObj.Id,
                SBQQ__ProductSubscriptionType__c = 'Evergreen',
                SBQQ__SubscriptionType__c = 'Evergreen',
                OP4I_Contract_Number__c = '045841',
                Parent_Of_Bundle__c = true,
                Sync_NetSuite__c = true,
                OP4I_Entitlement_Id__c = '6902322'
            )
        );
        insert subscription;
        Test.stopTest();
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Tests update handler methods
    **/
    @isTest
    public static void testUpdate() {
        List<SBQQ__Subscription__c> listOfSubscription = [
            SELECT Id, Sync_NetSuite__c, Parent_Of_Bundle__c, SBQQ__Contract__c, OP4I_Entitlement_Id__c,
                   OP4I_Contract_Number__c, SBQQ__Contract__r.OP4I_Error__c
              FROM SBQQ__Subscription__c
        ];

        listOfSubscription[0].Parent_Of_Bundle__c = false;
        listOfSubscription[0].OP4I_Entitlement_Id__c = '6902322';

        Test.startTest();
        update listOfSubscription;
        Test.stopTest();

        System.assertEquals(true, listOfSubscription[0].Sync_NetSuite__c);
    }

    /**
    * @description Tests that Segment_Bundle_Line__c is populated for static components
    **/
    @isTest
    static void testUpdateSegmentedBundleId() {
        SBQQ__Quote__c quote = getTestQuote();

        Product2 prod = (Product2)TestFactory.createSObject(
            new Product2(
                Name = 'Intapp Integration Service: advanced',
                ProductCode = 'IS-01602',
                isActive = true
            )
        );

        SBQQ__QuoteLine__c staticBundleQL = (SBQQ__QuoteLine__c)TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id,
                CPQ_Option_Type__c = QuoteLineConstants.OPTION_TYPE_STATIC_BUNDLE,
                SBQQ__Quantity__c = 10,
                SBQQ__Product__c = prod.Id,
                Print_at_Quote__c = false,
                SBQQ__CustomerPrice__c = 28,
                Line_Item_Key__c = 'BUNDLE-001'
            )
        );

        SBQQ__QuoteLine__c staticComponentQL = (SBQQ__QuoteLine__c)TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id,
                CPQ_Option_Type__c = QuoteLineConstants.OPTION_TYPE_STATIC_COMPONENT,
                SBQQ__Quantity__c = 10,
                SBQQ__Product__c = prod.Id,
                Print_at_Quote__c = false,
                SBQQ__CustomerPrice__c = 28,
                Segment_Bundle_Line_Id__c = 'BUNDLE-001'
            )
        );

        // Create test Subscriptions
        List<SBQQ__Subscription__c> subscriptions = new List<SBQQ__Subscription__c>();
        
        SBQQ__Subscription__c staticBundleSub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                CPQ_Option_Type__c = SubscriptionConstants.OPTION_TYPE_STATIC_BUNDLE,
                SBQQ__QuoteLine__c = staticBundleQL.Id
            )
        );
        subscriptions.add(staticBundleSub);
        
        SBQQ__Subscription__c staticComponentSub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                CPQ_Option_Type__c = SubscriptionConstants.OPTION_TYPE_STATIC_COMPONENT,
                SBQQ__QuoteLine__c = staticComponentQL.Id
            )
        );
        subscriptions.add(staticComponentSub);
        
        Test.startTest();
        insert subscriptions;
        Test.stopTest();

        SBQQ__Subscription__c updatedComponentSub = getSubscriptionById(staticComponentSub.Id);
        System.assertEquals(staticBundleSub.Id, updatedComponentSub.Segment_Bundle_Line__c);
    }
    
	/**
    * @description Tests delete handler methods
    **/
    @isTest
    public static void testDelete() {
        List<SBQQ__Subscription__c> listOfSubscription = [
            SELECT Id, Sync_NetSuite__c, Parent_Of_Bundle__c, SBQQ__Contract__c, OP4I_Entitlement_Id__c,
                   OP4I_Contract_Number__c, SBQQ__Contract__r.OP4I_Error__c
              FROM SBQQ__Subscription__c
        ];
		
        Test.startTest();
        delete listOfSubscription;
        Test.stopTest();
		
        List<SBQQ__Subscription__c> lstSubs = [
            SELECT Id, Sync_NetSuite__c, Parent_Of_Bundle__c, SBQQ__Contract__c, OP4I_Entitlement_Id__c,
                   OP4I_Contract_Number__c, SBQQ__Contract__r.OP4I_Error__c
              FROM SBQQ__Subscription__c
        ];
        
        System.assertEquals(0, lstSubs.size());
    }

    /**
    * @description Tests that Original_Opportunity_Product__c is populated during before insert
    *              when the subscription has a SBQQ__QuoteLine__c that maps to an OpportunityLineItem.
    **/
    @isTest
    static void testPopulateOriginalOpportunityProduct() {
        SBQQ__Quote__c quote = getTestQuote();
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        // Assign the standard pricebook to the opportunity (required for OLI insert)
        Id standardPricebookId = Test.getStandardPricebookId();
        opp.Pricebook2Id = standardPricebookId;
        update opp;

        // Create a PricebookEntry for the product in the standard pricebook
        PricebookEntry pbe = (PricebookEntry)TestFactory.createSObject(
            new PricebookEntry(
                Product2Id = prod.Id,
                Pricebook2Id = standardPricebookId,
                UnitPrice = 100
            ), 'PricebookEntryDefaults'
        );

        // Create a QuoteLine linked to the subscription
        SBQQ__QuoteLine__c quoteLine = (SBQQ__QuoteLine__c)TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__Product__c = prod.Id,
                SBQQ__CustomerPrice__c = 100
            )
        );

        // Create an OpportunityLineItem linked to the QuoteLine
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100,
            SBQQ__QuoteLine__c = quoteLine.Id
        );
        insert oli;

        Contract con = [SELECT Id FROM Contract LIMIT 1];

        Test.startTest();
        SBQQ__Subscription__c subscription = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Quantity__c = 5,
                SBQQ__Account__c = [SELECT Id FROM Account LIMIT 1].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Product__c = prod.Id,
                SBQQ__QuoteLine__c = quoteLine.Id
            )
        );
        insert subscription;
        Test.stopTest();

        SBQQ__Subscription__c result = [
            SELECT Id, Original_Opportunity_Product__c
              FROM SBQQ__Subscription__c
             WHERE Id = :subscription.Id
        ];
        System.assertEquals(oli.Id, result.Original_Opportunity_Product__c,
            'Original_Opportunity_Product__c should be set to the matching OpportunityLineItem Id');
    }

    /**
    * @description Tests that Original_Opportunity_Product__c remains null when there is no
    *              SBQQ__QuoteLine__c on the subscription.
    **/
    @isTest
    static void testPopulateOriginalOpportunityProductNoQuoteLine() {
        Contract con = [SELECT Id FROM Contract LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        SBQQ__Subscription__c subscription = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Quantity__c = 5,
                SBQQ__Account__c = acc.Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Product__c = prod.Id
            )
        );
        insert subscription;
        Test.stopTest();

        SBQQ__Subscription__c result = [
            SELECT Id, Original_Opportunity_Product__c
              FROM SBQQ__Subscription__c
             WHERE Id = :subscription.Id
        ];
        System.assertEquals(null, result.Original_Opportunity_Product__c,
            'Original_Opportunity_Product__c should remain null when no QuoteLine is set');
    }

    /***********************************************************************************************
    *
    * Getters 
    *
    ***********************************************************************************************/

    /**
     * @description Returns a test Quote record inserted in @testSeup
     * @return SBQQ__Quote__c instance
     */
    private static SBQQ__Quote__c getTestQuote() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
    }

    /**
     * @description Fetches a subscription by Id including Segment_Bundle_Line__c field
     * @param subscriptionId - Id of the subscription to query
     * @return SBQQ__Subscription__c instance
     */
    private static SBQQ__Subscription__c getSubscriptionById(Id subscriptionId) {
        return [
            SELECT Id, Segment_Bundle_Line__c
            FROM SBQQ__Subscription__c
            WHERE Id = :subscriptionId
        ];
    }
}