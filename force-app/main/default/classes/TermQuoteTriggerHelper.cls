/**
* @description       : Helper class for TermQuotesTrigger that contains business logic for processing Term Quote records.
*                      This class provides static utility methods to handle formatting and field population for Term Quotes.
*                      Methods in this class are called from TermQuoteTriggerHandler to process records during trigger execution.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
public inherited sharing class TermQuoteTriggerHelper {

    /***********************************************************************************************
     * 
     * public methods
     * 
     ***********************************************************************************************/

    /**
     * @description Removes HTML paragraph tags (<p> or similar) from the term quote body text.
     *              This method processes each term quote in the provided list and removes all HTML tags
     *              from the body__c field content.
     * @param termQuotesLst List of Term_Quote__c records to process. The body__c field will be modified in place.
     * @example
     * List<Term_Quote__c> termQuotes = [SELECT Id, body__c FROM Term_Quote__c WHERE Id = :termQuoteId];
     * TermQuoteTriggerHelper.removeParaTags(termQuotes);
     */
    public static void removeParaTags(List<Term_Quote__c> termQuotesLst){
        for(Term_Quote__c terms : termQuotesLst){
            if(String.isNotBlank(terms.body__c)){
                String body = terms.body__c;
                // Remove all HTML tags from the body
                body = body.replaceAll('<[^>]*>', '');           
                terms.body__c = body;
            }
        }
    }
    
    /**
     * @description Sets Has_Dynamic_Field__c checkbox and Dynamic_Field_Names__c on Term Quote records based on the parent Quote Term.
     *              This method queries the parent Quote Terms to retrieve their Has_Dynamic_Field__c values and body content,
     *              then propagates the checkbox value and extracts dynamic field API names from the parent body to populate
     *              Dynamic_Field_Names__c. Dynamic fields are identified by the pattern {!quote.fieldname} in the body.
     *              BIZ-75350
     * @param termQuotesLst List of Term_Quote__c records to process. The Has_Dynamic_Field__c and Dynamic_Field_Names__c fields will be set based on parent Quote Term.
     * @example
     * List<Term_Quote__c> termQuotes = [SELECT Id, Term__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c FROM Term_Quote__c WHERE Quote__c = :quoteId];
     * TermQuoteTriggerHelper.setHasDynamicFieldFromParent(termQuotes);
     * // If parent Quote Term has "{!quote.MSSA_Number__c}", Has_Dynamic_Field__c will be true and Dynamic_Field_Names__c will be "MSSA_Number__c"
     */
    public static void setHasDynamicFieldFromParent(List<Term_Quote__c> termQuotesLst){
        // Collect parent Quote Term IDs
        Set<Id> quoteTermIds = new Set<Id>();
        for(Term_Quote__c termQuote : termQuotesLst){
            if(termQuote.Term__c != null){
                quoteTermIds.add(termQuote.Term__c);
            }
        }
        
        if(quoteTermIds.isEmpty()){
            return;
        }
        
        // Query parent Quote Terms to get their Has_Dynamic_Field__c values and body content
        Map<Id, SBQQ__QuoteTerm__c> quoteTermMap = new Map<Id, SBQQ__QuoteTerm__c>(
            [SELECT Id, Has_Dynamic_Field__c, SBQQ__Body__c
             FROM SBQQ__QuoteTerm__c 
             WHERE Id IN :quoteTermIds]
        );
        
        // Set Dynamic_Field_Names__c on Term Quote based on parent Quote Term
        // Note: Has_Dynamic_Field__c is now a formula field that automatically gets its value from Term__r.Has_Dynamic_Field__c
        for(Term_Quote__c termQuote : termQuotesLst){
            if(termQuote.Term__c != null && quoteTermMap.containsKey(termQuote.Term__c)){
                // Note: Has_Dynamic_Field__c and Dynamic_Field_Names__c on Term_Quote__c are now formula fields
                // They automatically get their values from Term__r.Has_Dynamic_Field__c and Term__r.Dynamic_Field_Names__c
                // No need to set them explicitly here
            }
        }
    }
    
    /**
     * @description Extracts dynamic field API names from quote term body text using regex pattern matching.
     *              Dynamic fields are identified by either:
     *              - Modern format: {!quote.fieldname}
     *              - Legacy format: SBQQ__Quote__c.fieldname
     *              The method extracts all unique field names and returns them as a comma-separated string.
     *              BIZ-75350
     * @param bodyText The body text content to extract dynamic fields from
     * @return String Comma-separated list of dynamic field API names, or null if none found
     * @example
     * String body = "The term is {!quote.MSSA_Number__c} for SBQQ__Quote__c.CurrencyIsoCode";
     * String fieldNames = TermQuoteTriggerHelper.extractDynamicFieldNames(body);
     * // Returns "CurrencyIsoCode,MSSA_Number__c"
     */
    public static String extractDynamicFieldNames(String bodyText){
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
        
        if(fieldNames.isEmpty()){
            return null;
        }
        
        // Return comma-separated list of field names (sorted for consistency)
        List<String> sortedFieldNames = new List<String>(fieldNames);
        sortedFieldNames.sort();
        return String.join(sortedFieldNames, ',');
    }
    
    /**
     * @description Sets Modified__c flag to true when a user manually edits the Body__c field.
     *              This method detects manual edits by checking if Body__c changed WITHOUT Validator_Modified__c changing.
     *              System regenerations (via QuoteTermCreator) always toggle Validator_Modified__c, so when Body__c
     *              changes without Validator_Modified__c changing, it indicates a manual user edit.
     *              However, if Modified__c is explicitly set to false in the transaction, we respect that
     *              (it means QuoteTermCreator is clearing it for a system regeneration).
     *              BIZ-75350
     * @param newTermQuotes List of Term_Quote__c records being updated
     * @param oldTermQuotesMap Map of old Term_Quote__c records (before update)
     * @example
     * // In TermQuoteTriggerHandler.beforeUpdate:
     * TermQuoteTriggerHelper.setModifiedFlagForManualEdits(termQuotes, oldTermQuotesMap);
     */
    public static void setModifiedFlagForManualEdits(List<Term_Quote__c> newTermQuotes, Map<Id, Term_Quote__c> oldTermQuotesMap){
        for(Term_Quote__c newTerm : newTermQuotes){
            Term_Quote__c oldTerm = oldTermQuotesMap.get(newTerm.Id);
            
            if(oldTerm == null){
                continue;
            }
            
            // Check if Body__c changed (content change, not just HTML tag removal)
            Boolean bodyChanged = false;
            if(newTerm.Body__c != oldTerm.Body__c) {
                // Check if the change is only due to HTML tag removal (removeParaTags)
                String oldBodyWithoutTags = oldTerm.Body__c != null ? oldTerm.Body__c.replaceAll('<[^>]*>', '') : '';
                String newBodyWithoutTags = newTerm.Body__c != null ? newTerm.Body__c.replaceAll('<[^>]*>', '') : '';
                bodyChanged = (oldBodyWithoutTags != newBodyWithoutTags);
            }
            
            // Check if Validator_Modified__c changed
            Boolean validatorFlagChanged = newTerm.Validator_Modified__c != oldTerm.Validator_Modified__c;
            
            // Check if Modified__c was explicitly set to false (system regeneration)
            Boolean modifiedExplicitlyCleared = (oldTerm.Modified__c == true && newTerm.Modified__c == false);
            
            // If Body changed but Validator flag did NOT change, AND Modified__c wasn't explicitly cleared, it's a manual user edit
            if(bodyChanged && !validatorFlagChanged && !modifiedExplicitlyCleared){
                newTerm.Modified__c = true;
            }
        }
    }
    
    /**
     * @description Helper method to clean field names by removing HTML tags and trailing punctuation.
     * @param fieldName The raw field name to clean
     * @return String The cleaned field name
     */
    private static String cleanFieldName(String fieldName){
        if(String.isBlank(fieldName)){
            return fieldName;
        }
        
        fieldName = fieldName.trim();
        // Remove any HTML tags
        fieldName = fieldName.replaceAll('<[^>]+>', '');
        // Remove trailing punctuation
        fieldName = fieldName.replaceAll('[.,;:]$', '');
        return fieldName.trim();
    }
}