/**
 * AgenticQTC_TestRunnerController
 *
 * Apex controller for the agenticQtcTestDashboard LWC.
 * Provides methods to create test runs, poll status, retrieve results, and
 * return file attachments (screenshots) linked to a test run.
 */
public with sharing class AgenticQTC_TestRunnerController {

    // ─── Inner classes used as LWC wire/method return types ─────────────────

    public class TestRunWrapper {
        @AuraEnabled public String  id              { get; set; }
        @AuraEnabled public String  name            { get; set; }
        @AuraEnabled public String  status          { get; set; }
        @AuraEnabled public String  testSuite       { get; set; }
        @AuraEnabled public String  accountId       { get; set; }
        @AuraEnabled public String  accountName     { get; set; }
        @AuraEnabled public String  agentId         { get; set; }
        @AuraEnabled public Integer testsPassed     { get; set; }
        @AuraEnabled public Integer testsFailed     { get; set; }
        @AuraEnabled public Long    durationMs      { get; set; }
        @AuraEnabled public String  errorMessage    { get; set; }
        @AuraEnabled public String  logOutput       { get; set; }
        @AuraEnabled public String  richResults     { get; set; }
        @AuraEnabled public Datetime startedAt      { get; set; }
        @AuraEnabled public Datetime completedAt    { get; set; }
        @AuraEnabled public Datetime createdDate    { get; set; }
        @AuraEnabled public String  requestedByName { get; set; }
        @AuraEnabled public List<TestResultWrapper> testResults { get; set; }
    }

    public class TestResultWrapper {
        @AuraEnabled public String  id           { get; set; }
        @AuraEnabled public String  testName     { get; set; }
        @AuraEnabled public String  suiteName    { get; set; }
        @AuraEnabled public String  status       { get; set; }
        @AuraEnabled public Long    durationMs   { get; set; }
        @AuraEnabled public String  errorMessage { get; set; }
        @AuraEnabled public Integer retryCount   { get; set; }
    }

    public class AttachmentWrapper {
        @AuraEnabled public String id             { get; set; }
        @AuraEnabled public String title          { get; set; }
        @AuraEnabled public String fileType       { get; set; }
        @AuraEnabled public String fileExtension  { get; set; }  // e.g. 'webm', 'png'
        @AuraEnabled public String versionId      { get; set; }
        @AuraEnabled public String downloadUrl    { get; set; }
        // Base64-encoded text content for small files (rich-results.json, log-output.txt).
        // LWC decodes with atob() — avoids CSP/fetch issues entirely.
        @AuraEnabled public String textContentB64 { get; set; }
    }

    public class SuiteOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    // ─── LWC-callable methods ────────────────────────────────────────────────

    /**
     * Returns the list of Playwright suites available in the dashboard dropdown.
     * Sourced from the agenticQTC_TestSuite__mdt CMDT so the catalogue can be
     * extended without redeploying the LWC.
     */
    @AuraEnabled(cacheable=true)
    public static List<SuiteOption> getSuiteOptions() {
        List<SuiteOption> options = new List<SuiteOption>();
        for (agenticQTC_TestSuite__mdt rec : [
            SELECT MasterLabel, Suite_Value__c, Sort_Order__c
            FROM   agenticQTC_TestSuite__mdt
            WHERE  Is_Active__c = true
            WITH   SYSTEM_MODE
            ORDER BY Sort_Order__c ASC NULLS LAST, MasterLabel ASC
        ]) {
            SuiteOption opt = new SuiteOption();
            opt.label = rec.MasterLabel;
            opt.value = rec.Suite_Value__c;
            options.add(opt);
        }
        return options;
    }

    /**
     * Searches Accounts by name for the dashboard's account typeahead.
     * Delegates to AgenticQTC_AccountSearchService, which restricts results to
     * accounts that have at least one eligible (activated, in-force) contract —
     * the same accounts the Playwright specs can actually run amendments against.
     */
    @AuraEnabled(cacheable=true)
    public static List<AgenticQTC_AccountSearchService.AccountResult> searchAccounts(String searchTerm) {
        return AgenticQTC_AccountSearchService.searchAccounts(searchTerm);
    }

    /**
     * Creates a new Test_Run__c record with PENDING status.
     * accountName is required: the dashboard forces an account selection so the
     * target account flows through to the specs instead of their hard-coded fallback.
     */
    @AuraEnabled
    public static String createTestRun(String testSuite, String runner, String accountId, String accountName) {
        if (String.isBlank(testSuite)) {
            throw new AuraHandledException('testSuite is required.');
        }
        if (String.isBlank(accountName)) {
            throw new AuraHandledException('An account is required. Search for and select an account before running.');
        }

        // runner = 'github'  → CLAIMED immediately, trigger GitHub Actions workflow.
        // runner = 'local'   → PENDING, local agent picks it up via polling.
        // null / anything else → default to 'local' for backward compatibility.
        Boolean useGitHub = 'github'.equalsIgnoreCase(runner);

        Test_Run__c run = new Test_Run__c(
            Test_Suite__c    = testSuite,
            Status__c        = useGitHub ? 'CLAIMED' : 'PENDING',
            Agent_Id__c      = useGitHub ? 'github-actions' : null,
            Account__c       = String.isNotBlank(accountId) ? (Id) accountId : null,
            Account_Name__c  = accountName,
            Requested_By__c  = UserInfo.getUserId()
        );

        insert run;

        if (useGitHub) {
            // Trigger GitHub Actions asynchronously.
            // @future(callout=true) is required: no callouts allowed in same DML transaction.
            AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
                run.Id,
                testSuite,
                URL.getOrgDomainUrl().toExternalForm(),
                accountName
            );
        }

        return run.Id;
    }

    /**
     * Returns the current state of a Test_Run__c and all its child Test_Results.
     * LWC polls this every 3 seconds while status is PENDING / CLAIMED / RUNNING.
     */
    @AuraEnabled
    public static TestRunWrapper getTestRun(String testRunId) {
        if (String.isBlank(testRunId)) {
            throw new AuraHandledException('testRunId is required.');
        }

        List<Test_Run__c> runs = [
            SELECT
                Id, Name, Status__c, Test_Suite__c, Agent_Id__c,
                Account__c, Account_Name__c,
                Tests_Passed__c, Tests_Failed__c, Duration_Ms__c,
                Error_Message__c, Log_Output__c, Rich_Results__c,
                Started_At__c, Completed_At__c, CreatedDate,
                Requested_By__r.Name,
                (SELECT
                     Id, Name, Test_Name__c, Suite_Name__c, Status__c,
                     Duration_Ms__c, Error_Message__c, Retry_Count__c
                 FROM Test_Results__r
                 ORDER BY CreatedDate ASC)
            FROM Test_Run__c
            WHERE Id = :testRunId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (runs.isEmpty()) {
            throw new AuraHandledException('Test run not found: ' + testRunId);
        }

        return toWrapper(runs[0]);
    }

    /**
     * Returns the N most-recent Test_Run__c records (no child results).
     */
    @AuraEnabled(cacheable=true)
    public static List<TestRunWrapper> getRecentTestRuns(Integer limitCount) {
        Integer safeLimit = (limitCount == null || limitCount > 50) ? 20 : limitCount;

        List<Test_Run__c> runs = [
            SELECT
                Id, Name, Status__c, Test_Suite__c, Agent_Id__c,
                Account__c, Account_Name__c,
                Tests_Passed__c, Tests_Failed__c, Duration_Ms__c,
                Error_Message__c, Log_Output__c, Rich_Results__c,
                Started_At__c, Completed_At__c, CreatedDate,
                Requested_By__r.Name
            FROM Test_Run__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT :safeLimit
        ];

        List<TestRunWrapper> wrappers = new List<TestRunWrapper>();
        for (Test_Run__c r : runs) {
            wrappers.add(toWrapper(r));
        }
        return wrappers;
    }

    /**
     * Returns ContentVersion file attachments linked to a Test_Run__c record.
     * The local agent uploads screenshots and video via ContentDocumentLink.
     */
    @AuraEnabled
    public static List<AttachmentWrapper> getTestRunFiles(String testRunId) {
        if (String.isBlank(testRunId)) return new List<AttachmentWrapper>();

        List<ContentDocumentLink> links = [
            SELECT
                ContentDocumentId,
                ContentDocument.LatestPublishedVersionId,
                ContentDocument.Title,
                ContentDocument.FileType,
                ContentDocument.FileExtension,
                ContentDocument.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testRunId
            WITH SYSTEM_MODE
            ORDER BY ContentDocument.CreatedDate ASC
        ];

        // Collect version IDs for small text files so we can fetch their content in one query
        Set<Id> textVersionIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            String t = link.ContentDocument.Title;
            if (t == 'rich-results.json' || t == 'log-output.txt') {
                textVersionIds.add(link.ContentDocument.LatestPublishedVersionId);
            }
        }
        Map<Id, ContentVersion> textVersionMap = new Map<Id, ContentVersion>();
        if (!textVersionIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, VersionData FROM ContentVersion WHERE Id IN :textVersionIds WITH SYSTEM_MODE
            ]) {
                textVersionMap.put(cv.Id, cv);
            }
        }

        List<AttachmentWrapper> results = new List<AttachmentWrapper>();
        for (ContentDocumentLink link : links) {
            AttachmentWrapper w = new AttachmentWrapper();
            w.id            = link.ContentDocumentId;
            w.title         = link.ContentDocument.Title;
            w.fileType      = link.ContentDocument.FileType;
            w.fileExtension = link.ContentDocument.FileExtension;
            w.versionId     = link.ContentDocument.LatestPublishedVersionId;
            w.downloadUrl   = '/sfc/servlet.shepherd/version/download/'
                            + link.ContentDocument.LatestPublishedVersionId
                            + '?operationContext=CHATTER';
            // Inline text content for rich-results.json and log-output.txt
            if (textVersionMap.containsKey((Id)w.versionId)) {
                w.textContentB64 = EncodingUtil.base64Encode(
                    textVersionMap.get((Id)w.versionId).VersionData
                );
            }
            results.add(w);
        }
        return results;
    }

    /**
     * Cancels a PENDING test run (sets status to ERROR).
     */
    @AuraEnabled
    public static void cancelTestRun(String testRunId) {
        if (String.isBlank(testRunId)) {
            throw new AuraHandledException('testRunId is required.');
        }

        List<Test_Run__c> runs = [
            SELECT Id, Status__c, Requested_By__c
            FROM Test_Run__c
            WHERE Id = :testRunId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (runs.isEmpty()) {
            throw new AuraHandledException('Test run not found: ' + testRunId);
        }

        Test_Run__c run = runs[0];

        // Allow cancelling any in-progress run (PENDING waiting for an agent,
        // CLAIMED stuck without a heartbeat, or actively RUNNING).
        Set<String> cancellable = new Set<String>{ 'PENDING', 'CLAIMED', 'RUNNING' };
        if (!cancellable.contains(run.Status__c)) {
            throw new AuraHandledException(
                'Can only cancel in-progress runs. Current status: ' + run.Status__c
            );
        }

        Boolean isAdmin = FeatureManagement.checkPermission('ModifyAllData');
        if (run.Requested_By__c != UserInfo.getUserId() && !isAdmin) {
            throw new AuraHandledException('You can only cancel test runs you requested.');
        }

        run.Status__c = 'ERROR';
        update run;
    }

    // ─── Private helpers ─────────────────────────────────────────────────────

    private static TestRunWrapper toWrapper(Test_Run__c r) {
        TestRunWrapper w        = new TestRunWrapper();
        w.id                    = r.Id;
        w.name                  = r.Name;
        w.status                = r.Status__c;
        w.testSuite             = r.Test_Suite__c;
        w.accountId             = r.Account__c;
        w.accountName           = r.Account_Name__c;
        w.agentId               = r.Agent_Id__c;
        w.testsPassed           = r.Tests_Passed__c != null ? Integer.valueOf(r.Tests_Passed__c) : 0;
        w.testsFailed           = r.Tests_Failed__c != null ? Integer.valueOf(r.Tests_Failed__c) : 0;
        w.durationMs            = r.Duration_Ms__c  != null ? (Long) r.Duration_Ms__c.longValue()  : null;
        w.errorMessage          = r.Error_Message__c;
        w.logOutput             = r.Log_Output__c;
        w.richResults           = r.Rich_Results__c;
        w.startedAt             = r.Started_At__c;
        w.completedAt           = r.Completed_At__c;
        w.createdDate           = r.CreatedDate;
        w.requestedByName       = r.Requested_By__r != null ? r.Requested_By__r.Name : null;
        w.testResults           = new List<TestResultWrapper>();

        if (r.Test_Results__r != null) {
            for (Test_Result__c tr : r.Test_Results__r) {
                TestResultWrapper tw = new TestResultWrapper();
                tw.id           = tr.Id;
                tw.testName     = tr.Test_Name__c;
                tw.suiteName    = tr.Suite_Name__c;
                tw.status       = tr.Status__c;
                tw.durationMs   = tr.Duration_Ms__c  != null ? (Long) tr.Duration_Ms__c.longValue()  : null;
                tw.errorMessage = tr.Error_Message__c;
                tw.retryCount   = tr.Retry_Count__c  != null ? Integer.valueOf(tr.Retry_Count__c) : 0;
                w.testResults.add(tw);
            }
        }
        return w;
    }
}