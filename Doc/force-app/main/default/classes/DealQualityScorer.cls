/**
 * @description : Calculates the Deal Quality Score for a given Quote based on key deal parameters
 *                such as discounting, committed spend, pricing commitments, and payment terms.
 *                The final Deal Quality Score is determined by the lowest score among all evaluated criteria.
 * @author      : Ratan Paul | 05-11-2025, BIZ-71699
 * @createdDate : 05-Nov-2025
 * @usage       : Invoked from Quote triggers or helper methods (e.g., updateOppDealQualityScore)
 *                to dynamically evaluate and update Deal Quality on related Opportunities.
 */
public class DealQualityScorer {
    /************************************************************************************************************
     *
     * Constants
     *
     ************************************************************************************************************/
    private static final Set < String > SFA_CAP_SCORE_110 = new Set < String > {
        'cpi + 5%',
        'cpi + 10%',
        'rpi + 5%',
        'rpi + 10%',
        '5%',
        '10%',
        'greater of cpi or 5%',
        'greater of rpi or 5%',
        'greater of cpi or 10%',
        'greater of rpi or 10%',
        'n/a (master terms apply)'
    };
    private static final Set < String > SFA_CAP_SCORE_90 = new Set < String > {
        '',
        'cpi + 3%',
        'greater of cpi or 3%',
        '3%',
        'other'
    };

    /****************************************************************************************************
     *
     * private collections
     *
     ************************************************************************************************************/
    @TestVisible
    private static Map < String, Object > scoreCache = new Map < String, Object > ();
    @TestVisible
    private static Integer discountScore,
    spendScore,
    sfaCapScore,
    sfaTermScore,
    futurePricingScore,
    pdoScore,
    termScore,
    freqScore,
    paymentScore;

    /************************************************************************************************************
     *
     * Public Methods
     *
     ************************************************************************************************************/

    // Toggle to emit a single consolidated Nebula log entry from calculateCredit
    public static Boolean enableLogging = true;

    /**
     * @description Evaluates individual deal components based on Quote fields, aggregates their scores,
     *              and returns the minimum (worst) score. Logic is tier-based for EM2–EM5.
     * @param quote SBQQ__Quote__c record whose deal quality needs to be assessed.
     * @return Integer Calculated Deal Quality Score (default 100 if no criteria apply).
     */
    public static Integer calculateCredit(SBQQ__Quote__c quote) {
        List < Integer > scores = collectScores(quote);
        Integer finalScore = scores.isEmpty() ? 100 : getMinScore(scores);

        scoreCache = new Map < String, Object > {
            'quoteId' => quote.Id,
            'segmentIndexMax' => quote.SegmentIndex_Max__c,
            'isOneYearDeal' => isOneYearDeal(quote.SegmentIndex_Max__c),
            'inputs' => new Map < String,
            Object > {
                'GTM_Motion_Tier__c' => quote.GTM_Motion_Tier__c,
                'Initial_Term_Discount__c' => quote.Initial_Term_Discount__c + '-' + discountScore,
                'Min_year_on_year_committed_spend__c' => quote.Min_year_on_year_committed_spend__c + '-' + spendScore,
                'SFA_Cap_after_Initial_Term__c' => quote.SFA_Cap_after_Initial_Term__c + '-' + sfaCapScore,
                'SFA_Term__c' => quote.SFA_Term__c + '-' + sfaTermScore,
                'Future_Pricing_Commitment__c' => quote.Future_Pricing_Commitment__c + '-' + futurePricingScore,
                'Product_Development_Obligation__c' => quote.Product_Development_Obligation__c + '-' + pdoScore,
                'Includes_Termination_Clause__c' => quote.Includes_Termination_Clause__c + '-' + termScore,
                'SBQQ__BillingFrequency__c' => quote.SBQQ__BillingFrequency__c + '-' + freqScore,
                'Software_Payment_Terms__c' => quote.Software_Payment_Terms__c + '-' + paymentScore
            },
            'final' => new Map < String,
            Object > {
                'minScore' => finalScore,
                'allScores' => scores
            }
        };

        // Emit a compact consolidated debug payload (components are evaluated in collectScores)
        emitDebug(quote.Id, scoreCache);

        return finalScore;
    }

    /************************************************************************************************************
     *
     * Private Helper Methods
     *
     ************************************************************************************************************/

