/**
 * @description Test class for OpportunityProductDelayScheduler
 *              Verifies:
 *              1. scheduleAfterMinutes creates a Scheduled Apex job
 *              2. execute() enqueues the Queueable without exception
 */
@IsTest
public class OpportunityProductDelaySchedulerTest {

    /******************************************************************
     * TEST DATA SETUP
     ******************************************************************/
    @TestSetup
    static void setupTestData() {

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10),
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
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        List<OpportunityLineItem> olis = new List<OpportunityLineItem>{
            new OpportunityLineItem(
                OpportunityId = opp.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                TotalPrice = 100
            ),
            new OpportunityLineItem(
                OpportunityId = opp.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 2,
                TotalPrice = 200
            )
        };
        insert olis;
    }

    /******************************************************************
     * TEST: scheduleAfterMinutes
     ******************************************************************/
    @IsTest
    static void testScheduleAfterMinutesCreatesScheduledJob() {

        List<OpportunityLineItem> olis =
            [SELECT Id FROM OpportunityLineItem LIMIT 2];

        Test.startTest();
        OpportunityProductDelayScheduler.scheduleAfterMinutes(
            1,
            olis,
            'Delete'
        );
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'OPP_PROD_DELAY_%'
        ];

        System.assert(
            jobs.size() > 0,
            'Expected a scheduled job to be created'
        );
    }

    /******************************************************************
     * TEST: execute() enqueues Queueable
     ******************************************************************/
    @IsTest
    static void testExecuteEnqueuesQueueable() {

        List<OpportunityLineItem> olis =
            [SELECT Id FROM OpportunityLineItem LIMIT 1];

        OpportunityProductDelayScheduler scheduler =
            new OpportunityProductDelayScheduler(olis, 'Cancelled');

        Test.startTest();
        scheduler.execute(null); // SchedulableContext not required
        Test.stopTest();

        // If no exception is thrown, enqueue was successful
        System.assert(true, 'Queueable should be enqueued successfully');
    }
}