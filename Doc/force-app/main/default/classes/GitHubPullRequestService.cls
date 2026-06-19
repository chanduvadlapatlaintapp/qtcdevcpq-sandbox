/**
 * @description High-level service that orchestrates creating a GitHub Pull Request
 *              with config data changes from the SKU Management App.
 *              Uses the Git Data API (blob → tree → commit → ref → PR) to support
 *              multi-file commits in a single PR.
 *
 *              PoC Flow:
 *              1. Get latest SHA of target branch (staging)
 *              2. Create a new feature branch from that SHA
 *              3. Create blobs for each changed file
 *              4. Create a tree with the new blobs
 *              5. Create a commit on the new tree
 *              6. Update the feature branch ref to the new commit
 *              7. Open a PR from the feature branch → target branch
 *
 * @author      BIZ-80418
 * @date        2026-03-05
 */
public with sharing class GitHubPullRequestService {
    

    /**
     * @description Wrapper to hold a file change for the PR
     */
    public class FileChange {
        public String filePath;     // e.g., configdata/Product2/record-001.gs.json
        public String content;      // Full JSON content of the file
        public String changeType;   // 'update' or 'create'

        public FileChange(String filePath, String content, String changeType) {
            this.filePath = filePath;
            this.content = content;
            this.changeType = changeType;
        }
    }

    /**
     * @description Result wrapper for the PR creation outcome
     */
    public class PullRequestResult {
        public Boolean success;
        public String prUrl;
        public Integer prNumber;
        public String branchName;
        public String errorMessage;

        public PullRequestResult() {
            this.success = false;
        }
    }

    /**
     * @description Creates a Pull Request with the given config data file changes
     *              against the configured target branch (staging for PoC).
     * @param fileChanges List of file changes to include in the PR
     * @param prTitle Title for the pull request
     * @param prDescription Description/body for the pull request
     * @return PullRequestResult with success status and PR URL
     */
    public static PullRequestResult createConfigDataPR(
        List<FileChange> fileChanges,
        String prTitle,
        String prDescription
    ) {
        PullRequestResult result = new PullRequestResult();

        if (fileChanges == null || fileChanges.isEmpty()) {
            result.errorMessage = 'No file changes provided.';
            return result;
        }

        try {
            GitHub_Settings__mdt settings = GitHubApiService.getSettings();
            String owner = settings.Repository_Owner__c;
            String repo  = settings.Repository_Name__c;
            String baseBranch   = settings.Base_Branch__c;   // 'master' — configdata lives here
            String targetBranch = settings.Target_Branch__c; // 'staging' — PR target

            Nebula.Logger.info('Starting PR creation: ' + prTitle + ' | '
                + fileChanges.size() + ' file(s) | base=' + baseBranch + ' target=' + targetBranch)
                .addTag('GitHubPullRequestService');

            // Step 1: Get the latest commit SHA of the base branch (master)
            Map<String, Object> targetRef = GitHubApiService.getReference(owner, repo, 'heads/' + baseBranch);
            Map<String, Object> refObject = (Map<String, Object>) targetRef.get('object');
            String latestCommitSha = (String) refObject.get('sha');

            // Step 2: Create a unique feature branch name
            String branchName = generateBranchName(prTitle);
            result.branchName = branchName;

            // Step 3: Create the new branch from the target branch SHA
            GitHubApiService.createBranch(owner, repo, branchName, latestCommitSha);
            Nebula.Logger.info('Branch created: ' + branchName + ' from ' + baseBranch + ' (' + latestCommitSha.left(7) + ')')
                .addTag('GitHubPullRequestService');

            // Step 4: Get the tree SHA from the latest commit
            Map<String, Object> latestCommit = GitHubApiService.getCommit(owner, repo, latestCommitSha);
            Map<String, Object> commitTree = (Map<String, Object>) latestCommit.get('tree');
            String baseTreeSha = (String) commitTree.get('sha');

            // Step 4b: Resolve existing file paths from the base branch (master)
            //          so that updated files reuse their current path (avoids duplicates).
            remapToExistingPaths(fileChanges, owner, repo, baseBranch);

            // Step 4c: For existing files, merge our field changes into the full
            //          repo content so the PR diff only shows actual modifications.
            mergeWithExistingContent(fileChanges, owner, repo, baseBranch);

            // Step 5: Create blobs for each file change and build tree entries
            List<Map<String, String>> treeItems = new List<Map<String, String>>();

            for (FileChange fc : fileChanges) {
                Map<String, Object> blobResult = GitHubApiService.createBlob(
                    owner, repo, fc.content, 'utf-8'
                );
                String blobSha = (String) blobResult.get('sha');

                Map<String, String> treeItem = new Map<String, String>{
                    'path' => fc.filePath,
                    'mode' => '100644',   // regular file
                    'type' => 'blob',
                    'sha'  => blobSha
                };
                treeItems.add(treeItem);
            }

            Nebula.Logger.info('Created ' + treeItems.size() + ' blob(s) for tree')
                .addTag('GitHubPullRequestService');

            // Step 6: Create a new tree with the changes
            Map<String, Object> newTree = GitHubApiService.createTree(
                owner, repo, baseTreeSha, treeItems
            );
            String newTreeSha = (String) newTree.get('sha');

            // Step 7: Create a commit on the new tree
            String commitMessage = buildCommitMessage(prTitle, fileChanges);
            Map<String, Object> newCommit = GitHubApiService.createCommit(
                owner, repo, commitMessage, newTreeSha, latestCommitSha
            );
            String newCommitSha = (String) newCommit.get('sha');

            // Step 8: Update the feature branch to point to the new commit
            GitHubApiService.updateReference(owner, repo, branchName, newCommitSha);

            // Step 9: Create the Pull Request
            Map<String, Object> pr = GitHubApiService.createPullRequest(
                owner, repo, prTitle, prDescription, branchName, targetBranch
            );

            result.success = true;
            result.prUrl = (String) pr.get('html_url');
            result.prNumber = ((Decimal) pr.get('number')).intValue();

            Nebula.Logger.info('PR created successfully: #' + result.prNumber + ' ' + result.prUrl)
                .addTag('GitHubPullRequestService');
            Nebula.Logger.saveLog();

        } catch (GitHubApiService.GitHubApiException e) {
            result.errorMessage = 'GitHub API error: ' + e.getMessage();
            Nebula.Logger.error('GitHub API error during PR creation: ' + e.getMessage()
                + ' | Stack: ' + e.getStackTraceString())
                .addTag('GitHubPullRequestService');
            Nebula.Logger.saveLog();
        } catch (Exception e) {
            result.errorMessage = 'Unexpected error: ' + e.getMessage() + ' | ' + e.getStackTraceString();
            Nebula.Logger.error('Unexpected error during PR creation: ' + e.getMessage()
                + ' | Stack: ' + e.getStackTraceString())
                .addTag('GitHubPullRequestService');
            Nebula.Logger.saveLog();
        }

        return result;
    }

    /**
     * @description Convenience method for single-file PRs (common for individual record updates)
     * @param filePath Path to the config data file in the repo
     * @param jsonContent Updated JSON content
     * @param recordName Friendly name of the record being changed
     * @return PullRequestResult
     */
    
    public static PullRequestResult createSingleFilePR(
        String filePath, String jsonContent, String recordName
    ) {
        List<FileChange> changes = new List<FileChange>{
            new FileChange(filePath, jsonContent, 'update')
        };

        String title = 'Config Update: ' + recordName;
        String description = '## Config Data Change\n\n'
            + '**Record:** ' + recordName + '\n'
            + '**File:** `' + filePath + '`\n'
            + '**Source:** SKU Management App\n'
            + '**Timestamp:** ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss z') + '\n\n'
            + '_This PR was auto-generated by the SKU Management App._';

        return createConfigDataPR(changes, title, description);
    }

    // ────── Private Helpers ─────────────────────────────────────────────────

    /**
     * @description Generates a unique branch name based on PR title and timestamp
     */
    @TestVisible
    private static String generateBranchName(String prTitle) {
        String sanitized = prTitle.replaceAll('[^a-zA-Z0-9]', '-').toLowerCase();
        if (sanitized.length() > 40) {
            sanitized = sanitized.substring(0, 40);
        }
        String timestamp = Datetime.now().format('yyyyMMdd-HHmmss');
        return 'sku-app/' + sanitized + '-' + timestamp;
    }

    /**
     * @description Lists the configdata/{ObjectType}/ directories for each unique
     *              object type in the file changes, then remaps FileChange paths so
     *              that files with an existing entry in the repo (matched by
     *              GearsetExternalId) reuse the original path.
     *              This prevents Gearset validation errors caused by two files having
     *              the same GearsetExternalId under different filenames.
     * @param fileChanges   List of FileChange objects whose filePaths may be remapped
     * @param owner         Repository owner
     * @param repo          Repository name
     * @param targetBranch  Branch to check for existing files
     */
    @TestVisible
    private static void remapToExistingPaths(
        List<FileChange> fileChanges, String owner, String repo, String targetBranch
    ) {
        // Collect unique object directories from the file changes
        // e.g., configdata/Block_Pricing__c/ → we need to list this directory
        Set<String> objectDirs = new Set<String>();
        for (FileChange fc : fileChanges) {
            // File path format: configdata/{ObjectType}/{filename}.gs.json
            String[] parts = fc.filePath.split('/');
            if (parts.size() >= 2) {
                objectDirs.add(parts[0] + '/' + parts[1]);
            }
        }

        // For each unique object directory, list existing files and build extId → path map.
        // Uses Git Tree API instead of Contents API to bypass the 1000-file limit.
        Map<String, String> existingPathsByExtId = new Map<String, String>();
        for (String dir : objectDirs) {
            List<Object> dirContents = GitHubApiService.listDirectoryViaTree(owner, repo, dir, targetBranch);
            for (Object item : dirContents) {
                Map<String, Object> fileInfo = (Map<String, Object>) item;
                // Tree API returns 'path' (filename) and type 'blob' for files
                String name = (String) fileInfo.get('path');
                String type = (String) fileInfo.get('type');

                if (type != 'blob' || !name.endsWith('.gs.json')) {
                    continue;
                }

                String extId = extractExternalId(name);
                if (extId != null) {
                    existingPathsByExtId.put(extId, dir + '/' + name);
                }
            }
        }

        // Remap FileChange paths where an existing file is found for the same external Id
        Integer remapped = 0;
        for (FileChange fc : fileChanges) {
            String extId = extractExternalId(fc.filePath);
            if (extId != null && existingPathsByExtId.containsKey(extId)) {
                String oldPath = fc.filePath;
                fc.filePath = existingPathsByExtId.get(extId);
                if (oldPath != fc.filePath) { remapped++; }
            }
        }
        Nebula.Logger.info('remapToExistingPaths: ' + remapped + '/' + fileChanges.size()
            + ' file(s) remapped to existing repo paths')
            .addTag('GitHubPullRequestService');
    }

    /**
     * @description For each FileChange that targets an existing file in the repo,
     *              fetches the current file content and merges our changes into it.
     *              This ensures the PR diff only shows the fields we actually changed,
     *              rather than replacing the entire file with a subset of fields.
     * @param fileChanges  List of FileChange objects whose content may be merged
     * @param owner        Repository owner
     * @param repo         Repository name
     * @param branchRef    Branch to read existing files from
     */
    
    @TestVisible
    private static void mergeWithExistingContent(
        List<FileChange> fileChanges, String owner, String repo, String branchRef
    ) {
        Integer merged = 0;
        Integer newFiles = 0;
        for (FileChange fc : fileChanges) {
            // Only merge for updates/creates where a file already exists
            Map<String, Object> fileData = GitHubApiService.getFileContent(
                owner, repo, fc.filePath, branchRef
            );
            if (fileData == null) {
                // New file — use our content as-is
                newFiles++;
                continue;
            }

            // Decode the existing file content (base64-encoded by GitHub API)
            String encodedContent = (String) fileData.get('content');
            // GitHub returns base64 with newlines — strip them
            encodedContent = encodedContent.replaceAll('\\n', '').replaceAll('\\r', '');
            String existingJson = EncodingUtil.base64Decode(encodedContent).toString();

            // Merge our fields into the existing full JSON
            fc.content = mergeGearsetJson(existingJson, fc.content);
            merged++;
        }
        Nebula.Logger.info('mergeWithExistingContent: ' + merged + ' merged, ' + newFiles + ' new file(s)')
            .addTag('GitHubPullRequestService');
    }

    /**
     * @description Merges our field changes into the existing .gs.json by patching
     *              values line-by-line. Preserves the existing file's exact formatting,
     *              key order, and indentation so the PR diff shows only actual changes.
     *              - Only updates field values that already exist in the file
     *              - Skips GearsetDisplayName (Gearset-computed, not from Salesforce)
     *              - Updates Reference GearsetExternalId__c values when the lookup changed
     * @param existingJson The full JSON currently in the repo
     * @param ourJson      Our JSON with only the fields we captured
     * @return The patched JSON string
     */
    @TestVisible
    private static String mergeGearsetJson(String existingJson, String ourJson) {
        Map<String, Object> ours = (Map<String, Object>) JSON.deserializeUntyped(ourJson);
        Map<String, Object> ourFields = (Map<String, Object>) ours.get('Fields');
        if (ourFields == null) {
            return existingJson;
        }

        // Check which keys exist in the existing file
        Map<String, Object> existing = (Map<String, Object>) JSON.deserializeUntyped(existingJson);
        Map<String, Object> existingFields = (Map<String, Object>) existing.get('Fields');

        // Resolve boolean field names for the object so we can fix empty → "false"
        // and inject missing boolean fields that Gearset requires.
        // Skip system fields that Gearset doesn't manage.
        Set<String> SYSTEM_BOOLEAN_FIELDS = new Set<String>{
            'IsDeleted', 'IsArchived'
        };
        String objectApiName = (String) existing.get('Object');
        Set<String> booleanFields = new Set<String>();
        if (objectApiName != null) {
            Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
            if (sot != null) {
                for (Schema.SObjectField sof : sot.getDescribe().fields.getMap().values()) {
                    Schema.DescribeFieldResult dfr = sof.getDescribe();
                    if (dfr.getType() == Schema.DisplayType.BOOLEAN
                        && !SYSTEM_BOOLEAN_FIELDS.contains(dfr.getName())
                        && !dfr.isCalculated()) {
                        booleanFields.add(dfr.getName());
                    }
                }
            }
        }

        // Identify boolean fields missing from the existing file
        Set<String> missingBooleans = new Set<String>();
        if (existingFields != null && !booleanFields.isEmpty()) {
            for (String bf : booleanFields) {
                if (!existingFields.containsKey(bf)) {
                    missingBooleans.add(bf);
                }
            }
        }

        // Build map of field values to patch (only existing keys, skip GearsetDisplayName)
        Map<String, String> fieldsToUpdate = new Map<String, String>();
        for (String key : ourFields.keySet()) {
            if (existingFields != null && existingFields.containsKey(key)
                && key != 'GearsetDisplayName') {
                String val = ourFields.get(key) != null ? String.valueOf(ourFields.get(key)) : '';
                fieldsToUpdate.put(key, val);
            }
        }

        // Build reference update map: refName → resolved GearsetExternalId__c
        Map<String, String> refsToUpdate = new Map<String, String>();
        List<Object> ourRefs = (List<Object>) ours.get('References');
        if (ourRefs != null) {
            for (Object refObj : ourRefs) {
                Map<String, Object> ref = (Map<String, Object>) refObj;
                String refName = (String) ref.get('Name');
                Map<String, Object> refFields = (Map<String, Object>) ref.get('ReferencedFields');
                if (refName != null && refFields != null) {
                    String extId = (String) refFields.get('GearsetExternalId__c');
                    if (extId != null) {
                        refsToUpdate.put(refName, extId);
                    }
                }
            }
        }

        // Patch line-by-line, preserving exact format and key order
        List<String> lines = existingJson.split('\n');
        List<String> result = new List<String>();

        Boolean inFields = false;
        Boolean inReferences = false;
        String currentRefName = null;

        for (String line : lines) {
            String trimmed = line.trim();

            // Track which section we're in
            if (trimmed.startsWith('"Fields"')) {
                inFields = true;
            }
            if (inFields && (trimmed == '},' || trimmed == '}')) {
                // Could be end of Fields — check by looking at depth
                // Fields block ends with "  }," at 2-space indent
                String indent = line.length() > 0 ? line.substring(0, line.length() - trimmed.length()) : '';
                if (indent.length() <= 2) {
                    // Inject missing boolean fields before closing the Fields block
                    if (!missingBooleans.isEmpty()) {
                        // Ensure the previous line ends with a comma
                        if (!result.isEmpty()) {
                            String lastLine = result.get(result.size() - 1);
                            if (!lastLine.trim().endsWith(',')) {
                                result.set(result.size() - 1, lastLine + ',');
                            }
                        }
                        List<String> sortedMissing = new List<String>(missingBooleans);
                        sortedMissing.sort();
                        for (Integer m = 0; m < sortedMissing.size(); m++) {
                            String bfName = sortedMissing.get(m);
                            String bfLine = '    "' + bfName + '": "false"';
                            if (m < sortedMissing.size() - 1) { bfLine += ','; }
                            result.add(bfLine);
                        }
                    }
                    inFields = false;
                }
            }
            if (trimmed.startsWith('"References"')) {
                inFields = false;
                inReferences = true;
            }

            Boolean replaced = false;

            // Patch field values inside "Fields" section
            if (inFields) {
                for (String key : fieldsToUpdate.keySet()) {
                    String prefix = '"' + key + '": "';
                    if (trimmed.startsWith(prefix)) {
                        String indent = line.substring(0, line.length() - trimmed.length());
                        Boolean hasComma = trimmed.endsWith(',');
                        String escapedVal = fieldsToUpdate.get(key)
                            .replace('\\', '\\\\').replace('"', '\\"');
                        String newLine = indent + '"' + key + '": "' + escapedVal + '"';
                        if (hasComma) { newLine += ','; }
                        result.add(newLine);
                        replaced = true;
                        break;
                    }
                }
            }

            // Track reference context & patch GearsetExternalId__c values
            if (inReferences && !replaced) {
                if (trimmed.startsWith('"Name": "')) {
                    Integer start = trimmed.indexOf('"Name": "') + 9;
                    Integer nameEnd = trimmed.indexOf('"', start);
                    if (nameEnd > start) {
                        currentRefName = trimmed.substring(start, nameEnd);
                    }
                }

                if (currentRefName != null
                    && refsToUpdate.containsKey(currentRefName)
                    && trimmed.startsWith('"GearsetExternalId__c": "')) {
                    String indent = line.substring(0, line.length() - trimmed.length());
                    Boolean hasComma = trimmed.endsWith(',');
                    String newLine = indent + '"GearsetExternalId__c": "'
                        + refsToUpdate.get(currentRefName) + '"';
                    if (hasComma) { newLine += ','; }
                    result.add(newLine);
                    replaced = true;
                }
            }

            // Fix empty-string boolean fields → "false" (Gearset requires valid boolean)
            if (!replaced && inFields && !booleanFields.isEmpty()) {
                for (String boolField : booleanFields) {
                    String boolPrefix = '"' + boolField + '": ""';
                    if (trimmed.startsWith(boolPrefix)) {
                        String indent = line.substring(0, line.length() - trimmed.length());
                        Boolean hasComma = trimmed.endsWith(',');
                        String newLine = indent + '"' + boolField + '": "false"';
                        if (hasComma) { newLine += ','; }
                        result.add(newLine);
                        replaced = true;
                        break;
                    }
                }
            }

            if (!replaced) {
                result.add(line);
            }
        }

        return String.join(result, '\n');
    }

    /**
     * @description Extracts the GearsetExternalId from a file path matching the
     *              pattern: configdata/{Object}/{DisplayName}_[{ExternalId}].gs.json
     * @param filePath The file path to parse
     * @return The extracted external Id, or null if the path doesn't match
     */
    @TestVisible
    private static String extractExternalId(String filePath) {
        // Look for the pattern _[{id}].gs.json at the end of the path
        Integer bracketStart = filePath.lastIndexOf('_[');
        Integer bracketEnd = filePath.lastIndexOf('].gs.json');
        if (bracketStart >= 0 && bracketEnd > bracketStart) {
            return filePath.substring(bracketStart + 2, bracketEnd);
        }
        return null;
    }

    /**
     * @description Builds a descriptive commit message listing changed files.
     */
    private static String buildCommitMessage(String prTitle, List<FileChange> fileChanges) {
        String msg = prTitle + '\n\n';
        msg += 'Changed files:\n';
        for (FileChange fc : fileChanges) {
            msg += '- ' + fc.changeType + ': ' + fc.filePath + '\n';
        }
        msg += '\nAuto-committed by SKU Management App';
        return msg;
    }
}