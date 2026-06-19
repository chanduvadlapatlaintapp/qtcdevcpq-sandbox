/**
 * @description Evaluator class for determining ACV calculation scenarios.
 *              Separates scenario detection logic from calculation logic.
 * @author Sahal Mohamed
 * @date 2026-02-04
 */
public class ACVScenarioEvaluator {
    
    /***********************************************************************************************
    *
    * Main Scenario Evaluation
    *
    ***********************************************************************************************/
    
    /**
     * @description Evaluate and return the applicable ACV scenario for a quote line
     * @param ctx ACV calculation context
     * @return The applicable ACVScenario
     */
    public static ACVScenario evaluateScenario(ACVContext ctx) {
        // Scenario 1: Segment 1 New Sale or Amendment (Software)
        if (isNewSaleAmendmentScenario(ctx)) {
            return ACVScenario.NEW_SALE_AMENDMENT;
        }
        
        // Scenario 2: Consolidation Credit Lines
        if (isConsolidationCreditScenario(ctx)) {
            return ACVScenario.CONSOLIDATION_CREDIT;
        }
        
        // Scenario 3: Segment 1 Renewal (Software, Maintenance, Support)
        if (isRenewalScenario(ctx)) {
            return ACVScenario.RENEWAL;
        }
        
        // Scenario 4: Segment > 1 (Multi-year Software)
        if (isMultiYearScenario(ctx)) {
            return ACVScenario.MULTI_YEAR;
        }
        
        return ACVScenario.NONE;
    }
    
    /***********************************************************************************************
    *
    * Scenario Detection Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Check if this is a New Sale or Amendment scenario (Scenario 1)
     *              Conditions: Segment 1, Software product, Quote or Amendment type
     * @param ctx ACV calculation context
     * @return True if this is a new sale/amendment scenario
     */
    public static Boolean isNewSaleAmendmentScenario(ACVContext ctx) {
        return ctx.segmentIndex == 1 
            && ctx.guidedSellingType == ProductConstants.GUIDED_SELLING_TYPE_SOFTWARE
            && (ctx.quoteType == QuoteConstants.TYPE_QUOTE || ctx.quoteType == QuoteConstants.TYPE_AMENDMENT);
    }
    
    /**
     * @description Check if this is a Consolidation Credit scenario (Scenario 2)
     *              Conditions: Renewal type, Consolidated renewal, negative quantity, has renewed subscription
     * @param ctx ACV calculation context
     * @return True if this is a consolidation credit scenario
     */
    public static Boolean isConsolidationCreditScenario(ACVContext ctx) {
        return ctx.quoteType == QuoteConstants.TYPE_RENEWAL 
            && ctx.renewalQuoteType == QuoteConstants.RENEWAL_TYPE_CONSOLIDATED
            && ctx.hasNegativeQuantity
            && ctx.hasRenewedSubscription;
    }
    
    /**
     * @description Check if this is a Renewal scenario (Scenario 3)
     *              Conditions: Segment 1, Software/Maintenance/Support product, Renewal type, 
     *                          not auto-renewal tax change, non-negative quantity
     * @param ctx ACV calculation context
     * @return True if this is a renewal scenario
     */
    public static Boolean isRenewalScenario(ACVContext ctx) {
        // Must be segment 1 (either by index or year)
        Boolean isSegment1 = ctx.segmentIndex == 1 || ctx.segmentIndexYear == 1;
        
        // Must be Software, Maintenance, or Support product type
        Boolean isApplicableProductType = ctx.productType == ProductConstants.PRODUCT_TYPE_SOFTWARE 
            || ctx.productType == ProductConstants.PRODUCT_TYPE_MAINTENANCE 
            || ctx.productType == ProductConstants.PRODUCT_TYPE_SUPPORT;
        
        // Must be Renewal quote type
        Boolean isRenewal = ctx.quoteType == QuoteConstants.TYPE_RENEWAL;
        
        // Must not be auto-renewal with only tax change
        Boolean notAutoRenewalTaxChange = !isAutoRenewalTaxChanged(ctx);
        
        // Must have non-negative quantity
        Boolean nonNegativeQty = ctx.hasNonNegativeQuantity;
        
        return isSegment1 && isApplicableProductType && isRenewal && notAutoRenewalTaxChange && nonNegativeQty;
    }
    
    /**
     * @description Check if this is a Multi-year scenario (Scenario 4)
     *              Conditions: Segment > 1, Software product, not auto-renewal tax change
     * @param ctx ACV calculation context
     * @return True if this is a multi-year scenario
     */
    public static Boolean isMultiYearScenario(ACVContext ctx) {
        return ctx.segmentIndex > 1 
            && ctx.guidedSellingType == ProductConstants.GUIDED_SELLING_TYPE_SOFTWARE
            && !isAutoRenewalTaxChanged(ctx);
    }
    
    /***********************************************************************************************
    *
    * Helper Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Check if this is an auto-renewal with only tax change
     *              This replicates the flow's ISCHANGED check for AVA_SFCPQ__TaxAmount__c
     *              on Auto-Renewal quotes to exclude them from ACV recalculation when only tax changes
     * @param ctx ACV calculation context
     * @return True if auto-renewal with tax change (should skip ACV calculation)
     */
    public static Boolean isAutoRenewalTaxChanged(ACVContext ctx) {
        // Only applies to Auto-Renewal quote type
        if (ctx.renewalQuoteType != QuoteConstants.RENEWAL_TYPE_AUTO) {
            return false;
        }
        
        // For insert operations, no tax change possible
        if (ctx.oldQuoteLine == null) {
            return false;
        }
        
        // Check if tax amount changed
        Decimal currentTax = ctx.quoteLine.AVA_SFCPQ__TaxAmount__c != null ? ctx.quoteLine.AVA_SFCPQ__TaxAmount__c : 0;
        Decimal oldTax = ctx.oldQuoteLine.AVA_SFCPQ__TaxAmount__c != null ? ctx.oldQuoteLine.AVA_SFCPQ__TaxAmount__c : 0;
        
        return currentTax != oldTax;
    }
    
    /***********************************************************************************************
    *
    * Logging Utilities
    *
    ***********************************************************************************************/
    
    /**
     * @description Get the scenario name for logging purposes
     * @param scenario The ACVScenario enum value
     * @param segmentIndex The segment index (for multi-year logging)
     * @return Human-readable scenario name
     */
    public static String getScenarioName(ACVScenario scenario, Integer segmentIndex) {
        switch on scenario {
            when NEW_SALE_AMENDMENT {
                return 'Scenario 1: Segment 1 New Sale/Amendment';
            }
            when CONSOLIDATION_CREDIT {
                return 'Scenario 2: Consolidation Credit Lines';
            }
            when RENEWAL {
                return 'Scenario 3: Segment 1 Renewal';
            }
            when MULTI_YEAR {
                return 'Scenario 4: Multi-year Segment ' + segmentIndex;
            }
            when else {
                return 'None';
            }
        }
    }
}