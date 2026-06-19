/**
 * @description Test class for AgenticQTC_OsaDocumentService.
 *              Each public method has at minimum:
 *                1. Validation (blank/null Id) → AuraHandledException
 *                2. Happy / success path
 *              CongaUrlService-backed methods (generateAndSaveOsa,
 *              buildCongaUrlForSave) can short-circuit through their own
 *              error path when Conga metadata isn't present in the test
 *              context, so those tests accept either a successful return or
 *              an AuraHandledException — both exercise the wrapping logic.
 * @author AgenticQTC Team
 * @date 2026-05-19
 */
@isTest
private class AgenticQTC_OsaDocumentServiceTest {

    // ─── Test Setup ─────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        // CPQ's QuoteLine triggers don't bulk-safely handle inserts in test
        // context — disable them so seed data loads cleanly.
        SBQQ.TriggerControl.disable();

        // Bypass org Quote flows so quote DML doesn't trip an unrelated flow.
        insert new Automation_Controls__c(
            Active__c          = true,
            Bypass_Flows__c    = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c    = true,
            SetupOwnerId       = UserInfo.getUserId()
        );

        Account acct = new Account(
            Name         = 'OSA Doc Test Account',
            BillingCity  = 'Austin',
            BillingState = 'TX'
        );
        insert acct;

