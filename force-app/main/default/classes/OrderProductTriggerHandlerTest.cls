/**
 * @description Test class for OrderProductTriggerHandler trigger logic.
 * @author      Manisha
 * @date        2025-04-24
 * @jira        N/A
 * @updated     BIZ-81576 — set Bill_To_Address__c on Order creation (required in Prod).
 *              Added Address__c to @testSetup; switched inline Order creates to buildSObject
 *              pattern; added Automation_Controls__c bypass for Order Before Insert Update flow.
 */
@isTest
public with sharing class OrderProductTriggerHandlerTest {

    /***********************************************************************************************
    *
    * Shared Test Data Setup
    *
    ***********************************************************************************************/
    
    /**
     * @description Insert shared test data using TestFactory.
     */
    @testSetup
    public static void setup() {
        List<Product2> products = (List<Product2>) TestFactory.createSObjectList(
            new Product2(Name = 'Intapp Risk & Compliance PIN-01670'),
            1,
            'ProductDefaults'
        );

        for (Product2 product : products) {
            TestFactory.createSObjectList(
                new PricebookEntry(Product2Id = product.Id),
                1,
                'PricebookEntryDefaults'
            );
        }

        List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
            new Account(Name = 'Test Account'),
            1,
            'AccountDefaults'
        );

        List<Opportunity> opportunities = (List<Opportunity>) TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ),
            1,
            'OpportunityDefaults'
        );

        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
        for (Opportunity opp : opportunities) {
            quotes.addAll((List<SBQQ__Quote__c>) TestFactory.createSObjectList(
                new SBQQ__Quote__c(
                    SBQQ__Primary__c = true,
                    SBQQ__Opportunity2__c = opp.Id
                ),
                1,
                'SBQQQuoteDefaults'
            ));
        }

        SBQQ.TriggerControl.disable();

        for (SBQQ__Quote__c quote : quotes) {
            Product2 prod = products[0];

            SBQQ__QuoteLine__c parentQL = (SBQQ__QuoteLine__c) TestFactory.createSObject(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = quote.Id,
                    SBQQ__Product__c = prod.Id,
                    SBQQ__Quantity__c = 1,
                    SBQQ__CustomerPrice__c = 100,
                    Line_Item_Key__c = 'PARENT_KEY'
                ),
                'SBQQQuoteLineDefaults'
            );

            SBQQ__QuoteLine__c childQL = (SBQQ__QuoteLine__c) TestFactory.createSObject(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = quote.Id,
                    SBQQ__Product__c = prod.Id,
                    SBQQ__Quantity__c = 1,
                    SBQQ__CustomerPrice__c = 50,
                    Line_Item_Key__c = 'CHILD_KEY',
                    Segment_Bundle_Line_Id__c = 'PARENT_KEY'
                ),
                'SBQQQuoteLineDefaults'
            );
        }

        SBQQ.TriggerControl.enable();

        // ── Address (required on Order in Prod) ───────────────────────────────────────────────
        // Bill_To_Address__c is required on Order. The lookup filter requires Status__c =
        // 'Verification Approved' and Account__c matching the Order's Billing_Account__c.
        Address__c billToAddr = new Address__c(
            Account__c              = accounts[0].Id,
            Address__City__s        = 'Los Angeles',
            Address__CountryCode__s = 'US',
            Address__PostalCode__s  = '90210',
            Address__StateCode__s   = 'CA',
            Address__Street__s      = 'Beverly Hills',
            Status__c               = 'Verification Approved',
            Default_Billing_Address__c  = true,
            Default_Shipping_Address__c = true
        );
        insert billToAddr;

        // ── Bypass "Order : Before Insert Update" flow ────────────────────────────────────────
        // This flow tries to populate Bill_To_Address__c from the linked Quote/Contract.
        // When Order is not yet linked to a Quote (inline test creation), the flow would
        // clear the field. Active__c + Bypass_Flows__c + Order_Bypass__c suppresses it.
        Automation_Controls__c controls = Automation_Controls__c.getInstance();
        controls.Active__c       = true;
        controls.Bypass_Flows__c = true;
        controls.Order_Bypass__c = true;
        upsert controls;
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description test method for delete event
     */
    @isTest
    static void testDeleteOrderProducts() {
        Order orderObj = (Order) TestFactory.buildSObject(
            new Order(
                AccountId = getTestAccount().Id,
                Pricebook2Id = Test.getStandardPricebookId()
            ),
            'OrderDefaults'
        );
        orderObj.Billing_Account__c = getTestAccount().Id;
        orderObj.Bill_To_Address__c = getTestAddress().Id;
        insert orderObj;
        OrderItem orderItem = (OrderItem) TestFactory.createSObject(
            new OrderItem(
                OrderId = orderObj.Id,
                PricebookEntryId = getTestPricebookEntry().Id
            ),
            'OrderItemDefaults'
        );
        Test.startTest();
        delete orderItem;
        Test.stopTest();
    }

    /**
     * @description Verifies that updating OrderItem with SBQQ__Activated__c = true behaves correctly.
     */
    @isTest
    static void testOrderActivationWithApprovedOrder() {
        Order orderObj = (Order) TestFactory.buildSObject(
            new Order(
                AccountId = getTestAccount().Id,
                Pricebook2Id = Test.getStandardPricebookId()
            ),
            'OrderDefaults'
        );
        orderObj.Billing_Account__c = getTestAccount().Id;
        orderObj.Bill_To_Address__c = getTestAddress().Id;
        insert orderObj;

        OrderItem orderItem = (OrderItem) TestFactory.createSObject(
            new OrderItem(
                OrderId = orderObj.Id,
                PricebookEntryId = getTestPricebookEntry().Id
            ),
            'OrderItemDefaults'
        );

        Test.startTest();
            orderItem.SBQQ__Activated__c = true;
            update orderItem;
        Test.stopTest();

        System.assertEquals(true, orderItem.SBQQ__Activated__c, 'Order Item must be activated');
    }

    /**
     * @description Verifies that Static Component OrderItem gets Segment_Bundle_Line__c set from parent.
     */
    @isTest
    static void testUpdateSegmentedBundleId() {
        Order ord = (Order) TestFactory.buildSObject(
            new Order(
                AccountId = getTestAccount().Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = Test.getStandardPricebookId()
            ),
            'OrderDefaults'
        );
        ord.Billing_Account__c = getTestAccount().Id;
        ord.Bill_To_Address__c = getTestAddress().Id;
        insert ord;

        // OrderItem for Static Bundle
        OrderItem parentOI = new OrderItem(
            OrderId = ord.Id,
            Quantity = 1,
            UnitPrice = 100,
            PricebookEntryId = getTestPricebookEntry().Id,
            CPQ_Option_Type__c = OpportunityProductConstants.OPTION_TYPE_STATIC_BUNDLE,
            SBQQ__QuoteLine__c = getParentQuoteLine().Id
        );

        // OrderItem for Static Component
        OrderItem childOI = new OrderItem(
            OrderId = ord.Id,
            Quantity = 1,
            UnitPrice = 50,
            PricebookEntryId = getTestPricebookEntry().Id,
            CPQ_Option_Type__c = OpportunityProductConstants.OPTION_TYPE_STATIC_COMPONENT,
            SBQQ__QuoteLine__c = getChildQuoteLine().Id
        );

        Test.startTest();
        insert new List<OrderItem>{ parentOI, childOI };
        Test.stopTest();

        OrderItem updatedChild = getUpdatedOrderItem(childOI.Id);
        System.assertEquals(parentOI.Id, updatedChild.Segment_Bundle_Line__c, 'Segment_Bundle_Line__c should match parent OrderItem Id');
    }
    
    /***********************************************************************************************
    *
    * Getter Methods for Shared Data
    *
    ***********************************************************************************************/
    
    private static Account getTestAccount() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Address__c getTestAddress() {
        return [SELECT Id FROM Address__c LIMIT 1];
    }

    private static PricebookEntry getTestPricebookEntry() {
        return [SELECT Id FROM PricebookEntry LIMIT 1];
    }

    private static SBQQ__QuoteLine__c getParentQuoteLine() {
        return [SELECT Id, Line_Item_Key__c FROM SBQQ__QuoteLine__c WHERE Line_Item_Key__c = 'PARENT_KEY' LIMIT 1];
    }

    private static SBQQ__QuoteLine__c getChildQuoteLine() {
        return [SELECT Id, Segment_Bundle_Line_Id__c FROM SBQQ__QuoteLine__c WHERE Line_Item_Key__c = 'CHILD_KEY' LIMIT 1];
    }

    private static OrderItem getUpdatedOrderItem(Id orderItemId) {
        return [SELECT Segment_Bundle_Line__c FROM OrderItem WHERE Id = :orderItemId];
    }
}