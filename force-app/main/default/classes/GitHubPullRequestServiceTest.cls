/**
 * @description Test class for GitHubPullRequestService.
 *              Simulates the full PR creation workflow using mocked GitHub API responses.
 * @author      BIZ-80418
 * @date        2026-03-05
 */

@IsTest
private class GitHubPullRequestServiceTest {

    // ────── Multi-step Mock ─────────────────────────────────────────────────

    /**
     * @description Mock that returns appropriate responses based on the endpoint
     *              being called, simulating the full Git Data API workflow.
     */
    private class GitHubPRWorkflowMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String method = req.getMethod();

            // GET /repos/.../git/ref/heads/staging - Get target branch reference
            if (method == 'GET' && endpoint.contains('/git/ref/heads/')) {
                res.setStatusCode(200);
                res.setBody('{"ref":"refs/heads/staging","object":{"sha":"base-commit-sha-123","type":"commit"}}');
            }
            // POST /repos/.../git/refs - Create branch
            else if (method == 'POST' && endpoint.contains('/git/refs')) {
                res.setStatusCode(201);
                res.setBody('{"ref":"refs/heads/sku-app/test-branch","object":{"sha":"base-commit-sha-123"}}');
            }
            // GET /repos/.../git/commits/... - Get commit details
            else if (method == 'GET' && endpoint.contains('/git/commits/')) {
                res.setStatusCode(200);
                res.setBody('{"sha":"base-commit-sha-123","tree":{"sha":"base-tree-sha-456"},"message":"previous commit"}');
            }
            // POST /repos/.../git/blobs - Create blob
            else if (method == 'POST' && endpoint.contains('/git/blobs')) {
                res.setStatusCode(201);
                res.setBody('{"sha":"new-blob-sha-789","url":"https://api.github.com/repos/test/git/blobs/new-blob-sha-789"}');
            }
            // GET /repos/.../git/trees/... - Get tree (listDirectoryViaTree path walk)
            else if (method == 'GET' && endpoint.contains('/git/trees/')) {
                res.setStatusCode(200);
                res.setBody('{"sha":"base-tree-sha-456","tree":[]}');
            }
            // POST /repos/.../git/trees - Create tree
            else if (method == 'POST' && endpoint.contains('/git/trees')) {
                res.setStatusCode(201);
                res.setBody('{"sha":"new-tree-sha-101","url":"https://api.github.com/repos/test/git/trees/new-tree-sha-101"}');
            }
            // POST /repos/.../git/commits - Create commit
            else if (method == 'POST' && endpoint.contains('/git/commits')) {
                res.setStatusCode(201);
                res.setBody('{"sha":"new-commit-sha-202","message":"Config Update: Test Product"}');
            }
            // PATCH /repos/.../git/refs/heads/... - Update reference
            else if (method == 'PATCH' && endpoint.contains('/git/refs/heads/')) {
                res.setStatusCode(200);
                res.setBody('{"ref":"refs/heads/sku-app/test-branch","object":{"sha":"new-commit-sha-202"}}');
            }
            // POST /repos/.../pulls - Create PR
            else if (method == 'POST' && endpoint.contains('/pulls')) {
                res.setStatusCode(201);
                res.setBody('{"number":99,"html_url":"https://github.com/Intapp-BizApps/Salesforce-gearset/pull/99","state":"open","title":"Config Update: Test Product"}');
            }
            // GET /repos/.../contents/... - Directory listing / file content (remapToExistingPaths / mergeWithExistingContent)
            else if (method == 'GET' && endpoint.contains('/contents/')) {
                res.setStatusCode(404);
                res.setBody('{"message":"Not Found"}');
            }
            // Default fallback
            else {
                res.setStatusCode(200);
                res.setBody('{}');
            }

