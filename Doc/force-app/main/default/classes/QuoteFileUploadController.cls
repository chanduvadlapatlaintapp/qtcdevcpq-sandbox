/**
 * @author  Sahal Mohamed
 * @date    02/17/2026
 * @description Controller for the quoteFileList and quoteFileUploadModal LWC components.
 *              Provides methods to query files (ContentVersion + Attachment) linked to a Quote,
 *              stamp Document_Type__c on ContentVersion records after upload, edit file details,
 *              and delete files/attachments.
 * @jira    BIZ-79176
 */
public with sharing class QuoteFileUploadController {

    /**********************************************************************************************
     *
     * Wrapper Classes
     *
     ***********************************************************************************************/

    /**
     * @description Unified wrapper that normalizes ContentVersion and Attachment records
     *              into a single structure for the quoteFileList LWC.
     */
    public class FileWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String fileType;
        @AuraEnabled public Decimal contentSize;
        @AuraEnabled public String documentType;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String source;
        @AuraEnabled public String downloadUrl;
    }

    /**********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Fetches all files linked to a given Quote -- both modern ContentVersion records
     *              (via ContentDocumentLink) and classic Attachment records (via ParentId).
     *              Returns a unified list of FileWrapper sorted by CreatedDate descending.
     * @param quoteId The Id of the Quote (SBQQ__Quote__c) record.
     * @return List of FileWrapper records combining both sources.
     */
    @AuraEnabled(cacheable=true)
    public static List<FileWrapper> getQuoteFiles(Id quoteId) {
        if (quoteId == null) {
            throwAuraException('Quote Id is required.');
        }

        List<FileWrapper> allFiles = new List<FileWrapper>();

        // ---- ContentVersion files (modern Files) ----
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :quoteId
        ];

        if (!links.isEmpty()) {
            Set<Id> docIds = Pluck.ids('ContentDocumentId', links);

            List<ContentVersion> versions = [
                SELECT Id,
                       Title,
                       FileExtension,
                       FileType,
                       ContentSize,
                       Document_Type__c,
                       CreatedDate,
                       CreatedBy.Name,
                       ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                  AND IsLatest = true
                ORDER BY CreatedDate DESC
            ];

            for (ContentVersion cv : versions) {
                FileWrapper fw = new FileWrapper();
                fw.id = cv.Id;
                fw.title = cv.Title;
                fw.fileExtension = cv.FileExtension;
                fw.fileType = cv.FileType;
                fw.contentSize = cv.ContentSize;
                fw.documentType = cv.Document_Type__c;
                fw.createdDate = cv.CreatedDate;
                fw.createdByName = cv.CreatedBy != null ? cv.CreatedBy.Name : '';
                fw.contentDocumentId = cv.ContentDocumentId;
                fw.source = 'ContentVersion';
                fw.downloadUrl = '/sfc/servlet.shepherd/document/download/' + cv.ContentDocumentId;
                allFiles.add(fw);
            }
        }

        // ---- Classic Attachment records ----
        List<Attachment> attachments = [
            SELECT Id,
                   Name,
                   ContentType,
                   BodyLength,
                   CreatedDate,
                   CreatedBy.Name
            FROM Attachment
            WHERE ParentId = :quoteId
            ORDER BY CreatedDate DESC
        ];

        for (Attachment att : attachments) {
            FileWrapper fw = new FileWrapper();
            fw.id = att.Id;
            fw.title = att.Name;
            fw.fileExtension = extractExtension(att.Name);
            fw.fileType = att.ContentType != null ? att.ContentType.toUpperCase() : '';
            fw.contentSize = att.BodyLength;
            fw.documentType = null;
            fw.createdDate = att.CreatedDate;
            fw.createdByName = att.CreatedBy != null ? att.CreatedBy.Name : '';
            fw.contentDocumentId = null;
            fw.source = 'Attachment';
            fw.downloadUrl = '/servlet/servlet.FileDownload?file=' + att.Id + '&operationContext=S1';
            allFiles.add(fw);
        }

        // Sort combined list by createdDate descending
        allFiles.sort(new FileWrapperDateComparator());

        return allFiles;
    }

    /**
     * @description Stamps the Document_Type__c field on ContentVersion records after file upload.
     *              Called from the upload modal after lightning-file-upload completes.
     * @param contentDocumentIds List of ContentDocument Ids from the upload event.
     * @param documentType The picklist value to stamp on Document_Type__c.
     */
    @AuraEnabled
    public static void updateDocumentType(List<Id> contentDocumentIds, String documentType) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throwAuraException('No file Ids provided.');
        }
        if (String.isBlank(documentType)) {
            throwAuraException('Document Type is required.');
        }

        List<ContentVersion> versions = [
            SELECT Id, Document_Type__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
              AND IsLatest = true
        ];

        if (versions.isEmpty()) {
            throwAuraException('No ContentVersion records found for the uploaded files.');
        }

        for (ContentVersion cv : versions) {
            cv.Document_Type__c = documentType;
        }

        try {
            update versions;
        } catch (DmlException e) {
            throwAuraException('Failed to update Document Type: ' + e.getMessage());
        }
    }

    /**
     * @description Updates the Title and/or Document_Type__c on a ContentVersion record.
     *              Called from the edit modal in the quoteFileList component.
     * @param contentVersionId The Id of the ContentVersion record to update.
     * @param title The new file title.
     * @param documentType The new Document_Type__c picklist value.
     */
    @AuraEnabled
    public static void updateFileDetails(Id contentVersionId, String title, String documentType) {
        if (contentVersionId == null) {
            throwAuraException('ContentVersion Id is required.');
        }
        if (String.isBlank(title)) {
            throwAuraException('Title is required.');
        }
        if (String.isBlank(documentType)) {
            throwAuraException('Document Type is required.');
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, Document_Type__c
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            throwAuraException('File not found.');
        }

        ContentVersion cv = versions[0];
        cv.Title = title;
        cv.Document_Type__c = documentType;

        try {
            update cv;
        } catch (DmlException e) {
            throwAuraException('Failed to update file details: ' + e.getMessage());
        }
    }

    /**
     * @description Deletes a ContentDocument record. This cascades to delete all
     *              ContentVersion and ContentDocumentLink records associated with it.
     *              Blocked when the linked quote is in Contract Executed status.
     * @param contentDocumentId The Id of the ContentDocument to delete.
     */
    @AuraEnabled
    public static void deleteFile(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throwAuraException('ContentDocument Id is required.');
        }

        // Guard: block deletion when the linked quote is Contract Executed.
        // LinkedEntity.Type cannot be used as a SOQL filter on ContentDocumentLink,
        // so retrieve all links and identify the Quote link in Apex.
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
        ];
        Id linkedQuoteId;
        for (ContentDocumentLink cdl : links) {
            if (cdl.LinkedEntityId != null
                    && cdl.LinkedEntityId.getSObjectType() == SBQQ__Quote__c.SObjectType) {
                linkedQuoteId = cdl.LinkedEntityId;
                break;
            }
        }
        if (linkedQuoteId != null) {
            List<SBQQ__Quote__c> quotes = [
                SELECT Quote_Stage__c
                FROM SBQQ__Quote__c
                WHERE Id = :linkedQuoteId
                LIMIT 1
            ];
            if (!quotes.isEmpty() && quotes[0].Quote_Stage__c == QuoteConstants.STATUS_CONTRACT_EXECUTED) {
                throwAuraException('Files cannot be deleted from a Contract Executed quote.');
            }
        }

        try {
            ContentDocument doc = [
                SELECT Id FROM ContentDocument WHERE Id = :contentDocumentId LIMIT 1
            ];
            delete doc;
        } catch (QueryException e) {
            throwAuraException('File not found or already deleted.');
        } catch (DmlException e) {
            throwAuraException('Failed to delete file: ' + e.getMessage());
        }
    }

    /**
     * @description Deletes a classic Attachment record.
     *              Blocked when the parent quote is in Contract Executed status.
     * @param attachmentId The Id of the Attachment to delete.
     */
    @AuraEnabled
    public static void deleteAttachment(Id attachmentId) {
        if (attachmentId == null) {
            throwAuraException('Attachment Id is required.');
        }

        // Guard: block deletion when the parent quote is Contract Executed.
        // Fetch ParentId up front so we avoid a second query later.
        Attachment attForCheck;
        try {
            attForCheck = [SELECT Id, ParentId FROM Attachment WHERE Id = :attachmentId LIMIT 1];
        } catch (QueryException e) {
            throwAuraException('Attachment not found or already deleted.');
        }

        if (attForCheck.ParentId != null) {
            List<SBQQ__Quote__c> quotes = [
                SELECT Quote_Stage__c
                FROM SBQQ__Quote__c
                WHERE Id = :attForCheck.ParentId
                LIMIT 1
            ];
            if (!quotes.isEmpty() && quotes[0].Quote_Stage__c == QuoteConstants.STATUS_CONTRACT_EXECUTED) {
                throwAuraException('Attachments cannot be deleted from a Contract Executed quote.');
            }
        }

        try {
            delete attForCheck;
        } catch (DmlException e) {
            throwAuraException('Failed to delete attachment: ' + e.getMessage());
        }
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Extracts the file extension from a filename string.
     * @param fileName The full file name (e.g. 'document.pdf').
     * @return The extension without the dot (e.g. 'pdf'), or empty string if none.
     */
    private static String extractExtension(String fileName) {
        if (String.isBlank(fileName) || !fileName.contains('.')) {
            return '';
        }
        return fileName.substringAfterLast('.');
    }

    /**
     * @description Creates and throws an AuraHandledException with a message that is
     *              properly accessible via getMessage() in test context.
     *              Works around the known Salesforce issue where AuraHandledException
     *              returns 'Script-thrown exception' from getMessage() in tests.
     * @param message The error message.
     */
    private static void throwAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        throw e;
    }

    /**********************************************************************************************
     *
     * Inner Classes
     *
     ***********************************************************************************************/

    /**
     * @description Comparator to sort FileWrapper records by createdDate descending.
     */
    private class FileWrapperDateComparator implements Comparator<FileWrapper> {
        public Integer compare(FileWrapper a, FileWrapper b) {
            if (a.createdDate == null && b.createdDate == null) {
                return 0;
            }
            if (a.createdDate == null) {
                return 1;
            }
            if (b.createdDate == null) {
                return -1;
            }
            // Descending order
            if (b.createdDate > a.createdDate) {
                return 1;
            }
            if (b.createdDate < a.createdDate) {
                return -1;
            }
            return 0;
        }
    }
}