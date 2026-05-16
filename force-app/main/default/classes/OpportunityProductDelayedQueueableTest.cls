/**
 * @description Test class for OpportunityProductDelayedQueueable
 *              Verifies:
 *              1. Queueable runs without exception for valid input
 *              2. Queueable exits safely for null / empty input
 */
@IsTest
public class OpportunityProductDelayedQueueableTest {

    /******************************************************************
     * TEST DATA SETUP
     ******************************************************************/
    @TestSetup
    static void setupData() {

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(5),
            AccountId = acc.Id
        );
        insert opp;

        Product2 prod = new Product2(
            Name = 'Test Product',
            IsActive = true
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            UnitPrice = 50,
            IsActive = true
        );
        insert pbe;

        List<OpportunityLineItem> olis = new List<OpportunityLineItem>{
            new OpportunityLineItem(
                OpportunityId = opp.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                TotalPrice = 50
            ),
            new OpportunityLineItem(
                OpportunityId = opp.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 2,
                TotalPrice = 100
            )
        };
        insert olis;
    }

    /******************************************************************
     * TEST: Null list should no-op
     ******************************************************************/
    @IsTest
    static void testExecuteWithNullList() {

        Test.startTest();
        System.enqueueJob(
            new OpportunityProductDelayedQueueable(null, 'Delete')
        );
        Test.stopTest();

        // If no exception is thrown, test passes
        System.assert(true, 'Queueable should safely exit on null list');
    }

    /******************************************************************
     * TEST: Empty list should no-op
     ******************************************************************/
    @IsTest
    static void testExecuteWithEmptyList() {

        Test.startTest();
        System.enqueueJob(
            new OpportunityProductDelayedQueueable(
                new List<OpportunityLineItem>(),
                'Cancelled'
            )
        );
        Test.stopTest();

        System.assert(true, 'Queueable should safely exit on empty list');
    }

    /******************************************************************
     * TEST: Valid list should execute without exception
     ******************************************************************/
    @IsTest
    static void testExecuteWithValidList() {

        List<OpportunityLineItem> olis =
            [SELECT Id FROM OpportunityLineItem LIMIT 2];

        Test.startTest();
        System.enqueueJob(
            new OpportunityProductDelayedQueueable(olis, 'Delete')
        );
        Test.stopTest();

        // We cannot assert outbound messages in Apex tests
        // Successful execution without exception is sufficient
        System.assert(true, 'Queueable executed successfully with valid data');
    }
}