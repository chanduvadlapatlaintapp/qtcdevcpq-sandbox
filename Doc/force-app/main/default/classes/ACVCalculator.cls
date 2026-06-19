/**
 * @description Calculator class for ACV Change values.
 *              Contains pure calculation functions without side effects.
 * @author Sahal Mohamed
 * @date 2026-02-04
 * @updated 2026-03-18
 */
public class ACVCalculator {
    
    /***********************************************************************************************
    *
    * Constants
    *
    ***********************************************************************************************/
    
    /**
     * @description Number of months in a year - used for ACV annualization
     */
    public static final Integer MONTHS_PER_YEAR = 12;
    
    /***********************************************************************************************
    *
    * Current Value Calculations
    *
    ***********************************************************************************************/
    
    /**
     * @description Calculate current ACV value from quote line
     * @param ql Quote line record
     * @return Calculated current ACV value
     */
    public static Decimal calculateCurrentValue(SBQQ__QuoteLine__c ql) {
        Decimal netTotal = ql.SBQQ__NetTotal__c != null ? ql.SBQQ__NetTotal__c : 0;
        Decimal extendedTermDiscount = ql.Extended_Term_Discount__c;
        Decimal prorateMultiplier = getProrateMultiplier(ql.SBQQ__ProrateMultiplier__c);
        
        if (extendedTermDiscount == null) {
            return (netTotal * MONTHS_PER_YEAR) / prorateMultiplier;
        } else {
            return ((netTotal + extendedTermDiscount) * MONTHS_PER_YEAR) / prorateMultiplier;
        }
    }
    
    /***********************************************************************************************
    *
    * Previous Value Calculations
    *
    ***********************************************************************************************/
    
    /**
     * @description Calculate previous segment value for multi-year deals
     * @param prevSegmentLine Previous segment quote line
     * @return Calculated previous segment ACV value
     */
    public static Decimal calculatePreviousSegmentValue(SBQQ__QuoteLine__c prevSegmentLine) {
        if (prevSegmentLine == null) {
            return 0;
        }
        
        // If ACV_Change_Manual is set, use different calculation
        if (prevSegmentLine.ACV_Change_Manual__c != null) {
            if (prevSegmentLine.Extended_Term_Discount__c == null) {
                return prevSegmentLine.ACV_Change__c + prevSegmentLine.Previous_ACV_Change__c;
            } else {
                return prevSegmentLine.ACV_Change__c;
            }
        }
        
        // Standard calculation
        Decimal netTotal = prevSegmentLine.SBQQ__NetTotal__c != null ? prevSegmentLine.SBQQ__NetTotal__c : 0;
        Decimal extendedTermDiscount = prevSegmentLine.Extended_Term_Discount__c;
        Decimal prorateMultiplier = getProrateMultiplier(prevSegmentLine.SBQQ__ProrateMultiplier__c);
        
        if (extendedTermDiscount == null) {
            return (netTotal * MONTHS_PER_YEAR) / prorateMultiplier;
        } else {
            return ((netTotal + extendedTermDiscount) * MONTHS_PER_YEAR) / prorateMultiplier;
        }
    }
    
    /**
     * @description Calculate renewal previous value when original quote line exists
     *              For multi-year deals, the originalLine already contains the summed
     *              Original_ACV_Change from all segments (handled by ACVDataProvider)
     *              
     *              BIZ-78712 Issue 3: When amendments change quantities, we need to use
     *              the unit price × consolidated qty formula instead of summing Original_ACV_Change
     *              values, because the original ACV was calculated with the pre-amendment quantity.
     * @param ctx ACV calculation context
     * @param originalLine Original quote line (with summed ACV for multi-year)
     * @return Calculated previous ACV value
     */
    public static Decimal calculateRenewalPreviousValue(ACVContext ctx, SBQQ__QuoteLine__c originalLine) {
        // Check if quantities have changed due to amendments
        // If QL qty differs from subscription qty, amendments changed the quantity
        Decimal qlQty = ctx.quoteLine.SBQQ__Quantity__c != null ? ctx.quoteLine.SBQQ__Quantity__c : 0;
        Decimal subQty = ctx.subscription != null && ctx.subscription.SBQQ__Quantity__c != null 
            ? ctx.subscription.SBQQ__Quantity__c : 0;
        
        if (qlQty != subQty && ctx.subscription != null) {
            // Quantities changed due to amendment - use unit price × consolidated qty formula
            // This is same as migrated calculation but we have original quote line context
            // Formula: (Last Segment NetPrice) × (Consolidated Qty) × 12 / ProrateMultiplier
            return calculateMigratedPreviousValue(ctx);
        }
        
        // Standard path: use original line's Original_ACV_Change (summed for multi-year by ACVDataProvider)
        return originalLine.Original_ACV_Change__c != null ? originalLine.Original_ACV_Change__c : 0;
    }
    
