@isTest
private class SBQQ_QuoteBeforeTaxExtenderTest {

    

    @isTest
    static void testHookExtentionWithNullHeaderResults() {
        // Create the model instance
        AVA_MAPPER.CreateTransactionModel model = new AVA_MAPPER.CreateTransactionModel();
        String originalCompanyCode = model.companyCode;

        // Instantiate the extender and call the method with null headerResults
        SBQQ_QuoteBeforeTaxExtender extender = new SBQQ_QuoteBeforeTaxExtender();

        Test.startTest();
        extender.hookExtention(model, null);
        Test.stopTest();

        // Verify companyCode was not modified and no exception was thrown
        System.assertEquals(originalCompanyCode, model.companyCode, 'Company code should not be modified when headerResults is null');
    }

    @isTest
    static void testHookExtentionWithMissingQuoteKey() {
        // Create the headerResults map without the quote key
        Map<String, List<SObject>> headerResults = new Map<String, List<SObject>>();
        headerResults.put('some_other_key', new List<SObject>());

        // Create the model instance
        AVA_MAPPER.CreateTransactionModel model = new AVA_MAPPER.CreateTransactionModel();
        String originalCompanyCode = model.companyCode;

        // Instantiate the extender and call the method
        SBQQ_QuoteBeforeTaxExtender extender = new SBQQ_QuoteBeforeTaxExtender();

        Test.startTest();
        extender.hookExtention(model, headerResults);
        Test.stopTest();

        // Verify companyCode was not modified
        System.assertEquals(originalCompanyCode, model.companyCode, 'Company code should not be modified when quote key is missing');
    }

   

    @isTest
    static void testHookExtentionWithEmptyQuoteList() {
        // Create the headerResults map with empty quote list
        Map<String, List<SObject>> headerResults = new Map<String, List<SObject>>();
        headerResults.put('sbqq__quote__c', new List<SObject>());

        // Create the model instance
        AVA_MAPPER.CreateTransactionModel model = new AVA_MAPPER.CreateTransactionModel();
        String originalCompanyCode = model.companyCode;

        // Instantiate the extender and call the method
        SBQQ_QuoteBeforeTaxExtender extender = new SBQQ_QuoteBeforeTaxExtender();

        Test.startTest();
        extender.hookExtention(model, headerResults);
        Test.stopTest();

        // Verify companyCode was not modified
        System.assertEquals(originalCompanyCode, model.companyCode, 'Company code should not be modified when quote list is empty');
    }
}