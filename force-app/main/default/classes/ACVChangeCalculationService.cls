/**
 * @description Service class for calculating ACV Change values on Quote Lines.
 *              Orchestrates ACV calculations using helper classes for better maintainability.
 * @author Sahal Mohamed
 * @date 2026-01-22
 * 
 * Business Logic:
 * - Segment 1 New Sale/Amendment: Original_ACV_Change = calculateValue, Previous_ACV_Change = 0
 * - Segment 1 Renewal: Previous_ACV_Change from original quote line or migrated calculation
 * - Segment > 1 (Multi-year): Calculate based on prior segment
 * - Add-on Subscriptions: Sum Original_ACV_Change from add-on subscriptions
 * - ACV_Change__c: Final value based on quote type and manual override
 * 
 * Related Tickets: BIZ-65281, BIZ-65821, BIZ-50449, BIZ-46894, BIZ-47135, BIZ-50365, 
 *                  BIZ-68198, BIZ-77496, BIZ-77645, BIZ-78712
 * 
 * Helper Classes:
 * - ACVContext: DTO for passing calculation context
 * - ACVScenarioEvaluator: Determines which ACV scenario applies
 * - ACVCalculator: Pure calculation functions
 * - ACVDataProvider: SOQL queries and key generation
 */
public without sharing class ACVChangeCalculationService {
    
    /***********************************************************************************************
    *
    * Static Variables
    *
    ***********************************************************************************************/
    
    // Static flag to prevent recursion - persists for entire transaction
    private static Boolean isProcessing = false;
    
    // Track processed quote line IDs to prevent re-processing in same transaction
    private static Set<Id> processedQuoteLineIds = new Set<Id>();
    
    /***********************************************************************************************
    *
    * Public Entry Points
    *
    ***********************************************************************************************/
    
    /**
     * @description Main entry point for ACV Change calculation (before-context)
     *              Sets ACV fields directly on trigger records - no DML needed for Quote Lines.
     * @param quoteLines List of quote lines to process
     * @param oldMap Map of old quote line values (null for insert)
     */
    public static void calculateACVChange(List<SBQQ__QuoteLine__c> quoteLines, Map<Id, SBQQ__QuoteLine__c> oldMap) {
        // Check if ACV Change automation is bypassed via custom setting
        if (shouldBypass()) {
            Nebula.Logger.debug('ACVChangeCalculationService: Skipping due to Bypass_ACV_Change_Automation__c setting').addTag('ACV_Change');
            return;
        }
        
        // Prevent recursion - if already processing, skip entirely
        if (isProcessing) {
            Nebula.Logger.debug('ACVChangeCalculationService: Skipping due to recursion prevention').addTag('ACV_Change');
            return;
        }
        
        // Filter out already processed quote lines (for re-entry scenarios)
        List<SBQQ__QuoteLine__c> unprocessedLines = new List<SBQQ__QuoteLine__c>();
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            if (ql.Id == null || !processedQuoteLineIds.contains(ql.Id)) {
                unprocessedLines.add(ql);
            }
        }
        
        if (unprocessedLines.isEmpty()) {
            Nebula.Logger.debug('ACVChangeCalculationService: All quote lines already processed in this transaction').addTag('ACV_Change');
            return;
        }
        
        Nebula.Logger.info('ACVChangeCalculationService.calculateACVChange started - Processing ' + 
            unprocessedLines.size() + ' quote lines (filtered from ' + quoteLines.size() + ')').addTag('ACV_Change');
        
        try {
            isProcessing = true;
            processQuoteLines(unprocessedLines, oldMap);
            
            // Mark these quote lines as processed
            processedQuoteLineIds.addAll(Pluck.ids(unprocessedLines));
            
            Nebula.Logger.info('ACVChangeCalculationService.calculateACVChange completed successfully').addTag('ACV_Change');
        } catch (Exception e) {
            Nebula.Logger.error('ACVChangeCalculationService.calculateACVChange failed', e).addTag('ACV_Change');
            throw e; // Re-throw to prevent silent failures
        } finally {
            isProcessing = false;
            Nebula.Logger.saveLog();
        }
    }
    
    /***********************************************************************************************
    *
    * Bypass and Utility Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Check if ACV Change automation should be bypassed
     * @return True if bypass is enabled in Automation_Controls__c custom setting
     */
    @TestVisible
    private static Boolean shouldBypass() {
        Automation_Controls__c settings = Automation_Controls__c.getInstance();
        return settings != null && settings.Bypass_ACV_Change_Automation__c == true;
    }
    
    /**
     * @description Clear processed quote line IDs (for testing purposes)
     */
    @TestVisible
    private static void clearProcessedIds() {
        processedQuoteLineIds.clear();
    }
    
    /***********************************************************************************************
    *
    * OpportunityLineItem Sync
    *
    ***********************************************************************************************/
    
    /**
     * @description Sync ACV Change values to related OpportunityLineItems (after-context)
     *              This should be called from afterInsert/afterUpdate since it requires DML.
     * @param quoteLines List of quote lines with ACV values already calculated
     */
    public static void syncOpportunityLineItems(List<SBQQ__QuoteLine__c> quoteLines) {
        if (quoteLines == null || quoteLines.isEmpty()) {
            return;
        }
        
        // Check if bypass is enabled
        if (shouldBypass()) {
            return;
        }
        
        // Build map of quote line IDs to ACV Change values
        Map<Id, Decimal> quoteLineToACVChange = new Map<Id, Decimal>();
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            if (ql.Id != null && ql.ACV_Change__c != null) {
                quoteLineToACVChange.put(ql.Id, ql.ACV_Change__c);
            }
        }
        
        if (!quoteLineToACVChange.isEmpty()) {
            updateOpportunityLineItems(quoteLineToACVChange);
        }
    }
    
    /***********************************************************************************************
    *
    * Core Processing Logic
    *
    ***********************************************************************************************/
    
    /**
     * @description Process quote lines and calculate ACV values (before-context optimized)
     * @param quoteLines List of quote lines to process (trigger records - will be modified directly)
     * @param oldMap Map of old quote line values
     */
    private static void processQuoteLines(List<SBQQ__QuoteLine__c> quoteLines, Map<Id, SBQQ__QuoteLine__c> oldMap) {
        if (quoteLines == null || quoteLines.isEmpty()) {
            Nebula.Logger.debug('ACVChangeCalculationService.processQuoteLines: No quote lines to process').addTag('ACV_Change');
            return;
        }
        
        Nebula.Logger.debug('ACVChangeCalculationService.processQuoteLines: Processing ' + quoteLines.size() + ' quote lines').addTag('ACV_Change');
        
        // Collect IDs using data provider
        Map<String, Set<Id>> ids = ACVDataProvider.collectQuoteLineIds(quoteLines);
        
        // Query related data
        Map<Id, SBQQ__Quote__c> quoteMap = ACVDataProvider.getQuoteData(ids.get('quoteIds'));
        Map<Id, Product2> productMap = ACVDataProvider.getProductData(ids.get('productIds'));
        Map<Id, SBQQ__Subscription__c> subscriptionMap = ACVDataProvider.getSubscriptionData(ids.get('subscriptionIds'));
        
        // Collect additional IDs based on related data
        Map<String, Set<Id>> relatedIds = ACVDataProvider.collectRelatedIds(quoteLines, quoteMap, subscriptionMap);
        
        // Query additional related data
        Map<String, SBQQ__QuoteLine__c> originalQuoteLinesMap = ACVDataProvider.getOriginalQuoteLines(
            relatedIds.get('originalQuoteIds'), quoteLines, productMap, subscriptionMap);
        Map<String, SBQQ__QuoteLine__c> previousSegmentLinesMap = ACVDataProvider.getPreviousSegmentLines(quoteLines);
        // Fallback for new inserts: sibling segment lines aren't in DB yet (Before Insert),
        // so populate from trigger batch to allow segment 2+ to find segment 1 in memory.
        // SOQL results take precedence (not overwritten) so update scenario is unaffected.
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            if (ql.SBQQ__SegmentIndex__c != null) {
                String key = ACVDataProvider.getPreviousSegmentKey(ql);
                if (!previousSegmentLinesMap.containsKey(key)) {
                    previousSegmentLinesMap.put(key, ql);
                }
            }
        }
        Map<Id, List<SBQQ__Subscription__c>> addOnSubscriptionsMap = ACVDataProvider.getAddOnSubscriptions(
            relatedIds.get('renewedContractIds'), quoteLines, productMap);

        Map<Id, SBQQ__QuoteLine__c> triggerQuoteLinesById = new Map<Id, SBQQ__QuoteLine__c>();
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            if (ql.Id != null) {
                triggerQuoteLinesById.put(ql.Id, ql);
            }
        }
        
        // Process each quote line
        Integer modifiedCount = 0;
        
        for (SBQQ__QuoteLine__c ql : quoteLines) {
            SBQQ__Quote__c quote = quoteMap.get(ql.SBQQ__Quote__c);
            
            // Skip if quote should be skipped
            if (quote == null || ACVDataProvider.isQuoteSkippable(quote)) {
                continue;
            }
            
            // Build context
            ACVContext ctx = new ACVContext(
                ql,
                oldMap != null ? oldMap.get(ql.Id) : null,
                quote,
                productMap.get(ql.SBQQ__Product__c),
                subscriptionMap.get(ql.SBQQ__RenewedSubscription__c),
                originalQuoteLinesMap,
                previousSegmentLinesMap,
                addOnSubscriptionsMap,
                triggerQuoteLinesById
            );
            
            // Process the quote line
            if (processIndividualQuoteLine(ctx)) {
                modifiedCount++;
            }
        }
        
        Nebula.Logger.debug('ACVChangeCalculationService: Modified ' + modifiedCount + ' quote lines with ACV values (before-context, no DML)').addTag('ACV_Change');
        Nebula.Logger.debug('ACVChangeCalculationService.processQuoteLines: Completed processing').addTag('ACV_Change');
    }
    
    /**
     * @description Process an individual quote line and calculate ACV values
     * @param ctx ACV calculation context
     * @return True if the quote line was modified
     */
    private static Boolean processIndividualQuoteLine(ACVContext ctx) {
        // Evaluate scenario
        ACVScenario scenario = ACVScenarioEvaluator.evaluateScenario(ctx);
        
        if (scenario == ACVScenario.NONE) {
            return false;
        }
        
        Decimal originalACVChange = 0;
        Decimal previousACVChange = 0;
        Decimal yoyQuantityChange = null;
        
        // Calculate current value
        Decimal currentValue = ACVCalculator.calculateCurrentValue(ctx.quoteLine);
        
        // Calculate based on scenario
        switch on scenario {
            when NEW_SALE_AMENDMENT {
                originalACVChange = currentValue;
                previousACVChange = 0;
            }
            when CONSOLIDATION_CREDIT {
                originalACVChange = 0;
                previousACVChange = 0;
            }
            when RENEWAL {
                previousACVChange = calculateRenewalPreviousACV(ctx);
                originalACVChange = currentValue - previousACVChange;
            }
            when MULTI_YEAR {
                ACVResult multiYearResult = calculateMultiYearACV(ctx, currentValue);
                originalACVChange = multiYearResult.originalACVChange;
                previousACVChange = multiYearResult.previousACVChange;
                yoyQuantityChange = multiYearResult.yoyQuantityChange;
            }
        }
        
        // Determine final ACV_Change value
        Decimal acvChange = ACVCalculator.determineFinalACVChange(scenario, ctx, originalACVChange);
        
        // Set values directly on trigger record
        // Round to 2 decimal places to avoid floating-point precision artifacts
        // (e.g., CPQ may store NetPrice as 4172.9999 instead of 4173, causing 0.001 drift)
        ctx.quoteLine.Original_ACV_Change__c = originalACVChange != null ? originalACVChange.setScale(2, RoundingMode.HALF_UP) : null;
        ctx.quoteLine.Previous_ACV_Change__c = previousACVChange != null ? previousACVChange.setScale(2, RoundingMode.HALF_UP) : null;
        ctx.quoteLine.ACV_Change__c = acvChange != null ? acvChange.setScale(2, RoundingMode.HALF_UP) : null;
        
        if (yoyQuantityChange != null) {
            ctx.quoteLine.YOY_Quantity_Change__c = yoyQuantityChange;
        }
        
        // Log the calculation results
        String scenarioName = ACVScenarioEvaluator.getScenarioName(scenario, ctx.segmentIndex);
        Nebula.Logger.fine('QuoteLine ' + ctx.quoteLine.Id + ' ACV Calculation - ' +
                'Scenario: ' + scenarioName + 
                ' | QuoteType: ' + ctx.quoteType + 
                ' | SegmentIndex: ' + ctx.segmentIndex +
                ' | CurrentValue: ' + currentValue +
                ' | Original_ACV: ' + originalACVChange + 
                ' | Previous_ACV: ' + previousACVChange + 
                ' | ACV_Change: ' + acvChange).addTag('ACV_Change');
        
        return true;
    }
    
    /***********************************************************************************************
    *
    * Scenario-Specific Calculations
    *
    ***********************************************************************************************/
    
    /**
     * @description Calculate previous ACV for renewal scenario
     * @param ctx ACV calculation context
     * @return Calculated previous ACV value
     */
    private static Decimal calculateRenewalPreviousACV(ACVContext ctx) {
        Decimal previousACVChange = 0;
        Boolean usedOriginalQuoteLine = false;
        Boolean usedQtyBasedCalculation = false;
        
        // Get original quote line if exists
        String originalLineKey = ACVDataProvider.getOriginalLineKey(ctx);
        SBQQ__QuoteLine__c originalLine = ctx.originalQuoteLinesMap.get(originalLineKey);
        
        if (originalLine != null) {
            // Check if qty changed - if so, calculateRenewalPreviousValue will use migrated formula
            Decimal qlQty = ctx.quoteLine.SBQQ__Quantity__c != null ? ctx.quoteLine.SBQQ__Quantity__c : 0;
            Decimal subQty = ctx.subscription != null && ctx.subscription.SBQQ__Quantity__c != null 
                ? ctx.subscription.SBQQ__Quantity__c : 0;
            usedQtyBasedCalculation = (qlQty != subQty && ctx.subscription != null);
            
            previousACVChange = ACVCalculator.calculateRenewalPreviousValue(ctx, originalLine);
            usedOriginalQuoteLine = true;
            
            if (usedQtyBasedCalculation) {
                Nebula.Logger.fine('QuoteLine ' + ctx.quoteLine.Id + ': Using qty-based calculation for Previous ACV (qty changed from ' + subQty + ' to ' + qlQty + ')')
                    .addTag('ACV_Change');
            } else {
                Nebula.Logger.fine('QuoteLine ' + ctx.quoteLine.Id + ': Using original quote line for Previous ACV calculation')
                    .addTag('ACV_Change');
            }
        } else {
            previousACVChange = ACVCalculator.calculateMigratedPreviousValue(ctx);
            Nebula.Logger.fine('QuoteLine ' + ctx.quoteLine.Id + ': Using migrated calculation for Previous ACV')
                .addTag('ACV_Change');
        }
        
        // Add add-on subscription ACV (BIZ-78712)
        // Only add when using original quote line path AND qty hasn't changed
        // When qty changes, the migrated formula already uses consolidated qty, so don't double-count add-ons
        if (usedOriginalQuoteLine && !usedQtyBasedCalculation) {
            Decimal addOnACV = ACVCalculator.calculateAddOnSubscriptionACV(ctx);
            if (addOnACV != 0) {
                Nebula.Logger.fine('QuoteLine ' + ctx.quoteLine.Id + ': Added ' + addOnACV + ' from add-on subscriptions (BIZ-78712)')
                    .addTag('ACV_Change');
                previousACVChange += addOnACV;
            }
        }
        
        return previousACVChange;
    }
    
    /**
     * @description Calculate ACV for multi-year scenario
     * @param ctx ACV calculation context
     * @param currentValue Current ACV value
     * @return ACVResult containing calculated values
     */
    private static ACVResult calculateMultiYearACV(ACVContext ctx, Decimal currentValue) {
        ACVResult result = new ACVResult();
        
        String prevSegmentKey = ACVDataProvider.getPreviousSegmentLookupKey(ctx);
        SBQQ__QuoteLine__c prevSegmentLine = ctx.previousSegmentLinesMap.get(prevSegmentKey);
        
        if (prevSegmentLine != null) {
            result.previousACVChange = ACVCalculator.calculatePreviousSegmentValue(prevSegmentLine);
            result.originalACVChange = currentValue - result.previousACVChange;
            // Prefer same-batch Trigger.new quantity for previous segment (SOQL may be stale vs sibling lines).
            // SBQQ__EffectiveQuantity__c is not Apex-writeable on merged rows; resolve via ctx.triggerQuoteLinesById.
            Decimal previousEffQty = prevSegmentLine.SBQQ__EffectiveQuantity__c;
            if (ctx.triggerQuoteLinesById != null && prevSegmentLine.Id != null) {
                SBQQ__QuoteLine__c triggerPrev = ctx.triggerQuoteLinesById.get(prevSegmentLine.Id);
                if (triggerPrev != null && triggerPrev.SBQQ__EffectiveQuantity__c != null) {
                    previousEffQty = triggerPrev.SBQQ__EffectiveQuantity__c;
                }
            }
            result.yoyQuantityChange = ACVCalculator.calculateYOYQuantityChange(
                ctx.quoteLine.SBQQ__EffectiveQuantity__c,
                previousEffQty
            );
            Nebula.Logger.fine('QuoteLine ' + ctx.quoteLine.Id + ': Multi-year calculation - YOY Qty Change: ' + result.yoyQuantityChange)
                .addTag('ACV_Change');
        } else {
            Nebula.Logger.warn('QuoteLine ' + ctx.quoteLine.Id + ': Previous segment line not found for key: ' + prevSegmentKey)
                .addTag('ACV_Change');
            result.originalACVChange = currentValue;
            result.previousACVChange = 0;
        }
        
        return result;
    }
    
    /***********************************************************************************************
    *
    * DML Operations
    *
    ***********************************************************************************************/
    
    /**
     * @description Update OpportunityLineItems with ACV Change values
     * @param quoteLineToACVChange Map of quote line IDs to ACV Change values
     */
    private static void updateOpportunityLineItems(Map<Id, Decimal> quoteLineToACVChange) {
        if (quoteLineToACVChange.isEmpty()) {
            return;
        }
        
        List<OpportunityLineItem> olisToUpdate = ACVDataProvider.getOpportunityLineItems(quoteLineToACVChange.keySet());
        
        List<OpportunityLineItem> updates = new List<OpportunityLineItem>();
        for (OpportunityLineItem oli : olisToUpdate) {
            Decimal newACVChange = quoteLineToACVChange.get(oli.SBQQ__QuoteLine__c);
            if (oli.ACV_Change__c != newACVChange) {
                oli.ACV_Change__c = newACVChange;
                updates.add(oli);
            }
        }
        
        if (!updates.isEmpty()) {
            Nebula.Logger.debug('ACVChangeCalculationService: Updating ' + updates.size() + ' OpportunityLineItems with ACV Change values')
                .addTag('ACV_Change');
            update updates;
        }
    }
    
    /***********************************************************************************************
    *
    * Inner Classes
    *
    ***********************************************************************************************/
    
    /**
     * @description Inner class to hold multi-year calculation results
     */
    private class ACVResult {
        public Decimal originalACVChange = 0;
        public Decimal previousACVChange = 0;
        public Decimal yoyQuantityChange = null;
    }
}