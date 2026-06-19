/**
 * @author  Sahal Mohamed
 * @date    02/17/2026
 * @description Test class for QuoteFileUploadController.
 *              Covers getQuoteFiles (ContentVersion + Attachment), updateDocumentType,
 *              updateFileDetails, deleteFile, and deleteAttachment methods
 *              with positive, negative, and edge-case scenarios.
 * @jira    BIZ-79176
 */
@isTest
public class QuoteFileUploadControllerTest {

    /**********************************************************************************************
     *
     * Test Setup
     *
     ***********************************************************************************************/

    @TestSetup
    static void makeData() {
        // Create Account
        Account account = (Account) TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );

        // Create Opportunity
        Opportunity opportunity = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );

        // Create Quote
        SBQQ__Quote__c quote = (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );

        // Create 3 ContentVersion files linked to the Quote
        List<ContentVersion> files = new List<ContentVersion>();
        for (Integer i = 1; i <= 3; i++) {
            files.add(new ContentVersion(
                Title = 'TestFile' + i,
                PathOnClient = 'TestFile' + i + '.pdf',
                VersionData = Blob.valueOf('Test content ' + i)
            ));
        }
        insert files;

        // Re-query to get ContentDocumentIds
        List<ContentVersion> insertedFiles = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :files
        ];

        // Create ContentDocumentLinks to associate files with the Quote
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion cv : insertedFiles) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = quote.Id,
                ShareType = 'V'
            ));
        }
        insert links;

        // Create 2 classic Attachment records linked to the Quote
        List<Attachment> attachments = new List<Attachment>();
        for (Integer i = 1; i <= 2; i++) {
            attachments.add(new Attachment(
                Name = 'TestAttachment' + i + '.docx',
                ParentId = quote.Id,
                Body = Blob.valueOf('Attachment content ' + i),
                ContentType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            ));
        }
        insert attachments;
    }

    /**********************************************************************************************
     *
     * Helper Methods
     *
     ***********************************************************************************************/

    private static SBQQ__Quote__c getTestQuote() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
    }

    private static List<ContentVersion> getTestFiles() {
        return [
            SELECT Id, ContentDocumentId, Document_Type__c
            FROM ContentVersion
            WHERE IsLatest = true
            ORDER BY Title ASC
        ];
    }

    private static List<Attachment> getTestAttachments() {
        return [
            SELECT Id, Name
            FROM Attachment
            ORDER BY Name ASC
        ];
    }

    /**********************************************************************************************
     *
     * getQuoteFiles Tests
     *
     ***********************************************************************************************/

    /**
     * @description Verifies that getQuoteFiles returns ContentVersion files as FileWrapper
     *              records with source = 'ContentVersion' and all expected fields populated.
     */
    @isTest
    static void testGetQuoteFiles_ReturnsFiles() {
        SBQQ__Quote__c quote = getTestQuote();

        Test.startTest();
        List<QuoteFileUploadController.FileWrapper> results = QuoteFileUploadController.getQuoteFiles(quote.Id);
        Test.stopTest();

        // 3 ContentVersions + 2 Attachments = 5 total
        System.assertEquals(5, results.size(), 'Should return 5 total records (3 files + 2 attachments)');

        // Verify ContentVersion wrappers
        Integer cvCount = 0;
        for (QuoteFileUploadController.FileWrapper fw : results) {
            if (fw.source == 'ContentVersion') {
                cvCount++;
                System.assertNotEquals(null, fw.title, 'Title should be populated');
                System.assertNotEquals(null, fw.contentDocumentId, 'contentDocumentId should be populated');
                System.assertNotEquals(null, fw.createdDate, 'createdDate should be populated');
                System.assertNotEquals(null, fw.createdByName, 'createdByName should be populated');
                System.assert(fw.downloadUrl.startsWith('/sfc/servlet.shepherd'), 'ContentVersion downloadUrl should use shepherd path');
            }
        }
        System.assertEquals(3, cvCount, 'Should have 3 ContentVersion wrappers');
    }

    /**
     * @description Verifies that getQuoteFiles includes classic Attachment records
     *              with source = 'Attachment' and proper field mappings.
     */
    @isTest
    static void testGetQuoteFiles_IncludesAttachments() {
        SBQQ__Quote__c quote = getTestQuote();

        Test.startTest();
        List<QuoteFileUploadController.FileWrapper> results = QuoteFileUploadController.getQuoteFiles(quote.Id);
        Test.stopTest();

        Integer attCount = 0;
        for (QuoteFileUploadController.FileWrapper fw : results) {
            if (fw.source == 'Attachment') {
                attCount++;
                System.assertNotEquals(null, fw.title, 'Attachment title should be populated');
                System.assertEquals(null, fw.contentDocumentId, 'Attachment should have null contentDocumentId');
                System.assertEquals(null, fw.documentType, 'Attachment should have null documentType');
                System.assert(fw.downloadUrl.contains('/servlet/servlet.FileDownload'), 'Attachment downloadUrl should use FileDownload servlet');
                System.assertEquals('docx', fw.fileExtension, 'File extension should be extracted from filename');
            }
        }
        System.assertEquals(2, attCount, 'Should have 2 Attachment wrappers');
    }

    /**
     * @description Verifies that getQuoteFiles returns an empty list when the Quote has no files.
     */
    @isTest
    static void testGetQuoteFiles_NoFiles() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        SBQQ__Quote__c emptyQuote = (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opp.Id
            ), 'SBQQQuoteDefaults'
        );

        Test.startTest();
        List<QuoteFileUploadController.FileWrapper> results = QuoteFileUploadController.getQuoteFiles(emptyQuote.Id);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty list for Quote with no files');
    }

    /**
     * @description Verifies that getQuoteFiles throws an error when quoteId is null.
     */
    @isTest
    static void testGetQuoteFiles_NullId() {
        Test.startTest();
        try {
            QuoteFileUploadController.getQuoteFiles(null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Quote Id is required'), 'Error message should mention Quote Id');
        }
        Test.stopTest();
    }

    /**********************************************************************************************
     *
     * updateDocumentType Tests
     *
     ***********************************************************************************************/

    /**
     * @description Verifies that updateDocumentType stamps the Document_Type__c field
     *              on a single ContentVersion record.
     */
    @isTest
    static void testUpdateDocumentType_Success() {
        List<ContentVersion> files = getTestFiles();
        List<Id> docIds = new List<Id>{ files[0].ContentDocumentId };

        Test.startTest();
        QuoteFileUploadController.updateDocumentType(docIds, 'OSA - Signed');
        Test.stopTest();

        ContentVersion updated = [
            SELECT Document_Type__c FROM ContentVersion
            WHERE ContentDocumentId = :docIds[0] AND IsLatest = true
        ];
        System.assertEquals('OSA - Signed', updated.Document_Type__c, 'Document_Type__c should be stamped');
    }

    /**
     * @description Verifies that updateDocumentType stamps multiple files at once.
     */
    @isTest
    static void testUpdateDocumentType_MultipleFiles() {
        List<ContentVersion> files = getTestFiles();
        List<Id> docIds = new List<Id>();
        for (ContentVersion cv : files) {
            docIds.add(cv.ContentDocumentId);
        }

        Test.startTest();
        QuoteFileUploadController.updateDocumentType(docIds, 'OSA - Signed');
        Test.stopTest();

        List<ContentVersion> updated = [
            SELECT Document_Type__c FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
        ];
        System.assertEquals(3, updated.size(), 'Should have updated 3 files');
        for (ContentVersion cv : updated) {
            System.assertEquals('OSA - Signed', cv.Document_Type__c, 'All files should have Document_Type__c stamped');
        }
    }

    /**
     * @description Verifies that updateDocumentType throws an error when documentType is null.
     */
    @isTest
    static void testUpdateDocumentType_NullDocumentType() {
        List<ContentVersion> files = getTestFiles();
        List<Id> docIds = new List<Id>{ files[0].ContentDocumentId };

        Test.startTest();
        try {
            QuoteFileUploadController.updateDocumentType(docIds, null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Document Type is required'), 'Error message should mention Document Type');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that updateDocumentType throws an error when the Id list is empty.
     */
    @isTest
    static void testUpdateDocumentType_EmptyIdList() {
        Test.startTest();
        try {
            QuoteFileUploadController.updateDocumentType(new List<Id>(), 'OSA - Signed');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No file Ids provided'), 'Error message should mention missing Ids');
        }
        Test.stopTest();
    }

    /**********************************************************************************************
     *
     * updateFileDetails Tests
     *
     ***********************************************************************************************/

    /**
     * @description Verifies that updateFileDetails updates Title and Document_Type__c
     *              on a ContentVersion record.
     */
    @isTest
    static void testUpdateFileDetails_Success() {
        List<ContentVersion> files = getTestFiles();
        Id cvId = files[0].Id;

        Test.startTest();
        QuoteFileUploadController.updateFileDetails(cvId, 'Renamed File', 'OSA - Signed');
        Test.stopTest();

        ContentVersion updated = [
            SELECT Title, Document_Type__c FROM ContentVersion WHERE Id = :cvId
        ];
        System.assertEquals('Renamed File', updated.Title, 'Title should be updated');
        System.assertEquals('OSA - Signed', updated.Document_Type__c, 'Document_Type__c should be updated');
    }

    /**
     * @description Verifies that updateFileDetails throws an error when Title is blank.
     */
    @isTest
    static void testUpdateFileDetails_BlankTitle() {
        List<ContentVersion> files = getTestFiles();
        Id cvId = files[0].Id;

        Test.startTest();
        try {
            QuoteFileUploadController.updateFileDetails(cvId, '', 'OSA - Signed');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Title is required'), 'Error message should mention Title');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that updateFileDetails throws an error when Document Type is blank.
     */
    @isTest
    static void testUpdateFileDetails_BlankDocumentType() {
        List<ContentVersion> files = getTestFiles();
        Id cvId = files[0].Id;

        Test.startTest();
        try {
            QuoteFileUploadController.updateFileDetails(cvId, 'Some Title', '');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Document Type is required'), 'Error message should mention Document Type');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that updateFileDetails throws an error when ContentVersion Id is null.
     */
    @isTest
    static void testUpdateFileDetails_NullId() {
        Test.startTest();
        try {
            QuoteFileUploadController.updateFileDetails(null, 'Some Title', 'OSA - Signed');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('ContentVersion Id is required'), 'Error message should mention ContentVersion Id');
        }
        Test.stopTest();
    }

    /**********************************************************************************************
     *
     * deleteFile Tests
     *
     ***********************************************************************************************/

    /**
     * @description Verifies that deleteFile removes a ContentDocument and its associated versions/links.
     */
    @isTest
    static void testDeleteFile_Success() {
        List<ContentVersion> files = getTestFiles();
        Id docId = files[0].ContentDocumentId;

        Test.startTest();
        QuoteFileUploadController.deleteFile(docId);
        Test.stopTest();

        List<ContentDocument> remaining = [SELECT Id FROM ContentDocument WHERE Id = :docId];
        System.assertEquals(0, remaining.size(), 'ContentDocument should be deleted');
    }

    /**
     * @description Verifies that deleteFile throws an error when given a null Id.
     */
    @isTest
    static void testDeleteFile_NullId() {
        Test.startTest();
        try {
            QuoteFileUploadController.deleteFile(null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('ContentDocument Id is required'), 'Error message should mention ContentDocument Id');
        }
        Test.stopTest();
    }

    /**********************************************************************************************
     *
     * deleteAttachment Tests
     *
     ***********************************************************************************************/

    /**
     * @description Verifies that deleteAttachment removes an Attachment record.
     */
    @isTest
    static void testDeleteAttachment_Success() {
        List<Attachment> attachments = getTestAttachments();
        Id attId = attachments[0].Id;

        Test.startTest();
        QuoteFileUploadController.deleteAttachment(attId);
        Test.stopTest();

        List<Attachment> remaining = [SELECT Id FROM Attachment WHERE Id = :attId];
        System.assertEquals(0, remaining.size(), 'Attachment should be deleted');
    }

    /**
     * @description Verifies that deleteAttachment throws an error when given a null Id.
     */
    @isTest
    static void testDeleteAttachment_NullId() {
        Test.startTest();
        try {
            QuoteFileUploadController.deleteAttachment(null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Attachment Id is required'), 'Error message should mention Attachment Id');
        }
        Test.stopTest();
    }
}