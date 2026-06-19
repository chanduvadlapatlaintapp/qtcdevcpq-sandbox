/**
 * AgenticQTC_GitHubActionsService
 *
 * Triggers a GitHub Actions workflow_dispatch event via the GitHub REST API.
 * Called from AgenticQTC_TestRunnerController.createTestRun() after inserting
 * the Test_Run__c record.
 *
 * Configuration comes from the GitHub_Actions_Config__mdt Custom Metadata record
 * named "Default". Set the PAT__c field post-deploy via:
 *   Setup → Custom Metadata Types → GitHub Actions Config → Manage Records
 *
 * The PAT must have the "workflow" scope on GitHub.
 *
 * Requires Remote Site Setting: https://api.github.com (GitHub_API)
 */
public class AgenticQTC_GitHubActionsService {

    // ─── @future wrapper ──────────────────────────────────────────────────────
    // Salesforce prohibits HTTP callouts in the same transaction as DML operations.
    // The @future annotation defers the callout to a separate async transaction.

    @future(callout=true)
    public static void triggerWorkflowAsync(String runId, String testSuite, String instanceUrl, String accountName) {
        try {
            triggerWorkflow(runId, testSuite, instanceUrl, accountName);
        } catch (Exception e) {
            // Log the error to the Test_Run__c record so the LWC can surface it.
            // We cannot throw from a @future method — the run stays CLAIMED and
            // the LWC's stuck-run warning will fire after the timeout.
            System.debug(LoggingLevel.ERROR, '[AgenticQTC_GitHubActionsService] triggerWorkflowAsync failed: ' + e.getMessage());
            try {
                Test_Run__c run = new Test_Run__c(
                    Id            = runId,
                    Status__c     = 'ERROR',
                    Error_Message__c = 'GitHub Actions trigger failed: ' + e.getMessage()
                );
                update run;
            } catch (Exception updateEx) {
                System.debug(LoggingLevel.ERROR, '[AgenticQTC_GitHubActionsService] Could not update run to ERROR: ' + updateEx.getMessage());
            }
        }
    }

    // ─── Core callout ─────────────────────────────────────────────────────────

    @TestVisible
    private static void triggerWorkflow(String runId, String testSuite, String instanceUrl, String accountName) {
        GitHub_Actions_Config__mdt cfg = getConfig();

        if (String.isBlank(cfg.PAT__c)) {
            throw new AuraHandledException('GitHub Actions PAT not configured. ' + 'Set GitHub_Actions_Config__mdt.Default.PAT__c via Setup → Custom Metadata Types.');
        }
        if (String.isBlank(cfg.Repository_Owner__c) || String.isBlank(cfg.Repository_Name__c)) {
            throw new AuraHandledException('GitHub repository not configured. ' + 'Set Repository_Owner__c and Repository_Name__c in GitHub_Actions_Config__mdt.Default.');
        }

        String endpoint = 'https://api.github.com/repos/'
            + cfg.Repository_Owner__c + '/'
            + cfg.Repository_Name__c
            + '/actions/workflows/'
            + cfg.Workflow_File__c
            + '/dispatches';

        Map<String, Object> inputs = new Map<String, Object>{
            'test_run_id'     => runId,
            'test_suite'      => testSuite,
            'sf_instance_url' => instanceUrl,
            'account_name'    => accountName
        };

        Map<String, Object> payload = new Map<String, Object>{
            'ref'    => cfg.Branch__c,
            'inputs' => inputs
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + cfg.PAT__c);
        req.setHeader('Accept', 'application/vnd.github+json');
        req.setHeader('X-GitHub-Api-Version', '2022-11-28');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(10000);

        HttpResponse res = new Http().send(req);

        // GitHub returns 204 No Content on success
        if (res.getStatusCode() != 204) {
            throw new AuraHandledException('GitHub API error ' + res.getStatusCode() + ': ' + res.getBody());
        }

        System.debug('[AgenticQTC_GitHubActionsService] Workflow dispatched for run ' + runId);
    }

    // ─── Config helper ────────────────────────────────────────────────────────

    private static GitHub_Actions_Config__mdt getConfig() {
        List<GitHub_Actions_Config__mdt> cfgs = [
            SELECT PAT__c, Repository_Owner__c, Repository_Name__c, Branch__c, Workflow_File__c
            FROM   GitHub_Actions_Config__mdt
            WHERE  DeveloperName = 'Default'
            LIMIT  1
        ];
        if (cfgs.isEmpty()) {
            throw new AuraHandledException('GitHub_Actions_Config__mdt "Default" record not found. Deploy the metadata first.');
        }
        return cfgs[0];
    }
}