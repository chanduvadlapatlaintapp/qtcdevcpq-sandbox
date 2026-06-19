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

    // ─── Native PDF (Generate PDF — Instant) ──────────────────────────────────
    //
    // Browser-merge flow driven by the LWC:
    //   1. renderInstantPdfBytes — Apex renders the VF page to a base64 PDF + metadata.
    //   2. <browser-side merge>  — LWC uses pdf-lib to append every uploaded attachment
    //                              in user-chosen DisplayOrder.
    //   3. saveMergedInstantPdf — Apex persists the merged blob as ContentVersion + QuoteDoc.

    /**
     * @description Renders the OSA Visualforce page to a PDF and returns the bytes as
     *              base64 so the LWC can hand them to pdf-lib for browser-side merging.
     *              Also returns the next QuoteDocument version + standard file name so the
     *              follow-up save call doesn't need a second SOQL.
     */
    @AuraEnabled
    public static InstantPdfRender renderInstantPdfBytes(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        SBQQ__Quote__c quote = [
            SELECT Name,
                   SBQQ__Account__r.Name,
                   SBQQ__MasterContract__r.ContractNumber
            FROM   SBQQ__Quote__c
            WHERE  Id = :quoteId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        String contractNum = quote.SBQQ__MasterContract__r != null
            ? quote.SBQQ__MasterContract__r.ContractNumber
            : quote.Name;
        String safeAccount = String.isNotBlank(quote.SBQQ__Account__r?.Name)
            ? quote.SBQQ__Account__r.Name.replaceAll('[^a-zA-Z0-9 ]', '').trim().replace(' ', '_')
            : '';

        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('%PDF-1.4 test-native-pdf-content');
        } else {
            PageReference pdfPage = Page.AgenticQTC_OsaDocument;
            pdfPage.getParameters().put('quoteId', quoteId);
            pdfBlob = pdfPage.getContentAsPDF();
        }

        InstantPdfRender result = new InstantPdfRender();
        result.base64Pdf   = EncodingUtil.base64Encode(pdfBlob);
        result.fileName    = buildOsaFileName(contractNum, safeAccount);
        result.nextVersion = getNextQuoteDocVersion(quoteId);
        return result;
    }

    /**
     * @description Persists a merged PDF (OSA + appended uploads) produced by the LWC via
     *              pdf-lib. Creates a ContentVersion linked to the quote and a
     *              SBQQ__QuoteDocument__c row so the OP4I sync trigger fires.
     *
     * @param quoteId        Quote Id the merged PDF belongs to.
     * @param base64Pdf      Base64-encoded bytes of the merged PDF from pdf-lib.
     * @param fileName       File name produced by renderInstantPdfBytes.
     * @param versionNumber  Next QuoteDocument version from renderInstantPdfBytes.
     */
    @AuraEnabled
    public static GeneratedDocInfo saveMergedInstantPdf(String quoteId, String base64Pdf, String fileName, Integer versionNumber) {
        if (String.isBlank(quoteId) || String.isBlank(base64Pdf)) {
            throw new AuraHandledException('Quote ID and merged PDF data are required');
        }
        String safeName = String.isNotBlank(fileName)
            ? fileName
            : ('OSA_' + Date.today().format().replace('/', '-') + '.pdf');
        Integer ver = (versionNumber != null) ? versionNumber : getNextQuoteDocVersion(quoteId);

        Blob mergedBlob = EncodingUtil.base64Decode(base64Pdf);

        // Keep the File for the LWC's own preview/download (filePreview + Shepherd URL).
        ContentVersion cv = new ContentVersion(
            Title                  = safeName,
            PathOnClient           = safeName,
            VersionData            = mergedBlob,
            FirstPublishLocationId = quoteId
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId, Title
            FROM   ContentVersion
            WHERE  Id = :cv.Id
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        // Back SBQQ__DocumentId__c with a classic Document (015) so the View button and OP4I
        // sync work — a ContentDocument (069) is served by neither. BIZ-81419
        Id legacyDocId = createPdfDocument(safeName, mergedBlob);

        SBQQ__QuoteDocument__c quoteDoc = new SBQQ__QuoteDocument__c(
            Name                = safeName,
            SBQQ__Quote__c      = quoteId,
            SBQQ__Version__c    = ver,
            SBQQ__DocumentId__c = legacyDocId
        );
        insert quoteDoc;

        // Rename the QuoteDocument, its File, and the classic Document to the standard OSA
        // convention held in CustomName__c (YYYYMMDD_Bundle#<OSA>_<LOB>_<Account>[_v<n>], using
        // the Quote Expiration date). The provisional name above is only a fallback. BIZ-83515
        String standardName = applyStandardOsaName(quoteDoc.Id, cv.Id, legacyDocId);

        // If the quote is already approved, stamp this doc Approved (separate update) so
        // publishApprovedOSA fires the OnePlace publish now. Quotes still pending approval are
        // stamped by the Quote_After_Insert_Update flow when ApprovalStatus__c flips. BIZ-81419
        stampApprovedIfQuoteApproved(quoteDoc.Id, quoteId);

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId  = cv.Id;
        info.contentDocumentId = cv.ContentDocumentId;
        info.title             = String.isNotBlank(standardName) ? standardName : cv.Title;
        info.downloadUrl       = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        info.legacyDocumentId  = legacyDocId;
        info.quoteDocumentId   = quoteDoc.Id;
        return info;
    }

    /**
     * @description Carries the rendered OSA bytes plus the file-naming context the LWC
     *              needs to send back to saveMergedInstantPdf without a second SOQL.
     */
    public class InstantPdfRender {
        @AuraEnabled public String  base64Pdf;
        @AuraEnabled public String  fileName;
        @AuraEnabled public Integer nextVersion;
    }

    /**
     * @description Returns the binary contents of a ContentVersion as a base64 string so the
     *              LWC can hand the bytes to pdf-lib for merging without doing a browser
     *              fetch (which can hit CORS / content-domain redirects in some sessions).
     *              One Apex call per upload — each runs in its own 6 MB heap, so individually
     *              large attachments still fit.
     */
    @AuraEnabled
    public static String getContentVersionBase64(String contentVersionId) {
        if (String.isBlank(contentVersionId)) {
            throw new AuraHandledException('ContentVersion Id is required');
        }
        List<ContentVersion> rows = [
            SELECT VersionData
            FROM   ContentVersion
            WHERE  Id = :contentVersionId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        if (rows.isEmpty() || rows[0].VersionData == null) {
            return null;
        }
        return EncodingUtil.base64Encode(rows[0].VersionData);
    }

    // ─── Conga path: cover-page prepend ──────────────────────────────────────
    //
    // The Conga-generated OSA is missing the "OSA First Page" cover (Instructions
    // + Contact / Software Delivery / Invoicing tables). Rather than edit the
    // Conga template itself, we render a cover-only PDF here and the LWC uses
    // pdf-lib to prepend it to the Conga output, then ships the merged bytes
    // back to replaceCongaWithMergedPdf — same browser-merge pattern that the
    // Instant PDF path already uses for uploaded attachments.

    /**
     * @description Renders the AgenticQTC_OsaDocument VF page with `coverOnly=true`
     *              so the controller emits ONLY the SBQQ "OSA First Page" cover
     *              block. Returns the PDF bytes as base64 for the LWC to feed
     *              into pdf-lib alongside the Conga-saved file.
     */
    @AuraEnabled
    public static String renderCoverPdfBytes(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('%PDF-1.4 test-cover-pdf-content');
        } else {
            PageReference pdfPage = Page.AgenticQTC_OsaDocument;
            pdfPage.getParameters().put('quoteId', quoteId);
            pdfPage.getParameters().put('coverOnly', 'true');
            pdfBlob = pdfPage.getContentAsPDF();
        }
        return EncodingUtil.base64Encode(pdfBlob);
    }

    /**
     * @description Replaces the Conga-generated file with a merged PDF (cover + Conga
     *              output) produced by the LWC. Adds a new ContentVersion to the
     *              existing ContentDocument so the SBQQ__QuoteDocument__c row keeps
     *              pointing at the same ContentDocumentId — no QuoteDoc update needed.
     *
     * @param contentDocumentId  ContentDocumentId that Conga published (from finalizeOsaDocument).
     * @param base64Pdf          Base64-encoded merged PDF (cover prepended to Conga output).
     * @param legacyDocumentId   Id of the classic Document (015) backing SBQQ__DocumentId__c
     *                           (from finalizeOsaDocument). Its body is refreshed with the final
     *                           merged PDF so the View button + OP4I get the cover too. Optional —
     *                           when blank, only the File is updated. BIZ-81419
     * @return GeneratedDocInfo  Updated DTO pointing at the new ContentVersion's downloadUrl.
     */
    @AuraEnabled
    public static GeneratedDocInfo replaceCongaWithMergedPdf(String contentDocumentId, String base64Pdf, String legacyDocumentId) {
        if (String.isBlank(contentDocumentId) || String.isBlank(base64Pdf)) {
            throw new AuraHandledException('ContentDocument Id and merged PDF data are required');
        }

        // Reuse the existing document's title + path so the new version keeps
        // the same display name in Salesforce Files.
        List<ContentVersion> existing = [
            SELECT Title, PathOnClient
            FROM   ContentVersion
            WHERE  ContentDocumentId = :contentDocumentId
            AND    IsLatest = true
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        if (existing.isEmpty()) {
            throw new AuraHandledException('Could not find ContentVersion for the Conga document');
        }

        Blob mergedBlob = EncodingUtil.base64Decode(base64Pdf);

        ContentVersion newCv = new ContentVersion(
            ContentDocumentId = contentDocumentId,
            Title             = existing[0].Title,
            PathOnClient      = String.isNotBlank(existing[0].PathOnClient) ? existing[0].PathOnClient : existing[0].Title,
            VersionData       = mergedBlob,
            ReasonForChange   = 'Prepended OSA First Page cover'
        );
        insert newCv;

        // Refresh the classic Document (View button + OP4I source) with the final merged PDF
        // so those consumers get the cover + attachments, not just Conga's raw OSA. BIZ-81419
        if (String.isNotBlank(legacyDocumentId) && ((String) legacyDocumentId).startsWith('015')) {
            update new Document(Id = (Id) legacyDocumentId, Body = mergedBlob);
        }

        newCv = [
            SELECT Id, ContentDocumentId, Title
            FROM   ContentVersion
            WHERE  Id = :newCv.Id
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId  = newCv.Id;
        info.contentDocumentId = newCv.ContentDocumentId;
        info.title             = newCv.Title;
        info.downloadUrl       = '/sfc/servlet.shepherd/version/download/' + newCv.Id;
        info.legacyDocumentId  = legacyDocumentId;
        return info;
    }

    // ─── Shared private helpers ────────────────────────────────────────────────

    /**
     * @description Builds a standardised OSA file name.
     *              Format: OSA_<contractNum>_<safeAccountName>_<today>.pdf
     */
    private static String buildOsaFileName(String contractNum, String safeAccount) {
        String dateStr = Date.today().format().replace('/', '-');
        return 'OSA_' + contractNum
            + (String.isNotBlank(safeAccount) ? '_' + safeAccount : '')
            + '_' + dateStr + '.pdf';
    }

    /**
     * @description Returns the next sequential SBQQ__QuoteDocument__c version number
     *              for the given quote (max existing version + 1, defaults to 1).
     */
    private static Integer getNextQuoteDocVersion(String quoteId) {
        AggregateResult[] agg = [
            SELECT MAX(SBQQ__Version__c) maxVer
            FROM   SBQQ__QuoteDocument__c
            WHERE  SBQQ__Quote__c = :quoteId
        ];
        if (!agg.isEmpty() && agg[0].get('maxVer') != null) {
            return ((Decimal) agg[0].get('maxVer')).intValue() + 1;
        }
        return 1;
    }

    /**
     * @description Stores a PDF as a classic Document (015) in the running user's personal
     *              documents folder — the same storage standard CPQ uses for generated quote
     *              documents (FolderId = the author's User Id).
     *
     *              SBQQ__QuoteDocument__c.SBQQ__DocumentId__c MUST reference a Document (015) or
     *              Attachment (00P), not a ContentDocument File (069): the managed "View" button
     *              downloads it through /servlet/servlet.FileDownload (which cannot serve a 069
     *              File), and the OP4I integration likewise retrieves the PDF from this record.
     *              Pointing the field at a 069 File breaks both — see BIZ-81419.
     * @param fileName Display name for the Document (Document.Name max 255).
     * @param pdfBlob  PDF bytes to store.
     * @return Id of the inserted Document.
     */
    private static Id createPdfDocument(String fileName, Blob pdfBlob) {
        Document doc = new Document(
            Name        = fileName,
            FolderId    = UserInfo.getUserId(), // running user's personal documents folder
            Body        = pdfBlob,
            Type        = 'pdf',
            ContentType = 'application/pdf',
            IsPublic    = false
        );
        insert doc;
        return doc.Id;
    }

    /**
     * @description Renames a freshly-inserted OSA QuoteDocument — and its backing File
     *              (ContentVersion 069) and classic Document (015) — to the standard OSA
     *              naming convention held in the QuoteDocument's CustomName__c formula:
     *              YYYYMMDD_Bundle#<OSA_Number>_<LineOfBusiness>_<AccountShortName>[_v<Version>],
     *              where YYYYMMDD is the Quote Expiration Date.
     *
     *              CustomName__c is the single source of truth for this convention (the same
     *              value the standard Conga OFN mirrors), but a formula can only be read once
     *              the QuoteDocument exists — so the record is created with a provisional
     *              "OSA_<contract>_<date>" name and renamed here. No-ops when CustomName__c is
     *              blank (e.g. the quote is missing the fields the formula needs) so a
     *              half-formed name never overwrites the provisional one, and the whole step is
     *              best-effort: a rename failure is logged but never blocks document generation.
     *              Name is capped at Quote_Document_Name_Max_Length (72) — the same limit the
     *              QuoteDocument trigger enforces and Conga's OFN truncates to. BIZ-83515
     *
     * @param quoteDocId        Id of the just-inserted SBQQ__QuoteDocument__c.
     * @param contentVersionId  ContentVersion (069 File) to rename, or null to skip.
     * @param legacyDocumentId  Classic Document (015) to rename, or null to skip.
     * @return The applied file name (CustomName + '.pdf'), or null when no rename happened.
     */
    private static String applyStandardOsaName(Id quoteDocId, Id contentVersionId, Id legacyDocumentId) {
        try {
            // Read the formula back from the row we just inserted. SECURITY_ENFORCED is omitted
            // intentionally: this is an internal rename of a record created in this same
            // transaction, and a missing FLS grant on the formula must degrade to "keep the
            // provisional name", not throw — the try/catch below guarantees that.
            SBQQ__QuoteDocument__c qd = [
                SELECT Id, Name, CustomName__c, SBQQ__Quote__r.SBQQ__ExpirationDate__c
                FROM   SBQQ__QuoteDocument__c
                WHERE  Id = :quoteDocId
                LIMIT  1
            ];
            // The convention is anchored on a leading YYYYMMDD taken from the Quote Expiration
            // Date. With no expiration date the CustomName__c formula collapses to a date-less
            // "_Bundle#..." scaffold — keep the readable provisional name in that case rather
            // than stamp an incomplete one. BIZ-83515
            if (String.isBlank(qd.CustomName__c) || qd.SBQQ__Quote__r.SBQQ__ExpirationDate__c == null) {
                return null;
            }

            Integer maxLen = Integer.valueOf(Label.Quote_Document_Name_Max_Length);
            String docName = qd.CustomName__c.length() > maxLen
                ? qd.CustomName__c.substring(0, maxLen)
                : qd.CustomName__c;
            String fileName = docName + '.pdf';

            if (qd.Name != docName) {
                update new SBQQ__QuoteDocument__c(Id = quoteDocId, Name = docName);
            }
            if (contentVersionId != null) {
                update new ContentVersion(Id = contentVersionId, Title = fileName, PathOnClient = fileName);
            }
            if (legacyDocumentId != null) {
                update new Document(Id = legacyDocumentId, Name = fileName);
            }
            return fileName;
        } catch (Exception e) {
            Nebula.Logger.warn('AgenticQTC_OsaDocumentService.applyStandardOsaName failed for QuoteDocument '
                + quoteDocId + ': ' + e.getMessage());
            Nebula.Logger.saveLog();
            return null;
        }
    }

    /**
     * @description When the parent quote is already Approved, stamps the freshly-created
     *              QuoteDocument's Quote_ApprovalStatus__c to 'Approved'. This MUST be a
     *              separate update (QuoteDocumentTriggerHelper.publishApprovedOSA runs on
     *              afterUpdate only), which fires the DealEvent__e so OnePlace returns the
     *              document id. Quotes still pending approval are stamped later by the
     *              Quote_After_Insert_Update flow when ApprovalStatus__c transitions to
     *              Approved, so they are intentionally skipped here. BIZ-81419
     * @param quoteDocId The newly inserted SBQQ__QuoteDocument__c Id
     * @param quoteId    The parent SBQQ__Quote__c Id
     */
    private static void stampApprovedIfQuoteApproved(Id quoteDocId, Id quoteId) {
        if (quoteDocId == null || quoteId == null) {
            return;
        }
        List<SBQQ__Quote__c> quotes = [
            SELECT Id, ApprovalStatus__c
            FROM   SBQQ__Quote__c
            WHERE  Id = :quoteId
            LIMIT  1
        ];
        if (quotes.isEmpty() || quotes[0].ApprovalStatus__c != QuoteConstants.STATUS_APPROVED) {
            return;
        }
        update new SBQQ__QuoteDocument__c(
            Id                      = quoteDocId,
            Quote_ApprovalStatus__c = QuoteConstants.STATUS_APPROVED
        );
    }

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
        // Id of the classic Document (015) that backs SBQQ__DocumentId__c. The browser-merge
        // (cover-prepend) step passes this back so the Document can be refreshed with the
        // final merged PDF. BIZ-81419
        @AuraEnabled public String legacyDocumentId;
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
            cv = [SELECT Id, ContentDocumentId, Title, VersionData FROM ContentVersion WHERE Id = :stub.Id WITH SECURITY_ENFORCED LIMIT 1];
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
                SELECT Id, ContentDocumentId, Title, VersionData
                FROM ContentVersion
                WHERE Id = :links[0].ContentDocument.LatestPublishedVersionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }

        // ── 6. Insert SBQQ__QuoteDocument__c so OP4I sync trigger fires ──
        // Point SBQQ__DocumentId__c at a classic Document (015), not the ContentDocument (069):
        // the View button and OP4I both fail to retrieve a 069 File. BIZ-81419
        Id legacyDocId = createPdfDocument(fileName, cv.VersionData);

        SBQQ__QuoteDocument__c quoteDoc = new SBQQ__QuoteDocument__c(
            Name = fileName,
            SBQQ__Quote__c = quoteId,
            SBQQ__Version__c = nextVersion,
            SBQQ__DocumentId__c = legacyDocId
        );
        insert quoteDoc;

        // Rename the QuoteDocument, its File, and the classic Document to the standard OSA
        // convention held in CustomName__c (YYYYMMDD_Bundle#<OSA>_<LOB>_<Account>[_v<n>], using
        // the Quote Expiration date). The provisional name above is only a fallback. BIZ-83515
        String standardName = applyStandardOsaName(quoteDoc.Id, cv.Id, legacyDocId);

        // If the quote is already approved, stamp this doc Approved (separate update) so
        // publishApprovedOSA fires the OnePlace publish now. Quotes still pending approval are
        // stamped by the Quote_After_Insert_Update flow when ApprovalStatus__c flips. BIZ-81419
        stampApprovedIfQuoteApproved(quoteDoc.Id, quoteId);

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId = cv.Id;
        info.contentDocumentId = cv.ContentDocumentId;
        info.title = String.isNotBlank(standardName) ? standardName : cv.Title;
        info.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        info.quoteDocumentId = quoteDoc.Id;
        info.legacyDocumentId = legacyDocId;
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

        // BIZ-83493: the quote is no longer advanced to 'Finalize OSA' here. That stage
        // transition now happens when the quote is saved via the simplified quoting tool
        // (AgenticQTC_QuoteAmendmentService.saveQuoteChanges), not at document generation.
        // Term regeneration below is independent of the stage and remains the guarantee that
        // Conga's "Pricing Proposal Document" query has current Term_Quote__c records.

        // Regenerate Quote Terms synchronously before building the URL so the Term_Quote__c
        // records that Conga's "Pricing Proposal Document" query reads are always present and
        // current when the browser opens Conga. Without this, quotes that never transitioned
        // through the 'Finalize OSA' stage (the only path that normally generates terms) produce
        // an OSA with an empty Terms & Conditions section. Mirrors the standard launchCongaComposer
        // flow, which regenerates terms before the Conga URL too. Safe here because this method
        // performs no callout — only SOQL/DML — and generateQuoteTerms logs and swallows its own
        // errors, so a term-generation failure never blocks document generation. BIZ-81419
        QuoteTermValidator.generateQuoteTerms(quoteId);

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

        ContentVersion cv = [
            SELECT Id, ContentDocumentId, Title, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // Back SBQQ__DocumentId__c with a classic Document (015), not the ContentDocument (069):
        // the View button (/servlet/servlet.FileDownload) and OP4I both fail on a 069 File.
        // The cover-prepend step (replaceCongaWithMergedPdf) refreshes this Document with the
        // final merged PDF; if that step is skipped/fails, this Conga-only copy still views and
        // syncs correctly. BIZ-81419
        Id legacyDocId = createPdfDocument(fileName, cv.VersionData);

        SBQQ__QuoteDocument__c quoteDoc = new SBQQ__QuoteDocument__c(
            Name = fileName,
            SBQQ__Quote__c = quoteId,
            SBQQ__Version__c = nextVersion,
            SBQQ__DocumentId__c = legacyDocId
        );
        insert quoteDoc;

        // Rename the QuoteDocument, its File, and the classic Document to the standard OSA
        // convention held in CustomName__c (YYYYMMDD_Bundle#<OSA>_<LOB>_<Account>[_v<n>], using
        // the Quote Expiration date). The provisional name above is only a fallback. BIZ-83515
        String standardName = applyStandardOsaName(quoteDoc.Id, cv.Id, legacyDocId);

        // If the quote is already approved, stamp this doc Approved (separate update) so
        // publishApprovedOSA fires the OnePlace publish now. Quotes still pending approval are
        // stamped by the Quote_After_Insert_Update flow when ApprovalStatus__c flips. BIZ-81419
        stampApprovedIfQuoteApproved(quoteDoc.Id, quoteId);

        GeneratedDocInfo info = new GeneratedDocInfo();
        info.contentVersionId = cv.Id;
        info.contentDocumentId = cv.ContentDocumentId;
        info.title = String.isNotBlank(standardName) ? standardName : cv.Title;
        info.downloadUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        info.quoteDocumentId = quoteDoc.Id;
        info.legacyDocumentId = legacyDocId;
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
        // New row goes to the end. Treat null/empty MAX as zero so the first upload starts at 1.
        Decimal nextOrder = 1;
        AggregateResult[] agg = [
            SELECT MAX(SBQQ__DisplayOrder__c) maxOrder
            FROM   SBQQ__RelatedContent__c
            WHERE  SBQQ__Quote__c = :quoteId
            AND    Document_Type__c != 'Conga Generated OSA'
        ];
        if (!agg.isEmpty() && agg[0].get('maxOrder') != null) {
            nextOrder = ((Decimal) agg[0].get('maxOrder')) + 1;
        }
        insert new SBQQ__RelatedContent__c(
            Name = safeName,
            SBQQ__Quote__c = quoteId,
            SBQQ__ExternalId__c = contentDocumentId,
            SBQQ__Required__c = false,
            SBQQ__DisplayOrder__c = nextOrder
        );
    }

    /**
     * @description Rewrites SBQQ__DisplayOrder__c for every related-content row on a quote
     *              so it matches the order in `orderedIds`. Used by the drag-and-drop UI
     *              and the up/down arrow buttons on Step 1. Ids missing from the list (or
     *              not on this quote) are ignored — protects against the LWC sending a stale
     *              row that was deleted out from under it.
     */
    @AuraEnabled
    public static void reorderRelatedContent(String quoteId, List<String> orderedIds) {
        if (String.isBlank(quoteId) || orderedIds == null || orderedIds.isEmpty()) {
            return;
        }
        Map<Id, SBQQ__RelatedContent__c> byId = new Map<Id, SBQQ__RelatedContent__c>([
            SELECT Id
            FROM   SBQQ__RelatedContent__c
            WHERE  SBQQ__Quote__c = :quoteId
            AND    Id IN :orderedIds
        ]);
        List<SBQQ__RelatedContent__c> toUpdate = new List<SBQQ__RelatedContent__c>();
        for (Integer i = 0; i < orderedIds.size(); i++) {
            SBQQ__RelatedContent__c rc = byId.get(orderedIds[i]);
            if (rc != null) {
                rc.SBQQ__DisplayOrder__c = i + 1;
                toUpdate.add(rc);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Deletes a single SBQQ__RelatedContent__c row (the user-visible "X" on a
     *              Step 1 upload). The underlying ContentDocument is left in place — the
     *              user uploaded it, so deletion stays the user's call.
     */
    @AuraEnabled
    public static void deleteRelatedContent(String quoteId, String relatedContentId) {
        if (String.isBlank(quoteId) || String.isBlank(relatedContentId)) {
            throw new AuraHandledException('Quote ID and Related Content ID are required');
        }
        SBQQ__RelatedContent__c[] rows = [
            SELECT Id
            FROM   SBQQ__RelatedContent__c
            WHERE  Id = :relatedContentId
            AND    SBQQ__Quote__c = :quoteId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }
    }

    /**
     * @description Retrieves SBQQ__RelatedContent__c records linked to a quote,
     *              excluding 'Conga Generated OSA' entries (those are the generated docs).
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of RelatedContentInfo DTOs
     */
    // Non-cacheable: the LWC needs an immediate refresh after every delete or reorder,
    // and cacheable=true would otherwise serve stale rows back from the wire cache.
    @AuraEnabled
    public static List<RelatedContentInfo> getRelatedContent(String quoteId) {
        if (String.isBlank(quoteId)) {
            return new List<RelatedContentInfo>();
        }
        List<SBQQ__RelatedContent__c> rows = [
            SELECT Id, Name, Document_Type__c, SBQQ__ExternalId__c, SBQQ__DisplayOrder__c
            FROM   SBQQ__RelatedContent__c
            WHERE  SBQQ__Quote__c = :quoteId
            AND    Document_Type__c != 'Conga Generated OSA'
            WITH   SECURITY_ENFORCED
            ORDER BY SBQQ__DisplayOrder__c ASC NULLS LAST, Name ASC
        ];
        // The browser-merge path needs each upload's latest ContentVersionId so the LWC can
        // fetch its bytes from /sfc/servlet.shepherd/version/download/<id>. Keep the bind
        // String-typed — a malformed external id then quietly yields no match instead of
        // throwing a TypeException like an explicit (Id) cast would.
        Set<String> docIds = new Set<String>();
        for (SBQQ__RelatedContent__c rc : rows) {
            if (String.isNotBlank(rc.SBQQ__ExternalId__c)) {
                docIds.add(rc.SBQQ__ExternalId__c);
            }
        }
        Map<String, Id> docToLatestVersion = new Map<String, Id>();
        if (!docIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId
                FROM   ContentVersion
                WHERE  ContentDocumentId IN :docIds
                AND    IsLatest = true
                WITH   SECURITY_ENFORCED
            ]) {
                docToLatestVersion.put(String.valueOf(cv.ContentDocumentId), cv.Id);
            }
        }
        List<RelatedContentInfo> results = new List<RelatedContentInfo>();
        for (SBQQ__RelatedContent__c rc : rows) {
            RelatedContentInfo info = new RelatedContentInfo();
            info.id               = rc.Id;
            info.name             = rc.Name;
            info.documentType     = rc.Document_Type__c;
            info.externalId       = rc.SBQQ__ExternalId__c;
            info.displayOrder     = rc.SBQQ__DisplayOrder__c != null ? rc.SBQQ__DisplayOrder__c.intValue() : null;
            info.contentVersionId = String.isNotBlank(rc.SBQQ__ExternalId__c)
                ? docToLatestVersion.get(rc.SBQQ__ExternalId__c)
                : null;
            results.add(info);
        }
        return results;
    }

    /**
     * @description DTO for a SBQQ__RelatedContent__c record.
     */
    public class RelatedContentInfo {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  documentType;
        @AuraEnabled public String  externalId;        // ContentDocumentId
        @AuraEnabled public String  contentVersionId;  // latest ContentVersion of externalId
        @AuraEnabled public Integer displayOrder;
    }
}