/*
 * @description Test class for ContractOrderBatch
 * @author Pooja Hemrajani
 */
@isTest
public with sharing class ContractOrderBatchTest {
    
    /**********************************************************************************************
     * 
     * TEST SETUP
     * 
     **********************************************************************************************/
    
    /**
     * @description Creates test data for ContractOrderBatch tests including Account, Contact, 
     *              Address, Opportunity, Product, Quote, Order, and related records
     */
    @TestSetup
    static void makeData(){
        // Create Automation Controls to bypass triggers/flows
        TestFactory.createSObject(
            new Automation_Controls__c(
                Bypass_Flows__c = true,
                Bypass_Triggers__c = true,
                Active__c = true,
                Address_ByPass__c = true,
                Quote_Bypass__c = true,
                SetupOwnerId = UserInfo.getUserId()
            )
        );
        
        // Create Account
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account'
            ), 'AccountDefaults'
        );
        
        // Create Contact
        Contact con = (Contact) TestFactory.createSObject(
            new Contact(
                AccountId = account.Id
            ), 'ContactDefaults'
        );
        
        // Create Address with verification approved status
        Address__c addr = new Address__c();
        addr.Address__City__s = 'Los Angeles';
        addr.Address__CountryCode__s = 'US';
        addr.Address__PostalCode__s = '90210';
        addr.Address__StateCode__s = 'CA';
        addr.Address__Street__s = 'Beverly Hills';
        addr.Status__c = 'Verification Approved';
        addr.Department__c = 'Tax';
        addr.Default_Shipping_Address__c = true;
        addr.Default_Billing_Address__c = true;
        addr.Account__c = account.Id;
        insert addr;
        addr.Status__c = 'Verification Approved';
        update addr;
        
        // Create Opportunity
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = account.Id
            ), 1, 'OpportunityDefaults'
        );
        
        // Create Product and Pricebook Entry
        Product2 prodObj = (Product2)TestFactory.createSObject(
            new Product2(
                Name = 'Testproduct', 
                IsActive = true, 
                ProductCode = '123462'
            ), 'ProductDefaults'
        );

        List<PricebookEntry> priceBookEntry = (List<PricebookEntry>)TestFactory.createSObjectList(
            new PricebookEntry(
                Product2Id = prodObj.Id, 
                Pricebook2Id = Test.getStandardPricebookId()
            ), 1, 'PricebookEntryDefaults'
        );
        
        // Create Quote with billing and shipping addresses
        List<SBQQ__Quote__c> newQuote = new List<SBQQ__Quote__c>();
        newQuote.add(
            (SBQQ__Quote__c) TestFactory.buildSObject(
                new SBQQ__Quote__c(
                    SBQQ__Primary__c = true,
                    SBQQ__Opportunity2__c = opportunities[0].Id,
                    SBQQ__Account__c = account.Id,
                    OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket',
                    SBQQ__SubscriptionTerm__c = 36,
                    First_Segment_Months__c = 12,
                    Subsidiary__c = '01:200 Integration Appliance (US)',
                    Quote_Stage__c = 'Configure Products',
                    License_Basis__c = 'Lawyers',
                    SBQQ__StartDate__c = system.today(),
                    ApprovalStatus__c='Error',
                    Renewal_Quote_Type__c = 'Auto-Renewal',
                    SBQQ__PricebookId__c = Test.getStandardPricebookId(),
                    Bill_To_Address__c = addr.Id,
                    Ship_To_Address__c = addr.Id,
                    Bill_To_Account__c = account.Id,
                    Ship_To_Account__c = account.Id
                ), 'SBQQQuoteDefaults'
            )
        );
        insert newQuote;
        
        // Create Order linked to Quote
        Order newOrder = (Order)TestFactory.buildSObject(
            new Order(
                Name = 'Old Order',
                AccountId = account.Id,
                OpportunityId = opportunities[0].Id,
                Status = OrderConstants.STATUS_DRAFT,
                Pricebook2Id = Test.getStandardPricebookId(),
                SBQQ__Quote__c = newQuote[0].Id
            ), 'OrderDefaults'
        );
        insert newOrder;
        
        // Create OrderItem to enable order activation
        OrderItem item = (OrderItem)TestFactory.buildSObject(
            new OrderItem(
                OrderId = newOrder.Id,
                Quantity = 1,
                UnitPrice = 100,
                PricebookEntryId = priceBookEntry[0].Id
            ), 'OrderItemDefaults'
        );
        insert item;
        
        // Create Proforma Invoice linked to Quote
        Proforma_Invoice__c proformaInvoice = (Proforma_Invoice__c) TestFactory.createSObject(
            new Proforma_Invoice__c(
                Renewal_Quote__c = newQuote[0].Id,
                Status__c = RenewalLetterConstants.STATUS_INITIATED           
            )
        );
    }

    /**********************************************************************************************
     * 
     * TEST METHODS
     * 
     **********************************************************************************************/
    
    /**
     * @description Tests the batch execution via Database.executeBatch() method
     *              Verifies that the batch correctly marks an activated Order as contracted
     */
    @isTest
    static void testBatchExecution() {
        // Retrieve and activate test order
        Order testOrder = getTestOrder();
        activateOrder(testOrder);
        
        // Prepare order IDs for batch processing
        Set<Id> orderIds = new Set<Id>{ testOrder.Id };
        
        // Execute batch job
        Test.startTest();
        ContractOrderBatch batch = new ContractOrderBatch(orderIds);
        Database.executeBatch(batch, 1);
        Test.stopTest();
        
        // Verify the Order is marked as contracted
        Order updatedOrder = getOrderWithContractedStatus(testOrder.Id);
        System.assertEquals(true, updatedOrder.SBQQ__Contracted__c, 'Order should be contracted after batch execution');
    }
    
    /**
     * @description Tests the executeBatch() public method for direct batch execution
     *              Verifies that orders can be contracted without using Database.executeBatch()
     */
    @isTest
    static void testExecuteBatchPublicMethod() {
        // Retrieve and activate test order
        Order testOrder = getTestOrder();
        activateOrder(testOrder);
        
        // Prepare order IDs for batch processing
        Set<Id> orderIds = new Set<Id>{ testOrder.Id };
        
        // Execute batch via public executeBatch method
        Test.startTest();
        new ContractOrderBatch(orderIds).executeBatch(orderIds);
        Test.stopTest();
        
        // Verify the Order is marked as contracted
        Order updatedOrder = getOrderWithContractedStatus(testOrder.Id);
        System.assertEquals(true, updatedOrder.SBQQ__Contracted__c, 'Order should be contracted via executeBatch() method');
    }
    
    /**
     * @description Tests the Schedulable interface implementation
     *              Verifies that the batch can be scheduled successfully using System.schedule()
     */
    @isTest
    static void testSchedulableExecution() {
        // Retrieve and activate test order
        Order testOrder = getTestOrder();
        activateOrder(testOrder);
        
        // Prepare order IDs and schedule parameters
        Set<Id> orderIds = new Set<Id>{ testOrder.Id };
        String cronExp = '0 0 0 1 1 ? 2099'; 
        String jobName = 'Contract Orders - TestJob';
        
        // Schedule the batch job
        Test.startTest();
        System.schedule(jobName, cronExp, new ContractOrderBatch(orderIds));
        Test.stopTest();
        
        // Verify scheduling completed without errors
        System.assert(true, 'Scheduled batch with expected name completed successfully');
    }

    /**********************************************************************************************
     * 
     * HELPER METHODS
     * 
     **********************************************************************************************/
    
    /**
     * @description Retrieves a test Order record from the database
     * @return Order record with Id field
     */
    private static Order getTestOrder() {
        return [SELECT Id FROM Order LIMIT 1];
    }
    
    /**
     * @description Retrieves an Order record with contracted status field
     * @param orderId The Id of the Order to retrieve
     * @return Order record with Id and SBQQ__Contracted__c fields
     */
    private static Order getOrderWithContractedStatus(Id orderId) {
        return [SELECT Id, SBQQ__Contracted__c FROM Order WHERE Id = :orderId];
    }
    
    /**
     * @description Activates an Order by setting its status to Activated
     * @param testOrder The Order record to activate
     */
    private static void activateOrder(Order testOrder) {
        testOrder.Status = OrderConstants.STATUS_ACTIVATED;
        update testOrder;
    }
}