/**
 * @description Test class for SkuPublishController.
 *              Validates change set management operations for the Publish Changes feature.
 *
 * @author      Sahal Mohamed
 * @date        2026-03-10
 * @jira        BIZ-80418
 */
@IsTest
private class SkuPublishControllerTest {

    // ─── Test Setup ────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        SKU_Config_Staging__c session = (SKU_Config_Staging__c) TestFactory.createSObject(
            new SKU_Config_Staging__c(
                Session_Id__c = 'test-session-001',
                Status__c = 'Open'
            )
        );

        TestFactory.createSObject(
            new SKU_Config_Staging_Entry__c(
                Staging__c = session.Id,
                Object_API_Name__c = 'Product2',
                Record_Name__c = 'Test Product',
                Gearset_External_Id__c = 'ABC123',
                JSON_Content__c = '{"Object":"Product2","Fields":{"Name":"Test"}}',
                Operation_Type__c = 'Update'
            )
        );

        TestFactory.createSObject(
            new SKU_Config_Staging_Entry__c(
                Staging__c = session.Id,
                Object_API_Name__c = 'Block_Pricing__c',
                Record_Name__c = 'Test Pricing',
                Gearset_External_Id__c = 'DEF456',
                JSON_Content__c = '{"Object":"Block_Pricing__c","Fields":{"Price":"100"}}',
                Operation_Type__c = 'Create'
            )
        );
    }

    // ─── getChangeSets Tests ───────────────────────────────────────────

    @IsTest
    static void testGetChangeSets() {
        Test.startTest();
        List<SkuPublishController.ChangeSetSummary> results =
            SkuPublishController.getChangeSets();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one change set');
        System.assertEquals('Open', results[0].status, 'Status should be Open');
        System.assertEquals(2, results[0].entryCount, 'Should have 2 entries');
    }

    // ─── createChangeSet Tests ─────────────────────────────────────────

    @IsTest
    static void testCreateChangeSet() {
        Test.startTest();
        Id sessionId = SkuPublishController.createChangeSet();
        Test.stopTest();

        System.assertNotEquals(null, sessionId, 'Should return a session Id');

        SKU_Config_Staging__c session = [
            SELECT Id, Session_Id__c, Status__c
            FROM SKU_Config_Staging__c
            WHERE Id = :sessionId
        ];
        System.assertEquals('Open', session.Status__c, 'New session should be Open');
        System.assertNotEquals(null, session.Session_Id__c, 'Should have a session Id');
        System.assert(session.Session_Id__c.contains('-'), 'Session Id should be UUID format');
    }

    // ─── addChangeEntry Tests ──────────────────────────────────────────

    @IsTest
    static void testAddChangeEntry() {
        SKU_Config_Staging__c session = [
            SELECT Id FROM SKU_Config_Staging__c LIMIT 1
        ];

        Test.startTest();
        Id entryId = SkuPublishController.addChangeEntry(
            session.Id,
            'PricebookEntry',
            'PBE-Standard-Test',
            'GHI789',
            '{"Object":"PricebookEntry","Fields":{"UnitPrice":"50"}}',
            'Create'
        );
        Test.stopTest();

        System.assertNotEquals(null, entryId, 'Should return an entry Id');

        SKU_Config_Staging_Entry__c entry = [
            SELECT Object_API_Name__c, Record_Name__c, Operation_Type__c
            FROM SKU_Config_Staging_Entry__c
            WHERE Id = :entryId
        ];
        System.assertEquals('PricebookEntry', entry.Object_API_Name__c);
        System.assertEquals('PBE-Standard-Test', entry.Record_Name__c);
        System.assertEquals('Create', entry.Operation_Type__c);
    }

    @IsTest
    static void testAddChangeEntryToNonOpenSession() {
        SKU_Config_Staging__c session = [
            SELECT Id FROM SKU_Config_Staging__c LIMIT 1
        ];
        session.Status__c = 'Committed';
        update session;

        Test.startTest();
        try {
            SkuPublishController.addChangeEntry(
                session.Id, 'Product2', 'Test', 'X1', '{}', 'Update'
            );
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('Cannot add entries'),
                'Error should mention cannot add entries'
            );
        }
        Test.stopTest();
    }

    // ─── getChangeSetDetail Tests ──────────────────────────────────────

    @IsTest
    static void testGetChangeSetDetail() {
        SKU_Config_Staging__c session = [
            SELECT Id FROM SKU_Config_Staging__c LIMIT 1
        ];

        Test.startTest();
        SkuPublishController.ChangeSetDetail detail =
            SkuPublishController.getChangeSetDetail(session.Id);
        Test.stopTest();

        System.assertEquals(session.Id, detail.recordId, 'Record Id should match');
        System.assertEquals('Open', detail.status, 'Status should be Open');
        System.assertEquals(2, detail.entries.size(), 'Should have 2 entries');

        // Verify entries are ordered by object name
        System.assertEquals('Block_Pricing__c', detail.entries[0].objectApiName);
        System.assertEquals('Product2', detail.entries[1].objectApiName);
    }

    // ─── submitForReview Tests ─────────────────────────────────────────

    @IsTest
    static void testSubmitForReview() {
        SKU_Config_Staging__c session = [
            SELECT Id FROM SKU_Config_Staging__c LIMIT 1
        ];

        Test.startTest();
        String status = SkuPublishController.submitForReview(session.Id);
        Test.stopTest();

        System.assertEquals('Pending', status, 'Should return Pending status');

        SKU_Config_Staging__c updated = [
            SELECT Status__c, Finalized_By__c
            FROM SKU_Config_Staging__c
            WHERE Id = :session.Id
        ];
        System.assertEquals('Pending', updated.Status__c, 'DB status should be Pending');
        System.assertEquals('User', updated.Finalized_By__c, 'Finalized by should be User');
    }

    @IsTest
    static void testSubmitAlreadySubmittedSession() {
        SKU_Config_Staging__c session = [
            SELECT Id FROM SKU_Config_Staging__c LIMIT 1
        ];
        session.Status__c = 'Pending';
        update session;

        Test.startTest();
        try {
            SkuPublishController.submitForReview(session.Id);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('Only Draft change sets'),
                'Error should mention only Draft sets'
            );
        }
        Test.stopTest();
    }

    // ─── getChangeSetStatus Tests ──────────────────────────────────────

    @IsTest
    static void testGetChangeSetStatus() {
        SKU_Config_Staging__c session = [
            SELECT Id FROM SKU_Config_Staging__c LIMIT 1
        ];

        Test.startTest();
        SkuPublishController.ChangeSetSummary status =
            SkuPublishController.getChangeSetStatus(session.Id);
        Test.stopTest();

        System.assertEquals(session.Id, status.recordId, 'Record Id should match');
        System.assertEquals('Open', status.status, 'Status should be Open');
        System.assertEquals(2, status.entryCount, 'Should have 2 entries');
    }

    // ─── generateSessionId Tests ───────────────────────────────────────

    @IsTest
    static void testGenerateSessionIdFormat() {
        Test.startTest();
        String sessionId = SkuPublishController.generateSessionId();
        Test.stopTest();

        System.assertNotEquals(null, sessionId, 'Session Id should not be null');
        List<String> parts = sessionId.split('-');
        System.assertEquals(5, parts.size(), 'UUID should have 5 parts separated by dashes');
        System.assertEquals(8, parts[0].length(), 'First part should be 8 chars');
        System.assertEquals(4, parts[1].length(), 'Second part should be 4 chars');
    }

    @IsTest
    static void testGenerateSessionIdUniqueness() {
        Test.startTest();
        String id1 = SkuPublishController.generateSessionId();
        String id2 = SkuPublishController.generateSessionId();
        Test.stopTest();

        System.assertNotEquals(id1, id2, 'Generated IDs should be unique');
    }
}