/**
 * @description  Test class for QuoteLineItemTriggerHandler. The related trigger is SBQQQuoteLineTrigger.
 * @author       Manisha
 * @date         2025-07-02
 * @jira         N/A
 */
@isTest
public class QuoteLineItemTriggerHandlerTest {

    /***********************************************************************************************
    *
    * Shared Test Data Setup
    *
    ***********************************************************************************************/

    /**
     * @description Inserts shared test data using TestFactory.
     */
    @testSetup
    static void setupTestData() {
        // Create Product
        List<Product2> products = (List<Product2>) TestFactory.createSObjectList(
            new Product2(Name = 'Intapp Risk & Compliance PIN-01670'),
            1,
            'ProductDefaults'
        );

        // Create PricebookEntry for Product
        for (Product2 product : products) {
            TestFactory.createSObjectList(
                new PricebookEntry(Product2Id = product.Id),
                1,
                'PricebookEntryDefaults'
            );
        }

        // Create Account
        List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
            new Account(Name = 'Test Account'),
            1,
            'AccountDefaults'
        );

        // Create Opportunity
        List<Opportunity> opportunities = (List<Opportunity>) TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ),
            1,
            'OpportunityDefaults'
        );

        // Create Quotes for Opportunities
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
        for (Opportunity opp : opportunities) {
            quotes.addAll((List<SBQQ__Quote__c>) TestFactory.createSObjectList(
                new SBQQ__Quote__c(
                    SBQQ__Primary__c = true,
                    SBQQ__Opportunity2__c = opp.Id
                ),
                1,
                'SBQQQuoteDefaults'
            ));
        }

        // Create a Quote Line for each Quote
        for (SBQQ__Quote__c quote : quotes) {
            Product2 prod = products[0];

            SBQQ__QuoteLine__c parentQL = (SBQQ__QuoteLine__c) TestFactory.createSObject(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = quote.Id,
                    SBQQ__Product__c = prod.Id,
                    SBQQ__Quantity__c = 1,
                    SBQQ__CustomerPrice__c = 100,
                    Line_Item_Key__c = 'PARENT_KEY'
                ),
                'SBQQQuoteLineDefaults'
            );
        }
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/

    /**
     * @description Tests insert, update, delete, and undelete operations on SBQQ__QuoteLine__c.
     */
    @isTest
    static void testInsertUpdateDeleteQuoteLine() {
        // Get inserted Quote Line
        SBQQ__QuoteLine__c qli = getInsertedQuoteLine();

        // Update operation
        qli.SBQQ__Quantity__c = 10;
        update qli;

        // Delete operation
        delete qli;

        // Undelete operation (covers afterUnDelete)
        undelete qli;
    }

    /***********************************************************************************************
    *
    * Getter Methods for Shared Data
    *
    ***********************************************************************************************/

    /**
     * @description Retrieves an inserted Quote Line from the database.
     */
    private static SBQQ__QuoteLine__c getInsertedQuoteLine() {
        return [
            SELECT Id, SBQQ__Quantity__c 
            FROM SBQQ__QuoteLine__c 
            LIMIT 1
        ];
    }
}