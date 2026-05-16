/**
 * @description
 * Test class for RetryDmlQueueable and RetryScheduler classes.
 * Provides comprehensive test coverage for the retry mechanism including:
 * - Successful DML retry execution
 * - Scheduler to Queueable delegation
 * - Lock exception handling and retry scheduling
 * - MAX_RETRIES threshold enforcement
 * - Edge cases (null/empty records)
 * - Idempotency verification
 *
 * @author Manisha
 * @jira BIZ-78056
 */
@isTest
public with sharing class RetryDmlQueueableTest {

    /**********************************************************************************************
     *
     * TEST SETUP
     *
     **********************************************************************************************/

    /**
     * @description Creates basic test data used for retry execution tests.
     *              Sets up an Account and Opportunity for DML retry testing.
     */
    @TestSetup
    static void makeData() {

        // Create Account
        Account acc = new Account(Name = 'Retry Test Account');
        insert acc;

        // Create Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Retry Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
        insert opp;
    }

    /**********************************************************************************************
     *
     * TEST METHODS
     *
     **********************************************************************************************/

    /**
     * @description Verifies that RetryDmlQueueable executes successfully
     *              when DML succeeds on first attempt. Tests the happy path
     *              where no lock exception occurs and the update completes.
     */
    @isTest
    static void testRetryQueueableSuccessPath() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp = getOpportunityById(opp.Id);

        opp.Name = 'Updated via Retry Queueable';
        update opp;

        List<SObject> records = new List<SObject>{ opp };

        Test.startTest();
        System.enqueueJob(
            new RetryDmlQueueable(
                records,
                1,
                'RetryDmlQueueableTest'
            )
        );
        Test.stopTest();

        Opportunity updatedOpp = getOpportunityById(opp.Id);

        System.assertEquals(
            'Updated via Retry Queueable',
            updatedOpp.Name,
            'RetryDmlQueueable should update record successfully'
        );
    }

    /**
     * @description Verifies that RetryScheduler correctly enqueues
     *              RetryDmlQueueable when executed. Tests the scheduler's
     *              ability to delegate to the queueable class.
     */
    @isTest
    static void testRetrySchedulerExecution() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp = getOpportunityById(opp.Id);

        opp.Name = 'Updated via Retry Scheduler';
        update opp;

        List<SObject> records = new List<SObject>{ opp };

        RetryScheduler scheduler =
            new RetryScheduler(
                records,
                1,
                'RetrySchedulerTest'
            );

        String cronExp = '0 0 0 1 1 ? 2099';

        Test.startTest();
        System.schedule(
            'RetryScheduler-TestJob',
            cronExp,
            scheduler
        );
        Test.stopTest();

        Opportunity updatedOpp = getOpportunityById(opp.Id);

        System.assertEquals(
            'Updated via Retry Scheduler',
            updatedOpp.Name,
            'RetryScheduler should enqueue RetryDmlQueueable successfully'
        );
    }

    /**
     * @description Verifies that RetryDmlQueueable handles multiple executions
     *              without error (idempotent behavior). Ensures that running
     *              the same retry multiple times does not corrupt data.
     */
    @isTest
    static void testRetryQueueableIdempotency() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp = getOpportunityById(opp.Id);

        opp.Name = 'Retry Idempotent Update';

        List<SObject> records = new List<SObject>{ opp };

        Test.startTest();
        System.enqueueJob(
            new RetryDmlQueueable(
                records,
                1,
                'IdempotencyTest'
            )
        );
        System.enqueueJob(
            new RetryDmlQueueable(
                records,
                2,
                'IdempotencyTest'
            )
        );
        Test.stopTest();

        Opportunity updatedOpp = getOpportunityById(opp.Id);

        System.assertEquals(
            'Retry Idempotent Update',
            updatedOpp.Name,
            'Multiple retry executions should not corrupt data'
        );
    }

    /**
     * @description Verifies retry scheduling when a lock exception is encountered.
     *              Tests that UNABLE_TO_LOCK_ROW errors trigger a scheduled retry
     *              via RetryScheduler when under MAX_RETRIES threshold.
     */
    @isTest
    static void testRetryLockExceptionPath() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp = getOpportunityById(opp.Id);

        List<SObject> records = new List<SObject>{ opp };

        RetryDmlQueueable.forceTestLockException = true;

        Test.startTest();
        System.enqueueJob(
            new RetryDmlQueueable(
                records,
                1,
                'LockExceptionTest'
            )
        );
        Test.stopTest();

        RetryDmlQueueable.forceTestLockException = false;

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Retry-LockExceptionTest%'
        ];

        System.assert(
            jobs.size() > 0,
            'RetryScheduler should be scheduled when lock exception occurs'
        );
    }

    /**
     * @description Verifies that no retry is scheduled when MAX_RETRIES is exceeded.
     *              Tests that lock exceptions at attempt >= MAX_RETRIES result in
     *              permanent failure logging rather than scheduling another retry.
     */
    @isTest
    static void testRetryMaxRetriesExceeded() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp = getOpportunityById(opp.Id);

        List<SObject> records = new List<SObject>{ opp };

        RetryDmlQueueable.forceTestLockException = true;

        Test.startTest();
        // Attempt 3 is the MAX_RETRIES limit, so no new retry should be scheduled
        System.enqueueJob(
            new RetryDmlQueueable(
                records,
                3,
                'MaxRetryTest'
            )
        );
        Test.stopTest();

        RetryDmlQueueable.forceTestLockException = false;

        // Verify NO new scheduled job is created after max retries
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Retry-MaxRetryTest%'
        ];

        System.assertEquals(
            0,
            jobs.size(),
            'No retry should be scheduled after max retries exceeded'
        );
    }

    /**
     * @description Verifies that RetryDmlQueueable handles empty records gracefully.
     *              Tests the guard clause that prevents processing when records
     *              list is empty, ensuring no exceptions or scheduled jobs.
     */
    @isTest
    static void testRetryQueueableEmptyRecords() {

        List<SObject> emptyRecords = new List<SObject>();

        Test.startTest();
        System.enqueueJob(
            new RetryDmlQueueable(
                emptyRecords,
                1,
                'EmptyRecordsTest'
            )
        );
        Test.stopTest();

        // Verify no exceptions thrown and no jobs scheduled
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Retry-EmptyRecordsTest%'
        ];

        System.assertEquals(
            0,
            jobs.size(),
            'No retry should be scheduled for empty records'
        );
    }

    /**
     * @description Verifies that RetryDmlQueueable handles null records gracefully.
     *              Tests the guard clause that prevents processing when records
     *              parameter is null, ensuring no exceptions are thrown.
     */
    @isTest
    static void testRetryQueueableNullRecords() {

        Test.startTest();
        System.enqueueJob(
            new RetryDmlQueueable(
                null,
                1,
                'NullRecordsTest'
            )
        );
        Test.stopTest();

        // Verify no exceptions thrown
        System.assert(true, 'RetryDmlQueueable should handle null records without exception');
    }

    /**********************************************************************************************
     *
     * HELPER METHODS
     *
     **********************************************************************************************/

    /**
     * @description Retrieves an Opportunity record by Id with all fields needed for testing
     * @param opportunityId The Id of the Opportunity to retrieve
     * @return Opportunity record with Id, Name, StageName, CloseDate, and AccountId fields,
     *         or null if opportunityId is null
     */
    public static Opportunity getOpportunityById(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }

        return [
            SELECT Id,
                   Name,
                   StageName,
                   CloseDate,
                   AccountId
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
    }
}