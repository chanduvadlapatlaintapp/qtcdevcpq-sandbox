/**
 * @description Test class for GenerateMissingRenewalLetters batch class
 * @author Pooja Hemrajani
 * @jira BIZ-68060
 */
@isTest
private class GenerateMissingRenewalLettersTest {
    
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
        // Create test Account
        Account testAccount = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account'
            ), 'AccountDefaults'
        );
        
        // Create test Opportunity
        Opportunity testOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = testAccount.Id
            ), 'OpportunityDefaults'
        );
        
        // Create test Quote
        TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = testOpp.Id,
                SBQQ__Account__c = testAccount.Id,
                SBQQ__StartDate__c = Date.today().addDays(30),
                Renewal_Quote_Type__c = 'Auto-Renewal',
                AVA_SFCPQ__AvaTaxMessage__c = QuoteConstants.AVA_TAX_MSG_UPTO_DATE,
                CurrencyISOCode = 'EUR'
            ), 
            'SBQQQuoteDefaults'
        );
        
        Contract contract = new Contract(
            Name = 'Test Contract ' + testOpp.Name, 
            SBQQ__RenewalQuoted__c = false, 
            SBQQ__RenewalForecast__c = false, 
            EndDate = Date.today().addDays(80),              // within 90 days -> proforma window
            First_Segment_Months__c = 15,                    // triggers the (>12 && <24) path (if intended)
            SBQQ__RenewalTerm__c = 12,
            Renewals_Pause__c = false,                       // must be false to create quote
            SBQQ__Opportunity__c = testOpp.Id,
            AccountId = testAccount.Id,
            Subsidiary__c = '01:200 Integration Appliance (US)',
            Status = ContractConstants.STATUS_DRAFT
        );
        insert contract;
        contract.Status = ContractConstants.STATUS_PARTIALLY_SUPERSEDED;
    	update contract;
        
        testOpp.SBQQ__RenewedContract__c = contract.Id;
        update testOpp;
    }
    
    /**********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/
    /**
     * @description Test batch execution with default query
     */
    @isTest
    static void testBatchExecution() {
        Test.startTest();
            GenerateMissingRenewalLetters batch = new GenerateMissingRenewalLetters();
            Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify that renewal letter was created
        List<Proforma_Invoice__c> renewalLetters = getRenewalLetters();
        
        System.assertEquals(1, renewalLetters.size(), 'Should have created one renewal letter');
        System.assertEquals(RenewalLetterConstants.STATUS_INITIATED, renewalLetters[0].Status__c, 'Renewal letter should be in Initiated status');
    }
    
    /**
     * @description Test batch execution with custom query
     */
    @isTest
    static void testBatchExecutionWithCustomQuery() {
        String customQuery = 'SELECT Id, AVA_SFCPQ__AvaTaxMessage__c, SBQQ__StartDate__c, ' +
                           'Renewal_Letter__c, Renewal_Quote_Type__c, ' +
                           'SBQQ__Primary__c, SBQQ__Ordered__c, CurrencyISOCode ' +
                           'FROM SBQQ__Quote__c ' +
                           'WHERE Renewal_Letter__c = NULL ' +
                           'AND SBQQ__StartDate__c >= TODAY ' +
                           'AND SBQQ__StartDate__c <= NEXT_N_DAYS:90 ' +
                           'AND Renewal_Quote_Type__c = \'Auto-Renewal\' ' +
                           'AND SBQQ__Primary__c = TRUE ' +
                           'AND SBQQ__Ordered__c = FALSE';
        
        Test.startTest();
            GenerateMissingRenewalLetters batch = new GenerateMissingRenewalLetters(customQuery, 1);
            Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify that renewal letter was created
        List<Proforma_Invoice__c> renewalLetters = getRenewalLetters();
        
        System.assertEquals(1, renewalLetters.size(), 'Should have created one renewal letter');
        System.assertEquals(RenewalLetterConstants.STATUS_INITIATED, renewalLetters[0].Status__c, 'Renewal letter should be in Initiated status');

        // Verify that quote was updated to trigger tax calculation
        SBQQ__Quote__c updatedQuote = getQuote();   
        System.assertEquals(false, updatedQuote.AVA_SFCPQ__Quote_AutomateTaxCalculation__c, 
            'Quote should be marked for tax calculation');
        System.assertEquals(updatedQuote.CurrencyISOCode, renewalLetters[0].CurrencyISOCode, 
            'CurrencyISOCode should match between Quote and Renewal Letter');
    }
    
    /**
     * @description Test batch execution with quote needing tax calculation
     */
    @isTest
    static void testBatchExecutionWithTaxCalculation() {
        // Update quote to need tax calculation
        SBQQ__Quote__c quote = getQuote();
        quote.AVA_SFCPQ__AvaTaxMessage__c = 'Tax Calculation Needed';
        update quote;
        
        Test.startTest();
            GenerateMissingRenewalLetters batch = new GenerateMissingRenewalLetters();
            Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify that quote was updated to trigger tax calculation
        SBQQ__Quote__c updatedQuote = getQuote();
        
        System.assertEquals(false, updatedQuote.AVA_SFCPQ__Quote_AutomateTaxCalculation__c, 
            'Quote should be marked for tax calculation');
    }
    
    /**
     * @description Test schedulable execution
     */
    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
            GenerateMissingRenewalLetters schedulable = new GenerateMissingRenewalLetters();
            schedulable.execute(null);
        Test.stopTest();
        
        // Verify that renewal letter was created
        List<Proforma_Invoice__c> renewalLetters = getRenewalLetters();
        
        System.assertEquals(1, renewalLetters.size(), 'Should have created one renewal letter');
        System.assertEquals(RenewalLetterConstants.STATUS_INITIATED, renewalLetters[0].Status__c, 'Renewal letter should be in Initiated status');
    }

    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description Get renewal letters
     * @return List<Proforma_Invoice__c>
     */
    private static List<Proforma_Invoice__c> getRenewalLetters() {
        return [
            SELECT Id, Renewal_Quote__c, Status__c, CurrencyISOCode
            FROM Proforma_Invoice__c 
            WHERE Renewal_Quote__c != null
        ];
    }

    /**
     * @description Get quote
     * @return SBQQ__Quote__c
     */
    private static SBQQ__Quote__c getQuote() {
        return [
            SELECT Id, AVA_SFCPQ__AvaTaxMessage__c, AVA_SFCPQ__Quote_AutomateTaxCalculation__c,
                CurrencyISOCode
            FROM SBQQ__Quote__c 
            LIMIT 1
        ];
    }
}