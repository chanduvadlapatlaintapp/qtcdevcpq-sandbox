/**
 * @description Test class for GitHubApiService.
 *              Uses HttpCalloutMock to simulate GitHub API responses.
 * @author      BIZ-80418
 * @date        2026-03-05
 */
@IsTest
private class GitHubApiServiceTest {

    // ─── Mock Implementation ─────────────────────────────────────────────

    private class GitHubMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public GitHubMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setBody(this.responseBody);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    // Multi-request mock that returns different responses per endpoint
    private class GitHubMultiMock implements HttpCalloutMock {
        private Map<String, HttpCalloutMock> endpointMocks;
        private HttpCalloutMock defaultMock;

        public GitHubMultiMock(Map<String, HttpCalloutMock> endpointMocks, HttpCalloutMock defaultMock) {
            this.endpointMocks = endpointMocks;
            this.defaultMock = defaultMock;
        }

        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint();
            for (String key : endpointMocks.keySet()) {
                if (endpoint.contains(key)) {
                    return endpointMocks.get(key).respond(req);
                }
            }
            return defaultMock.respond(req);
        }
    }

    // ─── Test Methods ────────────────────────────────────────────────────

    @IsTest
    static void testGetReference() {
        String mockResponse = '{"ref":"refs/heads/staging","object":{"sha":"abc123def456","type":"commit"}}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(200, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.getReference('Intapp-BizApps', 'Salesforce-gearset', 'heads/staging');
        Test.stopTest();

        System.assertEquals('refs/heads/staging', (String) result.get('ref'), 'Reference should match');
        Map<String, Object> obj = (Map<String, Object>) result.get('object');
        System.assertEquals('abc123def456', (String) obj.get('sha'), 'SHA should match');
    }

    @IsTest
    static void testCreateBranch() {
        String mockResponse = '{"ref":"refs/heads/sku-app/test-branch","object":{"sha":"abc123"}}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(201, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.createBranch(
            'Intapp-BizApps', 'Salesforce-gearset', 'sku-app/test-branch', 'abc123'
        );
        Test.stopTest();

        System.assertEquals('refs/heads/sku-app/test-branch', (String) result.get('ref'));
    }

    @IsTest
    static void testGetFileContent() {
        String mockResponse = '{"name":"record.gs.json","path":"configdata/Product2/record.gs.json","sha":"file123","content":"eyJ0ZXN0IjoidmFsdWUifQ==","encoding":"base64"}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(200, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.getFileContent(
            'Intapp-BizApps', 'Salesforce-gearset', 'configdata/Product2/record.gs.json', 'staging'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('file123', (String) result.get('sha'));
    }

    @IsTest
    static void testGetFileContentNotFound() {
        Test.setMock(HttpCalloutMock.class, new GitHubMock(404, '{"message":"Not Found"}'));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.getFileContent(
            'Intapp-BizApps', 'Salesforce-gearset', 'nonexistent.json', 'staging'
        );
        Test.stopTest();

        System.assertEquals(null, result, 'Result should be null for 404');
    }

    @IsTest
    static void testCreateOrUpdateFile() {
        String mockResponse = '{"content":{"sha":"new123"},"commit":{"sha":"commit456"}}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(201, mockResponse));

        String content = EncodingUtil.base64Encode(Blob.valueOf('{"test":"value"}'));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.createOrUpdateFile(
            'Intapp-BizApps', 'Salesforce-gearset',
            'configdata/Product2/record.gs.json',
            content, 'Update product record', 'sku-app/test', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testCreateOrUpdateFileWithExistingSha() {
        String mockResponse = '{"content":{"sha":"updated123"},"commit":{"sha":"commit789"}}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(200, mockResponse));

        String content = EncodingUtil.base64Encode(Blob.valueOf('{"test":"updated"}'));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.createOrUpdateFile(
            'Intapp-BizApps', 'Salesforce-gearset',
            'configdata/Product2/record.gs.json',
            content, 'Update product record', 'sku-app/test', 'existing123'
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testCreatePullRequest() {
        String mockResponse = '{"number":42,"html_url":"https://github.com/Intapp-BizApps/Salesforce-gearset/pull/42","state":"open"}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(201, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.createPullRequest(
            'Intapp-BizApps', 'Salesforce-gearset',
            'Config Update: Test Product', 'Auto-generated PR',
            'sku-app/test-branch', 'staging'
        );
        Test.stopTest();

        System.assertEquals(42, ((Decimal) result.get('number')).intValue());
        System.assert(((String) result.get('html_url')).contains('/pull/42'));
    }

    @IsTest
    static void testCreateBlob() {
        String mockResponse = '{"sha":"blob123","url":"https://api.github.com/repos/Intapp-BizApps/Salesforce-gearset/git/blobs/blob123"}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(201, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.createBlob(
            'Intapp-BizApps', 'Salesforce-gearset', '{"test":"value"}', 'utf-8'
        );
        Test.stopTest();

        System.assertEquals('blob123', (String) result.get('sha'));
    }

    @IsTest
    static void testCreateTree() {
        String mockResponse = '{"sha":"tree123","url":"https://api.github.com/repos/test/git/trees/tree123"}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(201, mockResponse));

        List<Map<String, String>> treeItems = new List<Map<String, String>>{
            new Map<String, String>{
                'path' => 'configdata/Product2/test.gs.json',
                'mode' => '100644',
                'type' => 'blob',
                'sha'  => 'blob123'
            }
        };

        Test.startTest();
        Map<String, Object> result = GitHubApiService.createTree(
            'Intapp-BizApps', 'Salesforce-gearset', 'basetree123', treeItems
        );
        Test.stopTest();

        System.assertEquals('tree123', (String) result.get('sha'));
    }

    @IsTest
    static void testCreateCommit() {
        String mockResponse = '{"sha":"commit123","message":"test commit"}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(201, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.createCommit(
            'Intapp-BizApps', 'Salesforce-gearset', 'test commit', 'tree123', 'parent123'
        );
        Test.stopTest();

        System.assertEquals('commit123', (String) result.get('sha'));
    }

    @IsTest
    static void testUpdateReference() {
        String mockResponse = '{"ref":"refs/heads/sku-app/test","object":{"sha":"newcommit123"}}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(200, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.updateReference(
            'Intapp-BizApps', 'Salesforce-gearset', 'sku-app/test', 'newcommit123'
        );
        Test.stopTest();

        System.assertEquals('refs/heads/sku-app/test', (String) result.get('ref'));
    }

    @IsTest
    static void testGetCommit() {
        String mockResponse = '{"sha":"commit123","tree":{"sha":"tree123"},"message":"test"}';
        Test.setMock(HttpCalloutMock.class, new GitHubMock(200, mockResponse));

        Test.startTest();
        Map<String, Object> result = GitHubApiService.getCommit(
            'Intapp-BizApps', 'Salesforce-gearset', 'commit123'
        );
        Test.stopTest();

        System.assertEquals('commit123', (String) result.get('sha'));
    }

    @IsTest
    static void testApiErrorThrowsException() {
        Test.setMock(HttpCalloutMock.class, new GitHubMock(403, '{"message":"Bad credentials"}'));

        Test.startTest();
        try {
            GitHubApiService.getReference('Intapp-BizApps', 'Salesforce-gearset', 'heads/staging');
            System.assert(false, 'Should have thrown GitHubApiException');
        } catch (GitHubApiService.GitHubApiException e) {
            System.assert(e.getMessage().contains('Bad credentials'), 'Error message should contain API error');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateOrUpdateFileErrorThrowsException() {
        Test.setMock(HttpCalloutMock.class, new GitHubMock(409, '{"message":"Conflict"}'));

        String content = EncodingUtil.base64Encode(Blob.valueOf('{"test":"value"}'));

        Test.startTest();
        try {
            GitHubApiService.createOrUpdateFile(
                'Intapp-BizApps', 'Salesforce-gearset',
                'test.json', content, 'test', 'branch', null
            );
            System.assert(false, 'Should have thrown GitHubApiException');
        } catch (GitHubApiService.GitHubApiException e) {
            System.assert(e.getMessage().contains('Conflict'));
        }
        Test.stopTest();
    }
}