    /**
     * @description Collects individual scores for each deal quality component based on Quote fields.
     *              For single-year deals (SegmentIndex_Max__c = 1), only discount %, payment terms, and billing frequency are considered.
     * @param quote SBQQ__Quote__c record to evaluate.
     * @return List<Integer> List of individual component scores.
     */
    private static List < Integer > collectScores(SBQQ__Quote__c quote) {
        List < Integer > scores = new List < Integer > ();
        Boolean isOneYearDeal = isOneYearDeal(quote.SegmentIndex_Max__c);

        // Discount % - always considered
        discountScore = scoreInitialTermDiscount(quote.Initial_Term_Discount__c);
        if (discountScore != null) {
            scores.add(discountScore);
        }

        // Billing Frequency - always considered
        freqScore = scoreBillingFrequency(quote.SBQQ__BillingFrequency__c);
        if (freqScore != null) {
            scores.add(freqScore);
        }

        // Payment Terms - always considered (for EM4/EM5)
        if (isEm4OrEm5(quote.GTM_Motion_Tier__c)) {
            paymentScore = scorePaymentTerms(quote.Software_Payment_Terms__c);
            if (paymentScore != null) {
                scores.add(paymentScore);
            }
        }

        // For single-year deals (SegmentIndex_Max__c = 1), skip the remaining criteria - BIZ-78616
        if (isOneYearDeal) {
            return scores;
        }

        // The following criteria are only considered for multi-year deals (SegmentIndex_Max__c > 1)
        spendScore = scoreMinYoYCommittedSpend(
            quote.Min_year_on_year_committed_spend__c
        );
        if (spendScore != null) {
            scores.add(spendScore);
        }

        sfaCapScore = scoreSfaCapAfterInitialTerm(
            quote.SFA_Cap_after_Initial_Term__c
        );
        if (sfaCapScore != null) {
            scores.add(sfaCapScore);
        }

        sfaTermScore = scoreSfaTerm(quote.SFA_Term__c);
        if (sfaTermScore != null) {
            scores.add(sfaTermScore);
        }

        futurePricingScore = scoreFuturePricing(quote.Future_Pricing_Commitment__c);
        scores.add(futurePricingScore);

        pdoScore = scoreProductDevelopmentObligation(
            quote.Product_Development_Obligation__c
        );
        scores.add(pdoScore);

        termScore = scoreTerminationClause(quote.Includes_Termination_Clause__c);
        scores.add(termScore);

        return scores;
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
     * @description Checks if the deal is a single-year deal based on segment index.
     * @param segmentIndexMax Decimal value of the maximum segment index.
     * @return Boolean True if SegmentIndex_Max__c = 1, False otherwise.
     */
    @TestVisible
    private static Boolean isOneYearDeal(Decimal segmentIndexMax) {
        return segmentIndexMax != null && segmentIndexMax == 1;
    }

    /**
     * @description Scores the Initial Term Discount component.
     * @param discount Decimal value of the initial term discount percentage.
     * @return Integer Score based on discount thresholds.
     *         < -5% discount (customer paying > 105% of list)
     *         between -5% and 30% (inclusive)
     *         - >30% discount → 90
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
     *              The raw decimal spend is rounded to the nearest integer before comparison (BIZ-82581),
     *              so 4.99 rounds to 5 and qualifies for the 100 bucket.
     * @param spend Decimal value of the minimum year-on-year committed spend.
     * @return Integer Score based on spend thresholds.
     *         - <5% → 90
     *         - 5–6% → 100
     *         - ≥7% → 110
     */
    @TestVisible
    private static Integer scoreMinYoYCommittedSpend(Decimal spend) {
        if (spend == null) {
            return null;
        }
        Long roundedSpend = Math.round((Double)spend);
        if (roundedSpend < 5) {
            return 90;
        }
        if (roundedSpend <= 6) {
            return 100;
        }
        return 110;
    }

    /**
     * @description Scores the SFA Cap after Initial Term field based on CPI/RPI rules.
     * @param cap String value (e.g., 'CPI + 5%', '', 'RPI + 10%', etc.)
     * @return Integer Score based on predefined mapping:
     *         - 110 → CPI + 5%, CPI + 10%, RPI + 5%, RPI + 10%, 5%, 10%, Greater of CPI/RPI or 5%
     *         - 90  → '', 3%, Greater of CPI or 10%, Other
     *         - 100 → Any other value (neutral)
     */
    private static Integer scoreSfaCapAfterInitialTerm(String cap) {
        if (String.isBlank(cap)) {
            return null;
        }
        String val = cap.trim().toLowerCase();
        if (val == '') {
            return 90;
        }
        if (SFA_CAP_SCORE_110.contains(val)) {
            return 110;
        }
        if (SFA_CAP_SCORE_90.contains(val)) {
            return 90;
        }

        return 100;
    }

    /**
     * @description Scores the SFA Term (SFA Cap Duration) based on restricted picklist values.
     * @param term Picklist string: '1st Renewal Only', 'Thru 2nd Renewal', 'Thru 3rd Renewal', 'Perpetual'.
     * @return Integer Score:
     *         - '1st Renewal Only' → 110
     *         - 'Thru 2nd Renewal' → 110
     *         - 'Thru 3rd Renewal' → 90
     *         - 'Perpetual' → 90
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
     * @return Integer Score:
     *         - Any commitments → 90
     *         - No Commitments → 110
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
     * @return Integer Score:
     *         - Has obligation → 90
     *         - No obligation → 110
     */
    private static Integer scoreProductDevelopmentObligation(
        Boolean hasObligation
    ) {
        if (hasObligation == null) {
            return 100;
        }
        return hasObligation ? 90 : 110;
    }

    /**
     * @description Scores the Termination Clause component.
     * @param includesTermination Boolean indicating if the quote includes a termination clause.
     * @return Integer Score:
     *         - Includes clause → 90
     *         - Does not include → 110
     */
    private static Integer scoreTerminationClause(Boolean includesTermination) {
        if (includesTermination == null) {
            return 110;
        }

        return includesTermination ? 90 : 110;
    }

    /**
     * @description Scores the Billing Frequency component.
     * @param frequency String value of the billing frequency (e.g., Annual, Non Standard).
     * @return Integer Score:
     *         - Annual, No Software, Microsoft Azure Marketplace → 110
     *         - Non Standard → 90
     */
    private static Integer scoreBillingFrequency(String frequency) {
        if (String.isBlank(frequency)) {
            return null;
        }
        String f = frequency.trim().toLowerCase();
        return (f == 'annual' ||
                f == 'no software' ||
                f == 'microsoft azure marketplace') ?
            110 :
            90;
    }

    /**
     * @description Scores the Payment Terms component (applicable only for EM4 & EM5 tiers).
     * @param terms String value of the payment terms (e.g., Net 30, Net 60, Net 7, Advance, etc.)
     * @return Integer Score:
     *         - Net 30 or less (Net 7, Net 30, etc.) → 110
     *         - Net 60 or greater than Net 30 (Net 45, Net 60, etc.) → 90
     *         - Other / Unknown → 100
     */
    private static Integer scorePaymentTerms(String terms) {
        if (String.isBlank(terms)) {
            return null;
        }
        String term = terms.trim().toLowerCase();

        // Extract number from "net X" format
        // Handle both "net 30" and "net30" formats
        if (term.startsWith('net')) {
            // Remove "net" prefix and any whitespace
            String numberPart = term.substring(3).trim();
            // Extract digits from the remaining string
            Pattern digitPattern = Pattern.compile('(\\d+)');
            Matcher matcher = digitPattern.matcher(numberPart);

            if (matcher.find()) {
                Integer days = Integer.valueOf(matcher.group(1));
                // Net 30 or less = 110, greater than Net 30 = 90
                return days <= 30 ? 110 : 90;
            }
        }
        if (term == 'other') {
            return 90;
        }
        // For non-net terms (Advance, Prepaid, etc.), default to 110
        return 110;
    }

    /**
     * @description Returns the minimum score among all evaluated criteria.
     * @param scores List<Integer> containing all calculated component scores.
     * @return Integer Minimum score or 100 if list is empty.
     */
    private static Integer getMinScore(List < Integer > scores) {
        if (scores.isEmpty()) {
            return 100;
        }
        Integer minVal = scores[0];
        for (Integer i: scores) {
            if (i < minVal) {
                minVal = i;
            }
        }
        return minVal;
    }

    /**
     * @description Single static hook to log once using Nebula when enabled.
     * @param quoteId Id of the Quote record being scored.
     * @param payload Map<String, Object> containing log entry details.
     */
    private static void emitDebug(Id quoteId, Map < String, Object > payload) {
        if (!enableLogging || payload == null) {
            return;
        }
        String json = JSON.serialize(payload);
        // Set record ID and tag for Nebula logging using chainable methods
        Nebula.Logger.debug(
            'Deal Quality Score log entry using Nebula Logger with logging level == DEBUG ' +
            json
        )
        .setRecordId(quoteId)
        .addTag('DealQualityScorer');
        Nebula.Logger.saveLog();
    }
}