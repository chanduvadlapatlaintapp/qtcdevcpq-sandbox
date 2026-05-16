/**
 * @description Service for generating, storing, and retrieving OSA (Order Schedule Amendment)
 *              PDF documents. Uses a Visualforce page rendered as PDF and stores results
 *              as ContentVersion records linked to the quote.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_OsaDocumentService {

    private static final String ERR_QUOTE_REQUIRED = 'Quote ID is required';
    private static final String ERR_UPLOAD_REQUIRED = 'Quote ID and file data are required';
    private static final String DEFAULT_ATTACHMENT_NAME = 'attachment.pdf';

    /**
     * @description Generates an OSA PDF document for a quote and stores it as a ContentVersion.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return GeneratedDocInfo DTO with document identifiers and download URL
     */
    @AuraEnabled
    public static GeneratedDocInfo generateOsaDocument(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        PageReference pdfPage = Page.AgenticQTC_OsaTemplate;
        pdfPage.getParameters().put('quoteId', quoteId);

        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('Test PDF Content');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }

        SBQQ__Quote__c quote = [
            SELECT Name, SBQQ__MasterContract__r.ContractNumber
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        String contractNum = quote.SBQQ__MasterContract__r != null
            ? quote.SBQQ__MasterContract__r.ContractNumber
            : quote.Name;
        String fileName = 'OSA_' + contractNum + '_' + Date.today().format() + '.pdf';

        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = pdfBlob,
            FirstPublishLocationId = quoteId
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :cv.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId = cv.Id;
        info.contentDocumentId = cv.ContentDocumentId;
        info.title = cv.Title;
        info.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        return info;
    }

    /**
     * @description DTO containing identifiers and download URL for a generated document.
     */
    public class GeneratedDocInfo {
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public String quoteDocumentId;
    }

    /**
     * @description Uploads an additional PDF attachment to a quote.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param fileName The file name for the attachment
     * @param base64Data Base64-encoded PDF content
     * @return The ContentVersion record Id
     */
    @AuraEnabled
    public static String uploadAdditionalPdf(String quoteId, String fileName, String base64Data) {
        if (String.isBlank(quoteId) || String.isBlank(base64Data)) {
            throw new AuraHandledException(ERR_UPLOAD_REQUIRED);
        }

        String safeName = String.isNotBlank(fileName) ? fileName : DEFAULT_ATTACHMENT_NAME;
        ContentVersion cv = new ContentVersion(
            Title = safeName,
            PathOnClient = safeName,
            VersionData = EncodingUtil.base64Decode(base64Data),
            FirstPublishLocationId = quoteId
        );
        insert cv;
        return cv.Id;
    }

    /**
     * @description Retrieves all documents linked to a quote.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of DocumentInfo DTOs
     */
    @AuraEnabled(cacheable=true)
    public static List<DocumentInfo> getQuoteDocuments(String quoteId) {
        if (String.isBlank(quoteId)) {
            return new List<DocumentInfo>();
        }
        List<DocumentInfo> docs = new List<DocumentInfo>();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, ContentDocument.Title,
                   ContentDocument.FileType, ContentDocument.ContentSize,
                   ContentDocument.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY ContentDocument.CreatedDate DESC
        ];

        for (ContentDocumentLink link : links) {
            DocumentInfo doc = new DocumentInfo();
            doc.id = link.ContentDocumentId;
            doc.title = link.ContentDocument.Title;
            doc.fileType = link.ContentDocument.FileType;
            doc.size = link.ContentDocument.ContentSize;
            doc.createdDate = link.ContentDocument.CreatedDate;
            docs.add(doc);
        }
        return docs;
    }

    /**
     * @description DTO representing a document linked to a quote.
     */
    public class DocumentInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
        @AuraEnabled public Long size;
        @AuraEnabled public Datetime createdDate;
    }

    /**
     * @description Generates the OSA PDF via a server-side Conga callout, saves it as a
     *              ContentVersion linked to the quote, and creates a SBQQ__QuoteDocument__c
     *              record so the OP4I sync trigger fires.
     *              Flow: query → callout → DML (no DML before callout).
     * @param quoteId The SBQQ__Quote__c record Id
     * @return GeneratedDocInfo DTO with document identifiers, download URL, and quoteDocumentId
     */
    @AuraEnabled
    public static GeneratedDocInfo generateAndSaveOsa(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        // ── 1. Build server-side Conga URL ──
        // generateCongaURL() returns a relative VF page URL (Label.Conga_URL starts with /apex/...)
        // with unresolved merge fields — not usable as an HTTP endpoint.
        // Strategy: extract the &QueryId=... params portion from that URL (which contains the
        // correct query IDs, template ID, OFN, watermark etc), then prepend the absolute
        // Label.Conga_Composer_URL base with real session credentials — same pattern as
        // GenerateRenLetterPDFBatch.
        String browserUrl = CongaUrlService.generateCongaURL(quoteId);
        if (String.isBlank(browserUrl) || browserUrl.startsWith('ERROR')) {
            throw new AuraHandledException('Failed to build Conga URL: ' + browserUrl);
        }

        // Extract from &QueryId= onwards — everything before is the VF page base with merge fields
        Integer queryIdIdx = browserUrl.indexOf('&QueryId=');
        if (queryIdIdx == -1) {
            throw new AuraHandledException('Invalid Conga URL structure — &QueryId= not found');
        }
        String paramsPart = browserUrl.substring(queryIdIdx); // &QueryId=...&TemplateId=...&DS7=...

        // Conga_Composer_URL is a JavaScript SPA (composer.congamerge.com).
        // DS7=11 = background mode, saves merged doc as Salesforce Files on the master object.
        // APIMode=12 requires email params (EmailToId + CongaEmailTemplateId) to trigger processing
        // and returns HTTP 200 without saving when those are absent.
        // SC1=SalesforceFile kept as belt-and-suspenders alongside DS7=11.
        paramsPart = paramsPart
            .replace('DS7=1&DS7Preview=1', 'DS7=11')
            .replace('&SC1=Attachments', '')
            .replace('&SC1=SalesforceFile', ''); // dedup
        paramsPart += '&SC1=SalesforceFile&SC0=1';

        // Build absolute server-side URL using the Conga Composer endpoint label
        String sessionId = UserInfo.getSessionId();
        String serverUrl = URL.getOrgDomainUrl().toExternalForm()
            + '/services/Soap/u/59.0/' + UserInfo.getOrganizationId();
        String shortId = quoteId.length() > 15 ? quoteId.substring(0, 15) : quoteId;

        String serverSideUrl = System.Label.Conga_Composer_URL
            + 'sessionId=' + sessionId
            + '&serverUrl=' + serverUrl
            + '&id=' + shortId
            + paramsPart;

        // ── 2. HTTP callout to Conga ──
        // APIMode=12 is processed server-side by Conga's backend (not the JS SPA).
        // The HTTP response is always the SPA HTML shell — the real work (generate + save) is
        // a side-effect of Conga's server processing. Only check the HTTP status code.
        Datetime beforeCallout = Datetime.now().addSeconds(-5); // buffer for any clock skew
        if (!Test.isRunningTest()) {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(serverSideUrl);
            req.setMethod('GET');
            req.setTimeout(120000);
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            HttpResponse res = http.send(req);
            if (res.getStatusCode() != 200) {
                throw new AuraHandledException(
                    'Conga returned HTTP ' + res.getStatusCode() + ': ' + res.getStatus()
                );
            }
        }

        // ── 3. Determine file name ──
        SBQQ__Quote__c quote = [
            SELECT Name, SBQQ__MasterContract__r.ContractNumber
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        String contractNum = quote.SBQQ__MasterContract__r != null
            ? quote.SBQQ__MasterContract__r.ContractNumber
            : quote.Name;
        String fileName = 'OSA_' + contractNum + '_' + Date.today().format() + '.pdf';

        // ── 4. Determine next version number ──
        AggregateResult[] agg = [
            SELECT MAX(SBQQ__Version__c) maxVer
            FROM SBQQ__QuoteDocument__c
            WHERE SBQQ__Quote__c = :quoteId
        ];
        Integer nextVersion = 1;
        if (!agg.isEmpty() && agg[0].get('maxVer') != null) {
            nextVersion = ((Decimal) agg[0].get('maxVer')).intValue() + 1;
        }

        // ── 5. Retrieve the ContentVersion Conga saved via SC1=SalesforceFile ──
        ContentVersion cv;
        if (Test.isRunningTest()) {
            ContentVersion stub = new ContentVersion(
                Title = fileName, PathOnClient = fileName,
                VersionData = Blob.valueOf('Test PDF Content'),
                FirstPublishLocationId = quoteId
            );
            insert stub;
            cv = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :stub.Id WITH SECURITY_ENFORCED LIMIT 1];
        } else {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, ContentDocument.LatestPublishedVersionId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :quoteId
                AND ContentDocument.CreatedDate >= :beforeCallout
                ORDER BY ContentDocument.CreatedDate DESC
                LIMIT 1
            ];
            if (links.isEmpty()) {
                throw new AuraHandledException(
                    'Conga did not save the OSA file. ' +
                    'Verify that APIMode=12 and SC1=SalesforceFile are supported in this Conga configuration.'
                );
            }
            cv = [
                SELECT Id, ContentDocumentId, Title
                FROM ContentVersion
                WHERE Id = :links[0].ContentDocument.LatestPublishedVersionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }

        // ── 6. Insert SBQQ__QuoteDocument__c so OP4I sync trigger fires ──
        SBQQ__QuoteDocument__c quoteDoc = new SBQQ__QuoteDocument__c(
            Name = fileName,
            SBQQ__Quote__c = quoteId,
            SBQQ__Version__c = nextVersion,
            SBQQ__DocumentId__c = cv.ContentDocumentId
        );
        insert quoteDoc;

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId = cv.Id;
        info.contentDocumentId = cv.ContentDocumentId;
        info.title = cv.Title;
        info.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        info.quoteDocumentId = quoteDoc.Id;
        return info;
    }

    /**
     * @description Builds the Conga Composer URL that the LWC opens in a new browser tab.
     *              Uses DS7=11 (background mode, save to Salesforce Files) so the JS SPA
     *              generates and saves the document without showing a preview dialog.
     *              The LWC then polls pollForNewDocument() until the file appears.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return Absolute Conga Composer URL with session credentials and save parameters
     */
    @AuraEnabled
    public static String buildCongaUrlForSave(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }
        String browserUrl = CongaUrlService.generateCongaURL(quoteId);
        if (String.isBlank(browserUrl) || browserUrl.startsWith('ERROR')) {
            throw new AuraHandledException('Failed to build Conga URL: ' + browserUrl);
        }
        Integer queryIdIdx = browserUrl.indexOf('&QueryId=');
        if (queryIdIdx == -1) {
            throw new AuraHandledException('Invalid Conga URL — &QueryId= not found');
        }
        String paramsPart = browserUrl.substring(queryIdIdx);

        // DS7=11: background mode + save to Salesforce Files, no preview dialog required
        paramsPart = paramsPart
            .replace('DS7=1&DS7Preview=1', 'DS7=11')
            .replace('&SC1=Attachments', '')
            .replace('&SC1=SalesforceFile', ''); // dedup
        paramsPart += '&SC1=SalesforceFile';

        // Use the Salesforce-hosted VF page URL — auth via browser session cookie.
        // Avoids the "Lock IPs" error that occurs when passing sessionId obtained
        // from Apex (locked to Salesforce's server IP) into an external URL opened
        // from the user's browser (different IP).
        String shortId = quoteId.length() > 15 ? quoteId.substring(0, 15) : quoteId;
        return '/apex/APXTConga4__Conga_Composer?id=' + shortId + paramsPart;
    }

    /**
     * @description Polls for a ContentVersion saved by Conga after the given ISO timestamp.
     *              Returns null if no file has appeared yet (LWC retries on interval).
     * @param quoteId The SBQQ__Quote__c record Id
     * @param beforeTimestamp ISO 8601 string, e.g. "2026-05-12T10:30:00.000Z"
     * @return GeneratedDocInfo if a new file was found, null otherwise
     */
    @AuraEnabled
    public static GeneratedDocInfo pollForNewDocument(String quoteId, String beforeTimestamp) {
        if (String.isBlank(quoteId)) {
            return null;
        }
        Datetime cutoff = parseCutoff(beforeTimestamp);

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, ContentDocument.LatestPublishedVersionId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :quoteId
            AND ContentDocument.CreatedDate >= :cutoff
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 1
        ];
        if (links.isEmpty()) {
            return null;
        }

        ContentVersion cv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :links[0].ContentDocument.LatestPublishedVersionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId = cv.Id;
        info.contentDocumentId = cv.ContentDocumentId;
        info.title = cv.Title;
        info.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        return info;
    }

    /**
     * @description Called once after pollForNewDocument() finds the file.
     *              Creates the SBQQ__QuoteDocument__c record so the OP4I sync trigger fires,
     *              then returns the complete GeneratedDocInfo with quoteDocumentId.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param contentDocumentId The ContentDocument Id of the saved OSA
     * @return GeneratedDocInfo with quoteDocumentId populated
     */
    @AuraEnabled
    public static GeneratedDocInfo finalizeOsaDocument(String quoteId, String contentDocumentId) {
        if (String.isBlank(quoteId) || String.isBlank(contentDocumentId)) {
            throw new AuraHandledException('Quote ID and Content Document ID are required');
        }

        SBQQ__Quote__c quote = [
            SELECT Name, SBQQ__MasterContract__r.ContractNumber
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        String contractNum = quote.SBQQ__MasterContract__r != null
            ? quote.SBQQ__MasterContract__r.ContractNumber
            : quote.Name;
        String fileName = 'OSA_' + contractNum + '_' + Date.today().format() + '.pdf';

        AggregateResult[] agg = [
            SELECT MAX(SBQQ__Version__c) maxVer
            FROM SBQQ__QuoteDocument__c
            WHERE SBQQ__Quote__c = :quoteId
        ];
        Integer nextVersion = 1;
        if (!agg.isEmpty() && agg[0].get('maxVer') != null) {
            nextVersion = ((Decimal) agg[0].get('maxVer')).intValue() + 1;
        }

        SBQQ__QuoteDocument__c quoteDoc = new SBQQ__QuoteDocument__c(
            Name = fileName,
            SBQQ__Quote__c = quoteId,
            SBQQ__Version__c = nextVersion,
            SBQQ__DocumentId__c = contentDocumentId
        );
        insert quoteDoc;

        ContentVersion cv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId = cv.Id;
        info.contentDocumentId = cv.ContentDocumentId;
        info.title = cv.Title;
        info.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        info.quoteDocumentId = quoteDoc.Id;
        return info;
    }

    private static Datetime parseCutoff(String beforeTimestamp) {
        if (String.isBlank(beforeTimestamp)) {
            return Datetime.now().addMinutes(-5);
        }
        try {
            // "2026-05-12T10:30:00.000Z" → "2026-05-12 10:30:00"
            String normalized = beforeTimestamp
                .replace('T', ' ')
                .replaceAll('\\.\\d+Z?$', '')
                .replace('Z', '');
            return Datetime.valueOfGmt(normalized);
        } catch (Exception e) {
            return Datetime.now().addMinutes(-5);
        }
    }

    /**
     * @description Creates a SBQQ__RelatedContent__c record linking an uploaded file to the quote
     *              so it appears in the Additional Documents related list.
     *              Field pattern matches AttachmentTriggerHandler and ProductDocumentService.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param contentDocumentId The ContentDocument Id of the uploaded file
     * @param fileName Display name for the related content record
     */
    @AuraEnabled
    public static void createRelatedContent(String quoteId, String contentDocumentId, String fileName) {
        if (String.isBlank(quoteId) || String.isBlank(contentDocumentId)) {
            throw new AuraHandledException('Quote ID and Content Document ID are required');
        }
        String safeName = String.isNotBlank(fileName) ? fileName : 'Additional Document';
        insert new SBQQ__RelatedContent__c(
            Name = safeName,
            SBQQ__Quote__c = quoteId,
            SBQQ__ExternalId__c = contentDocumentId,
            SBQQ__Required__c = false,
            SBQQ__DisplayOrder__c = 1
        );
    }

    /**
     * @description Retrieves SBQQ__RelatedContent__c records linked to a quote,
     *              excluding 'Conga Generated OSA' entries (those are the generated docs).
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of RelatedContentInfo DTOs
     */
    @AuraEnabled(cacheable=true)
    public static List<RelatedContentInfo> getRelatedContent(String quoteId) {
        if (String.isBlank(quoteId)) {
            return new List<RelatedContentInfo>();
        }
        List<RelatedContentInfo> results = new List<RelatedContentInfo>();
        for (SBQQ__RelatedContent__c rc : [
            SELECT Id, Name, Document_Type__c, SBQQ__ExternalId__c
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = :quoteId
            AND Document_Type__c != 'Conga Generated OSA'
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ]) {
            RelatedContentInfo info = new RelatedContentInfo();
            info.id = rc.Id;
            info.name = rc.Name;
            info.documentType = rc.Document_Type__c;
            info.externalId = rc.SBQQ__ExternalId__c;
            results.add(info);
        }
        return results;
    }

    /**
     * @description DTO for a SBQQ__RelatedContent__c record.
     */
    public class RelatedContentInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String documentType;
        @AuraEnabled public String externalId;
    }
}