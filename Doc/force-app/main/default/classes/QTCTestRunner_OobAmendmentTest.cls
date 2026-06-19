/**
 * @description Tests for QTCTestRunner_OobAmendmentRestResource.
 *              The success path is driven through the
 *              AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel seam so the
 *              ContractAmender managed-package call is never invoked (it can't
 *              run in test context). The 400 / 500 branches are exercised with
 *              a blank and a malformed contractId respectively.
 * @author AgenticQTC Team
 */
@IsTest
private class QTCTestRunner_OobAmendmentTest {

    /** Builds a RestContext request/response pair with the given JSON body. */
    private static void setupRestContext(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/agenticQtc/amendment/oob';
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
    static void createOobAmendment_success_returnsQuoteId() {
        // Fabricate valid-format Contract + Quote Ids; the mock seam short-circuits
        // ContractAmender so no real records are needed.
        Id contractId = Id.valueOf(Schema.SObjectType.Contract.getKeyPrefix() + '000000000001');
        Id quoteId    = Id.valueOf(Schema.SObjectType.SBQQ__Quote__c.getKeyPrefix() + '000000000001');

        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel = new Map<String, Object>{
            'record'    => new Map<String, Object>{ 'Id' => String.valueOf(quoteId) },
            'lineItems' => new List<Object>()
        };
        setupRestContext(JSON.serialize(new Map<String, Object>{ 'contractId' => contractId }));

        Test.startTest();
        QTCTestRunner_OobAmendmentRestResource.createOobAmendment();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, 'Should return 200 on success');
        Map<String, Object> body = parseResponse();
        System.assertEquals('success', body.get('status'));
        System.assertEquals(String.valueOf(quoteId), body.get('id'), 'Should echo the quote Id');
    }

    @IsTest
    static void createOobAmendment_blankContractId_returns400() {
        setupRestContext(JSON.serialize(new Map<String, Object>{ 'contractId' => '' }));

        Test.startTest();
        QTCTestRunner_OobAmendmentRestResource.createOobAmendment();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Blank contractId should be 400');
        System.assertEquals('error', parseResponse().get('status'));
    }

    @IsTest
    static void createOobAmendment_invalidContractId_returns500() {
        // Non-blank but malformed Id → Id.valueOf throws → caught → 500.
        setupRestContext(JSON.serialize(new Map<String, Object>{ 'contractId' => 'not-an-id' }));

        Test.startTest();
        QTCTestRunner_OobAmendmentRestResource.createOobAmendment();
        Test.stopTest();

        System.assertEquals(500, RestContext.response.statusCode, 'Malformed contractId should be 500');
        System.assertEquals('error', parseResponse().get('status'));
    }
}
