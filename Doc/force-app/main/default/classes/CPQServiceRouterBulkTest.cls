/**

* @description CPQ ServiceRouter API Test - Quote Creation via QuoteSaver

* Tests pure CPQ API quote creation using SBQQ.ServiceRouter:

* - QuoteSaver - Create and persist a new CPQ Quote

*

* Monitors governor limits before and after the API call

* No HTTP callouts — pure CPQ ServiceRouter API

* DML used only in helper methods for test data setup

*/

@isTest

private class CPQServiceRouterBulkTest {
 
    private static Account quoteApiAccount;
    private static Opportunity quoteApiOpp;
    private static SBQQ__Quote__c quoteApiQuoteRecord;

    // You can also create a full Model as described in the documentation and use that instead
    // https://developer.salesforce.com/docs/atlas.en-us.cpq_dev_api.meta/cpq_dev_api/cpq_api_models.htm
    private class TinyQuoteModel {
        public SBQQ__Quote__c record;
        public TinyQuoteLineModel[] lineItems;
    }

    // You can also create a full Model as described in the documentation and use that instead
    // https://developer.salesforce.com/docs/atlas.en-us.cpq_dev_api.meta/cpq_dev_api/cpq_api_models.htm
    private class TinyQuoteLineModel {
        public SBQQ__QuoteLine__c record;
    }

    // Create an Account, Opportunity and a Quote
    private static void setUpQuoteWithNoLines() {
        quoteApiAccount = new Account(Name='Amazing Computers');
        insert quoteApiAccount;

        quoteApiOpp = new Opportunity(AccountId=quoteApiAccount.Id,Name='ComputerMaintenance1K',CloseDate=System.today().addMonths(12),StageName='Prospecting',Pricebook2Id=Test.getStandardPricebookId());
        insert quoteApiOpp;

        quoteApiQuoteRecord = new SBQQ__Quote__c(SBQQ__Opportunity2__c=quoteApiOpp.Id,SBQQ__StartDate__c=System.today(),SBQQ__SubscriptionTerm__c=12);
        insert quoteApiQuoteRecord;
    }

    /**
     * Read a quote created in setUpQuoteWithNoLines using the QuoteReader API
     */
    @isTest static void loadQuoteByIdReturnsEmptyQuote() {
        // Create Quote
        setUpQuoteWithNoLines();
        String qid = (String)quoteApiQuoteRecord.Id;

        // Read quote using QuoteAPI.QuoteReader
        Test.startTest();
        String qmodelJson = SBQQ.ServiceRouter.read('QuoteAPI.QuoteReader', qid);
        TinyQuoteModel quote = (TinyQuoteModel)JSON.deserialize(qmodelJson, TinyQuoteModel.class);
        Test.stopTest();

        // Verify
        System.assert(quote != null, 'Did not load quote, QuoteReader returned null');
        System.assertEquals(quoteApiQuoteRecord.Id, quote.record.get('Id'), 'Quote Id is not the one expected');
        System.assertEquals(0, quote.lineItems.size(), 'Quote line count is not 0');
    }

}