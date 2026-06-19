/**
 * @description Service class for interacting with the GitHub REST API.
 *              Provides low-level HTTP methods for GitHub operations including
 *              reading files, creating blobs, trees, commits, branches, and pull requests.
 *              Part of the PoC for SKU Management App config data PR automation.
 * @author      BIZ-80418
 * @date        2026-03-05
 */

public with sharing class GitHubApiService {

    private static final String GITHUB_API_BASE = 'https://api.github.com';
    private static final Integer TIMEOUT_MS = 30000;

    /**
     * @description Retrieves GitHub configuration from Custom Metadata.
     * @return GitHub_Settings__mdt record with API credentials and repo info.
     */
    public static GitHub_Settings__mdt getSettings() {
        List<GitHub_Settings__mdt> settings = [
            SELECT DeveloperName, Personal_Access_Token__c, Repository_Owner__c,
                   Repository_Name__c, Base_Branch__c, Target_Branch__c
            FROM GitHub_Settings__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (settings.isEmpty()) {
            throw new GitHubApiException('GitHub_Settings__mdt "Default" record not found. Please configure GitHub settings.');
        }
        return settings[0];
    }

    // ─── Core HTTP Methods ───────────────────────────────────────────────

    /**
     * @description Performs a GET request to the GitHub API
     * @param endpoint The API endpoint path (e.g., /repos/{owner}/{repo}/...)
     * @return HttpResponse from GitHub
     */
    public static HttpResponse doGet(String endpoint) {
        return sendRequest('GET', endpoint, null);
    }

    /**
     * @description Performs a POST request to the GitHub API
     * @param endpoint The API endpoint path
     * @param body JSON request body
     * @return HttpResponse from GitHub
     */
    public static HttpResponse doPost(String endpoint, String body) {
        return sendRequest('POST', endpoint, body);
    }

    /**
     * @description Performs a PATCH request to the GitHub API
     * @param endpoint The API endpoint path
     * @param body JSON request body
     * @return HttpResponse from GitHub
     */
    public static HttpResponse doPatch(String endpoint, String body) {
        return sendRequest('PATCH', endpoint, body);
    }

    /**
     * @description Performs a PUT request to the GitHub API
     * @param endpoint The API endpoint path
     * @param body JSON request body
     * @return HttpResponse from GitHub
     */
    public static HttpResponse doPut(String endpoint, String body) {
        return sendRequest('PUT', endpoint, body);
    }

    // ─── GitHub API Operations ───────────────────────────────────────────

    /**
     * @description Gets a reference (branch) from the repository
     * @param owner Repository owner
     * @param repo Repository name
     * @param refPath Reference path (e.g., heads/staging)
     * @return Parsed JSON map of the reference
     */
    public static Map<String, Object> getReference(String owner, String repo, String refPath) {
        String endpoint = '/repos/' + owner + '/' + repo + '/git/ref/' + refPath;
        HttpResponse res = doGet(endpoint);
        validateResponse(res, 200, 'Get reference');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Creates a new branch reference
     * @param owner Repository owner
     * @param repo Repository name
     * @param branchName New branch name
     * @param fromSha SHA to branch from
     * @return Parsed JSON map of the new reference
     */
    
    public static Map<String, Object> createBranch(String owner, String repo, String branchName, String fromSha) {
        String endpoint = '/repos/' + owner + '/' + repo + '/git/refs';
        Map<String, String> payload = new Map<String, String>{
            'ref' => 'refs/heads/' + branchName,
            'sha' => fromSha
        };
        HttpResponse res = doPost(endpoint, JSON.serialize(payload));
        validateResponse(res, 201, 'Create branch');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Gets the content of a file from the repository
     * @param owner Repository owner
     * @param repo Repository name
     * @param filePath Path to the file in the repo
     * @param branchRef Branch reference
     * @return Parsed JSON map with file content and metadata
     */
    public static Map<String, Object> getFileContent(String owner, String repo, String filePath, String branchRef) {
        String endpoint = '/repos/' + owner + '/' + repo + '/contents/' + encodePathSegments(filePath) + '?ref=' + branchRef;
        HttpResponse res = doGet(endpoint);
        if (res.getStatusCode() == 404) {
            return null; // File does not exist
        }
        validateResponse(res, 200, 'Get file content');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Creates or updates a file in the repository
     * @param owner Repository owner
     * @param repo Repository name
     * @param filePath Path to the file
     * @param contentBase64 Base64-encoded file content
     * @param commitMessage Commit message
     * @param branchName Branch to commit to
     * @param existingSha SHA of existing file (null for new files)
     * @return Parsed JSON map of the commit result
     */
    public static Map<String, Object> createOrUpdateFile(
        String owner, String repo, String filePath,
        String contentBase64, String commitMessage,
        String branchName, String existingSha
    ) {
        String endpoint = '/repos/' + owner + '/' + repo + '/contents/' + filePath;
        Map<String, Object> payload = new Map<String, Object>{
            'message' => commitMessage,
            'content' => contentBase64,
            'branch'  => branchName
        };
        if (existingSha != null) {
            payload.put('sha', existingSha);
        }
        HttpResponse res = doPut(endpoint, JSON.serialize(payload));
        // 200 for update, 201 for create
        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new GitHubApiException(
                'Create/Update file failed (' + res.getStatusCode() + '): ' + res.getBody()
            );
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Creates a pull request
     * @param owner Repository owner
     * @param repo Repository name
     * @param title PR title
     * @param body PR description body
     * @param headBranch Source branch
     * @param baseBranch Target branch
     * @return Parsed JSON map of the created PR
     */
    
    public static Map<String, Object> createPullRequest(
        String owner, String repo, String title,
        String body, String headBranch, String baseBranch
    ) {
        String endpoint = '/repos/' + owner + '/' + repo + '/pulls';
        Map<String, String> payload = new Map<String, String>{
            'title' => title,
            'body'  => body,
            'head'  => headBranch,
            'base'  => baseBranch
        };
        HttpResponse res = doPost(endpoint, JSON.serialize(payload));
        validateResponse(res, 201, 'Create pull request');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Lists the contents of a directory in the repository.
     *              Returns a list of file/directory metadata maps.
     *              Returns an empty list if the directory does not exist (404).
     * @param owner Repository owner
     * @param repo Repository name
     * @param dirPath Path to the directory in the repo
     * @param branchRef Branch reference
     * @return List of parsed JSON maps for each item in the directory
     */
    public static List<Object> listDirectory(String owner, String repo, String dirPath, String branchRef) {
        String endpoint = '/repos/' + owner + '/' + repo + '/contents/' + dirPath + '?ref=' + branchRef;
        HttpResponse res = doGet(endpoint);
        if (res.getStatusCode() == 404) {
            return new List<Object>();
        }
        validateResponse(res, 200, 'List directory');
        return (List<Object>) JSON.deserializeUntyped(res.getBody());
    }
    

    /**
     * @description Lists directory contents via Git Tree API — no 1000-file cap.
     *              Resolves: branchRef → commit → root tree → subtree for dirPath.
     *              Each returned map has 'path' (filename only), 'type' ('blob'/'tree'), and 'sha'.
     * @param owner Repository owner
     * @param repo Repository name
     * @param dirPath Directory path (e.g. 'configdata/PricebookEntry')
     * @param branchRef Branch reference
     * @return List of parsed JSON maps for each item
     */
    public static List<Object> listDirectoryViaTree(
        String owner, String repo, String dirPath, String branchRef
    ) {
        // Step 1: Resolve branch → commit SHA → root tree SHA
        Map<String, Object> refData = getReference(owner, repo, 'heads/' + branchRef);
        String commitSha = (String) ((Map<String, Object>) refData.get('object')).get('sha');
        Map<String, Object> commitData = getCommit(owner, repo, commitSha);
        String rootTreeSha = (String) ((Map<String, Object>) commitData.get('tree')).get('sha');

        // Step 2: Walk each segment of dirPath to find the subtree SHA
        String treeSha = rootTreeSha;
        for (String segment : dirPath.split('/')) {
            String endpoint = '/repos/' + owner + '/' + repo + '/git/trees/' + treeSha;
            HttpResponse res = doGet(endpoint);
            if (res.getStatusCode() == 404) { return new List<Object>(); }
            validateResponse(res, 200, 'Get tree');

            Map<String, Object> treeData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> entries = (List<Object>) treeData.get('tree');
            String nextSha = null;
            for (Object entry : entries) {
                Map<String, Object> e = (Map<String, Object>) entry;
                if (segment.equals((String) e.get('path')) && 'tree'.equals((String) e.get('type'))) {
                    nextSha = (String) e.get('sha');
                    break;
                }
            }
            if (nextSha == null) { return new List<Object>(); }
            treeSha = nextSha;
        }

        // Step 3: Fetch the target subtree (non-recursive — single level)
        String endpoint = '/repos/' + owner + '/' + repo + '/git/trees/' + treeSha;
        HttpResponse res = doGet(endpoint);
        if (res.getStatusCode() == 404) { return new List<Object>(); }
        validateResponse(res, 200, 'Get subtree');

        Map<String, Object> treeData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (List<Object>) treeData.get('tree');
    }

    /**
     * @description Gets a specific commit by SHA
     * @param owner Repository owner
     * @param repo Repository name
     * @param sha Commit SHA
     * @return Parsed JSON map of the commit
     */
    
    public static Map<String, Object> getCommit(String owner, String repo, String sha) {
        String endpoint = '/repos/' + owner + '/' + repo + '/git/commits/' + sha;
        HttpResponse res = doGet(endpoint);
        validateResponse(res, 200, 'Get commit');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Creates a new blob (file content) in the repository
     * @param owner Repository owner
     * @param repo Repository name
     * @param content File content
     * @param encoding Content encoding (utf-8 or base64)
     * @return Parsed JSON map with the blob SHA
     */
    public static Map<String, Object> createBlob(String owner, String repo, String content, String encoding) {
        String endpoint = '/repos/' + owner + '/' + repo + '/git/blobs';
        Map<String, String> payload = new Map<String, String>{
            'content'  => content,
            'encoding' => encoding
        };
        HttpResponse res = doPost(endpoint, JSON.serialize(payload));
        validateResponse(res, 201, 'Create blob');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Creates a new tree in the repository
     * @param owner Repository owner
     * @param repo Repository name
     * @param baseTreeSha Base tree SHA
     * @param treeItems List of tree item maps (path, mode, type, sha)
     * @return Parsed JSON map with the tree SHA
     */
    public static Map<String, Object> createTree(
        String owner, String repo, String baseTreeSha, List<Map<String, String>> treeItems
    ) {
        String endpoint = '/repos/' + owner + '/' + repo + '/git/trees';
        Map<String, Object> payload = new Map<String, Object>{
            'base_tree' => baseTreeSha,
            'tree'      => treeItems
        };
        HttpResponse res = doPost(endpoint, JSON.serialize(payload));
        validateResponse(res, 201, 'Create tree');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Creates a new commit
     * @param owner Repository owner
     * @param repo Repository name
     * @param message Commit message
     * @param treeSha Tree SHA for the commit
     * @param parentSha Parent commit SHA
     * @return Parsed JSON map with the commit SHA
     */
    public static Map<String, Object> createCommit(
        String owner, String repo, String message, String treeSha, String parentSha
    ) {
        String endpoint = '/repos/' + owner + '/' + repo + '/git/commits';
        Map<String, Object> payload = new Map<String, Object>{
            'message' => message,
            'tree'    => treeSha,
            'parents' => new List<String>{ parentSha }
        };
        HttpResponse res = doPost(endpoint, JSON.serialize(payload));
        validateResponse(res, 201, 'Create commit');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * @description Updates a branch reference to point to a new commit
     * @param owner Repository owner
     * @param repo Repository name
     * @param branchName Branch name
     * @param commitSha New commit SHA
     * @return Parsed JSON map of the updated reference
     */
    public static Map<String, Object> updateReference(
        String owner, String repo, String branchName, String commitSha
    ) {
        String endpoint = '/repos/' + owner + '/' + repo + '/git/refs/heads/' + branchName;
        Map<String, Object> payload = new Map<String, Object>{
            'sha'   => commitSha,
            'force' => false
        };
        HttpResponse res = doPatch(endpoint, JSON.serialize(payload));
        validateResponse(res, 200, 'Update reference');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // ─── Private Helpers ─────────────────────────────────────────────────

    private static HttpResponse sendRequest(String method, String endpoint, String body) {
        GitHub_Settings__mdt settings = getSettings();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(GITHUB_API_BASE + endpoint);
        req.setMethod(method);
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Accept', 'application/vnd.github+json');
        req.setHeader('Authorization', 'Bearer ' + settings.Personal_Access_Token__c);
        req.setHeader('X-GitHub-Api-Version', '2022-11-28');

        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }

        Http http = new Http();
        return http.send(req);
    }

    private static void validateResponse(HttpResponse res, Integer expectedStatus, String operation) {
        if (res.getStatusCode() != expectedStatus) {
            String errMsg = operation + ' failed (HTTP ' + res.getStatusCode() + '): ' + res.getBody();
            Nebula.Logger.error(errMsg).addTag('GitHubApiService');
            Nebula.Logger.saveLog();
            throw new GitHubApiException(errMsg);
        }
    }

    /**
     * @description URL-encodes each segment of a file path while preserving '/' separators.
     *              E.g. 'configdata/Product2/My Product_[EXT].gs.json'
     *              → 'configdata/Product2/My+Product_%5BEXT%5D.gs.json'
     */
    @TestVisible
    private static String encodePathSegments(String filePath) {
        List<String> segments = filePath.split('/');
        List<String> encoded = new List<String>();
        for (String seg : segments) {
            encoded.add(EncodingUtil.urlEncode(seg, 'UTF-8'));
        }
        return String.join(encoded, '/');
    }

    // ─── Custom Exception ────────────────────────────────────────────────

    public class GitHubApiException extends Exception {}
}