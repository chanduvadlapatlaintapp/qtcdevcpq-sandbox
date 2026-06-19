/**
 * @description Test class for OrderTriggerHelper
**/
@isTest
public class OrderTriggerHandlerTest {

    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/
    @testSetup 
    /**
     * @description Test Setup
     */
    static void setup() {
        Product2  testProduct = (Product2)TestFactory.buildSObject(
                new Product2(
                    Name = 'Test Product', 
                    IsActive = true
                ), 'ProductDefaults'
            );

        insert new List<Product2>{ testProduct };

        PricebookEntry   testPbe = (PricebookEntry  )TestFactory.buildSObject(
                new PricebookEntry (
                    Product2Id = testProduct.Id,
                    UnitPrice = 100
                ), 'PricebookEntryDefaults'
            );

        insert new List<PricebookEntry >{ testPbe };

        // Create Account
        Account activeAccount = (Account)TestFactory.buildSObject(
                new Account(
                    Name = 'Test Account', 
                    Type = AccountConstants.TYPE_CLIENT
                ), 'AccountDefaults'
            );

            insert new List<Account>{ activeAccount};

        Address__c billToAddress = new Address__c(Account__c = activeAccount.Id);
        insert billToAddress;

        // Create Contract to be superseded

        Contract oldContract = (Contract)TestFactory.buildSObject(
            new Contract(
                Name = 'ActiveContract',
                AccountId = activeAccount.Id,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addMonths(12),
                Billing_Account__c = activeAccount.Id,
                Bill_To_Address__c = billToAddress.Id
            ), 'ContractDefaults'
        );

        insert new List<Contract>{ oldContract};
            
        // Create Opportunity with specific deal type and linked to the contract
        Opportunity opp = (Opportunity)TestFactory.buildSObject(
                new Opportunity(
                    Name = 'Test Opportunity',
                    StageName = OpportunityConstants.STAGE_PROSPECTING,
                    CloseDate = Date.today(),
                    Deal_Type__c = OpportunityConstants.DEAL_TYPE_AMENDMENT_TO_SUPERCEDE,
                    AccountId = activeAccount.Id,
                    Associated_Contract_OSA__c = oldContract.Id,
                    SBQQ__AmendedContract__c = oldContract.Id,
                    OP4I_Auto_Number_Deal_ID__c = 'Test Opp'
                ), 'OpportunityDefaults'
            );

        // create nymy opp
        Opportunity nymyOpp = (Opportunity)TestFactory.buildSObject(
                new Opportunity(
                    Name = 'NYMY Opportunity',
                    StageName = OpportunityConstants.STAGE_PROSPECTING,
                    CloseDate = Date.today(),
                    Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                    AccountId = activeAccount.Id,
                    Associated_Contract_OSA__c = oldContract.Id,
                    OP4I_Auto_Number_Deal_ID__c = 'NYMY Opp'
                ), 'OpportunityDefaults'
            );
        // Mock related opportunity for the contract (to be closed)
        Opportunity renewalOpp = (Opportunity)TestFactory.buildSObject(
            new Opportunity(
                Name = 'Renewal Opp',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today(),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_AMENDMENT_TO_SUPERCEDE,
                AccountId = activeAccount.Id,
                SBQQ__AmendedContract__c = oldContract.Id,
                OP4I_Auto_Number_Deal_ID__c = 'Renewal Opp'

            ), 'OpportunityDefaults'
        );

        // Created amended opp for the contract
        Opportunity amendedOpp = (Opportunity)TestFactory.buildSObject(
            new Opportunity(
                Name = 'Amendment Opp',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today(),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_CANCELLATION,
                AccountId = activeAccount.Id,
                SBQQ__AmendedContract__c = oldContract.Id,
                OP4I_Auto_Number_Deal_ID__c = 'Amendment Opp'
            ), 'OpportunityDefaults'
        );
        insert new List<Opportunity>{ opp, nymyOpp, renewalOpp, amendedOpp};

        // Create Order (old and new version)
        Order oldOrder = (Order)TestFactory.buildSObject(
                new Order(
                    Name = 'Old Order',
                    AccountId = activeAccount.Id,
                    OpportunityId = opp.Id,
                    Status =  OrderConstants.STATUS_DRAFT,
                    Is_RMA_Order__c = 'Yes',
                    Pricebook2Id = Test.getStandardPricebookId(),
                    Billing_Account__c = activeAccount.Id,
                    Bill_To_Address__c = billToAddress.Id
                ), 'OrderDefaults'
            );

            Order newOrder = (Order)TestFactory.buildSObject(
                new Order(
                    Name = 'New Order',
                    AccountId = activeAccount.Id,
                    OpportunityId = renewalOpp.Id,
                    Status =  OrderConstants.STATUS_DRAFT,
                    Is_RMA_Order__c = 'Yes',
                    Pricebook2Id = Test.getStandardPricebookId(),
                    Billing_Account__c = activeAccount.Id,
                    Bill_To_Address__c = billToAddress.Id
                ), 'OrderDefaults'
            );

             Order rmaOrder = (Order)TestFactory.buildSObject(
                new Order(
                    Name = 'RMA Order',
                    AccountId = activeAccount.Id,
                    OpportunityId = amendedOpp.Id,
                    Status =  OrderConstants.STATUS_DRAFT,
                    Is_RMA_Order__c = 'Yes',
                    Pricebook2Id = Test.getStandardPricebookId(),
                    Billing_Account__c = activeAccount.Id,
                    Bill_To_Address__c = billToAddress.Id
                ), 'OrderDefaults'
            );

            insert new List<Order>{ oldOrder, newOrder, rmaOrder};

            OrderItem testOrderItem1 = (OrderItem)TestFactory.buildSObject(
                new OrderItem(
                    OrderId = oldOrder.Id,
                    Quantity = 10,
                    UnitPrice = 100,
                    PricebookEntryId = testPbe.Id
                ), 'OrderItemDefaults'
            );
            OrderItem testOrderItem2 = (OrderItem)TestFactory.buildSObject(
                new OrderItem(
                    OrderId = newOrder.Id,
                    Quantity = -10,
                    UnitPrice = 100,
                    PricebookEntryId = testPbe.Id
                ), 'OrderItemDefaults'
            );
            OrderItem testOrderItem3 = (OrderItem)TestFactory.buildSObject(
                new OrderItem(
                    OrderId = rmaOrder.Id,
                    Quantity = -10,
                    UnitPrice = 100,
                    PricebookEntryId = testPbe.Id
                ), 'OrderItemDefaults'
            );
            insert new List<OrderItem>{ testOrderItem1, testOrderItem2, testOrderItem3 };
    }

