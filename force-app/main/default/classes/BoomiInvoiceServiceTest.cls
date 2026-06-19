/**
 * @description       : Test class for BoomiInvoiceService — verifies the Boomi invoice
 *                      API callout, response parsing, error handling, and edge cases
 *                      using HTTP callout mocks.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Apr-16-2026
 * Jira               : BIZ-80686
 **/
@isTest
public class BoomiInvoiceServiceTest {

    /***********************************************************************************************
     *
     * Mock Classes
     *
     ***********************************************************************************************/

    /**
     * @description Mock returning a successful Boomi response with 2 invoices
     *              and nested line items.
     */
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                '  "success": true,' +
                '  "count": 2,' +
                '  "data": [' +
                '    {' +
                '      "id": "6314445",' +
                '      "tranid": "Invoice #200038316",' +
                '      "type": "Invoice",' +
                '      "status": "Paid In Full",' +
                '      "foreigntotal": null,' +
                '      "osa": "43557",' +
                '      "termStart": "5/19/2025",' +
                '      "termEnd": "5/18/2026",' +
                '      "creditmemo_amount": "0.0",' +
                '      "lines": [' +
                '        {"itemId": "5673", "itemName": "DC-01641", "quantity": 5, "amount": 100.00},' +
                '        {"itemId": "9538", "itemName": "DC-02009", "quantity": 1, "amount": 50.00}' +
                '      ]' +
                '    },' +
                '    {' +
                '      "id": "6330051",' +
                '      "tranid": "Invoice #PS73808",' +
                '      "type": "Invoice",' +
                '      "status": "Paid In Full",' +
                '      "foreigntotal": null,' +
                '      "osa": "43557",' +
                '      "termStart": "",' +
                '      "termEnd": "",' +
                '      "creditmemo_amount": "0.0",' +
                '      "lines": [' +
                '        {"itemId": "3262", "itemName": "GE-01483", "quantity": 1, "amount": 200.00}' +
                '      ]' +
                '    }' +
                '  ]' +
                '}'
            );
            return res;
        }
    }

    /**
     * @description Mock returning a successful response with zero invoices.
     */
    private class EmptyResultMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true, "count": 0, "data": []}');
            return res;
        }
    }

    /**
     * @description Mock returning a Boomi-level failure (success=false).
     */
    private class BoomiFailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": false, "count": 0, "data": []}');
            return res;
        }
    }

    /**
     * @description Mock returning HTTP 401 Unauthorized.
     */
    private class AuthErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('Unauthorized');
            return res;
        }
    }

    /**
     * @description Mock returning HTTP 500 Internal Server Error.
     */
    private class ServerErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    /**
     * @description Mock that validates the request body and endpoint.
     */
    private class RequestValidationMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Validate endpoint uses Named Credential path
            System.assert(
                req.getEndpoint().contains('/ws/simple/queryOsaNumbers'),
                'Endpoint should contain the query path'
            );

            // Validate request body contains osaNumbers
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            System.assert(body.containsKey('osaNumbers'), 'Body should contain osaNumbers key');

            // Validate method and headers
            System.assertEquals('POST', req.getMethod(), 'Method should be POST');
            System.assertEquals('application/json', req.getHeader('Content-Type'), 'Content-Type should be application/json');

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true, "count": 0, "data": []}');
            return res;
        }
    }

    /***********************************************************************************************
     *
     * Test Methods — Successful Queries
     *
     ***********************************************************************************************/

    @isTest
    static void testQueryByOsaNumbers_Success() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557 });
        Test.stopTest();

        System.assert(result.success, 'Query should succeed');
        System.assertNotEquals(null, result.response, 'Response should not be null');
        System.assertEquals(2, result.response.count, 'Should return count of 2');
        System.assertEquals(2, result.response.data.size(), 'Should return 2 invoices');
        System.assertEquals(null, result.errorMessage, 'Error message should be null');
    }

    @isTest
    static void testQueryByOsaNumbers_InvoiceFields() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557 });
        Test.stopTest();

        BoomiInvoiceService.BoomiInvoice invoice = result.response.data[0];
        System.assertEquals('6314445', invoice.id, 'Invoice id should match');
        System.assertEquals('Invoice #200038316', invoice.tranid, 'Tranid should match');
        System.assertEquals('Paid In Full', invoice.status, 'Status should match');
        System.assertEquals('43557', invoice.osa, 'OSA should match');
        System.assertEquals('5/19/2025', invoice.termStart, 'Term start should match');
        System.assertEquals('5/18/2026', invoice.termEnd, 'Term end should match');
    }

    @isTest
    static void testQueryByOsaNumbers_LineItems() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557 });
        Test.stopTest();

        BoomiInvoiceService.BoomiInvoice invoice = result.response.data[0];
        System.assertEquals(2, invoice.lines.size(), 'First invoice should have 2 lines');

        BoomiInvoiceService.BoomiInvoiceLine line = invoice.lines[0];
        System.assertEquals('5673', line.itemId, 'Item ID should match');
        System.assertEquals('DC-01641', line.itemName, 'Item name should match');
        System.assertEquals(5, line.quantity, 'Quantity should match');
        System.assertEquals(100.00, line.amount, 'Amount should match');
    }

    @isTest
    static void testQueryByOsaNumbers_EmptyResult() {
        Test.setMock(HttpCalloutMock.class, new EmptyResultMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 99999 });
        Test.stopTest();

        System.assert(result.success, 'Empty result should still be success');
        System.assertEquals(0, result.response.data.size(), 'Should return zero invoices');
    }

    @isTest
    static void testQueryByOsaNumbers_MultipleOsas() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557, 43558, 43559 });
        Test.stopTest();

        System.assert(result.success, 'Multiple OSA query should succeed');
    }

    /***********************************************************************************************
     *
     * Test Methods — Request Validation
     *
     ***********************************************************************************************/

    @isTest
    static void testQueryByOsaNumbers_RequestFormat() {
        Test.setMock(HttpCalloutMock.class, new RequestValidationMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557 });
        Test.stopTest();

        System.assert(result.success, 'Request validation should pass');
    }

    /***********************************************************************************************
     *
     * Test Methods — Error Handling
     *
     ***********************************************************************************************/

    @isTest
    static void testQueryByOsaNumbers_BoomiFailure() {
        Test.setMock(HttpCalloutMock.class, new BoomiFailureMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557 });
        Test.stopTest();

        System.assertEquals(false, result.success, 'Boomi failure should not be success');
        System.assert(
            result.errorMessage.contains('success=false'),
            'Error should mention success=false'
        );
    }

    @isTest
    static void testQueryByOsaNumbers_AuthError() {
        Test.setMock(HttpCalloutMock.class, new AuthErrorMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557 });
        Test.stopTest();

        System.assertEquals(false, result.success, 'Auth error should not be success');
        System.assert(result.errorMessage.contains('401'), 'Error should contain HTTP 401');
    }

    @isTest
    static void testQueryByOsaNumbers_ServerError() {
        Test.setMock(HttpCalloutMock.class, new ServerErrorMock());

        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>{ 43557 });
        Test.stopTest();

        System.assertEquals(false, result.success, 'Server error should not be success');
        System.assert(result.errorMessage.contains('500'), 'Error should contain HTTP 500');
    }

    @isTest
    static void testQueryByOsaNumbers_NullInput() {
        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(null);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null input should not be success');
        System.assert(
            result.errorMessage.contains('required'),
            'Error should mention required input'
        );
    }

    @isTest
    static void testQueryByOsaNumbers_EmptyInput() {
        Test.startTest();
        BoomiInvoiceService.BoomiServiceResult result =
            BoomiInvoiceService.queryByOsaNumbers(new List<Integer>());
        Test.stopTest();

        System.assertEquals(false, result.success, 'Empty input should not be success');
        System.assert(
            result.errorMessage.contains('required'),
            'Error should mention required input'
        );
    }
}