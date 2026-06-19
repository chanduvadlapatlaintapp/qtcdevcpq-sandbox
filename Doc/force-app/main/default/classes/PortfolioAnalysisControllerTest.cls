/**
 * @description       : Test class for PortfolioAnalysisController.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Mar-02-2026
 * Jira               : BIZ-80262, BIZ-80292
 **/
@isTest
public class PortfolioAnalysisControllerTest {

    /***********************************************************************************************
     *
     * Mock Classes — NetSuite Invoice Callouts
     *
     ***********************************************************************************************/

    private class InvoiceSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"items":[' +
                '{"id":"6834263","tranid":"200042121",' +
                '"custbody_osa_contract_num":"37098",' +
                '"custbody_inv_term_start_date":"7/1/2025",' +
                '"custbody_inv_term_end_date":"6/30/2026",' +
                '"statusdisplay":"Invoice : Paid In Full","foreigntotal":50000.00,' +
                '"lineamount":-25000.00,"linequantity":-100,"itemcode":"IN-01465"},' +
                '{"id":"6834263","tranid":"200042121",' +
                '"custbody_osa_contract_num":"37098",' +
                '"custbody_inv_term_start_date":"7/1/2025",' +
                '"custbody_inv_term_end_date":"6/30/2026",' +
                '"statusdisplay":"Invoice : Paid In Full","foreigntotal":50000.00,' +
                '"lineamount":-25000.00,"linequantity":-200,"itemcode":"IN-01489"},' +
                '{"id":"6834264","tranid":"200042122",' +
                '"custbody_osa_contract_num":"37099",' +
                '"custbody_inv_term_start_date":"1/1/2026",' +
                '"custbody_inv_term_end_date":"12/31/2026",' +
                '"statusdisplay":"Invoice : Open","foreigntotal":75000.00,' +
                '"lineamount":-75000.00,"linequantity":-500,"itemcode":"TB-00709"}' +
                '],"totalResults":3,"hasMore":false}');
            return res;
        }
    }

    private class InvoiceEmptyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"items":[],"totalResults":0,"hasMore":false}');
            return res;
        }
    }

    private class InvoiceErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"code":"INTERNAL_ERROR","message":"Server error occurred."}}');
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
        Account account = (Account) TestFactory.createSObject(
            new Account(
                Name = 'Portfolio Test Account',
                Type = 'Client',
                BillingCountry = 'United States'
            ),
            'AccountDefaults'
        );

        // NetSuite TBA credentials for callout tests
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
     * Helper Methods
     *
     ***********************************************************************************************/

    private static Account getTestAccount() {
        return [SELECT Id, Name FROM Account WHERE Name = 'Portfolio Test Account' LIMIT 1];
    }

    /***********************************************************************************************
     *
     * Test Methods — Account Search
     *
     ***********************************************************************************************/

    @isTest
    static void testSearchAccounts_ReturnsResults() {
        Account testAccount = getTestAccount();

        Test.startTest();
        List<Account> results = PortfolioAnalysisController.searchAccounts('Portfolio Test');
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should return at least one account');
        System.assertEquals('Portfolio Test Account', results[0].Name, 'Should match the test account name');
    }

    @isTest
    static void testSearchAccounts_EmptySearch() {
        Test.startTest();
        List<Account> results = PortfolioAnalysisController.searchAccounts('');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty search should return no results');
    }

    @isTest
    static void testSearchAccounts_ShortSearch() {
        Test.startTest();
        List<Account> results = PortfolioAnalysisController.searchAccounts('a');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Single character search should return no results');
    }

    @isTest
    static void testSearchAccounts_NoMatch() {
        Test.startTest();
        List<Account> results = PortfolioAnalysisController.searchAccounts('ZZZZNOEXIST');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Non-matching search should return no results');
    }

    /***********************************************************************************************
     *
     * Test Methods — Account Details
     *
     ***********************************************************************************************/

    @isTest
    static void testGetAccountDetails_Success() {
        Account testAccount = getTestAccount();

        Test.startTest();
        Account result = PortfolioAnalysisController.getAccountDetails(testAccount.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return account details');
        System.assertEquals(testAccount.Id, result.Id, 'Should return the correct account');
    }

    @isTest
    static void testGetAccountDetails_NullId() {
        Test.startTest();
        try {
            PortfolioAnalysisController.getAccountDetails(null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Account Id is required'), 'Error message should indicate missing Id');
        }
        Test.stopTest();
    }

    /***********************************************************************************************
     *
     * Test Methods — Subscriptions
     *
     ***********************************************************************************************/

    @isTest
    static void testGetSubscriptions_Success() {
        Account testAccount = getTestAccount();

        Test.startTest();
        List<SBQQ__Subscription__c> results = PortfolioAnalysisController.getSubscriptions(testAccount.Name);
        Test.stopTest();

        // No subscriptions created in test setup, so expect empty list
        System.assertNotEquals(null, results, 'Should return a list (even if empty)');
    }

    @isTest
    static void testGetSubscriptions_BlankName() {
        Test.startTest();
        try {
            PortfolioAnalysisController.getSubscriptions('');
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Account name is required'), 'Error message should indicate missing name');
        }
        Test.stopTest();
    }

    /***********************************************************************************************
     *
     * Test Methods — Invoice Data (NetSuite)
     *
     ***********************************************************************************************/

    @isTest
    static void testGetInvoiceData_Success() {
        Test.setMock(HttpCalloutMock.class, new InvoiceSuccessMock());

        Test.startTest();
        PortfolioAnalysisController.InvoiceDataResult result =
            PortfolioAnalysisController.getInvoiceData(new List<String>{ '37098', '37099' });
        Test.stopTest();

        System.assertEquals(true, result.success, 'Should return success');
        System.assertEquals(3, result.invoices.size(), 'Should return 3 invoice lines');

        // Verify first invoice line
        PortfolioAnalysisController.InvoiceRecord inv1 = result.invoices[0];
        System.assertEquals('6834263', inv1.invoiceId, 'Invoice Id should match');
        System.assertEquals('200042121', inv1.invoiceNumber, 'Invoice number should match');
        System.assertEquals('37098', inv1.osaNumber, 'OSA number should match');
        System.assertEquals('Paid In Full', inv1.paymentStatus, 'Payment status should strip Invoice prefix');
        System.assert(inv1.sharePointUrl.contains('6834263_200042121'), 'SharePoint URL should contain id_tranid');

        // Verify date normalization (M/D/YYYY → YYYY-MM-DD)
        System.assertEquals('2025-07-01', inv1.termStartDate, 'Start date should be normalized to YYYY-MM-DD');
        System.assertEquals('2026-06-30', inv1.termEndDate, 'End date should be normalized to YYYY-MM-DD');

        // Verify line-level fields
        System.assertEquals(-25000.00, inv1.lineAmount, 'Line amount should match foreignamount');
        System.assertEquals(-100, inv1.lineQuantity, 'Line quantity should match');
        System.assertEquals('IN-01465', inv1.itemCode, 'Item code should match product code');
    }

    @isTest
    static void testGetInvoiceData_EmptyResult() {
        Test.setMock(HttpCalloutMock.class, new InvoiceEmptyMock());

        Test.startTest();
        PortfolioAnalysisController.InvoiceDataResult result =
            PortfolioAnalysisController.getInvoiceData(new List<String>{ '99999' });
        Test.stopTest();

        System.assertEquals(true, result.success, 'Should return success even with empty result');
        System.assertEquals(0, result.invoices.size(), 'Should return 0 invoices');
    }

    @isTest
    static void testGetInvoiceData_NullOsaList() {
        Test.startTest();
        PortfolioAnalysisController.InvoiceDataResult result =
            PortfolioAnalysisController.getInvoiceData(null);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should return failure for null input');
        System.assert(result.errorMessage.contains('OSA numbers list is required'), 'Error message should indicate missing OSAs');
    }

    @isTest
    static void testGetInvoiceData_EmptyOsaList() {
        Test.startTest();
        PortfolioAnalysisController.InvoiceDataResult result =
            PortfolioAnalysisController.getInvoiceData(new List<String>());
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should return failure for empty list');
        System.assert(result.errorMessage.contains('OSA numbers list is required'), 'Error message should indicate missing OSAs');
    }

    @isTest
    static void testGetInvoiceData_NetSuiteError() {
        Test.setMock(HttpCalloutMock.class, new InvoiceErrorMock());

        Test.startTest();
        PortfolioAnalysisController.InvoiceDataResult result =
            PortfolioAnalysisController.getInvoiceData(new List<String>{ '37098' });
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should return failure on NetSuite error');
        System.assertNotEquals(null, result.errorMessage, 'Error message should be populated');
    }

    /***********************************************************************************************
     *
     * Test Methods — Previous Contract Subscriptions
     *
     ***********************************************************************************************/

    @isTest
    static void testGetPreviousContractSubscriptions_Success() {
        Account testAccount = getTestAccount();

        Test.startTest();
        List<SBQQ__Subscription__c> results = PortfolioAnalysisController.getPreviousContractSubscriptions(
            testAccount.Name,
            new List<String>{ '37098' },
            new List<Id>()
        );
        Test.stopTest();

        // No subscriptions created in test setup, so expect empty list
        System.assertNotEquals(null, results, 'Should return a list (even if empty)');
    }

    @isTest
    static void testGetPreviousContractSubscriptions_BlankAccountName() {
        Test.startTest();
        try {
            PortfolioAnalysisController.getPreviousContractSubscriptions(
                '',
                new List<String>{ '37098' },
                new List<Id>()
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Account name is required'), 'Error message should indicate missing name');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetPreviousContractSubscriptions_EmptyOsaNumbers() {
        Account testAccount = getTestAccount();

        Test.startTest();
        List<SBQQ__Subscription__c> results = PortfolioAnalysisController.getPreviousContractSubscriptions(
            testAccount.Name,
            new List<String>(),
            new List<Id>()
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty OSA list should return empty results');
    }

    @isTest
    static void testGetPreviousContractSubscriptions_NullExcludeIds() {
        Account testAccount = getTestAccount();

        Test.startTest();
        List<SBQQ__Subscription__c> results = PortfolioAnalysisController.getPreviousContractSubscriptions(
            testAccount.Name,
            new List<String>{ '37098' },
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should handle null exclude IDs gracefully');
    }
}