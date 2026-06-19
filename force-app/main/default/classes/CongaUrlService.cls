/**
 * @description Generates Conga document URL for a given Quote.
 * @author Sahal Mohamed
 */
public without sharing class CongaUrlService {

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
    public static String generateQuoteTerms(String quoteId){
        Nebula.logger.info('CongaUrlService --> generateQuoteTerms METHOD BEGINS for Quote Id: ' + quoteId);
        Nebula.logger.saveLog();
        try {
            // QuoteTermValidator.generateQuoteTerms() also links product documents via
            // ProductDocumentService.linkProductDocumentsForQuote() — the single,
            // amendment-aware path (BIZ-83059). Do not link documents again here.
            QuoteTermValidator.generateQuoteTerms(quoteId);

            Nebula.logger.saveLog();
            return 'Quote Terms generated successfully.';
        }
        catch(Exception ex) {
            Nebula.logger.error('Exception occured while generating Quote Terms: ' + ex.getMessage());
            Nebula.logger.saveLog();
            return 'ERROR : '+ex.getMessage();
        }
    }

    /**
     * @description Generates Conga document URL for a given Quote.
     * @param quoteId Id of the SBQQ__Quote__c
     * @return String Generated Conga URL or error string
     */
    @AuraEnabled(cacheable=true)
    public static String generateCongaURL(String quoteId){
        Nebula.logger.info('Conga URL generation started for Quote Id: ' + quoteId); // initial log
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

    /****************************************************************************************************************************************************
     * 
     * Private methods
     * 
     *****************************************************************************************************************************************************/
    /**
     * @description Normalizes a Salesforce Id to 15 characters.
     * @param idVal Salesforce Id
     * @return 15-character Id
     */
    private static String normalizeIdTo15(String idVal) {
        if (idVal == null) {
            return null;
        }
        return idVal.length() > 15 ? String.valueOf(idVal).substring(0, 15) : idVal;
    }

    /**
     * @description Normalizes a Date field to 'yyyyMMdd' string format.
     * @param expirationField Date field value
     * @return String in 'yyyyMMdd' format
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
     * @return Map of Alias to Query Key
     */
    private static Map<String, String> queryCongaQueryMap() {
        Map<String, String> mapCongaQuery = new Map<String, String>();
        for (APXTConga4__Conga_Solution_Query__c con : [SELECT Id, APXTConga4__Alias__c, APXTConga4__Conga_Solution__r.Name, APXTConga4__Conga_Query__r.APXTConga4__Key__c
                                                        FROM APXTConga4__Conga_Solution_Query__c
                                                        WHERE APXTConga4__Conga_Solution__r.Name = 'Pricing Proposal Document']) {
            mapCongaQuery.put(con.APXTConga4__Alias__c, con.APXTConga4__Conga_Query__r.APXTConga4__Key__c);
        }
        return mapCongaQuery;
    }

    /**
     * @description Builds the Conga URL prefix with query parameters.
     * @param congaPrefix Base Conga URL prefix
     * @param mapCongaQuery Map of Alias to Query Key
     * @param shortId 15-character Quote Id
     * @return Constructed Conga URL prefix
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
     * @description Retrieves and adjusts the Account Short Name for filename usage.
     * @param qtr SBQQ__Quote__c record
     * @return Adjusted Account Short Name or null
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
     * @description Builds the Conga URL suffix with template and filename parameters.
     * @param qtr SBQQ__Quote__c record
     * @param dateAsString Normalized date string
     * @return Constructed Conga URL suffix
     */
    private static String buildSuffix(SBQQ__Quote__c qtr, String dateAsString) {
        String osaTempId = System.Label.OSA_Document_Key;
        String sAdjustedAccountName = getAdjustedAccountName(qtr);
        Boolean isFinalizeOsa = qtr.Quote_Stage__c == QuoteConstants.STATUS_FINALIZE_OSA;
        Boolean isAmend = qtr.SBQQ__Type__c == QuoteConstants.TYPE_AMENDMENT;
        Boolean watermark = qtr.SBQQ__WatermarkShown__c == true;

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

        // For Finalize OSA branch, compute suffix using watermark/type
        if (watermark) {
            if (isAmend) {
                return '&TemplateId=' + osaTempId + '&defaultpdf=1&DS7=1&DS7Preview=1&SC0=1&SC1=Attachments&zipfiles=0&DV0=DRAFT&OFN=' + fileNamePart;
            }
            return '&TemplateId=' + osaTempId + '&defaultpdf=1&DS7=1&DS7Preview=1&SC0=1&SC1=Attachments&zipfiles=0&DV0=DRAFT&OFN=' + fileNamePart;
        }

        if (isAmend) {
            return '&TemplateId=' + osaTempId + '&defaultpdf=1&DS7=1&DS7Preview=1&SC0=1&SC1=Attachments&zipfiles=0&OFN=' + fileNamePart;
        }
        return '&TemplateId=' + osaTempId + '&defaultpdf=1&DS7=1&DS7Preview=1&SC0=1&SC1=Attachments&zipfiles=0&OFN=' + fileNamePart;
    }

    /******************************************************************************************************************************************************
     * 
     * Data getters
     * 
     ******************************************************************************************************************************************************/
    /**
     * @description Fetches SBQQ__Quote__c record for given Id.
     * @param quoteId Id of the SBQQ__Quote__c
     * @return SBQQ__Quote__c record
     */
    private static SBQQ__Quote__c getQuote(String quoteId) {
        return [SELECT Id, Name, Account_Name__c, SBQQ__Account__c, SBQQ__Account__r.Account_Short_Name__c, Quote_Stage__c, 
                    SBQQ__Type__c, Subsidiary__c, Version__c, SBQQ__ExpirationDate__c, OSA_Number__c, Line_of_Business__c, SBQQ__WatermarkShown__c
                FROM SBQQ__Quote__c
                WHERE Id = :quoteId];
    }
}