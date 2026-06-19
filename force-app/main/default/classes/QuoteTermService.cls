/**
* @description       : Service class that handles Quote Term generation and management logic for Quote records.
*                      This class provides functionality to automatically generate quote terms when quotes transition
*                      to 'Finalize OSA' stage or when dynamic fields referenced in quote terms are updated.
*                      The service determines when quote terms need to be regenerated based on stage changes and
*                      field value changes, then triggers asynchronous quote term generation via QuoteTermValidator.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
public inherited sharing class QuoteTermService {

    /***********************************************************************************************
     * 
     * public methods
     * 
     ***********************************************************************************************/

    /**
     * @description Processes quote records to identify when quote terms need to be regenerated.
     *              Quote terms are regenerated in two scenarios:
     *              1. When a quote transitions to 'Finalize OSA' stage
     *              2. When a quote is already at 'Finalize OSA' stage and any field in the
     *                 Quote Term Dynamic Fields field set has changed
     *              The method handles bulk processing by limiting future method calls when
     *              the number of quotes exceeds the configured limit.
     * @param quoteNewList List of updated SBQQ__Quote__c records with new field values
     * @param quoteOldMap Map<Id, SBQQ__Quote__c> of old records with previous field values before the update
     * @example
     * List<SBQQ__Quote__c> quotes = [SELECT Id, Quote_Stage__c FROM SBQQ__Quote__c WHERE Id IN :quoteIds];
     * Map<Id, SBQQ__Quote__c> oldQuotesMap = new Map<Id, SBQQ__Quote__c>([SELECT Id, Quote_Stage__c FROM SBQQ__Quote__c WHERE Id IN :quoteIds]);
     * QuoteTermService.addQuoteTerms(quotes, oldQuotesMap);
     **/
    public static void addQuoteTerms(List<SBQQ__Quote__c> quoteNewList, Map<Id, SBQQ__Quote__c> quoteOldMap) {
        Schema.FieldSet quoteTermFieldSet = getQuoteTermDynamicFieldSet();
        
        // Collect quotes that need processing and all unique changed fields
        QuoteProcessingData processingData = collectQuoteProcessingData(quoteNewList, quoteOldMap, quoteTermFieldSet);
        
        // Build map of quote IDs to term IDs for dynamic field changes
        Map<Id, List<Id>> quoteToTermIdsMap = buildQuoteToTermIdsMap(
            processingData.quoteToChangedFieldsMap,
            processingData.allChangedFields
        );
        
        // Process quotes asynchronously based on bulk limits
        Boolean isBulkUpdate = isBulkProcessing(quoteNewList.size());
        processStageTransitions(processingData.quoteIdSetforTerms, isBulkUpdate);
        processDynamicFieldChanges(quoteToTermIdsMap, isBulkUpdate);
    }

    /***********************************************************************************************
     * 
     * private methods
     * 
     ***********************************************************************************************/
    
    /**
     * @description Collects quotes that need processing and tracks changed fields.
     * @param quoteNewList List of updated quotes
     * @param quoteOldMap Map of old quote values
     * @param quoteTermFieldSet Field set for dynamic fields
     * @return QuoteProcessingData Container with quotes needing processing and changed fields
     **/
    private static QuoteProcessingData collectQuoteProcessingData(
        List<SBQQ__Quote__c> quoteNewList,
        Map<Id, SBQQ__Quote__c> quoteOldMap,
        Schema.FieldSet quoteTermFieldSet
    ) {
        QuoteProcessingData data = new QuoteProcessingData();
        
        for(SBQQ__Quote__c quote : quoteNewList) {
            SBQQ__Quote__c oldQuote = quoteOldMap.get(quote.Id);
            if(oldQuote == null) {
                continue;
            }
            
            Boolean movedToFinalizeOsa = oldQuote.Quote_Stage__c != 'Finalize OSA' && quote.Quote_Stage__c == 'Finalize OSA';
            Set<String> changedFields = getChangedDynamicFields(quote, oldQuote, quoteTermFieldSet);
            Boolean fieldSetChanged = quote.Quote_Stage__c == 'Finalize OSA' && !changedFields.isEmpty();
            
            if(movedToFinalizeOsa) {
                data.quoteIdSetforTerms.add(quote.Id);
            } else if(fieldSetChanged) {
                data.quoteToChangedFieldsMap.put(quote.Id, changedFields);
                data.allChangedFields.addAll(changedFields);
            }
        }
        
        return data;
    }
    
    /**
     * @description Builds a map of quote IDs to affected term IDs based on changed fields.
     * @param quoteToChangedFieldsMap Map of quote IDs to their changed fields
     * @param allChangedFields Set of all unique changed fields across all quotes
     * @return Map<Id, List<Id>> Map of quote IDs to affected term IDs
     **/
    private static Map<Id, List<Id>> buildQuoteToTermIdsMap(
        Map<Id, Set<String>> quoteToChangedFieldsMap,
        Set<String> allChangedFields
    ) {
        Map<Id, List<Id>> quoteToTermIdsMap = new Map<Id, List<Id>>();
        
        if(allChangedFields.isEmpty()) {
            return quoteToTermIdsMap;
        }
        
        Map<String, Set<Id>> fieldToTermIdsMap = getQuoteTermsForFieldsMap(allChangedFields);
        
        for(Id quoteId : quoteToChangedFieldsMap.keySet()) {
            Set<String> changedFields = quoteToChangedFieldsMap.get(quoteId);
            Set<Id> affectedQuoteTermIds = new Set<Id>();
            
            for(String fieldName : changedFields) {
                if(fieldToTermIdsMap.containsKey(fieldName)) {
                    affectedQuoteTermIds.addAll(fieldToTermIdsMap.get(fieldName));
                }
            }
            
                if(!affectedQuoteTermIds.isEmpty()) {
                quoteToTermIdsMap.put(quoteId, new List<Id>(affectedQuoteTermIds));
                }
            }
        
        return quoteToTermIdsMap;
    }
    
    /**
     * @description Processes stage transitions for quotes that moved to Finalize OSA.
     * @param quoteIdSetforTerms List of quote IDs that need term regeneration
     * @param isBulkUpdate Whether this is a bulk update operation
     **/
    private static void processStageTransitions(List<Id> quoteIdSetforTerms, Boolean isBulkUpdate) {
        if(quoteIdSetforTerms == null || quoteIdSetforTerms.isEmpty()) {
            return;
        }
        
        if(isBulkUpdate) {
                QuoteTermValidator.generateQuoteTermsAsync(quoteIdSetforTerms[0]);
        } else {
                for(Id quoteId : quoteIdSetforTerms) {
                    QuoteTermValidator.generateQuoteTermsAsync(quoteId);
                }
            }
        }

    /**
     * @description Processes dynamic field changes for quotes already at Finalize OSA.
     * @param quoteToTermIdsMap Map of quote IDs to affected term IDs
     * @param isBulkUpdate Whether this is a bulk update operation
     **/
    private static void processDynamicFieldChanges(Map<Id, List<Id>> quoteToTermIdsMap, Boolean isBulkUpdate) {
        if(quoteToTermIdsMap == null || quoteToTermIdsMap.isEmpty()) {
            return;
        }
        
        if(isBulkUpdate) {
            Id firstQuoteId = new List<Id>(quoteToTermIdsMap.keySet())[0];
            List<Id> termIds = quoteToTermIdsMap.get(firstQuoteId);
            QuoteTermValidator.generateQuoteTermsForSpecificTermsAsync(firstQuoteId, termIds);
        } else {
            for(Id quoteId : quoteToTermIdsMap.keySet()) {
                List<Id> termIds = quoteToTermIdsMap.get(quoteId);
                QuoteTermValidator.generateQuoteTermsForSpecificTermsAsync(quoteId, termIds);
            }
        }
    }
    
    /**
     * @description Determines if the operation should be treated as bulk processing.
     * @param quoteListSize Number of quotes being processed
     * @return Boolean True if bulk processing should be used
     **/
    private static Boolean isBulkProcessing(Integer quoteListSize) {
        String limitOfFutureCalls = System.label.FutureCallLimit;
        Integer futureCallLimit = Integer.valueOf(limitOfFutureCalls);
        return quoteListSize > futureCallLimit;
    }

    /**
     * @description Retrieves the Quote Term Dynamic Fields field set from the SBQQ__Quote__c object.
     *              This field set contains all fields that are referenced dynamically in quote terms.
     *              The method first attempts to find a field set with the exact name 'Quote_Term_Dynamic_Fields',
     *              and if not found, searches for any field set containing 'quote', 'term', and 'dynamic' in its name.
     * @return Schema.FieldSet The field set containing dynamic fields, or null if not found
     **/
    private static Schema.FieldSet getQuoteTermDynamicFieldSet() {
        Map<String, Schema.FieldSet> fieldSets = Schema.SObjectType.SBQQ__Quote__c.FieldSets.getMap();
        
        if(fieldSets == null || fieldSets.isEmpty()) {
            return null;
        }
        
        String preferredName = 'Quote_Term_Dynamic_Fields';
        if(fieldSets.containsKey(preferredName)) {
            return fieldSets.get(preferredName);
        }
        
        for(String fieldSetName : fieldSets.keySet()) {
            String normalizedName = fieldSetName.toLowerCase();
            if(normalizedName.contains('quote') && normalizedName.contains('term') && normalizedName.contains('dynamic')) {
                return fieldSets.get(fieldSetName);
            }
        }
        
        return null;
    }

    /**
     * @description Gets the list of dynamic fields that have changed between the old and new quote records.
     *              This is used to identify which specific fields changed so only affected quote terms are regenerated.
     *              Only direct fields (not relationship fields containing '.') are checked.
     *              BIZ-75350
     * @param newQuote The updated SBQQ__Quote__c record with new field values
     * @param oldQuote The previous SBQQ__Quote__c record with old field values
     * @param fieldSet The Schema.FieldSet containing fields to check for changes
     * @return Set<String> Returns the set of field API names that have changed
     **/
    private static Set<String> getChangedDynamicFields(
        SBQQ__Quote__c newQuote,
        SBQQ__Quote__c oldQuote,
        Schema.FieldSet fieldSet
    ) {
        Set<String> changedFields = new Set<String>();
        
        if(newQuote == null || oldQuote == null || fieldSet == null) {
            return changedFields;
        }
        
        for(Schema.FieldSetMember fieldMember : fieldSet.getFields()) {
            String fieldPath = fieldMember.getFieldPath();
            
            // Skip relationship fields (fields containing '.')
            if(fieldPath.contains('.')) {
                continue;
            }
            
            Object newValue = newQuote.get(fieldPath);
            Object oldValue = oldQuote.get(fieldPath);
            
            if(valuesDiffer(newValue, oldValue)) {
                changedFields.add(fieldPath);
            }
        }
        
        return changedFields;
    }
    
    /**
     * @description Queries Quote Terms that reference the specified dynamic fields in their body.
     *              Executes a single SOQL query to retrieve all relevant terms, then builds a map
     *              for efficient lookup. This method is optimized for bulk processing to avoid
     *              the 100-query governor limit.
     *              BIZ-75350
     * @param allChangedFields Set of all unique field API names that changed across all quotes
     * @return Map<String, Set<Id>> Returns a map where keys are field API names and values are
     *                              sets of Quote Term IDs that reference each field
     **/
    private static Map<String, Set<Id>> getQuoteTermsForFieldsMap(Set<String> allChangedFields) {
        Map<String, Set<Id>> fieldToTermIdsMap = new Map<String, Set<Id>>();
        
        if(allChangedFields == null || allChangedFields.isEmpty()) {
            return fieldToTermIdsMap;
        }
        
        // Initialize the map with empty sets for all changed fields
        for(String fieldName : allChangedFields) {
            fieldToTermIdsMap.put(fieldName, new Set<Id>());
        }
        
        // Single SOQL query to get all Quote Terms that have dynamic fields
        // This query executes once per transaction, not per quote
        List<SBQQ__QuoteTerm__c> quoteTerms = [
            SELECT Id, SBQQ__Body__c 
            FROM SBQQ__QuoteTerm__c 
            WHERE SBQQ__Quote__c = null 
            AND SBQQ__Active__c = true 
            AND Has_Dynamic_Field__c = true
        ];
        
        // Process each term and check which fields it references
        for(SBQQ__QuoteTerm__c term : quoteTerms) {
            if(String.isNotBlank(term.SBQQ__Body__c)) {
                // Check if the body contains any of the changed fields
                for(String fieldName : allChangedFields) {
                    // Pattern to match {!quote.FieldName} (modern format)
                    String modernPatternString = '\\{!quote\\.' + Pattern.quote(fieldName) + '\\}';
                    Pattern modernPattern = Pattern.compile(modernPatternString);
                    Matcher modernMatcher = modernPattern.matcher(term.SBQQ__Body__c);
                    
                    // Pattern to match SBQQ__Quote__c.FieldName (legacy format)
                    String legacyPatternString = 'SBQQ__Quote__c\\.' + Pattern.quote(fieldName);
                    Pattern legacyPattern = Pattern.compile(legacyPatternString);
                    Matcher legacyMatcher = legacyPattern.matcher(term.SBQQ__Body__c);
                    
                    if(modernMatcher.find() || legacyMatcher.find()) {
                        // Add this term ID to the set for this field
                        fieldToTermIdsMap.get(fieldName).add(term.Id);
                    }
                }
            }
        }
        
        return fieldToTermIdsMap;
    }

    /**
     * @description Compares two field values to determine if they differ. Handles null values
     *              by treating null as equal to null, and any null as different from any non-null value.
     * @param newValue The new field value to compare
     * @param oldValue The old field value to compare
     * @return Boolean Returns true if the values differ, false if they are the same
     **/
    private static Boolean valuesDiffer(Object newValue, Object oldValue) {
        if(newValue == null && oldValue == null) {
            return false;
        }
        
        if(newValue == null || oldValue == null) {
            return true;
        }
        
        return String.valueOf(newValue) != String.valueOf(oldValue);
    }
    
    /***********************************************************************************************
     * 
     * Inner Classes
     * 
     ***********************************************************************************************/
    
    /**
     * @description Data container for quote processing information.
     **/
    private class QuoteProcessingData {
        List<Id> quoteIdSetforTerms = new List<Id>();
        Map<Id, Set<String>> quoteToChangedFieldsMap = new Map<Id, Set<String>>();
        Set<String> allChangedFields = new Set<String>();
    }
}