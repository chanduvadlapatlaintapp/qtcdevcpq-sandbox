/**
 * @description Service for product catalog search and adding products to CPQ quotes.
 *              Supports dual-path: direct DML (default) or CPQ ServiceRouter APIs,
 *              controlled via AgenticQTC_Config__mdt.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_ProductService {

    private static final String ERR_IDS_REQUIRED = 'Quote ID and Product ID are required';

    /**
     * @description Searches the Product2 catalog for active products matching a term.
     * @param searchTerm Optional search string; blank returns all active products.
     * @return List of ProductInfo DTOs
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductInfo> getEligibleProducts(String searchTerm) {
        List<ProductInfo> results = new List<ProductInfo>();
        String term = String.isNotBlank(searchTerm)
            ? '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%'
            : '';

        List<Product2> products;
        if (String.isNotBlank(term)) {
            products = [
                SELECT Id, Name, ProductCode, Family, Description
                FROM Product2
                WHERE IsActive = true AND (Name LIKE :term OR ProductCode LIKE :term)
                WITH SECURITY_ENFORCED
                ORDER BY Name LIMIT 50
            ];
        } else {
            products = [
                SELECT Id, Name, ProductCode, Family, Description
                FROM Product2
                WHERE IsActive = true
                WITH SECURITY_ENFORCED
                ORDER BY Name LIMIT 50
            ];
        }
        for (Product2 p : products) {
            results.add(new ProductInfo(p));
        }
        return results;
    }

    /**
     * @description Adds a product to a CPQ quote as a new quote line.
     *              Uses CPQ QuoteProductAdder API if configured, with DML fallback.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param productId The Product2 record Id
     * @param quantity The desired quantity (defaults to 1 if null or < 1)
     */
    @AuraEnabled
    public static void addProductToQuote(String quoteId, String productId, Decimal quantity) {
        if (String.isBlank(quoteId) || String.isBlank(productId)) {
            throw new AuraHandledException(ERR_IDS_REQUIRED);
        }

        if (AgenticQTC_ConfigService.useCpqApis()) {
            try {
                addProductViaCpqApi(quoteId, productId, quantity);
                return;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'CPQ add product failed, falling back to DML: ' + e.getMessage());
            }
        }
        addProductViaDml(quoteId, productId, quantity);
    }

    /**
     * @description Adds a product to a quote via the CPQ ServiceRouter API.
     *              If quantity > 1, performs a second save to update the line quantity.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param productId The Product2 record Id
     * @param quantity The desired quantity; values <= 1 are ignored
     */
    private static void addProductViaCpqApi(String quoteId, String productId, Decimal quantity) {
        String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
        String productJson = SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteProductAdder', quoteId,
            '{"outgoing":false,"ignoreCalculate":false,"products":[{"record":{"Id":"' + productId + '"}}]}');
        String savedJson = SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', productJson);

        if (quantity != null && quantity > 1) {
            Map<String, Object> model = (Map<String, Object>) JSON.deserializeUntyped(savedJson);
            List<Object> lineItems = (List<Object>) model.get('lineItems');
            if (lineItems != null) {
                for (Object item : lineItems) {
                    Map<String, Object> li = (Map<String, Object>) item;
                    Map<String, Object> rec = (Map<String, Object>) li.get('record');
                    if (rec.get('SBQQ__Product__c') == productId) {
                        rec.put('SBQQ__Quantity__c', quantity);
                        break;
                    }
                }
                SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', JSON.serialize(model));
            }
        }
    }

    /**
     * @description Adds a product to a quote via direct DML insert of a QuoteLine.
     *              Resolves the pricebook and list price before creating the line.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param productId The Product2 record Id
     * @param quantity The desired quantity; defaults to 1 when null or <= 0
     */
    private static void addProductViaDml(String quoteId, String productId, Decimal quantity) {
        Product2 prod = [
            SELECT Id, Name, ProductCode
            FROM Product2
            WHERE Id = :productId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        SBQQ__Quote__c quote = [
            SELECT Id, CurrencyIsoCode, SBQQ__PricebookId__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Decimal listPrice = 0;
        String currencyCode = quote.CurrencyIsoCode != null
            ? quote.CurrencyIsoCode
            : AgenticQTC_ConfigService.defaultCurrency();

        Id pbId = quote.SBQQ__PricebookId__c;
        if (pbId == null) {
            List<Pricebook2> stdPb = [
                SELECT Id
                FROM Pricebook2
                WHERE IsStandard = true
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!stdPb.isEmpty()) {
                pbId = stdPb[0].Id;
            }
        }

        if (pbId != null) {
            List<PricebookEntry> pbes = [
                SELECT UnitPrice
                FROM PricebookEntry
                WHERE Product2Id = :productId AND Pricebook2Id = :pbId
                AND IsActive = true AND CurrencyIsoCode = :currencyCode
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!pbes.isEmpty()) {
                listPrice = pbes[0].UnitPrice;
            }
        }

        Integer maxNumber = 0;
        List<AggregateResult> agg = [
            SELECT MAX(SBQQ__Number__c) maxNum
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            WITH SECURITY_ENFORCED
        ];
        if (!agg.isEmpty() && agg[0].get('maxNum') != null) {
            maxNumber = ((Decimal) agg[0].get('maxNum')).intValue();
        }

        Decimal qty = (quantity != null && quantity > 0) ? quantity : 1;

        SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Quantity__c = qty,
            SBQQ__PriorQuantity__c = 0,
            SBQQ__ListPrice__c = listPrice,
            SBQQ__NetPrice__c = listPrice * qty,
            SBQQ__CustomerPrice__c = listPrice,
            SBQQ__Number__c = maxNumber + 1
        );
        insert ql;
    }

    /**
     * @description Lightweight DTO for product catalog entries.
     */
    public class ProductInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public String description;

        /**
         * @description Constructs a ProductInfo from a Product2 record.
         * @param p The Product2 SObject
         */
        public ProductInfo(Product2 p) {
            this.id = p.Id;
            this.name = p.Name;
            this.productCode = p.ProductCode;
            this.family = p.Family;
            this.description = p.Description;
        }
    }
}