global class SBQQ_QuoteBeforeTaxExtender implements AVA_MAPPER.IBeforeTaxCalculation {
    global void hookExtention(AVA_MAPPER.CreateTransactionModel model, Map<String, List<SObject>> headerResults) {
        // Ensure we have the Quote in headerResults
        if (headerResults != null && headerResults.containsKey('sbqq__quote__c')) { // lowercase object name
            List<SBQQ__Quote__c> quotes = (List<SBQQ__Quote__c>) headerResults.get('sbqq__quote__c');
            
            for (SBQQ__Quote__c quote : quotes) {
                // Use Subsidiary_No__c to override companyCode
                if (String.isNotBlank(quote.Subsidiary_No__c)) model.companyCode = quote.Subsidiary_No__c;
            }
        }
    }
}