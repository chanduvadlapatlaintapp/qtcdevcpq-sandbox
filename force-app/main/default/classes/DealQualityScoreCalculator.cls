/**
 * @description Service class for calculating Deal Quality Scores with support for calculated formula fields.
 *              This class provides a clean interface for calculating deal quality scores when formula fields
 *              need to be calculated from cart data rather than read from the quote record.
 * @author      : Auto-generated
 * @createdDate : 2025
 */
public class DealQualityScoreCalculator {
    
    /**
     * @description Calculates the Deal Quality Score for a quote with calculated formula field values.
     *              This method is used when formula fields (Initial_Term_Discount__c and 
     *              Min_year_on_year_committed_spend__c) need to be calculated from cart data
     *              rather than read from the quote record.
     * 
     * @param quoteId The ID of the quote record
     * @param calculatedInitialTermDiscount Calculated value for Initial_Term_Discount__c formula field
     * @param calculatedMinYoYSpend Calculated value for Min_year_on_year_committed_spend__c formula field
     * @return Integer The calculated Deal Quality Score
     */
    public static Integer calculateScoreWithCalculatedFields(
        String quoteId, 
        Decimal calculatedInitialTermDiscount, 
        Decimal calculatedMinYoYSpend
    ) {
        try {
            if (String.isBlank(quoteId)) {
                throw new IllegalArgumentException('Quote ID is required');
            }

            // Fetch the quote record with all necessary fields
            SBQQ__Quote__c quote = fetchQuoteForScoring(quoteId);

            // Collect scores using calculated formula field values
            List<Integer> scores = collectScoresWithCalculatedFields(
                quote, 
                calculatedInitialTermDiscount, 
                calculatedMinYoYSpend
            );
            
            // Return the minimum score (worst score)
            Integer finalScore = scores.isEmpty() ? 100 : getMinScore(scores);
            return finalScore;
        } catch (Exception e) {
            throw new DealQualityScoreException(
                'Error calculating deal quality score: ' + e.getMessage(), 
                e
            );
        }
    }

    /**
     * @description Calculates formula field values from quote data map.
     *              This method calculates Initial_Term_Discount__c and Min_year_on_year_committed_spend__c
     *              based on the provided quote data.
     * 
     * @param quoteData Map containing quote field values
     * @return DealQualityFormulaFields Wrapper containing calculated formula field values
     */
    public static DealQualityFormulaFields calculateFormulaFields(Map<String, Object> quoteData) {
        DealQualityFormulaFields formulaFields = new DealQualityFormulaFields();

        // Calculate Initial_Term_Discount__c
        // Formula: IF(ROUND(Segment_Total_List_Unit_Price__c,2) = 0, 0, 
        //         (Segment_Total_List_Unit_Price__c - Segment_Total_Net_unit_Price__c) / Segment_Total_List_Unit_Price__c * 100)
        Decimal segmentTotalListPrice = getDecimalValue(quoteData, 'Segment_Total_List_Unit_Price__c');
        Decimal segmentTotalNetPrice = getDecimalValue(quoteData, 'Segment_Total_Net_unit_Price__c');

        if (segmentTotalListPrice != null && segmentTotalListPrice != 0) {
            Decimal roundedListPrice = segmentTotalListPrice.setScale(2);
            if (roundedListPrice != 0) {
                formulaFields.initialTermDiscount = ((segmentTotalListPrice - segmentTotalNetPrice) / segmentTotalListPrice) * 100;
            } else {
                formulaFields.initialTermDiscount = 0;
            }
        } else {
            formulaFields.initialTermDiscount = 0;
        }

        // Calculate Min_year_on_year_committed_spend__c
        // This is the minimum year-over-year percentage change across all years
        Decimal firstYear = getDecimalValue(quoteData, 'First_Year_Software_Total__c');
        Decimal secondYear = getDecimalValue(quoteData, 'Second_Year_Software_Total__c');
        Decimal thirdYear = getDecimalValue(quoteData, 'Third_Year_Software_Total__c');
        Decimal fourthYear = getDecimalValue(quoteData, 'Fourth_Year_Software_Total__c');
        Decimal fifthYear = getDecimalValue(quoteData, 'Fifth_Year_Software_Total__c');
        Decimal sixthYear = getDecimalValue(quoteData, 'Sixth_Year_Software_Total__c');

        formulaFields.minYoYSpend = calculateMinYoYSpend(
            firstYear, secondYear, thirdYear, fourthYear, fifthYear, sixthYear
        );

        return formulaFields;
    }

