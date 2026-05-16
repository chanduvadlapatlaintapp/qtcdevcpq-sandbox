public class CountryStateCodeHelper {

    @InvocableMethod(label='Get Billing and Shipping Country and State Code' description='Returns Country Code and State Code for Billing and Shipping based on provided values or labels, including ISO codes')
    public static List<CountryStateCode> getCountryStateCodes(List<RequestWrapper> requests) {
        List<CountryStateCode> results = new List<CountryStateCode>();

        for (RequestWrapper request : requests) {
            CountryStateCode result = new CountryStateCode();
            
            // Get Billing Country Code
            result.billingCountryCode = getCountryCodeFromLabelOrValue(request.billingCountry);

            // Get Shipping Country Code
            result.shippingCountryCode = getCountryCodeFromLabelOrValue(request.shippingCountry);

            // Get Billing State Code
            result.billingStateCode = getStateCodeFromLabelOrValue(result.billingCountryCode, request.billingState);

            // Get Shipping State Code
            result.shippingStateCode = getStateCodeFromLabelOrValue(result.shippingCountryCode, request.shippingState);
            
            results.add(result);
        }

        return results;
    }

    // Method to get the Country Code based on the Country Label or ISO Code from Billing_Address_Old__CountryCode__s
    private static String getCountryCodeFromLabelOrValue(String countryInput) {
        Schema.DescribeFieldResult countryField = Order_Change__c.Billing_Address_Old__CountryCode__s.getDescribe();
        List<Schema.PicklistEntry> countryPicklistValues = countryField.getPicklistValues();

        for (Schema.PicklistEntry entry : countryPicklistValues) {
            // First check if the input matches the ISO code (value)
            if (entry.getValue().equalsIgnoreCase(countryInput)) {
                return entry.getValue(); // Return the ISO country code directly
            }
            // Then check if the input matches the country label
            if (entry.getLabel().equalsIgnoreCase(countryInput)) {
                return entry.getValue(); // Return the ISO country code based on the label
            }
        }
        return null; // If not found
    }

    // Method to get the State Code based on the State Label or ISO Code from Billing_Address_New__StateCode__s
    private static String getStateCodeFromLabelOrValue(String countryCode, String stateInput) {
        Schema.DescribeFieldResult stateField = Order_Change__c.Billing_Address_New__StateCode__s.getDescribe();
        List<Schema.PicklistEntry> statePicklistValues = stateField.getPicklistValues();

        for (Schema.PicklistEntry entry : statePicklistValues) {
            // First check if the input matches the ISO code (value)
            if (entry.getValue().equalsIgnoreCase(stateInput)) {
                return entry.getValue(); // Return the ISO state code directly
            }
            // Then check if the input matches the state label
            if (entry.getLabel().equalsIgnoreCase(stateInput)) {
                return entry.getValue(); // Return the ISO state code based on the label
            }
        }
        return null; // If not found
    }

    // Wrapper class for input parameters
    public class RequestWrapper {
        @InvocableVariable(label='Billing Country' )
        public String billingCountry;

        @InvocableVariable(label='Billing State' )
        public String billingState;

        @InvocableVariable(label='Shipping Country')
        public String shippingCountry;

        @InvocableVariable(label='Shipping State' )
        public String shippingState;
    }

    // Wrapper class for the output result
    public class CountryStateCode {
        @InvocableVariable
        public String billingCountryCode;

        @InvocableVariable
        public String billingStateCode;

        @InvocableVariable
        public String shippingCountryCode;

        @InvocableVariable
        public String shippingStateCode;
    }
}