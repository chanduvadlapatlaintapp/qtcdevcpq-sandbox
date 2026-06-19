/**
 * @description Test class for ContractStatusUpdateBatch
 * BIZ-69730: Tests for batch that closes opportunities on cancelled/superseded contracts
 * @author Sahal Mohamed
 * @jira BIZ-69730
 */
@isTest
public class ContractStatusUpdateBatchTest {
    
    @testSetup
    static void setup() {
        // Create Account
        Account testAccount = (Account)TestFactory.buildSObject(
            new Account(
                Name = 'Test Account',
                Type = AccountConstants.TYPE_CLIENT
            ), 'AccountDefaults'
        );
        insert testAccount;
        
        // Create Product
        Product2 testProduct = (Product2)TestFactory.buildSObject(
            new Product2(
                Name = 'Test Product',
                IsActive = true,
                SBQQ__SubscriptionType__c = 'Renewable'
            ), 'ProductDefaults'
        );
        insert testProduct;
        
        // Create Contract flagged for opportunity closure (simulates cancelled contract)
        Contract testContract = (Contract)TestFactory.buildSObject(
            new Contract(
                Name = 'Test Contract',
                AccountId = testAccount.Id,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addMonths(12),
                Pending_Opp_Closure__c = true
            ), 'ContractDefaults'
        );
        insert testContract;
        
        // Activate the contract then set to Cancelled
        testContract.Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        update testContract;
        
        // Create NYMY Opportunity linked to the contract
        Opportunity nymyOpp = (Opportunity)TestFactory.buildSObject(
            new Opportunity(
                Name = 'NYMY Opportunity',
                AccountId = testAccount.Id,
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addMonths(3),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                Associated_Contract_OSA__c = testContract.Id
            ), 'OpportunityDefaults'
        );
        insert nymyOpp;
        
        // Create Contract NOT flagged for processing
        Contract unflaggedContract = (Contract)TestFactory.buildSObject(
            new Contract(
                Name = 'Unflagged Contract',
                AccountId = testAccount.Id,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addMonths(12),
                Pending_Opp_Closure__c = false
            ), 'ContractDefaults'
        );
        insert unflaggedContract;
        
        unflaggedContract.Status = ContractConstants.STATUS_INFORCE;
        update unflaggedContract;
    }
    
    @isTest
    static void testBatch_WithNoSubscriptions_ShouldCloseOpportunities() {
        // Contract with no subscriptions should have opportunities closed
        
        Test.startTest();
            ContractStatusUpdateBatch batch = new ContractStatusUpdateBatch();
            Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify NYMY opportunity was closed
        Opportunity nymyOpp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'NYMY Opportunity' LIMIT 1];
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opportunity should be closed when no active subscriptions exist');
        
