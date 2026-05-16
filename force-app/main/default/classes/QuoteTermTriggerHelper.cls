/**
* @description       : Helper class for QuoteTermTrigger that contains business logic for processing Quote Term records.
*                      This class provides static utility methods to handle formatting and field population for Quote Terms.
*                      Methods in this class are called from QuoteTermTriggerHandler to process records during trigger execution.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
public inherited sharing class QuoteTermTriggerHelper {

    /***********************************************************************************************
     * 
     * public methods
     * 
     ***********************************************************************************************/

    /**
     * @description Removes the first HTML paragraph tag (<p> or similar) from the quote term body text.
     *              This method processes each quote term in the provided list and removes the first HTML tag
     *              found at the beginning of the SBQQ__Body__c field content.
     * @param quoteTermsLst List of SBQQ__QuoteTerm__c records to process. The SBQQ__Body__c field will be modified in place.
     * @example
     * List<SBQQ__QuoteTerm__c> terms = [SELECT Id, SBQQ__Body__c FROM SBQQ__QuoteTerm__c WHERE Id = :termId];
     * QuoteTermTriggerHelper.removeParaTags(terms);
     */
    public static void removeParaTags(List<SBQQ__QuoteTerm__c> quoteTermsLst){
        for(SBQQ__QuoteTerm__c terms : quoteTermsLst){
            if(String.isNotBlank(terms.SBQQ__Body__c)){
                String body = terms.SBQQ__Body__c;
                body = body.replaceFirst('<[^>]*>','');           
                terms.SBQQ__Body__c = body;
            }
        }
    }
    
    /**
     * @description Sets the Has_Dynamic_Field__c checkbox and Dynamic_Field_Names__c field for standard quote terms.
     *              Dynamic fields are identified by either:
     *              - Modern format: {!quote.fieldname}
     *              - Legacy format: SBQQ__Quote__c.fieldname
     *              This method uses regex pattern matching to detect the presence of dynamic fields and updates
     *              the Has_Dynamic_Field__c field accordingly. It also extracts all unique field API names and
     *              stores them as a comma-separated list in Dynamic_Field_Names__c.
     *              Only processes standard terms (where SBQQ__Quote__c is null).
     *              BIZ-75350
     * @param quoteTermsLst List of SBQQ__QuoteTerm__c records to process. The Has_Dynamic_Field__c and Dynamic_Field_Names__c fields will be set based on body content.
     * @example
     * List<SBQQ__QuoteTerm__c> terms = [SELECT Id, SBQQ__Body__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c FROM SBQQ__QuoteTerm__c WHERE Id = :termId];
     * QuoteTermTriggerHelper.setHasDynamicField(terms);
     * // If term.SBQQ__Body__c contains "{!quote.MSSA_Number__c}" and "SBQQ__Quote__c.CurrencyIsoCode", 
     * // Has_Dynamic_Field__c will be true and Dynamic_Field_Names__c will be "CurrencyIsoCode,MSSA_Number__c"
     */
    public static void setHasDynamicField(List<SBQQ__QuoteTerm__c> quoteTermsLst){
        for(SBQQ__QuoteTerm__c term : quoteTermsLst){
            // Only process standard terms (SBQQ__Quote__c is null)
            if(term.SBQQ__Quote__c != null){
                continue;
            }
            
            Boolean hasDynamicField = false;
            String dynamicFieldNames = null;
            
            // Check if SBQQ__Body__c contains dynamic fields and extract field names
            if(String.isNotBlank(term.SBQQ__Body__c)){
                dynamicFieldNames = extractDynamicFieldNames(term.SBQQ__Body__c);
                hasDynamicField = String.isNotBlank(dynamicFieldNames);
            }
            
            // Set the fields based on whether dynamic fields are found
            term.Has_Dynamic_Field__c = hasDynamicField;
            term.Dynamic_Field_Names__c = dynamicFieldNames;
        }
    }
    
    /***********************************************************************************************
     * 
     * private helper methods
     * 
     ***********************************************************************************************/
    
    /**
     * @description Extracts dynamic field API names from quote term body text using regex pattern matching.
     *              Dynamic fields are identified by either:
     *              - Modern format: {!quote.fieldname}
     *              - Legacy format: SBQQ__Quote__c.fieldname
     *              The method extracts all unique field names and returns them as a comma-separated string.
     *              BIZ-75350
     * @param bodyText The body text content to extract dynamic fields from
     * @return String Comma-separated list of dynamic field API names (alphabetically sorted), or null if none found
     * @example
     * String body = "The term is {!quote.MSSA_Number__c} for SBQQ__Quote__c.CurrencyIsoCode";
     * String fieldNames = QuoteTermTriggerHelper.extractDynamicFieldNames(body);
     * // Returns "CurrencyIsoCode,MSSA_Number__c"
     */
    private static String extractDynamicFieldNames(String bodyText){
        if(String.isBlank(bodyText)){
            return null;
        }
        
        Set<String> fieldNames = new Set<String>();
        
        // Pattern to match {!quote.fieldname} (modern format) - captures the field name
        Pattern modernPattern = Pattern.compile('\\{!quote\\.([^}]+)\\}');
        Matcher modernMatcher = modernPattern.matcher(bodyText);
        
        while(modernMatcher.find()){
            String fieldName = modernMatcher.group(1);
            fieldName = cleanFieldName(fieldName);
            if(String.isNotBlank(fieldName)){
                fieldNames.add(fieldName);
            }
        }
        
        // Pattern to match SBQQ__Quote__c.fieldname (legacy format) - captures the field name
        Pattern legacyPattern = Pattern.compile('SBQQ__Quote__c\\.([^\\s<,;:\\)}]+)');
        Matcher legacyMatcher = legacyPattern.matcher(bodyText);
        
        while(legacyMatcher.find()){
            String fieldName = legacyMatcher.group(1);
            fieldName = cleanFieldName(fieldName);
            if(String.isNotBlank(fieldName)){
                fieldNames.add(fieldName);
            }
        }
        
        // Return comma-separated list (sorted alphabetically for consistency)
        if(fieldNames.isEmpty()){
            return null;
        }
        
        List<String> sortedFieldNames = new List<String>(fieldNames);
        sortedFieldNames.sort();
        return String.join(sortedFieldNames, ',');
    }
    
    /**
     * @description Cleans a field name by removing common HTML entities, tags, and whitespace.
     *              This ensures extracted field names are valid API names.
     * @param fieldName The raw field name extracted from the body text
     * @return String The cleaned field name, or null if the result is blank
     */
    private static String cleanFieldName(String fieldName){
        if(String.isBlank(fieldName)){
            return null;
        }
        
        // Remove HTML entities and tags
        fieldName = fieldName.replaceAll('&[^;]+;', ''); // Remove HTML entities like &nbsp;
        fieldName = fieldName.replaceAll('<[^>]*>', ''); // Remove HTML tags
        fieldName = fieldName.trim();
        
        return String.isNotBlank(fieldName) ? fieldName : null;
    }
}