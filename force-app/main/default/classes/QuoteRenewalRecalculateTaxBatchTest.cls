/** 
 * @description  Test class for QuoteRenewalRecalculateTaxBatch
 */
@isTest
private class QuoteRenewalRecalculateTaxBatchTest {

    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    /**
     * @description Test Setup
     */
    @testSetup
    static void setup() {
        Automation_Controls__c settings = new Automation_Controls__c(
            SetupOwnerId = UserInfo.getUserId(),
            Active__c = true,
            Bypass_Triggers__c = true,
            Bypass_Flows__c = true
        );
        insert settings;
        // Set up the test data
        Account testAccount = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account'
            ), 'AccountDefaults'
        );

        Contract testContract = (Contract)TestFactory.createSObject(
            new Contract(
                AccountId = testAccount.Id,
                StartDate = Date.today(),
                ContractTerm = 12
            )
        );

        Opportunity testOpportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                CloseDate = Date.today(),
                AccountId = testAccount.Id,
                SBQQ__RenewedContract__c = testContract.Id,
                OP4I_Auto_Number_Deal_ID__c = '12345'
            ), 'OpportunityDefaults');


        SBQQ__Quote__c testQuote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = testOpportunity.Id,
                SBQQ__StartDate__c = Date.today(),
                SBQQ__Primary__c = true,
                Renewal_Quote_Type__c = QuoteConstants.RENEWAL_QUOTE_TYPE_AUTO_RENEWAL,
                SBQQ__Type__c = QuoteConstants.TYPE_RENEWAL
            ), 'SBQQQuoteDefaults'
        );

        Product2 prodObj = (Product2) TestFactory.createSObject(
            new Product2(
                Name = 'Testproduct',
                IsActive = true,
                ProductCode = '123462'
            ), 'ProductDefaults'
        );


        PricebookEntry pbe = (PricebookEntry)TestFactory.createSObject(
            new PricebookEntry(
                Product2Id = prodObj.Id
            ), 'PricebookEntryDefaults'
        );

        // Start the test
        Test.startTest();
            SBQQ.TriggerControl.disable();
            SBQQ__QuoteLine__c testqli1 = (SBQQ__QuoteLine__c)TestFactory.createSObject(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = testQuote.Id,
                    SBQQ__Product__c = prodObj.id,
                    Print_at_Quote__c = true,
                    SBQQ__CustomerPrice__c = 25,
                    SBQQ__PricebookEntryId__c = pbe.Id
                ), 'SBQQQuoteLineDefaults'
            );
            SBQQ.TriggerControl.enable();
            update testqli1;
        Test.stopTest();

    }

    /**********************************************************************************************
    *
    * unit tests
    *
    ***********************************************************************************************/
    /**
     * @description Test batch execution without default query
     */
    @IsTest
    static void testBatchExecution() {
        
        // Execute the batch
        String query = 'SELECT Id, Renewal_Quote_Type__c, SBQQ__Type__c, AVA_SFCPQ__AvaTaxMessage__c, ' + 
                                      'SBQQ__StartDate__c, AVA_SFCPQ__Quote_AutomateTaxCalculation__c, SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Renewal_to_be_created_Before_Days__c ' + 
                                      'FROM SBQQ__Quote__c';

        Test.startTest();

            QuoteRenewalRecalculateTaxBatch batchJob = new QuoteRenewalRecalculateTaxBatch(query, 1);
            Database.executeBatch(batchJob);

        Test.stopTest();

        // Verify the results
        SBQQ__Quote__c testQuote = getQuote();
        System.assertEquals(QuoteConstants.AVA_TAX_MSG_REFRESH, testQuote.AVA_SFCPQ__AvaTaxMessage__c, 'AvaTax message should be set to refresh');
    }

    /**
     * @description Test batch execution scheduler with default query
     */
    @IsTest
    static void testBatchScheduler() {
        Test.startTest();

            QuoteRenewalRecalculateTaxBatch batchJob = new QuoteRenewalRecalculateTaxBatch();
            batchJob.execute(null);

        Test.stopTest();

        // Verify the results
        SBQQ__Quote__c testQuote = getQuote();
        System.assertEquals(QuoteConstants.AVA_TAX_MSG_REFRESH, testQuote.AVA_SFCPQ__AvaTaxMessage__c, 'AvaTax message should be set to refresh');
    }

    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description Getter for quotes
     * @return List<SBQQ__Quote__c>
     */
    private static SBQQ__Quote__c getQuote() {
        return [SELECT AVA_SFCPQ__Quote_AutomateTaxCalculation__c, AVA_SFCPQ__AvaTaxMessage__c 
                FROM SBQQ__Quote__c LIMIT 1];
    }
}