    /**
     * @description Calculates the minimum year-over-year committed spend percentage.
     * 
     * @param firstYear First year software total
     * @param secondYear Second year software total
     * @param thirdYear Third year software total
     * @param fourthYear Fourth year software total
     * @param fifthYear Fifth year software total
     * @param sixthYear Sixth year software total
     * @return Decimal Minimum YoY percentage change (multiplied by 100)
     */
    private static Decimal calculateMinYoYSpend(
        Decimal firstYear, Decimal secondYear, Decimal thirdYear,
        Decimal fourthYear, Decimal fifthYear, Decimal sixthYear
    ) {
        if (firstYear == null || firstYear == 0 || secondYear == null || secondYear == 0) {
            return 0;
        }

        List<Decimal> yearOverYearChanges = new List<Decimal>();

        // Check if we have 6 years of data
        if (sixthYear != null && sixthYear != 0 && fifthYear != null && fifthYear != 0) {
            yearOverYearChanges.add((sixthYear - fifthYear) / fifthYear);
            yearOverYearChanges.add((fifthYear - fourthYear) / fourthYear);
            yearOverYearChanges.add((fourthYear - thirdYear) / thirdYear);
            yearOverYearChanges.add((thirdYear - secondYear) / secondYear);
            yearOverYearChanges.add((secondYear - firstYear) / firstYear);
        } else if (fifthYear != null && fifthYear != 0 && fourthYear != null && fourthYear != 0) {
            yearOverYearChanges.add((fifthYear - fourthYear) / fourthYear);
            yearOverYearChanges.add((fourthYear - thirdYear) / thirdYear);
            yearOverYearChanges.add((thirdYear - secondYear) / secondYear);
            yearOverYearChanges.add((secondYear - firstYear) / firstYear);
        } else if (fourthYear != null && fourthYear != 0 && thirdYear != null && thirdYear != 0) {
            yearOverYearChanges.add((fourthYear - thirdYear) / thirdYear);
            yearOverYearChanges.add((thirdYear - secondYear) / secondYear);
            yearOverYearChanges.add((secondYear - firstYear) / firstYear);
        } else if (thirdYear != null && thirdYear != 0 && secondYear != null && secondYear != 0) {
            yearOverYearChanges.add((thirdYear - secondYear) / secondYear);
            yearOverYearChanges.add((secondYear - firstYear) / firstYear);
        } else if (secondYear != null && secondYear != 0 && firstYear != null && firstYear != 0) {
            yearOverYearChanges.add((secondYear - firstYear) / firstYear);
        }

        if (yearOverYearChanges.isEmpty()) {
            return 0;
        }

        // Find minimum change
        Decimal minChange = yearOverYearChanges[0];
        for (Decimal change : yearOverYearChanges) {
            if (change < minChange) {
                minChange = change;
            }
        }

        return minChange * 100;
    }

    /**
     * @description Fetches the quote record with all fields needed for deal quality scoring.
     * 
     * @param quoteId The ID of the quote
     * @return SBQQ__Quote__c Quote record with all necessary fields
     */
    private static SBQQ__Quote__c fetchQuoteForScoring(String quoteId) {
        return [
            SELECT Id, Initial_Term_Discount__c, Min_year_on_year_committed_spend__c,
                   SFA_Cap_after_Initial_Term__c, SFA_Term__c, Future_Pricing_Commitment__c,
                   Product_Development_Obligation__c, Includes_Termination_Clause__c,
                   SBQQ__BillingFrequency__c, Software_Payment_Terms__c, GTM_Motion_Tier__c,
                   Segment_Total_List_Unit_Price__c, Segment_Total_Net_unit_Price__c,
                   First_Year_Software_Total__c, Second_Year_Software_Total__c,
                   Third_Year_Software_Total__c, Fourth_Year_Software_Total__c,
                   Fifth_Year_Software_Total__c, Sixth_Year_Software_Total__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            LIMIT 1
        ];
    }

