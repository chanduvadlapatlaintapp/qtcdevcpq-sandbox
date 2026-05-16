/**
 * @description Data provider class for ACV Change calculations.
 *              Centralizes all SOQL queries and key generation for ACV processing.
 * @author Sahal Mohamed
 * @date 2026-02-04
 */
public class ACVDataProvider {
    
    /***********************************************************************************************
    *
    * Core Data Queries
    *
    ***********************************************************************************************/
    
    /**
     * @description Get Quote data for ACV processing
     * @param quoteIds Set of Quote IDs
     * @return Map of Quote records
     */
    public static Map<Id, SBQQ__Quote__c> getQuoteData(Set<Id> quoteIds) {
        if (quoteIds.isEmpty()) {
            return new Map<Id, SBQQ__Quote__c>();
        }
        return new Map<Id, SBQQ__Quote__c>([
            SELECT Id, SBQQ__Type__c, Renewal_Quote_Type__c, Deal_Type__c,
                   AVA_SFCPQ__AvaTaxMessage__c, SegmentIndex_Max__c, SBQQ__Opportunity2__c,
                   SBQQ__Opportunity2__r.SBQQ__RenewedContract__c
            FROM SBQQ__Quote__c
            WHERE Id IN :quoteIds
        ]);
    }
    
    /**
     * @description Get Product data for ACV processing
     * @param productIds Set of Product IDs
     * @return Map of Product records
     */
    public static Map<Id, Product2> getProductData(Set<Id> productIds) {
        if (productIds.isEmpty()) {
            return new Map<Id, Product2>();
        }
        return new Map<Id, Product2>([
            SELECT Id, Product_Type__c, Guided_Selling_Type__c
            FROM Product2
            WHERE Id IN :productIds
        ]);
    }
    
    /**
     * @description Get Subscription data for ACV processing
     * @param subscriptionIds Set of Subscription IDs
     * @return Map of Subscription records
     */
    public static Map<Id, SBQQ__Subscription__c> getSubscriptionData(Set<Id> subscriptionIds) {
        if (subscriptionIds.isEmpty()) {
            return new Map<Id, SBQQ__Subscription__c>();
        }
        return new Map<Id, SBQQ__Subscription__c>([
            SELECT Id, SBQQ__OriginalQuoteLine__c, SBQQ__OriginalQuoteLine__r.SBQQ__Quote__c,
                   SBQQ__OriginalQuoteLine__r.SBQQ__Quote__r.Id, SBQQ__OriginalQuoteLine__r.SBQQ__Quote__r.SegmentIndex_Max__c,
                   SBQQ__NetPrice__c, SBQQ__Quantity__c, SBQQ__ProrateMultiplier__c,
                   SBQQ__RevisedSubscription__c, Last_Segment_Subscription__c,
                   Last_Segment_Subscription__r.SBQQ__NetPrice__c, Last_Segment_Subscription__r.SBQQ__Quantity__c,
                   Last_Segment_Subscription__r.SBQQ__ProrateMultiplier__c
            FROM SBQQ__Subscription__c
            WHERE Id IN :subscriptionIds
        ]);
    }
    
    /***********************************************************************************************
    *
    * Renewal/Original Quote Line Queries
    *
    ***********************************************************************************************/
    
    /**
     * @description Get original quote lines for renewal calculations
     * @param originalQuoteIds Set of original quote IDs
     * @param quoteLines List of quote lines being processed
     * @param productMap Map of product records
     * @param subscriptionMap Map of subscription records
     * @return Map of original quote lines keyed by product and quote
     */
    public static Map<String, SBQQ__QuoteLine__c> getOriginalQuoteLines(
        Set<Id> originalQuoteIds, 
        List<SBQQ__QuoteLine__c> quoteLines,
        Map<Id, Product2> productMap,
        Map<Id, SBQQ__Subscription__c> subscriptionMap
    ) {
        Map<String, SBQQ__QuoteLine__c> result = new Map<String, SBQQ__QuoteLine__c>();
        
        if (originalQuoteIds.isEmpty()) {
            return result;
        }
        
        // Collect original quote line IDs and their segment keys
        Set<Id> originalQuoteLineIds = new Set<Id>();
        Map<Id, Integer> quoteToSegmentMax = new Map<Id, Integer>();
        
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            SBQQ__Subscription__c sub = subscriptionMap.get(ql.SBQQ__RenewedSubscription__c);
            if (sub?.SBQQ__OriginalQuoteLine__c != null) {
                originalQuoteLineIds.add(sub.SBQQ__OriginalQuoteLine__c);
                Id quoteId = sub.SBQQ__OriginalQuoteLine__r?.SBQQ__Quote__c;
                if (quoteId != null) {
                    Integer segmentMax = sub.SBQQ__OriginalQuoteLine__r?.SBQQ__Quote__r?.SegmentIndex_Max__c != null
                        ? Integer.valueOf(sub.SBQQ__OriginalQuoteLine__r.SBQQ__Quote__r.SegmentIndex_Max__c) : 1;
                    quoteToSegmentMax.put(quoteId, segmentMax);
                }
            }
        }
        
