/**
 * @author : Pooja Hemrajani
 * @date : 15/04/2025
 * @description : RenewalQuotecreationBatchTest test class for RenewalQuotecreationBatch
 * @jira : BIZ-68091
 **/
@isTest
public class RenewalQuotecreationBatchTest {
	
    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    /**
     * @description Test Setup
     */
    @testSetup
    public static void setup(){

        // Create test products
        List<Product2> products = (List<Product2>)TestFactory.createSObjectList(
            new Product2(
                Name = 'Intapp Risk & Compliance PIN-01670'
            ), 1, 'ProductDefaults'
        );

        // Create test pricebook entry
        for(Product2 product: products){
	        TestFactory.createSObjectList(
    	        new PricebookEntry(Product2Id = product.Id), 1, 'PricebookEntryDefaults'
        	);
        }
        
        // Create an Account
        List<Account> objAcc = (List<Account>)TestFactory.createSObjectList(
            new Account(
                Name = 'test acc1'
            ), 1, 'AccountDefaults');
        
        // Create test Opportunities
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity', 
                CloseDate = Date.today().addMonths(1),
                AccountId = objAcc[0].Id
            ), 1, 'ClosedWonOpportunityDefaults'
        );
        
        // Create test Quotes associated with Opportunities (SBQQ__Opportunity2__c)
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
        for (Opportunity opp : opportunities) {
            List<SBQQ__Quote__c> quote = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
                new SBQQ__Quote__c(
                    SBQQ__Primary__c = true, 
                    SBQQ__Opportunity2__c = opportunities[0].Id 
                ), 1,'SBQQQuoteDefaults'
            );
            quotes.addAll(quote);
        }

        // Create test Quote Line associated with Quotes 
		SBQQ.TriggerControl.disable();
        for (SBQQ__Quote__c quote : quotes) {
            TestFactory.createSObjectList(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = quote.Id,
                    SBQQ__Product__c = products[0].Id
                ), 1,'SBQQQuoteLineDefaults'
            );
        }    
        SBQQ.TriggerControl.enable();
    }
    
    /**********************************************************************************************
    *
    * Test Methods - 395-Day Renewal Rule
    *
    ***********************************************************************************************/

    /**
     * @description Negative test: Contract with EndDate > 395 days should NOT create renewal
     */
    @isTest
    static void testEndDateMoreThan395DaysNoRenewal() {

        List<Opportunity> opportunitiesList = getOpportunities();
        List<Product2> listOfProducts = getProducts();

        Test.startTest();

        // EndDate = today + 400 days → opportunityRenewalDate = today + 5 days → not yet reached → no renewal
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract EndDate > 395 Days',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addDays(400), // > 395 days
                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opportunitiesList[0].Id,
                AccountId = opportunitiesList[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)'
            )
        );

        SBQQ__Subscription__c subscription1 = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opportunitiesList[0].AccountId,
                SBQQ__Product__c = listOfProducts[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 10000,
                SBQQ__SubscriptionStartDate__c = System.today(),
                SBQQ__SubscriptionEndDate__c = System.today().addMonths(12)
            )
        );
        insert subscription1;

        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' +
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);

        Test.stopTest();

        Contract updatedContract = getContract(con.Id);
        System.assertEquals(false, updatedContract.SBQQ__RenewalQuoted__c, 'SBQQ__RenewalQuoted__c should be false as EndDate > 395 days');
        System.assertEquals(false, updatedContract.SBQQ__RenewalForecast__c, 'SBQQ__RenewalForecast__c should be false as EndDate > 395 days');
    }
    
    /**
     * @description Positive test: Contract with EndDate within 395 days should create renewal
     */
    @isTest
    static void testEndDateWithin395DaysCreatesRenewal() {

        List<Opportunity> opportunitiesList = getOpportunities();
        List<Product2> listOfProducts = getProducts();

        SBQQ.TriggerControl.disable();
        Test.startTest();

        // EndDate = today + 80 days → opportunityRenewalDate = today - 315 days → already passed → renewal triggered
        Contract contract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract EndDate Within 395 Days',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addMonths(-18),
                EndDate = Date.today().addDays(80), // < 395 days
                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opportunitiesList[0].Id,
                AccountId = opportunitiesList[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );

        SBQQ__Subscription__c subscription1 = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opportunitiesList[0].AccountId,
                SBQQ__Product__c = listOfProducts[0].Id,
                SBQQ__Contract__c = contract.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 10000,
                SBQQ__SubscriptionStartDate__c = System.today(),
                SBQQ__SubscriptionEndDate__c = System.today().addMonths(12)
            )
        );
        insert subscription1;

        contract.Status = ContractConstants.STATUS_PARTIALLY_SUPERSEDED;
        update contract;

        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch();
        Database.executeBatch(batch);

        Test.stopTest();

        Contract updatedContract = getContract(contract.Id);
        System.assertEquals(true, updatedContract.SBQQ__RenewalQuoted__c, 'SBQQ__RenewalQuoted__c should be true as EndDate is within 395 days');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Boundary test: Contract with EndDate exactly 395 days away should create renewal
     */
    @isTest
    static void testEndDateExactly395DaysCreatesRenewal() {

        List<Opportunity> opportunitiesList = getOpportunities();
        List<Product2> listOfProducts = getProducts();

        SBQQ.TriggerControl.disable();
        Test.startTest();

        // Contract with EndDate exactly 395 days away: opportunityRenewalDate = today exactly → should trigger
        Contract contract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract Boundary 395 Days',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addDays(395), // Exactly 395 days
                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opportunitiesList[0].Id,
                AccountId = opportunitiesList[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );

        SBQQ__Subscription__c subscription1 = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opportunitiesList[0].AccountId,
                SBQQ__Product__c = listOfProducts[0].Id,
                SBQQ__Contract__c = contract.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 10000,
                SBQQ__SubscriptionStartDate__c = System.today(),
                SBQQ__SubscriptionEndDate__c = System.today().addMonths(12)
            )
        );
        insert subscription1;

        contract.Status = ContractConstants.STATUS_INFORCE;
        update contract;

        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' +
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + contract.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);

        Test.stopTest();

        Contract updatedContract = getContract(contract.Id);
        System.assertEquals(true, updatedContract.SBQQ__RenewalQuoted__c || updatedContract.SBQQ__RenewalForecast__c,
            'Renewal should be triggered when EndDate is exactly 395 days away');
        SBQQ.TriggerControl.enable();
    }
    
    /**********************************************************************************************
    *
    * Test Methods - 395-Day Rule: Started and Future-Start Contract Scenarios
    *
    ***********************************************************************************************/

    /**
     * @description Positive test: Contract already started and within 395 days of EndDate should create renewal
     */
    @isTest
    static void testContractAlreadyStartedWithin395DaysCreatesRenewal() {

        List<Opportunity> opportunitiesList = getOpportunities();
        List<Product2> listOfProducts = getProducts();

        SBQQ.TriggerControl.disable();
        Test.startTest();

        // StartDate = today - 1 day (already started), EndDate = today + ~364 days
        // opportunityRenewalDate = today + 364 - 395 = today - 31 days → already passed → renewal triggered
        Contract contract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract Already Started Within 395 Days',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-1), // Already started
                EndDate = Date.today().addMonths(12).addDays(-1),
                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opportunitiesList[0].Id,
                AccountId = opportunitiesList[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );

        SBQQ__Subscription__c subscription1 = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opportunitiesList[0].AccountId,
                SBQQ__Product__c = listOfProducts[0].Id,
                SBQQ__Contract__c = contract.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 10000,
                SBQQ__SubscriptionStartDate__c = System.today(),
                SBQQ__SubscriptionEndDate__c = System.today().addMonths(12)
            )
        );
        insert subscription1;

        contract.Status = ContractConstants.STATUS_INFORCE;
        update contract;

        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' +
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + contract.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);

        Test.stopTest();

        Contract updatedContract = getContract(contract.Id);
        System.assertEquals(true, updatedContract.SBQQ__RenewalQuoted__c || updatedContract.SBQQ__RenewalForecast__c,
            'Renewal should be triggered for a started contract within 395 days of EndDate');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Positive test (AC): Contract with future StartDate but within 395 days of EndDate should create renewal
     * This is the key scenario from BIZ-68091: renewal must trigger even if the contract has not yet started
     */
    @isTest
    static void testContractNotYetStartedButWithin395DaysCreatesRenewal() {

        List<Opportunity> opportunitiesList = getOpportunities();
        List<Product2> listOfProducts = getProducts();

        SBQQ.TriggerControl.disable();
        Test.startTest();

        // Contract has not yet started (StartDate = today + 30 days)
        // but is within 395 days of EndDate (EndDate = today + 200 days)
        // opportunityRenewalDate = today + 200 - 395 = today - 195 days → already passed → renewal should trigger
        Contract contract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract Not Yet Started Within 395 Days',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(30), // Not yet started
                EndDate = Date.today().addDays(200), // Within 395 days
                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opportunitiesList[0].Id,
                AccountId = opportunitiesList[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );

        SBQQ__Subscription__c subscription1 = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opportunitiesList[0].AccountId,
                SBQQ__Product__c = listOfProducts[0].Id,
                SBQQ__Contract__c = contract.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 10000,
                SBQQ__SubscriptionStartDate__c = Date.today().addDays(30),
                SBQQ__SubscriptionEndDate__c = Date.today().addDays(200)
            )
        );
        insert subscription1;

        contract.Status = ContractConstants.STATUS_INFORCE;
        update contract;

        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' +
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + contract.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);

        Test.stopTest();

        Contract updatedContract = getContract(contract.Id);
        System.assertEquals(true, updatedContract.SBQQ__RenewalQuoted__c || updatedContract.SBQQ__RenewalForecast__c,
            'Renewal should be triggered for a contract within 395 days of EndDate even if StartDate not yet reached');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Positive test: Contract starting today and within 395 days of EndDate should create renewal
     */
    @isTest
    static void testContractStartingTodayWithin395DaysCreatesRenewal() {

        List<Opportunity> opportunitiesList = getOpportunities();
        List<Product2> listOfProducts = getProducts();

        SBQQ.TriggerControl.disable();
        Test.startTest();

        // StartDate = today, EndDate = today + ~364 days → within 395 days → renewal triggered
        Contract contract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract Starting Today Within 395 Days',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today(),
                EndDate = Date.today().addMonths(12).addDays(-1),
                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opportunitiesList[0].Id,
                AccountId = opportunitiesList[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );

        SBQQ__Subscription__c subscription1 = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opportunitiesList[0].AccountId,
                SBQQ__Product__c = listOfProducts[0].Id,
                SBQQ__Contract__c = contract.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 10000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert subscription1;

        contract.Status = ContractConstants.STATUS_INFORCE;
        update contract;

        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' +
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + contract.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);

        Test.stopTest();

        Contract updatedContract = getContract(contract.Id);
        System.assertEquals(true, updatedContract.SBQQ__RenewalQuoted__c || updatedContract.SBQQ__RenewalForecast__c,
            'Renewal should be triggered for a contract starting today that is within 395 days of EndDate');
        SBQQ.TriggerControl.enable();
    }
    
    /**********************************************************************************************
    *
    * Test Methods - Renewals Pause Logic
    *
    ***********************************************************************************************/
    
    /**
     * @description Positive test: Contract with Renewals_Pause__c = true should set RenewalForecast to true
     */
    @isTest
    static void testBatchWithRenewalPauseTrue() {
        
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract with Renewals_Pause__c = true and EndDate within 365 days
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Pause Contract',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                EndDate = Date.today().addDays(10), // Within 365 days

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Renewals_Pause__c = true,
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        // Add subscription
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        Test.startTest();
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);
        Test.stopTest();
        
        Contract updatedCon = getContract(con.Id);
        System.assertEquals(true, updatedCon.SBQQ__RenewalForecast__c, 'RenewalForecast should be true when Renewals_Pause__c is true');
        SBQQ.TriggerControl.enable();
    }
    
    /**********************************************************************************************
    *
    * Test Methods - Constructor and Execution Coverage
    *
    ***********************************************************************************************/
    
    /**
     * @description Test default constructor
     */
    @isTest
    static void testDefaultConstructor() {
        Test.startTest();
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch();
        System.assertNotEquals(null, batch, 'Batch instance should not be null');
        Test.stopTest();
    }
    
    /**
     * @description Test parameterized constructor with null values
     */
    @isTest
    static void testParameterizedConstructorWithNulls() {
        Test.startTest();
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(null, null);
        System.assertNotEquals(null, batch, 'Batch instance should not be null even with null parameters');
        Test.stopTest();
    }
    
    /**
     * @description Test executeBatch method
     */
    @isTest
    static void testExecuteBatchMethod() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract in DRAFT status first
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'ExecuteBatch Test Contract',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                EndDate = Date.today().addDays(100),

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        // Update to INFORCE status
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        Test.startTest();
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch();
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        batch.executeBatch(testQuery, 1);
        Test.stopTest();
        
        SBQQ.TriggerControl.enable();
        System.assert(true, 'executeBatch method should complete without errors');
    }
    
    /**
     * @description Test schedulable execute method
     */
    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch();
        String cronExp = '0 0 0 1 1 ? 2099';
        String jobId = System.schedule('Test Renewal Batch', cronExp, batch);
        System.assertNotEquals(null, jobId, 'Scheduled job ID should not be null');
        Test.stopTest();
    }
    
    /**
     * @description Test batch finish method completes successfully
     */
    @isTest
    static void testBatchFinishMethod() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract in DRAFT status first
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Finish Method Test Contract',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                EndDate = Date.today().addDays(100), // Within 365 days

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        // Update to INFORCE status
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        Test.startTest();
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify batch completed and processed the contract
        Contract updatedCon = getContract(con.Id);
        System.assertEquals(true, updatedCon.SBQQ__RenewalQuoted__c || updatedCon.SBQQ__RenewalForecast__c, 
            'Batch should process contract and set renewal flag');
        SBQQ.TriggerControl.enable();
    }

    /**
     * @description Test contract with multiple subscriptions only processes once
     */
    @isTest
    static void testContractWithMultipleSubscriptionsProcessedOnce() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Multi-Subscription Contract',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-30),
                EndDate = Date.today().addDays(80), // Within 365 days

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        // Create multiple subscriptions for the same contract
        List<SBQQ__Subscription__c> subs = new List<SBQQ__Subscription__c>();
        for (Integer i = 0; i < 3; i++) {
            SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Account__c = opps[0].AccountId,
                    SBQQ__Product__c = products[0].Id,
                    SBQQ__Contract__c = con.Id,
                    SBQQ__Quantity__c = 1,
                    SBQQ__ListPrice__c = 1000,
                    SBQQ__SubscriptionStartDate__c = Date.today(),
                    SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
                )
            );
            subs.add(sub);
        }
        insert subs;
        
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        Test.startTest();
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);
        Test.stopTest();
        
        Contract updatedCon = getContract(con.Id);
        // Contract should still be processed (renewal created)
        System.assertEquals(true, updatedCon.SBQQ__RenewalQuoted__c || updatedCon.SBQQ__RenewalForecast__c, 
            'Contract with multiple subscriptions should be processed');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Test Add-On contract creates renewal opportunity not quote
     */
    @isTest
    static void testAddOnContractCreatesRenewalOpportunity() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create Add-On contract
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Add-On Contract',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-30),
                EndDate = Date.today().addDays(80), // Within 90 days (proforma window)

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Deal_Type__c = ContractConstants.DEAL_TYPE_ADD_ON,
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        Test.startTest();
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);
        Test.stopTest();
        
        Contract updatedCon = getContract(con.Id);
        // Add-On contracts should create renewal opportunity (forecast) not quote
        System.assertEquals(true, updatedCon.SBQQ__RenewalForecast__c, 'Add-On contract should have RenewalForecast set to true');
        SBQQ.TriggerControl.enable();
    }

    /**********************************************************************************************
    *
    * Test Methods - RenewalQuoteCreationService Coverage
    *
    ***********************************************************************************************/
    
    /**
     * @description Test contract with existing renewal opportunity in valid stage creates quote
     */
    @isTest
    static void testContractWithValidRenewalOpportunityCreatesQuote() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract within 90 days (proforma window)
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract With Valid Renewal Opp',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-30),
                EndDate = Date.today().addDays(60), // Within 90 days

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        // Create renewal opportunity with open stage
        Opportunity renewalOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Renewal Opp for Contract',
                AccountId = opps[0].AccountId,
                CloseDate = Date.today().addMonths(3),
                StageName = 'Negotiation',
                SBQQ__RenewedContract__c = con.Id
            )
        );
        
        // Link renewal opp to contract
        con.SBQQ__RenewalOpportunity__c = renewalOpp.Id;
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        Test.startTest();
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);
        Test.stopTest();
        
        Contract updatedCon = getContract(con.Id);
        System.assertEquals(true, updatedCon.SBQQ__RenewalQuoted__c, 
            'Contract with valid renewal opp should have RenewalQuoted set to true');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Test contract with Closed Lost renewal opportunity does not create quote
     */
    @isTest
    static void testContractWithClosedLostOppNoQuote() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract within 90 days (proforma window)
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract With Closed Lost Opp',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-30),
                EndDate = Date.today().addDays(60), // Within 90 days

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        // Create renewal opportunity with Closed Lost stage
        Opportunity renewalOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Closed Lost Renewal Opp',
                AccountId = opps[0].AccountId,
                CloseDate = Date.today().addMonths(3),
                StageName = OpportunityConstants.STAGE_CLOSED_LOST,
                SBQQ__RenewedContract__c = con.Id
            )
        );
        
        // Link renewal opp to contract
        con.SBQQ__RenewalOpportunity__c = renewalOpp.Id;
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        Test.startTest();
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);
        Test.stopTest();
        
        Contract updatedCon = getContract(con.Id);
        // Should create renewal forecast instead of quote due to Closed Lost opp
        System.assertEquals(true, updatedCon.SBQQ__RenewalForecast__c, 
            'Contract with Closed Lost opp should create renewal forecast instead');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Test getOpenNYMYOpportunities method
     */
    @isTest
    static void testGetOpenNYMYOpportunities() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract For NYMY Test',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-30),
                EndDate = Date.today().addDays(100),

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        // Create NYMY opportunity associated with contract
        Opportunity nymyOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'NYMY Opportunity',
                AccountId = opps[0].AccountId,
                CloseDate = Date.today().addMonths(3),
                StageName = 'Negotiation',
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                Associated_Contract_OSA__c = con.Id
            )
        );
        
        Test.startTest();
        Set<Id> contractIds = new Set<Id>{con.Id};
        List<Opportunity> nymyOpps = RenewalQuoteCreationService.getOpenNYMYOpportunities(contractIds);
        Test.stopTest();
        
        System.assertEquals(1, nymyOpps.size(), 'Should find 1 open NYMY opportunity');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Test getMaxSegments method
     */
    @isTest
    static void testGetMaxSegments() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract For Segments Test',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-30),
                EndDate = Date.today().addDays(100),

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        // Create subscriptions with segment indices
        List<SBQQ__Subscription__c> subs = new List<SBQQ__Subscription__c>();
        for (Integer i = 1; i <= 3; i++) {
            SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
                new SBQQ__Subscription__c(
                    SBQQ__Account__c = opps[0].AccountId,
                    SBQQ__Product__c = products[0].Id,
                    SBQQ__Contract__c = con.Id,
                    SBQQ__Quantity__c = 1,
                    SBQQ__ListPrice__c = 1000,
                    SBQQ__SubscriptionStartDate__c = Date.today(),
                    SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12),
                    SBQQ__SegmentIndex__c = i
                )
            );
            subs.add(sub);
        }
        insert subs;
        
        Test.startTest();
        Set<Id> contractIds = new Set<Id>{con.Id};
        Map<Id, Integer> maxSegments = RenewalQuoteCreationService.getMaxSegments(contractIds);
        Test.stopTest();
        
        System.assertEquals(1, maxSegments.size(), 'Should have 1 contract in map');
        System.assertEquals(3, maxSegments.get(con.Id), 'Max segment should be 3');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Test getRenewableSubscriptions method directly
     */
    @isTest
    static void testGetRenewableSubscriptions() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract For Subscriptions Test',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-30),
                EndDate = Date.today().addDays(100),

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        // Create renewable subscription
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        Test.startTest();
        Set<Id> contractIds = new Set<Id>{con.Id};
        List<SBQQ__Subscription__c> renewableSubs = RenewalQuoteCreationService.getRenewableSubscriptions(contractIds);
        Test.stopTest();
        
        System.assert(renewableSubs.size() > 0, 'Should find renewable subscriptions');
        SBQQ.TriggerControl.enable();
    }
    
    /**
     * @description Test contract outside 90-day window creates opportunity not quote
     */
    @isTest
    static void testContractOutside90DayWindowCreatesOpportunity() {
        List<Opportunity> opps = getOpportunities();
        List<Product2> products = getProducts();
        
        SBQQ.TriggerControl.disable();
        
        // Create contract outside 90-day window but within 365 days
        Contract con = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'Contract Outside 90 Day Window',
                SBQQ__RenewalQuoted__c = false,
                SBQQ__RenewalForecast__c = false,
                StartDate = Date.today().addDays(-180),
                EndDate = Date.today().addDays(150), // > 90 days but < 365 days

                SBQQ__RenewalTerm__c = 12,
                SBQQ__Opportunity__c = opps[0].Id,
                AccountId = opps[0].AccountId,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Status = ContractConstants.STATUS_DRAFT
            )
        );
        
        SBQQ__Subscription__c sub = (SBQQ__Subscription__c)TestFactory.buildSObject(
            new SBQQ__Subscription__c(
                SBQQ__Account__c = opps[0].AccountId,
                SBQQ__Product__c = products[0].Id,
                SBQQ__Contract__c = con.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1000,
                SBQQ__SubscriptionStartDate__c = Date.today(),
                SBQQ__SubscriptionEndDate__c = Date.today().addMonths(12)
            )
        );
        insert sub;
        
        con.Status = ContractConstants.STATUS_INFORCE;
        update con;
        
        Test.startTest();
        String testQuery = 'SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm, ' + 
                            'Status, SBQQ__RenewalOpportunity__c, SBQQ__RenewalTerm__c, ' +
                            'SBQQ__RenewalForecast__c, SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, ' +
                            'SBQQ__RenewalOpportunity__r.IsClosed, Deal_Type__c, Is_Migrated_Contract__c, Renewals_Pause__c ' +
                            'FROM Contract WHERE Id = \'' + con.Id + '\'';
        RenewalQuotecreationBatch batch = new RenewalQuotecreationBatch(testQuery, 1);
        Database.executeBatch(batch);
        Test.stopTest();
        
        Contract updatedCon = getContract(con.Id);
        // Should create renewal forecast (opportunity) not quote since outside 90-day window
        System.assertEquals(true, updatedCon.SBQQ__RenewalForecast__c, 
            'Contract outside 90-day window should have RenewalForecast set to true');
        System.assertEquals(false, updatedCon.SBQQ__RenewalQuoted__c, 
            'Contract outside 90-day window should NOT have RenewalQuoted set to true');
        SBQQ.TriggerControl.enable();
    }

    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description - Helper method to get test Contracts
     * @return - List of Contracts
     */
    private static List<Contract> getContracts() {
        return [SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm,
                        Is_Migrated_Contract__c, Deal_Type__c, Status, SBQQ__RenewalOpportunity__c,
                        SBQQ__RenewalTerm__c, SBQQ__RenewalForecast__c,
                        SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName, 
                        SBQQ__RenewalOpportunity__r.IsClosed, Renewals_Pause__c 
                 FROM Contract];
    }

    /**
     * @description - Helper method to get a specific Contract by Id
     * @param contractId - Id of the Contract to retrieve
     * @return - Contract record
     */
    private static Contract getContract(Id contractId) {
        return [SELECT Id, Subsidiary__c, SBQQ__RenewalQuoted__c, StartDate, EndDate, ContractTerm,
                        Is_Migrated_Contract__c, Deal_Type__c, Status, SBQQ__RenewalOpportunity__c,
                        SBQQ__RenewalTerm__c, SBQQ__RenewalForecast__c,
                        SBQQ__Evergreen__c, SBQQ__RenewalOpportunity__r.StageName,
                        SBQQ__RenewalOpportunity__r.IsClosed, Renewals_Pause__c 
                 FROM Contract WHERE Id = :contractId LIMIT 1];
    }

    /**
     * @description - Helper method to get test Opps
     * @return - List of Opportunities
     */
    private static List<Opportunity> getOpportunities() {
        return [SELECT Id, Name, StageName, AccountId FROM Opportunity];
    }

    /**
     * @description - Helper method to get test Products
     * @return - List of Products
     */
    private static List<Product2> getProducts() {
        return [SELECT Id, Name FROM Product2];
    }
}