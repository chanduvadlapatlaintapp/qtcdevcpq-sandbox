/**
 * @author : Ratan Paul
 * @date : 04/02/2025
 * @description : Test class for RetryContractRenewalBatch batch job.
*                     Ensures batch execution updates contracts and deletes quotes correctly.
 * @jira : BIZ-68101
 **/
@isTest
private class RetryContractRenewalBatchTest {
    
    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    /**
     * @description Test Setup
     */
    @testSetup
    static void setupTestData() {
        // Create an admin user for testing
        User adminUser = (User)TestFactory.createSObject(
            new User(
                LastName = 'RetryContractRenewalBatchTest',
                Email = 'admin@test.com'
            ), 'AdminUserDefaults');
        System.runAs(adminUser) {
            // Create an Account
            Account objAcc = (Account)TestFactory.createSObject(
                new Account(
                    Name = 'test acc1'
                ), 'AccountDefaults');
            
            // Create test Opportunities
            List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
                new Opportunity(
                    Name = 'Test Opportunity', 
                    StageName = 'Prospecting', 
                    CloseDate = Date.today().addMonths(1),
                    OwnerId = adminUser.Id,
                    AccountId = objAcc.Id
                ), 1, 'OpportunityDefaults'
            );
            
          	SBQQ.TriggerControl.disable();
            // Create test Contracts
            List<Contract> contracts = new List<Contract>();
            for (Opportunity opp : opportunities) {
                Contract con = (Contract)TestFactory.buildSObject(
                    new Contract(
                        Name = 'Test Contract ' + opp.Name, 
                        SBQQ__RenewalQuoted__c = true, 
                        SBQQ__RenewalForecast__c = true, 
                        EndDate = Date.today().addDays(100),
                        SBQQ__Opportunity__c = opp.Id,
                        AccountId = opp.AccountId
                    )
                );
                contracts.add(con);
            }
            insert contracts;
            SBQQ.TriggerControl.enable();
            
            Test.startTest();
            // Create test Opportunities with lookup to Contracts (SBQQ__RenewedContract__c)
            for (Integer i = 0; i < opportunities.size(); i++) {
                opportunities[i].SBQQ__RenewedContract__c = contracts[i].Id;
            }
            update opportunities;
            
            // Create test RecordJob records with failed status
            List<SBQQ__RecordJob__c> jobRecords = new List<SBQQ__RecordJob__c>();
            for (Contract con : contracts) {
                SBQQ__RecordJob__c job = new SBQQ__RecordJob__c(
                    SBQQ__JobStatus__c = 'Failed',
                    SBQQ__RecordId__c = con.Id + '::RenewContract',
                    SBQQ__JobDetails__c = 'Job failed due to error'
                );
                jobRecords.add(job);
            }
            insert jobRecords;
            // Create test Quotes associated with Opportunities (SBQQ__Opportunity2__c)
            List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
            for (Opportunity opp : opportunities) {
                SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.buildSObject(
                    new SBQQ__Quote__c(
                        SBQQ__Primary__c = true, 
                        SBQQ__Opportunity2__c = opp.Id 
                    ),'SBQQQuoteDefaults'
                );
                quotes.add(quote);
            }
            insert quotes;
            Test.stopTest();
        }
    }
    
    /**
     * @description unit test for batch execution
     */
    @isTest
    static void testBatchExecution() {
        // Run the test as an admin user
        User adminUser = getUser('admin@test.com');
        System.runAs(adminUser) {
            Test.startTest();
            RetryContractRenewalBatch batch = new RetryContractRenewalBatch();
            Database.executeBatch(batch);
            Test.stopTest();
            
            // Verify that the contract job status is updated
            for (Contract con : getContracts()) {
                System.assertNotEquals(null, con.Contract_Renewal_Job_Status__c, 'Job status should be updated.');
            }
            
            // Verify that quotes without line items are deleted
            Integer quoteCount = getQuotes().size();
            System.assertEquals(0, quoteCount, 'Quotes with no line items should be deleted.');
        }
    }
    
    /**
     * @description unit test for batch execution
     */
    @isTest
    static void testBatchExecution1() {
        // Run the test as an admin user
        User adminUser = getUser('admin@test.com');
        System.runAs(adminUser) {
            String query;
            Test.startTest();
            RetryContractRenewalBatch batch = new RetryContractRenewalBatch(query, 10);
            batch.executeBatch(query, 10);
            Test.stopTest();
            
            // Verify that the contract job status is updated
            for (Contract con : getContracts()) {
                System.assertNotEquals(null, con.Contract_Renewal_Job_Status__c, 'Job status should be updated.');
            }
            
            // Verify that quotes without line items are deleted
            Integer quoteCount = getQuotes().size();
            System.assertEquals(0, quoteCount, 'Quotes with no line items should be deleted.');
        }
    }

    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description Getter for user
     * @param email
     * @return User
     */
    private static User getUser(String email) {
        return [SELECT Id FROM User WHERE Email = :email LIMIT 1];
    }

    /**
     * @description Getter for contracts
     * @return List<Contract>
     */
    private static List<Contract> getContracts() {
        return [SELECT Id, SBQQ__RenewalQuoted__c, Contract_Renewal_Job_Status__c FROM Contract];
    }

    /**
     * @description Getter for quotes
     * @return List<SBQQ__Quote__c>
     */
    private static List<SBQQ__Quote__c> getQuotes() {
        return [SELECT Id, SBQQ__Opportunity2__c FROM SBQQ__Quote__c];
    }

}