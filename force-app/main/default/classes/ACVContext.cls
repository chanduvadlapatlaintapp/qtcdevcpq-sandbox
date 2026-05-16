/**
 * @description Data Transfer Object (DTO) for ACV Change calculation context.
 *              Encapsulates all data needed to calculate ACV values for a single quote line.
 * @author Sahal Mohamed
 * @date 2026-02-04
 */
public class ACVContext {
    
    /***********************************************************************************************
    *
    * Core Records
    *
    ***********************************************************************************************/
    
    public SBQQ__QuoteLine__c quoteLine { get; set; }
    public SBQQ__QuoteLine__c oldQuoteLine { get; set; }
    public SBQQ__Quote__c quote { get; set; }
    public Product2 product { get; set; }
    public SBQQ__Subscription__c subscription { get; set; }
    
    /***********************************************************************************************
    *
    * Lookup Maps
    *
    ***********************************************************************************************/
    
    public Map<String, SBQQ__QuoteLine__c> originalQuoteLinesMap { get; set; }
    public Map<String, SBQQ__QuoteLine__c> previousSegmentLinesMap { get; set; }
    public Map<Id, List<SBQQ__Subscription__c>> addOnSubscriptionsMap { get; set; }

    /** In-memory trigger state for sibling lines in the same batch (keyed by Id).
     *  Used to resolve SBQQ__EffectiveQuantity__c for previous segments without
     *  relying on stale SOQL results within the same transaction. */
    public Map<Id, SBQQ__QuoteLine__c> triggerQuoteLinesById { get; set; }
    
    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    
    /**
     * @description Default constructor
     */
    public ACVContext() {
        this.originalQuoteLinesMap = new Map<String, SBQQ__QuoteLine__c>();
        this.previousSegmentLinesMap = new Map<String, SBQQ__QuoteLine__c>();
        this.addOnSubscriptionsMap = new Map<Id, List<SBQQ__Subscription__c>>();
        this.triggerQuoteLinesById = new Map<Id, SBQQ__QuoteLine__c>();
    }
    
    /**
     * @description Full constructor with all parameters
     */
    public ACVContext(
        SBQQ__QuoteLine__c quoteLine,
        SBQQ__QuoteLine__c oldQuoteLine,
        SBQQ__Quote__c quote,
        Product2 product,
        SBQQ__Subscription__c subscription,
        Map<String, SBQQ__QuoteLine__c> originalQuoteLinesMap,
        Map<String, SBQQ__QuoteLine__c> previousSegmentLinesMap,
        Map<Id, List<SBQQ__Subscription__c>> addOnSubscriptionsMap,
        Map<Id, SBQQ__QuoteLine__c> triggerQuoteLinesById
    ) {
        this.quoteLine = quoteLine;
        this.oldQuoteLine = oldQuoteLine;
        this.quote = quote;
        this.product = product;
        this.subscription = subscription;
        this.originalQuoteLinesMap = originalQuoteLinesMap != null ? originalQuoteLinesMap : new Map<String, SBQQ__QuoteLine__c>();
        this.previousSegmentLinesMap = previousSegmentLinesMap != null ? previousSegmentLinesMap : new Map<String, SBQQ__QuoteLine__c>();
        this.addOnSubscriptionsMap = addOnSubscriptionsMap != null ? addOnSubscriptionsMap : new Map<Id, List<SBQQ__Subscription__c>>();
        this.triggerQuoteLinesById = triggerQuoteLinesById != null ? triggerQuoteLinesById : new Map<Id, SBQQ__QuoteLine__c>();
    }
    
    /***********************************************************************************************
    *
    * Computed Properties
    *
    ***********************************************************************************************/
    
    /**
     * @description Quote type (Quote, Amendment, Renewal, Migration Quote)
     */
    public String quoteType {
        get { return quote?.SBQQ__Type__c; }
    }

    /**
     * @description Deal type (New_Software, Contract_Replacement, Uplift, Add-On, etc.)
     */
    public String dealType {
        get { return quote?.Deal_Type__c; }
    }

    /**
     * @description Renewal quote type (Auto, Consolidated, Changes)
     */
    public String renewalQuoteType {
        get { return quote?.Renewal_Quote_Type__c; }
    }
    
    /**
     * @description Segment index (1 for first year, 2+ for multi-year)
     */
    public Integer segmentIndex {
        get { 
            return quoteLine?.SBQQ__SegmentIndex__c != null 
                ? Integer.valueOf(quoteLine.SBQQ__SegmentIndex__c) 
                : 0; 
        }
    }
    
    /**
     * @description Segment index year (alternative segment tracking)
     */
    public Integer segmentIndexYear {
        get { 
            return quoteLine?.SegmentIndex_Year__c != null 
                ? Integer.valueOf(quoteLine.SegmentIndex_Year__c) 
                : 0; 
        }
    }
    
    /**
     * @description Product type (Software, Maintenance, Support, etc.)
     */
    public String productType {
        get { return product?.Product_Type__c; }
    }
    
    /**
     * @description Guided selling type (Software, Services, etc.)
     */
    public String guidedSellingType {
        get { return product?.Guided_Selling_Type__c; }
    }
    
    /**
     * @description Renewed contract ID from the opportunity
     */
    public Id renewedContractId {
        get { return quote?.SBQQ__Opportunity2__r?.SBQQ__RenewedContract__c; }
    }
    
    /**
     * @description Check if this is a renewal with revised subscription
     */
    public Boolean hasRevisedSubscription {
        get { return subscription?.SBQQ__RevisedSubscription__c != null; }
    }
    
    /**
     * @description Check if quote line has non-negative quantity
     */
    public Boolean hasNonNegativeQuantity {
        get { return quoteLine?.SBQQ__Quantity__c >= 0; }
    }
    
    /**
     * @description Check if quote line has negative quantity (credit line)
     */
    public Boolean hasNegativeQuantity {
        get { return quoteLine?.SBQQ__Quantity__c < 0; }
    }
    
    /**
     * @description Check if quote line has renewed subscription
     */
    public Boolean hasRenewedSubscription {
        get { return quoteLine?.SBQQ__RenewedSubscription__c != null; }
    }
}