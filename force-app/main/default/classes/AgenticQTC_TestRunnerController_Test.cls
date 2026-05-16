/**
 * AgenticQTC_TestRunnerController_Test
 *
 * Unit tests for AgenticQTC_TestRunnerController.
 * Covers: createTestRun, getTestRun, getRecentTestRuns, cancelTestRun.
 */
@IsTest
private class AgenticQTC_TestRunnerController_Test {

    // ─── createTestRun ───────────────────────────────────────────────────────

    @IsTest
    static void createTestRun_happyPath() {
        Test.startTest();
        String runId = AgenticQTC_TestRunnerController.createTestRun('agenticQtcQuantityIncrease');
        Test.stopTest();

        System.assertNotEquals(null, runId, 'Should return a record Id');

        Test_Run__c run = [SELECT Id, Status__c, Test_Suite__c, Requested_By__c
                           FROM Test_Run__c WHERE Id = :runId];
        System.assertEquals('PENDING',                     run.Status__c,    'Status should be PENDING');
        System.assertEquals('agenticQtcQuantityIncrease',  run.Test_Suite__c, 'Suite should be set');
        System.assertEquals(UserInfo.getUserId(),           run.Requested_By__c, 'Requester should be current user');
    }

    @IsTest
    static void createTestRun_blankSuite_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.createTestRun('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for blank testSuite');
    }

    @IsTest
    static void createTestRun_nullSuite_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.createTestRun(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for null testSuite');
    }

    // ─── getTestRun ──────────────────────────────────────────────────────────

    @IsTest
    static void getTestRun_returnsRunWithResults() {
        // Create a run
        Test_Run__c run = new Test_Run__c(
            Test_Suite__c   = 'demoSuite',
            Status__c       = 'PASSED',
            Tests_Passed__c = 3,
            Tests_Failed__c = 1,
            Duration_Ms__c  = 45000
        );
        insert run;

        // Create child results
        List<Test_Result__c> results = new List<Test_Result__c>{
            new Test_Result__c(
                Test_Run__c   = run.Id,
                Test_Name__c  = 'should load the contract list',
                Suite_Name__c = 'demoSuite',
                Status__c     = 'PASSED',
                Duration_Ms__c = 12000
            ),
            new Test_Result__c(
                Test_Run__c    = run.Id,
                Test_Name__c   = 'should generate PDF',
                Suite_Name__c  = 'demoSuite',
                Status__c      = 'FAILED',
                Duration_Ms__c = 8000,
                Error_Message__c = 'Timeout waiting for iframe'
            )
        };
        insert results;

        Test.startTest();
        AgenticQTC_TestRunnerController.TestRunWrapper w =
            AgenticQTC_TestRunnerController.getTestRun(run.Id);
        Test.stopTest();

        System.assertEquals(run.Id,    w.id,           'Id should match');
        System.assertEquals('PASSED',  w.status,       'Status should be PASSED');
        System.assertEquals('demoSuite', w.testSuite,  'Suite should match');
        System.assertEquals(3,          w.testsPassed, 'testsPassed should be 3');
        System.assertEquals(1,          w.testsFailed, 'testsFailed should be 1');
        System.assertEquals(45000,      w.durationMs,  'durationMs should be 45000');
        System.assertEquals(2,          w.testResults.size(), 'Should have 2 child results');

        // Spot-check second result
        AgenticQTC_TestRunnerController.TestResultWrapper failed = null;
        for (AgenticQTC_TestRunnerController.TestResultWrapper tr : w.testResults) {
            if (tr.status == 'FAILED') { failed = tr; }
        }
        System.assertNotEquals(null, failed, 'Should find the failed result');
        System.assertEquals('Timeout waiting for iframe', failed.errorMessage);
    }

    @IsTest
    static void getTestRun_notFound_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.getTestRun('a0000000000000000');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for missing run');
    }

    @IsTest
    static void getTestRun_blankId_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.getTestRun('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for blank Id');
    }

    // ─── getRecentTestRuns ───────────────────────────────────────────────────

    @IsTest
    static void getRecentTestRuns_returnsRecords() {
        List<Test_Run__c> toInsert = new List<Test_Run__c>();
        for (Integer i = 0; i < 5; i++) {
            toInsert.add(new Test_Run__c(
                Test_Suite__c = 'suite' + i,
                Status__c     = 'PASSED'
            ));
        }
        insert toInsert;

        Test.startTest();
        List<AgenticQTC_TestRunnerController.TestRunWrapper> result =
            AgenticQTC_TestRunnerController.getRecentTestRuns(10);
        Test.stopTest();

        System.assert(result.size() >= 5, 'Should return at least 5 runs');
    }

    @IsTest
    static void getRecentTestRuns_limitsTo20WhenNull() {
        // Insert 25 records
        List<Test_Run__c> toInsert = new List<Test_Run__c>();
        for (Integer i = 0; i < 25; i++) {
            toInsert.add(new Test_Run__c(
                Test_Suite__c = 'suite' + i,
                Status__c     = 'PENDING'
            ));
        }
        insert toInsert;

        Test.startTest();
        List<AgenticQTC_TestRunnerController.TestRunWrapper> result =
            AgenticQTC_TestRunnerController.getRecentTestRuns(null);
        Test.stopTest();

        System.assert(result.size() <= 20, 'Should cap at 20 when null limit passed');
    }

    // ─── cancelTestRun ───────────────────────────────────────────────────────

    @IsTest
    static void cancelTestRun_pendingRun_setsError() {
        Test_Run__c run = new Test_Run__c(
            Test_Suite__c   = 'cancelSuite',
            Status__c       = 'PENDING',
            Requested_By__c = UserInfo.getUserId()
        );
        insert run;

        Test.startTest();
        AgenticQTC_TestRunnerController.cancelTestRun(run.Id);
        Test.stopTest();

        Test_Run__c updated = [SELECT Status__c FROM Test_Run__c WHERE Id = :run.Id];
        System.assertEquals('ERROR', updated.Status__c, 'Status should be ERROR after cancel');
    }

    @IsTest
    static void cancelTestRun_nonPendingRun_throwsException() {
        Test_Run__c run = new Test_Run__c(
            Test_Suite__c   = 'runningRun',
            Status__c       = 'RUNNING',
            Requested_By__c = UserInfo.getUserId()
        );
        insert run;

        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.cancelTestRun(run.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for non-PENDING run');
    }

    @IsTest
    static void cancelTestRun_blankId_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.cancelTestRun('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for blank Id');
    }
}