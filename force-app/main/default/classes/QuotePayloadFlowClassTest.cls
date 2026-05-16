/**
 * @description : BIZ-74649 - Test class for QuotePayloadFlowClass. 
 *                Validates that quotes with valid Ids are sent to OP4i and the Pause Quote Payload flag is flipped as expected.
 * @author      : Manisha Sharma
 * @createdDate : Oct-10-2025
 */
@isTest
public class QuotePayloadFlowClassTest {

    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    @testSetup
    static void setupTestData() {
        // Create test products
        List<Product2> products = (List<Product2>)TestFactory.createSObjectList(
            new Product2(Name = 'Test Product', IsActive = true), 1, 'ProductDefaults'
        );

        // Create test pricebook entry
        for(Product2 product: products){
            List<PricebookEntry> priceBookEntry = (List<PricebookEntry>)TestFactory.createSObjectList(
                new PricebookEntry(Product2Id = product.Id, Pricebook2Id = Test.getStandardPricebookId()), 
                1, 
                'PricebookEntryDefaults'
            );
        }

        // Create an Account
        List<Account> accounts = (List<Account>)TestFactory.createSObjectList(
            new Account(Name = 'Test Account'), 1, 'AccountDefaults'
        );

        // Create test Opportunities
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ), 
            1, 
            'OpportunityDefaults'
        );

        // Create test Quotes associated with Opportunities
        List<SBQQ__Quote__c> quotes = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SBQQ__Account__c = accounts[0].Id,
                OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket',
                Pause_Quote_Payload__c = true // set TRUE to test reset logic
            ), 
            1, 
            'SBQQQuoteDefaults'
        );

        // Create test Quote Line associated with Quotes
        List<SBQQ__QuoteLine__c> testqli1 = (List<SBQQ__QuoteLine__c>)TestFactory.createSObjectList(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quotes[0].Id,
                SBQQ__Product__c = products[0].Id
            ), 
            1, 
            'SBQQQuoteLineDefaults'
        );
    }

    /**********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/
    @isTest
    static void testSendQuotePayload() {
        // Arrange
        SBQQ__Quote__c quote = [SELECT Id, Pause_Quote_Payload__c FROM SBQQ__Quote__c LIMIT 1];

        // Act
        Test.startTest();
        QuotePayloadFlowClass.sendQuotePayload(new List<Id>{quote.Id});
        Test.stopTest();

        // Assert
        SBQQ__Quote__c updatedQuote = [SELECT Id, Pause_Quote_Payload__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals(false, updatedQuote.Pause_Quote_Payload__c, 'Pause_Quote_Payload__c should be reset to false');
    }

    @isTest
    static void testSendQuotePayload_NoPauseFlag() {
        // Arrange: Create a new quote with Pause_Quote_Payload__c = false
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc.Id,
            SBQQ__Primary__c = true,
            OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket',
            Pause_Quote_Payload__c = false
        );
        insert quote;

        // Act
        Test.startTest();
        QuotePayloadFlowClass.sendQuotePayload(new List<Id>{quote.Id});
        Test.stopTest();

        // Assert: Flag remains false
        SBQQ__Quote__c updatedQuote = [SELECT Id, Pause_Quote_Payload__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals(false, updatedQuote.Pause_Quote_Payload__c, 'Pause_Quote_Payload__c should remain false');
    }

    @isTest
    static void testSendQuotePayload_BulkQuotes() {
        // Arrange: Insert multiple quotes with Pause_Quote_Payload__c = true
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
        for(Integer i=0;i<5;i++){
            quotes.add(new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = opp.Id,
                SBQQ__Account__c = acc.Id,
                OP4I_Sales_Segment__c = 'Segment ' + i,
                Pause_Quote_Payload__c = true
            ));
        }
        insert quotes;

        List<Id> quoteIds = new List<Id>();
        for(SBQQ__Quote__c q : quotes) quoteIds.add(q.Id);

        // Act
        Test.startTest();
        QuotePayloadFlowClass.sendQuotePayload(quoteIds);
        Test.stopTest();

        // Assert: All flags reset
        List<SBQQ__Quote__c> updatedQuotes = [SELECT Id, Pause_Quote_Payload__c FROM SBQQ__Quote__c WHERE Id IN :quoteIds];
        for(SBQQ__Quote__c q : updatedQuotes){
            System.assertEquals(false, q.Pause_Quote_Payload__c, 'Pause_Quote_Payload__c should be reset to false');
        }
    }
}