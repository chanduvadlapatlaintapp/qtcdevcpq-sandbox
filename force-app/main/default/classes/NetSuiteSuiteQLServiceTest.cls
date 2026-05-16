/**
 * @description       : Test class for NetSuiteSuiteQLService — verifies SuiteQL query execution,
 *                      response parsing, error handling, and pagination using HTTP callout mocks.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Mar-05-2026
 * Jira               : BIZ-80292
 **/
@isTest
public class NetSuiteSuiteQLServiceTest {

    /***********************************************************************************************
     *
     * Mock Classes
     *
     ***********************************************************************************************/

    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"items":[{"id":"123","tranid":"INV-001","status":"Open","amount":1500.00},{"id":"456","tranid":"INV-002","status":"Paid","amount":2300.50}],"totalResults":2,"hasMore":false,"count":2,"offset":0}');
            return res;
        }
    }

    private class EmptyResultMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"items":[],"totalResults":0,"hasMore":false,"count":0,"offset":0}');
            return res;
        }
    }

    private class PaginatedMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"items":[{"id":"789"}],"totalResults":2500,"hasMore":true,"count":1000,"offset":0}');
            return res;
        }
    }

    private class AuthErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"code":"INVALID_LOGIN_ATTEMPT","message":"Invalid login attempt."}}');
            return res;
        }
    }

    private class ServerErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
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
     * Test Methods — Successful Queries
     *
     ***********************************************************************************************/

    @isTest
    static void testExecuteQuery_Success() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('SELECT id, tranid, status, amount FROM transaction WHERE type = \'CustInvc\'');
        Test.stopTest();

        System.assert(result.success, 'Query should succeed');
        System.assertEquals(2, result.items.size(), 'Should return two items');
        System.assertEquals(2, result.totalResults, 'Total results should be 2');
        System.assertEquals(false, result.hasMore, 'Should not have more results');
        System.assertEquals(null, result.errorMessage, 'Error message should be null');
    }

    @isTest
    static void testExecuteQuery_SuccessSimpleOverload() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('SELECT id FROM transaction');
        Test.stopTest();

        System.assert(result.success, 'Simple overload should succeed');
        System.assertEquals(2, result.items.size(), 'Should return items');
    }

    @isTest
    static void testExecuteQuery_EmptyResult() {
        Test.setMock(HttpCalloutMock.class, new EmptyResultMock());

        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('SELECT id FROM transaction WHERE ROWNUM < 0');
        Test.stopTest();

        System.assert(result.success, 'Empty result should still be success');
        System.assertEquals(0, result.items.size(), 'Should return zero items');
        System.assertEquals(0, result.totalResults, 'Total results should be 0');
    }

    /***********************************************************************************************
     *
     * Test Methods — Pagination
     *
     ***********************************************************************************************/

    @isTest
    static void testExecuteQuery_Pagination() {
        Test.setMock(HttpCalloutMock.class, new PaginatedMock());

        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('SELECT id FROM transaction', 1000, 0);
        Test.stopTest();

        System.assert(result.success, 'Paginated query should succeed');
        System.assertEquals(2500, result.totalResults, 'Total results should be 2500');
        System.assert(result.hasMore, 'hasMore should be true for paginated results');
    }

    /***********************************************************************************************
     *
     * Test Methods — Error Handling
     *
     ***********************************************************************************************/

    @isTest
    static void testExecuteQuery_AuthError() {
        Test.setMock(HttpCalloutMock.class, new AuthErrorMock());

        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('SELECT id FROM transaction');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Auth error should not be success');
        System.assert(result.errorMessage.contains('INVALID_LOGIN_ATTEMPT'), 'Error should contain NetSuite error code');
    }

    @isTest
    static void testExecuteQuery_ServerError() {
        Test.setMock(HttpCalloutMock.class, new ServerErrorMock());

        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('SELECT id FROM transaction');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Server error should not be success');
        System.assert(result.errorMessage.contains('500'), 'Error should contain HTTP status code');
    }

    @isTest
    static void testExecuteQuery_BlankQuery() {
        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Blank query should not be success');
        System.assert(result.errorMessage.contains('blank'), 'Error should mention blank query');
    }

    @isTest
    static void testExecuteQuery_NullQuery() {
        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery(null);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Null query should not be success');
    }

    @isTest
    static void testExecuteQuery_NullLimitAndOffset() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        NetSuiteSuiteQLService.SuiteQLResult result =
            NetSuiteSuiteQLService.executeQuery('SELECT id FROM transaction', null, null);
        Test.stopTest();

        System.assert(result.success, 'Null limit/offset should default and succeed');
    }
}