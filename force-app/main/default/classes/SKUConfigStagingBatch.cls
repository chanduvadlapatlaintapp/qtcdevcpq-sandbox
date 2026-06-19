/**
 * @description Scheduled Batchable that processes staged config data changes into GitHub PRs.
 *              Runs daily at 6:00 PM PT as a safety net — auto-finalizes any Open sessions
 *              and creates PRs for all Pending sessions.
 *
 *              Processing flow:
 *              1. start() — Flips all Open sessions to Pending, then queries all Pending parents
 *              2. execute() — scope=1: For each parent, queries child entries, builds FileChange[],
 *                 calls GitHubPullRequestService.createConfigDataPR(), updates parent status
 *              3. finish() — Logs summary via Nebula.Logger
 *
 * @author      BIZ-80418
 * @date        2026-03-10
 * @jira        BIZ-80418
 */
public with sharing class SKUConfigStagingBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful, Schedulable {

    // ─── Public Constants ────────────────────────────────────────────────

    public static final String STATUS_OPEN      = 'Open';
    public static final String STATUS_PENDING   = 'Pending';
    public static final String STATUS_COMMITTED = 'Committed';
    public static final String STATUS_FAILED    = 'Failed';

    public static final String FINALIZED_BY_USER  = 'User';
    public static final String FINALIZED_BY_BATCH = 'Scheduled Batch';

    // ─── Private Stateful Counters ───────────────────────────────────────

    private Integer successCount = 0;
    private Integer failureCount = 0;
    private Integer skippedCount = 0;

    // ─── Schedulable ─────────────────────────────────────────────────────

    /**
     * @description Schedulable entry point — kicks off the batch with scope = 1.
     * @param sc SchedulableContext
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new SKUConfigStagingBatch(), 1);
    }

    // ─── Batchable: Start ────────────────────────────────────────────────

    /**
     * @description Flips all Open sessions to Pending (daily safety net),
     *              then returns a QueryLocator for all Pending parents.
     * @param bc BatchableContext
     * @return QueryLocator of Pending SKU_Config_Staging__c records
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Auto-finalize all Open sessions
        List<SKU_Config_Staging__c> openSessions = [
            SELECT Id, Status__c, Finalized_By__c
            FROM SKU_Config_Staging__c
            WHERE Status__c = :STATUS_OPEN
        ];

        if (!openSessions.isEmpty()) {
            for (SKU_Config_Staging__c session : openSessions) {
                session.Status__c = STATUS_PENDING;
                session.Finalized_By__c = FINALIZED_BY_BATCH;
            }
            update openSessions;
        }

        // Return all Pending sessions for processing
        return Database.getQueryLocator([
            SELECT Id, Session_Id__c, Status__c, Finalized_By__c,
                   CreatedBy.Name, CreatedDate
            FROM SKU_Config_Staging__c
            WHERE Status__c = :STATUS_PENDING
            ORDER BY CreatedDate ASC
        ]);
    }

    // ─── Batchable: Execute ──────────────────────────────────────────────

    /**
     * @description Processes a single Pending parent (scope = 1).
     *              Queries child entries, builds FileChange[], calls GitHub PR service,
     *              and updates the parent with the result.
     * @param bc BatchableContext
     * @param scope List containing a single SKU_Config_Staging__c record
     */
    public void execute(Database.BatchableContext bc, List<SKU_Config_Staging__c> scope) {
        SKU_Config_Staging__c parent = scope[0];

        try {
            // Query all child entries for this parent
            List<SKU_Config_Staging_Entry__c> entries = [
                SELECT Id, Object_API_Name__c, Record_Name__c,
                       Gearset_External_Id__c, JSON_Content__c, Operation_Type__c
                FROM SKU_Config_Staging_Entry__c
                WHERE Staging__c = :parent.Id
                ORDER BY Object_API_Name__c, Record_Name__c
            ];

            // Handle empty session — no entries to process
            if (entries.isEmpty()) {
                parent.Status__c = STATUS_COMMITTED;
                parent.Error_Message__c = 'No staging entries found — skipped';
                update parent;
                skippedCount++;
                return;
            }

            // Build FileChange[] from entries
            List<GitHubPullRequestService.FileChange> fileChanges = buildFileChanges(entries);

            // Build PR title and description
            String prTitle = buildPRTitle(parent);
            String prDescription = buildPRDescription(parent, entries);

            // Call GitHub PR service
            GitHubPullRequestService.PullRequestResult result =
                GitHubPullRequestService.createConfigDataPR(fileChanges, prTitle, prDescription);

            // Update parent based on result
            if (result.success) {
                parent.Status__c = STATUS_COMMITTED;
                parent.PR_URL__c = result.prUrl;
                parent.PR_Number__c = result.prNumber;
                parent.Branch_Name__c = result.branchName;
                successCount++;
            } else {
                parent.Status__c = STATUS_FAILED;
                parent.Error_Message__c = result.errorMessage;
                failureCount++;
            }

        } catch (Exception e) {
            parent.Status__c = STATUS_FAILED;
            parent.Error_Message__c = 'Batch exception: ' + e.getMessage()
                + ' | ' + e.getStackTraceString();
            failureCount++;
        }

        update parent;
    }

    // ─── Batchable: Finish ───────────────────────────────────────────────

    /**
     * @description Logs batch execution summary via Nebula.Logger.
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        String summary = String.format(
            'SKUConfigStagingBatch complete — Success: {0}, Failed: {1}, Skipped: {2}',
            new List<String>{
                String.valueOf(successCount),
                String.valueOf(failureCount),
                String.valueOf(skippedCount)
            }
        );

        System.debug(LoggingLevel.INFO, summary);

        // Nebula.Logger integration (if available in the org)
        try {
            Nebula.Logger.info(summary).addTag('SKUConfigStaging');
            Nebula.Logger.saveLog();
        } catch (Exception e) {
            // Nebula.Logger may not be available in all orgs — graceful fallback
            System.debug(LoggingLevel.WARN, 'Nebula.Logger not available: ' + e.getMessage());
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────

    /**
     * @description Builds a list of FileChange objects from staging entries.
     *              Derives the file path dynamically from entry fields.
     * @param entries List of staging entries
     * @return List of FileChange objects for the PR service
     */
    @TestVisible
    private static List<GitHubPullRequestService.FileChange> buildFileChanges(
        List<SKU_Config_Staging_Entry__c> entries
    ) {
        List<GitHubPullRequestService.FileChange> fileChanges =
            new List<GitHubPullRequestService.FileChange>();

        for (SKU_Config_Staging_Entry__c entry : entries) {
            String filePath = deriveFilePath(entry);
            String changeType = entry.Operation_Type__c.toLowerCase();

            fileChanges.add(new GitHubPullRequestService.FileChange(
                filePath, entry.JSON_Content__c, changeType
            ));
        }

        return fileChanges;
    }

    /**
     * @description Derives the GitHub file path from a staging entry's fields.
     *              Format: configdata/{Object_API_Name}/{RecordName}_[{GearsetExternalId}].gs.json
     * @param entry The staging entry
     * @return The derived file path
     */
    @TestVisible
    private static String deriveFilePath(SKU_Config_Staging_Entry__c entry) {
        String sanitizedName = entry.Record_Name__c.replaceAll('[^a-zA-Z0-9_\\-&. ]', '_');
        String fileName = sanitizedName + '_[' + entry.Gearset_External_Id__c + '].gs.json';
        return 'configdata/' + entry.Object_API_Name__c + '/' + fileName;
    }

    /**
     * @description Builds the PR title from the parent staging record.
     *              Format: "SKU Config Update — {CreatedBy.Name} — {CreatedDate}"
     * @param parent The parent staging record
     * @return The PR title string
     */
    @TestVisible
    private static String buildPRTitle(SKU_Config_Staging__c parent) {
        String userName = parent.CreatedBy != null ? parent.CreatedBy.Name : 'Unknown User';
        String dateStr = parent.CreatedDate != null
            ? parent.CreatedDate.format('yyyy-MM-dd')
            : Date.today().format();
        return 'SKU Config Update — ' + userName + ' — ' + dateStr;
    }

    /**
     * @description Builds the PR description with a summary of objects and files changed.
     * @param parent The parent staging record
     * @param entries The child staging entries
     * @return The PR description markdown string
     */
    @TestVisible
    private static String buildPRDescription(
        SKU_Config_Staging__c parent,
        List<SKU_Config_Staging_Entry__c> entries
    ) {
        String userName = parent.CreatedBy != null ? parent.CreatedBy.Name : 'Unknown User';
        String finalizedBy = String.isNotBlank(parent.Finalized_By__c)
            ? parent.Finalized_By__c : 'Unknown';

        // Build object summary — count per object + operation type
        Map<String, Map<String, Integer>> objectSummary = new Map<String, Map<String, Integer>>();
        for (SKU_Config_Staging_Entry__c entry : entries) {
            String objName = entry.Object_API_Name__c;
            if (!objectSummary.containsKey(objName)) {
                objectSummary.put(objName, new Map<String, Integer>());
            }
            Map<String, Integer> opCounts = objectSummary.get(objName);
            String opType = entry.Operation_Type__c.toLowerCase();
            opCounts.put(opType, (opCounts.containsKey(opType) ? opCounts.get(opType) : 0) + 1);
        }

        // Build markdown description
        String prBody = '## Config Data Changes\n\n';
        prBody += '**Session:** ' + parent.Session_Id__c + '\n';
        prBody += '**Initiated by:** ' + userName + '\n';
        prBody += '**Finalized by:** ' + finalizedBy + '\n\n';

        // Objects modified section
        prBody += '### Objects Modified\n';
        for (String objName : objectSummary.keySet()) {
            Map<String, Integer> opCounts = objectSummary.get(objName);
            Integer totalRecords = 0;
            List<String> opDetails = new List<String>();
            for (String opType : opCounts.keySet()) {
                Integer count = opCounts.get(opType);
                totalRecords += count;
                opDetails.add(count + ' ' + opType + (count > 1 ? 'd' : 'd'));
            }
            prBody += '- **' + objName + '** — ' + totalRecords
                + ' record' + (totalRecords > 1 ? 's' : '')
                + ' (' + String.join(opDetails, ', ') + ')\n';
        }

        // Files changed section
        prBody += '\n### Files Changed\n';
        Integer fileNum = 1;
        for (SKU_Config_Staging_Entry__c entry : entries) {
            String filePath = deriveFilePath(entry);
            prBody += fileNum + '. `' + filePath + '` (' + entry.Operation_Type__c.toLowerCase() + ')\n';
            fileNum++;
        }

        prBody += '\n_This PR was auto-generated by the SKU Config Staging batch._';
        return prBody;
    }
}