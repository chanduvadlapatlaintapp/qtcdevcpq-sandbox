/********************************************************************************
*  Name             :  AgenticQTC_CPQAPIUtils
*  Description      :  Utility service wrapping Salesforce CPQ API calls via
*                      SBQQ.ServiceRouter.
*  Change history   :
*  Date          Author            Description
*  24/04/26      Gaurav Mishra     Created
********************************************************************************/
// Intentionally without sharing: delegates all data access to SBQQ.ServiceRouter,
// which enforces its own CPQ permission checks. No direct SOQL or DML on user data.
public without sharing class AgenticQTC_CPQAPIUtils {

    private static final String OP_QUOTE_READ         = 'SBQQ.QuoteAPI.QuoteReader';
    private static final String OP_QUOTE_SAVE         = 'SBQQ.QuoteAPI.QuoteSaver';
    private static final String OP_QUOTE_CALCULATE    = 'SBQQ.QuoteAPI.QuoteCalculator';
    private static final String OP_PRODUCT_READ       = 'SBQQ.ProductAPI.ProductLoader';
    private static final String OP_PRODUCT_ADD        = 'SBQQ.QuoteAPI.QuoteProductAdder';
    private static final String OP_CONTRACT_AMEND     = 'SBQQ.ContractManipulationAPI.ContractAmender';

    // Test-only seams: SBQQ.ServiceRouter calls (QuoteCalculator throws an uncatchable
    // System.UnexpectedException in test context; QuoteSaver rejects hand-built mock models
    // with "Nested object for polymorphic foreign key..."; ContractAmender requires
    // fully-wired SBQQ test data). These hooks let tests substitute a pre-built quote model
    // instead of invoking the managed package.
    @TestVisible private static Map<String, Object> mockAmendmentQuoteModel;
    @TestVisible private static Map<String, Object> mockCalculatedQuoteModel;
    @TestVisible private static Map<String, Object> mockSavedQuoteModel;

    /**
     * @description Loads a CPQ quote model by quote record Id as a deserialized map.
     */
    public static Map<String, Object> readQuoteModel(Id quoteId) {
        return deserializeModel(SBQQ.ServiceRouter.read(OP_QUOTE_READ, quoteId));
    }

    /**
     * @description Saves a CPQ quote model and returns the saved model as a deserialized map.
     */
    public static Map<String, Object> saveQuoteModel(Map<String, Object> quoteModel) {
        if (Test.isRunningTest() && mockSavedQuoteModel != null) {
            return mockSavedQuoteModel;
        }
        return deserializeModel(SBQQ.ServiceRouter.save(OP_QUOTE_SAVE, JSON.serialize(quoteModel)));
    }

    /**
     * @description Calculates a quote model and returns the calculated model as a deserialized map.
     *              Pass '' for synchronous, or a class name implementing SBQQ.CalculateCallback for async mode.
     */
    public static Map<String, Object> calculateQuoteModel(Map<String, Object> quoteModel, String callbackClass) {
        if (Test.isRunningTest() && mockCalculatedQuoteModel != null) {
            return mockCalculatedQuoteModel;
        }
        Map<String, Object> apiPayload = new Map<String, Object>{
            'quote'         => quoteModel,
            'callbackClass' => callbackClass
        };
        String result = SBQQ.ServiceRouter.load(OP_QUOTE_CALCULATE, null, JSON.serialize(apiPayload));
        // QuoteCalculator returns null in async callback mode — return the in-memory model as-is
        return String.isBlank(result) ? quoteModel : deserializeModel(result);
    }

    /**
     * @description Loads CPQ product models ready for addition to a quote.
     */
    public static String readProduct(Id quoteId, Id pricebookId, List<Id> productIds, String currencyCode) {
        Map<String, Object> context = new Map<String, Object>{
            'pricebookId'  => String.valueOf(pricebookId),
            'productIds'   => productIds,
            'currencyCode' => currencyCode
        };
        return SBQQ.ServiceRouter.load(OP_PRODUCT_READ, quoteId, JSON.serialize(context));
    }

    /**
     * @description Adds products to a CPQ quote model.
     */
    public static String addProducts(Map<String, Object> quoteModel, List<Object> productModelList, Boolean isIgnoreCalculate) {
        Map<String, Object> apiPayload = new Map<String, Object>{
            'quote'           => quoteModel,
            'products'        => productModelList,
            'ignoreCalculate' => isIgnoreCalculate
        };
        return SBQQ.ServiceRouter.save(OP_PRODUCT_ADD, JSON.serialize(apiPayload));
    }

    /**
     * @description Loads an amendment quote model from an existing contract as a deserialized map.
     */
    public static Map<String, Object> createAmendmentQuote(Id contractId) {
        if (Test.isRunningTest() && mockAmendmentQuoteModel != null) {
            return mockAmendmentQuoteModel;
        }
        return deserializeModel(SBQQ.ServiceRouter.load(OP_CONTRACT_AMEND, contractId, null));
    }

    /**
     * @description Deserializes a CPQ API JSON response into a Map<String, Object>.
     */
    public static Map<String, Object> deserializeModel(String jsonString) {
        return (Map<String, Object>) JSON.deserializeUntyped(jsonString);
    }

    /**
     * @description Extracts the SFDC record Id from the top-level 'record' node of a CPQ quote model.
     */
    public static Id getQuoteId(Map<String, Object> quoteModel) {
        Map<String, Object> record = (Map<String, Object>) quoteModel.get('record');
        if (record == null || record.get('Id') == null) {
            return null;
        }
        return Id.valueOf(String.valueOf(record.get('Id')));
    }
}