        if (originalQuoteLineIds.isEmpty()) {
            return result;
        }
        
        // First, get the segment keys for the original quote lines
        Map<Id, String> originalQLToSegmentKey = new Map<Id, String>();
        Map<Id, Id> originalQLToQuoteId = new Map<Id, Id>();
        for (SBQQ__QuoteLine__c origQL : [
            SELECT Id, SBQQ__Quote__c, SBQQ__SegmentKey__c
            FROM SBQQ__QuoteLine__c
            WHERE Id IN :originalQuoteLineIds
        ]) {
            originalQLToSegmentKey.put(origQL.Id, origQL.SBQQ__SegmentKey__c);
            originalQLToQuoteId.put(origQL.Id, origQL.SBQQ__Quote__c);
        }
        
        // Collect all segment keys we need to query
        Set<String> segmentKeys = new Set<String>(originalQLToSegmentKey.values());
        
        // Query all quote lines with these segment keys and sum by segment key
        Map<String, Decimal> totalAcvBySegmentKey = new Map<String, Decimal>();
        Map<String, SBQQ__QuoteLine__c> lastSegmentBySegmentKey = new Map<String, SBQQ__QuoteLine__c>();
        
        for (SBQQ__QuoteLine__c origQL : [
            SELECT Id, SBQQ__Quote__c, SBQQ__Product__c, SBQQ__SegmentIndex__c, 
                   SBQQ__SegmentKey__c, Original_ACV_Change__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c IN :originalQuoteIds
              AND SBQQ__SegmentKey__c IN :segmentKeys
            ORDER BY SBQQ__SegmentIndex__c ASC
        ]) {
            String segmentKey = origQL.SBQQ__SegmentKey__c;
            Integer targetSegment = quoteToSegmentMax.get(origQL.SBQQ__Quote__c);
            
            if (targetSegment != null && segmentKey != null) {
                // Sum up Original_ACV_Change from all segments with same segment key
                Decimal currentTotal = totalAcvBySegmentKey.containsKey(segmentKey) 
                    ? totalAcvBySegmentKey.get(segmentKey) : 0;
                Decimal segmentAcv = origQL.Original_ACV_Change__c != null ? origQL.Original_ACV_Change__c : 0;
                totalAcvBySegmentKey.put(segmentKey, currentTotal + segmentAcv);
                
                // Track the last segment quote line (for structure)
                if (origQL.SBQQ__SegmentIndex__c == targetSegment) {
                    lastSegmentBySegmentKey.put(segmentKey, origQL);
                }
            }
        }
        
        // Build result map keyed by original quote line ID
        for (Id originalQLId : originalQuoteLineIds) {
            String segmentKey = originalQLToSegmentKey.get(originalQLId);
            
            if (segmentKey == null) {
                continue;
            }
            
            SBQQ__QuoteLine__c lastSegmentQL = lastSegmentBySegmentKey.get(segmentKey);
            if (lastSegmentQL == null) {
                continue;
            }
            
            // Create a clone with the summed Original_ACV_Change for multi-year
            SBQQ__QuoteLine__c resultQL = lastSegmentQL.clone(true, true, true, true);
            resultQL.Original_ACV_Change__c = totalAcvBySegmentKey.get(segmentKey);
            
            // Key by original quote line ID for unique lookup
            String key = String.valueOf(originalQLId);
            result.put(key, resultQL);
        }
        
