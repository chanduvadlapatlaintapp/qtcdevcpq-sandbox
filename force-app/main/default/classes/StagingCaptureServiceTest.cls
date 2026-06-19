/**
 * @description Test class for StagingCaptureService.
 *              Validates automatic staging entry capture at DML points.
 *
 * @author      Sahal Mohamed
 * @date        2026-03-11
 * @jira        BIZ-80418
 */
@IsTest
private class StagingCaptureServiceTest {

    // ─── Test Setup ────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Create a Product2 to use in tests
        Product2 prod = (Product2) TestFactory.createSObject(
            new Product2(
                Name = 'Test Product Alpha',
                ProductCode = 'TP-ALPHA',
                IsActive = true,
                GearsetExternalId__c = 'EXT-PROD-001'
            )
        );
    }

    // ─── capture: Basic Create ─────────────────────────────────────────

    @IsTest
    static void testCaptureCreateSingleRecord() {
        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        Test.startTest();
        StagingCaptureService.capture(
            new List<Product2>{ prod },
            'Product2',
            'Create'
        );
        Test.stopTest();

        // Should have created an Open session
        List<SKU_Config_Staging__c> sessions = [
            SELECT Id, Status__c, Session_Id__c
            FROM SKU_Config_Staging__c
            WHERE CreatedById = :UserInfo.getUserId()
              AND Status__c = 'Open'
        ];
        System.assertEquals(1, sessions.size(), 'Should auto-create one session');
        System.assert(sessions[0].Session_Id__c.contains('-'), 'Session Id should be UUID format');

        // Should have one staging entry
        List<SKU_Config_Staging_Entry__c> entries = [
            SELECT Id, Object_API_Name__c, Record_Name__c,
                   Gearset_External_Id__c, Operation_Type__c, JSON_Content__c
            FROM SKU_Config_Staging_Entry__c
            WHERE Staging__c = :sessions[0].Id
        ];
        System.assertEquals(1, entries.size(), 'Should have one entry');
        System.assertEquals('Product2', entries[0].Object_API_Name__c);
        System.assertEquals('Test Product Alpha', entries[0].Record_Name__c);
        System.assertEquals('EXT-PROD-001', entries[0].Gearset_External_Id__c);
        System.assertEquals('Create', entries[0].Operation_Type__c);
        System.assert(entries[0].JSON_Content__c.contains('Test Product Alpha'), 'JSON should contain product name');
        System.assert(entries[0].JSON_Content__c.contains('"Object" : "Product2"'), 'JSON should have Object key');
        System.assert(entries[0].JSON_Content__c.contains('"Fields"'), 'JSON should have Fields key');
        System.assert(entries[0].JSON_Content__c.contains('"References"'), 'JSON should have References key');
    }

    // ─── capture: Session Reuse ────────────────────────────────────────

    @IsTest
    static void testCaptureReusesExistingSession() {
        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        Test.startTest();
        // First capture creates session
        StagingCaptureService.capture(
            new List<Product2>{ prod },
            'Product2',
            'Create'
        );

        // Reset static cache to simulate a new transaction
        StagingCaptureService.cachedSessionId = null;

        // Second capture should reuse the same session
        StagingCaptureService.capture(
            new List<Product2>{ prod },
            'Product2',
            'Update'
        );
        Test.stopTest();

        // Should still have only one session
        List<SKU_Config_Staging__c> sessions = [
            SELECT Id
            FROM SKU_Config_Staging__c
            WHERE CreatedById = :UserInfo.getUserId()
              AND Status__c = 'Open'
        ];
        System.assertEquals(1, sessions.size(), 'Should reuse existing session');
    }

    // ─── capture: Delete Before Insert ─────────────────────────────────

    @IsTest
    static void testCaptureReplacesStaleEntries() {
        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        Test.startTest();
        // First capture
        StagingCaptureService.capture(
            new List<Product2>{ prod },
            'Product2',
            'Create'
        );

        // Persist the rename so requeryRecords sees the latest state on the second capture
        prod.Name = 'Updated Product Alpha';
        update prod;
        StagingCaptureService.capture(
            new List<Product2>{ prod },
            'Product2',
            'Update'
        );
        Test.stopTest();

        // Should have only 1 entry (the latest), not 2
        List<SKU_Config_Staging_Entry__c> entries = [
            SELECT Id, Operation_Type__c, JSON_Content__c
            FROM SKU_Config_Staging_Entry__c
            WHERE Object_API_Name__c = 'Product2'
              AND Gearset_External_Id__c = 'EXT-PROD-001'
        ];
        System.assertEquals(1, entries.size(), 'Should replace stale entry');
        System.assertEquals('Update', entries[0].Operation_Type__c, 'Should be the latest operation');
        System.assert(entries[0].JSON_Content__c.contains('Updated Product Alpha'), 'Should have latest data');
    }

    // ─── captureDeletes ────────────────────────────────────────────────

    @IsTest
    static void testCaptureDeletes() {
        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        Test.startTest();
        StagingCaptureService.captureDeletes(
            new List<Product2>{ prod },
            'Product2'
        );
        Test.stopTest();

        List<SKU_Config_Staging_Entry__c> entries = [
            SELECT Id, Operation_Type__c
            FROM SKU_Config_Staging_Entry__c
            WHERE Gearset_External_Id__c = 'EXT-PROD-001'
        ];
        System.assertEquals(1, entries.size(), 'Should have one delete entry');
        System.assertEquals('Delete', entries[0].Operation_Type__c);
    }

    // ─── capture: Skip Records Without External Id ─────────────────────

    @IsTest
    static void testCaptureSkipsRecordsWithoutExternalId() {
        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];
        prod.GearsetExternalId__c = null;
        update prod;

        Test.startTest();
        StagingCaptureService.capture(
            new List<Product2>{ prod },
            'Product2',
            'Create'
        );
        Test.stopTest();

        List<SKU_Config_Staging_Entry__c> entries = [
            SELECT Id FROM SKU_Config_Staging_Entry__c
        ];
        System.assertEquals(0, entries.size(), 'Should skip records without external Id');
    }

    // ─── capture: Unknown Object (not in registry) ─────────────────────

    @IsTest
    static void testCaptureUnknownObjectSilentlyIgnored() {
        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        Test.startTest();
        StagingCaptureService.capture(
            new List<Product2>{ prod },
            'Unknown_Object__c',
            'Create'
        );
        Test.stopTest();

        List<SKU_Config_Staging_Entry__c> entries = [
            SELECT Id FROM SKU_Config_Staging_Entry__c
        ];
        System.assertEquals(0, entries.size(), 'Should not create entries for unknown objects');
    }

    // ─── capture: Empty / Null Lists ───────────────────────────────────

    @IsTest
    static void testCaptureEmptyListDoesNothing() {
        Test.startTest();
        StagingCaptureService.capture(new List<Product2>(), 'Product2', 'Create');
        StagingCaptureService.capture(null, 'Product2', 'Create');
        Test.stopTest();

        List<SKU_Config_Staging__c> sessions = [
            SELECT Id FROM SKU_Config_Staging__c
        ];
        System.assertEquals(0, sessions.size(), 'Should not create session for empty/null lists');
    }

    // ─── capture: Multiple Records ─────────────────────────────────────

    @IsTest
    static void testCaptureMultipleRecords() {
        Product2 prod1 = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        // Insert a second, distinct product so requeryRecords returns both rows
        Product2 prod2 = (Product2) TestFactory.createSObject(
            new Product2(
                Name = 'Product Beta',
                ProductCode = 'TP-BETA',
                IsActive = true,
                GearsetExternalId__c = 'EXT-PROD-002'
            )
        );

        Test.startTest();
        StagingCaptureService.capture(
            new List<Product2>{ prod1, prod2 },
            'Product2',
            'Create'
        );
        Test.stopTest();

        List<SKU_Config_Staging_Entry__c> entries = [
            SELECT Id, Gearset_External_Id__c
            FROM SKU_Config_Staging_Entry__c
            ORDER BY Gearset_External_Id__c
        ];
        System.assertEquals(2, entries.size(), 'Should have 2 entries');
    }

    // ─── serializeGearsetFormat ─────────────────────────────────────────

    @IsTest
    static void testSerializeGearsetFormat() {
        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        StagingCaptureService.ObjectConfig config = StagingCaptureService.OBJECT_REGISTRY.get('Product2');
        Map<Id, String> emptyLookups = new Map<Id, String>();

        Test.startTest();
        String jsonStr = StagingCaptureService.serializeGearsetFormat(
            prod, config, 'Product2', emptyLookups
        );
        Test.stopTest();

        // Verify Gearset .gs.json structure
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals('Product2', parsed.get('Object'), 'Should have Object key');
        System.assert(parsed.containsKey('Fields'), 'Should have Fields key');
        System.assert(parsed.containsKey('References'), 'Should have References key');

        // Verify Fields are strings
        Map<String, Object> fields = (Map<String, Object>) parsed.get('Fields');
        System.assertEquals('Test Product Alpha', fields.get('Name'));
        System.assertEquals('TP-ALPHA', fields.get('ProductCode'));
        System.assertEquals('true', fields.get('IsActive'), 'Boolean should be serialised as string');
        System.assert(fields.containsKey('GearsetDisplayName'), 'Should include GearsetDisplayName');
    }

    @IsTest
    static void testSerializeGearsetFormatWithReferences() {
        Product2 prod = [SELECT Id, Name, GearsetExternalId__c FROM Product2 LIMIT 1];

        // Simulate a Block_Pricing record with a lookup to the product
        Block_Pricing__c bp = (Block_Pricing__c) TestFactory.createSObject(
            new Block_Pricing__c(
                Product__c = prod.Id,
                GearsetExternalId__c = 'EXT-BP-001'
            )
        );
        bp = [SELECT Id, Name, Product__c, GearsetExternalId__c FROM Block_Pricing__c WHERE Id = :bp.Id];

        StagingCaptureService.ObjectConfig config = StagingCaptureService.OBJECT_REGISTRY.get('Block_Pricing__c');
        Map<Id, String> lookupMap = new Map<Id, String>{ prod.Id => 'EXT-PROD-001' };

        Test.startTest();
        String jsonStr = StagingCaptureService.serializeGearsetFormat(
            bp, config, 'Block_Pricing__c', lookupMap
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals('Block_Pricing__c', parsed.get('Object'));

        // Verify References array
        List<Object> refs = (List<Object>) parsed.get('References');
        System.assert(refs.size() >= 1, 'Should have at least one reference');

        // Find the Product__r reference
        Boolean foundProductRef = false;
        for (Object refObj : refs) {
            Map<String, Object> ref = (Map<String, Object>) refObj;
            if (ref.get('Name') == 'Product__r') {
                foundProductRef = true;
                System.assertEquals('Product2', ref.get('ReferencedObject'));
                Map<String, Object> refFields = (Map<String, Object>) ref.get('ReferencedFields');
                System.assertEquals('EXT-PROD-001', refFields.get('GearsetExternalId__c'),
                    'Should resolve lookup to external Id');
            }
        }
        System.assert(foundProductRef, 'Should have Product__r reference');
    }

    // ─── getOrCreateSession ────────────────────────────────────────────

    @IsTest
    static void testGetOrCreateSessionCreatesNewSession() {
        Test.startTest();
        Id sessionId = StagingCaptureService.getOrCreateSession();
        Test.stopTest();

        System.assertNotEquals(null, sessionId, 'Should return a session Id');

        SKU_Config_Staging__c session = [
            SELECT Id, Status__c, Session_Id__c
            FROM SKU_Config_Staging__c
            WHERE Id = :sessionId
        ];
        System.assertEquals('Open', session.Status__c);
        System.assertNotEquals(null, session.Session_Id__c);
    }

    @IsTest
    static void testGetOrCreateSessionReusesExisting() {
        // Pre-create an Open session
        SKU_Config_Staging__c existing = (SKU_Config_Staging__c) TestFactory.createSObject(
            new SKU_Config_Staging__c(
                Session_Id__c = 'existing-session-001',
                Status__c = 'Open'
            )
        );

        Test.startTest();
        Id sessionId = StagingCaptureService.getOrCreateSession();
        Test.stopTest();

        System.assertEquals(existing.Id, sessionId, 'Should reuse existing Open session');
    }

    @IsTest
    static void testGetOrCreateSessionIgnoresNonOpenSessions() {
        // Pre-create a Pending session (should be ignored)
        TestFactory.createSObject(
            new SKU_Config_Staging__c(
                Session_Id__c = 'pending-session-001',
                Status__c = 'Pending'
            )
        );

        Test.startTest();
        Id sessionId = StagingCaptureService.getOrCreateSession();
        Test.stopTest();

        // Should create a new session (not reuse the Pending one)
        SKU_Config_Staging__c newSession = [
            SELECT Id, Status__c
            FROM SKU_Config_Staging__c
            WHERE Id = :sessionId
        ];
        System.assertEquals('Open', newSession.Status__c, 'Should create a new Open session');
    }

    // ─── buildGearsetExternalId ────────────────────────────────────────

    @IsTest
    static void testBuildGearsetExternalId() {
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        Test.startTest();
        String extId = StagingCaptureService.buildGearsetExternalId(prod.Id);
        Test.stopTest();

        String plainId = String.valueOf(prod.Id);
        String expected = StagingCaptureService.reverseString(plainId);

        System.assertEquals(expected, extId, 'buildGearsetExternalId should return reversed SF Id');
        System.assertNotEquals(plainId, extId, 'Result should differ from plain Id');
        System.assertEquals(plainId.length(), extId.length(), 'Reversed Id should be same length');
    }

    // ─── reverseString ────────────────────────────────────────────────

    @IsTest
    static void testReverseString() {
        Test.startTest();
        System.assertEquals(
            'IAS4Tas000000J2dAa',
            StagingCaptureService.reverseString('aAd2J000000saT4SAI'),
            'Should reverse known Salesforce-style Id'
        );
        System.assertEquals('cba', StagingCaptureService.reverseString('abc'), 'Should reverse simple string');
        System.assertEquals('',   StagingCaptureService.reverseString(''),    'Empty string should stay empty');
        System.assertEquals(null, StagingCaptureService.reverseString(null),  'Null input should return null');
        Test.stopTest();
    }

    // ─── capture: Bypass Flag ─────────────────────────────────────────

    @IsTest
    static void testCaptureBypassFlagSkipsCapture() {
        // Enable bypass at user level
        Automation_Controls__c controls = new Automation_Controls__c(
            SetupOwnerId            = UserInfo.getUserId(),
            Active__c               = true,
            Bypass_Staging_Capture__c = true
        );
        upsert controls;

        Product2 prod = [SELECT Id, Name, ProductCode, IsActive, GearsetExternalId__c FROM Product2 LIMIT 1];

        Test.startTest();
        StagingCaptureService.capture(new List<Product2>{ prod }, 'Product2', 'Create');
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM SKU_Config_Staging_Entry__c],
            'Bypass flag should suppress all staging capture'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM SKU_Config_Staging__c],
            'No session should be created when bypassed'
        );
    }

    // ─── buildDisplayName: QuoteTerm composite ────────────────────────

    @IsTest
    static void testQuoteTermCompositeDisplayName() {
        SBQQ__QuoteTerm__c term = (SBQQ__QuoteTerm__c) TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__PrintOrder__c  = 10,
                SBQQ__Status__c      = 'Active',
                SBQQ__Active__c      = true,
                GearsetExternalId__c = 'EXT-QT-COMPOSITE-001'
            )
        );

        Test.startTest();
        StagingCaptureService.capture(
            new List<SBQQ__QuoteTerm__c>{ term },
            'SBQQ__QuoteTerm__c',
            'Create'
        );
        Test.stopTest();

        SKU_Config_Staging_Entry__c entry = [
            SELECT Record_Name__c
            FROM SKU_Config_Staging_Entry__c
            WHERE Gearset_External_Id__c = 'EXT-QT-COMPOSITE-001'
        ];
        System.assert(
            entry.Record_Name__c.contains(' - '),
            'QuoteTerm display name should use composite "PrintOrder - Status" format, got: ' + entry.Record_Name__c
        );
        System.assert(
            entry.Record_Name__c.contains('Active'),
            'QuoteTerm display name should include SBQQ__Status__c value'
        );
    }

    // ─── requeryRecords: empty Ids early return ────────────────────────

    @IsTest
    static void testRequeryRecordsEmptyIdsReturnsOriginal() {
        // A record with no Id (e.g. a failed partial-success insert)
        Product2 unsaved = new Product2(
            Name                 = 'Unsaved Product',
            GearsetExternalId__c = 'EXT-UNSAVED-001'
        );

        StagingCaptureService.ObjectConfig config = StagingCaptureService.OBJECT_REGISTRY.get('Product2');

        Test.startTest();
        List<SObject> result = StagingCaptureService.requeryRecords(
            new List<SObject>{ unsaved },
            'Product2',
            config
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return original list when no Ids present');
        System.assertEquals(
            'Unsaved Product',
            (String) result[0].get('Name'),
            'Returned record should be the original unsaved record'
        );
    }
}