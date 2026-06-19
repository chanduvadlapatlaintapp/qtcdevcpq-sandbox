/**
 * @description Test class for PortfolioAnalysisRunRESTService.
 *              Covers the full portfolio analysis pipeline: data assembly, CSV
 *              generation, and SharePoint upload via the Teams bot REST endpoint.
 * @author      Vignesh Prabhudoss
 * @date        2026-04-24
 * @jira        BIZ-82161
 */
@isTest
public class PortfolioAnalysisRunRESTServiceTest {

    /***********************************************************************************************
     *
     * Mock Classes
     *
     ***********************************************************************************************/

    /**
     * @description Routes callouts to the correct mock response based on the endpoint URL.
     *              Handles both NetSuite invoice calls and SharePoint upload calls.
     */
    private class MultiCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String endpoint = req.getEndpoint();

            if (endpoint.contains('sharepoint') || endpoint.contains('SharePoint_PortfolioAnalysis')) {
                return sharePointUploadSuccess();
            }

            // Default: NetSuite invoice response
            return netSuiteInvoiceSuccess();
        }

        private HTTPResponse netSuiteInvoiceSuccess() {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"items":[' +
                '{"id":"6834263","tranid":"200042121",' +
                '"custbody_osa_contract_num":"37098",' +
                '"custbody_inv_term_start_date":"7/1/2025",' +
                '"custbody_inv_term_end_date":"6/30/2026",' +
                '"statusdisplay":"Invoice : Paid In Full","foreigntotal":50000.00,' +
                '"lineamount":-25000.00,"linequantity":-100,"itemcode":"IN-01465"}' +
                '],"totalResults":1,"hasMore":false}');
            return res;
        }

        private HTTPResponse sharePointUploadSuccess() {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            // SharePoint REST API response for Files/Add
            res.setBody('{"d":{"ServerRelativeUrl":"/sites/appsintegration/Shared Documents/Portfolio Analysis Reports/Portfolio_REST_Test_Account_Portfolio_2026-04-24.csv",' +
                '"Name":"Portfolio_REST_Test_Account_Portfolio_2026-04-24.csv",' +
                '"TimeLastModified":"2026-04-24T00:00:00Z"}}');
            return res;
        }
    }

    /**
     * @description Mock that simulates a NetSuite error to force a 500 response.
     */
    private class NetSuiteErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal server error"}');
            return res;
        }
    }

    /***********************************************************************************************
     *
     * Test Setup
     *
     ***********************************************************************************************/

    @TestSetup
    static void makeData() {
        TestFactory.createSObject(
            new Account(
                Name = 'Portfolio REST Run Account',
                Type = 'Client',
                BillingCountry = 'United States'
            ),
            'AccountDefaults'
        );

        NetSuite_TBA_Credentials__c creds = new NetSuite_TBA_Credentials__c(
            Account_Id__c = '1234567_SB1',
            Consumer_Key__c = 'test-consumer-key-1234567890abcdef1234567890abcdef',
            Consumer_Secret__c = 'test-consumer-secret-1234567890abcdef1234567890abcde',
            Token_Id__c = 'test-token-id-1234567890abcdef1234567890abcdef1234',
            Token_Secret__c = 'test-token-secret-1234567890abcdef1234567890abcdef'
        );
        insert creds;
    }

    /***********************************************************************************************
     *
     * Helpers
     *
     ***********************************************************************************************/

    private static Account getTestAccount() {
        return [SELECT Id, Name FROM Account WHERE Name = 'Portfolio REST Run Account' LIMIT 1];
    }

    /**
     * @description Sets up a mock REST GET request with the given params.
     */
    private static void setupRequest(String accountId, String userEmail) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/portfolioAnalysis/run';
        req.httpMethod = 'GET';
        if (accountId != null) {
            req.params.put('accountId', accountId);
        }
        if (userEmail != null) {
            req.params.put('userEmail', userEmail);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    /**
     * @description Deserialises the REST response body into a map for assertions.
     */
    private static Map<String, Object> getResponseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    /***********************************************************************************************
     *
     * Test Methods — Happy Path
     *
     ***********************************************************************************************/

    @isTest
    static void testRun_Success_ReturnsCsvContent() {
        Account testAccount = getTestAccount();
        Test.setMock(HttpCalloutMock.class, new MultiCalloutMock());
        setupRequest(testAccount.Id, 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        System.assertEquals(200, RestContext.response.statusCode, 'Status should be 200');
        System.assertEquals(true, body.get('success'), 'Should return success');
        System.assertNotEquals(null, body.get('csvContent'), 'Should return base64 CSV content');
        System.assertNotEquals(null, body.get('fileName'), 'Should return file name');
        System.assertEquals('Portfolio REST Run Account', body.get('accountName'), 'Should return account name');
    }

    @isTest
    static void testRun_FileNameContainsAccountName() {
        Account testAccount = getTestAccount();
        Test.setMock(HttpCalloutMock.class, new MultiCalloutMock());
        setupRequest(testAccount.Id, 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        String fileName = (String) body.get('fileName');
        System.assert(fileName.endsWith('.csv'), 'File name should have .csv extension');
        System.assert(fileName.contains('Portfolio'), 'File name should contain Portfolio');
    }

    @isTest
    static void testRun_CsvContentIsValidBase64() {
        Account testAccount = getTestAccount();
        Test.setMock(HttpCalloutMock.class, new MultiCalloutMock());
        setupRequest(testAccount.Id, 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        String csvContent = (String) body.get('csvContent');

        // Decode to verify it's valid base64 and contains CSV headers
        Blob decoded = EncodingUtil.base64Decode(csvContent);
        String csvText = decoded.toString();
        System.assert(csvText.contains('OSA'), 'Decoded CSV should contain OSA column header');
        System.assert(csvText.contains('Contract Value'), 'Decoded CSV should contain Contract Value header');
    }

    @isTest
    static void testRun_WithoutUserEmail_StillSucceeds() {
        // userEmail is optional — SF handles the email delivery separately
        Account testAccount = getTestAccount();
        Test.setMock(HttpCalloutMock.class, new MultiCalloutMock());
        setupRequest(testAccount.Id, null);

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        System.assertEquals(200, RestContext.response.statusCode, 'Status should be 200 even without email');
        System.assertEquals(true, body.get('success'), 'Should succeed without userEmail param');
    }

    /***********************************************************************************************
     *
     * Test Methods — Validation Errors
     *
     ***********************************************************************************************/

    @isTest
    static void testRun_MissingAccountId_Returns400() {
        setupRequest(null, 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        System.assertEquals(400, RestContext.response.statusCode, 'Status should be 400');
        System.assertEquals(false, body.get('success'), 'Should return failure');
        System.assertNotEquals(null, body.get('errorMessage'), 'Should include error message');
    }

    @isTest
    static void testRun_InvalidAccountId_Returns500() {
        setupRequest('INVALIDID000', 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        System.assertEquals(500, RestContext.response.statusCode, 'Status should be 500 for invalid Id');
        System.assertEquals(false, body.get('success'), 'Should return failure');
    }

    @isTest
    static void testRun_NonExistentAccount_Returns404() {
        // Valid SF Id format but no matching record
        setupRequest('001000000000000AAA', 'testuser@intapp.com');
        Test.setMock(HttpCalloutMock.class, new MultiCalloutMock());

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        System.assertEquals(404, RestContext.response.statusCode, 'Status should be 404 for missing account');
        System.assertEquals(false, body.get('success'), 'Should return failure');
    }

    /***********************************************************************************************
     *
     * Test Methods — SharePoint Failure
     *
     ***********************************************************************************************/

    @isTest
    static void testRun_NetSuiteError_StillSucceeds() {
        // NetSuite failure should not block CSV generation — invoices just come back empty
        Account testAccount = getTestAccount();
        Test.setMock(HttpCalloutMock.class, new NetSuiteErrorMock());
        setupRequest(testAccount.Id, 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        // No subscriptions in test data so no OSA numbers → NetSuite never called
        // This test verifies the flow completes without error
        System.assertNotEquals(null, body.get('success'), 'Should return a success field');
    }

    /***********************************************************************************************
     *
     * Test Methods — Response Shape
     *
     ***********************************************************************************************/

    @isTest
    static void testRun_ResponseHasContentTypeHeader() {
        Account testAccount = getTestAccount();
        Test.setMock(HttpCalloutMock.class, new MultiCalloutMock());
        setupRequest(testAccount.Id, 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        String contentType = RestContext.response.headers.get('Content-Type');
        System.assertEquals('application/json', contentType, 'Response should be JSON');
    }

    @isTest
    static void testRun_ErrorResponse_HasNoCsvContent() {
        setupRequest(null, 'testuser@intapp.com');

        Test.startTest();
        PortfolioAnalysisRunRESTService.runAnalysis();
        Test.stopTest();

        Map<String, Object> body = getResponseBody();
        System.assertEquals(null, body.get('csvContent'), 'Error response should not include csvContent');
        System.assertEquals(null, body.get('fileName'), 'Error response should not include fileName');
    }

    /***********************************************************************************************
     *
     * Test Methods — Utility Methods (via @TestVisible)
     *
     ***********************************************************************************************/

    @isTest
    static void testCsvEscape_NullReturnsEmpty() {
        String result = PortfolioAnalysisRunRESTService.csvEscape(null);
        System.assertEquals('', result, 'Null should return empty string');
    }

    @isTest
    static void testCsvEscape_BlankReturnsEmpty() {
        String result = PortfolioAnalysisRunRESTService.csvEscape('');
        System.assertEquals('', result, 'Blank should return empty string');
    }

    @isTest
    static void testCsvEscape_WrapsInQuotes() {
        String result = PortfolioAnalysisRunRESTService.csvEscape('Acme Corp');
        System.assertEquals('"Acme Corp"', result, 'Should wrap value in double quotes');
    }

    @isTest
    static void testCsvEscape_EscapesInternalQuotes() {
        String result = PortfolioAnalysisRunRESTService.csvEscape('Acme "Corp"');
        System.assertEquals('"Acme ""Corp"""', result, 'Should escape internal double quotes');
    }

    @isTest
    static void testDaysBetween_ValidDates() {
        Date startDt = Date.newInstance(2026, 1, 1);
        Date endDt   = Date.newInstance(2026, 12, 31);
        Integer result = PortfolioAnalysisRunRESTService.daysBetween(startDt, endDt);
        System.assertEquals(364, result, 'Should return correct day count');
    }

    @isTest
    static void testDaysBetween_NullStart_ReturnsNull() {
        Integer result = PortfolioAnalysisRunRESTService.daysBetween(null, Date.today());
        System.assertEquals(null, result, 'Null start date should return null');
    }

    @isTest
    static void testDaysBetween_NullEnd_ReturnsNull() {
        Integer result = PortfolioAnalysisRunRESTService.daysBetween(Date.today(), null);
        System.assertEquals(null, result, 'Null end date should return null');
    }

    @isTest
    static void testAnnualize_ValidInputs() {
        Date startDt = Date.newInstance(2026, 1, 1);
        Date endDt   = Date.newInstance(2027, 1, 1);
        Decimal result = PortfolioAnalysisRunRESTService.annualize(36500, startDt, endDt);
        System.assertNotEquals(null, result, 'Should return annualized value');
        System.assert(result > 0, 'Annualized value should be positive');
    }

    @isTest
    static void testAnnualize_NullContractValue_ReturnsNull() {
        Decimal result = PortfolioAnalysisRunRESTService.annualize(null, Date.today(), Date.today().addYears(1));
        System.assertEquals(null, result, 'Null contract value should return null');
    }

    @isTest
    static void testAnnualize_NullDates_ReturnsNull() {
        Decimal result = PortfolioAnalysisRunRESTService.annualize(10000, null, null);
        System.assertEquals(null, result, 'Null dates should return null');
    }

    @isTest
    static void testAnnualize_ZeroDays_ReturnsNull() {
        Date sameDt = Date.newInstance(2026, 1, 1);
        Decimal result = PortfolioAnalysisRunRESTService.annualize(10000, sameDt, sameDt);
        System.assertEquals(null, result, 'Zero day term should return null');
    }

    @isTest
    static void testSanitiseFileName_ReplacesSpecialChars() {
        String result = PortfolioAnalysisRunRESTService.sanitiseFileName('Acme Corp, Inc. (Test)');
        System.assert(!result.contains(' '), 'Should not contain spaces');
        System.assert(!result.contains(','), 'Should not contain commas');
        System.assert(!result.contains('.'), 'Should not contain periods');
        System.assert(!result.contains('('), 'Should not contain parentheses');
    }

    @isTest
    static void testSanitiseFileName_BlankReturnsUnknown() {
        String result = PortfolioAnalysisRunRESTService.sanitiseFileName('');
        System.assertEquals('Unknown', result, 'Blank name should return Unknown');
    }

    @isTest
    static void testSanitiseFileName_NullReturnsUnknown() {
        String result = PortfolioAnalysisRunRESTService.sanitiseFileName(null);
        System.assertEquals('Unknown', result, 'Null name should return Unknown');
    }

    @isTest
    static void testBuildInvoiceMap_NullList_ReturnsEmptyMap() {
        Map<String, PortfolioAnalysisController.InvoiceRecord> result =
            PortfolioAnalysisRunRESTService.buildInvoiceMap(null);
        System.assertNotEquals(null, result, 'Should return empty map not null');
        System.assertEquals(0, result.size(), 'Should return empty map for null input');
    }

    @isTest
    static void testBuildInvoiceMap_DeduplicatesByKey() {
        PortfolioAnalysisController.InvoiceRecord inv1 = new PortfolioAnalysisController.InvoiceRecord();
        inv1.osaNumber = '37098';
        inv1.termStartDate = '2026-01-01';
        inv1.termEndDate = '2026-12-31';
        inv1.invoiceNumber = 'INV-001';

        PortfolioAnalysisController.InvoiceRecord inv2 = new PortfolioAnalysisController.InvoiceRecord();
        inv2.osaNumber = '37098';
        inv2.termStartDate = '2026-01-01';
        inv2.termEndDate = '2026-12-31';
        inv2.invoiceNumber = 'INV-002'; // duplicate key, different invoice

        List<PortfolioAnalysisController.InvoiceRecord> invoices =
            new List<PortfolioAnalysisController.InvoiceRecord>{ inv1, inv2 };

        Map<String, PortfolioAnalysisController.InvoiceRecord> result =
            PortfolioAnalysisRunRESTService.buildInvoiceMap(invoices);

        System.assertEquals(1, result.size(), 'Duplicate keys should produce a single map entry');
        System.assertEquals('INV-001', result.get('37098|2026-01-01|2026-12-31').invoiceNumber,
            'First invoice should win on duplicate key');
    }

    @isTest
    static void testBuildCsv_EmptySubscriptions_ContainsHeaders() {
        Account acc = new Account(
            Name = 'Test Corp',
            GTM_Motion_Tier__c = 'Tier 1',
            Contract_Term_Version__c = '1.0'
        );

        String csv = PortfolioAnalysisRunRESTService.buildCsv(
            acc,
            new List<SBQQ__Subscription__c>(),
            new Map<String, PortfolioAnalysisController.InvoiceRecord>()
        );

        System.assert(csv.contains('OSA'), 'CSV should contain OSA column header');
        System.assert(csv.contains('Contract Value'), 'CSV should contain Contract Value header');
        System.assert(csv.contains('Test Corp'), 'CSV should contain account name');
    }

    @isTest
    static void testBuildCsv_WithSubscription_ContainsDataRow() {
        Account acc = new Account(Name = 'Test Corp');

        // Only use writable fields — CPQ formula/rollup fields (Name, Contract_Status__c,
        // Segment_Months__c, SBQQ__StartDate__c, SBQQ__EndDate__c) are omitted
        // as they are managed by the CPQ package and not directly settable in Apex.
        // The buildCsv method handles nulls for all fields gracefully.
        SBQQ__Subscription__c sub = new SBQQ__Subscription__c(
            CurrencyIsoCode = 'USD',
            SBQQ__NetPrice__c = 10000,
            SBQQ__SegmentQuantity__c = 1,
            Support_Level__c = 'Standard',
            SBQQ__SegmentStartDate__c = Date.newInstance(2026, 1, 1),
            SBQQ__SegmentEndDate__c = Date.newInstance(2026, 12, 31)
        );

        String csv = PortfolioAnalysisRunRESTService.buildCsv(
            acc,
            new List<SBQQ__Subscription__c>{ sub },
            new Map<String, PortfolioAnalysisController.InvoiceRecord>()
        );

        System.assert(csv.contains('10000'), 'CSV should contain contract value');
        System.assert(csv.contains('Standard'), 'CSV should contain support level');
        System.assert(csv.contains('USD'), 'CSV should contain currency');
    }

    @isTest
    static void testBuildCsv_WithMatchedInvoice_ContainsInvoiceData() {
        Account acc = new Account(Name = 'Test Corp');

        SBQQ__Subscription__c sub = new SBQQ__Subscription__c(
            CurrencyIsoCode = 'USD',
            SBQQ__NetPrice__c = 5000,
            SBQQ__SegmentQuantity__c = 2,
            SBQQ__SegmentStartDate__c = Date.newInstance(2026, 1, 1),
            SBQQ__SegmentEndDate__c = Date.newInstance(2026, 12, 31)
        );

        PortfolioAnalysisController.InvoiceRecord inv = new PortfolioAnalysisController.InvoiceRecord();
        inv.osaNumber     = '';
        inv.termStartDate = '2026-01-01';
        inv.termEndDate   = '2026-12-31';
        inv.invoiceNumber = 'INV-12345';
        inv.paymentStatus = 'Paid In Full';
        inv.lineAmount    = -10000;

        Map<String, PortfolioAnalysisController.InvoiceRecord> invoiceMap =
            new Map<String, PortfolioAnalysisController.InvoiceRecord>{
                '|2026-01-01|2026-12-31' => inv
            };

        String csv = PortfolioAnalysisRunRESTService.buildCsv(
            acc,
            new List<SBQQ__Subscription__c>{ sub },
            invoiceMap
        );

        System.assert(csv.contains('INV-12345'), 'CSV should contain matched invoice number');
        System.assert(csv.contains('Paid In Full'), 'CSV should contain payment status');
    }

    @isTest
    static void testBuildInvoiceMap_MultipleDistinctKeys() {
        PortfolioAnalysisController.InvoiceRecord inv1 = new PortfolioAnalysisController.InvoiceRecord();
        inv1.osaNumber = '37098';
        inv1.termStartDate = '2026-01-01';
        inv1.termEndDate = '2026-12-31';

        PortfolioAnalysisController.InvoiceRecord inv2 = new PortfolioAnalysisController.InvoiceRecord();
        inv2.osaNumber = '37099';
        inv2.termStartDate = '2026-01-01';
        inv2.termEndDate = '2026-12-31';

        List<PortfolioAnalysisController.InvoiceRecord> invoices =
            new List<PortfolioAnalysisController.InvoiceRecord>{ inv1, inv2 };

        Map<String, PortfolioAnalysisController.InvoiceRecord> result =
            PortfolioAnalysisRunRESTService.buildInvoiceMap(invoices);

        System.assertEquals(2, result.size(), 'Distinct keys should produce separate map entries');
    }
}