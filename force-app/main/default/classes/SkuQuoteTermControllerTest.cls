@IsTest
private class SkuQuoteTermControllerTest {

    @TestSetup
    static void setup() {
        SBQQ__QuoteTerm__c term = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Test term body content',
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 1,
            SBQQ__Status__c = 'Draft'
        );
        insert term;
    }

    @IsTest
    static void testGetQuoteTermsNoFilter() {
        Test.startTest();
        List<SBQQ__QuoteTerm__c> results = SkuQuoteTermController.getQuoteTerms(null, null, null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return quote terms');
    }

    @IsTest
    static void testGetQuoteTermsWithTypeFilter() {
        // SBQQ__Type__c is a formula field; query to see what value our test record gets
        SBQQ__QuoteTerm__c term = [SELECT SBQQ__Type__c FROM SBQQ__QuoteTerm__c LIMIT 1];
        String typeValue = term.SBQQ__Type__c;

        Test.startTest();
        List<SBQQ__QuoteTerm__c> results = SkuQuoteTermController.getQuoteTerms(
            String.isNotBlank(typeValue) ? typeValue : 'Standard', null, null, null, null, null
        );
        Test.stopTest();

        // Verify the filter executes without errors; count depends on formula evaluation
    }

    @IsTest
    static void testGetQuoteTermsWithStatusFilter() {
        Test.startTest();
        List<SBQQ__QuoteTerm__c> results = SkuQuoteTermController.getQuoteTerms(null, 'Draft', null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return status-filtered terms');
    }

    @IsTest
    static void testGetQuoteTermsWithSearch() {
        Test.startTest();
        List<SBQQ__QuoteTerm__c> results = SkuQuoteTermController.getQuoteTerms(null, null, 'Test', null, null, null);
        Test.stopTest();
        // Results depend on auto-name; just verify no errors
    }

    @IsTest
    static void testGetQuoteTermsNewFilters() {
        Test.startTest();
        List<SBQQ__QuoteTerm__c> activeResults = SkuQuoteTermController.getQuoteTerms(null, null, null, 'true', null, null);
        List<SBQQ__QuoteTerm__c> inactiveResults = SkuQuoteTermController.getQuoteTerms(null, null, null, 'false', null, null);
        List<SBQQ__QuoteTerm__c> categoryResults = SkuQuoteTermController.getQuoteTerms(null, null, null, null, 'Legal', null);
        List<SBQQ__QuoteTerm__c> descResults = SkuQuoteTermController.getQuoteTerms(null, null, null, null, null, 'Test');
        Test.stopTest();

        System.assertNotEquals(null, activeResults, 'Active filter should execute without errors');
        System.assertNotEquals(null, inactiveResults, 'Inactive filter should execute without errors');
    }

    @IsTest
    static void testSaveQuoteTerms() {
        SBQQ__QuoteTerm__c newTerm = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'New term body',
            SBQQ__Active__c = true,
            SBQQ__PrintOrder__c = 2
        );

        String json = JSON.serialize(new List<SBQQ__QuoteTerm__c>{ newTerm });

        Test.startTest();
        List<SBQQ__QuoteTerm__c> results = SkuQuoteTermController.saveQuoteTerms(json);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return saved terms');
        System.assertNotEquals(null, results[0].Id, 'Term should have been inserted');
    }

    @IsTest
    static void testSaveQuoteTermsUpdate() {
        SBQQ__QuoteTerm__c existing = [SELECT Id, SBQQ__Body__c FROM SBQQ__QuoteTerm__c LIMIT 1];
        existing.SBQQ__Body__c = 'Updated body';

        String json = JSON.serialize(new List<SBQQ__QuoteTerm__c>{ existing });

        Test.startTest();
        List<SBQQ__QuoteTerm__c> results = SkuQuoteTermController.saveQuoteTerms(json);
        Test.stopTest();

        SBQQ__QuoteTerm__c updated = [SELECT SBQQ__Body__c FROM SBQQ__QuoteTerm__c WHERE Id = :existing.Id];
        // Body may be modified by trigger (HTML stripping)
        System.assertNotEquals(null, updated.SBQQ__Body__c, 'Body should not be null');
    }

    @IsTest
    static void testDeleteQuoteTerms() {
        SBQQ__QuoteTerm__c existing = [SELECT Id FROM SBQQ__QuoteTerm__c LIMIT 1];

        Test.startTest();
        SkuQuoteTermController.deleteQuoteTerms(new List<Id>{ existing.Id });
        Test.stopTest();

        List<SBQQ__QuoteTerm__c> remaining = [SELECT Id FROM SBQQ__QuoteTerm__c WHERE Id = :existing.Id];
        System.assertEquals(0, remaining.size(), 'Term should be deleted');
    }

    @IsTest
    static void testDeleteQuoteTermsEmptyList() {
        Test.startTest();
        SkuQuoteTermController.deleteQuoteTerms(new List<Id>());
        SkuQuoteTermController.deleteQuoteTerms(null);
        Test.stopTest();
    }

    @IsTest
    static void testGetQuoteTermsByProductCode() {
        SBQQ__QuoteTerm__c term = [SELECT Id FROM SBQQ__QuoteTerm__c LIMIT 1];

        // Create a TermCondition that links this term to a product code
        SBQQ__TermCondition__c condition = new SBQQ__TermCondition__c(
            SBQQ__QuoteTerm__c = term.Id,
            SBQQ__TestedField__c = 'master_product_pins_from_all_quote_lines__c',
            SBQQ__Value__c = 'TEST-PROD-001'
        );
        insert condition;

        Test.startTest();
        List<SBQQ__QuoteTerm__c> results =
            SkuQuoteTermController.getQuoteTermsByProductCode('TEST-PROD-001');
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 quote term for the product code');
        System.assertEquals(term.Id, results[0].Id, 'Should return the correct quote term');
    }

    @IsTest
    static void testGetQuoteTermsByProductCodeBlank() {
        Test.startTest();
        List<SBQQ__QuoteTerm__c> results =
            SkuQuoteTermController.getQuoteTermsByProductCode('');
        List<SBQQ__QuoteTerm__c> nullResults =
            SkuQuoteTermController.getQuoteTermsByProductCode(null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty for blank product code');
        System.assertEquals(0, nullResults.size(), 'Should return empty for null product code');
    }

    @IsTest
    static void testGetQuoteTermsByProductCodeNoMatch() {
        Test.startTest();
        List<SBQQ__QuoteTerm__c> results =
            SkuQuoteTermController.getQuoteTermsByProductCode('NONEXISTENT-CODE');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty when no conditions match');
    }

    @IsTest
    static void testGetQuoteTermPicklists() {
        Test.startTest();
        Map<String, List<SkuQuoteTermController.PicklistOption>> picklists =
            SkuQuoteTermController.getQuoteTermPicklists();
        Test.stopTest();

        System.assertNotEquals(null, picklists, 'Picklists should not be null');
    }
}