        // Verify flag was reset
        Contract testContract = [SELECT Id, Pending_Opp_Closure__c FROM Contract WHERE Name = 'Test Contract' LIMIT 1];
        System.assertEquals(false, testContract.Pending_Opp_Closure__c,
            'Pending_Opp_Closure__c flag should be reset after processing');
    }
    
    @isTest
    static void testBatch_WithActiveSubscriptions_ShouldNotCloseOpportunities() {
        Contract testContract = [SELECT Id, AccountId FROM Contract WHERE Name = 'Test Contract' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];
        
        // Disable triggers to create subscription
        SBQQ.TriggerControl.disable();
        
        // Create an ACTIVE subscription (no TerminatedDate) - this should block opportunity closure
        SBQQ__Subscription__c activeSubscription = new SBQQ__Subscription__c(
            SBQQ__Account__c = testAccount.Id,
            SBQQ__Contract__c = testContract.Id,
            SBQQ__Product__c = testProduct.Id,
            SBQQ__Quantity__c = 1
        );
        insert activeSubscription;
        
        SBQQ.TriggerControl.enable();
        
        Test.startTest();
            ContractStatusUpdateBatch batch = new ContractStatusUpdateBatch();
            Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify NYMY opportunity was NOT closed (active subscription exists)
        Opportunity nymyOpp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'NYMY Opportunity' LIMIT 1];
        System.assertNotEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opportunity should NOT be closed when active subscriptions exist');
        
        // Verify flag was NOT reset (contract still needs processing)
        Contract updatedContract = [SELECT Id, Pending_Opp_Closure__c FROM Contract WHERE Name = 'Test Contract' LIMIT 1];
        System.assertEquals(true, updatedContract.Pending_Opp_Closure__c,
            'Pending_Opp_Closure__c flag should remain set when active subscriptions exist');
    }
    
    @isTest
    static void testBatch_WithTerminatedSubscriptions_ShouldCloseOpportunities() {
        Contract testContract = [SELECT Id, AccountId FROM Contract WHERE Name = 'Test Contract' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];
        
        // Disable triggers to create subscription
        SBQQ.TriggerControl.disable();
        
        // Create a TERMINATED subscription (with TerminatedDate) - this should allow opportunity closure
        SBQQ__Subscription__c terminatedSubscription = new SBQQ__Subscription__c(
            SBQQ__Account__c = testAccount.Id,
            SBQQ__Contract__c = testContract.Id,
            SBQQ__Product__c = testProduct.Id,
            SBQQ__Quantity__c = 1,
            SBQQ__TerminatedDate__c = Date.today()
        );
        insert terminatedSubscription;
        
        SBQQ.TriggerControl.enable();
        
        Test.startTest();
            ContractStatusUpdateBatch batch = new ContractStatusUpdateBatch();
            Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify NYMY opportunity WAS closed (all subscriptions terminated)
        Opportunity nymyOpp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'NYMY Opportunity' LIMIT 1];
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opportunity should be closed when all subscriptions are terminated');
        
        // Verify flag was reset
        Contract updatedContract = [SELECT Id, Pending_Opp_Closure__c FROM Contract WHERE Name = 'Test Contract' LIMIT 1];
        System.assertEquals(false, updatedContract.Pending_Opp_Closure__c,
            'Pending_Opp_Closure__c flag should be reset after successful processing');
    }
    
    @isTest
    static void testBatch_UnflaggedContract_ShouldNotBeProcessed() {
        // The unflagged contract should not be processed
        
        Test.startTest();
            ContractStatusUpdateBatch batch = new ContractStatusUpdateBatch();
            Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify unflagged contract was not processed
        Contract unflaggedContract = [SELECT Id, Status FROM Contract WHERE Name = 'Unflagged Contract' LIMIT 1];
        System.assertEquals(ContractConstants.STATUS_INFORCE, unflaggedContract.Status,
            'Unflagged contract should not be affected');
    }
    
    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
            String cronExp = '0 0 0 ? * * *';
            ContractStatusUpdateBatch batch = new ContractStatusUpdateBatch();
            String jobId = System.schedule('Test Contract Opp Closure Batch', cronExp, batch);
        Test.stopTest();
        
        // Verify job was scheduled
        List<CronTrigger> scheduledJobs = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, scheduledJobs.size(), 'Job should be scheduled');
    }
    
    @isTest
    static void testDefaultConstructor() {
        Test.startTest();
            ContractStatusUpdateBatch batch = new ContractStatusUpdateBatch();
            Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify opportunities were closed (no subscriptions = all terminated)
        Opportunity nymyOpp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'NYMY Opportunity' LIMIT 1];
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opportunity should be closed');
    }
    
    @isTest
    static void testCustomQueryConstructor() {
        String customQuery = 'SELECT Id, Status, AccountId ' +
                            'FROM Contract WHERE Pending_Opp_Closure__c = true AND Name = \'Test Contract\'';
        
        Test.startTest();
            ContractStatusUpdateBatch batch = new ContractStatusUpdateBatch(customQuery);
            Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify opportunities were closed
        Opportunity nymyOpp = [SELECT Id, StageName FROM Opportunity WHERE Name = 'NYMY Opportunity' LIMIT 1];
        System.assertEquals(OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED, nymyOpp.StageName,
            'NYMY Opportunity should be closed with custom query');
    }
}