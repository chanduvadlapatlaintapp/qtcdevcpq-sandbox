/**
 * @description Tests for QTCTestRunner_CustAmendmentRestResource.
 *              The success path delegates to
 *              AgenticQTC_QuoteAmendmentService.createAmendmentQuote, which is
 *              driven through the AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel
 *              seam so SBQQ.ServiceRouter is never invoked. The same CPQ-bypass
 *              scaffolding as AgenticQTC_QuoteAmendmentServiceTest is used. The
 *              400 / 500 branches are exercised with a blank and a malformed
 *              contractId respectively.
 * @author AgenticQTC Team
 */
@IsTest
private class QTCTestRunner_CustAmendmentTest {

    @testSetup
    static void setupTestData() {
        SBQQ.TriggerControl.disable();

        // Bypass the org's "Quote Before Insert Update" flow / triggers so the
        // seeded quote doesn't trip unrelated production automation.
        insert new Automation_Controls__c(
            Active__c          = true,
            Bypass_Flows__c    = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c    = true,
            SetupOwnerId       = UserInfo.getUserId()
        );

        Account acct = new Account(Name = 'Test Account for Cust Amendment');
        insert acct;

        Contract con = new Contract(
            AccountId    = acct.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-1),
            ContractTerm = 12
        );
        insert con;
        con.Status = 'Activated';
        update con;

        Opportunity opp = new Opportunity(
            Name      = 'Test Cust Amendment Opportunity',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c        = acct.Id,
            SBQQ__Opportunity2__c   = opp.Id,
            SBQQ__MasterContract__c = con.Id,
            SBQQ__Primary__c        = true,
            SBQQ__Status__c         = 'Draft',
            SBQQ__Type__c           = 'Amendment',
            SBQQ__StartDate__c      = Date.today(),
            SBQQ__EndDate__c        = Date.today().addYears(1),
            Deal_Type__c            = 'Add-On'
        );
        insert quote;
    }

    private static void setupRestContext(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/agenticQtc/amendment/custom';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request  = req;
        RestContext.response = new RestResponse();
    }

    private static Map<String, Object> parseResponse() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
    }

    @IsTest
    static void createCustomAmendment_success_returnsQuoteId() {
        SBQQ.TriggerControl.disable();
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Contract con         = [SELECT Id FROM Contract LIMIT 1];

        // Empty-update amend returns the model as-is; point its record Id at the
        // seeded quote so getQuoteById resolves a real record.
        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel = new Map<String, Object>{
            'record'    => new Map<String, Object>{ 'Id' => String.valueOf(quote.Id) },
            'lineItems' => new List<Object>()
        };
        setupRestContext(JSON.serialize(new Map<String, Object>{ 'contractId' => con.Id }));

        Test.startTest();
        QTCTestRunner_CustAmendmentRestResource.createCustomAmendment();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, 'Should return 200 on success');
        Map<String, Object> body = parseResponse();
        System.assertEquals('success', body.get('status'));
        System.assertEquals(String.valueOf(quote.Id), body.get('id'), 'Should echo the quote Id');
    }

    @IsTest
    static void createCustomAmendment_blankContractId_returns400() {
        setupRestContext(JSON.serialize(new Map<String, Object>{ 'contractId' => '' }));

        Test.startTest();
        QTCTestRunner_CustAmendmentRestResource.createCustomAmendment();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Blank contractId should be 400');
        System.assertEquals('error', parseResponse().get('status'));
    }

    @IsTest
    static void createCustomAmendment_invalidContractId_returns500() {
        // Non-blank but malformed Id → Id.valueOf throws downstream → caught → 500 with actual message.
        setupRestContext(JSON.serialize(new Map<String, Object>{ 'contractId' => 'not-an-id' }));

        Test.startTest();
        QTCTestRunner_CustAmendmentRestResource.createCustomAmendment();
        Test.stopTest();

        System.assertEquals(500, RestContext.response.statusCode, 'Malformed contractId should be 500');
        Map<String, Object> body = parseResponse();
        System.assertEquals('error', body.get('status'));
        System.assertNotEquals(null, body.get('message'), 'Actual exception message should be returned');
    }

    @IsTest
    static void createCustomAmendment_cpqReturnsNoQuoteId_returns500() {
        // Mock returns a model with no Id in the record node → service's own null guard
        // throws AuraHandledException → caught → 500 with actual message.
        SBQQ.TriggerControl.disable();
        Contract con = [SELECT Id FROM Contract LIMIT 1];

        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel = new Map<String, Object>{
            'record'    => new Map<String, Object>(),  // no 'Id' key → getQuoteId returns null
            'lineItems' => new List<Object>()
        };
        setupRestContext(JSON.serialize(new Map<String, Object>{ 'contractId' => con.Id }));

        Test.startTest();
        QTCTestRunner_CustAmendmentRestResource.createCustomAmendment();
        Test.stopTest();

        System.assertEquals(500, RestContext.response.statusCode, 'Missing quoteId from CPQ should be 500');
        Map<String, Object> body = parseResponse();
        System.assertEquals('error', body.get('status'));
        System.assertNotEquals(null, body.get('message'), 'Actual exception message should be present');
    }
}