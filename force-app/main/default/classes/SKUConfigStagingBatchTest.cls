/**
 * @description Test class for SKUConfigStagingBatch.
 *              Validates batch processing of staged config data changes into GitHub PRs.
 *              Uses TestFactory for record creation and HttpCalloutMock for GitHub API simulation.
 *
 * @author      BIZ-80418
 * @date        2026-03-10
 * @jira        BIZ-80418
 */
@IsTest
private class SKUConfigStagingBatchTest {

    // ─── HTTP Mocks ──────────────────────────────────────────────────────

    /**
     * @description Mock that simulates a successful GitHub PR creation workflow.
     */
    private class GitHubSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/git/ref/heads/')) {
                res.setStatusCode(200);
                res.setBody('{"ref":"refs/heads/staging","object":{"sha":"base-sha-123","type":"commit"}}');
            } else if (method == 'POST' && endpoint.contains('/git/refs')) {
                res.setStatusCode(201);
                res.setBody('{"ref":"refs/heads/sku-app/test","object":{"sha":"base-sha-123"}}');
            } else if (method == 'GET' && endpoint.contains('/git/commits/')) {
                res.setStatusCode(200);
                res.setBody('{"sha":"base-sha-123","tree":{"sha":"base-tree-456"},"message":"prev"}');
            } else if (method == 'POST' && endpoint.contains('/git/blobs')) {
                res.setStatusCode(201);
                res.setBody('{"sha":"blob-sha-789"}');
            } else if (method == 'GET' && endpoint.contains('/git/trees/')) {
                res.setStatusCode(200);
                res.setBody('{"sha":"base-tree-456","tree":[]}');
            } else if (method == 'POST' && endpoint.contains('/git/trees')) {
                res.setStatusCode(201);
                res.setBody('{"sha":"new-tree-101"}');
            } else if (method == 'POST' && endpoint.contains('/git/commits')) {
                res.setStatusCode(201);
                res.setBody('{"sha":"new-commit-202"}');
            } else if (method == 'PATCH' && endpoint.contains('/git/refs/heads/')) {
                res.setStatusCode(200);
                res.setBody('{"ref":"refs/heads/sku-app/test","object":{"sha":"new-commit-202"}}');
            } else if (method == 'POST' && endpoint.contains('/pulls')) {
                res.setStatusCode(201);
                res.setBody('{"number":100,"html_url":"https://github.com/Intapp-BizApps/Salesforce-gearset/pull/100","state":"open"}');
            } else if (method == 'GET' && endpoint.contains('/contents/')) {
                res.setStatusCode(404);
                res.setBody('{"message":"Not Found"}');
            } else {
                res.setStatusCode(200);
                res.setBody('{}');
            }

            return res;
        }
    }

    /**
     * @description Mock that simulates a GitHub API failure during branch creation.
     */
    private class GitHubFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            String method = req.getMethod();

            if (method == 'GET' && endpoint.contains('/git/ref/heads/')) {
                res.setStatusCode(200);
                res.setBody('{"ref":"refs/heads/staging","object":{"sha":"base-sha","type":"commit"}}');
            } else if (method == 'POST' && endpoint.contains('/git/refs')) {
                res.setStatusCode(422);
                res.setBody('{"message":"Reference already exists"}');
            } else {
                res.setStatusCode(200);
                res.setBody('{}');
            }

            return res;
        }
    }

    // ─── Test Data Setup ─────────────────────────────────────────────────

    /**
     * @description Creates a parent staging record with the given status and session ID.
     */
    private static SKU_Config_Staging__c createParent(String sessionId, String status) {
        return createParent(sessionId, status, null);
    }

    private static SKU_Config_Staging__c createParent(String sessionId, String status, String finalizedBy) {
        SKU_Config_Staging__c staging = new SKU_Config_Staging__c(
            Session_Id__c = sessionId,
            Status__c = status
        );
        if (finalizedBy != null) {
            staging.Finalized_By__c = finalizedBy;
        }
        SKU_Config_Staging__c parent = (SKU_Config_Staging__c) TestFactory.createSObject(staging);
        return parent;
    }

    /**
     * @description Creates a child staging entry linked to the given parent.
     */
    private static SKU_Config_Staging_Entry__c createEntry(
        Id parentId, String objectApiName, String recordName,
        String gearsetExtId, String content, String operationType
    ) {
        SKU_Config_Staging_Entry__c entry = (SKU_Config_Staging_Entry__c) TestFactory.createSObject(
            new SKU_Config_Staging_Entry__c(
                Staging__c = parentId,
                Object_API_Name__c = objectApiName,
                Record_Name__c = recordName,
                Gearset_External_Id__c = gearsetExtId,
                JSON_Content__c = content,
                Operation_Type__c = operationType
            )
        );
        return entry;
    }

    // ─── Test Methods ────────────────────────────────────────────────────

    /**
     * @description Happy path — Pending parent with entries → Committed + PR URL populated.
     */
    @IsTest
    static void testBatchProcessesPendingSession() {
        SKU_Config_Staging__c parent = createParent('sess-001', 'Pending', SKUConfigStagingBatch.FINALIZED_BY_USER);

        createEntry(parent.Id, 'Product2', 'BL-02114 - Intapp Assist',
            '0AIQYcB800000mVt10', '{"Object":"Product2","Fields":{"ProductCode":"BL-02114"}}', 'Update');

        Test.setMock(HttpCalloutMock.class, new GitHubSuccessMock());

        Test.startTest();
        Database.executeBatch(new SKUConfigStagingBatch(), 1);
        Test.stopTest();

        SKU_Config_Staging__c result = [
            SELECT Status__c, PR_URL__c, PR_Number__c, Branch_Name__c, Error_Message__c
            FROM SKU_Config_Staging__c
            WHERE Id = :parent.Id
        ];

        System.assertEquals('Committed', result.Status__c, 'Status should be Committed');
        System.assert(result.PR_URL__c != null, 'PR URL should be populated');
        System.assertEquals(100, result.PR_Number__c, 'PR Number should be 100');
        System.assert(result.Branch_Name__c != null, 'Branch Name should be populated');
    }

    /**
     * @description Entries across multiple objects — Product2, Block_Pricing__c, PricebookEntry.
     */
    @IsTest
    static void testBatchProcessesMultipleObjects() {
        SKU_Config_Staging__c parent = createParent('sess-002', 'Pending', SKUConfigStagingBatch.FINALIZED_BY_USER);

        createEntry(parent.Id, 'Product2', 'BL-02114 - Intapp Assist',
            '0AIQYcB800000mVt10', '{"Object":"Product2","Fields":{"ProductCode":"BL-02114"}}', 'Update');
        createEntry(parent.Id, 'Block_Pricing__c', 'BP-00001',
            'GA20jEC200000ZVF1a', '{"Object":"Block_Pricing__c","Fields":{"Price__c":"100"}}', 'Update');
        createEntry(parent.Id, 'PricebookEntry', 'PBE-Standard-BL02114',
            'XY30kFD300000ABC2b', '{"Object":"PricebookEntry","Fields":{"UnitPrice":"50.00"}}', 'Create');

        Test.setMock(HttpCalloutMock.class, new GitHubSuccessMock());

        Test.startTest();
        Database.executeBatch(new SKUConfigStagingBatch(), 1);
        Test.stopTest();

        SKU_Config_Staging__c result = [
            SELECT Status__c, PR_URL__c
            FROM SKU_Config_Staging__c
            WHERE Id = :parent.Id
        ];

        System.assertEquals('Committed', result.Status__c, 'Multi-object session should be Committed');
        System.assert(result.PR_URL__c != null, 'PR URL should be populated for multi-object PR');
    }

    /**
     * @description Open session auto-finalized by batch → Pending → processed.
     */
    @IsTest
    static void testBatchCatchesOpenSession() {
        SKU_Config_Staging__c parent = createParent('sess-003', 'Open');

        createEntry(parent.Id, 'Product2', 'New SKU Product',
            'ABC123DEF456', '{"Object":"Product2","Fields":{"Name":"New SKU"}}', 'Create');

        Test.setMock(HttpCalloutMock.class, new GitHubSuccessMock());

        Test.startTest();
        Database.executeBatch(new SKUConfigStagingBatch(), 1);
        Test.stopTest();

        SKU_Config_Staging__c result = [
            SELECT Status__c, Finalized_By__c, PR_URL__c
            FROM SKU_Config_Staging__c
            WHERE Id = :parent.Id
        ];

        System.assertEquals('Committed', result.Status__c, 'Open session should be auto-finalized and committed');
        System.assertEquals('Scheduled Batch', result.Finalized_By__c, 'Should be finalized by batch');
        System.assert(result.PR_URL__c != null, 'PR URL should be populated');
    }

    /**
     * @description GitHub API error → Status = Failed + Error_Message populated.
     */
    @IsTest
    static void testBatchHandlesApiFailure() {
        SKU_Config_Staging__c parent = createParent('sess-004', 'Pending', SKUConfigStagingBatch.FINALIZED_BY_USER);

        createEntry(parent.Id, 'Product2', 'Failing Product',
            'FAIL123', '{"Object":"Product2","Fields":{"Name":"Fail"}}', 'Update');

        Test.setMock(HttpCalloutMock.class, new GitHubFailureMock());

        Test.startTest();
        Database.executeBatch(new SKUConfigStagingBatch(), 1);
        Test.stopTest();

        SKU_Config_Staging__c result = [
            SELECT Status__c, Error_Message__c, PR_URL__c
            FROM SKU_Config_Staging__c
            WHERE Id = :parent.Id
        ];

        System.assertEquals('Failed', result.Status__c, 'Status should be Failed on API error');
        System.assert(result.Error_Message__c != null, 'Error message should be populated');
        System.assertEquals(null, result.PR_URL__c, 'PR URL should be null on failure');
    }

    /**
     * @description Pending parent with no entries → Committed (no-op) with skip message.
     */
    @IsTest
    static void testBatchSkipsEmptySession() {
        SKU_Config_Staging__c parent = createParent('sess-005', 'Pending', SKUConfigStagingBatch.FINALIZED_BY_USER);

        // No entries created for this parent

        Test.startTest();
        Database.executeBatch(new SKUConfigStagingBatch(), 1);
        Test.stopTest();

        SKU_Config_Staging__c result = [
            SELECT Status__c, Error_Message__c, PR_URL__c
            FROM SKU_Config_Staging__c
            WHERE Id = :parent.Id
        ];

        System.assertEquals('Committed', result.Status__c, 'Empty session should be Committed (no-op)');
        System.assert(result.Error_Message__c.contains('No staging entries found'), 'Should have skip message');
        System.assertEquals(null, result.PR_URL__c, 'No PR URL for empty session');
    }

    /**
     * @description Schedulable interface invokes the batch correctly.
     */
    @IsTest
    static void testSchedulableExecution() {
        Test.startTest();
        String jobId = System.schedule(
            'Test SKU Config Staging Batch',
            '0 0 18 * * ?',
            new SKUConfigStagingBatch()
        );
        Test.stopTest();

        CronTrigger ct = [
            SELECT Id, CronExpression, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals('0 0 18 * * ?', ct.CronExpression, 'Cron expression should match');
    }

    /**
     * @description Verifies correct file path construction from entry fields.
     */
    @IsTest
    static void testFilePathDerivation() {
        SKU_Config_Staging_Entry__c entry = new SKU_Config_Staging_Entry__c(
            Object_API_Name__c = 'Product2',
            Record_Name__c = 'BL-02114 - Intapp Assist',
            Gearset_External_Id__c = '0AIQYcB800000mVt10'
        );

        Test.startTest();
        String filePath = SKUConfigStagingBatch.deriveFilePath(entry);
        Test.stopTest();

        System.assertEquals(
            'configdata/Product2/BL-02114 - Intapp Assist_[0AIQYcB800000mVt10].gs.json',
            filePath,
            'File path should match expected format'
        );
    }

    /**
     * @description Verifies file path sanitization removes special characters.
     */
    @IsTest
    static void testFilePathSanitization() {
        SKU_Config_Staging_Entry__c entry = new SKU_Config_Staging_Entry__c(
            Object_API_Name__c = 'Block_Pricing__c',
            Record_Name__c = 'Test/Record:With<Special>Chars',
            Gearset_External_Id__c = 'EXT001'
        );

        Test.startTest();
        String filePath = SKUConfigStagingBatch.deriveFilePath(entry);
        Test.stopTest();

        System.assert(!filePath.contains('/Record'), 'Special chars should be sanitized');
        System.assert(filePath.startsWith('configdata/Block_Pricing__c/'), 'Object path should be preserved');
        System.assert(filePath.endsWith('_[EXT001].gs.json'), 'External ID and extension should be intact');
    }

    /**
     * @description Verifies auto-generated PR title format.
     */
    @IsTest
    static void testPRTitleAndDescription() {
        SKU_Config_Staging__c parent = createParent('sess-006', 'Pending', SKUConfigStagingBatch.FINALIZED_BY_USER);

        // Re-query to get CreatedBy populated
        parent = [
            SELECT Id, Session_Id__c, Status__c, Finalized_By__c,
                   CreatedBy.Name, CreatedDate
            FROM SKU_Config_Staging__c
            WHERE Id = :parent.Id
        ];

        Test.startTest();
        String title = SKUConfigStagingBatch.buildPRTitle(parent);
        Test.stopTest();

        System.assert(title.startsWith('SKU Config Update'), 'Title should start with SKU Config Update');
        System.assert(title.contains('—'), 'Title should contain em dash separator');
    }

    /**
     * @description Verifies PR description includes object summary and file list.
     */
    @IsTest
    static void testPRDescriptionContent() {
        SKU_Config_Staging__c parent = createParent('sess-007', 'Pending', SKUConfigStagingBatch.FINALIZED_BY_BATCH);

        parent = [
            SELECT Id, Session_Id__c, Status__c, Finalized_By__c,
                   CreatedBy.Name, CreatedDate
            FROM SKU_Config_Staging__c
            WHERE Id = :parent.Id
        ];

        List<SKU_Config_Staging_Entry__c> entries = new List<SKU_Config_Staging_Entry__c>();
        entries.add(new SKU_Config_Staging_Entry__c(
            Staging__c = parent.Id,
            Object_API_Name__c = 'Product2',
            Record_Name__c = 'Test Product',
            Gearset_External_Id__c = 'EXT001',
            JSON_Content__c = '{}',
            Operation_Type__c = 'Update'
        ));

        Test.startTest();
        String prBody = SKUConfigStagingBatch.buildPRDescription(parent, entries);
        Test.stopTest();

        System.assert(prBody.contains('## Config Data Changes'), 'Description should have header');
        System.assert(prBody.contains('sess-007'), 'Description should contain session ID');
        System.assert(prBody.contains('Product2'), 'Description should list objects');
        System.assert(prBody.contains('configdata/Product2/'), 'Description should list file paths');
        System.assert(prBody.contains('Scheduled Batch'), 'Description should show finalized by');
    }
}