        return result;
    }
    
    /***********************************************************************************************
    *
    * Multi-year Segment Queries
    *
    ***********************************************************************************************/
    
    /**
     * @description Get previous segment lines for multi-year deals
     * @param quoteLines List of quote lines being processed
     * @return Map of previous segment lines
     */
    public static Map<String, SBQQ__QuoteLine__c> getPreviousSegmentLines(List<SBQQ__QuoteLine__c> quoteLines) {
        Map<String, SBQQ__QuoteLine__c> result = new Map<String, SBQQ__QuoteLine__c>();
        
        // Filter to only multi-year quote lines (segment > 1)
        List<SBQQ__QuoteLine__c> multiYearLines = new List<SBQQ__QuoteLine__c>();
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            if (ql.SBQQ__SegmentIndex__c > 1) {
                multiYearLines.add(ql);
            }
        }
        
        if (multiYearLines.isEmpty()) {
            return result;
        }
        
        Set<Id> quoteIds = Pluck.ids(SBQQ__QuoteLine__c.SBQQ__Quote__c, multiYearLines);
        Set<Id> productIds = Pluck.ids(SBQQ__QuoteLine__c.SBQQ__Product__c, multiYearLines);
        
        for (SBQQ__QuoteLine__c prevQL : [
            SELECT Id, SBQQ__Quote__c, SBQQ__Product__c, SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c,
                   SBQQ__EffectiveQuantity__c, Original_ACV_Change__c, SBQQ__NetTotal__c,
                   SBQQ__ProrateMultiplier__c, Extended_Term_Discount__c, ACV_Change__c,
                   ACV_Change_Manual__c, Previous_ACV_Change__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c IN :quoteIds
              AND SBQQ__Product__c IN :productIds
        ]) {
            String key = getPreviousSegmentKey(prevQL);
            result.put(key, prevQL);
        }
        
        return result;
    }
    
    /***********************************************************************************************
    *
    * Add-on Subscription Queries
    *
    ***********************************************************************************************/
    
    /**
     * @description Get add-on subscriptions for renewal calculations
     * @param contractIds Set of contract IDs
     * @param quoteLines List of quote lines being processed
     * @param productMap Map of product records
     * @return Map of subscriptions by contract ID
     */
    public static Map<Id, List<SBQQ__Subscription__c>> getAddOnSubscriptions(
        Set<Id> contractIds, 
        List<SBQQ__QuoteLine__c> quoteLines,
        Map<Id, Product2> productMap
    ) {
        Map<Id, List<SBQQ__Subscription__c>> result = new Map<Id, List<SBQQ__Subscription__c>>();
        
        if (contractIds.isEmpty()) {
            return result;
        }
        
        Set<Id> productIds = Pluck.ids(SBQQ__QuoteLine__c.SBQQ__Product__c, quoteLines);
        
        for (SBQQ__Subscription__c sub : [
            SELECT Id, SBQQ__Contract__c, SBQQ__Product__c, 
                   SBQQ__QuoteLine__r.Original_ACV_Change__c,
                   SBQQ__RevisedSubscription__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c IN :contractIds
              AND SBQQ__Product__c IN :productIds
              AND SBQQ__RevisedSubscription__c != null
        ]) {
            if (!result.containsKey(sub.SBQQ__Contract__c)) {
                result.put(sub.SBQQ__Contract__c, new List<SBQQ__Subscription__c>());
            }
            result.get(sub.SBQQ__Contract__c).add(sub);
        }
        
        return result;
    }
    
    /***********************************************************************************************
    *
    * OpportunityLineItem Queries
    *
    ***********************************************************************************************/
    
    /**
     * @description Get OpportunityLineItems related to quote lines
     * @param quoteLineIds Set of quote line IDs
     * @return List of OpportunityLineItems
     */
    public static List<OpportunityLineItem> getOpportunityLineItems(Set<Id> quoteLineIds) {
        if (quoteLineIds.isEmpty()) {
            return new List<OpportunityLineItem>();
        }
        return [
            SELECT Id, SBQQ__QuoteLine__c, ACV_Change__c
            FROM OpportunityLineItem
            WHERE SBQQ__QuoteLine__c IN :quoteLineIds
        ];
    }
    
    /***********************************************************************************************
    *
    * Key Generation Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Get key for original quote line lookup
     * @param ctx ACV calculation context
     * @return Lookup key string
     */
    public static String getOriginalLineKey(ACVContext ctx) {
        if (ctx.subscription?.SBQQ__OriginalQuoteLine__c == null) {
            return null;
        }
        // Use original quote line ID as the unique key
        return String.valueOf(ctx.subscription.SBQQ__OriginalQuoteLine__c);
    }
    
    /**
     * @description Get key for previous segment line lookup
     * @param ql Quote line
     * @return Lookup key string
     */
    public static String getPreviousSegmentKey(SBQQ__QuoteLine__c ql) {
        return ql.SBQQ__Quote__c + '-' + ql.SBQQ__Product__c + '-' + Integer.valueOf(ql.SBQQ__SegmentIndex__c) + '-' + ql.SBQQ__SegmentKey__c;
    }
    
    /**
     * @description Get key for looking up previous segment (segment index - 1)
     * @param ctx ACV calculation context
     * @return Lookup key string for previous segment
     */
    public static String getPreviousSegmentLookupKey(ACVContext ctx) {
        return ctx.quoteLine.SBQQ__Quote__c + '-' + ctx.quoteLine.SBQQ__Product__c + '-' + (ctx.segmentIndex - 1) + '-' + ctx.quoteLine.SBQQ__SegmentKey__c;
    }
    
    /***********************************************************************************************
    *
    * ID Collection Helpers
    *
    ***********************************************************************************************/
    
    /**
     * @description Collect IDs from quote lines for batch queries
     * @param quoteLines List of quote lines
     * @return Map containing sets of quoteIds, productIds, and subscriptionIds
     */
    public static Map<String, Set<Id>> collectQuoteLineIds(List<SBQQ__QuoteLine__c> quoteLines) {
        return new Map<String, Set<Id>>{
            'quoteIds' => Pluck.ids(SBQQ__QuoteLine__c.SBQQ__Quote__c, quoteLines),
            'productIds' => Pluck.ids(SBQQ__QuoteLine__c.SBQQ__Product__c, quoteLines),
            'subscriptionIds' => Pluck.ids(SBQQ__QuoteLine__c.SBQQ__RenewedSubscription__c, quoteLines)
        };
    }
    
    /**
     * @description Collect original quote IDs and renewed contract IDs from related data
     * @param quoteLines List of quote lines
     * @param quoteMap Map of quotes
     * @param subscriptionMap Map of subscriptions
     * @return Map containing sets of originalQuoteIds and renewedContractIds
     */
    public static Map<String, Set<Id>> collectRelatedIds(
        List<SBQQ__QuoteLine__c> quoteLines,
        Map<Id, SBQQ__Quote__c> quoteMap,
        Map<Id, SBQQ__Subscription__c> subscriptionMap
    ) {
        Set<Id> originalQuoteIds = new Set<Id>();
        Set<Id> renewedContractIds = new Set<Id>();
        
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            SBQQ__Quote__c quote = quoteMap.get(ql.SBQQ__Quote__c);
            SBQQ__Subscription__c sub = subscriptionMap.get(ql.SBQQ__RenewedSubscription__c);
            
            // Skip if quote is calculating tax or is a Migration Quote
            if (quote == null || isQuoteSkippable(quote)) {
                continue;
            }
            
            // Collect original quote IDs for renewal scenarios
            if (sub?.SBQQ__OriginalQuoteLine__r?.SBQQ__Quote__c != null) {
                originalQuoteIds.add(sub.SBQQ__OriginalQuoteLine__r.SBQQ__Quote__c);
            }
            
            // Collect renewed contract IDs for add-on subscription queries
            if (quote.SBQQ__Opportunity2__r?.SBQQ__RenewedContract__c != null) {
                renewedContractIds.add(quote.SBQQ__Opportunity2__r.SBQQ__RenewedContract__c);
            }
        }
        
        return new Map<String, Set<Id>>{
            'originalQuoteIds' => originalQuoteIds,
            'renewedContractIds' => renewedContractIds
        };
    }
    
    /**
     * @description Check if a quote should be skipped from ACV processing
     * @param quote The quote record
     * @return True if quote should be skipped
     */
    public static Boolean isQuoteSkippable(SBQQ__Quote__c quote) {
        return quote.AVA_SFCPQ__AvaTaxMessage__c == QuoteConstants.AVA_TAX_MSG_REFRESH 
            || quote.SBQQ__Type__c == QuoteConstants.TYPE_MIGRATION_QUOTE;
    }
}