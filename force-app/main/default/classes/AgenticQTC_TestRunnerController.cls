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
        @AuraEnabled public String  contractId      { get; set; }
        @AuraEnabled public String  contractNumber  { get; set; }
        @AuraEnabled public String  quoteId         { get; set; }
        @AuraEnabled public String  quoteName       { get; set; }
        @AuraEnabled public String  accountsJson    { get; set; }
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
        @AuraEnabled public String fileExtension  { get; set; }
        @AuraEnabled public String versionId      { get; set; }
        @AuraEnabled public String downloadUrl    { get; set; }
        @AuraEnabled public String textContentB64 { get; set; }
    }

    public class SuiteOption {
        @AuraEnabled public String  label                { get; set; }
        @AuraEnabled public String  value                { get; set; }
        @AuraEnabled public String  moduleName           { get; set; }
        @AuraEnabled public String  description          { get; set; }
        @AuraEnabled public Boolean allowMultipleAccount { get; set; }
        @AuraEnabled public String  defaultAccounts      { get; set; }
    }

    public class ModuleOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    public class ContractOption {
        @AuraEnabled public String label          { get; set; }
        @AuraEnabled public String value          { get; set; }
        @AuraEnabled public String contractNumber { get; set; }
    }

    public class QuoteOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String name  { get; set; }
    }

    // ─── LWC-callable methods ────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ModuleOption> getModuleOptions() {
        List<ModuleOption> options = new List<ModuleOption>();
        for (Module__mdt rec : [
            SELECT MasterLabel, Module_Name__c
            FROM   Module__mdt
            WITH   SYSTEM_MODE
            ORDER BY MasterLabel ASC
        ]) {
            ModuleOption opt = new ModuleOption();
            opt.label = rec.MasterLabel;
            opt.value = (rec.Module_Name__c != null ? rec.Module_Name__c : rec.MasterLabel);
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<SuiteOption> getSuiteOptions() {
        List<SuiteOption> options = new List<SuiteOption>();
        for (agenticQTC_TestSuite__mdt rec : [
            SELECT MasterLabel, Suite_Value__c, Sort_Order__c, Module__c, Description__c,
                   Allow_Multiple_Account__c, Default_Accounts__c
            FROM   agenticQTC_TestSuite__mdt
            WHERE  Is_Active__c = true
            WITH   SYSTEM_MODE
            ORDER BY Sort_Order__c ASC NULLS LAST, MasterLabel ASC
        ]) {
            SuiteOption opt = new SuiteOption();
            opt.label                = rec.MasterLabel;
            opt.value                = rec.Suite_Value__c;
            opt.moduleName           = rec.Module__c;
            opt.description          = rec.Description__c;
            opt.allowMultipleAccount = rec.Allow_Multiple_Account__c;
            opt.defaultAccounts      = rec.Default_Accounts__c;
            options.add(opt);
        }
        return options;
    }

    /**
     * Returns active contracts for an account — populates the optional
     * Contract dropdown on the dashboard.
     */
    @AuraEnabled(cacheable=true)
    public static List<ContractOption> getContractsForAccount(String accountId) {
        List<ContractOption> options = new List<ContractOption>();
        if (String.isBlank(accountId)) return options;
        for (AgenticQTC_ContractService.ContractResult c : AgenticQTC_ContractService.getActiveContracts(accountId)) {
            ContractOption opt = new ContractOption();
            opt.value          = c.id;
            opt.contractNumber = c.contractNumber;
            opt.label          = c.contractNumber + (String.isNotBlank(c.contractName) ? ' — ' + c.contractName : '');
            options.add(opt);
        }
        return options;
    }

    /**
     * Returns draft amendment quotes for a contract — populates the optional
     * Quote dropdown on the dashboard.
     */
    @AuraEnabled(cacheable=true)
    public static List<QuoteOption> getQuotesForContract(String contractId) {
        List<QuoteOption> options = new List<QuoteOption>();
        if (String.isBlank(contractId)) return options;
        for (AgenticQTC_QuoteAmendmentService.DraftQuoteOption q : AgenticQTC_QuoteAmendmentService.getDraftQuotesForContract(contractId)) {
            QuoteOption opt = new QuoteOption();
            opt.value = q.id;
            opt.name  = q.name;
            opt.label = q.name + (String.isNotBlank(q.startDate) ? ' (' + q.startDate + ')' : '');
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<AgenticQTC_AccountSearchService.AccountResult> searchAccounts(String searchTerm) {
        return AgenticQTC_AccountSearchService.searchAccounts(searchTerm);
    }

    /**
     * Creates a test run without contract/quote scoping.
     * Kept for backward compatibility with existing test code and older callers.
     */
    @AuraEnabled
    public static String createTestRun(String testSuite, String runner, String accountId, String accountName) {
        return doCreateTestRun(testSuite, runner, accountId, accountName, null, null, null, null, null);
    }

    /**
     * Creates a test run with optional contract/quote scoping and/or multi-account JSON.
     * accountsJson: JSON array of {id, search, fullName} objects for multi-account runs.
     *   When present, QTC_ACCOUNTS env var is set on the agent; contract/quote are ignored.
     * When null the run behaves as a normal single-account scoped run.
     */
    @AuraEnabled
    public static String createTestRunScoped(
        String testSuite,
        String runner,
        String accountId,
        String accountName,
        String contractId,
        String contractNumber,
        String quoteId,
        String quoteName,
        String accountsJson
    ) {
        return doCreateTestRun(testSuite, runner, accountId, accountName, contractId, contractNumber, quoteId, quoteName, accountsJson);
    }

    private static String doCreateTestRun(
        String testSuite,
        String runner,
        String accountId,
        String accountName,
        String contractId,
        String contractNumber,
        String quoteId,
        String quoteName,
        String accountsJson
    ) {
        if (String.isBlank(testSuite)) {
            throw new AuraHandledException('testSuite is required.');
        }
        if (String.isBlank(accountName)) {
            throw new AuraHandledException('An account is required. Search for and select an account before running.');
        }

        Boolean useGitHub = 'github'.equalsIgnoreCase(runner);

        Test_Run__c run = new Test_Run__c(
            Test_Suite__c      = testSuite,
            Status__c          = useGitHub ? 'CLAIMED' : 'PENDING',
            Agent_Id__c        = useGitHub ? 'github-actions' : null,
            Account__c         = String.isNotBlank(accountId)      ? (Id) accountId      : null,
            Account_Name__c    = accountName,
            Contract__c        = String.isNotBlank(contractId)     ? (Id) contractId     : null,
            Contract_Number__c = String.isNotBlank(contractNumber) ? contractNumber      : null,
            Quote__c           = String.isNotBlank(quoteId)        ? (Id) quoteId        : null,
            Quote_Name__c      = String.isNotBlank(quoteName)      ? quoteName           : null,
            Multiple_Accounts__c        = String.isNotBlank(accountsJson)   ? accountsJson        : null,
            Requested_By__c    = UserInfo.getUserId()
        );

        insert run;

        if (useGitHub) {
            AgenticQTC_GitHubActionsService.triggerWorkflowAsync(
                run.Id,
                testSuite,
                URL.getOrgDomainUrl().toExternalForm(),
                accountName,
                contractId,
                contractNumber,
                quoteName,
                accountsJson
            );
        }

        return run.Id;
    }

    @AuraEnabled
    public static TestRunWrapper getTestRun(String testRunId) {
        if (String.isBlank(testRunId)) {
            throw new AuraHandledException('testRunId is required.');
        }

        List<Test_Run__c> runs = [
            SELECT
                Id, Name, Status__c, Test_Suite__c, Agent_Id__c,
                Account__c, Account_Name__c,
                Contract__c, Contract_Number__c,
                Quote__c, Quote_Name__c,
                Multiple_Accounts__c,
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

    @AuraEnabled(cacheable=true)
    public static List<TestRunWrapper> getRecentTestRuns(Integer limitCount) {
        Integer safeLimit = (limitCount == null || limitCount > 50) ? 20 : limitCount;

        List<Test_Run__c> runs = [
            SELECT
                Id, Name, Status__c, Test_Suite__c, Agent_Id__c,
                Account__c, Account_Name__c,
                Contract__c, Contract_Number__c,
                Quote__c, Quote_Name__c,
                Multiple_Accounts__c,
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

    @AuraEnabled(cacheable=false)
    public static List<TestRunWrapper> searchTestRuns(String searchTerm, Integer limitCount) {
        if (String.isBlank(searchTerm)) return new List<TestRunWrapper>();
        Integer safeLimit = (limitCount == null || limitCount > 200) ? 50 : limitCount;
        String q = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';

        List<Test_Run__c> runs = [
            SELECT
                Id, Name, Status__c, Test_Suite__c, Agent_Id__c,
                Account__c, Account_Name__c,
                Contract__c, Contract_Number__c,
                Quote__c, Quote_Name__c,
                Multiple_Accounts__c,
                Tests_Passed__c, Tests_Failed__c, Duration_Ms__c,
                Error_Message__c, Log_Output__c, Rich_Results__c,
                Started_At__c, Completed_At__c, CreatedDate,
                Requested_By__r.Name
            FROM Test_Run__c
            WHERE Name LIKE :q
               OR Account_Name__c LIKE :q
               OR Test_Suite__c LIKE :q
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
            if (textVersionMap.containsKey((Id)w.versionId)) {
                w.textContentB64 = EncodingUtil.base64Encode(
                    textVersionMap.get((Id)w.versionId).VersionData
                );
            }
            results.add(w);
        }
        return results;
    }

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
        w.contractId            = r.Contract__c;
        w.contractNumber        = r.Contract_Number__c;
        w.quoteId               = r.Quote__c;
        w.quoteName             = r.Quote_Name__c;
        w.accountsJson          = r.Multiple_Accounts__c;
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