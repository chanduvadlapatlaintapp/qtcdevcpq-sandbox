/**
* @description       : Service class that consolidates new and existing Term Quote records.
*                      Handles upserting new terms and deleting obsolete terms.
*                      Uses a caller-context flag (preserveModified) to control overwrite behavior:
*                      - Full regeneration paths (Conga, stage transition) pass preserveModified=true
*                        to respect Modified__c unconditionally, preserving user edits.
*                      - Targeted regeneration (trigger detects a dynamic field change) passes
*                        preserveModified=false to override Modified__c for dynamic terms.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
public without sharing class QuoteTermCreator {
    
    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/
    
    /**
     * @description Consolidates new and existing Term Quote records by performing upserts and deletes.
     *              Models new and old Term Quotes as circles in a Venn diagram:
     *              - Intersection: Existing terms that are still relevant (updated if needed)
     *              - Left only: New terms to insert
     *              - Right only: Obsolete terms to delete
     * @param newTerms List of new Term Quote records to be created/updated
     * @param existingTerms List of existing Term Quote records currently on the quote
     * @param preserveModified When true (Conga/stage transition), respects Modified__c unconditionally
     *        so user edits are never overwritten. When false (targeted regeneration from trigger),
     *        overrides Modified__c for dynamic terms since a field value actually changed.
     */
    public static void consolidateOldAndNew(List<Term_Quote__c> newTerms, List<Term_Quote__c> existingTerms, Boolean preserveModified) {
        Map<Id, Term_Quote__c> newTermsByIds = getTermsById(newTerms);
        Map<Id, Term_Quote__c> existingTermsByIds = getTermsById(existingTerms);

        List<Term_Quote__c> termsForUpsert = getTermsForUpsert(newTermsByIds, existingTermsByIds, preserveModified);
        List<Term_Quote__c> obsoleteTerms = getTermsForDelete(newTermsByIds, existingTermsByIds);

        persistTerms(termsForUpsert);
        deleteTerms(obsoleteTerms);
    }

    /***********************************************************************************************
     *
     * Private Helper Methods - Data Preparation
     *
     ***********************************************************************************************/
    
    /**
     * @description Builds a map of Term Quote records keyed by Term__c for efficient lookup.
     * @param quoteTerms List of Term Quote records
     * @return Map<Id, Term_Quote__c> Map of Term__c to Term Quote record
     */
    private static Map<Id, Term_Quote__c> getTermsById(List<Term_Quote__c> quoteTerms) {
        Map<Id, Term_Quote__c> termIdMap = new Map<Id, Term_Quote__c>();
        for(Term_Quote__c term : quoteTerms) {
            termIdMap.put(term.Term__c, term);
        }
        return termIdMap;
    }

    /***********************************************************************************************
     *
     * Private Helper Methods - Term Reconciliation Logic
     *
     ***********************************************************************************************/
    
    /**
     * @description Prepares Term Quotes for upsert by identifying new terms and updating existing ones.
     *              New terms are added for insert. Existing terms are updated with new body and print order.
     *              BIZ-75350 / BIZ-78745: The preserveModified flag controls whether Modified__c is
     *              respected for dynamic terms. See consolidateOldAndNew for usage details.
     * @param newTermsMap Map of new Term Quotes keyed by Term__c
     * @param existingTermsMap Map of existing Term Quotes keyed by Term__c
     * @param preserveModified When true, Modified__c=true terms are always skipped.
     *        When false, Modified__c=true dynamic terms are still overwritten.
     * @return List<Term_Quote__c> List of terms to upsert
    */
    private static List<Term_Quote__c> getTermsForUpsert(Map<Id, Term_Quote__c> newTermsMap, Map<Id, Term_Quote__c> existingTermsMap, Boolean preserveModified) {
        List<Term_Quote__c> termsList = new List<Term_Quote__c>();
        
        for(Id termId : newTermsMap.keySet()) {
            if(!existingTermsMap.containsKey(termId)) {
                termsList.add(newTermsMap.get(termId));
            } else {
                Term_Quote__c termQuote = existingTermsMap.get(termId);
                Term_Quote__c newTerm = newTermsMap.get(termId);
                
                Boolean hasDynamicFields = termQuote.Has_Dynamic_Field__c == true || 
                                           String.isNotBlank(termQuote.Dynamic_Field_Names__c);
                if(!termQuote.Modified__c || (!preserveModified && hasDynamicFields)) {
                   termQuote.Body__c = newTerm.Body__c;
                   termQuote.Print_Order__c = newTerm.Print_Order__c;
                   termQuote.Validator_Modified__c = !termQuote.Validator_Modified__c;
                   termQuote.Modified__c = false;
                   termsList.add(termQuote); 
                }
            }
        }
        
        return termsList;
    }

    /**
     * @description Identifies obsolete Term Quotes that exist but are no longer in the new terms list.
     *              These terms should be deleted as they are no longer applicable to the quote.
     * @param newTermsMap Map of new Term Quotes keyed by Term__c
     * @param existingTermsMap Map of existing Term Quotes keyed by Term__c
     * @return List<Term_Quote__c> List of obsolete terms to delete
     */
    private static List<Term_Quote__c> getTermsForDelete(Map<Id, Term_Quote__c> newTermsMap, Map<Id, Term_Quote__c> existingTermsMap) {
       List<Term_Quote__c> termsToDelete = new List<Term_Quote__c>();
        
        for(Id termId : existingTermsMap.keySet()) {
            // Term exists in old but not in new - mark for deletion
            if(String.isNotBlank(String.valueOf(termId)) && !newTermsMap.containsKey(termId)) {
                termsToDelete.add(existingTermsMap.get(termId));
            }
        }
        
        return termsToDelete;
    }

    /***********************************************************************************************
     *
     * Private Helper Methods - DML Operations
     *
     ***********************************************************************************************/
    
    /**
     * @description Upserts Term Quote records and handles success/error logging.
     *              Uses allOrNone=false to allow partial success, enabling graceful error handling
     *              for individual record failures without failing the entire batch.
     * @param termsToPersist List of Term Quote records to upsert
     */
    private static void persistTerms(List<Term_Quote__c> termsToPersist) {        
        if(termsToPersist == null || termsToPersist.isEmpty()) {
            return;
        }
        
        // Use allOrNone=false to allow partial success and enable error handling for individual failures
        Database.UpsertResult[] srList = Database.upsert(termsToPersist, false);

        for(Database.UpsertResult sr : srList) {
            if(sr.isSuccess()) {
                Nebula.Logger.debug('Successfully upserted Term Quote. ID: ' + sr.getId())
                    .addTag('QuoteTermCreator')
                    .addTag('DML_Upsert')
                    .setRecordId(sr.getId());
            } else {
                for(Database.Error err : sr.getErrors()) {
                    Nebula.Logger.error('Error upserting Term Quote: ' + err.getStatusCode() + ' - ' + err.getMessage())
                        .addTag('QuoteTermCreator')
                        .addTag('DML_Upsert')
                        .addTag('DMLError')
                        .setRecordId(sr.getId());
                    
                    if(err.getFields() != null && !err.getFields().isEmpty()) {
                        Nebula.Logger.debug('Affected fields: ' + String.join(err.getFields(), ', '))
                            .addTag('QuoteTermCreator')
                            .addTag('DML_Upsert')
                            .setRecordId(sr.getId());
                    }
                }
            }
        }

        Nebula.Logger.saveLog();
    }

    /**
     * @description Deletes obsolete Term Quote records and handles success/error logging.
     *              Uses allOrNone=false to allow partial success, enabling graceful error handling
     *              for individual record failures without failing the entire batch.
     * @param termsToDelete List of Term Quote records to delete
     */
    private static void deleteTerms(List<Term_Quote__c> termsToDelete) {
        if(termsToDelete == null || termsToDelete.isEmpty()) {
            return;
        }
        
        // Use allOrNone=false to allow partial success and enable error handling for individual failures
        Database.DeleteResult[] srList = Database.delete(termsToDelete, false);

        for(Database.DeleteResult sr : srList) {
            if(sr.isSuccess()) {
                Nebula.Logger.debug('Successfully deleted Term Quote. ID: ' + sr.getId())
                    .addTag('QuoteTermCreator')
                    .addTag('DML_Delete')
                    .setRecordId(sr.getId());
            } else {
                for(Database.Error err : sr.getErrors()) {
                    Nebula.Logger.error('Error deleting Term Quote: ' + err.getStatusCode() + ' - ' + err.getMessage())
                        .addTag('QuoteTermCreator')
                        .addTag('DML_Delete')
                        .addTag('DMLError')
                        .setRecordId(sr.getId());
                    
                    if(err.getFields() != null && !err.getFields().isEmpty()) {
                        Nebula.Logger.debug('Affected fields: ' + String.join(err.getFields(), ', '))
                            .addTag('QuoteTermCreator')
                            .addTag('DML_Delete')
                            .setRecordId(sr.getId());
                    }
                }
            }
        }

        Nebula.Logger.saveLog();
    }

}