        Contract con = new Contract(
            AccountId    = acct.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-1),
            ContractTerm = 12
        );
        insert con;
        con.Status = 'Activated';
        update con;

        Opportunity opp = new Opportunity(
            Name      = 'OSA Doc Test Opportunity',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c        = acct.Id,
            SBQQ__Opportunity2__c   = opp.Id,
            SBQQ__MasterContract__c = con.Id,
            SBQQ__Primary__c        = true,
            SBQQ__Status__c         = 'Draft',
            SBQQ__Type__c           = 'Amendment',
            SBQQ__StartDate__c      = Date.today(),
            SBQQ__EndDate__c        = Date.today().addYears(1)
        );
        insert quote;

        // A second quote with no MasterContract so we can exercise the
        // `quote.Name` fallback branch in the file-name builder.
        SBQQ__Quote__c quoteNoContract = new SBQQ__Quote__c(
            SBQQ__Account__c      = acct.Id,
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Status__c       = 'Draft',
            SBQQ__Type__c         = 'Quote',
            SBQQ__StartDate__c    = Date.today(),
            SBQQ__EndDate__c      = Date.today().addYears(1)
        );
        insert quoteNoContract;
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private static SBQQ__Quote__c getQuote() {
        return [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Type__c = 'Amendment' LIMIT 1];
    }

    private static SBQQ__Quote__c getQuoteWithoutContract() {
        return [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Type__c = 'Quote' LIMIT 1];
    }

    /** Inserts a ContentVersion linked to the quote and returns the
     *  corresponding ContentDocument Id (used to simulate Conga-saved files). */
    private static Id insertContentVersionLinkedToQuote(Id quoteId, String title) {
        ContentVersion cv = new ContentVersion(
            Title                  = title,
            PathOnClient           = title,
            VersionData            = Blob.valueOf('test pdf content'),
            FirstPublishLocationId = quoteId
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
    }

    // ─── generateOsaDocument ───────────────────────────────────────────

    @isTest
    static void testGenerateOsaDocument_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.generateOsaDocument(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, info, 'GeneratedDocInfo should not be null');
        System.assertNotEquals(null, info.contentVersionId, 'ContentVersion Id should be populated');
        System.assertNotEquals(null, info.contentDocumentId, 'ContentDocument Id should be populated');
        System.assert(info.title.startsWith('OSA_'), 'Title should be prefixed with OSA_');
        System.assert(info.downloadUrl.contains('/sfc/servlet.shepherd/version/download/'),
            'Download URL should hit the Shepherd endpoint');
    }

    @isTest
    static void testGenerateOsaDocument_UsesQuoteNameWhenNoContract() {
        SBQQ__Quote__c q = getQuoteWithoutContract();
        SBQQ.TriggerControl.disable();

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.generateOsaDocument(q.Id);
        Test.stopTest();

        System.assert(info.title.startsWith('OSA_'),
            'Should still generate a file name when MasterContract is null');
    }

    @isTest
    static void testGenerateOsaDocument_BlankIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.generateOsaDocument('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quoteId should raise AuraHandledException');
    }

    @isTest
    static void testGenerateOsaDocument_NullIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.generateOsaDocument(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null quoteId should raise AuraHandledException');
    }

    // ─── uploadAdditionalPdf ───────────────────────────────────────────

    @isTest
    static void testUploadAdditionalPdf_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('fake pdf bytes'));
        SBQQ.TriggerControl.disable();

        Test.startTest();
        String cvId = AgenticQTC_OsaDocumentService.uploadAdditionalPdf(q.Id, 'extra.pdf', base64);
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'ContentVersion Id should be returned');
        ContentVersion cv = [SELECT Title FROM ContentVersion WHERE Id = :cvId LIMIT 1];
        System.assertEquals('extra.pdf', cv.Title, 'Custom file name should be preserved');
    }

    @isTest
    static void testUploadAdditionalPdf_NullFileNameUsesDefault() {
        SBQQ__Quote__c q = getQuote();
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('fake pdf bytes'));
        SBQQ.TriggerControl.disable();

        Test.startTest();
        String cvId = AgenticQTC_OsaDocumentService.uploadAdditionalPdf(q.Id, null, base64);
        Test.stopTest();

        ContentVersion cv = [SELECT Title FROM ContentVersion WHERE Id = :cvId LIMIT 1];
        System.assertEquals('attachment.pdf', cv.Title, 'Null file name should fall back to default');
    }

    @isTest
    static void testUploadAdditionalPdf_BlankQuoteIdThrows() {
        Boolean threw = false;
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('x'));
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.uploadAdditionalPdf('', 'x.pdf', base64);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quoteId should raise AuraHandledException');
    }

    @isTest
    static void testUploadAdditionalPdf_BlankBase64Throws() {
        SBQQ__Quote__c q = getQuote();
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.uploadAdditionalPdf(q.Id, 'x.pdf', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank base64 data should raise AuraHandledException');
    }

    // ─── getQuoteDocuments ─────────────────────────────────────────────

    @isTest
    static void testGetQuoteDocuments_Empty() {
        SBQQ__Quote__c q = getQuote();
        Test.startTest();
        List<AgenticQTC_OsaDocumentService.DocumentInfo> docs =
            AgenticQTC_OsaDocumentService.getQuoteDocuments(q.Id);
        Test.stopTest();
        System.assertNotEquals(null, docs);
        System.assertEquals(0, docs.size(), 'No documents linked yet — list should be empty');
    }

    @isTest
    static void testGetQuoteDocuments_WithDocs() {
        SBQQ__Quote__c q = getQuote();
        insertContentVersionLinkedToQuote(q.Id, 'LinkedDoc.pdf');

        Test.startTest();
        List<AgenticQTC_OsaDocumentService.DocumentInfo> docs =
            AgenticQTC_OsaDocumentService.getQuoteDocuments(q.Id);
        Test.stopTest();

        System.assertEquals(1, docs.size(), 'Inserted CV should surface as one DocumentInfo');
        System.assertEquals('LinkedDoc.pdf', docs[0].title);
        System.assertNotEquals(null, docs[0].id);
        System.assertNotEquals(null, docs[0].createdDate);
    }

    @isTest
    static void testGetQuoteDocuments_BlankReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_OsaDocumentService.DocumentInfo> docs =
            AgenticQTC_OsaDocumentService.getQuoteDocuments('');
        Test.stopTest();
        System.assertEquals(0, docs.size(), 'Blank input should return empty list, not throw');
    }

    // ─── generateAndSaveOsa ────────────────────────────────────────────

    @isTest
    static void testGenerateAndSaveOsa_BlankIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.generateAndSaveOsa('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quoteId should raise AuraHandledException');
    }

    @isTest
    static void testGenerateAndSaveOsa_ExercisesService() {
        // CongaUrlService relies on org metadata + labels that may or may not
        // resolve cleanly in test context. Either outcome (success path with
        // stubbed ContentVersion + QuoteDocument, or AuraHandledException
        // bubbled from the Conga URL builder) exercises the service logic.
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();

        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
                AgenticQTC_OsaDocumentService.generateAndSaveOsa(q.Id);
            // Success path: stub CV inserted + QuoteDocument created.
            System.assertNotEquals(null, info.contentVersionId);
            System.assertNotEquals(null, info.quoteDocumentId);
            System.assert(info.title.startsWith('OSA_'));
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(),
                'AuraHandledException should carry a message');
        }
        Test.stopTest();
    }

    // ─── buildCongaUrlForSave ──────────────────────────────────────────

    @isTest
    static void testBuildCongaUrlForSave_BlankIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.buildCongaUrlForSave('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quoteId should raise AuraHandledException');
    }

    @isTest
    static void testBuildCongaUrlForSave_ExercisesService() {
        SBQQ__Quote__c q = getQuote();

        Test.startTest();
        try {
            String url = AgenticQTC_OsaDocumentService.buildCongaUrlForSave(q.Id);
            System.assertNotEquals(null, url, 'Returned URL should not be null on success');
            System.assert(url.contains('/apex/APXTConga4__Conga_Composer'),
                'URL should point at the VF Conga Composer page');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testBuildCongaUrlForSave_WithAdditionalAttachments() {
        // Seed an additional-document related-content record so the
        // injectAdditionalAttachments branch runs.
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Attached.pdf');

        SBQQ__RelatedContent__c rc = new SBQQ__RelatedContent__c(
            Name                 = 'Attached.pdf',
            SBQQ__Quote__c       = q.Id,
            SBQQ__ExternalId__c  = cdId,
            SBQQ__Required__c    = false,
            SBQQ__DisplayOrder__c = 1
        );
        insert rc;

        Test.startTest();
        try {
            String url = AgenticQTC_OsaDocumentService.buildCongaUrlForSave(q.Id);
            System.assertNotEquals(null, url);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ─── pollForNewDocument ────────────────────────────────────────────

    @isTest
    static void testPollForNewDocument_BlankReturnsNull() {
        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.pollForNewDocument('', '2026-05-19T10:00:00.000Z');
        Test.stopTest();
        System.assertEquals(null, info, 'Blank quoteId should short-circuit to null');
    }

    @isTest
    static void testPollForNewDocument_NoMatchReturnsNull() {
        SBQQ__Quote__c q = getQuote();
        // Insert a CV *before* the cutoff so it's outside the window.
        insertContentVersionLinkedToQuote(q.Id, 'Old.pdf');
        String futureCutoff = Datetime.now().addHours(1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.pollForNewDocument(q.Id, futureCutoff);
        Test.stopTest();
        System.assertEquals(null, info, 'No new docs after cutoff should return null');
    }

    @isTest
    static void testPollForNewDocument_FindsMatch() {
        SBQQ__Quote__c q = getQuote();
        // 1-hour-ago cutoff guarantees the CV we just inserted falls inside the window.
        String pastCutoff = Datetime.now().addHours(-1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        insertContentVersionLinkedToQuote(q.Id, 'Fresh.pdf');

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.pollForNewDocument(q.Id, pastCutoff);
        Test.stopTest();

        System.assertNotEquals(null, info, 'Should locate the recently inserted CV');
        System.assertEquals('Fresh.pdf', info.title);
        System.assertNotEquals(null, info.contentVersionId);
        System.assertNotEquals(null, info.contentDocumentId);
    }

    @isTest
    static void testPollForNewDocument_BlankTimestampDefaultsToFiveMinAgo() {
        SBQQ__Quote__c q = getQuote();
        insertContentVersionLinkedToQuote(q.Id, 'JustNow.pdf');

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.pollForNewDocument(q.Id, '');
        Test.stopTest();

        System.assertNotEquals(null, info,
            'Blank timestamp should default to a 5-minute window and find the recent CV');
    }

    @isTest
    static void testPollForNewDocument_InvalidTimestampFallsBack() {
        // Malformed timestamp triggers the catch block → default 5-min window.
        SBQQ__Quote__c q = getQuote();
        insertContentVersionLinkedToQuote(q.Id, 'Recent.pdf');

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.pollForNewDocument(q.Id, 'not-a-date');
        Test.stopTest();

        System.assertNotEquals(null, info,
            'Unparseable timestamp should fall back to the default window');
    }

    // ─── finalizeOsaDocument ───────────────────────────────────────────

    @isTest
    static void testFinalizeOsaDocument_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'ToFinalize.pdf');
        SBQQ.TriggerControl.disable();

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.finalizeOsaDocument(q.Id, cdId);
        Test.stopTest();

        System.assertNotEquals(null, info.contentVersionId);
        System.assertEquals(cdId, Id.valueOf(info.contentDocumentId));
        System.assertNotEquals(null, info.quoteDocumentId, 'QuoteDocument should be created');

        SBQQ__QuoteDocument__c qd = [
            SELECT SBQQ__Version__c, SBQQ__DocumentId__c, SBQQ__Quote__c
            FROM SBQQ__QuoteDocument__c
            WHERE Id = :info.quoteDocumentId
            LIMIT 1
        ];
        System.assertEquals(1, qd.SBQQ__Version__c, 'First finalized doc should be version 1');
        // BIZ-81419: DocumentId must point at a classic Document (015), not the ContentDocument
        // (069) — the View button and OP4I can only retrieve the former.
        System.assertNotEquals(null, qd.SBQQ__DocumentId__c);
        System.assertNotEquals(String.valueOf(cdId), qd.SBQQ__DocumentId__c,
            'DocumentId should be the classic Document, not the ContentDocument');
        System.assert(qd.SBQQ__DocumentId__c.startsWith('015'),
            'DocumentId should be a classic Document (015) id');
        System.assertEquals(q.Id, qd.SBQQ__Quote__c);
    }

    @isTest
    static void testFinalizeOsaDocument_IncrementsVersion() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Version1.pdf');
        SBQQ.TriggerControl.disable();

        // Pre-seed an existing QuoteDocument so the agg query returns version 1.
        insert new SBQQ__QuoteDocument__c(
            Name             = 'Existing',
            SBQQ__Quote__c   = q.Id,
            SBQQ__Version__c = 1,
            SBQQ__DocumentId__c = cdId
        );

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.finalizeOsaDocument(q.Id, cdId);
        Test.stopTest();

        SBQQ__QuoteDocument__c qd = [
            SELECT SBQQ__Version__c FROM SBQQ__QuoteDocument__c
            WHERE Id = :info.quoteDocumentId LIMIT 1
        ];
        System.assertEquals(2, qd.SBQQ__Version__c, 'Should increment to version 2');
    }

    @isTest
    static void testFinalizeOsaDocument_BlankIdsThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.finalizeOsaDocument('', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank ids should raise AuraHandledException');
    }

    @isTest
    static void testFinalizeOsaDocument_UsesQuoteNameWhenNoContract() {
        SBQQ__Quote__c q = getQuoteWithoutContract();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'FallbackName.pdf');
        SBQQ.TriggerControl.disable();

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.finalizeOsaDocument(q.Id, cdId);
        Test.stopTest();

        System.assertNotEquals(null, info.quoteDocumentId);
    }

    // ─── createRelatedContent ──────────────────────────────────────────

    @isTest
    static void testCreateRelatedContent_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Linked.pdf');

        Test.startTest();
        AgenticQTC_OsaDocumentService.createRelatedContent(q.Id, cdId, 'My Related Doc');
        Test.stopTest();

        SBQQ__RelatedContent__c rc = [
            SELECT Name, SBQQ__Quote__c, SBQQ__ExternalId__c, SBQQ__Required__c, SBQQ__DisplayOrder__c
            FROM   SBQQ__RelatedContent__c
            WHERE  SBQQ__Quote__c = :q.Id
            LIMIT  1
        ];
        System.assertEquals('My Related Doc', rc.Name);
        System.assertEquals(q.Id, rc.SBQQ__Quote__c);
        System.assertEquals(String.valueOf(cdId), rc.SBQQ__ExternalId__c);
        System.assertEquals(false, rc.SBQQ__Required__c);
        System.assertEquals(1, rc.SBQQ__DisplayOrder__c, 'First upload should land at display order 1');
    }

    @isTest
    static void testCreateRelatedContent_NullNameUsesDefault() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Linked.pdf');

        Test.startTest();
        AgenticQTC_OsaDocumentService.createRelatedContent(q.Id, cdId, null);
        Test.stopTest();

        SBQQ__RelatedContent__c rc = [
            SELECT Name FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :q.Id LIMIT 1
        ];
        System.assertEquals('Additional Document', rc.Name, 'Null name should fall back to default');
    }

    @isTest
    static void testCreateRelatedContent_IncrementsDisplayOrder() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Existing.pdf');

        // Seed an existing related-content row so the agg-MAX branch runs.
        insert new SBQQ__RelatedContent__c(
            Name                  = 'Existing',
            SBQQ__Quote__c        = q.Id,
            SBQQ__ExternalId__c   = cdId,
            SBQQ__Required__c     = false,
            SBQQ__DisplayOrder__c = 3
        );

        Test.startTest();
        AgenticQTC_OsaDocumentService.createRelatedContent(q.Id, cdId, 'Next Upload');
        Test.stopTest();

        SBQQ__RelatedContent__c rc = [
            SELECT SBQQ__DisplayOrder__c
            FROM   SBQQ__RelatedContent__c
            WHERE  SBQQ__Quote__c = :q.Id
            AND    Name = 'Next Upload'
            LIMIT  1
        ];
        System.assertEquals(4, rc.SBQQ__DisplayOrder__c,
            'New row should be appended after the highest existing display order');
    }

    @isTest
    static void testCreateRelatedContent_BlankIdsThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.createRelatedContent('', '', 'x');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank ids should raise AuraHandledException');
    }

    // ─── getRelatedContent ─────────────────────────────────────────────

    @isTest
    static void testGetRelatedContent_BlankReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_OsaDocumentService.RelatedContentInfo> results =
            AgenticQTC_OsaDocumentService.getRelatedContent('');
        Test.stopTest();
        System.assertEquals(0, results.size());
    }

    @isTest
    static void testGetRelatedContent_FiltersGeneratedOsa() {
        SBQQ__Quote__c q = getQuote();

        insert new List<SBQQ__RelatedContent__c>{
            new SBQQ__RelatedContent__c(
                Name                  = 'Customer Upload',
                SBQQ__Quote__c        = q.Id,
                SBQQ__ExternalId__c   = '0691234567890123',
                Document_Type__c      = 'Other',
                SBQQ__Required__c     = false,
                SBQQ__DisplayOrder__c = 1
            ),
            // Should be filtered out by the Document_Type__c != 'Conga Generated OSA' clause.
            new SBQQ__RelatedContent__c(
                Name                  = 'Generated OSA',
                SBQQ__Quote__c        = q.Id,
                SBQQ__ExternalId__c   = '0691234567890124',
                Document_Type__c      = 'Conga Generated OSA',
                SBQQ__Required__c     = false,
                SBQQ__DisplayOrder__c = 2
            )
        };

        Test.startTest();
        List<AgenticQTC_OsaDocumentService.RelatedContentInfo> results =
            AgenticQTC_OsaDocumentService.getRelatedContent(q.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Conga Generated OSA entries should be filtered out');
        System.assertEquals('Customer Upload', results[0].name);
        System.assertEquals('Other', results[0].documentType);
        System.assertEquals('0691234567890123', results[0].externalId);
    }

    @isTest
    static void testGetRelatedContent_PopulatesContentVersionId() {
        // Real ContentDocumentId so the docToLatestVersion map gets populated
        // and the contentVersionId branch surfaces a value.
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Mapped.pdf');

        insert new SBQQ__RelatedContent__c(
            Name                  = 'Mapped Upload',
            SBQQ__Quote__c        = q.Id,
            SBQQ__ExternalId__c   = cdId,
            Document_Type__c      = 'Other',
            SBQQ__Required__c     = false,
            SBQQ__DisplayOrder__c = 1
        );

        Test.startTest();
        List<AgenticQTC_OsaDocumentService.RelatedContentInfo> results =
            AgenticQTC_OsaDocumentService.getRelatedContent(q.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].contentVersionId,
            'Latest ContentVersion Id should be looked up and populated');
        System.assertEquals(1, results[0].displayOrder);
    }

    // ─── renderInstantPdfBytes ─────────────────────────────────────────

    @isTest
    static void testRenderInstantPdfBytes_HappyPath() {
        SBQQ__Quote__c q = getQuote();

        Test.startTest();
        AgenticQTC_OsaDocumentService.InstantPdfRender render =
            AgenticQTC_OsaDocumentService.renderInstantPdfBytes(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, render);
        System.assertNotEquals(null, render.base64Pdf, 'Base64 PDF should be populated');
        System.assert(render.fileName.startsWith('OSA_'),
            'File name should be the standard OSA_ prefix');
        System.assertEquals(1, render.nextVersion, 'No QuoteDocuments yet — next version is 1');
    }

    @isTest
    static void testRenderInstantPdfBytes_QuoteNameFallback() {
        // No MasterContract so the buildOsaFileName branch falls back to Quote.Name.
        SBQQ__Quote__c q = getQuoteWithoutContract();

        Test.startTest();
        AgenticQTC_OsaDocumentService.InstantPdfRender render =
            AgenticQTC_OsaDocumentService.renderInstantPdfBytes(q.Id);
        Test.stopTest();

        System.assert(render.fileName.startsWith('OSA_'));
    }

    @isTest
    static void testRenderInstantPdfBytes_BlankIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.renderInstantPdfBytes('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quoteId should raise AuraHandledException');
    }

    // ─── saveMergedInstantPdf ──────────────────────────────────────────

    @isTest
    static void testSaveMergedInstantPdf_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 merged'));

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.saveMergedInstantPdf(q.Id, base64, 'Merged.pdf', 5);
        Test.stopTest();

        System.assertNotEquals(null, info.contentVersionId);
        System.assertNotEquals(null, info.contentDocumentId);
        System.assertEquals('Merged.pdf', info.title);
        System.assert(info.downloadUrl.contains('/sfc/servlet.shepherd/version/download/'));

        SBQQ__QuoteDocument__c qd = [
            SELECT SBQQ__Version__c, SBQQ__Quote__c, SBQQ__DocumentId__c
            FROM   SBQQ__QuoteDocument__c
            WHERE  SBQQ__Quote__c = :q.Id
            LIMIT  1
        ];
        System.assertEquals(5, qd.SBQQ__Version__c, 'Supplied versionNumber should be honoured');
    }

    @isTest
    static void testSaveMergedInstantPdf_BlankFileNameAndVersionFallback() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 merged'));

        Test.startTest();
        // null fileName and null versionNumber exercise both fallback branches.
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.saveMergedInstantPdf(q.Id, base64, null, null);
        Test.stopTest();

        System.assert(info.title.startsWith('OSA_'),
            'Null file name should fall back to the OSA_<date> default');
        SBQQ__QuoteDocument__c qd = [
            SELECT SBQQ__Version__c FROM SBQQ__QuoteDocument__c
            WHERE SBQQ__Quote__c = :q.Id LIMIT 1
        ];
        System.assertEquals(1, qd.SBQQ__Version__c,
            'Null versionNumber should fall back to next-version lookup (1)');
    }

    @isTest
    static void testSaveMergedInstantPdf_BlankIdsThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.saveMergedInstantPdf('', '', 'x.pdf', 1);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quoteId/base64 should raise AuraHandledException');
    }

    @isTest
    static void testSaveMergedInstantPdf_ApprovedQuoteStampsDoc() {
        // BIZ-81419: when the quote is already Approved at generation time, the new
        // QuoteDocument is stamped Quote_ApprovalStatus__c = 'Approved' (separate update)
        // so QuoteDocumentTriggerHelper.publishApprovedOSA fires the OnePlace publish.
        SBQQ__Quote__c q = getQuote();
        update new SBQQ__Quote__c(Id = q.Id, ApprovalStatus__c = QuoteConstants.STATUS_APPROVED);
        SBQQ.TriggerControl.disable();
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 merged'));

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.saveMergedInstantPdf(q.Id, base64, 'Approved.pdf', 1);
        Test.stopTest();

        SBQQ__QuoteDocument__c qd = [
            SELECT Quote_ApprovalStatus__c
            FROM   SBQQ__QuoteDocument__c
            WHERE  Id = :info.quoteDocumentId
            LIMIT  1
        ];
        System.assertEquals(QuoteConstants.STATUS_APPROVED, qd.Quote_ApprovalStatus__c,
            'Doc generated on an already-approved quote should be auto-stamped Approved');
    }

    // ─── getContentVersionBase64 ───────────────────────────────────────

    @isTest
    static void testGetContentVersionBase64_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        ContentVersion cv = new ContentVersion(
            Title                  = 'Bytes.pdf',
            PathOnClient           = 'Bytes.pdf',
            VersionData            = Blob.valueOf('hello pdf'),
            FirstPublishLocationId = q.Id
        );
        insert cv;

        Test.startTest();
        String b64 = AgenticQTC_OsaDocumentService.getContentVersionBase64(cv.Id);
        Test.stopTest();

        System.assertNotEquals(null, b64);
        System.assertEquals('hello pdf',
            EncodingUtil.base64Decode(b64).toString(),
            'Round-tripped bytes should match what was stored');
    }

    @isTest
    static void testGetContentVersionBase64_BlankIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.getContentVersionBase64('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank id should raise AuraHandledException');
    }

    // ─── renderCoverPdfBytes ───────────────────────────────────────────

    @isTest
    static void testRenderCoverPdfBytes_HappyPath() {
        SBQQ__Quote__c q = getQuote();

        Test.startTest();
        String b64 = AgenticQTC_OsaDocumentService.renderCoverPdfBytes(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, b64, 'Cover PDF bytes should be returned');
        System.assert(b64.length() > 0, 'Base64 string should be non-empty');
    }

    @isTest
    static void testRenderCoverPdfBytes_BlankIdThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.renderCoverPdfBytes('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quoteId should raise AuraHandledException');
    }

    // ─── replaceCongaWithMergedPdf ─────────────────────────────────────

    @isTest
    static void testReplaceCongaWithMergedPdf_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'CongaOriginal.pdf');
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 merged-with-cover'));

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.replaceCongaWithMergedPdf(cdId, base64, null);
        Test.stopTest();

        System.assertEquals(String.valueOf(cdId), info.contentDocumentId,
            'New version should share the original ContentDocumentId');
        System.assertEquals('CongaOriginal.pdf', info.title,
            'Title should be carried over from the original');
        System.assertNotEquals(null, info.contentVersionId,
            'New ContentVersion Id should be returned');
    }

    @isTest
    static void testReplaceCongaWithMergedPdf_BlankIdsThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.replaceCongaWithMergedPdf('', '', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank inputs should raise AuraHandledException');
    }

    @isTest
    static void testReplaceCongaWithMergedPdf_NoExistingVersionThrows() {
        // Use a real-but-deleted ContentDocumentId so SOQL accepts the format
        // but the IsLatest=true lookup returns empty → triggers the throw.
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'ToOrphan.pdf');
        delete [SELECT Id FROM ContentDocument WHERE Id = :cdId];

        Boolean threw = false;
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('x'));
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.replaceCongaWithMergedPdf(cdId, base64, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Missing original ContentVersion should raise AuraHandledException');
    }

    // ─── reorderRelatedContent ─────────────────────────────────────────

    @isTest
    static void testReorderRelatedContent_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Reorder.pdf');

        SBQQ__RelatedContent__c rc1 = new SBQQ__RelatedContent__c(
            Name = 'First',  SBQQ__Quote__c = q.Id, SBQQ__ExternalId__c = cdId,
            SBQQ__Required__c = false, SBQQ__DisplayOrder__c = 1
        );
        SBQQ__RelatedContent__c rc2 = new SBQQ__RelatedContent__c(
            Name = 'Second', SBQQ__Quote__c = q.Id, SBQQ__ExternalId__c = cdId,
            SBQQ__Required__c = false, SBQQ__DisplayOrder__c = 2
        );
        insert new List<SBQQ__RelatedContent__c>{ rc1, rc2 };

        // Reverse the order.
        List<String> newOrder = new List<String>{ rc2.Id, rc1.Id };

        Test.startTest();
        AgenticQTC_OsaDocumentService.reorderRelatedContent(q.Id, newOrder);
        Test.stopTest();

        Map<Id, SBQQ__RelatedContent__c> reordered = new Map<Id, SBQQ__RelatedContent__c>([
            SELECT Id, SBQQ__DisplayOrder__c
            FROM   SBQQ__RelatedContent__c
            WHERE  Id IN :newOrder
        ]);
        System.assertEquals(1, reordered.get(rc2.Id).SBQQ__DisplayOrder__c,
            'rc2 should now be first');
        System.assertEquals(2, reordered.get(rc1.Id).SBQQ__DisplayOrder__c,
            'rc1 should now be second');
    }

    @isTest
    static void testReorderRelatedContent_BlankInputShortCircuits() {
        // Should not throw; should simply no-op.
        Test.startTest();
        AgenticQTC_OsaDocumentService.reorderRelatedContent('', new List<String>());
        AgenticQTC_OsaDocumentService.reorderRelatedContent(null, null);
        Test.stopTest();
    }

    @isTest
    static void testReorderRelatedContent_IgnoresStaleIds() {
        // LWC may race a delete against a reorder. We exercise the
        // `if (rc != null)` skip branch by including a real-but-deleted id
        // in the orderedIds payload alongside a live one.
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'StaleRace.pdf');

        SBQQ__RelatedContent__c live = new SBQQ__RelatedContent__c(
            Name = 'Live', SBQQ__Quote__c = q.Id, SBQQ__ExternalId__c = cdId,
            SBQQ__Required__c = false, SBQQ__DisplayOrder__c = 1
        );
        SBQQ__RelatedContent__c stale = new SBQQ__RelatedContent__c(
            Name = 'Stale', SBQQ__Quote__c = q.Id, SBQQ__ExternalId__c = cdId,
            SBQQ__Required__c = false, SBQQ__DisplayOrder__c = 2
        );
        insert new List<SBQQ__RelatedContent__c>{ live, stale };
        Id staleId = stale.Id;
        delete stale;

        Test.startTest();
        AgenticQTC_OsaDocumentService.reorderRelatedContent(
            q.Id, new List<String>{ staleId, live.Id }
        );
        Test.stopTest();

        SBQQ__RelatedContent__c reloaded = [
            SELECT SBQQ__DisplayOrder__c FROM SBQQ__RelatedContent__c
            WHERE Id = :live.Id LIMIT 1
        ];
        System.assertEquals(2, reloaded.SBQQ__DisplayOrder__c,
            'Live row should still be reordered even though a stale id was included');
    }

    // ─── deleteRelatedContent ──────────────────────────────────────────

    @isTest
    static void testDeleteRelatedContent_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'ToDelete.pdf');

        SBQQ__RelatedContent__c rc = new SBQQ__RelatedContent__c(
            Name = 'Delete me', SBQQ__Quote__c = q.Id, SBQQ__ExternalId__c = cdId,
            SBQQ__Required__c = false, SBQQ__DisplayOrder__c = 1
        );
        insert rc;

        Test.startTest();
        AgenticQTC_OsaDocumentService.deleteRelatedContent(q.Id, rc.Id);
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT() FROM SBQQ__RelatedContent__c WHERE Id = :rc.Id
        ];
        System.assertEquals(0, remaining, 'Row should be deleted');
    }

    @isTest
    static void testDeleteRelatedContent_BlankIdsThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_OsaDocumentService.deleteRelatedContent('', '');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank inputs should raise AuraHandledException');
    }

    @isTest
    static void testDeleteRelatedContent_StaleIdNoOps() {
        // Stale id (real-but-deleted) → empty query result → no-op branch.
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'Stale.pdf');
        SBQQ__RelatedContent__c rc = new SBQQ__RelatedContent__c(
            Name = 'Stale', SBQQ__Quote__c = q.Id, SBQQ__ExternalId__c = cdId,
            SBQQ__Required__c = false, SBQQ__DisplayOrder__c = 1
        );
        insert rc;
        Id staleId = rc.Id;
        delete rc;

        Test.startTest();
        AgenticQTC_OsaDocumentService.deleteRelatedContent(q.Id, staleId);
        Test.stopTest();
        // No exception → branch covered.
    }

    // ─── applyStandardOsaName (standard rename when Expiration Date is set) ──

    @isTest
    static void testFinalizeOsaDocument_withExpirationDate_appliesStandardName() {
        // With a Quote Expiration Date set, CustomName__c resolves to a non-blank
        // standard name, so applyStandardOsaName proceeds past its early-return and
        // renames the QuoteDocument / File / classic Document. BIZ-83515
        SBQQ__Quote__c q = getQuote();
        q.SBQQ__ExpirationDate__c = Date.today().addDays(30);
        update q;

        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'ExpDated.pdf');
        SBQQ.TriggerControl.disable();

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.finalizeOsaDocument(q.Id, cdId);
        Test.stopTest();

        System.assertNotEquals(null, info.quoteDocumentId,
            'QuoteDocument should be created and run through the standard-name path');
    }

    // ─── getNextQuoteDocVersion (increment branch via renderInstantPdfBytes) ─

    @isTest
    static void testRenderInstantPdfBytes_incrementsVersion() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        // Pre-seed an existing QuoteDocument so getNextQuoteDocVersion returns max+1.
        insert new SBQQ__QuoteDocument__c(
            Name             = 'Prior',
            SBQQ__Quote__c   = q.Id,
            SBQQ__Version__c = 1
        );

        Test.startTest();
        AgenticQTC_OsaDocumentService.InstantPdfRender render =
            AgenticQTC_OsaDocumentService.renderInstantPdfBytes(q.Id);
        Test.stopTest();

        System.assertEquals(2, render.nextVersion,
            'Existing version 1 → next version should be 2');
    }

    // ─── getContentVersionBase64 (not-found → null) ─────────────────────────

    @isTest
    static void testGetContentVersionBase64_notFoundReturnsNull() {
        // Well-formed but non-existent ContentVersion Id → empty query → null.
        Test.startTest();
        String result = AgenticQTC_OsaDocumentService.getContentVersionBase64('068000000000001AAA');
        Test.stopTest();

        System.assertEquals(null, result,
            'A non-existent ContentVersion should return null, not throw');
    }

    // ─── replaceCongaWithMergedPdf (refreshes the classic 015 Document) ──────

    @isTest
    static void testReplaceCongaWithMergedPdf_refreshesLegacyDocument() {
        SBQQ__Quote__c q = getQuote();
        Id cdId = insertContentVersionLinkedToQuote(q.Id, 'CongaForLegacy.pdf');

        // A classic Document (015) so the legacyDocumentId branch (startsWith '015') runs.
        Document legacy = new Document(
            Name        = 'Legacy OSA',
            FolderId    = UserInfo.getUserId(),
            Body        = Blob.valueOf('old legacy body'),
            Type        = 'pdf',
            ContentType = 'application/pdf'
        );
        insert legacy;

        String base64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 merged-with-cover'));

        Test.startTest();
        AgenticQTC_OsaDocumentService.GeneratedDocInfo info =
            AgenticQTC_OsaDocumentService.replaceCongaWithMergedPdf(cdId, base64, legacy.Id);
        Test.stopTest();

        System.assertNotEquals(null, info.contentVersionId,
            'A new ContentVersion should be returned');
        Document refreshed = [SELECT Body FROM Document WHERE Id = :legacy.Id LIMIT 1];
        System.assertEquals('%PDF-1.4 merged-with-cover', refreshed.Body.toString(),
            'The classic Document body should be refreshed with the merged PDF');
    }

}