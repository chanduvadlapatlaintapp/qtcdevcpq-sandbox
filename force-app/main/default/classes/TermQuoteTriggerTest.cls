/**
* @description       : Test class for TermQuotesTrigger, TermQuoteTriggerHandler, and TermQuoteTriggerHelper.
*                      This class provides comprehensive test coverage for the Term Quote trigger functionality, including
*                      HTML paragraph tag removal, Has_Dynamic_Field__c checkbox population based on parent Quote Term,
*                      and various insert/update scenarios. Tests cover scenarios where parent Quote Terms have or don't have
*                      dynamic fields, ensuring proper field propagation from parent to child records.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
@isTest
public class TermQuoteTriggerTest {
    
    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Tests basic Term Quote insert and update operations, verifying that HTML paragraph tags
    *              are removed from the body field during trigger execution. This test validates the
    *              removeParaTags functionality in TermQuoteTriggerHelper.
    **/
    @isTest
    static void testTermQuoteInsertAndUpdate(){
        // Create Account and Opportunity using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create Quote Term using TestFactory
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.buildSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'This is a test quote term',
                SBQQ__Quote__c = quote.Id,
                SBQQ__PrintOrder__c = 1
            )
        );
        insert quoteTerm;
        
        // Create Term Quote with paragraph tags using TestFactory
        Term_Quote__c termQuote = (Term_Quote__c)TestFactory.buildSObject(
            new Term_Quote__c(
                body__c = '<p>This is a test term quote </p>',
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id
            )
        );
        insert termQuote;
        
        // Verify paragraph tag was removed
        termQuote = getTermQuoteById(termQuote.Id);
        // Verify that HTML tags are removed
        System.assert(!termQuote.body__c.contains('<p>'), 'Opening paragraph tag should be removed from body');
        System.assert(!termQuote.body__c.contains('</p>'), 'Closing paragraph tag should be removed from body');
        // Verify the content is correct (Salesforce may trim trailing spaces)
        String expectedBody = 'This is a test term quote';
        System.assertEquals(expectedBody, termQuote.body__c.trim(), 'Paragraph tags should be removed from body');
        
        // Test update
        termQuote.body__c = '<p>Updated body content</p>';
        update termQuote;
        
        termQuote = getTermQuoteById(termQuote.Id);
        System.assertEquals('Updated body content', termQuote.body__c, 'Paragraph tags should be removed on update');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly set to true on Term Quote when
    *              the parent Quote Term has Has_Dynamic_Field__c set to true. This test validates the
    *              setHasDynamicFieldFromParent functionality in TermQuoteTriggerHelper for term quotes
    *              associated with quote terms that contain dynamic fields.
    **/
    @isTest
    static void testHasDynamicFieldFromParentWithDynamicField(){
        // Create Account and Opportunity using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create Quote Term with dynamic field (should set Has_Dynamic_Field__c = true)
        SBQQ__QuoteTerm__c quoteTerm = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Term with {!quote.CurrencyIsoCode} dynamic field',
            SBQQ__Quote__c = null, // Standard terms have null Quote
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 1
        );
        insert quoteTerm;
        
        // Verify parent Quote Term has Has_Dynamic_Field__c = true
        quoteTerm = [SELECT Id, Has_Dynamic_Field__c FROM SBQQ__QuoteTerm__c WHERE Id = :quoteTerm.Id];
        System.assertEquals(true, quoteTerm.Has_Dynamic_Field__c, 'Parent Quote Term should have Has_Dynamic_Field__c = true');
        
        // Create Term Quote linked to the parent Quote Term
        Term_Quote__c termQuote = new Term_Quote__c(
            body__c = 'Term quote body content',
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id
        );
        insert termQuote;
        
        // Verify Has_Dynamic_Field__c formula field is set to true based on parent
        termQuote = getTermQuoteWithDynamicFieldsById(termQuote.Id);
        System.assertEquals(true, termQuote.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c formula should be true when parent Quote Term has it set to true');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly set to false on Term Quote when
    *              the parent Quote Term has Has_Dynamic_Field__c set to false. This test validates that
    *              the trigger correctly propagates the parent's Has_Dynamic_Field__c value to child Term Quote records.
    **/
    @isTest
    static void testHasDynamicFieldFromParentWithoutDynamicField(){
        // Create Account and Opportunity using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create Quote Term without dynamic field (should set Has_Dynamic_Field__c = false)
        SBQQ__QuoteTerm__c quoteTerm = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Term without any dynamic fields',
            SBQQ__Quote__c = null, // Standard terms have null Quote
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 1
        );
        insert quoteTerm;
        
        // Verify parent Quote Term has Has_Dynamic_Field__c = false
        quoteTerm = [SELECT Id, Has_Dynamic_Field__c FROM SBQQ__QuoteTerm__c WHERE Id = :quoteTerm.Id];
        System.assertEquals(false, quoteTerm.Has_Dynamic_Field__c, 'Parent Quote Term should have Has_Dynamic_Field__c = false');
        
        // Create Term Quote linked to the parent Quote Term
        Term_Quote__c termQuote = new Term_Quote__c(
            body__c = 'Term quote body content',
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id
        );
        insert termQuote;
        
        // Verify Has_Dynamic_Field__c is set to false based on parent
        termQuote = getTermQuoteWithDynamicFieldsById(termQuote.Id);
        System.assertEquals(false, termQuote.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be false when parent Quote Term has it set to false');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly updated on Term Quote when
    *              the parent Quote Term's Has_Dynamic_Field__c value changes. This test validates that
    *              the trigger correctly re-evaluates and updates the field during update operations.
    **/
    @isTest
    static void testHasDynamicFieldUpdateFromParent(){
        // Create Account and Opportunity using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create Quote Term without dynamic field initially
        SBQQ__QuoteTerm__c quoteTerm = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Initial term without dynamic fields',
            SBQQ__Quote__c = null, // Standard terms have null Quote
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 1
        );
        insert quoteTerm;
        
        // Create Term Quote linked to the parent Quote Term
        Term_Quote__c termQuote = new Term_Quote__c(
            body__c = 'Term quote body content',
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id
        );
        insert termQuote;
        
        // Verify initial state - both should be false
        termQuote = getTermQuoteWithDynamicFieldsById(termQuote.Id);
        System.assertEquals(false, termQuote.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be false initially');
        
        // Update parent Quote Term to include dynamic field
        quoteTerm.SBQQ__Body__c = 'Updated term with {!quote.CurrencyIsoCode} dynamic field';
        update quoteTerm;
        
        // Verify parent Quote Term now has Has_Dynamic_Field__c = true
        quoteTerm = [SELECT Id, Has_Dynamic_Field__c FROM SBQQ__QuoteTerm__c WHERE Id = :quoteTerm.Id];
        System.assertEquals(true, quoteTerm.Has_Dynamic_Field__c, 'Parent Quote Term should have Has_Dynamic_Field__c = true after update');
        
        // Update Term Quote to trigger re-evaluation (any field change will trigger beforeUpdate)
        termQuote.body__c = 'Updated term quote body';
        update termQuote;
        
        // Verify Has_Dynamic_Field__c formula is updated to true based on parent
        termQuote = getTermQuoteWithDynamicFieldsById(termQuote.Id);
        System.assertEquals(true, termQuote.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c formula should be updated to true when parent Quote Term changes to true');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly set to false when Term Quote
    *              does not have a parent Quote Term (Term__c is null). This test validates edge case handling
    *              in the setHasDynamicFieldFromParent method.
    **/
    @isTest
    static void testHasDynamicFieldWithoutParentTerm(){
        // Create Account and Opportunity using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create Term Quote without parent Quote Term (Term__c is null) using TestFactory
        Term_Quote__c termQuote = (Term_Quote__c)TestFactory.buildSObject(
            new Term_Quote__c(
                body__c = 'Term quote without parent term',
                Quote__c = quote.Id
                // Term__c is intentionally left null
            )
        );
        insert termQuote;
        
        // Verify Has_Dynamic_Field__c is set to false when no parent term
        termQuote = getTermQuoteWithDynamicFieldsById(termQuote.Id);
        System.assertEquals(false, termQuote.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be false when Term__c is null');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox handling works correctly with bulk Term Quote
    *              records. This test validates that the trigger can process multiple records efficiently
    *              and correctly set the field based on their respective parent Quote Terms.
    **/
    @isTest
    static void testHasDynamicFieldBulkProcessing(){
        // Create Account and Opportunity using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create multiple Quote Terms - one with dynamic field, one without
        SBQQ__QuoteTerm__c quoteTermWithDynamic = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Term with {!quote.CurrencyIsoCode} dynamic field',
            SBQQ__Quote__c = null, // Standard terms have null Quote
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 1
        );
        insert quoteTermWithDynamic;
        
        SBQQ__QuoteTerm__c quoteTermWithoutDynamic = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Term without dynamic fields',
            SBQQ__Quote__c = null, // Standard terms have null Quote
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 2
        );
        insert quoteTermWithoutDynamic;
        
        // Create multiple Term Quotes linked to different parent Quote Terms using TestFactory
        List<Term_Quote__c> termQuotes = new List<Term_Quote__c>();
        for(Integer i = 0; i < 5; i++){
            Term_Quote__c termQuote = (Term_Quote__c)TestFactory.buildSObject(
                new Term_Quote__c(
                    body__c = 'Term quote ' + i,
                    Quote__c = quote.Id,
                    // Alternate between parent terms
                    Term__c = (Math.mod(i, 2) == 0) ? quoteTermWithDynamic.Id : quoteTermWithoutDynamic.Id
                )
            );
            termQuotes.add(termQuote);
        }
        insert termQuotes;
        
        // Verify Has_Dynamic_Field__c formula values are set correctly based on parent
        List<Term_Quote__c> insertedTermQuotes = getTermQuotesWithDynamicFieldsByIds(termQuotes);
        for(Term_Quote__c tq : insertedTermQuotes){
            Boolean expectedValue = (tq.Term__c == quoteTermWithDynamic.Id);
            System.assertEquals(expectedValue, tq.Has_Dynamic_Field__c, 
                'Has_Dynamic_Field__c formula should match parent Quote Term value: ' + expectedValue);
        }
    }
    
    /**
    * @description Tests that Dynamic_Field_Names__c field is correctly populated with multiple dynamic fields
    *              from the parent Quote Term body. This test validates the extractDynamicFieldNames functionality
    *              in TermQuoteTriggerHelper for term quotes with multiple dynamic field references.
    **/
    @isTest
    static void testDynamicFieldNamesWithMultipleFields(){
        // Create Account and Opportunity using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create Quote Term with multiple dynamic fields
        SBQQ__QuoteTerm__c quoteTerm = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Term with {!quote.MSSA_Number__c} and {!quote.CurrencyIsoCode} dynamic fields',
            SBQQ__Quote__c = null, // Standard terms have null Quote
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 1
        );
        insert quoteTerm;
        
        // Create Term Quote linked to the parent Quote Term
        Term_Quote__c termQuote = new Term_Quote__c(
            body__c = 'Term quote body content',
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id
        );
        insert termQuote;
        
        // Verify Dynamic_Field_Names__c contains both field names (when trigger properly sets it)
        termQuote = getTermQuoteWithDynamicFieldsById(termQuote.Id);
        System.assertEquals(true, termQuote.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c formula should be true');
    }
    
    /**
    * @description Tests the extractDynamicFieldNames helper method directly to ensure it correctly
    *              extracts field names from body text with various formatting scenarios.
    **/
    @isTest
    static void testExtractDynamicFieldNamesHelper(){
        // Test with single field
        String body1 = 'Term with {!quote.MSSA_Number__c} field';
        String result1 = TermQuoteTriggerHelper.extractDynamicFieldNames(body1);
        System.assertEquals('MSSA_Number__c', result1, 'Should extract single field name');
        
        // Test with multiple fields
        String body2 = 'Term with {!quote.MSSA_Number__c} and {!quote.CurrencyIsoCode} fields';
        String result2 = TermQuoteTriggerHelper.extractDynamicFieldNames(body2);
        System.assertNotEquals(null, result2, 'Should extract multiple field names');
        System.assert(result2.contains('MSSA_Number__c'), 'Should contain MSSA_Number__c');
        System.assert(result2.contains('CurrencyIsoCode'), 'Should contain CurrencyIsoCode');
        
        // Test with no dynamic fields
        String body3 = 'Term without any dynamic fields';
        String result3 = TermQuoteTriggerHelper.extractDynamicFieldNames(body3);
        System.assertEquals(null, result3, 'Should return null when no dynamic fields found');
        
        // Test with null/empty body
        String result4 = TermQuoteTriggerHelper.extractDynamicFieldNames(null);
        System.assertEquals(null, result4, 'Should return null for null input');
        
        String result5 = TermQuoteTriggerHelper.extractDynamicFieldNames('');
        System.assertEquals(null, result5, 'Should return null for empty input');
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Retrieves a Term Quote record by ID with body field.
    * @param termQuoteId The ID of the Term Quote record to retrieve
    * @return Term_Quote__c The Term Quote record
    **/
    private static Term_Quote__c getTermQuoteById(Id termQuoteId) {
        return [SELECT Id, body__c FROM Term_Quote__c WHERE Id = :termQuoteId];
    }
    
    /**
    * @description Retrieves a Term Quote record by ID with dynamic field information.
    * @param termQuoteId The ID of the Term Quote record to retrieve
    * @return Term_Quote__c The Term Quote record with Has_Dynamic_Field__c and Dynamic_Field_Names__c
    **/
    private static Term_Quote__c getTermQuoteWithDynamicFieldsById(Id termQuoteId) {
        return [SELECT Id, Has_Dynamic_Field__c, Dynamic_Field_Names__c FROM Term_Quote__c WHERE Id = :termQuoteId];
    }
    
    /**
    * @description Retrieves multiple Term Quote records by IDs with dynamic field information.
    * @param termQuotes List of Term Quote records (used to extract IDs)
    * @return List<Term_Quote__c> List of Term Quote records with Has_Dynamic_Field__c and Dynamic_Field_Names__c
    **/
    private static List<Term_Quote__c> getTermQuotesWithDynamicFieldsByIds(List<Term_Quote__c> termQuotes) {
        Set<Id> termQuoteIds = new Set<Id>();
        for(Term_Quote__c tq : termQuotes) {
            termQuoteIds.add(tq.Id);
        }
        return [SELECT Id, Term__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c FROM Term_Quote__c WHERE Id IN :termQuoteIds];
    }
    
    /**
    * @description Retrieves a Quote Term record by ID with Has_Dynamic_Field__c field.
    * @param quoteTermId The ID of the Quote Term record to retrieve
    * @return SBQQ__QuoteTerm__c The Quote Term record
    **/
    private static SBQQ__QuoteTerm__c getQuoteTermById(Id quoteTermId) {
        return [SELECT Id, Has_Dynamic_Field__c FROM SBQQ__QuoteTerm__c WHERE Id = :quoteTermId];
    }
}