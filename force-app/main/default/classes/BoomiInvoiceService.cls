/**
 * @description       : Service class for querying invoice data from the Boomi
 *                      middleware API. Replaces the direct NetSuite SuiteQL
 *                      integration — the Boomi layer exposes only the fields
 *                      needed by the Portfolio Analysis app.
 *                      Uses a Named Credential for Basic Auth so credentials
 *                      are never visible in code or the Salesforce UI.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Apr-16-2026
 * Jira               : BIZ-80686
 **/
public with sharing class BoomiInvoiceService {

    /***********************************************************************************************
     *
     * Constants
     *
     ***********************************************************************************************/

    private static final String NAMED_CREDENTIAL = 'callout:Portfolio_Analysis_API';
    private static final String QUERY_PATH = '/ws/simple/queryOsaNumbers';
    private static final Integer CALLOUT_TIMEOUT_MS = 30000;

    /***********************************************************************************************
     *
     * Inner Classes / Wrappers — Boomi Response
     *
     ***********************************************************************************************/

    /**
     * @description Top-level response envelope from the Boomi queryOsaNumbers endpoint.
     */
    public class BoomiResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer count;
        @AuraEnabled public List<BoomiInvoice> data;
    }

    /**
     * @description A single invoice record within the Boomi response, containing
     *              header-level fields and a nested list of transaction lines.
     */
    public class BoomiInvoice {
        @AuraEnabled public String id;
        @AuraEnabled public String tranid;
        @AuraEnabled public String type;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal foreigntotal;
        @AuraEnabled public String osa;
        @AuraEnabled public String termStart;
        @AuraEnabled public String termEnd;
        @AuraEnabled public String creditmemo_amount;
        @AuraEnabled public List<BoomiInvoiceLine> lines;
    }

    /**
     * @description A single transaction line within a Boomi invoice.
     */
    public class BoomiInvoiceLine {
        @AuraEnabled public String itemId;
        @AuraEnabled public String itemName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal amount;
    }

    /**
     * @description Wrapper for the service call result, adding success/error
     *              metadata around the Boomi response payload.
     */
    public class BoomiServiceResult {
        @AuraEnabled public BoomiResponse response;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;

        public BoomiServiceResult() {
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
     * @description Queries the Boomi invoice API for the given OSA numbers.
     *              Sends a POST request with the OSA list in the body and returns
     *              a structured result with invoice headers and line items.
     * @param osaNumbers List of OSA numbers (integers) to query.
     * @return BoomiServiceResult containing the parsed response or error info.
     */
    public static BoomiServiceResult queryByOsaNumbers(List<Integer> osaNumbers) {
        BoomiServiceResult result = new BoomiServiceResult();

        if (osaNumbers == null || osaNumbers.isEmpty()) {
            result.errorMessage = 'OSA numbers list is required.';
            return result;
        }

        Integer statusCode = 0;

        try {
            HttpResponse response = sendRequest(osaNumbers);
            statusCode = response.getStatusCode();

            if (statusCode == 200) {
                result.response = (BoomiResponse) JSON.deserialize(
                    response.getBody(), BoomiResponse.class
                );

                if (result.response != null && result.response.success == true) {
                    result.success = true;
                } else {
                    result.errorMessage = 'Boomi API returned success=false.';
                }
            } else {
                result.errorMessage = 'HTTP ' + statusCode + ': ' + response.getBody();
            }

            logCallout(statusCode, result.success, result.errorMessage, osaNumbers.size());

        } catch (Exception e) {
            result.errorMessage = 'Callout failed: ' + e.getMessage();
            logCallout(statusCode, false, e.getMessage(), osaNumbers.size());
        }

        return result;
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — HTTP Request
     *
     ***********************************************************************************************/

    /**
     * @description Builds and sends the HTTP POST request to the Boomi endpoint.
     *              The Named Credential automatically injects the Authorization
     *              header (Basic Auth), so no credentials appear in code.
     * @param osaNumbers List of OSA numbers to include in the request body.
     * @return HttpResponse from the Boomi API.
     */
    private static HttpResponse sendRequest(List<Integer> osaNumbers) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + QUERY_PATH);
        req.setMethod('POST');
        req.setTimeout(CALLOUT_TIMEOUT_MS);
        req.setHeader('Content-Type', 'application/json');

        Map<String, Object> body = new Map<String, Object>{
            'osaNumbers' => osaNumbers
        };
        req.setBody(JSON.serialize(body));

        Http http = new Http();
        return http.send(req);
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Logging
     *
     ***********************************************************************************************/

    /**
     * @description Logs the callout details to Nebula Logger for observability.
     * @param statusCode HTTP response status code
     * @param success Whether the call succeeded
     * @param errorMessage Error detail if the call failed
     * @param osaCount Number of OSA numbers queried
     */
    private static void logCallout(Integer statusCode, Boolean success, String errorMessage, Integer osaCount) {
        if (success) {
            Nebula.Logger.info(
                'Boomi Invoice API: Query executed successfully (HTTP ' + statusCode +
                ') for ' + osaCount + ' OSA(s)'
            )
                .addTag('BoomiIntegration')
                .addTag('PortfolioAnalysis');
        } else {
            Nebula.Logger.error(
                'Boomi Invoice API: Callout failed (HTTP ' + statusCode + ') — ' + errorMessage
            )
                .addTag('BoomiIntegration')
                .addTag('PortfolioAnalysis');
        }
        Nebula.Logger.saveLog();
    }
}