            return res;
        }
    }

    /**
     * @description Mock that simulates a failure during branch creation
     */
    private class GitHubPRFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String method = req.getMethod();

            // GET ref succeeds
            if (method == 'GET' && endpoint.contains('/git/ref/heads/')) {
                res.setStatusCode(200);
                res.setBody('{"ref":"refs/heads/staging","object":{"sha":"base-sha","type":"commit"}}');
            }
            // Create branch fails (e.g., branch already exists)
            else if (method == 'POST' && endpoint.contains('/git/refs')) {
                res.setStatusCode(422);
                res.setBody('{"message":"Reference already exists"}');
            }
            else {
                res.setStatusCode(200);
                res.setBody('{}');
            }

            return res;
        }
    }

    // ────── Test Methods ────────────────────────────────────────────────────

    @IsTest
    static void testCreateConfigDataPR_Success() {
        Test.setMock(HttpCalloutMock.class, new GitHubPRWorkflowMock());

        List<GitHubPullRequestService.FileChange> changes = new List<GitHubPullRequestService.FileChange>{
            new GitHubPullRequestService.FileChange(
                'configdata/Product2/test-record.gs.json',
                '{"Object":"Product2","Fields":{"ProductCode":"TEST-001","Name":"Test Product"}}',
                'update'
            )
        };

        Test.startTest();
        GitHubPullRequestService.PullRequestResult result =
            GitHubPullRequestService.createConfigDataPR(changes, 'Config Update: Test Product', 'Auto-generated test PR');
        Test.stopTest();

        System.assertEquals(true, result.success, 'PR creation should succeed');
        System.assertEquals(99, result.prNumber, 'PR number should be 99');
        System.assert(result.prUrl.contains('/pull/99'), 'PR URL should contain PR number');
        System.assert(result.branchName.startsWith('sku-app/'), 'Branch should start with sku-app/');
        System.assertEquals(null, result.errorMessage, 'No error message expected');
    }

    @IsTest
    static void testCreateConfigDataPR_MultipleFiles() {
        Test.setMock(HttpCalloutMock.class, new GitHubPRWorkflowMock());

        List<GitHubPullRequestService.FileChange> changes = new List<GitHubPullRequestService.FileChange>{
            new GitHubPullRequestService.FileChange(
                'configdata/Product2/product-001.gs.json',
                '{"Object":"Product2","Fields":{"ProductCode":"PROD-001"}}',
                'update'
            ),
            new GitHubPullRequestService.FileChange(
                'configdata/Item_Master_Product__c/item-001.gs.json',
                '{"Object":"Item_Master_Product__c","Fields":{"Name":"PIN-00100"}}',
                'update'
            ),
            new GitHubPullRequestService.FileChange(
                'configdata/PricebookEntry/pbe-001.gs.json',
                '{"Object":"PricebookEntry","Fields":{"UnitPrice":"100.00"}}',
                'create'
            )
        };

        Test.startTest();
        GitHubPullRequestService.PullRequestResult result =
            GitHubPullRequestService.createConfigDataPR(changes, 'Bulk Config Update', 'Multiple product changes');
        Test.stopTest();

        System.assertEquals(true, result.success, 'Multi-file PR should succeed');
        System.assertEquals(99, result.prNumber);
    }

    @IsTest
    static void testCreateConfigDataPR_EmptyChanges() {
        Test.startTest();
        GitHubPullRequestService.PullRequestResult result =
            GitHubPullRequestService.createConfigDataPR(
                new List<GitHubPullRequestService.FileChange>(), 'Empty PR', 'No changes'
            );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with empty changes');
        System.assertEquals('No file changes provided.', result.errorMessage);
    }

    @IsTest
    static void testCreateConfigDataPR_NullChanges() {
        Test.startTest();
        GitHubPullRequestService.PullRequestResult result =
            GitHubPullRequestService.createConfigDataPR(null, 'Null PR', 'No changes');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with null changes');
        System.assertEquals('No file changes provided.', result.errorMessage);
    }

    @IsTest
    static void testCreateConfigDataPR_ApiFailure() {
        Test.setMock(HttpCalloutMock.class, new GitHubPRFailureMock());

        List<GitHubPullRequestService.FileChange> changes = new List<GitHubPullRequestService.FileChange>{
            new GitHubPullRequestService.FileChange(
                'configdata/Product2/test.gs.json', '{"test":"data"}', 'update'
            )
        };

        Test.startTest();
        GitHubPullRequestService.PullRequestResult result =
            GitHubPullRequestService.createConfigDataPR(changes, 'Failing PR', 'Should fail');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail on API error');
        System.assert(result.errorMessage.contains('GitHub API error'), 'Error should mention GitHub API');
    }

    @IsTest
    static void testCreateSingleFilePR() {
        Test.setMock(HttpCalloutMock.class, new GitHubPRWorkflowMock());

        String jsonContent = '{"Object":"Product2","Fields":{"ProductCode":"BL-01879","Name":"Intapp Billstream"}}';

        Test.startTest();
        GitHubPullRequestService.PullRequestResult result =
            GitHubPullRequestService.createSingleFilePR(
                'configdata/Product2/bl-01879.gs.json', jsonContent, 'Intapp Billstream (BL-01879)'
            );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Single file PR should succeed');
        System.assertEquals(99, result.prNumber);
    }

    @IsTest
    static void testGenerateBranchName() {
        Test.startTest();
        String branchName = GitHubPullRequestService.generateBranchName('Config Update: Test Product (BL-01879)');
        Test.stopTest();

        System.assert(branchName.startsWith('sku-app/'), 'Should start with sku-app/');
        System.assert(!branchName.contains(' '), 'Should not contain spaces');
        System.assert(!branchName.contains(':'), 'Should not contain colons');
        System.assert(!branchName.contains('('), 'Should not contain parentheses');
    }

    @IsTest
    static void testFileChangeConstructor() {
        GitHubPullRequestService.FileChange fc = new GitHubPullRequestService.FileChange(
            'configdata/Product2/test.gs.json', '{"test":"data"}', 'update'
        );

        System.assertEquals('configdata/Product2/test.gs.json', fc.filePath);
        System.assertEquals('{"test":"data"}', fc.content);
        System.assertEquals('update', fc.changeType);
    }

    @IsTest
    static void testPullRequestResult() {
        GitHubPullRequestService.PullRequestResult result = new GitHubPullRequestService.PullRequestResult();

        System.assertEquals(false, result.success, 'Default should be false');
        System.assertEquals(null, result.prUrl);
        System.assertEquals(null, result.prNumber);
        System.assertEquals(null, result.branchName);
        System.assertEquals(null, result.errorMessage);
    }

    // ────── extractExternalId Unit Tests ─────────────────────────────────────

    @IsTest
    static void testExtractExternalId_ValidPath() {
        String path = 'configdata/Product2/BL-02114 - Intapp Assist_[0AIQYcB800000mVt10].gs.json';

        Test.startTest();
        String extId = GitHubPullRequestService.extractExternalId(path);
        Test.stopTest();

        System.assertEquals('0AIQYcB800000mVt10', extId, 'Should extract external ID from path');
    }

    @IsTest
    static void testExtractExternalId_NoMatch() {
        String path = 'configdata/Product2/some-file-without-id.gs.json';

        Test.startTest();
        String extId = GitHubPullRequestService.extractExternalId(path);
        Test.stopTest();

        System.assertEquals(null, extId, 'Should return null for path without external ID');
    }

    @IsTest
    static void testExtractExternalId_SpecialCharsInName() {
        String path = 'configdata/Block_Pricing__c/Intapp Relationships - UNBANDED_[GA20jEC200000ZVF1a].gs.json';

        Test.startTest();
        String extId = GitHubPullRequestService.extractExternalId(path);
        Test.stopTest();

        System.assertEquals('GA20jEC200000ZVF1a', extId, 'Should extract ID even with spaces and hyphens in name');
    }

    // ────── mergeGearsetJson Unit Tests ──────────────────────────────────────

    @IsTest
    static void testMergeGearsetJson_UpdatesExistingFields() {
        String existingJson =
            '{\n' +
            '  "Object": "Product2",\n' +
            '  "Fields": {\n' +
            '    "ProductCode": "BL-02114",\n' +
            '    "Name": "Old Name",\n' +
            '    "Description": "Old Description",\n' +
            '    "IsActive": "true"\n' +
            '  }\n' +
            '}';

        String ourJson =
            '{"Object":"Product2","Fields":{"Name":"New Name","Description":"New Description"}}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        System.assert(result.contains('"Name": "New Name"'), 'Name should be updated');
        System.assert(result.contains('"Description": "New Description"'), 'Description should be updated');
        System.assert(result.contains('"ProductCode": "BL-02114"'), 'Unchanged fields should be preserved');
        System.assert(result.contains('"IsActive": "true"'), 'Boolean field should be preserved');
    }
    

    @IsTest
    static void testMergeGearsetJson_SkipsGearsetDisplayName() {
        String existingJson =
            '{\n' +
            '  "Object": "Product2",\n' +
            '  "Fields": {\n' +
            '    "GearsetDisplayName": "Old Display Name",\n' +
            '    "Name": "Old Name"\n' +
            '  }\n' +
            '}';

        String ourJson =
            '{"Object":"Product2","Fields":{"GearsetDisplayName":"New Display","Name":"New Name"}}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        System.assert(result.contains('"GearsetDisplayName": "Old Display Name"'),
            'GearsetDisplayName should NOT be updated — Gearset manages this field');
        System.assert(result.contains('"Name": "New Name"'), 'Name should be updated');
    }

    @IsTest
    static void testMergeGearsetJson_FixesEmptyBooleans() {
        String existingJson =
            '{\n' +
            '  "Object": "Product2",\n' +
            '  "Fields": {\n' +
            '    "IsActive": "",\n' +
            '    "Name": "Test"\n' +
            '  }\n' +
            '}';

        String ourJson = '{"Object":"Product2","Fields":{"Name":"Test"}}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        System.assert(result.contains('"IsActive": "false"'),
            'Empty boolean should be defaulted to "false"');
    }

    @IsTest
    static void testMergeGearsetJson_NullOurFields() {
        String existingJson =
            '{\n' +
            '  "Object": "Product2",\n' +
            '  "Fields": {\n' +
            '    "Name": "Test"\n' +
            '  }\n' +
            '}';

        String ourJson = '{"Object":"Product2"}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        System.assertEquals(existingJson, result, 'Should return existing JSON unchanged when our Fields is null');
    }

    @IsTest
    static void testMergeGearsetJson_UpdatesReferences() {
        String existingJson =
            '{\n' +
            '  "Object": "PricebookEntry",\n' +
            '  "Fields": {\n' +
            '    "UnitPrice": "100.00"\n' +
            '  },\n' +
            '  "References": [\n' +
            '    {\n' +
            '      "Name": "Pricebook2Id",\n' +
            '      "ReferencedFields": {\n' +
            '        "GearsetExternalId__c": "OLD-EXT-ID-123"\n' +
            '      }\n' +
            '    }\n' +
            '  ]\n' +
            '}';

        String ourJson =
            '{"Object":"PricebookEntry","Fields":{"UnitPrice":"200.00"},"References":[{"Name":"Pricebook2Id","ReferencedFields":{"GearsetExternalId__c":"NEW-EXT-ID-456"}}]}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        System.assert(result.contains('"UnitPrice": "200.00"'), 'UnitPrice should be updated');
        System.assert(result.contains('"GearsetExternalId__c": "NEW-EXT-ID-456"'),
            'Reference GearsetExternalId should be updated');
        System.assert(!result.contains('OLD-EXT-ID-123'), 'Old reference ID should be replaced');
    }

    @IsTest
    static void testMergeGearsetJson_PreservesFormatting() {
        String existingJson =
            '{\n' +
            '  "Object": "Product2",\n' +
            '  "Fields": {\n' +
            '    "ProductCode": "BL-02114",\n' +
            '    "Name": "Old"\n' +
            '  }\n' +
            '}';

        String ourJson = '{"Object":"Product2","Fields":{"Name":"New"}}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        // Verify indentation is preserved (2-space indent for fields)
        System.assert(result.contains('    "Name": "New"'),
            'Should preserve 4-space indentation for field values');
        System.assert(result.contains('    "ProductCode": "BL-02114"'),
            'Unchanged field should keep original indent');
    }

    @IsTest
    static void testMergeGearsetJson_EscapesSpecialChars() {
        String existingJson =
            '{\n' +
            '  "Object": "Product2",\n' +
            '  "Fields": {\n' +
            '    "Description": "Old value"\n' +
            '  }\n' +
            '}';

        String ourJson = '{"Object":"Product2","Fields":{"Description":"Value with \\"quotes\\" and \\\\backslash"}}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        System.assert(result.contains('"Description"'), 'Description field should exist');
    }

    @IsTest
    static void testMergeGearsetJson_OnlyUpdatesExistingKeys() {
        String existingJson =
            '{\n' +
            '  "Object": "Product2",\n' +
            '  "Fields": {\n' +
            '    "Name": "Old"\n' +
            '  }\n' +
            '}';

        // Our JSON has a field not in the existing file
        String ourJson = '{"Object":"Product2","Fields":{"Name":"New","NewField__c":"ShouldNotAppear"}}';

        Test.startTest();
        String result = GitHubPullRequestService.mergeGearsetJson(existingJson, ourJson);
        Test.stopTest();

        System.assert(result.contains('"Name": "New"'), 'Existing field should be updated');
        System.assert(!result.contains('NewField__c'), 'New fields not in existing file should not be injected');
    }

    // ────── Branch Name Edge Cases ───────────────────────────────────────────

    @IsTest
    static void testGenerateBranchName_LongTitle() {
        String longTitle = 'SKU Config Update — John Smith with a really really really long name — 2026-03-17';

        Test.startTest();
        String branchName = GitHubPullRequestService.generateBranchName(longTitle);
        Test.stopTest();

        System.assert(branchName.startsWith('sku-app/'), 'Should start with sku-app/');
        // Total should be sku-app/ (8) + sanitized (max 40) + - + timestamp (15)
        System.assert(branchName.length() <= 80, 'Branch name should be reasonably sized');
    }
}