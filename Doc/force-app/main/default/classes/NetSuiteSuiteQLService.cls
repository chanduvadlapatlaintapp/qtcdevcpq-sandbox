/**
 * @description       : Service class for executing SuiteQL queries against NetSuite
 *                      via the SuiteQL REST API. Uses NetSuiteOAuth1 for OAuth 1.0a
 *                      Token-Based Authentication. Supports pagination and returns
 *                      structured results via the SuiteQLResult wrapper.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Mar-05-2026
 * Jira               : BIZ-80292
 **/
public with sharing class NetSuiteSuiteQLService {

    /***********************************************************************************************
     *
     * Constants
     *
     ***********************************************************************************************/

    private static final String SUITEQL_PATH = '/services/rest/query/v1/suiteql';
    private static final Integer DEFAULT_LIMIT = 1000;
    private static final Integer CALLOUT_TIMEOUT_MS = 30000;

    /***********************************************************************************************
     *
     * Inner Classes / Wrappers
     *
     ***********************************************************************************************/

    /**
     * @description Wrapper for a SuiteQL query result containing parsed data
     *              and metadata about the query execution.
     */
    public class SuiteQLResult {
        @AuraEnabled public List<Map<String, Object>> items;
        @AuraEnabled public Integer totalResults;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;

        public SuiteQLResult() {
            this.items = new List<Map<String, Object>>();
            this.totalResults = 0;
            this.hasMore = false;
            this.success = false;
            this.errorMessage = null;
        }
    }

    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Executes a SuiteQL query against NetSuite with default limit and no offset.
     * @param query The SuiteQL SELECT statement
     * @return SuiteQLResult containing rows or error info
     */
    public static SuiteQLResult executeQuery(String query) {
        return executeQuery(query, DEFAULT_LIMIT, 0);
    }

    /**
     * @description Executes a SuiteQL query against NetSuite with pagination support.
     * @param query The SuiteQL SELECT statement
     * @param queryLimit Maximum rows to return (capped at 1000 by NetSuite)
     * @param offset Pagination offset (0-based)
     * @return SuiteQLResult containing rows or error info
     */
    public static SuiteQLResult executeQuery(String query, Integer queryLimit, Integer offset) {
        if (String.isBlank(query)) {
            SuiteQLResult result = new SuiteQLResult();
            result.errorMessage = 'Query cannot be blank.';
            return result;
        }

        if (queryLimit == null || queryLimit <= 0) {
            queryLimit = DEFAULT_LIMIT;
        }
        if (offset == null || offset < 0) {
            offset = 0;
        }

        String endpointUrl = buildEndpointUrl(queryLimit, offset);
        Integer statusCode = 0;

        try {
            HttpResponse response = sendRequest(endpointUrl, query);
            statusCode = response.getStatusCode();
            SuiteQLResult result = parseResponse(response);

            logCallout(endpointUrl, query, statusCode, result.success, result.errorMessage);
            return result;

        } catch (Exception e) {
            SuiteQLResult result = new SuiteQLResult();
            result.errorMessage = 'Callout failed: ' + e.getMessage();

            logCallout(endpointUrl, query, statusCode, false, e.getMessage());
            return result;
        }
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — HTTP Request
     *
     ***********************************************************************************************/

    /**
     * @description Builds the full SuiteQL endpoint URL from the Account ID in credentials,
     *              including limit and offset query parameters for pagination.
     * @param queryLimit Row limit
     * @param offset Pagination offset
     * @return Full SuiteQL endpoint URL with query parameters
     */
    private static String buildEndpointUrl(Integer queryLimit, Integer offset) {
        NetSuite_TBA_Credentials__c creds = NetSuite_TBA_Credentials__c.getInstance();
        String accountId = creds != null ? creds.Account_Id__c : '';
        // NetSuite API subdomains use hyphens, but Account IDs use underscores
        String subdomain = accountId.toLowerCase().replace('_', '-');

        String baseUrl = 'https://' + subdomain + '.suitetalk.api.netsuite.com' + SUITEQL_PATH;

        return baseUrl + '?limit=' + queryLimit + '&offset=' + offset;
    }

    /**
     * @description Constructs and sends the HTTP POST request to the SuiteQL endpoint.
     *              Sets required headers (Content-Type, Prefer, Authorization).
     * @param endpointUrl Full URL with query parameters
     * @param query The SuiteQL query string
     * @return HttpResponse from NetSuite
     */
    private static HttpResponse sendRequest(String endpointUrl, String query) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setTimeout(CALLOUT_TIMEOUT_MS);

        // Required NetSuite SuiteQL headers
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Prefer', 'transient');

        // OAuth 1.0a Authorization header — pass full URL so query params are included in signature
        String authHeader = NetSuiteOAuth1.buildAuthorizationHeader('POST', endpointUrl);
        req.setHeader('Authorization', authHeader);

        // SuiteQL request body
        Map<String, Object> body = new Map<String, Object>{ 'q' => query };
        req.setBody(JSON.serialize(body));

        Http http = new Http();
        return http.send(req);
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Response Parsing
     *
     ***********************************************************************************************/

    /**
     * @description Parses the JSON response from NetSuite into a SuiteQLResult.
     *              Handles both success (200) and error responses.
     * @param response The HTTP response from NetSuite
     * @return SuiteQLResult with parsed data or error details
     */
    private static SuiteQLResult parseResponse(HttpResponse response) {
        SuiteQLResult result = new SuiteQLResult();
        Integer statusCode = response.getStatusCode();

        if (statusCode == 200) {
            result.success = true;

            Map<String, Object> jsonBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

            // Parse items array
            List<Object> rawItems = (List<Object>) jsonBody.get('items');
            if (rawItems != null) {
                for (Object item : rawItems) {
                    result.items.add((Map<String, Object>) item);
                }
            }

            // Parse pagination metadata
            result.totalResults = jsonBody.containsKey('totalResults')
                ? (Integer) jsonBody.get('totalResults')
                : result.items.size();
            result.hasMore = jsonBody.containsKey('hasMore')
                ? (Boolean) jsonBody.get('hasMore')
                : false;

        } else {
            result.success = false;

            // Attempt to extract error message from NetSuite response
            try {
                Map<String, Object> errorBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                if (errorBody.containsKey('error')) {
                    Map<String, Object> errorDetail = (Map<String, Object>) errorBody.get('error');
                    String code = (String) errorDetail.get('code');
                    String message = (String) errorDetail.get('message');
                    result.errorMessage = 'NetSuite error ' + code + ': ' + message;
                } else {
                    result.errorMessage = 'HTTP ' + statusCode + ': ' + response.getBody();
                }
            } catch (Exception e) {
                result.errorMessage = 'HTTP ' + statusCode + ': ' + response.getBody();
            }
        }

        return result;
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Logging
     *
     ***********************************************************************************************/

    /**
     * @description Logs the callout details to Nebula Logger for observability and debugging.
     * @param endpointUrl URL that was called
     * @param query SuiteQL query that was executed
     * @param statusCode HTTP response status code
     * @param success Whether the call succeeded
     * @param errorMessage Error detail if the call failed
     */
    private static void logCallout(String endpointUrl, String query, Integer statusCode, Boolean success, String errorMessage) {
        if (success) {
            Nebula.Logger.info('NetSuite SuiteQL: Query executed successfully (HTTP ' + statusCode + ')')
                .addTag('NetSuiteIntegration')
                .addTag('SuiteQL');
        } else {
            Nebula.Logger.error('NetSuite SuiteQL: Callout failed (HTTP ' + statusCode + ') - ' + errorMessage)
                .addTag('NetSuiteIntegration')
                .addTag('SuiteQL');
        }
        Nebula.Logger.saveLog();
    }
}