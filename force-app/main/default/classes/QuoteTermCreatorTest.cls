/**
* @description       : Test class for QuoteTermCreator. This class provides comprehensive test coverage for
*                      the Term Quote consolidation functionality, including upserting new terms, updating
*                      existing terms, deleting obsolete terms, and handling dynamic field term updates.
*                      Tests validate that terms with Has_Dynamic_Field__c = true are updated only when the
*                      regenerated body actually differs, preserving user edits otherwise (BIZ-75350 / BIZ-78745).
*                      BIZ-78745: Key tests now invoke via record DML (quote updates) rather than calling
*                      QuoteTermCreator.consolidateOldAndNew() directly, ensuring the full call chain
*                      (trigger -> QuoteTermService -> QuoteTermValidator -> QuoteTermCreator) is exercised.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
@isTest
public class QuoteTermCreatorTest {

    /***********************************************************************************************
    *
    * Test Setup and Helper Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Creates test data including accounts, quotes, and quote terms for use in test methods.
    *              This method is called automatically by the test framework before each test method execution.
    **/
    @testSetup
    static void setupTestData() {
        // Create Automation Controls to bypass flows/processes that interfere with tests
        TestFactory.createSObject(
            new Automation_Controls__c(
                SetupOwnerId = UserInfo.getUserId()
            ), 'AutomationControlsDefaults'
        );
        
        // Create Account using TestFactory
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                BillingCountry = 'United States'
            ), 'AccountDefaults'
        );
        
        // Create Opportunity using TestFactory
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                AccountId = account.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting'
            ), 'OpportunityDefaults'
        );
        
        // Create Quote using TestFactory
        TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opportunity.Id
            ), 'SBQQQuoteDefaults'
        );
    }
    
    /***********************************************************************************************
    *
    * Test Methods - Direct consolidateOldAndNew() Tests
    *
    ***********************************************************************************************/
    
    /**
    * @description Tests the basic consolidation functionality with new and existing Term Quote records.
    *              Validates that:
    *              - New terms are inserted
    *              - Existing terms are updated
    *              - Obsolete terms are deleted
    **/
    @isTest
    static void testConsolidateOldAndNew() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create SBQQ__QuoteTerm__c records (Term__c field on Term_Quote__c is a lookup to SBQQ__QuoteTerm__c)
        List<SBQQ__QuoteTerm__c> quoteTerms = new List<SBQQ__QuoteTerm__c>();
        for (Integer i = 0; i < 5; i++) {
            quoteTerms.add((SBQQ__QuoteTerm__c)TestFactory.createSObject(
                new SBQQ__QuoteTerm__c(
                    SBQQ__Body__c = 'Term Body ' + i,
                    SBQQ__Quote__c = null,
                    SBQQ__Active__c = true,
                    SBQQ__PrintOrder__c = i
                )
            ));
        }

        // Build map of QuoteTerm IDs
        Map<Id, SBQQ__QuoteTerm__c> quoteTermsMap = new Map<Id, SBQQ__QuoteTerm__c>(quoteTerms);
        List<Id> quoteTermIds = new List<Id>(quoteTermsMap.keySet());

        // Create existing Term_Quote__c records (first 3 terms)
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();
        for (Integer i = 0; i < 3; i++) {
            existingTerms.add((Term_Quote__c)TestFactory.createSObject(
                new Term_Quote__c(
                    Quote__c = quote.Id,
                    Term__c = quoteTermIds[i],
                    Body__c = 'Existing Term Body ' + i,
                    Print_Order__c = i
                ), 'TermQuoteDefaults'
            ));
        }

        // Create new Term_Quote__c records (terms 1-4, overlapping with existing)
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>();
        for (Integer i = 1; i <= 4; i++) {
            newTerms.add(new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTermIds[i],
                Body__c = 'New Term Body ' + i,
                Print_Order__c = i,
                Validator_Modified__c = false,
                Modified__c = false
            ));
        }

        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();

        // Verify upserted records
        List<Term_Quote__c> upsertedTerms = getTermQuotesByTermIds(quoteTermIds);
        System.assertEquals(4, upsertedTerms.size(), 'Four terms should exist after upsert (terms 1-4).');
        
        // Verify updated existing terms (terms 1-2 should be updated)
        for (Term_Quote__c term : upsertedTerms) {
            if (term.Term__c == quoteTermIds[1] || term.Term__c == quoteTermIds[2]) {
                Integer expectedOrder = quoteTermIds.indexOf(term.Term__c);
                System.assertEquals('New Term Body ' + expectedOrder, term.Body__c, 
                    'Term body should be updated from new terms.');
                System.assertEquals(expectedOrder, term.Print_Order__c, 
                    'Print order should be updated.');
            }
        }

        // Verify deleted records (term 0 should be deleted)
        List<Term_Quote__c> deletedTerms = getTermQuotesByTermId(quoteTermIds[0]);
        System.assertEquals(0, deletedTerms.size(), 
            'Obsolete term (Term 0) should be deleted.');
    }

    /**
    * @description Tests consolidation with empty lists to ensure no errors occur and no DML operations
    *              are performed when there are no terms to process.
    **/
    @isTest
    static void testEmptyTerms() {
        // Test with empty lists
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>();
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();

        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();

        // Assert no records were upserted or deleted
        System.assertEquals(0, getTermQuoteCount(), 
            'No terms should exist when both lists are empty.');
    }

    /**
    * @description BIZ-75350 / BIZ-78745: Integration test that validates the FULL targeted regeneration
    *              path by updating a dynamic field on a quote that is already at 'Finalize OSA'.
    *              This triggers: Quote trigger -> QuoteTermService -> QuoteTermValidator.generateQuoteTermsForSpecificTerms
    *              -> getExistingTerms() (the query that was missing Dynamic_Field_Names__c) -> QuoteTermCreator.consolidateOldAndNew.
    *              
    *              This test would have caught the BIZ-78745 bug because it exercises getExistingTerms()
    *              which previously did not query Dynamic_Field_Names__c, causing a SObjectException
    *              in QuoteTermCreator.getTermsForUpsert().
    **/
    @isTest
    static void testForceUpdateForDynamicFieldTermsViaDML() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        Account account = getTestAccount();
        
        // Create Quote Term with dynamic field referencing OSA_Number__c
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'OSA Number is {!quote.OSA_Number__c}',
                SBQQ__Quote__c = null
            ), 'SBQQQuoteTermDefaults'
        );
        
        // Verify parent term has dynamic field flags set
        quoteTerm = [SELECT Id, Has_Dynamic_Field__c, Dynamic_Field_Names__c FROM SBQQ__QuoteTerm__c WHERE Id = :quoteTerm.Id];
        System.assertEquals(true, quoteTerm.Has_Dynamic_Field__c,
            'Trigger should set Has_Dynamic_Field__c = true on parent SBQQ__QuoteTerm__c');
        
        // Prepare quote for 'Finalize OSA' (creates addresses, quote lines, etc.)
        prepareQuoteForFinalizeOSA(quote, account.Id);
        
        // Transition quote to 'Finalize OSA' — this triggers full regeneration via @future.
        // Since we can only call Test.startTest() once, we set the stage first,
        // then manually create the Term_Quote__c (simulating the full regeneration result),
        // and use the single Test.startTest/stopTest block for the targeted regeneration path.
        quote.Quote_Stage__c = 'Finalize OSA';
        if(String.isBlank(quote.Bill_To_Account__c) || String.isBlank(quote.Ship_To_Account__c)) {
            quote.Bill_To_Account__c = account.Id;
            quote.Ship_To_Account__c = account.Id;
        }
        update quote;
        
        Id quoteId = quote.Id;
        Id quoteTermId = quoteTerm.Id;
        
        // Create a Term_Quote__c to simulate the result of full regeneration.
        // This avoids needing a Test.startTest/stopTest to flush the @future from stage transition,
        // reserving the single allowed Test.startTest/stopTest for the targeted regeneration path.
        TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quoteId,
                Term__c = quoteTermId,
                Body__c = 'OSA Number is OLD-VALUE',
                Print_Order__c = 1,
                Modified__c = true
            ), 'TermQuoteDefaults'
        );
        
        // Now change OSA_Number__c on the quote (while already at 'Finalize OSA')
        // This triggers the TARGETED regeneration path via QuoteTermService -> QuoteTermValidator.generateQuoteTermsForSpecificTerms
        quote = [SELECT Id, OSA_Number__c, Quote_Stage__c, Bill_To_Account__c, Ship_To_Account__c FROM SBQQ__Quote__c WHERE Id = :quoteId];
        quote.OSA_Number__c = 'TEST-OSA-78745';
        
        Test.startTest();
        update quote; // This fires the quote trigger -> QuoteTermService.addQuoteTerms -> targeted regeneration
        Test.stopTest();
        
        // Verify the term was regenerated (body updated) and Modified__c was cleared
        List<Term_Quote__c> updatedTerms = [
            SELECT Id, Body__c, Modified__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c
            FROM Term_Quote__c 
            WHERE Quote__c = :quoteId AND Term__c = :quoteTermId
        ];
        
        System.assert(!updatedTerms.isEmpty(), 
            'Term Quote should exist after targeted regeneration');
        // The targeted regeneration should have completed without SObjectException (BIZ-78745 fix)
        // and the term should have been updated (Modified__c cleared, body regenerated)
        System.assertEquals(false, updatedTerms[0].Modified__c,
            'Modified__c should be cleared by targeted regeneration (BIZ-78745: getExistingTerms now queries Dynamic_Field_Names__c)');
        System.assert(updatedTerms[0].Body__c != 'OSA Number is OLD-VALUE',
            'Body should be refreshed because the dynamic field value changed');
    }
    
    /**
    * @description BIZ-78745: Tests that preserveModified=true (Conga/stage transition path)
    *              respects Modified__c unconditionally, preserving user edits on dynamic terms
    *              even when the regenerated body is identical.
    **/
    @isTest
    static void testPreserveModifiedDynamicTermWhenBodyUnchanged() {
        SBQQ__Quote__c quote = getTestQuote();
        
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'OSA Number is {!quote.OSA_Number__c}',
                SBQQ__Quote__c = null
            ), 'SBQQQuoteTermDefaults'
        );
        
        String sharedBody = 'OSA Number is CURRENT-VALUE';
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = sharedBody,
                Print_Order__c = 1,
                Modified__c = true
            ), 'TermQuoteDefaults'
        );
        
        // Re-query to pick up Has_Dynamic_Field__c and Dynamic_Field_Names__c formula values
        existingTerm = [
            SELECT Id, Term__c, Quote__c, Body__c, Print_Order__c, Validator_Modified__c,
                   Modified__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c
            FROM Term_Quote__c WHERE Id = :existingTerm.Id
        ];
        System.assertEquals(true, existingTerm.Has_Dynamic_Field__c,
            'Has_Dynamic_Field__c formula should derive true from parent');
        
        // Regenerated term with the SAME body (no dynamic field value changed)
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = sharedBody,
            Print_Order__c = 1
        );
        
        Test.startTest();
        // preserveModified=true: full regeneration path — user edits must be preserved
        QuoteTermCreator.consolidateOldAndNew(
            new List<Term_Quote__c>{ newTerm },
            new List<Term_Quote__c>{ existingTerm },
            true
        );
        Test.stopTest();
        
        Term_Quote__c result = getTermQuoteForUpdateById(existingTerm.Id);
        System.assertEquals(true, result.Modified__c,
            'Modified__c should remain true when preserveModified=true (Conga/full regen path)');
        System.assertEquals(sharedBody, result.Body__c,
            'Body should be preserved when preserveModified=true');
    }
    
    /**
    * @description BIZ-78745: Tests that preserveModified=false (targeted regeneration from trigger)
    *              overrides Modified__c for dynamic terms, allowing the system to refresh them
    *              when a dynamic field value actually changed on the quote.
    **/
    @isTest
    static void testOverwriteModifiedDynamicTermWhenBodyChanged() {
        SBQQ__Quote__c quote = getTestQuote();
        
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'OSA Number is {!quote.OSA_Number__c}',
                SBQQ__Quote__c = null
            ), 'SBQQQuoteTermDefaults'
        );
        
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'OSA Number is OLD-VALUE',
                Print_Order__c = 1,
                Modified__c = true
            ), 'TermQuoteDefaults'
        );
        
        // Re-query to pick up Has_Dynamic_Field__c and Dynamic_Field_Names__c formula values
        existingTerm = [
            SELECT Id, Term__c, Quote__c, Body__c, Print_Order__c, Validator_Modified__c,
                   Modified__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c
            FROM Term_Quote__c WHERE Id = :existingTerm.Id
        ];
        System.assertEquals(true, existingTerm.Has_Dynamic_Field__c,
            'Has_Dynamic_Field__c formula should derive true from parent');
        
        // Regenerated term with DIFFERENT body (dynamic field value changed)
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = 'OSA Number is NEW-VALUE',
            Print_Order__c = 1
        );
        
        Test.startTest();
        // preserveModified=false: targeted regeneration path — dynamic terms get overwritten
        QuoteTermCreator.consolidateOldAndNew(
            new List<Term_Quote__c>{ newTerm },
            new List<Term_Quote__c>{ existingTerm },
            false
        );
        Test.stopTest();
        
        Term_Quote__c result = getTermQuoteForUpdateById(existingTerm.Id);
        System.assertEquals(false, result.Modified__c,
            'Modified__c should be cleared when preserveModified=false (targeted regen) for dynamic term');
        System.assertEquals('OSA Number is NEW-VALUE', result.Body__c,
            'Body should be updated when preserveModified=false for dynamic term');
    }
    
    /**
    * @description BIZ-78745: Tests that preserveModified=true preserves user edits on dynamic terms
    *              even when the body has been modified by the user (body differs from regenerated).
    *              This is the exact Conga gap scenario: user adds static text to a dynamic term,
    *              then clicks OSA Document — the edit must not be overwritten.
    **/
    @isTest
    static void testPreserveModifiedDynamicTermWhenBodyEdited() {
        SBQQ__Quote__c quote = getTestQuote();
        
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'OSA Number is {!quote.OSA_Number__c}',
                SBQQ__Quote__c = null
            ), 'SBQQQuoteTermDefaults'
        );
        
        // User edited the term — body differs from what the template would generate
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'OSA Number is CURRENT-VALUE. See Appendix B',
                Print_Order__c = 1,
                Modified__c = true
            ), 'TermQuoteDefaults'
        );
        
        existingTerm = [
            SELECT Id, Term__c, Quote__c, Body__c, Print_Order__c, Validator_Modified__c,
                   Modified__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c
            FROM Term_Quote__c WHERE Id = :existingTerm.Id
        ];
        
        // Regenerated body from template (no dynamic value change, just template output)
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = 'OSA Number is CURRENT-VALUE',
            Print_Order__c = 1
        );
        
        Test.startTest();
        // preserveModified=true: full regeneration path — user-edited body must not be overwritten
        QuoteTermCreator.consolidateOldAndNew(
            new List<Term_Quote__c>{ newTerm },
            new List<Term_Quote__c>{ existingTerm },
            true
        );
        Test.stopTest();
        
        Term_Quote__c result = getTermQuoteForUpdateById(existingTerm.Id);
        System.assertEquals(true, result.Modified__c,
            'Modified__c should remain true — preserveModified=true protects user edits even when body differs');
        System.assertEquals('OSA Number is CURRENT-VALUE. See Appendix B', result.Body__c,
            'User-edited body must be preserved when preserveModified=true');
    }
    
    /**
    * @description Tests that Term Quotes with Has_Dynamic_Field__c = false and Modified__c = true
    *              are NOT updated (preserves manual modifications for non-dynamic terms).
    *              This validates that only dynamic field terms are force-updated.
    **/
    @isTest
    static void testPreserveModificationsForNonDynamicTerms() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term without dynamic fields
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term without dynamic fields',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create existing Term Quote that has been manually modified
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Manually modified body - should be preserved',
                Print_Order__c = 1,
                Modified__c = true
            ), 'TermQuoteDefaults'
        );
        
        // Create new Term Quote from Quote Term model
        Term_Quote__c newTerm = new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'New regenerated body',
                Print_Order__c = 1
        );
        
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{ newTerm };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>{ existingTerm };
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify that the existing term was NOT updated because Modified__c = true and Has_Dynamic_Field__c = false
        Term_Quote__c preservedTerm = getTermQuoteForUpdateById(existingTerm.Id);
        System.assertEquals('Manually modified body - should be preserved', preservedTerm.Body__c,
            'Term with Has_Dynamic_Field__c = false and Modified__c = true should preserve manual modifications');
    }
    
    /**
    * @description Tests that new Term Quotes are inserted when they don't exist in the existing list.
    *              Validates the insert path of the consolidation logic.
    **/
    @isTest
    static void testInsertNewTerms() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create SBQQ__QuoteTerm__c records
        List<SBQQ__QuoteTerm__c> quoteTerms = new List<SBQQ__QuoteTerm__c>();
        for (Integer i = 0; i < 3; i++) {
            quoteTerms.add((SBQQ__QuoteTerm__c)TestFactory.createSObject(
                new SBQQ__QuoteTerm__c(
                    SBQQ__Body__c = 'Term Body ' + i,
                    SBQQ__Quote__c = null,
                    SBQQ__Active__c = true,
                    SBQQ__PrintOrder__c = i
                )
            ));
        }
        
        // Create new Term Quotes (no existing terms)
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>();
        for (Integer i = 0; i < 3; i++) {
            newTerms.add(new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerms[i].Id,
                Body__c = 'New Term Body ' + i,
                Print_Order__c = i
            ));
        }
        
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify all new terms were inserted
        List<Term_Quote__c> insertedTerms = [
            SELECT Id, Body__c, Print_Order__c 
            FROM Term_Quote__c 
            WHERE Quote__c = :quote.Id
            ORDER BY Print_Order__c
        ];
        System.assertEquals(3, insertedTerms.size(), 
            'All three new terms should be inserted.');
        for (Integer i = 0; i < 3; i++) {
            System.assertEquals('New Term Body ' + i, insertedTerms[i].Body__c,
                'Term body should match new term body.');
        }
    }
    
    /**
    * @description Tests that Term Quotes not in the new list are deleted (obsolete terms).
    *              Validates the delete path of the consolidation logic.
    **/
    @isTest
    static void testDeleteObsoleteTerms() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create SBQQ__QuoteTerm__c records
        List<SBQQ__QuoteTerm__c> quoteTerms = new List<SBQQ__QuoteTerm__c>();
        for (Integer i = 0; i < 3; i++) {
            quoteTerms.add((SBQQ__QuoteTerm__c)TestFactory.createSObject(
                new SBQQ__QuoteTerm__c(
                    SBQQ__Body__c = 'Term Body ' + i,
                    SBQQ__Quote__c = null,
                    SBQQ__Active__c = true,
                    SBQQ__PrintOrder__c = i
                )
            ));
        }
        
        // Create existing Term Quotes (all 3 terms)
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();
        for (Integer i = 0; i < 3; i++) {
            existingTerms.add((Term_Quote__c)TestFactory.createSObject(
                new Term_Quote__c(
                    Quote__c = quote.Id,
                    Term__c = quoteTerms[i].Id,
                    Body__c = 'Existing Term Body ' + i,
                    Print_Order__c = i
                ), 'TermQuoteDefaults'
            ));
        }
        
        // Create new Term Quotes (only first 2 terms - term 2 should be deleted)
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>();
        for (Integer i = 0; i < 2; i++) {
            newTerms.add(new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerms[i].Id,
                Body__c = 'New Term Body ' + i,
                Print_Order__c = i
            ));
        }
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify term 2 was deleted
        List<Term_Quote__c> remainingTerms = [
            SELECT Id, Term__c 
            FROM Term_Quote__c 
            WHERE Quote__c = :quote.Id
        ];
        System.assertEquals(2, remainingTerms.size(), 
            'Only two terms should remain after deletion.');
        
        // Verify deleted term is not in the list
        Set<Id> remainingTermIds = new Set<Id>();
        for (Term_Quote__c term : remainingTerms) {
            remainingTermIds.add(term.Term__c);
        }
        System.assert(!remainingTermIds.contains(quoteTerms[2].Id),
            'Term 2 should be deleted as it is obsolete.');
    }
    
    /**
    * @description Tests that Validator_Modified__c flag is toggled when updating existing terms.
    *              This validates the toggle logic in getTermsForUpsert.
    **/
    @isTest
    static void testToggleValidatorModifiedFlag() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term using TestFactory
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term Body',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create existing Term Quote with Validator_Modified__c = false
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Existing body',
                Print_Order__c = 1
            ), 'TermQuoteDefaults'
        );
        
        // Create new Term Quote
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = 'New body',
            Print_Order__c = 1
        );
        
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{ newTerm };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>{ existingTerm };
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify Validator_Modified__c was toggled to true
        Term_Quote__c updatedTerm = [
            SELECT Id, Validator_Modified__c, Body__c 
            FROM Term_Quote__c 
            WHERE Id = :existingTerm.Id
        ];
        System.assertEquals(true, updatedTerm.Validator_Modified__c,
            'Validator_Modified__c should be toggled from false to true.');
        System.assertEquals('New body', updatedTerm.Body__c,
            'Body should be updated.');
    }
    
    /**
    * @description Tests error handling when invalid data is provided (invalid Term__c lookup).
    *              Validates that errors are logged but don't cause exceptions.
    *              With allOrNone=false, this test will trigger the error handling paths
    *              in persistTerms method, including the nested if statement
    *              that checks for affected fields.
    **/
    @isTest
    static void testErrorHandling() {
        // Get test quote
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create a valid Quote Term to get a valid ID format, then delete it
        // This ensures we use a properly formatted ID that doesn't exist
        SBQQ__QuoteTerm__c tempTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Temp Term',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        Id invalidTermId = tempTerm.Id;
        delete tempTerm;
        
        // Test error handling - invalid Term__c lookup (non-existent record)
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = invalidTermId,
                Body__c = 'Invalid Term - non-existent Term__c'
            )
        };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();

        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify no terms were created (DML error prevents insert due to invalid Term__c)
        Integer termCount = [SELECT COUNT() FROM Term_Quote__c WHERE Quote__c = :quote.Id];
        System.assertEquals(0, termCount, 
            'No terms should be created when Term__c references a non-existent record.');
    }
    
    /**
    * @description Tests error handling in deleteTerms when attempting to delete non-existent records.
    *              Validates that errors are logged but don't cause exceptions.
    **/
    @isTest
    static void testDeleteErrorHandling() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term Body',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create a valid term first
        Term_Quote__c validTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Valid term',
                Print_Order__c = 1
            ), 'TermQuoteDefaults'
        );
        
        // Capture the ID
        Id termId = validTerm.Id;
        
        // Delete it manually
        delete validTerm;
        
        // Create a Term_Quote__c with the deleted record's ID
        Term_Quote__c nonExistentTerm = new Term_Quote__c(
            Id = termId,
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id
        );
        
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>();
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>{ nonExistentTerm };

        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify no terms exist
        System.assertEquals(0, [SELECT COUNT() FROM Term_Quote__c WHERE Quote__c = :quote.Id], 
            'No terms should exist after attempting to delete non-existent record.');
    }
    
    /**
    * @description Tests that terms with Modified__c = false are updated when Has_Dynamic_Field__c = false.
    *              Validates the update path for non-dynamic terms that haven't been manually modified.
    **/
    @isTest
    static void testUpdateNonDynamicTermWhenNotModified() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term without dynamic fields
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term without dynamic fields',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create existing Term Quote that has NOT been manually modified
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Original body',
                Print_Order__c = 1
            ), 'TermQuoteDefaults'
        );
        
        // Create new Term Quote from Quote Term model
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = 'Updated body',
            Print_Order__c = 1
        );
        
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{ newTerm };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>{ existingTerm };
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify that the existing term was updated because Modified__c = false
        Term_Quote__c updatedTerm = getTermQuoteForUpdateById(existingTerm.Id);
        System.assertEquals('Updated body', updatedTerm.Body__c,
            'Term with Has_Dynamic_Field__c = false and Modified__c = false should be updated');
    }
    
    /**
    * @description Tests that Validator_Modified__c flag is toggled from true to false when updating existing terms.
    *              This validates the toggle logic works in both directions.
    **/
    @isTest
    static void testToggleValidatorModifiedFlagFromTrueToFalse() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term using TestFactory
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term Body',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create existing Term Quote with Validator_Modified__c = true
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Existing body',
                Print_Order__c = 1,
                Validator_Modified__c = true
            ), 'TermQuoteDefaults'
        );
        
        // Create new Term Quote
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = 'New body',
            Print_Order__c = 1
        );
        
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{ newTerm };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>{ existingTerm };
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify Validator_Modified__c was toggled to false
        Term_Quote__c updatedTerm = [
            SELECT Id, Validator_Modified__c, Body__c 
            FROM Term_Quote__c 
            WHERE Id = :existingTerm.Id
        ];
        System.assertEquals(false, updatedTerm.Validator_Modified__c,
            'Validator_Modified__c should be toggled from true to false.');
        System.assertEquals('New body', updatedTerm.Body__c,
            'Body should be updated.');
    }
    
    /**
    * @description Tests that terms with null Term__c values are handled gracefully.
    *              Validates that getTermsById handles null Term__c values without errors.
    **/
    @isTest
    static void testHandleTermsWithNullTermId() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term Body',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create new Term with null Term__c (edge case)
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = null,
                Body__c = 'Term with null Term__c',
                Print_Order__c = 1
            ),
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Term with valid Term__c',
                Print_Order__c = 2
            )
        };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();

        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify that the term with valid Term__c was inserted
        List<Term_Quote__c> insertedTerms = [
            SELECT Id, Term__c, Body__c 
            FROM Term_Quote__c 
            WHERE Quote__c = :quote.Id AND Term__c = :quoteTerm.Id
        ];
        System.assert(insertedTerms.size() >= 1, 
            'Term with valid Term__c should be inserted.');
        System.assertEquals(quoteTerm.Id, insertedTerms[0].Term__c,
            'Inserted term should have valid Term__c.');
    }
    
    /**
    * @description Tests edge case where getTermsForDelete processes terms with various conditions.
    *              This ensures the String.isNotBlank check and map key iteration paths are covered.
    **/
    @isTest
    static void testGetTermsForDeleteEdgeCases() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Terms
        List<SBQQ__QuoteTerm__c> quoteTerms = new List<SBQQ__QuoteTerm__c>();
        for (Integer i = 0; i < 3; i++) {
            quoteTerms.add((SBQQ__QuoteTerm__c)TestFactory.createSObject(
                new SBQQ__QuoteTerm__c(
                    SBQQ__Body__c = 'Term Body ' + i,
                    SBQQ__Quote__c = null,
                    SBQQ__Active__c = true,
                    SBQQ__PrintOrder__c = i
                )
            ));
        }
        
        // Create existing terms (all 3)
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();
        for (Integer i = 0; i < 3; i++) {
            existingTerms.add((Term_Quote__c)TestFactory.createSObject(
                new Term_Quote__c(
                    Quote__c = quote.Id,
                    Term__c = quoteTerms[i].Id,
                    Body__c = 'Existing Term ' + i,
                    Print_Order__c = i
                ), 'TermQuoteDefaults'
            ));
        }
        
        // Create new terms (only first 1, so terms 1-2 should be deleted)
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerms[0].Id,
                Body__c = 'New Term 0',
                Print_Order__c = 0
            )
        };

        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify terms 1-2 were deleted
        List<Term_Quote__c> remainingTerms = [
            SELECT Id, Term__c 
            FROM Term_Quote__c 
            WHERE Quote__c = :quote.Id
        ];
        System.assertEquals(1, remainingTerms.size(), 
            'Only one term should remain after deletion of obsolete terms.');
        System.assertEquals(quoteTerms[0].Id, remainingTerms[0].Term__c,
            'Remaining term should be term 0.');
    }
    
    /**
    * @description Tests edge case where existing term has Modified__c = false and Has_Dynamic_Field__c = true.
    *              This should result in an update.
    **/
    @isTest
    static void testUpdateDynamicTermWhenNotModified() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term with dynamic field
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term with {!quote.CurrencyIsoCode} field',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create existing Term Quote that has NOT been manually modified but has dynamic fields
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Original body with dynamic field',
                Print_Order__c = 1
            ), 'TermQuoteDefaults'
        );
        
        // Create new Term Quote from Quote Term model
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = 'Updated body with new dynamic field value',
            Print_Order__c = 1
        );
        
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{ newTerm };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>{ existingTerm };
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify that the existing term was updated because Modified__c = false
        Term_Quote__c updatedTerm = getTermQuoteForUpdateById(existingTerm.Id);
        System.assertEquals('Updated body with new dynamic field value', updatedTerm.Body__c,
            'Term with Modified__c = false should be updated regardless of Has_Dynamic_Field__c value');
    }
    
    /**
    * @description Tests that terms with same Term__c but different Quotes are handled correctly
    *              when both are in the new terms list. Validates map key uniqueness behavior.
    **/
    @isTest
    static void testMultipleQuotesWithSameTerm() {
        // Get test data
        SBQQ__Quote__c quote1 = getTestQuote();
        
        // Create second quote
        Account account = getTestAccount();
        Opportunity opp = [SELECT Id FROM Opportunity WHERE AccountId = :account.Id LIMIT 1];
        SBQQ__Quote__c quote2 = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75),
                SBQQ__Account__c = account.Id,
                SBQQ__Opportunity2__c = opp.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Create Quote Term
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term Body',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 1
            )
        );
        
        // Create new terms for both quotes using same Term__c
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{
            new Term_Quote__c(
                Quote__c = quote1.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Term for Quote 1',
                Print_Order__c = 1
            ),
            new Term_Quote__c(
                Quote__c = quote2.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'Term for Quote 2',
                Print_Order__c = 1
            )
        };
        
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();

        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify only one term was inserted (the last one in the list, due to map overwrite)
        List<Term_Quote__c> insertedTerms = [
            SELECT Id, Quote__c, Term__c 
            FROM Term_Quote__c 
            WHERE Term__c = :quoteTerm.Id
        ];
        System.assertEquals(1, insertedTerms.size(), 
            'Only one term should be inserted when same Term__c is used (map overwrites).');
    }
    
    /**
    * @description Tests bulk operations with multiple terms to ensure the method handles larger datasets
    *              efficiently. This validates scalability of the consolidation logic.
    **/
    @isTest
    static void testBulkConsolidation() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create multiple Quote Terms using createSObjectList for bulk insert
        List<SBQQ__QuoteTerm__c> quoteTerms = (List<SBQQ__QuoteTerm__c>)TestFactory.createSObjectList(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'Term Body',
                SBQQ__Quote__c = null,
                SBQQ__Active__c = true,
                SBQQ__PrintOrder__c = 0
            ), 50
        );
        
        // Create existing terms (first 30)
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>();
        for (Integer i = 0; i < 30; i++) {
            existingTerms.add((Term_Quote__c)TestFactory.createSObject(
                new Term_Quote__c(
                    Quote__c = quote.Id,
                    Term__c = quoteTerms[i].Id,
                    Body__c = 'Existing Body ' + i,
                    Print_Order__c = i
                ), 'TermQuoteDefaults'
            ));
        }
        
        // Create new terms (terms 20-49, overlapping with existing)
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>();
        for (Integer i = 20; i < 50; i++) {
            newTerms.add(new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerms[i].Id,
                Body__c = 'New Body ' + i,
                Print_Order__c = i,
                Modified__c = false
            ));
        }
        
            Test.startTest();
            // preserveModified=true: simulates full regeneration (Conga / stage transition)
            QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
            Test.stopTest();
        
        // Verify bulk operations completed successfully
        List<Term_Quote__c> allTerms = [
            SELECT Id, Term__c 
            FROM Term_Quote__c 
            WHERE Quote__c = :quote.Id
        ];
        System.assertEquals(30, allTerms.size(), 
            'Should have 30 terms after bulk consolidation (terms 20-49).');
        
        // Verify obsolete terms (0-19) were deleted
        Set<Id> remainingTermIds = new Set<Id>();
        for (Term_Quote__c term : allTerms) {
            remainingTermIds.add(term.Term__c);
        }
        for (Integer i = 0; i < 20; i++) {
            System.assert(!remainingTermIds.contains(quoteTerms[i].Id),
                'Term ' + i + ' should be deleted as obsolete.');
        }
    }
    
    /**
    * @description Tests that Modified__c flag remains false when a term is regenerated due to dynamic field updates.
    *              This validates the Flow logic that only sets Modified__c = true for user modifications,
    *              not system regenerations (BIZ-75350).
    **/
    @isTest
    static void testModifiedFlagRemainsUncheckedOnRegeneration() {
        // Get test data
        SBQQ__Quote__c quote = getTestQuote();
        
        // Create Quote Term with dynamic field
        SBQQ__QuoteTerm__c quoteTerm = (SBQQ__QuoteTerm__c)TestFactory.createSObject(
            new SBQQ__QuoteTerm__c(
                SBQQ__Body__c = 'OSA Number is {!quote.OSA_Number__c}',
                SBQQ__Quote__c = null
            ), 'SBQQQuoteTermDefaults'
        );
        
        // Re-query parent to verify trigger set Has_Dynamic_Field__c
        quoteTerm = [
            SELECT Id, Has_Dynamic_Field__c, Dynamic_Field_Names__c, SBQQ__Body__c 
            FROM SBQQ__QuoteTerm__c 
            WHERE Id = :quoteTerm.Id
        ];
        System.assertEquals(true, quoteTerm.Has_Dynamic_Field__c,
            'Trigger should set Has_Dynamic_Field__c = true on parent SBQQ__QuoteTerm__c');
        System.assert(String.isNotBlank(quoteTerm.Dynamic_Field_Names__c),
            'Trigger should populate Dynamic_Field_Names__c on parent SBQQ__QuoteTerm__c');
        
        // Create existing Term Quote (not manually modified)
        Term_Quote__c existingTerm = (Term_Quote__c)TestFactory.createSObject(
            new Term_Quote__c(
                Quote__c = quote.Id,
                Term__c = quoteTerm.Id,
                Body__c = 'OSA Number is OLD-VALUE',
                Print_Order__c = 1
            ), 'TermQuoteDefaults'
        );
        
        // Re-query to get formula field values including Dynamic_Field_Names__c (BIZ-78745 fix)
        existingTerm = [
            SELECT Id, Term__c, Quote__c, Body__c, Print_Order__c, Validator_Modified__c,
                   Modified__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c
            FROM Term_Quote__c 
            WHERE Id = :existingTerm.Id
        ];
        
        System.assertEquals(false, existingTerm.Modified__c,
            'Initial Modified__c should be false');
        System.assertEquals(true, existingTerm.Has_Dynamic_Field__c,
            'Has_Dynamic_Field__c formula should derive true from parent');
        
        // Create new Term Quote from regeneration (Body__c changed due to dynamic field update)
        Term_Quote__c newTerm = new Term_Quote__c(
            Quote__c = quote.Id,
            Term__c = quoteTerm.Id,
            Body__c = 'OSA Number is NEW-VALUE',
            Print_Order__c = 1
        );
        
        List<Term_Quote__c> newTerms = new List<Term_Quote__c>{ newTerm };
        List<Term_Quote__c> existingTerms = new List<Term_Quote__c>{ existingTerm };
        
        Test.startTest();
        // preserveModified=true: simulates full regeneration (Conga / stage transition)
        QuoteTermCreator.consolidateOldAndNew(newTerms, existingTerms, true);
        Test.stopTest();
        
        // Verify that Modified__c remains false after regeneration
        Term_Quote__c updatedTerm = [
            SELECT Id, Body__c, Modified__c, Validator_Modified__c
            FROM Term_Quote__c 
            WHERE Id = :existingTerm.Id
        ];
        
        System.assertEquals('OSA Number is NEW-VALUE', updatedTerm.Body__c,
            'Body should be updated with new dynamic field value');
        System.assertEquals(false, updatedTerm.Modified__c,
            'Modified__c should remain false when term is regenerated (system update, not user modification)');
        System.assertEquals(true, updatedTerm.Validator_Modified__c,
            'Validator_Modified__c should be toggled to true to track system update');
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Retrieves the test Account record created in @testSetup.
    * @return Account The test Account record
    **/
    private static Account getTestAccount() {
        return [SELECT Id FROM Account LIMIT 1];
    }
    
    /**
    * @description Retrieves the test Quote record created in @testSetup.
    * @return SBQQ__Quote__c The test Quote record
    **/
    private static SBQQ__Quote__c getTestQuote() {
        return [SELECT Id, Quote_Stage__c, Bill_To_Account__c, Ship_To_Account__c, Contract_Master_Terms__c FROM SBQQ__Quote__c LIMIT 1];
    }
    
    /**
    * @description Retrieves a Term Quote record by ID with fields needed for update verification.
    * @param termQuoteId The ID of the Term Quote record to retrieve
    * @return Term_Quote__c The Term Quote record with Body__c, Modified__c, Has_Dynamic_Field__c, and Dynamic_Field_Names__c
    **/
    private static Term_Quote__c getTermQuoteForUpdateById(Id termQuoteId) {
        return [
            SELECT Id, Body__c, Modified__c, Has_Dynamic_Field__c, Dynamic_Field_Names__c
            FROM Term_Quote__c 
            WHERE Id = :termQuoteId
        ];
    }
    
    /**
    * @description Retrieves Term Quote records by Term__c IDs.
    * @param termIds Collection of Term__c IDs to filter by
    * @return List<Term_Quote__c> List of Term Quote records
    **/
    private static List<Term_Quote__c> getTermQuotesByTermIds(List<Id> termIds) {
        return [
            SELECT Term__c, Body__c, Print_Order__c, Validator_Modified__c, Modified__c, Has_Dynamic_Field__c
            FROM Term_Quote__c
            WHERE Term__c IN :termIds
        ];
    }
    
    /**
    * @description Retrieves Term Quote records by a single Term__c ID.
    * @param termId The Term__c ID to filter by
    * @return List<Term_Quote__c> List of Term Quote records
    **/
    private static List<Term_Quote__c> getTermQuotesByTermId(Id termId) {
        return [
            SELECT Term__c 
            FROM Term_Quote__c 
            WHERE Term__c = :termId
        ];
    }
    
    /**
    * @description Gets the count of Term Quote records.
    * @return Integer The count of Term Quote records
    **/
    private static Integer getTermQuoteCount() {
        return [SELECT COUNT() FROM Term_Quote__c];
    }
    
    /**
    * @description Creates approved addresses for the given account and sets them on the quote.
    * @param accountId The Account ID to create the address for
    * @param quote The Quote to set the address on
    **/
    private static void setupApprovedAddressesForQuote(Id accountId, SBQQ__Quote__c quote) {
        Address__c address = (Address__c)TestFactory.createSObject(
            new Address__c(
                Account__c = accountId
            ), 'AddressDefaults'
        );
        
        quote.Bill_To_Address__c = address.Id;
        quote.Ship_To_Address__c = address.Id;
    }
    
    /**
    * @description Sets up a quote with required fields to allow transition to 'Finalize OSA'.
    *              This includes creating approved addresses and a quote line to satisfy validation rules.
    * @param quote The Quote to prepare
    * @param accountId The Account ID for the quote
    **/
    private static void prepareQuoteForFinalizeOSA(SBQQ__Quote__c quote, Id accountId) {
        Id quoteId = quote.Id;
        
        // Set Contract Master Terms (required validation field)
        if(String.isBlank(quote.Contract_Master_Terms__c)) {
            quote.Contract_Master_Terms__c = 'URL Terms';
        }
        
        // First update: Set Bill_To_Account__c and Ship_To_Account__c before setting addresses
        quote.Bill_To_Account__c = accountId;
        quote.Ship_To_Account__c = accountId;
        update quote;
        
        // Set up approved addresses (required for transition to 'Finalize OSA')
        setupApprovedAddressesForQuote(accountId, quote);
        update quote;
        
        // Create a product and quote line to satisfy validation rule requiring quote lines
        Product2 product = (Product2)TestFactory.createSObject(
            new Product2(
                Name = 'Test Product',
                ProductCode = 'TEST-PROD-001'
            ), 'ProductDefaults'
        );
        
        PricebookEntry pbe = (PricebookEntry)TestFactory.createSObject(
            new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 100
            ), 'PricebookEntryDefaults'
        );
        
        TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quoteId,
                SBQQ__Product__c = product.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__NetPrice__c = 100,
                SBQQ__CustomerPrice__c = 100
            ), 'SBQQQuoteLineDefaults'
        );
    }
}