    /**
     * @description Helper method to safely extract Decimal value from map.
     * 
     * @param dataMap Map containing the data
     * @param key Key to look up
     * @return Decimal The decimal value, or 0 if null/not found
     */
    private static Decimal getDecimalValue(Map<String, Object> dataMap, String key) {
        if (dataMap == null || !dataMap.containsKey(key)) {
            return 0;
        }
        Object value = dataMap.get(key);
        if (value == null) {
            return 0;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof String) {
            String strValue = (String) value;
            return String.isBlank(strValue) ? 0 : Decimal.valueOf(strValue);
        }
        return 0;
    }

    /**
     * @description Collects individual scores for each deal quality component using calculated formula field values.
     * 
     * @param quote SBQQ__Quote__c record to evaluate
     * @param calculatedInitialTermDiscount Calculated value for Initial_Term_Discount__c
     * @param calculatedMinYoYSpend Calculated value for Min_year_on_year_committed_spend__c
     * @return List<Integer> List of individual component scores
     */
    private static List<Integer> collectScoresWithCalculatedFields(
        SBQQ__Quote__c quote, 
        Decimal calculatedInitialTermDiscount, 
        Decimal calculatedMinYoYSpend
    ) {
        List<Integer> scores = new List<Integer>();

        // Score Initial Term Discount using calculated value
        Integer discountScore = scoreInitialTermDiscount(calculatedInitialTermDiscount);
        if (discountScore != null) { 
            scores.add(discountScore); 
        }

        // Score Min YoY Committed Spend using calculated value
        Integer spendScore = scoreMinYoYCommittedSpend(calculatedMinYoYSpend);
        if (spendScore != null) { 
            scores.add(spendScore); 
        }

        // Score other fields from quote
        Integer sfaCapScore = scoreSfaCapAfterInitialTerm(quote.SFA_Cap_after_Initial_Term__c);
        if (sfaCapScore != null) {
            scores.add(sfaCapScore);
        }

        Integer sfaTermScore = scoreSfaTerm(quote.SFA_Term__c);
        if (sfaTermScore != null) {
            scores.add(sfaTermScore);
        }

        Integer futurePricingScore = scoreFuturePricing(quote.Future_Pricing_Commitment__c);
        scores.add(futurePricingScore);

        Integer pdoScore = scoreProductDevelopmentObligation(quote.Product_Development_Obligation__c);
        scores.add(pdoScore);

        Integer termScore = scoreTerminationClause(quote.Includes_Termination_Clause__c);
        scores.add(termScore);

        Integer freqScore = scoreBillingFrequency(quote.SBQQ__BillingFrequency__c);
        if (freqScore != null) {
            scores.add(freqScore);
        }

        if (isEm4OrEm5(quote.GTM_Motion_Tier__c)) {
            Integer paymentScore = scorePaymentTerms(quote.Software_Payment_Terms__c);
            if (paymentScore != null) {
                scores.add(paymentScore);
            }
        }

        return scores;
    }

    /**
     * @description Scores the Initial Term Discount component.
     * @param discount Decimal value of the initial term discount percentage.
     * @return Integer Score based on discount thresholds.
     */
    private static Integer scoreInitialTermDiscount(Decimal discount) {
        if (discount == null) {
            return null;
        }
        if (discount < -5) {
            return 110;
        }
        if (discount >= -5 && discount <= 30) {
            return 100;
        }
        return 90;
    }

    /**
     * @description Scores the Minimum Year-on-Year Committed Spend component.
     * @param spend Decimal value of the minimum year-on-year committed spend.
     * @return Integer Score based on spend thresholds.
     */
    private static Integer scoreMinYoYCommittedSpend(Decimal spend) {
        if (spend == null) {
            return null;
        }
        if (spend < 5) {
            return 90;
        }
        if (spend <= 6.99) {
            return 100;
        }
        return 110;
    }

    /**
     * @description Scores the SFA Cap after Initial Term field.
     * @param cap String value (e.g., 'CPI + 5%', '', 'RPI + 10%', etc.)
     * @return Integer Score based on predefined mapping.
     */
    private static Integer scoreSfaCapAfterInitialTerm(String cap) {
        if (String.isBlank(cap)) {
            return null;
        }
        String val = cap.trim().toLowerCase();
        if (val == '') {
            return 90;
        }
        Set<String> score110 = new Set<String>{
            'cpi + 5%', 'cpi + 10%', 'rpi + 5%', 'rpi + 10%', '5%', '10%', 
            'greater of cpi or 5%', 'greater of rpi or 5%',
            'greater of cpi or 10%', 'greater of rpi or 10%', 'n/a (master terms apply)'
        };
        Set<String> score90 = new Set<String>{
            'cpi + 3%', 'greater of cpi or 3%', '3%', 'other'
        };
        if (score110.contains(val)) {
            return 110;
        }
        if (score90.contains(val)) {
            return 90;
        }
        return 100;
    }

