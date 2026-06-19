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
        Account acct = new Account(Name = 'Bates White');
        insert acct;

        Test.startTest();
        String runId = AgenticQTC_TestRunnerController.createTestRun(
            'agenticQtcQuantityIncrease', 'local', acct.Id, 'Bates White');
        Test.stopTest();

        System.assertNotEquals(null, runId, 'Should return a record Id');

        Test_Run__c run = [SELECT Id, Status__c, Test_Suite__c, Account__c, Account_Name__c, Requested_By__c
                           FROM Test_Run__c WHERE Id = :runId];
        System.assertEquals('PENDING',                     run.Status__c,    'Status should be PENDING');
        System.assertEquals('agenticQtcQuantityIncrease',  run.Test_Suite__c, 'Suite should be set');
        System.assertEquals(acct.Id,                        run.Account__c,    'Account lookup should be set');
        System.assertEquals('Bates White',                 run.Account_Name__c, 'Account name should be set');
        System.assertEquals(UserInfo.getUserId(),           run.Requested_By__c, 'Requester should be current user');
    }

    @IsTest
    static void createTestRun_blankSuite_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.createTestRun('', 'local', null, 'Bates White');
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
            AgenticQTC_TestRunnerController.createTestRun(null, 'local', null, 'Bates White');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for null testSuite');
    }

    @IsTest
    static void createTestRun_blankAccount_throwsException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.createTestRun('agenticQtcQuantityIncrease', 'local', null, '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for blank accountName');
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
    static void cancelTestRun_terminalRun_throwsException() {
        // PENDING, CLAIMED and RUNNING are all cancellable; a terminal status
        // (e.g. PASSED) is not and must throw.
        Test_Run__c run = new Test_Run__c(
            Test_Suite__c   = 'finishedRun',
            Status__c       = 'PASSED',
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
        System.assert(threw, 'Should throw for a terminal (non-cancellable) run');
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

    // ─── createTestRun (github runner) ───────────────────────────────────────

    private class GitHubDispatchMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(204);
            res.setBody('');
            return res;
        }
    }

    @IsTest
    static void createTestRun_githubRunner_dispatchesWorkflow() {
        Test.setMock(HttpCalloutMock.class, new GitHubDispatchMock());

        Account acct = new Account(Name = 'Bates White');
        insert acct;

        Test.startTest();
        String runId = AgenticQTC_TestRunnerController.createTestRun(
            'agenticQtcQuantityIncrease', 'github', acct.Id, 'Bates White');
        Test.stopTest();

        System.assertNotEquals(null, runId, 'Should return a record Id');

        Test_Run__c run = [
            SELECT Status__c, Agent_Id__c, Test_Suite__c
            FROM   Test_Run__c
            WHERE  Id = :runId
        ];
        System.assertEquals('github-actions', run.Agent_Id__c,
            'Agent_Id should be github-actions for github runner');
        System.assertEquals('agenticQtcQuantityIncrease', run.Test_Suite__c);
        // Status is CLAIMED on insert; the @future may flip it to ERROR if the
        // metadata Default record has no PAT — both are acceptable here.
        System.assert(
            run.Status__c == 'CLAIMED' || run.Status__c == 'ERROR',
            'Status should be CLAIMED (or ERROR if config missing). Actual: ' + run.Status__c
        );
    }

    // ─── getTestRunFiles ─────────────────────────────────────────────────────

    @IsTest
    static void getTestRunFiles_blankId_returnsEmptyList() {
        Test.startTest();
        List<AgenticQTC_TestRunnerController.AttachmentWrapper> files =
            AgenticQTC_TestRunnerController.getTestRunFiles('');
        Test.stopTest();

        System.assertNotEquals(null, files, 'Should return non-null list');
        System.assertEquals(0, files.size(), 'Blank Id should yield empty list');
    }

    @IsTest
    static void getTestRunFiles_withAttachment_returnsWrapper() {
        Test_Run__c run = new Test_Run__c(
            Test_Suite__c = 'filesSuite',
            Status__c     = 'PASSED'
        );
        insert run;

        ContentVersion cv = new ContentVersion(
            Title           = 'screenshot',
            PathOnClient    = 'screenshot.png',
            VersionData     = Blob.valueOf('fake-png-bytes'),
            IsMajorVersion  = true
        );
        insert cv;

        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = run.Id,
            ShareType         = 'V'
        );

        Test.startTest();
        List<AgenticQTC_TestRunnerController.AttachmentWrapper> files =
            AgenticQTC_TestRunnerController.getTestRunFiles(run.Id);
        Test.stopTest();

        System.assertEquals(1, files.size(), 'Should return one attachment');
        AgenticQTC_TestRunnerController.AttachmentWrapper w = files[0];
        System.assertEquals(contentDocumentId, w.id,        'id should be ContentDocumentId');
        System.assertEquals('screenshot',       w.title,    'title should be set');
        System.assertNotEquals(null, w.versionId,           'versionId should be set');
        System.assert(
            w.downloadUrl != null && w.downloadUrl.contains(w.versionId),
            'downloadUrl should embed the versionId'
        );
    }

    // ─── AgenticQTC_GitHubActionsService inner try/catch coverage ───────────

    @IsTest
    static void triggerWorkflowAsync_calloutFails_marksRunAsError() {
        Test_Run__c run = new Test_Run__c(
            Test_Suite__c = 'agenticQtcQuantityIncrease',
            Status__c     = 'CLAIMED',
            Agent_Id__c   = 'github-actions'
        );
        insert run;

        // No HttpCalloutMock installed → the HTTP send inside triggerWorkflow
        // throws, the outer catch fires, and the inner try updates the run
        // to ERROR. Covers the inner try body (new Test_Run__c + update run).
        Test.startTest();
        AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
            run.Id,
            'agenticQtcQuantityIncrease',
            'https://test.salesforce.com',
            'Bates White'
        );
        Test.stopTest();

        Test_Run__c updated = [
            SELECT Status__c, Error_Message__c
            FROM   Test_Run__c
            WHERE  Id = :run.Id
        ];
        System.assertEquals('ERROR', updated.Status__c,
            'Run should be flipped to ERROR by the inner try block');
        System.assertNotEquals(null, updated.Error_Message__c,
            'Error_Message__c should be populated');
        System.assert(
            updated.Error_Message__c.startsWith('GitHub Actions trigger failed:'),
            'Error message should start with the documented prefix. Actual: '
                + updated.Error_Message__c
        );
    }

    @IsTest
    static void triggerWorkflowAsync_invalidRunId_swallowsUpdateError() {
        // Passing a malformed Id forces the `Id = runId` assignment inside the
        // inner try to throw, exercising the `catch (Exception updateEx)` line.
        // The method must NOT propagate the exception.
        Test.startTest();
        AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
            'not-a-valid-id',
            'agenticQtcQuantityIncrease',
            'https://test.salesforce.com',
            'Bates White'
        );
        Test.stopTest();

        // Reaching this line proves the inner catch swallowed the update error.
        System.assert(true, 'triggerWorkflowAsync must not propagate exceptions');
    }

    // ─── searchAccounts passthrough ──────────────────────────────────────────

    @IsTest
    static void searchAccounts_shortTerm_returnsEmpty() {
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_TestRunnerController.searchAccounts('a');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return a non-null list');
        System.assertEquals(0, results.size(),
            'Search terms under the minimum length should yield no results');
    }

    // ─── getSuiteOptions ─────────────────────────────────────────────────────

    @IsTest
    static void getSuiteOptions_returnsActiveSuites() {
        Test.startTest();
        List<AgenticQTC_TestRunnerController.SuiteOption> opts =
            AgenticQTC_TestRunnerController.getSuiteOptions();
        Test.stopTest();

        System.assertNotEquals(null, opts, 'Should return a non-null list');
        // Custom metadata is visible in tests by default — every option must
        // have both fields populated (CMDT enforces Suite_Value__c required).
        for (AgenticQTC_TestRunnerController.SuiteOption o : opts) {
            System.assertNotEquals(null, o.label, 'label should be set');
            System.assertNotEquals(null, o.value, 'value should be set');
        }
    }

    @IsTest
    static void suiteOption_propertiesRoundTrip() {
        AgenticQTC_TestRunnerController.SuiteOption o =
            new AgenticQTC_TestRunnerController.SuiteOption();
        o.label = 'Quantity Increase (Full Flow)';
        o.value = 'agenticQtcQuantityIncrease';
        System.assertEquals('Quantity Increase (Full Flow)', o.label);
        System.assertEquals('agenticQtcQuantityIncrease',    o.value);
    }

    // ─── AttachmentWrapper property coverage ─────────────────────────────────

    @IsTest
    static void attachmentWrapper_propertiesRoundTrip() {
        AgenticQTC_TestRunnerController.AttachmentWrapper w =
            new AgenticQTC_TestRunnerController.AttachmentWrapper();
        w.id            = '069000000000001';
        w.title         = 'video';
        w.fileType      = 'WEBM';
        w.fileExtension = 'webm';
        w.versionId     = '068000000000001';
        w.downloadUrl   = '/sfc/servlet.shepherd/version/download/068000000000001';

        System.assertEquals('069000000000001', w.id);
        System.assertEquals('video',           w.title);
        System.assertEquals('WEBM',            w.fileType);
        System.assertEquals('webm',            w.fileExtension);
        System.assertEquals('068000000000001', w.versionId);
        System.assertEquals(
            '/sfc/servlet.shepherd/version/download/068000000000001',
            w.downloadUrl
        );
    }

    // ─── getModuleOptions ────────────────────────────────────────────────────

    @IsTest
    static void getModuleOptions_returnsModules() {
        Test.startTest();
        List<AgenticQTC_TestRunnerController.ModuleOption> opts =
            AgenticQTC_TestRunnerController.getModuleOptions();
        Test.stopTest();

        System.assertNotEquals(null, opts, 'Should return a non-null list');
        // Module__mdt records are visible in tests by default; each option must
        // have both fields populated.
        for (AgenticQTC_TestRunnerController.ModuleOption o : opts) {
            System.assertNotEquals(null, o.label, 'Module label should be set');
            System.assertNotEquals(null, o.value, 'Module value should be set');
        }
    }

    // ─── getContractsForAccount ──────────────────────────────────────────────

    @IsTest
    static void getContractsForAccount_blankReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_TestRunnerController.ContractOption> opts =
            AgenticQTC_TestRunnerController.getContractsForAccount('');
        Test.stopTest();

        System.assertNotEquals(null, opts, 'Should return a non-null list');
        System.assertEquals(0, opts.size(), 'Blank accountId should yield an empty list');
    }

    @IsTest
    static void getContractsForAccount_withAccount_runsQuery() {
        Account acct = new Account(Name = 'Bates White');
        insert acct;

        Test.startTest();
        List<AgenticQTC_TestRunnerController.ContractOption> opts =
            AgenticQTC_TestRunnerController.getContractsForAccount(acct.Id);
        Test.stopTest();

        // No eligible (in-force, software-subscription) contracts exist in the
        // test context, so the list is empty — but the method body (the query
        // + return) is exercised.
        System.assertNotEquals(null, opts, 'Should return a non-null list');
    }

    // ─── getQuotesForContract ────────────────────────────────────────────────

    @IsTest
    static void getQuotesForContract_blankReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_TestRunnerController.QuoteOption> opts =
            AgenticQTC_TestRunnerController.getQuotesForContract('');
        Test.stopTest();

        System.assertNotEquals(null, opts, 'Should return a non-null list');
        System.assertEquals(0, opts.size(), 'Blank contractId should yield an empty list');
    }

    @IsTest
    static void getQuotesForContract_withContract_runsQuery() {
        Account acct = new Account(Name = 'Bates White');
        insert acct;
        Contract con = new Contract(AccountId = acct.Id, StartDate = Date.today(), ContractTerm = 12);
        insert con;

        Test.startTest();
        List<AgenticQTC_TestRunnerController.QuoteOption> opts =
            AgenticQTC_TestRunnerController.getQuotesForContract(con.Id);
        Test.stopTest();

        // No draft amendment quotes exist for this contract → empty, but the
        // method body (query + return) is exercised.
        System.assertNotEquals(null, opts, 'Should return a non-null list');
    }

    // ─── createTestRunScoped ─────────────────────────────────────────────────

    @IsTest
    static void createTestRunScoped_localRunner_setsScopeFields() {
        Account acct = new Account(Name = 'Bates White');
        insert acct;
        Contract con = new Contract(AccountId = acct.Id, StartDate = Date.today(), ContractTerm = 12);
        insert con;

        Test.startTest();
        String runId = AgenticQTC_TestRunnerController.createTestRunScoped(
            'agenticQtcQuantityIncrease', 'local', acct.Id, 'Bates White',
            con.Id, 'CONT-0001', null, 'Q-12345', null);
        Test.stopTest();

        System.assertNotEquals(null, runId, 'Should return a record Id');

        Test_Run__c run = [
            SELECT Status__c, Contract__c, Contract_Number__c, Quote_Name__c
            FROM Test_Run__c WHERE Id = :runId
        ];
        System.assertEquals('PENDING',    run.Status__c,          'Local runner → PENDING');
        System.assertEquals(con.Id,        run.Contract__c,        'Contract lookup should be set');
        System.assertEquals('CONT-0001',   run.Contract_Number__c, 'Contract number should be set');
        System.assertEquals('Q-12345',     run.Quote_Name__c,      'Quote name should be set');

        // Fetch via getTestRun to exercise toWrapper's contract/quote mapping.
        AgenticQTC_TestRunnerController.TestRunWrapper w =
            AgenticQTC_TestRunnerController.getTestRun(runId);
        System.assertEquals(con.Id,      w.contractId,     'Wrapper contractId should map');
        System.assertEquals('CONT-0001', w.contractNumber, 'Wrapper contractNumber should map');
        System.assertEquals('Q-12345',   w.quoteName,      'Wrapper quoteName should map');
    }

    // ─── getTestRunFiles (rich-results.json text branch) ─────────────────────

    @IsTest
    static void getTestRunFiles_richResultsJson_returnsDecodedContent() {
        Test_Run__c run = new Test_Run__c(Test_Suite__c = 'filesSuite', Status__c = 'PASSED');
        insert run;

        ContentVersion cv = new ContentVersion(
            Title          = 'rich-results.json',
            PathOnClient   = 'rich-results.json',
            VersionData    = Blob.valueOf('{"kind":"demo"}'),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = run.Id,
            ShareType         = 'V'
        );

        Test.startTest();
        List<AgenticQTC_TestRunnerController.AttachmentWrapper> files =
            AgenticQTC_TestRunnerController.getTestRunFiles(run.Id);
        Test.stopTest();

        System.assertEquals(1, files.size(), 'Should return the rich-results file');
        AgenticQTC_TestRunnerController.AttachmentWrapper w = files[0];
        System.assertEquals('rich-results.json', w.title, 'Title should match');
        System.assertNotEquals(null, w.textContentB64,
            'Text content should be base64-populated for rich-results.json');
        System.assertEquals('{"kind":"demo"}',
            EncodingUtil.base64Decode(w.textContentB64).toString(),
            'Decoded text content should round-trip');
    }

    // ─── cancelTestRun (not found) ───────────────────────────────────────────

    @IsTest
    static void cancelTestRun_notFound_throwsException() {
        // Insert then delete to obtain a well-formed Id that no longer resolves.
        Test_Run__c run = new Test_Run__c(Test_Suite__c = 'ghost', Status__c = 'PENDING');
        insert run;
        Id ghostId = run.Id;
        delete run;

        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_TestRunnerController.cancelTestRun(ghostId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for a non-existent run');
    }

    // ─── inner option classes property coverage ─────────────────────────────

    @IsTest
    static void innerOptionClasses_propertiesRoundTrip() {
        AgenticQTC_TestRunnerController.ModuleOption m =
            new AgenticQTC_TestRunnerController.ModuleOption();
        m.label = 'Quote Editor';
        m.value = 'quoteEditor';
        System.assertEquals('Quote Editor', m.label);
        System.assertEquals('quoteEditor',  m.value);

        AgenticQTC_TestRunnerController.ContractOption c =
            new AgenticQTC_TestRunnerController.ContractOption();
        c.label          = 'CONT-1 — Acme';
        c.value          = '800000000000001AAA';
        c.contractNumber = 'CONT-1';
        System.assertEquals('CONT-1 — Acme',       c.label);
        System.assertEquals('800000000000001AAA',  c.value);
        System.assertEquals('CONT-1',              c.contractNumber);

        AgenticQTC_TestRunnerController.QuoteOption q =
            new AgenticQTC_TestRunnerController.QuoteOption();
        q.label = 'Q-1 (2026-01-01)';
        q.value = 'a0x0000000000001AAA';
        q.name  = 'Q-1';
        System.assertEquals('Q-1 (2026-01-01)',     q.label);
        System.assertEquals('a0x0000000000001AAA',  q.value);
        System.assertEquals('Q-1',                  q.name);

        // SuiteOption.moduleName/description + AttachmentWrapper.textContentB64
        AgenticQTC_TestRunnerController.SuiteOption s =
            new AgenticQTC_TestRunnerController.SuiteOption();
        s.label = 'L'; s.value = 'v'; s.moduleName = 'quoteEditor'; s.description = 'desc';
        System.assertEquals('quoteEditor', s.moduleName);
        System.assertEquals('desc',        s.description);

        AgenticQTC_TestRunnerController.AttachmentWrapper a =
            new AgenticQTC_TestRunnerController.AttachmentWrapper();
        a.textContentB64 = 'abc';
        System.assertEquals('abc', a.textContentB64);
    }

    // ─── AgenticQTC_GitHubActionsService — 7-param overload coverage ─────────

    private class GitHubApiErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"message":"Internal Server Error"}');
            return res;
        }
    }

    @IsTest
    static void triggerWorkflowAsyncScoped_apiError_marksRunAsError() {
        // GitHub returns a non-204 → triggerWorkflow throws → the 7-param
        // overload's outer catch flips the run to ERROR. Covers the API-error
        // branch plus the catch body (new Test_Run__c + update).
        Test.setMock(HttpCalloutMock.class, new GitHubApiErrorMock());

        Test_Run__c run = new Test_Run__c(
            Test_Suite__c = 'agenticQtcQuantityIncrease',
            Status__c     = 'CLAIMED',
            Agent_Id__c   = 'github-actions'
        );
        insert run;

        Test.startTest();
        AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
            run.Id,
            'agenticQtcQuantityIncrease',
            'https://test.salesforce.com',
            'Bates White',
            null,           // contractId
            'CONT-0001',    // contractNumber
            'Q-12345'       // quoteName
        );
        Test.stopTest();

        Test_Run__c updated = [
            SELECT Status__c, Error_Message__c FROM Test_Run__c WHERE Id = :run.Id
        ];
        System.assertEquals('ERROR', updated.Status__c,
            'A non-204 API response should flip the run to ERROR via the 7-param catch block');
        System.assertNotEquals(null, updated.Error_Message__c,
            'Error_Message__c should be populated');
        System.assert(
            updated.Error_Message__c.startsWith('GitHub Actions trigger failed:'),
            'Error message should start with the documented prefix. Actual: '
                + updated.Error_Message__c
        );
    }

    @IsTest
    static void triggerWorkflowAsyncScoped_invalidRunId_swallowsUpdateError() {
        // A malformed Id forces the `Id = runId` assignment inside the inner try
        // to throw, exercising the 7-param overload's `catch (Exception updateEx)`.
        // The method must NOT propagate the exception.
        Test.setMock(HttpCalloutMock.class, new GitHubApiErrorMock());

        Test.startTest();
        AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
            'not-a-valid-id',
            'agenticQtcQuantityIncrease',
            'https://test.salesforce.com',
            'Bates White',
            null, 'CONT-0001', 'Q-12345'
        );
        Test.stopTest();

        System.assert(true, '7-param triggerWorkflowAsync must not propagate exceptions');
    }

    // ─── AgenticQTC_GitHubActionsService — 8-param overload coverage ─────────

    @IsTest
    static void triggerWorkflowAsync8_apiError_marksRunAsError() {
        // GitHub returns a non-204 → triggerWorkflow throws → the 8-param
        // overload's outer catch flips the run to ERROR. Covers lines 90-98.
        Test.setMock(HttpCalloutMock.class, new GitHubApiErrorMock());

        Test_Run__c run = new Test_Run__c(
            Test_Suite__c = 'agenticQtcQuantityIncrease',
            Status__c     = 'CLAIMED',
            Agent_Id__c   = 'github-actions'
        );
        insert run;

        Test.startTest();
        AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
            run.Id,
            'agenticQtcQuantityIncrease',
            'https://test.salesforce.com',
            'Bates White',
            null,
            'CONT-0001',
            'Q-12345',
            '[{"id":"acct1","name":"Bates White"}]'
        );
        Test.stopTest();

        Test_Run__c updated = [
            SELECT Status__c, Error_Message__c FROM Test_Run__c WHERE Id = :run.Id
        ];
        System.assertEquals('ERROR', updated.Status__c,
            'Non-204 response should flip run to ERROR via 8-param catch block');
        System.assert(
            updated.Error_Message__c.startsWith('GitHub Actions trigger failed:'),
            'Error message should carry the documented prefix'
        );
    }

    @IsTest
    static void triggerWorkflowAsync8_invalidRunId_swallowsUpdateError() {
        // Malformed Id forces inner update to throw, exercising the 8-param
        // catch (Exception updateEx) branch. Must not propagate.
        Test.setMock(HttpCalloutMock.class, new GitHubApiErrorMock());

        Test.startTest();
        AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
            'not-a-valid-id',
            'agenticQtcQuantityIncrease',
            'https://test.salesforce.com',
            'Bates White',
            null, 'CONT-0001', 'Q-12345',
            '[{"id":"acct1","name":"Bates White"}]'
        );
        Test.stopTest();

        System.assert(true, '8-param triggerWorkflowAsync must not propagate exceptions');
    }
}