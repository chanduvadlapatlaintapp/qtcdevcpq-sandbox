/**
 * @description       : Utility class for building OAuth 1.0a Authorization headers
 *                      for NetSuite Token-Based Authentication (TBA).
 *                      Loads credentials from the NetSuite_TBA_Credentials__c
 *                      Protected Custom Setting and signs requests using HMAC-SHA256.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Mar-05-2026
 * Jira               : BIZ-80292
 **/
public with sharing class NetSuiteOAuth1 {

    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Builds a complete OAuth 1.0a Authorization header value for the
     *              given HTTP method and URL using credentials from the Custom Setting.
     *              Supports URLs with query parameters — query params are included in
     *              the signature base string per OAuth 1.0a spec (RFC 5849).
     * @param httpMethod The HTTP verb (e.g. 'POST', 'GET')
     * @param requestUrl The full endpoint URL (may include query parameters)
     * @return The Authorization header value (e.g. 'OAuth realm="...", oauth_consumer_key="...", ...')
     */
    public static String buildAuthorizationHeader(String httpMethod, String requestUrl) {
        NetSuite_TBA_Credentials__c creds = getCredentials();

        // Separate base URL from query parameters
        String baseUrl = requestUrl;
        Map<String, String> queryParams = new Map<String, String>();
        if (requestUrl.contains('?')) {
            baseUrl = requestUrl.substring(0, requestUrl.indexOf('?'));
            String queryString = requestUrl.substring(requestUrl.indexOf('?') + 1);
            for (String param : queryString.split('&')) {
                List<String> keyValue = param.split('=', 2);
                if (keyValue.size() == 2) {
                    queryParams.put(keyValue[0], keyValue[1]);
                }
            }
        }

        String nonce = generateNonce();
        String timestamp = String.valueOf(DateTime.now().getTime() / 1000);

        Map<String, String> oauthParams = new Map<String, String>();
        oauthParams.put('oauth_consumer_key', creds.Consumer_Key__c);
        oauthParams.put('oauth_token', creds.Token_Id__c);
        oauthParams.put('oauth_nonce', nonce);
        oauthParams.put('oauth_timestamp', timestamp);
        oauthParams.put('oauth_signature_method', 'HMAC-SHA256');
        oauthParams.put('oauth_version', '1.0');

        // Merge query params + OAuth params for signature (per RFC 5849 §3.4.1.3)
        Map<String, String> allParams = new Map<String, String>();
        allParams.putAll(oauthParams);
        allParams.putAll(queryParams);

        String baseString = buildSignatureBaseString(httpMethod.toUpperCase(), baseUrl, allParams);
        String signature = generateSignature(baseString, creds.Consumer_Secret__c, creds.Token_Secret__c);

        oauthParams.put('oauth_signature', signature);

        return assembleHeader(creds.Account_Id__c, oauthParams);
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Credential Access
     *
     ***********************************************************************************************/

    /**
     * @description Loads credentials from the Protected Custom Setting.
     * @return NetSuite_TBA_Credentials__c org-default instance
     * @throws AuraHandledException if credentials are not configured
     */
    private static NetSuite_TBA_Credentials__c getCredentials() {
        NetSuite_TBA_Credentials__c creds = NetSuite_TBA_Credentials__c.getInstance();

        if (creds == null || String.isBlank(creds.Consumer_Key__c)) {
            Nebula.Logger.error('NetSuite OAuth: Credentials not configured in Custom Setting')
                .addTag('NetSuiteIntegration')
                .addTag('OAuth');
            Nebula.Logger.saveLog();

            AuraHandledException e = new AuraHandledException('NetSuite credentials are not configured. Contact your administrator.');
            e.setMessage('NetSuite credentials are not configured. Contact your administrator.');
            throw e;
        }

        return creds;
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Signature Generation
     *
     ***********************************************************************************************/

    /**
     * @description Generates the OAuth 1.0a signature base string.
     *              Format: METHOD&percent_encode(URL)&percent_encode(sorted_params)
     * @param httpMethod HTTP verb (uppercase)
     * @param baseUrl Endpoint URL
     * @param params Map of all oauth_* parameters (will be sorted alphabetically)
     * @return The signature base string
     */
    private static String buildSignatureBaseString(String httpMethod, String baseUrl, Map<String, String> params) {
        List<String> sortedKeys = new List<String>(params.keySet());
        sortedKeys.sort();

        List<String> paramParts = new List<String>();
        for (String key : sortedKeys) {
            paramParts.add(percentEncode(key) + '=' + percentEncode(params.get(key)));
        }

        String paramString = String.join(paramParts, '&');

        return httpMethod + '&' + percentEncode(baseUrl) + '&' + percentEncode(paramString);
    }

    /**
     * @description Signs the base string using HMAC-SHA256 with the composite signing key.
     *              Signing key format: percent_encode(consumer_secret)&percent_encode(token_secret)
     * @param baseString The signature base string
     * @param consumerSecret The consumer secret
     * @param tokenSecret The token secret
     * @return Base64-encoded HMAC-SHA256 signature
     */
    private static String generateSignature(String baseString, String consumerSecret, String tokenSecret) {
        String signingKey = percentEncode(consumerSecret) + '&' + percentEncode(tokenSecret);

        Blob signatureBlob = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(baseString),
            Blob.valueOf(signingKey)
        );

        return EncodingUtil.base64Encode(signatureBlob);
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Header Assembly
     *
     ***********************************************************************************************/

    /**
     * @description Assembles the final OAuth Authorization header string with all parameters.
     * @param accountId The NetSuite Account ID (used as realm)
     * @param oauthParams Map of all OAuth parameters including the signature
     * @return The complete Authorization header value
     */
    private static String assembleHeader(String accountId, Map<String, String> oauthParams) {
        List<String> headerParts = new List<String>();
        headerParts.add('realm="' + percentEncode(accountId) + '"');

        List<String> sortedKeys = new List<String>(oauthParams.keySet());
        sortedKeys.sort();

        for (String key : sortedKeys) {
            headerParts.add(key + '="' + percentEncode(oauthParams.get(key)) + '"');
        }

        return 'OAuth ' + String.join(headerParts, ', ');
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Utilities
     *
     ***********************************************************************************************/

    /**
     * @description Generates a cryptographically random nonce string.
     * @return A 32-character alphanumeric nonce
     */
    private static String generateNonce() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 32);
    }

    /**
     * @description RFC 3986 percent-encoding as required by OAuth 1.0a.
     *              Standard URL encoding uses '+' for spaces; OAuth 1.0a requires '%20'.
     * @param value The string to encode
     * @return The percent-encoded string
     */
    @TestVisible
    private static String percentEncode(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        return EncodingUtil.urlEncode(value, 'UTF-8')
            .replace('+', '%20')
            .replace('*', '%2A')
            .replace('%7E', '~');
    }
}