/**
 * @description       : Test class for NetSuiteOAuth1 — verifies OAuth 1.0a header generation,
 *                      signature structure, nonce uniqueness, and percent encoding.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Mar-05-2026
 * Jira               : BIZ-80292
 **/
@isTest
public class NetSuiteOAuth1Test {

    /***********************************************************************************************
     *
     * Test Setup
     *
     ***********************************************************************************************/

    @TestSetup
    static void makeData() {
        NetSuite_TBA_Credentials__c creds = new NetSuite_TBA_Credentials__c(
            Account_Id__c = '1234567_SB1',
            Consumer_Key__c = 'test-consumer-key-abc123',
            Consumer_Secret__c = 'test-consumer-secret-xyz789',
            Token_Id__c = 'test-token-id-def456',
            Token_Secret__c = 'test-token-secret-ghi012'
        );
        insert creds;
    }

    /***********************************************************************************************
     *
     * Test Methods — Header Structure
     *
     ***********************************************************************************************/

    @isTest
    static void testBuildAuthorizationHeader_StartsWithOAuth() {
        Test.startTest();
        String header = NetSuiteOAuth1.buildAuthorizationHeader('POST', 'https://1234567_SB1.suitetalk.api.netsuite.com/services/rest/query/v1/suiteql');
        Test.stopTest();

        System.assert(header.startsWith('OAuth '), 'Header should start with "OAuth "');
        System.assert(header.contains('realm='), 'Header should contain realm parameter');
    }

    @isTest
    static void testBuildAuthorizationHeader_ContainsAllRequiredParams() {
        Test.startTest();
        String header = NetSuiteOAuth1.buildAuthorizationHeader('POST', 'https://1234567_SB1.suitetalk.api.netsuite.com/services/rest/query/v1/suiteql');
        Test.stopTest();

        System.assert(header.contains('oauth_consumer_key='), 'Header should contain oauth_consumer_key');
        System.assert(header.contains('oauth_token='), 'Header should contain oauth_token');
        System.assert(header.contains('oauth_nonce='), 'Header should contain oauth_nonce');
        System.assert(header.contains('oauth_timestamp='), 'Header should contain oauth_timestamp');
        System.assert(header.contains('oauth_signature_method="HMAC-SHA256"'), 'Header should contain HMAC-SHA256 signature method');
        System.assert(header.contains('oauth_signature='), 'Header should contain oauth_signature');
        System.assert(header.contains('oauth_version="1.0"'), 'Header should contain version 1.0');
    }

    @isTest
    static void testBuildAuthorizationHeader_ContainsCredentialValues() {
        Test.startTest();
        String header = NetSuiteOAuth1.buildAuthorizationHeader('POST', 'https://1234567_SB1.suitetalk.api.netsuite.com/services/rest/query/v1/suiteql');
        Test.stopTest();

        System.assert(header.contains('test-consumer-key-abc123'), 'Header should contain consumer key value');
        System.assert(header.contains('test-token-id-def456'), 'Header should contain token ID value');
        System.assert(header.contains('1234567_SB1'), 'Header should contain account ID in realm');
    }

    /***********************************************************************************************
     *
     * Test Methods — Nonce Uniqueness
     *
     ***********************************************************************************************/

    @isTest
    static void testNonceUniqueness() {
        Test.startTest();
        String header1 = NetSuiteOAuth1.buildAuthorizationHeader('POST', 'https://example.com/api');
        String header2 = NetSuiteOAuth1.buildAuthorizationHeader('POST', 'https://example.com/api');
        Test.stopTest();

        // Extract nonces — they should differ between calls
        System.assertNotEquals(header1, header2, 'Two consecutive headers should differ (different nonce/timestamp)');
    }

    /***********************************************************************************************
     *
     * Test Methods — Percent Encoding
     *
     ***********************************************************************************************/

    @isTest
    static void testPercentEncode_Spaces() {
        String result = NetSuiteOAuth1.percentEncode('hello world');
        System.assertEquals('hello%20world', result, 'Spaces should be encoded as %20, not +');
    }

    @isTest
    static void testPercentEncode_Tildes() {
        String result = NetSuiteOAuth1.percentEncode('test~value');
        System.assertEquals('test~value', result, 'Tildes should remain unencoded per RFC 3986');
    }

    @isTest
    static void testPercentEncode_Asterisks() {
        String result = NetSuiteOAuth1.percentEncode('test*value');
        System.assertEquals('test%2Avalue', result, 'Asterisks should be encoded as %2A');
    }

    @isTest
    static void testPercentEncode_Null() {
        String result = NetSuiteOAuth1.percentEncode(null);
        System.assertEquals('', result, 'Null input should return empty string');
    }

    @isTest
    static void testPercentEncode_Empty() {
        String result = NetSuiteOAuth1.percentEncode('');
        System.assertEquals('', result, 'Empty input should return empty string');
    }

    /***********************************************************************************************
     *
     * Test Methods — Error Handling
     *
     ***********************************************************************************************/

    @isTest
    static void testBuildAuthorizationHeader_MissingCredentials() {
        // Clear the Consumer Key to simulate missing/incomplete credentials
        NetSuite_TBA_Credentials__c creds = [
            SELECT Id, Consumer_Key__c FROM NetSuite_TBA_Credentials__c LIMIT 1
        ];
        creds.Consumer_Key__c = '';
        update creds;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            NetSuiteOAuth1.buildAuthorizationHeader('POST', 'https://example.com/api');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('credentials'), 'Error should mention credentials');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException when credentials are missing');
    }
}