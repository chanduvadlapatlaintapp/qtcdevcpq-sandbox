/**
* @description       : Generates Term_Quote__c records for a Quote from active CPQ Quote Terms.
*                      Supports full regeneration and targeted regeneration for specific term IDs.
*                      Used by QuoteTermService to regenerate terms when dynamic fields change (BIZ-75350).
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
public without sharing class QuoteTermValidator {
    
    /***********************************************************************************************
    *
    * Public Async Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Asynchronously generates all quote terms for a given quote.
    *              Used when full regeneration is needed (e.g., stage transition to 'Finalize OSA').
    * @param quoteId The ID of the Quote to generate terms for
    **/
    @future(callout=false)
    public static void generateQuoteTermsAsync(Id quoteId){
        QuoteTermValidator.generateQuoteTerms(quoteId);
    }
    
    /**
    * @description Asynchronously generates specific quote terms for a given quote.
    *              Used when only terms with dynamic fields need regeneration (BIZ-75350).
    * @param quoteId The ID of the Quote to generate terms for
    * @param quoteTermIds List of specific Quote Term IDs to regenerate
    **/
    @future(callout=false)
    public static void generateQuoteTermsForSpecificTermsAsync(Id quoteId, List<Id> quoteTermIds){
        QuoteTermValidator.generateQuoteTermsForSpecificTerms(quoteId, quoteTermIds);
    }
    
    /***********************************************************************************************
    *
    * Public Synchronous Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Generates all quote terms for a given quote. Evaluates all active standard
    *              Quote Terms against the quote's current data and creates corresponding Term_Quote__c records.
    *              Handles reconciliation with existing terms (updates/deletes as needed).
    * @param quoteId The ID of the Quote to generate terms for
    * @return String Status message indicating completion or error
    **/
    @AuraEnabled
    public static String generateQuoteTerms(Id quoteId){
        String message = '';
        try {
        if(quoteId != null) {
                Nebula.Logger.info('Starting quote term generation for Quote: ' + quoteId)
                    .addTag('QuoteTermValidator')
                    .addTag('QuoteTermGeneration')
                    .setRecordId(quoteId);
                
                // Step 1: Load all active global quote terms (templates)
        Map<Id, SBQQ__QuoteTerm__c> quoteTermMap = getAllQuoteTerms();
                
                // Step 2: Gather quote fields needed for dynamic term evaluation
        List<String> quoteFields = getQuoteFields(quoteTermMap.values());
                
                // Step 3: Load the quote with its line items for evaluation context
        SBQQ__Quote__c quoteDetails = getQuoteDetails(quoteId, quoteFields);
                
                // Step 4: Evaluate term conditions and build Term_Quote__c records
        List<Term_Quote__c> termsToCreate = evaluateTermConditions(quoteTermMap, quoteDetails); 
                
                // Step 5: Reconcile with existing terms (handles insert/update/delete)
        List<Term_Quote__c> existingTermsOnQuote = getExistingTerms(quoteId);
        QuoteTermCreator.consolidateOldAndNew(termsToCreate, existingTermsOnQuote, true);
                
                Nebula.Logger.info('Quote terms generated successfully for Quote: ' + quoteId)
                    .addTag('QuoteTermValidator')
                    .addTag('QuoteTermGeneration')
                    .setRecordId(quoteId);
            message = 'Quote Terms are generated.';
        }
        } catch(Exception ex) {
            Nebula.Logger.error('Error generating quote terms for Quote: ' + quoteId, ex)
                .addTag('QuoteTermValidator')
                .addTag('QuoteTermGeneration')
                .addTag('CaughtException')
                .setRecordId(quoteId);
        } finally {
            Nebula.Logger.saveLog();
        }
        return message;
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods - Data Retrieval
    *
    ***********************************************************************************************/
    
    /**
    * @description Retrieves all active standard Quote Terms (global templates).
    *              Excludes quote-specific terms by filtering for SBQQ__Quote__c = null.
    * @return Map<Id, SBQQ__QuoteTerm__c> Map of Quote Term IDs to Quote Term records with conditions
    **/
    private static Map<Id, SBQQ__QuoteTerm__c> getAllQuoteTerms() {
        Map<Id, SBQQ__QuoteTerm__c> quoteTermMap = new Map<Id, SBQQ__QuoteTerm__c>([
            SELECT Id, SBQQ__Body__c, SBQQ__PrintOrder__c, SBQQ__ConditionsMet__c, SBQQ__AdvancedCondition__c,
                (SELECT Id, SBQQ__Index__c, SBQQ__Operator__c, SBQQ__TestedField__c, SBQQ__TestedVariable__c, SBQQ__Value__c 
                 FROM SBQQ__UseConditions__r) 
            FROM SBQQ__QuoteTerm__c 
            WHERE SBQQ__Quote__c = null 
            AND SBQQ__Active__c = true
        ]);
        Nebula.Logger.debug('Found ' + quoteTermMap.size() + ' active standard quote terms')
            .addTag('QuoteTermValidator');
        return quoteTermMap;
    }
     
    /**
    * @description Retrieves Quote details with all specified fields and related line items.
    *              Uses dynamic SOQL to support variable field lists for term evaluation.
    * @param quoteId The ID of the Quote to retrieve
    * @param quoteFields List of field API names to query on the Quote object
    * @return SBQQ__Quote__c Quote record with line items
    **/
    private static SBQQ__Quote__c getQuoteDetails(Id quoteId, List<String> quoteFields) {
        List<SBQQ__Quote__c> quoteList = new List<SBQQ__Quote__c>();
        String query = 'SELECT ' + String.join(quoteFields, ',') + 
                       ', (SELECT Id, SBQQ__ProductCode__c, SBQQ__EffectiveQuantity__c FROM SBQQ__LineItems__r) ' +
                       'FROM SBQQ__Quote__c WHERE Id = :quoteId';
        
        // Iterate to avoid "Aggregate query has too many rows" error
        for(SBQQ__Quote__c quote : Database.query(query)){
            quoteList.add(quote);
        }
        
        return quoteList[0];
    }
	
    /**
    * @description Retrieves all field API names from the SBQQ__Quote__c object.
    *              Required to support dynamic field replacements in quote term bodies ({!quote.FieldName__c}).
    * @param terms List of Quote Terms (parameter kept for interface consistency, not currently used)
    * @return List<String> List of all Quote field API names
    **/
    private static List<String> getQuoteFields(List<SBQQ__QuoteTerm__c> terms) {
        List<String> fieldSet = new List<String>();
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get('SBQQ__Quote__c');
		Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe().fields.getMap();
        
        for (Schema.SObjectField field : fieldMap.values()) {
             fieldSet.add(field.getDescribe().getName());
         }
        
        return fieldSet;
    }
    
    /**
    * @description Retrieves existing Term_Quote__c records for a given quote.
    *              Used for reconciliation when regenerating terms.
    *              BIZ-78745: Added Dynamic_Field_Names__c to avoid SObjectException when
    *              QuoteTermCreator.getTermsForUpsert() accesses it during targeted regeneration.
    * @param quoteId The ID of the Quote
    * @return List<Term_Quote__c> Existing term records on the quote
    **/
    private static List<Term_Quote__c> getExistingTerms(Id quoteId) {
        return [
            SELECT Id, Term__c, Quote__c, Body__c, Print_Order__c, Validator_Modified__c, 
                   Modified__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c 
            FROM Term_Quote__c 
            WHERE Quote__c = :quoteId
        ];
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods - Term Evaluation
    *
    ***********************************************************************************************/
    
    /**
    * @description Evaluates quote term conditions against quote data and builds Term_Quote__c records.
    *              Uses QuoteTermReader to load terms with dynamic field values already evaluated,
    *              then applies additional condition logic via ConditionEvaluator.
    * @param quoteTermMap Map of Quote Term IDs to evaluate (null/empty = evaluate all terms)
    * @param quoteDetails Quote record with line items
    * @return List<Term_Quote__c> Terms that meet conditions and should be added to the quote
    **/
    private static List<Term_Quote__c> evaluateTermConditions(Map<Id, SBQQ__QuoteTerm__c> quoteTermMap, SBQQ__Quote__c quoteDetails) {
        List<Term_Quote__c> termsToCreate = new List<Term_Quote__c>();
        
        // Build product code set from quote lines for condition evaluation
        Set<String> productCodes = new Set<String>();
        if(quoteDetails != null && !quoteDetails.SBQQ__LineItems__r.isEmpty()) {
            for(SBQQ__QuoteLine__c quoteLine : quoteDetails.SBQQ__LineItems__r) {
                if(quoteLine.SBQQ__EffectiveQuantity__c > 0) {
                productCodes.add(quoteLine.SBQQ__ProductCode__c);
            }
        }
        }
        
        // Load terms using QuoteTermReader (handles dynamic field replacement)
        // IMPORTANT: Use an org-appropriate language code. Hardcoding 'en' can return 0 terms in some orgs
        // (e.g., where the effective language is 'en_US').
        String language = (quoteDetails != null && String.isNotBlank(quoteDetails.SBQQ__QuoteLanguage__c))
            ? quoteDetails.SBQQ__QuoteLanguage__c
            : UserInfo.getLanguage();
        if(String.isBlank(language)) {
            language = 'en';
        }
        QuoteTermReader quoteTermReader = new QuoteTermReader();
        List<QuoteTermReader.QuoteTermModel> quoteTerms = quoteTermReader.load(quoteDetails.Id, null, language);
        
        for(QuoteTermReader.QuoteTermModel oQT : quoteTerms){
            // Determine the standard term/template id for this model.
            // In some orgs, QuoteTermReader returns standardTermId = null for standard terms, and the template id is in oQT.Id.
            Id templateTermId = (oQT != null && oQT.standardTermId != null) ? oQT.standardTermId : (oQT != null ? oQT.Id : null);

            // Filter to specific terms if quoteTermMap is provided (for targeted regeneration)
            if(quoteTermMap == null || quoteTermMap.isEmpty() || (templateTermId != null && quoteTermMap.containsKey(templateTermId))) {
                // Convert QuoteTermModel to SBQQ__QuoteTerm__c for ConditionEvaluator
                SBQQ__QuoteTerm__c term = new SBQQ__QuoteTerm__c();
                term.Id = templateTermId;
                term.SBQQ__Body__c = oQT.value;
                term.SBQQ__PrintOrder__c = Decimal.valueOf(oQT.label);
                
                // Evaluate conditions and create Term_Quote__c if conditions are met
                ConditionEvaluator evaluateConditions = new ConditionEvaluator(term, quoteDetails, productCodes);  
                Term_Quote__c termquote = evaluateConditions.evaluateConditionsAndInstantiateQuoteTerm();
                
                if(termquote != null) {
                    termsToCreate.add(termquote);
                }
            }
        } 
        
        return termsToCreate;
    }
    
    /***********************************************************************************************
    *
    * Public Methods - Targeted Regeneration
    *
    ***********************************************************************************************/
    
    /**
    * @description Generates quote terms for specific Quote Terms only (targeted regeneration).
    *              Used when dynamic fields change and only terms with those fields need updating.
    *              This is more efficient than regenerating all terms. BIZ-75350
     * @param quoteId The ID of the Quote to generate terms for
    * @param quoteTermIds List of specific Quote Term IDs to regenerate
    * @return String Status message indicating completion or error
     **/
    @AuraEnabled
    public static String generateQuoteTermsForSpecificTerms(Id quoteId, List<Id> quoteTermIds){
        String message = '';
        try {
            Set<Id> quoteTermIdSet = new Set<Id>(quoteTermIds);
            if(quoteId != null && quoteTermIdSet != null && !quoteTermIdSet.isEmpty()) {
                Nebula.Logger.info('Starting targeted quote term regeneration for Quote: ' + quoteId + ' with ' + quoteTermIdSet.size() + ' terms')
                    .addTag('QuoteTermValidator')
                    .addTag('TargetedRegeneration')
                    .setRecordId(quoteId);
                
                // Step 1: Load only the specific quote terms that need regeneration
                Map<Id, SBQQ__QuoteTerm__c> quoteTermMap = getSpecificQuoteTerms(quoteTermIdSet);
                
                // Step 2: Gather quote fields and load quote details
        List<String> quoteFields = getQuoteFields(quoteTermMap.values());
        SBQQ__Quote__c quoteDetails = getQuoteDetails(quoteId, quoteFields);
                
                // Step 3: Evaluate conditions and create terms
        List<Term_Quote__c> termsToCreate = evaluateTermConditions(quoteTermMap, quoteDetails); 
                
                // Step 4: Reconcile with existing terms
        // IMPORTANT: This is *targeted* regeneration. We must not delete unrelated Term_Quote__c records.
        // Only reconcile (insert/update/delete) the subset whose Term__c is in the targeted Quote Term IDs.
        List<Term_Quote__c> existingTermsOnQuote = getExistingTerms(quoteId);
        List<Term_Quote__c> existingTargetedTerms = new List<Term_Quote__c>();
        for(Term_Quote__c existingTerm : existingTermsOnQuote) {
            if(existingTerm != null && existingTerm.Term__c != null && quoteTermIdSet.contains(existingTerm.Term__c)) {
                existingTargetedTerms.add(existingTerm);
            }
        }
        QuoteTermCreator.consolidateOldAndNew(termsToCreate, existingTargetedTerms, false);

                Nebula.Logger.info('Targeted quote term regeneration completed successfully for Quote: ' + quoteId)
                    .addTag('QuoteTermValidator')
                    .addTag('TargetedRegeneration')
                    .setRecordId(quoteId);
        message = 'Quote Terms are generated for specific terms.';
        }
        } catch(Exception ex) {
            Nebula.Logger.error('Error generating specific quote terms for Quote: ' + quoteId, ex)
                .addTag('QuoteTermValidator')
                .addTag('TargetedRegeneration')
                .addTag('CaughtException')
                .setRecordId(quoteId);
        } finally {
            Nebula.Logger.saveLog();
        }
        return message;
    }
    
    /**
    * @description Retrieves specific active Quote Terms by ID for targeted regeneration.
    * @param quoteTermIds Set of Quote Term IDs to retrieve
    * @return Map<Id, SBQQ__QuoteTerm__c> Map of requested Quote Terms with conditions
    **/
    private static Map<Id, SBQQ__QuoteTerm__c> getSpecificQuoteTerms(Set<Id> quoteTermIds) {
        Map<Id, SBQQ__QuoteTerm__c> quoteTermMap = new Map<Id, SBQQ__QuoteTerm__c>([
            SELECT Id, SBQQ__Body__c, SBQQ__PrintOrder__c, SBQQ__ConditionsMet__c, SBQQ__AdvancedCondition__c,
            (SELECT Id, SBQQ__Index__c, SBQQ__Operator__c, SBQQ__TestedField__c, SBQQ__TestedVariable__c, SBQQ__Value__c 
             FROM SBQQ__UseConditions__r) 
            FROM SBQQ__QuoteTerm__c 
            WHERE Id IN :quoteTermIds 
            AND SBQQ__Active__c = true
        ]);
        Nebula.Logger.debug('Found ' + quoteTermMap.size() + ' specific quote terms to regenerate')
            .addTag('QuoteTermValidator')
            .addTag('TargetedRegeneration');
        return quoteTermMap;
    }
    
}