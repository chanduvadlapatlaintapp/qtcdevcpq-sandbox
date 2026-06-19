/**
 * @description Generates Conga document URLs for a given Quote — both the standard
 *              PDF-preview/save flow and the new DocuSign send flow.
 * @author Sahal Mohamed
 * @modified 2026-06-02 — Added generateDocuSignUrl() and buildDocuSignSuffix() for
 *                         single- and dual-signer DocuSign integration (BIZ-XXXXX)
 */
public without sharing class CongaUrlService {

    // ─── DocuSign URL parameter constants ─────────────────────────────────────
    /**
     * DS7=2  — Background mode: Conga merges the template and hands the merged
     *           document straight to DocuSign without showing the Conga preview
     *           dialog. Combine with DocuSignVisible=1 so the user still sees the
     *           DocuSign "Prepare & Send" screen before the envelope goes out.
     *
     * Contrast with DS7=1 (preview only, no DocuSign) and DS7=11 (background save
     * to Salesforce Files, used by the existing buildCongaUrlForSave path).
     */
    private static final String DS7_DOCUSIGN              = '2';
    private static final String DOCUSIGN_VISIBLE          = '1';   // show DocuSign prep screen
    private static final String DOCUSIGN_TYPE_SIGNER      = 'Signer';
    private static final String DOCUSIGN_ROLE_SIGNER_1    = 'Signer+1';
    private static final String DOCUSIGN_ROLE_SIGNER_2    = 'Signer+2';
    // ──────────────────────────────────────────────────────────────────────────

    /*****************************************************************************************************************************************************
     *
     * Public Methods
     *
     *******************************************************************************************************************************************************/

    /**
     * @description Generates Quote Terms for a given Quote.
     * @param quoteId Id of the SBQQ__Quote__c
     * @return String Result message
     */
    @AuraEnabled
    public static String generateQuoteTerms(String quoteId) {
        Nebula.logger.info('CongaUrlService --> generateQuoteTerms METHOD BEGINS for Quote Id: ' + quoteId);
        Nebula.logger.saveLog();
        try {
            QuoteTermValidator.generateQuoteTerms(quoteId);
            Nebula.logger.saveLog();
            return 'Quote Terms generated successfully.';
        } catch (Exception ex) {
            Nebula.logger.error('Exception occured while generating Quote Terms: ' + ex.getMessage());
            Nebula.logger.saveLog();
            return 'ERROR : ' + ex.getMessage();
        }
    }

    /**
     * @description Generates the standard Conga Composer URL (PDF preview / background-save flow).
     *              This URL is consumed by AgenticQTC_OsaDocumentService.buildCongaUrlForSave()
     *              which rewrites DS7=1&DS7Preview=1 → DS7=11 for silent Salesforce File save.
     * @param quoteId Id of the SBQQ__Quote__c
     * @return String Generated Conga URL or error string starting with 'ERROR : '
     */
    @AuraEnabled(cacheable=true)
    public static String generateCongaURL(String quoteId) {
        Nebula.logger.info('Conga URL generation started for Quote Id: ' + quoteId);
        try {
            SBQQ__Quote__c qtr = getQuote(quoteId);
            String shortId = normalizeIdTo15(quoteId);
            String dateAsString = normalizeDateToString(qtr.SBQQ__ExpirationDate__c);

            Map<String, String> mapCongaQuery = queryCongaQueryMap();
            String prefix = buildQueryPrefix(System.Label.Conga_URL, mapCongaQuery, shortId);
            String suffix = buildSuffix(qtr, dateAsString);

            String congaURL = prefix + suffix;
            Nebula.logger.info('Conga URL generated: ' + congaURL);
            Nebula.logger.saveLog();
            return congaURL;
        } catch (Exception ex) {
            Nebula.logger.error('Exception occured while generating conga URL: ' + ex.getMessage());
            Nebula.logger.saveLog();
            return 'ERROR : ' + ex.getMessage();
        }
    }

    /**
     * @description Generates a Conga Composer URL that merges the OSA template and routes
     *              the merged document to DocuSign for electronic signature.
     *
     *              Signer resolution:
     *              - R1 (primary / Signer 1) = Quote's Invoicing_Contact__c
     *              - R2 (secondary / Signer 2) = Quote's Software_Delivery_Contact__c,
     *                only added when it is set AND differs from R1
     *
     *              The returned URL is opened in the user's browser (same-session cookie auth).
     *              DocuSignVisible=1 presents the DocuSign "Prepare & Send" screen so the rep
     *              can verify recipients before the envelope is dispatched.
     *
     *              Word template anchor tags (add these in white text to the OSA .docx):
     *                  \s1\  — Signature tab, Signer 1
     *                  \d1\  — Date-Signed tab, Signer 1
     *                  \s2\  — Signature tab, Signer 2  (ignored if no R2 param is passed)
     *                  \d2\  — Date-Signed tab, Signer 2
     *
     * @param quoteId Id of the SBQQ__Quote__c
     * @return String Absolute Conga URL with DocuSign parameters, or error string
     */
    @AuraEnabled
    public static String generateDocuSignUrl(String quoteId) {
        Nebula.logger.info('CongaUrlService --> generateDocuSignUrl started for Quote Id: ' + quoteId);
        try {
            if (String.isBlank(quoteId)) {
                return 'ERROR : Quote ID is required';
            }

            SBQQ__Quote__c qtr = getQuote(quoteId);
            String shortId       = normalizeIdTo15(quoteId);
            String dateAsString  = normalizeDateToString(qtr.SBQQ__ExpirationDate__c);

            // Validate that at least the primary signer is available
            if (qtr.Invoicing_Contact__c == null) {
                return 'ERROR : Invoicing Contact must be set on the Quote before sending via DocuSign';
            }

            Map<String, String> mapCongaQuery = queryCongaQueryMap();
            String prefix = buildQueryPrefix(System.Label.Conga_URL, mapCongaQuery, shortId);
            String suffix = buildDocuSignSuffix(qtr, dateAsString);

            String congaUrl = prefix + suffix;
            Nebula.logger.info('DocuSign Conga URL generated: ' + congaUrl);
            Nebula.logger.saveLog();
            return congaUrl;
        } catch (Exception ex) {
            Nebula.logger.error('Exception in generateDocuSignUrl: ' + ex.getMessage());
            Nebula.logger.saveLog();
            return 'ERROR : ' + ex.getMessage();
        }
    }

    /****************************************************************************************************************************************************
     *
     * Private Methods
     *
     ****************************************************************************************************************************************************/

    /**
     * @description Normalizes a Salesforce Id to 15 characters.
     */
    private static String normalizeIdTo15(String idVal) {
        if (idVal == null) {
            return null;
        }
        return idVal.length() > 15 ? String.valueOf(idVal).substring(0, 15) : idVal;
    }

    /**
     * @description Normalizes a Date field to 'yyyyMMdd' string format.
     */
    private static String normalizeDateToString(Object expirationField) {
        Date convertedDate;
        if (expirationField != null) {
            try {
                convertedDate = Date.valueOf(expirationField);
            } catch (Exception e) {
                convertedDate = Date.today();
            }
        } else {
            convertedDate = Date.today();
        }
        return String.valueOf(convertedDate).replace('-', '');
    }

    /**
     * @description Queries Conga Solution Query records for 'Pricing Proposal Document' solution.
     */
    private static Map<String, String> queryCongaQueryMap() {
        Map<String, String> mapCongaQuery = new Map<String, String>();
        for (APXTConga4__Conga_Solution_Query__c con : [
            SELECT Id, APXTConga4__Alias__c,
                   APXTConga4__Conga_Solution__r.Name,
                   APXTConga4__Conga_Query__r.APXTConga4__Key__c
            FROM APXTConga4__Conga_Solution_Query__c
            WHERE APXTConga4__Conga_Solution__r.Name = 'Pricing Proposal Document'
        ]) {
            mapCongaQuery.put(con.APXTConga4__Alias__c, con.APXTConga4__Conga_Query__r.APXTConga4__Key__c);
        }
        return mapCongaQuery;
    }

    /**
     * @description Builds the Conga URL prefix with query parameters.
     */
    private static String buildQueryPrefix(String congaPrefix, Map<String, String> mapCongaQuery, String shortId) {
        String congaURL = congaPrefix + shortId + '&QueryId=';
        for (String str : mapCongaQuery.keyset()) {
            if (str != null) {
                congaURL += '[' + str + ']' + mapCongaQuery.get(str) + '%3Fpv0%3D' + shortId + ',';
            }
        }
        return congaURL.removeEnd(',');
    }

    /**
     * @description Retrieves and adjusts the Account Short Name for filename usage (max 36 chars).
     */
    private static String getAdjustedAccountName(SBQQ__Quote__c qtr) {
        if (qtr.SBQQ__Account__c == null || qtr.SBQQ__Account__r == null) {
            return null;
        }
        String acc = qtr.SBQQ__Account__r.Account_Short_Name__c;
        if (String.isBlank(acc)) {
            return acc;
        }
        return acc.length() > 36 ? acc.substring(0, 35) : acc;
    }

    /**
     * @description Builds the standard Conga URL suffix for the PDF preview/save flow.
     *              DS7=1&DS7Preview=1 is intentionally left here — AgenticQTC_OsaDocumentService
     *              .buildCongaUrlForSave() rewrites it to DS7=11 for the background-save path.
     */
    private static String buildSuffix(SBQQ__Quote__c qtr, String dateAsString) {
        String osaTempId = System.Label.OSA_Document_Key;
        String sAdjustedAccountName = getAdjustedAccountName(qtr);
        Boolean isFinalizeOsa = qtr.Quote_Stage__c == QuoteConstants.STATUS_FINALIZE_OSA;
        Boolean isAmend       = qtr.SBQQ__Type__c  == QuoteConstants.TYPE_AMENDMENT;
        Boolean watermark     = qtr.SBQQ__WatermarkShown__c == true;

        String fileNamePart = dateAsString +
            (isAmend ? '_Amendment_' : '_Bundle') +
            qtr.OSA_Number__c + '_' +
            qtr.Line_of_Business__c + '_' +
            sAdjustedAccountName + '_v' + qtr.Version__c;

        if (fileNamePart.length() > 72) {
            fileNamePart = fileNamePart.substring(0, 72);
        }

        String defaultSuffix = '&TemplateId=' + osaTempId +
            '&defaultpdf=1&DS7=1&DS7Preview=1&SC0=1&SC1=Attachments&zipfiles=0' +
            '&OFN=' + fileNamePart;

        if (!isFinalizeOsa) {
            return defaultSuffix;
        }

        String draftToken = watermark ? '&DV0=DRAFT' : '';
        return '&TemplateId=' + osaTempId +
            '&defaultpdf=1&DS7=1&DS7Preview=1&SC0=1&SC1=Attachments&zipfiles=0' +
            draftToken + '&OFN=' + fileNamePart;
    }

    /**
     * @description Builds the Conga URL suffix for the DocuSign send flow.
     *
     *              Parameter notes
     *              ───────────────
     *              DS7=2         — Merge & send directly to DocuSign (skips Conga preview dialog).
     *              DocuSignVisible=1
     *                            — Show the DocuSign "Prepare & Send" web UI so the rep can
     *                              confirm/edit recipients and routing before the envelope goes out.
     *              SC0=1         — Save the merged (pre-signature) document to Salesforce.
     *              SC1=SalesforceFile
     *                            — Storage location for that merged document.
     *              DocuSignR1Id  — 15-char Salesforce Id of Invoicing Contact (primary signer).
     *              DocuSignR1Type=Signer / DocuSignR1Role=Signer+1
     *                            — Designates R1 as a signer and maps to the \s1\ anchor in the
     *                              Word template.
     *              DocuSignR2Id  — 15-char Id of Software Delivery Contact when set and ≠ R1.
     *                              Maps to the \s2\ anchor in the Word template.
     *              DocuSignEnvelopeSubject
     *                            — Pre-fills the DocuSign envelope subject line for the rep.
     *
     * @param qtr           SBQQ__Quote__c with contact lookups populated
     * @param dateAsString  Normalized date string (yyyyMMdd)
     * @return              Conga URL suffix string starting with '&TemplateId=...'
     */
    private static String buildDocuSignSuffix(SBQQ__Quote__c qtr, String dateAsString) {
        String osaTempId            = System.Label.OSA_Document_Key;
        String sAdjustedAccountName = getAdjustedAccountName(qtr);
        Boolean isAmend             = qtr.SBQQ__Type__c == QuoteConstants.TYPE_AMENDMENT;
        Boolean watermark           = qtr.SBQQ__WatermarkShown__c == true;

        // ── Output filename ──
        String fileNamePart = dateAsString +
            (isAmend ? '_Amendment_' : '_Bundle') +
            qtr.OSA_Number__c + '_' +
            qtr.Line_of_Business__c + '_' +
            sAdjustedAccountName + '_v' + qtr.Version__c;

        if (fileNamePart.length() > 72) {
            fileNamePart = fileNamePart.substring(0, 72);
        }

        // ── Envelope subject: "Order Schedule Amendment – CONT-050332" ──
        String contractNum = (qtr.SBQQ__MasterContract__r != null &&
                              String.isNotBlank(qtr.SBQQ__MasterContract__r.ContractNumber))
            ? qtr.SBQQ__MasterContract__r.ContractNumber
            : qtr.Name;
        String envelopeSubject = EncodingUtil.urlEncode(
            'Order Schedule Amendment - ' + contractNum, 'UTF-8');

        // ── Watermark token (DRAFT overlay) ──
        String draftToken = watermark ? '&DV0=DRAFT' : '';

        // ── Signer 1: Invoicing Contact (required — validated in generateDocuSignUrl) ──
        String r1Id = normalizeIdTo15(qtr.Invoicing_Contact__c);
        String signerParams =
            '&DocuSignVisible='   + DOCUSIGN_VISIBLE     +
            '&DocuSignR1Id='      + r1Id                 +
            '&DocuSignR1Type='    + DOCUSIGN_TYPE_SIGNER  +
            '&DocuSignR1Role='    + DOCUSIGN_ROLE_SIGNER_1;

        // ── Signer 2: Software Delivery Contact (optional, only when distinct from R1) ──
        if (qtr.Software_Delivery_Contact__c != null &&
            qtr.Software_Delivery_Contact__c != qtr.Invoicing_Contact__c) {

            String r2Id = normalizeIdTo15(qtr.Software_Delivery_Contact__c);
            signerParams +=
                '&DocuSignR2Id='   + r2Id                 +
                '&DocuSignR2Type=' + DOCUSIGN_TYPE_SIGNER  +
                '&DocuSignR2Role=' + DOCUSIGN_ROLE_SIGNER_2;
        }

        return '&TemplateId='             + osaTempId        +
               '&defaultpdf=1'                               +
               '&DS7='                    + DS7_DOCUSIGN      +  // merge → DocuSign, no Conga dialog
               '&SC0=1'                                       +  // save merged draft
               '&SC1=SalesforceFile'                          +  // save to Salesforce Files
               '&zipfiles=0'                                  +
               draftToken                                     +
               '&DocuSignEnvelopeSubject=' + envelopeSubject  +
               signerParams                                   +
               '&OFN='                    + fileNamePart;
    }

    /******************************************************************************************************************************************************
     *
     * Data Getters
     *
     ******************************************************************************************************************************************************/

    /**
     * @description Fetches SBQQ__Quote__c record for the given Id.
     *              Includes Invoicing_Contact__c and Software_Delivery_Contact__c for DocuSign
     *              signer resolution, and MasterContract for envelope subject generation.
     * @param quoteId Id of the SBQQ__Quote__c
     * @return SBQQ__Quote__c record
     */
    private static SBQQ__Quote__c getQuote(String quoteId) {
        return [
            SELECT Id, Name, Account_Name__c,
                   SBQQ__Account__c,
                   SBQQ__Account__r.Account_Short_Name__c,
                   Quote_Stage__c,
                   SBQQ__Type__c,
                   Subsidiary__c,
                   Version__c,
                   SBQQ__ExpirationDate__c,
                   OSA_Number__c,
                   Line_of_Business__c,
                   SBQQ__WatermarkShown__c,
                   // ── DocuSign signer fields ──
                   Invoicing_Contact__c,
                   Invoicing_Contact__r.Name,
                   Invoicing_Contact__r.Email,
                   Software_Delivery_Contact__c,
                   Software_Delivery_Contact__r.Name,
                   Software_Delivery_Contact__r.Email,
                   // ── For envelope subject ──
                   SBQQ__MasterContract__c,
                   SBQQ__MasterContract__r.ContractNumber
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
        ];
    }
}