    /**
     * @description Scores the SFA Term field.
     * @param term Picklist string value
     * @return Integer Score based on term value.
     */
    private static Integer scoreSfaTerm(String term) {
        if (String.isBlank(term)) {
            return null;
        }
        if (term == '1st Renewal Only') {
            return 110;
        }
        if (term == 'Thru 2nd Renewal') {
            return 110;
        }
        if (term == 'Thru 3rd Renewal') {
            return 90;
        }
        if (term == 'Perpetual') {
            return 90;
        }
        return 100;
    }

    /**
     * @description Scores the Future Pricing Commitment component.
     * @param hasCommitment Boolean indicating if there is a future pricing commitment.
     * @return Integer Score.
     */
    private static Integer scoreFuturePricing(Boolean hasCommitment) {
        if (hasCommitment == null) {
            return 100;
        }
        return hasCommitment ? 90 : 110;
    }

    /**
     * @description Scores the Product Development Obligation component.
     * @param hasObligation Boolean indicating if there is a product development obligation.
     * @return Integer Score.
     */
    private static Integer scoreProductDevelopmentObligation(Boolean hasObligation) {
        if (hasObligation == null) {
            return 100;
        }
        return hasObligation ? 90 : 110;
    }

    /**
     * @description Scores the Termination Clause component.
     * @param includesTermination Boolean indicating if the quote includes a termination clause.
     * @return Integer Score.
     */
    private static Integer scoreTerminationClause(Boolean includesTermination) {
        if (includesTermination == null) {
            return 110;
        }
        return includesTermination ? 90 : 110;
    }

    /**
     * @description Scores the Billing Frequency component.
     * @param frequency String value of the billing frequency.
     * @return Integer Score.
     */
    private static Integer scoreBillingFrequency(String frequency) {
        if (String.isBlank(frequency)) {
            return null;
        }
        String f = frequency.trim().toLowerCase();
        return (f == 'annual' || f == 'no software' || f == 'microsoft azure marketplace') ? 110 : 90;
    }

    /**
     * @description Scores the Payment Terms component (applicable only for EM4 & EM5 tiers).
     * @param terms String value of the payment terms.
     * @return Integer Score.
     */
    private static Integer scorePaymentTerms(String terms) {
        if (String.isBlank(terms)) {
            return null;
        }
        String term = terms.trim().toLowerCase();
        Set<String> betterThanNet30 = new Set<String>{
            'net 45','net 60','net 90','net 120'
        };
        if (term == 'net 30') {
            return 100;
        }
        if (betterThanNet30.contains(term)) {
            return 90;
        }
        return 110;
    }

    /**
     * @description Checks if the GTM Motion Tier is EM4 or EM5.
     * @param tier String value from Quote.GTM_Motion_Tier__c.
     * @return Boolean True if EM4 or EM5, False otherwise.
     */
    private static Boolean isEm4OrEm5(String tier) {
        if (String.isBlank(tier)) {
            return false;
        }
        String t = tier.trim().toUpperCase();
        return t == 'EM4' || t == 'EM5';
    }

    /**
     * @description Returns the minimum score among all evaluated criteria.
     * @param scores List<Integer> containing all calculated component scores.
     * @return Integer Minimum score or 100 if list is empty.
     */
    private static Integer getMinScore(List<Integer> scores) {
        if (scores.isEmpty()) {
            return 100;
        }
        Integer minVal = scores[0];
        for (Integer i : scores) {
            if (i < minVal) {
                minVal = i;
            }
        }
        return minVal;
    }

    /**
     * @description Wrapper class for calculated formula field values.
     */
    public class DealQualityFormulaFields {
        public Decimal initialTermDiscount { get; set; }
        public Decimal minYoYSpend { get; set; }

        public DealQualityFormulaFields() {
            this.initialTermDiscount = 0;
            this.minYoYSpend = 0;
        }
    }

    /**
     * @description Custom exception class for deal quality score calculation errors.
     */
    public class DealQualityScoreException extends Exception {
    }
}