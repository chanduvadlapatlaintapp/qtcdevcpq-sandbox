/**
* @description Test class for UpdateQuoteQueueable
* @author Sahal Mohamed
* @jira BIZ-68060
**/
@isTest
private class UpdateQuoteQueueableTest {
    
    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    /**
     * @description Test Setup
     */
    @TestSetup
    static void makeData(){
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account'
            ), 'AccountDefaults'
        );
        
        Contact con = (Contact) TestFactory.createSObject(
            new Contact(
                AccountId = account.Id
            ), 'ContactDefaults'
        );
        
        Contract ctr = (Contract) SmartFactory.createSObject('Contract');
        ctr.AccountId = account.Id;
        insert ctr;
        
        Opportunity opportunity = (Opportunity) SmartFactory.createSObject('Opportunity');
        opportunity.AccountId = account.Id;
        opportunity.Associated_Contract_OSA__c = ctr.Id;
        opportunity.Contract_Signer__c = con.Id;
        opportunity.Requested_Contract_Expiration__c = Date.today();
        opportunity.Initial_Software_Term_Length_Months__c = 12;
        opportunity.SBQQ__QuotePricebookId__c = Test.getStandardPricebookId();
        opportunity.OP4I_Auto_Number_Deal_ID__c = '12345';
        opportunity.Type = OpportunityConstants.TYPE_RENEWAL;
        opportunity.Quote_Start_Date__c = Date.today().addDays(30);
        insert opportunity;
        

        Product2 prodObj = (Product2) SmartFactory.createSObject('Product2');
        prodObj.Name = 'Testproduct';
        prodObj.IsActive = true;
        prodObj.ProductCode = '123462';
        insert prodObj;

        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=Test.getStandardPricebookId(), Product2Id=prodObj.id, UnitPrice=1, IsActive=True);
        insert pbe; 

        Test.startTest();
        SBQQ.TriggerControl.disable();
        // Create test Quote
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = opportunity.Id,
                SBQQ__Account__c = account.Id,
                SBQQ__StartDate__c = Date.today().addDays(30),
                Renewal_Quote_Type__c = 'Auto-Renewal',
                AVA_SFCPQ__AvaTaxMessage__c = QuoteConstants.AVA_TAX_MSG_UPTO_DATE
            ), 
            'SBQQQuoteDefaults'
        );
        SBQQ.TriggerControl.enable();
        Test.stopTest();
        Proforma_Invoice__c proformaInvoice = (Proforma_Invoice__c) TestFactory.createSObject(
            new Proforma_Invoice__c(
                Renewal_Quote__c = newQuote.Id,
                Status__c = RenewalLetterConstants.STATUS_INITIATED           
            )
        );
    }
    
    /**********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/
    /**
     * @description tests the record id extract
     */
    @IsTest
    static void UpdateQuoteQueueableTestMethod() {
        
        List<SBQQ__Quote__c> quotes = getQuotes();
        quotes[0].AVA_SFCPQ__AvaTaxMessage__c = 'Tax Calculation Needed';
        update quotes[0];

        Test.startTest();
        // Create and execute the Queueable
        UpdateQuoteQueueable queueable = 
            new UpdateQuoteQueueable(quotes);
        System.enqueueJob(queueable);
        Test.stopTest();
    }
    
    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description Getter for Quotes
     * @return List<Quote>
     */
    private static List<SBQQ__Quote__c> getQuotes() {
        return [SELECT Id, AVA_SFCPQ__AvaTaxMessage__c, SBQQ__StartDate__c, AVA_SFCPQ__Quote_AutomateTaxCalculation__c,
                       Renewal_Letter__c, Renewal_Quote_Type__c, Opportunity_Stage__c,
                       SBQQ__Primary__c, SBQQ__Ordered__c
                       FROM SBQQ__Quote__c  LIMIT 1];
    }

    /**
     * @description Getter for error logs
     * @return List<Error_Log__c>
     */
    private static List<Error_Log__c> getLogs() {
        return [SELECT Id, Process__c, Exception_Message__c, Sobject_Name__c FROM Error_Log__c LIMIT 1000];
    }

}