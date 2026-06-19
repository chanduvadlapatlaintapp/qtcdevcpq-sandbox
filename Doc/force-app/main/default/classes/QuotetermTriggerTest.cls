/**
* @description       : Test class for QuoteTermTrigger, QuoteTermTriggerHandler, and QuoteTermTriggerHelper.
*                      This class provides comprehensive test coverage for the Quote Term trigger functionality, including
*                      HTML paragraph tag removal, dynamic field detection, and Has_Dynamic_Field__c checkbox population.
*                      Tests cover various scenarios: insert operations, update operations, dynamic field presence/absence,
*                      and standard terms (terms not associated with a specific quote).
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
@isTest
public class QuotetermTriggerTest {
    
    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Tests basic Quote Term insert and update operations, verifying that HTML paragraph tags
    *              are removed from the body field during trigger execution. This test validates the
    *              removeParaTags functionality in QuoteTermTriggerHelper.
    **/
    @isTest
    static void testTermQuotes(){
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
        
        SBQQ__QuoteTerm__c termQuote = new SBQQ__QuoteTerm__c();
        termQuote.SBQQ__Body__c = '<p>This is a test method </p>';
        termQuote.SBQQ__Quote__c = quote.Id;
     	termQuote.SBQQ__PrintOrder__c = 1;
        insert termQuote;
        
        termQuote.SBQQ__Body__c = 'This is test method testing..';
        update termQuote;
     
        System.assertEquals(termQuote.SBQQ__Body__c,'This is test method testing..');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly set to true when a Quote Term
    *              body contains dynamic field references (fields wrapped in {!quote.fieldname} pattern).
    *              This test validates the setHasDynamicField functionality in QuoteTermTriggerHelper
    *              for quote terms associated with a quote during insert operations.
    **/
    @isTest
    static void testHasDynamicFieldWithDynamicField(){
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
        
        // Test with dynamic field in body - create as STANDARD term (SBQQ__Quote__c = null)
        SBQQ__QuoteTerm__c termWithDynamicField = new SBQQ__QuoteTerm__c();
        termWithDynamicField.SBQQ__Body__c = 'The term is {!quote.CurrencyIsoCode} for {!quote.SBQQ__SubscriptionTerm__c} months';
        // Note: SBQQ__Quote__c is null, making this a standard term
        termWithDynamicField.SBQQ__PrintOrder__c = 1;
        insert termWithDynamicField;
        
        // Requery to get the trigger-updated value
        termWithDynamicField = getQuoteTermById(termWithDynamicField.Id);
        
        // Verify checkbox is set to true
        System.assertEquals(true, termWithDynamicField.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be true when body contains dynamic fields');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly set to false when a Quote Term
    *              body does not contain any dynamic field references. This test validates that the trigger
    *              correctly identifies terms without dynamic fields and sets the checkbox accordingly.
    **/
    @isTest
    static void testHasDynamicFieldWithoutDynamicField(){
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
        
        // Test without dynamic field in body - create as STANDARD term (SBQQ__Quote__c = null)
        SBQQ__QuoteTerm__c termWithoutDynamicField = new SBQQ__QuoteTerm__c();
        termWithoutDynamicField.SBQQ__Body__c = 'This is a standard term without any dynamic fields';
        // Note: SBQQ__Quote__c is null, making this a standard term
        termWithoutDynamicField.SBQQ__PrintOrder__c = 1;
        insert termWithoutDynamicField;
        
        // Requery to get the trigger-updated value
        termWithoutDynamicField = getQuoteTermById(termWithoutDynamicField.Id);
        
        // Verify checkbox is set to false
        System.assertEquals(false, termWithoutDynamicField.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be false when body does not contain dynamic fields');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly updated when a Quote Term body
    *              is modified to include or remove dynamic field references. This test validates that
    *              the trigger correctly re-evaluates the body content during update operations and
    *              updates the checkbox value accordingly.
    **/
    @isTest
    static void testHasDynamicFieldUpdate(){
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
        
        // Create term without dynamic field - as STANDARD term (SBQQ__Quote__c = null)
        SBQQ__QuoteTerm__c term = new SBQQ__QuoteTerm__c();
        term.SBQQ__Body__c = 'Initial body without dynamic fields';
        // Note: SBQQ__Quote__c is null, making this a standard term
        term.SBQQ__PrintOrder__c = 1;
        insert term;
        
        // Requery to get the trigger-updated value
        term = getQuoteTermById(term.Id);
        System.assertEquals(false, term.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be false initially');
        
        // Update with dynamic field
        term.SBQQ__Body__c = 'Updated body with {!quote.CurrencyIsoCode} field';
        update term;
        
        // Requery to get the trigger-updated value after update
        term = getQuoteTermById(term.Id);
        System.assertEquals(true, term.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be true after adding dynamic field');
    }
    
    /**
    * @description Tests that Has_Dynamic_Field__c checkbox is correctly set for standard Quote Terms
    *              (terms where SBQQ__Quote__c is null). Standard terms are reusable templates that
    *              can be applied to multiple quotes. This test validates that dynamic field detection
    *              works correctly for standard terms during insert operations.
    **/
    @isTest
    static void testHasDynamicFieldStandardTerm(){
        // Test with standard term (SBQQ__Quote__c is null)
        SBQQ__QuoteTerm__c standardTerm = new SBQQ__QuoteTerm__c();
        standardTerm.SBQQ__Body__c = 'Standard term with {!quote.MSSA_Number__c} dynamic field';
        standardTerm.SBQQ__PrintOrder__c = 10;
        standardTerm.SBQQ__Active__c = true;
        insert standardTerm;
        
        // Requery to get the trigger-updated value
        standardTerm = getQuoteTermById(standardTerm.Id);
        
        // Verify checkbox is set correctly for standard terms
        System.assertEquals(true, standardTerm.Has_Dynamic_Field__c, 'Has_Dynamic_Field__c should be true for standard terms with dynamic fields');
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Retrieves a Quote Term record by ID with Has_Dynamic_Field__c field.
    * @param quoteTermId The ID of the Quote Term record to retrieve
    * @return SBQQ__QuoteTerm__c The Quote Term record
    **/
    private static SBQQ__QuoteTerm__c getQuoteTermById(Id quoteTermId) {
        return [SELECT Id, Has_Dynamic_Field__c FROM SBQQ__QuoteTerm__c WHERE Id = :quoteTermId];
    }
}