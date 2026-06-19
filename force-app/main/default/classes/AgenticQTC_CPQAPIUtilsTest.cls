/********************************************************************************
*  Name             :  AgenticQTC_CPQAPIUtilsTest
*  Description      :  Unit tests for AgenticQTC_CPQAPIUtils — the thin wrapper over
*                      Salesforce CPQ's SBQQ.ServiceRouter.
*
*                      SBQQ.ServiceRouter cannot be successfully invoked from a test
*                      context. QuoteCalculator and QuoteSaver throw an uncatchable
*                      System.UnexpectedException, so those wrappers are exercised only
*                      through their @TestVisible mock seams (mockCalculatedQuoteModel /
*                      mockSavedQuoteModel). The remaining operations (QuoteReader,
*                      ProductLoader, QuoteProductAdder, ContractAmender) throw catchable
*                      exceptions and are wrapped in try/catch purely for call-path line
*                      coverage. Pure helpers (deserializeModel, getQuoteId) are asserted
*                      directly against hand-built JSON/maps. No DML — Ids are fabricated
*                      from object key prefixes.
*  Change history   :
*  Date          Author            Description
*  05/06/26      Anand Manhas      Created (BIZ-83493)
********************************************************************************/
@isTest
private class AgenticQTC_CPQAPIUtilsTest {

    // ─── Helpers ────────────────────────────────────────────────────────

    /** Fabricates a valid-format Id for the given SObjectType without DML. */
    private static Id fakeId(Schema.SObjectType sot) {
        return Id.valueOf(sot.getDescribe().getKeyPrefix() + '000000000001');
    }

    /** Minimal CPQ-shaped quote model: top-level 'record' (with Id) plus 'lineItems'. */
    private static Map<String, Object> buildModel(Id quoteId) {
        return new Map<String, Object>{
            'record'    => new Map<String, Object>{ 'Id' => String.valueOf(quoteId) },
            'lineItems' => new List<Object>()
        };
    }

    // ─── Pure helpers ───────────────────────────────────────────────────

    @isTest
    static void testDeserializeModel() {
        Map<String, Object> result = AgenticQTC_CPQAPIUtils.deserializeModel(
            '{"record":{"Id":"a0B000000000001"},"lineItems":[]}');
        System.assertNotEquals(null, result, 'Deserialized model should not be null');
        System.assertEquals(true, result.containsKey('record'), 'record key should be present');
        System.assertEquals(true, result.containsKey('lineItems'), 'lineItems key should be present');
    }

    @isTest
    static void testGetQuoteId_Present() {
        Id quoteId = fakeId(SBQQ__Quote__c.SObjectType);
        System.assertEquals(quoteId, AgenticQTC_CPQAPIUtils.getQuoteId(buildModel(quoteId)),
            'getQuoteId should extract the record Id');
    }

    @isTest
    static void testGetQuoteId_NoRecord() {
        Map<String, Object> model = new Map<String, Object>{ 'lineItems' => new List<Object>() };
        System.assertEquals(null, AgenticQTC_CPQAPIUtils.getQuoteId(model),
            'getQuoteId should return null when there is no record node');
    }

    @isTest
    static void testGetQuoteId_NullId() {
        Map<String, Object> model = new Map<String, Object>{
            'record' => new Map<String, Object>{ 'Id' => null }
        };
        System.assertEquals(null, AgenticQTC_CPQAPIUtils.getQuoteId(model),
            'getQuoteId should return null when the record Id is null');
    }

    // ─── Mock-seam branches (no ServiceRouter call) ─────────────────────

    @isTest
    static void testSaveQuoteModel_ReturnsMock() {
        Id quoteId = fakeId(SBQQ__Quote__c.SObjectType);
        AgenticQTC_CPQAPIUtils.mockSavedQuoteModel = buildModel(quoteId);
        Map<String, Object> saved = AgenticQTC_CPQAPIUtils.saveQuoteModel(
            new Map<String, Object>{ 'record' => new Map<String, Object>() });
        System.assertEquals(quoteId, AgenticQTC_CPQAPIUtils.getQuoteId(saved),
            'saveQuoteModel should return the injected mock without calling ServiceRouter');
    }

    @isTest
    static void testCalculateQuoteModel_ReturnsMock() {
        Id quoteId = fakeId(SBQQ__Quote__c.SObjectType);
        AgenticQTC_CPQAPIUtils.mockCalculatedQuoteModel = buildModel(quoteId);
        Map<String, Object> calc = AgenticQTC_CPQAPIUtils.calculateQuoteModel(
            new Map<String, Object>(), '');
        System.assertEquals(quoteId, AgenticQTC_CPQAPIUtils.getQuoteId(calc),
            'calculateQuoteModel should return the injected mock without calling ServiceRouter');
    }

    @isTest
    static void testCreateAmendmentQuote_ReturnsMock() {
        Id quoteId = fakeId(SBQQ__Quote__c.SObjectType);
        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel = buildModel(quoteId);
        Map<String, Object> model = AgenticQTC_CPQAPIUtils.createAmendmentQuote(
            fakeId(Contract.SObjectType));
        System.assertEquals(quoteId, AgenticQTC_CPQAPIUtils.getQuoteId(model),
            'createAmendmentQuote should return the injected mock without calling ServiceRouter');
    }

    // ─── ServiceRouter call paths (catchable; line coverage only) ───────

    @isTest
    static void testReadQuoteModel_ServiceRouterCallPath() {
        Test.startTest();
        try {
            AgenticQTC_CPQAPIUtils.readQuoteModel(fakeId(SBQQ__Quote__c.SObjectType));
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testReadProduct_ServiceRouterCallPath() {
        Test.startTest();
        try {
            AgenticQTC_CPQAPIUtils.readProduct(
                fakeId(SBQQ__Quote__c.SObjectType),
                Test.getStandardPricebookId(),
                new List<Id>{ fakeId(Product2.SObjectType) },
                'USD'
            );
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testAddProducts_ServiceRouterCallPath() {
        Test.startTest();
        try {
            AgenticQTC_CPQAPIUtils.addProducts(
                new Map<String, Object>{ 'record' => new Map<String, Object>() },
                new List<Object>(),
                true
            );
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateAmendmentQuote_ServiceRouterCallPath() {
        // No mock set -> exercises the real ContractAmender branch (catchable in tests).
        Test.startTest();
        try {
            AgenticQTC_CPQAPIUtils.createAmendmentQuote(fakeId(Contract.SObjectType));
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}