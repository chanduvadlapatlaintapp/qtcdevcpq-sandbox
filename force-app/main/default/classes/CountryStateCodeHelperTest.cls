@isTest
private class CountryStateCodeHelperTest {

    @isTest
    static void testGetCountryStateCodes() {
        Test.startTest();
        // Create a request wrapper instance with valid values
        CountryStateCodeHelper.RequestWrapper request = new CountryStateCodeHelper.RequestWrapper();
        request.billingCountry = 'United States'; // valid label
        request.billingState = 'California'; // valid label
        request.shippingCountry = 'US'; // valid ISO code
        request.shippingState = 'CA'; // valid ISO code
        
        // Create a list of request wrappers
        List<CountryStateCodeHelper.RequestWrapper> requests = new List<CountryStateCodeHelper.RequestWrapper> { request };

        // Call the method
        List<CountryStateCodeHelper.CountryStateCode> results = CountryStateCodeHelper.getCountryStateCodes(requests);
        
        // Assert that results are not null
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
        
        // Validate billing country and state codes
        System.assertEquals('US', results[0].billingCountryCode, 'The billing country code should match the expected ISO code.');
        System.assertEquals('CA', results[0].billingStateCode, 'The billing state code should match the expected ISO code.');
        
        // Validate shipping country and state codes
        System.assertEquals('US', results[0].shippingCountryCode, 'The shipping country code should match the expected ISO code.');
        System.assertEquals('CA', results[0].shippingStateCode, 'The shipping state code should match the expected ISO code.');

        Test.stopTest();
    }
    
    @isTest
    static void testGetCountryStateCodesWithMixedInputs() {
        Test.startTest();
        // Create a request wrapper instance with a mix of valid and invalid values
        CountryStateCodeHelper.RequestWrapper request = new CountryStateCodeHelper.RequestWrapper();
        request.billingCountry = 'United States'; // valid label
        request.billingState = 'Invalid State'; // invalid label
        request.shippingCountry = 'US'; // valid ISO code
        request.shippingState = 'Invalid State'; // invalid label
        
        // Create a list of request wrappers
        List<CountryStateCodeHelper.RequestWrapper> requests = new List<CountryStateCodeHelper.RequestWrapper> { request };

        // Call the method
        List<CountryStateCodeHelper.CountryStateCode> results = CountryStateCodeHelper.getCountryStateCodes(requests);
        
        // Assert that results are not null
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
        
        // Validate billing country code and state code
        System.assertEquals('US', results[0].billingCountryCode, 'The billing country code should match the expected ISO code.');
        System.assertEquals(null, results[0].billingStateCode, 'The billing state code should be null for invalid input.');

        // Validate shipping country and state codes
        System.assertEquals('US', results[0].shippingCountryCode, 'The shipping country code should match the expected ISO code.');
        System.assertEquals(null, results[0].shippingStateCode, 'The shipping state code should be null for invalid input.');

        Test.stopTest();
    }
}