    /***********************************************************************************************
    *
    * Test methods
    *
    ***********************************************************************************************/
    /**
     * @description Full cancellation via Queueable: all recurring subs terminated -> contract = Cancelled/Lapsed, opps closed, account lapsed
     */
    @isTest
    static void setContractAsCancelledTest() {
        Contract oldContract = getContract();
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            ),
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('RMA Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};

        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        Test.startTest();
            newOrder.SBQQ__Contracted__c = true;
            update newOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertEquals(ContractConstants.STATUS_CANCELLED_LAPSED, updatedContract.Status, 'Contract should be marked as Cancelled');

        Opportunity nymyOpp = getOpportunity('NYMY Opportunity');
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName, 'Opportunity should be moved to ' + OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED);

        Account account = getAccount();
        System.assertEquals(AccountConstants.TYPE_CLIENT_LAPSED, account.Type, 'Account must be ' + AccountConstants.TYPE_CLIENT_LAPSED);
    }

    /**
     * @description Full supersession via Queueable: all recurring subs terminated -> contract = Superseded, opps closed
     */
    @isTest
    static void setContractAsSupercededTest() {
        Contract oldContract = getContract();
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            ),
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('New Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};
        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        Test.startTest();
            newOrder.SBQQ__Contracted__c = true;
            newOrder.ContractNumber__c = '12345';
            update newOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertEquals(ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT, updatedContract.Status, 'Contract should be marked as Superseded');

        Opportunity nymyOpp = getOpportunity('NYMY Opportunity');
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName, 'Opportunity should be moved to ' + OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED);
    }

    /**
     * @description Partial cancellation guard: when one subscription is still active (no TerminatedDate),
     *              the Queueable skips the contract. Contract stays In Force, NYMY stays open, account not lapsed.
     */
    @isTest
    static void setContractAsCancelled_PartialTest() {
        Contract oldContract = getContract();
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            ),
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable'
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('RMA Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};

        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        Test.startTest();
            newOrder.SBQQ__Contracted__c = true;
            update newOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertNotEquals(ContractConstants.STATUS_CANCELLED_LAPSED, updatedContract.Status,
            'Contract should NOT be cancelled when active recurring subscriptions remain');

        Opportunity nymyOpp = getOpportunity('NYMY Opportunity');
        System.assertNotEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opp should remain open when partial cancellation is detected');

        Account account = getAccount();
        System.assertEquals(AccountConstants.TYPE_CLIENT, account.Type,
            'Account should remain Client when contract is not cancelled');
    }

    /**
     * @description Partial supersession guard: when one subscription is still active (no TerminatedDate),
     *              the Queueable skips the contract. Contract stays In Force, NYMY stays open.
     */
    @isTest
    static void setContractAsSuperceded_PartialTest() {
        Contract oldContract = getContract();
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            ),
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable'
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('New Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};
        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        Test.startTest();
            newOrder.SBQQ__Contracted__c = true;
            newOrder.ContractNumber__c = '12345';
            update newOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertNotEquals(ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT, updatedContract.Status,
            'Contract should NOT be superseded when active recurring subscriptions remain');

        Opportunity nymyOpp = getOpportunity('NYMY Opportunity');
        System.assertNotEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opp should remain open when partial supersession is detected');
    }

    /**
     * @description Full cancellation on a contract that already has a closed renewal opp.
     *              Only the open NYMY opp should be closed; the already-closed renewal stays as-is.
     */
    @isTest
    static void setContractAsCancelled_WithPriorRenewalTest() {
        Contract oldContract = getContract();
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Opportunity closedRenewalOpp = (Opportunity) TestFactory.buildSObject(
            new Opportunity(
                Name = 'Prior Renewal Opp',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addMonths(-3),
                Type = OpportunityConstants.TYPE_RENEWAL,
                AccountId = testAccount.Id,
                SBQQ__RenewedContract__c = oldContract.Id,
                OP4I_Auto_Number_Deal_ID__c = 'Prior Renewal'
            ), 'OpportunityDefaults'
        );
        insert closedRenewalOpp;

        closedRenewalOpp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        update closedRenewalOpp;

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('RMA Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};

        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        Test.startTest();
            newOrder.SBQQ__Contracted__c = true;
            update newOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertEquals(ContractConstants.STATUS_CANCELLED_LAPSED, updatedContract.Status, 'Contract should be marked as Cancelled');

        Opportunity nymyOpp = getOpportunity('NYMY Opportunity');
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName, 'Open NYMY Opp should be closed');

        Opportunity closedRenewal = getOpportunity('Prior Renewal Opp');
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_WON, closedRenewal.StageName, 'Already-closed renewal should remain Closed Won');

        Account account = getAccount();
        System.assertEquals(AccountConstants.TYPE_CLIENT_LAPSED, account.Type, 'Account must be ' + AccountConstants.TYPE_CLIENT_LAPSED);
    }

    /**
     * @description Full supersession on a contract that already has a closed renewal opp.
     *              Only the open NYMY opp should be closed; the already-closed renewal stays as-is.
     */
    @isTest
    static void setContractAsSuperceded_WithPriorRenewalTest() {
        Contract oldContract = getContract();
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Opportunity closedRenewalOpp = (Opportunity) TestFactory.buildSObject(
            new Opportunity(
                Name = 'Prior Renewal Opp',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addMonths(-3),
                Type = OpportunityConstants.TYPE_RENEWAL,
                AccountId = testAccount.Id,
                SBQQ__RenewedContract__c = oldContract.Id,
                OP4I_Auto_Number_Deal_ID__c = 'Prior Renewal'
            ), 'OpportunityDefaults'
        );
        insert closedRenewalOpp;

        closedRenewalOpp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        update closedRenewalOpp;

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('New Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};
        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        Test.startTest();
            newOrder.SBQQ__Contracted__c = true;
            newOrder.ContractNumber__c = '12345';
            update newOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertEquals(ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT, updatedContract.Status, 'Contract should be marked as Superseded');

        Opportunity nymyOpp = getOpportunity('NYMY Opportunity');
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName, 'Open NYMY Opp should be closed');

        Opportunity closedRenewal = getOpportunity('Prior Renewal Opp');
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_WON, closedRenewal.StageName, 'Already-closed renewal should remain Closed Won');
    }

    /**
     * @description Cancellation of a contract already in Partially Cancelled status should
     *              NOT incorrectly lapse the account when other active contracts exist.
     *              Validates the fix for the Codex review finding on PR #5660.
     */
    @isTest
    static void setContractAsCancelled_FromPartialStatusTest() {
        Contract oldContract = getContract();
        Account testAccount = getAccount();
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        oldContract.Status = ContractConstants.STATUS_PARTIALLY_SUPERSEDED;
        update oldContract;

        Contract secondContract = (Contract)TestFactory.buildSObject(
            new Contract(
                Name = 'Second Active Contract',
                AccountId = testAccount.Id,
                StartDate = Date.today().addMonths(-6),
                EndDate = Date.today().addMonths(18)
            ), 'ContractDefaults'
        );
        insert secondContract;

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('RMA Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};

        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        Test.startTest();
            newOrder.SBQQ__Contracted__c = true;
            update newOrder;
        Test.stopTest();

        Contract updatedContract = [SELECT Id, Status FROM Contract WHERE Id = :oldContract.Id];
        System.assertEquals(ContractConstants.STATUS_CANCELLED_LAPSED, updatedContract.Status,
            'Contract should still be cancelled even from Partially Cancelled status');

        Opportunity nymyOpp = getOpportunity('NYMY Opportunity');
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opp should be closed');

        Account account = getAccount();
        System.assertEquals(AccountConstants.TYPE_CLIENT, account.Type,
            'Account should NOT be lapsed because another active contract exists');
    }

    /**
     * @description Status guard: when contract is already Cancelled / Lapsed, re-touching the
     *              RMA order should not enqueue a redundant Queueable or cause errors.
     *              Validates the filterContractsNotInStatus guard (BIZ-69730).
     */
    @isTest
    static void setContractAsCancelled_AlreadyCancelledNoOpTest() {
        Contract oldContract = getContract();
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Order oldOrder = getOrder('Old Order');
        Order rmaOrder = getOrder('RMA Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        rmaOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, rmaOrder};

        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        rmaOrder.SBQQ__Contracted__c = true;
        update rmaOrder;

        oldContract.Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        update oldContract;

        Test.startTest();
            rmaOrder.ContractNumber__c = 'RETRIGGER';
            update rmaOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertEquals(ContractConstants.STATUS_CANCELLED_LAPSED, updatedContract.Status,
            'Contract should remain Cancelled / Lapsed when order is re-touched');
    }

    /**
     * @description Status guard: when contract is already Superseded by Newer Contract,
     *              re-touching the RMA order should not enqueue a redundant Queueable or cause errors.
     *              Validates the filterContractsNotInStatus guard (BIZ-69730).
     */
    @isTest
    static void setContractAsSuperceded_AlreadySupercededNoOpTest() {
        Contract oldContract = getContract();
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            (SBQQ__Subscription__c) TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Contract__c = oldContract.Id,
                    SBQQ__Product__c = testProduct.Id,
                    SBQQ__ProductSubscriptionType__c = 'Renewable',
                    SBQQ__SubscriptionType__c = 'Renewable',
                    SBQQ__TerminatedDate__c = Date.today()
                ), 'SBQQSubScriptionDefaults'
            )
        };

        Order oldOrder = getOrder('Old Order');
        Order newOrder = getOrder('New Order');

        oldOrder.Status = OrderConstants.STATUS_ACTIVATED;
        newOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update new List<Order> {oldOrder, newOrder};

        oldOrder.SBQQ__Contracted__c = true;
        update oldOrder;

        newOrder.SBQQ__Contracted__c = true;
        update newOrder;

        oldContract.Status = ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT;
        update oldContract;

        Test.startTest();
            newOrder.ContractNumber__c = 'RETRIGGER';
            update newOrder;
        Test.stopTest();

        Contract updatedContract = getContract();
        System.assertEquals(ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT, updatedContract.Status,
            'Contract should remain Superseded when order is re-touched');
    }

    /**
     * @description Test that populateMasterContract sets Master_Contract__c from the
     *              Opportunity's SBQQ__AmendedContract__c when an Order is inserted.
     */
    @isTest
    static void populateMasterContractTest() {
        Account acc = getAccount();
        Address__c addr = getAddress();
        Contract existingContract = getContract();
        Opportunity amendmentOpp = getOpportunityByDealId('Renewal Opp');

        Order testOrder = (Order)TestFactory.buildSObject(
            new Order(
                Name = 'Master Contract Order',
                AccountId = acc.Id,
                OpportunityId = amendmentOpp.Id,
                Status = OrderConstants.STATUS_DRAFT,
                Is_RMA_Order__c = 'Yes',
                Pricebook2Id = Test.getStandardPricebookId(),
                Billing_Account__c = acc.Id,
                Bill_To_Address__c = addr.Id
            ), 'OrderDefaults'
        );

        Test.startTest();
            insert testOrder;
        Test.stopTest();

        Order insertedOrder = getOrder('Master Contract Order');
        System.assertEquals(existingContract.Id, insertedOrder.Master_Contract__c,
            'Master_Contract__c should be populated from Opportunity.SBQQ__AmendedContract__c');
    }

    /**
     * @description Test that populateMasterContract does NOT set Master_Contract__c
     *              when the Opportunity has no SBQQ__AmendedContract__c.
     *              Bypasses Order_Before_Insert_Update flow which requires Bill_To_Address__c
     *              to be populated from the Quote or amended Contract.
     */
    @isTest
    static void populateMasterContractNoAmendedContractTest() {
        Account acc = getAccount();
        Address__c addr = getAddress();

        Automation_Controls__c controls = Automation_Controls__c.getInstance();
        controls.Active__c = true;
        controls.Bypass_Flows__c = true;
        controls.Order_Bypass__c = true;
        upsert controls;

        Opportunity noAmendOpp = (Opportunity) TestFactory.buildSObject(
            new Opportunity(
                Name = 'No Amend Opp',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today(),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_AMENDMENT_TO_SUPERCEDE,
                AccountId = acc.Id,
                OP4I_Auto_Number_Deal_ID__c = 'No Amend Opp'
            ), 'OpportunityDefaults'
        );
        insert noAmendOpp;

        Order testOrder = (Order)TestFactory.buildSObject(
            new Order(
                Name = 'No Master Contract Order',
                AccountId = acc.Id,
                OpportunityId = noAmendOpp.Id,
                Status = OrderConstants.STATUS_DRAFT,
                Pricebook2Id = Test.getStandardPricebookId(),
                Billing_Account__c = acc.Id,
                Bill_To_Address__c = addr.Id
            ), 'OrderDefaults'
        );

        Test.startTest();
            insert testOrder;
        Test.stopTest();

        Order insertedOrder = getOrder('No Master Contract Order');
        System.assertEquals(null, insertedOrder.Master_Contract__c,
            'Master_Contract__c should be null when Opportunity has no amended contract');
    }

    /***********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description get order by name
     * @param name
     * @return Order
     */
    private static Order getOrder(String name) {
        return [SELECT Id, Name, Master_Contract__c FROM Order WHERE Name =:name];
    }

    /**
     * @description get contract
     * @return Contract
     */
    private static Contract getContract() {
        return [SELECT Id, Name, Status, Consolidated_Quote__c FROM Contract LIMIT 1];
    }

    /**
     * @description get opportunity
     * @param name
     * @return Opportunity
     */
    private static Opportunity getOpportunity(String name) {
        String compareString = '%' + name + '%';
        return [SELECT Id, StageName FROM Opportunity WHERE Name LIKE :compareString LIMIT 1];
    }

    /**
     * @description get opportunity by OP4I_Auto_Number_Deal_ID__c
     * @param dealId
     * @return Opportunity
     */
    private static Opportunity getOpportunityByDealId(String dealId) {
        return [SELECT Id, StageName FROM Opportunity WHERE OP4I_Auto_Number_Deal_ID__c = :dealId LIMIT 1];
    }

    /**
     * @description get account
     * @return Account
     */
    private static Account getAccount() {
        return [SELECT Id, Type FROM Account LIMIT 1];
    }

    /**
     * @description get address
     * @return Address__c
     */
    private static Address__c getAddress() {
        return [SELECT Id FROM Address__c LIMIT 1];
    }
}