    /**
     * @description Calculate migrated previous value for contracts without original quote line
     *              For migrated contracts, we use the quote line's quantity (which represents
     *              the post-amendment state) combined with the subscription's renewal price.
     *              This ensures Previous ACV reflects what the customer was paying after amendments.
     * @param ctx ACV calculation context
     * @return Calculated migrated previous ACV value
     */
    public static Decimal calculateMigratedPreviousValue(ACVContext ctx) {
        if (ctx.subscription == null) {
            return 0;
        }
        
        // Use Last Segment Subscription if available for pricing info
        SBQQ__Subscription__c lastSegmentSub = ctx.subscription.Last_Segment_Subscription__r;
        
        Decimal renewalPrice;
        Decimal prorateMultiplier;
        
        if (lastSegmentSub != null) {
            renewalPrice = lastSegmentSub.SBQQ__NetPrice__c != null ? lastSegmentSub.SBQQ__NetPrice__c : 0;
            prorateMultiplier = getProrateMultiplier(lastSegmentSub.SBQQ__ProrateMultiplier__c);
        } else {
            renewalPrice = ctx.subscription.SBQQ__NetPrice__c != null ? ctx.subscription.SBQQ__NetPrice__c : 0;
            prorateMultiplier = getProrateMultiplier(ctx.subscription.SBQQ__ProrateMultiplier__c);
        }
        
        // Use quote line's quantity for migrated contracts - this represents the post-amendment
        // quantity which includes any amendments (add-ons or reductions) made to the contract.
        // The subscription quantity may only reflect the original pre-amendment value.
        Decimal quantity = ctx.quoteLine.SBQQ__Quantity__c != null ? ctx.quoteLine.SBQQ__Quantity__c : 0;
        
        // Formula: (RenewalPrice * Quantity * 12) / ProrateMultiplier
        return (renewalPrice * quantity * MONTHS_PER_YEAR) / prorateMultiplier;
    }
    
    /**
     * @description Calculate add-on subscription ACV contribution
     *              Add-on subscriptions are amendments that revised the original subscription.
     *              We sum the Original_ACV_Change from add-on subscriptions that revised
     *              the specific renewed subscription for this quote line.
     * @param ctx ACV calculation context
     * @return Total add-on subscription ACV
     */
    public static Decimal calculateAddOnSubscriptionACV(ACVContext ctx) {
        Id contractId = ctx.renewedContractId;
        if (contractId == null) {
            return 0;
        }
        
        // Get the renewed subscription ID from the quote line
        Id renewedSubscriptionId = ctx.quoteLine.SBQQ__RenewedSubscription__c;
        if (renewedSubscriptionId == null) {
            return 0;
        }
        
        List<SBQQ__Subscription__c> addOnSubs = ctx.addOnSubscriptionsMap.get(contractId);
        
        if (addOnSubs == null || addOnSubs.isEmpty()) {
            return 0;
        }
        
        Decimal totalAddOnACV = 0;
        for (SBQQ__Subscription__c sub : addOnSubs) {
            // Match add-on subscriptions that revised the specific renewed subscription
            if (sub.SBQQ__RevisedSubscription__c == renewedSubscriptionId) {
                Decimal addOnACV = sub.SBQQ__QuoteLine__r?.Original_ACV_Change__c != null 
                    ? sub.SBQQ__QuoteLine__r.Original_ACV_Change__c : 0;
                totalAddOnACV += addOnACV;
            }
        }
        
        return totalAddOnACV;
    }
    
    /***********************************************************************************************
    *
    * Final Value Determination
    *
    ***********************************************************************************************/
    
    /**
     * @description Determine the final ACV_Change value based on quote type and manual override
     * @param scenario The ACV scenario (passed for caller intent documentation; logic is derived from ctx)
     * @param ctx ACV calculation context
     * @param originalACVChange The calculated original ACV change (delta for multi-year)
     * @return Final ACV_Change value
     */
    public static Decimal determineFinalACVChange(ACVScenario scenario, ACVContext ctx, Decimal originalACVChange) {
        String quoteType = ctx.quoteType;
        String renewalQuoteType = ctx.renewalQuoteType;
        Integer segmentIndex = ctx.segmentIndex;

        // Amendment or Renewal-Changes: ACV_Change = 0
        if (quoteType == QuoteConstants.TYPE_AMENDMENT || renewalQuoteType == QuoteConstants.RENEWAL_TYPE_CHANGES) {
            return 0;
        }

        // Manual override
        if (ctx.quoteLine.ACV_Change_Manual__c != null
            && ctx.quoteLine.ACV_Change_Manual__c != 0
            && quoteType != QuoteConstants.TYPE_QUOTE
            && quoteType != QuoteConstants.TYPE_AMENDMENT
            && renewalQuoteType != QuoteConstants.RENEWAL_TYPE_CHANGES) {
            return ctx.quoteLine.ACV_Change_Manual__c;
        }

        // New Sale Segment 1: ACV_Change = 0
        if (segmentIndex == 1 && quoteType == QuoteConstants.TYPE_QUOTE) {
            return 0;
        }

        // Default: ACV_Change = Original_ACV_Change
        return originalACVChange;
    }
    
    /***********************************************************************************************
    *
    * YOY Calculations
    *
    ***********************************************************************************************/
    
    /**
     * @description Calculate Year-over-Year quantity change
     * @param currentQuantity Current effective quantity
     * @param previousQuantity Previous segment effective quantity
     * @return YOY quantity change
     */
    public static Decimal calculateYOYQuantityChange(Decimal currentQuantity, Decimal previousQuantity) {
        Decimal current = currentQuantity != null ? currentQuantity : 0;
        Decimal previous = previousQuantity != null ? previousQuantity : 0;
        return current - previous;
    }
    
    /***********************************************************************************************
    *
    * Helper Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Get prorate multiplier with default value
     * @param prorateMultiplier The prorate multiplier value
     * @return Prorate multiplier or default of 12
     */
    private static Decimal getProrateMultiplier(Decimal prorateMultiplier) {
        return (prorateMultiplier != null && prorateMultiplier != 0) ? prorateMultiplier : MONTHS_PER_YEAR;
    }
}