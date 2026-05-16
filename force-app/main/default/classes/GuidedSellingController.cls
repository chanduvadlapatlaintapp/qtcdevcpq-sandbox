/**
 * @description Apex controller for the Guided Selling Lightning Web Component.
 *              Provides methods for retrieving products, creating quote lines, calculating deal quality scores,
 *              and managing quote contract terms. Handles product filtering based on Sub_Vertical__c,
 *              creates quote lines from cart data, and integrates with DealQualityScoreCalculator
 *              for score calculations.
 * @author Auto-generated
 */
public with sharing class GuidedSellingController {
    /**
     * @description Map of Sub_Vertical__c values to corresponding Product field names for filtering
     */
    private static Map<String, String> subVerticalToFieldMap = new Map<String, String>{
        'Legal' => 'Is_Legal__c',
        'Accounting' => 'Is_Accounting__c',
        'Consulting' => 'Is_Consulting__c',
        'Corporate' => 'Iss_Corporate__c',
        'Real Assets' => 'Is_Real_Assets__c',
        'IB&A' => 'Is_IB_A__c',
        'PCM' => 'Is_PCM__c',
        'Other' => 'Other__c'
    };

    /**
     * @description Retrieves active products filtered by the Quote's Sub_Vertical__c field.
     *              If a quoteId is provided, products are filtered based on the Sub_Vertical__c value
     *              using the subVerticalToFieldMap mapping. Products must be active and have a 
     *              Product_LineNew__r.Practice__c value.
     * @param quoteId The ID of the quote to determine Sub_Vertical__c filtering (optional)
     * @return List<Product2> List of active products matching the Sub_Vertical__c criteria, 
     *                        or all active products if no quoteId or Sub_Vertical__c mapping exists
     * @throws AuraHandledException If an error occurs while fetching products
     */
    @AuraEnabled(cacheable=true)
    public static List<Product2> getActiveProducts(String quoteId) {
        try {
            // Fetch Quote record to get Sub_Vertical__c
            String subVertical = null;
            if (String.isNotBlank(quoteId)) {
                List<SBQQ__Quote__c> quotes = [
                    SELECT Sub_Vertical__c 
                    FROM SBQQ__Quote__c 
                    WHERE Id = :quoteId 
                    LIMIT 1
                ];
                if (!quotes.isEmpty() && String.isNotBlank(quotes[0].Sub_Vertical__c)) {
                    subVertical = quotes[0].Sub_Vertical__c;
                }
            }

            // Get the product field name based on Sub_Vertical__c
            String productField = subVerticalToFieldMap.get(subVertical);
            
            // Query all active products with Product_LineNew__r.Practice__c
            // Also query the lookup field to ensure relationship exists
            List<Product2> allProducts = [
                SELECT Id, Name, ProductCode, Description, 
                       Product_LineNew__c, Product_LineNew__r.Practice__c,
                       Is_Legal__c, Is_Accounting__c, Is_Consulting__c,
                       Is_Real_Assets__c, Iss_Corporate__c, Is_IB_A__c, Is_PCM__c, Other__c
                FROM Product2
                WHERE IsActive = true and Product_LineNew__r.Practice__c != null
                ORDER BY Name
            ];
            
            // Filter products based on Sub_Vertical__c mapping
            if (String.isNotBlank(productField)) {
                List<Product2> filteredProducts = new List<Product2>();
                for (Product2 product : allProducts) {
                    // Use reflection to get field value dynamically
                    Object fieldValue = product.get(productField);
                    if (fieldValue != null && (String.valueOf(fieldValue) == 'Active')) {
                        filteredProducts.add(product);
                    }
                }
                return filteredProducts;
            }
            
            // If no Sub_Vertical__c or mapping not found, return all active products
            return allProducts;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching products: ' + e.getMessage());
        }
    }

    /**
     * @description Retrieves all quote lines associated with a given quote, ordered by creation date.
     * @param quoteId The ID of the quote to retrieve quote lines for
     * @return List<SBQQ__QuoteLine__c> List of quote lines, or empty list if quoteId is blank
     * @throws AuraHandledException If an error occurs while fetching quote lines
     */
    @AuraEnabled(cacheable=true)
    public static List<SBQQ__QuoteLine__c> getQuoteLines(String quoteId) {
        try {
            if (String.isBlank(quoteId)) {
                return new List<SBQQ__QuoteLine__c>();
            }

            return [
                SELECT Id, Name, SBQQ__Quantity__c, SBQQ__ListPrice__c, SBQQ__NetPrice__c,
                       SBQQ__Product__c, SBQQ__Product__r.Name, SBQQ__Product__r.ProductCode,
                       SBQQ__Quote__c, CreatedDate, Override_Sales_Price_Per_Month__c
                FROM SBQQ__QuoteLine__c
                WHERE SBQQ__Quote__c = :quoteId
                ORDER BY CreatedDate ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching quote lines: ' + e.getMessage());
        }
    }

    /**
     * @description Creates quote lines from cart items JSON. Each cart item can have multiple years,
     *              and a separate quote line is created for each year. The method validates the quote
     *              exists, parses the cart items, and inserts the quote lines with pricing information.
     * @param quoteId The ID of the quote to create quote lines for
     * @param cartItemsJson JSON string containing cart items with years, pricing, and quantities
     * @return QuoteLinesResult Wrapper containing success message and list of created quote line IDs
     * @throws AuraHandledException If quoteId is blank, quote not found, cart is empty, 
     *                              or no valid quote lines can be created
     */
    @AuraEnabled
    public static QuoteLinesResult createQuoteLines(String quoteId, String cartItemsJson) {
        try {
            if (String.isBlank(quoteId)) {
                throw new AuraHandledException('Quote ID is required');
            }

            // Verify quote exists
            List<SBQQ__Quote__c> quotes = [
                SELECT Id 
                FROM SBQQ__Quote__c 
                WHERE Id = :quoteId 
                LIMIT 1
            ];
            
            if (quotes.isEmpty()) {
                throw new AuraHandledException('Quote not found');
            }

            // Parse cart items JSON
            List<CartItemWrapper> cartItems = (List<CartItemWrapper>) JSON.deserialize(
                cartItemsJson, 
                List<CartItemWrapper>.class
            );

            if (cartItems == null || cartItems.isEmpty()) {
                throw new AuraHandledException('No cart items to create');
            }

            // Create quote lines
            List<SBQQ__QuoteLine__c> quoteLines = new List<SBQQ__QuoteLine__c>();
            
            for (CartItemWrapper cartItem : cartItems) {
                if (cartItem.years == null || cartItem.years.isEmpty()) {
                    continue;
                }

                // Create a quote line for each year
                for (YearWrapper year : cartItem.years) {
                    SBQQ__QuoteLine__c quoteLine = new SBQQ__QuoteLine__c();
                    quoteLine.SBQQ__Quote__c = quoteId;
                    quoteLine.SBQQ__Product__c = cartItem.Id;
                    quoteLine.SBQQ__Quantity__c = cartItem.quantity != null ? cartItem.quantity : 1;
                    quoteLine.SBQQ__ListPrice__c = String.isNotBlank(year.unitPrice) ? Decimal.valueOf(year.unitPrice) : 0;
                    quoteLine.SBQQ__NetPrice__c = String.isNotBlank(year.netPrice) ? Decimal.valueOf(year.netPrice) : 0;
                    quoteLine.SBQQ__Discount__c = year.discount != null ? year.discount : 0;
                    
                    // Set Override Sales Price Per Month - directly assign what user entered
                    if (year.overrideSalePricePerMonth != null) {
                        quoteLine.Override_Sales_Price_Per_Month__c = year.overrideSalePricePerMonth.setScale(2);
                    }
                    
                    // Add custom fields if needed
                    // quoteLine.Year_Number__c = year.yearNumber;
                    // quoteLine.Months__c = year.months;
                    // quoteLine.Start_Month__c = year.startMonth;
                    // quoteLine.End_Month__c = year.endMonth;
                    
                    quoteLines.add(quoteLine);
                }
            }

            if (quoteLines.isEmpty()) {
                throw new AuraHandledException('No valid quote lines to create');
            }

            // Insert quote lines
            insert quoteLines;

            // Collect created quote line IDs
            List<String> createdIds = new List<String>();
            for (SBQQ__QuoteLine__c line : quoteLines) {
                createdIds.add(line.Id);
            }

            // Return result with message and created IDs
            QuoteLinesResult result = new QuoteLinesResult();
            result.message = 'Successfully created ' + quoteLines.size() + ' quote line(s)';
            result.createdQuoteLineIds = createdIds;
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating quote lines: ' + e.getMessage());
        }
    }

    /**
     * @description Wrapper class for createQuoteLines result containing success message and created IDs
     */
    public class QuoteLinesResult {
        /** Success message describing the operation result */
        public String message;
        /** List of IDs for the quote lines that were created */
        public List<String> createdQuoteLineIds;
    }

    /**
     * @description Wrapper class for cart item JSON deserialization
     */
    public class CartItemWrapper {
        /** Product ID */
        public String Id;
        /** Product Name */
        public String Name;
        /** Quantity of the product */
        public Decimal quantity;
        /** List of years associated with this cart item */
        public List<YearWrapper> years;
    }

    /**
     * @description Wrapper class for year data within a cart item
     */
    public class YearWrapper {
        /** Year number (1, 2, 3, etc.) */
        public Integer yearNumber;
        /** Number of months in this year */
        public Integer months;
        /** Starting month number */
        public Integer startMonth;
        /** Ending month number */
        public Integer endMonth;
        /** Discount percentage */
        public Decimal discount;
        /** Override sales price per month */
        public Decimal overrideSalePricePerMonth;
        /** Unit price as string */
        public String unitPrice;
        /** Net price as string */
        public String netPrice;
        /** Total price as string */
        public String totalPrice;
        /** Whether this year has a promotion */
        public Boolean hasPromo;
        /** Promotion label text */
        public String promoLabel;
        /** Whether this year has sales VP rate */
        public Boolean hasSalesVpRate;
    }

    /**
     * @description Calculates the Deal Quality Score and breakdown for a quote based on cart data
     * @param quoteId The ID of the quote
     * @param quoteData JSON string containing quote field values
     * @return DealQualityScoreResult Wrapper containing the score and breakdown explanation
     */
    @AuraEnabled
    public static DealQualityScoreResult calculateDealQualityScoreWithBreakdown(String quoteId, String quoteData) {
        try {
            Integer score = calculateDealQualityScore(quoteId, quoteData);
            String breakdown = buildScoreBreakdown(quoteId, quoteData);
            return new DealQualityScoreResult(score, breakdown);
        } catch (Exception e) {
            throw new AuraHandledException('Error calculating deal quality score: ' + e.getMessage());
        }
    }

    /**
     * @description Calculates the Deal Quality Score for a quote based on cart data
     * @param quoteId The ID of the quote
     * @param quoteData JSON string containing quote field values
     * @return Integer The calculated Deal Quality Score
     */
    @AuraEnabled
    public static Integer calculateDealQualityScore(String quoteId, String quoteData) {
        try {
            if (String.isBlank(quoteId)) {
                throw new AuraHandledException('Quote ID is required');
            }

            // Fetch the quote record
            SBQQ__Quote__c quote = [
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

            // If quoteData is provided, calculate formula fields and score with calculated values
            if (String.isNotBlank(quoteData)) {
                Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(quoteData);
                
                // Update quote fields with provided values (for non-formula fields)
                updateQuoteFields(quote, dataMap);
                
                // Calculate formula fields using the new DealQualityScoreCalculator
                DealQualityScoreCalculator.DealQualityFormulaFields formulaFields = 
                    DealQualityScoreCalculator.calculateFormulaFields(dataMap);
                
                // Calculate score using the new calculator class
                return DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
                    quoteId,
                    formulaFields.initialTermDiscount,
                    formulaFields.minYoYSpend
                );
            }

            // Calculate the deal quality score using DealQualityScorer (no calculated fields provided)
            return DealQualityScorer.calculateCredit(quote);
        } catch (Exception e) {
            throw new AuraHandledException('Error calculating deal quality score: ' + e.getMessage());
        }
    }

    /**
     * @description Helper method to update quote fields from data map.
     * @param quote The quote record to update
     * @param dataMap Map containing field values
     */
    private static void updateQuoteFields(SBQQ__Quote__c quote, Map<String, Object> dataMap) {
        // Update formula field dependencies if provided
        if (dataMap.containsKey('Segment_Total_List_Unit_Price__c')) {
            quote.Segment_Total_List_Unit_Price__c = (Decimal) dataMap.get('Segment_Total_List_Unit_Price__c');
        }
        if (dataMap.containsKey('Segment_Total_Net_unit_Price__c')) {
            quote.Segment_Total_Net_unit_Price__c = (Decimal) dataMap.get('Segment_Total_Net_unit_Price__c');
        }
        if (dataMap.containsKey('First_Year_Software_Total__c')) {
            quote.First_Year_Software_Total__c = (Decimal) dataMap.get('First_Year_Software_Total__c');
        }
        if (dataMap.containsKey('Second_Year_Software_Total__c')) {
            quote.Second_Year_Software_Total__c = (Decimal) dataMap.get('Second_Year_Software_Total__c');
        }
        if (dataMap.containsKey('Third_Year_Software_Total__c')) {
            quote.Third_Year_Software_Total__c = (Decimal) dataMap.get('Third_Year_Software_Total__c');
        }
        if (dataMap.containsKey('Fourth_Year_Software_Total__c')) {
            quote.Fourth_Year_Software_Total__c = (Decimal) dataMap.get('Fourth_Year_Software_Total__c');
        }
        if (dataMap.containsKey('Fifth_Year_Software_Total__c')) {
            quote.Fifth_Year_Software_Total__c = (Decimal) dataMap.get('Fifth_Year_Software_Total__c');
        }
        if (dataMap.containsKey('Sixth_Year_Software_Total__c')) {
            quote.Sixth_Year_Software_Total__c = (Decimal) dataMap.get('Sixth_Year_Software_Total__c');
        }

        // Update direct fields if provided
        if (dataMap.containsKey('SFA_Cap_after_Initial_Term__c')) {
            quote.SFA_Cap_after_Initial_Term__c = (String) dataMap.get('SFA_Cap_after_Initial_Term__c');
        }
        if (dataMap.containsKey('SFA_Term__c')) {
            quote.SFA_Term__c = (String) dataMap.get('SFA_Term__c');
        }
        if (dataMap.containsKey('Future_Pricing_Commitment__c')) {
            quote.Future_Pricing_Commitment__c = (Boolean) dataMap.get('Future_Pricing_Commitment__c');
        }
        if (dataMap.containsKey('Product_Development_Obligation__c')) {
            quote.Product_Development_Obligation__c = (Boolean) dataMap.get('Product_Development_Obligation__c');
        }
        if (dataMap.containsKey('Includes_Termination_Clause__c')) {
            quote.Includes_Termination_Clause__c = (Boolean) dataMap.get('Includes_Termination_Clause__c');
        }
        if (dataMap.containsKey('SBQQ__BillingFrequency__c')) {
            quote.SBQQ__BillingFrequency__c = (String) dataMap.get('SBQQ__BillingFrequency__c');
        }
        if (dataMap.containsKey('Software_Payment_Terms__c')) {
            quote.Software_Payment_Terms__c = (String) dataMap.get('Software_Payment_Terms__c');
        }
        // Note: GTM_Motion_Tier__c is a formula field (from Account: SBQQ__Account__r.GTM_Motion_Tier__c)
        // It cannot be written to, so we use the value from the quote record which is automatically 
        // calculated from the Account when the quote is queried
    }

    /**
     * @description Builds a human-readable breakdown of the deal quality score
     * @param quoteId The ID of the quote
     * @param quoteData JSON string containing quote field values
     * @return String Breakdown explanation
     */
    private static String buildScoreBreakdown(String quoteId, String quoteData) {
        try {
            SBQQ__Quote__c quote = [
                SELECT Id, Initial_Term_Discount__c, Min_year_on_year_committed_spend__c,
                       SFA_Cap_after_Initial_Term__c, SFA_Term__c, Future_Pricing_Commitment__c,
                       Product_Development_Obligation__c, Includes_Termination_Clause__c,
                       SBQQ__BillingFrequency__c, Software_Payment_Terms__c, GTM_Motion_Tier__c
                FROM SBQQ__Quote__c
                WHERE Id = :quoteId
                LIMIT 1
            ];

            Decimal calculatedInitialTermDiscount = null;
            Decimal calculatedMinYoYSpend = null;
            
            if (String.isNotBlank(quoteData)) {
                Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(quoteData);
                updateQuoteFields(quote, dataMap);
                DealQualityScoreCalculator.DealQualityFormulaFields formulaFields = 
                    DealQualityScoreCalculator.calculateFormulaFields(dataMap);
                calculatedInitialTermDiscount = formulaFields.initialTermDiscount;
                calculatedMinYoYSpend = formulaFields.minYoYSpend;
            }

            List<String> breakdownItems = new List<String>();
            Integer finalScore;
            
            // Calculate score using calculated formula fields if available
            if (calculatedInitialTermDiscount != null && calculatedMinYoYSpend != null) {
                finalScore = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(
                    quoteId,
                    calculatedInitialTermDiscount,
                    calculatedMinYoYSpend
                );
            } else {
                finalScore = DealQualityScorer.calculateCredit(quote);
            }
            
            // Build breakdown based on scoring logic
            Decimal discount = calculatedInitialTermDiscount != null ? calculatedInitialTermDiscount : quote.Initial_Term_Discount__c;
            if (discount != null) {
                if (discount < -5) {
                    breakdownItems.add('Initial Term Discount: ' + discount.setScale(2) + '% (Score: 110 - Excellent)');
                } else if (discount >= -5 && discount <= 30) {
                    breakdownItems.add('Initial Term Discount: ' + discount.setScale(2) + '% (Score: 100 - Good)');
                } else {
                    breakdownItems.add('Initial Term Discount: ' + discount.setScale(2) + '% (Score: 90 - Needs Review)');
                }
            }

            Decimal spend = calculatedMinYoYSpend != null ? calculatedMinYoYSpend : quote.Min_year_on_year_committed_spend__c;
            if (spend != null) {
                if (spend < 5) {
                    breakdownItems.add('Min YoY Committed Spend: ' + spend.setScale(2) + '% (Score: 90 - Needs Review)');
                } else if (spend <= 6.99) {
                    breakdownItems.add('Min YoY Committed Spend: ' + spend.setScale(2) + '% (Score: 100 - Good)');
                } else {
                    breakdownItems.add('Min YoY Committed Spend: ' + spend.setScale(2) + '% (Score: 110 - Excellent)');
                }
            }

            if (String.isNotBlank(quote.SFA_Cap_after_Initial_Term__c)) {
                breakdownItems.add('SFA Cap: ' + quote.SFA_Cap_after_Initial_Term__c);
            }

            if (String.isNotBlank(quote.SFA_Term__c)) {
                breakdownItems.add('SFA Term: ' + quote.SFA_Term__c);
            }

            if (quote.Future_Pricing_Commitment__c != null) {
                breakdownItems.add('Future Pricing Commitment: ' + (quote.Future_Pricing_Commitment__c ? 'Yes (Score: 90)' : 'No (Score: 110)'));
            }

            if (quote.Product_Development_Obligation__c != null) {
                breakdownItems.add('Product Development Obligation: ' + (quote.Product_Development_Obligation__c ? 'Yes (Score: 90)' : 'No (Score: 110)'));
            }

            if (quote.Includes_Termination_Clause__c != null) {
                breakdownItems.add('Termination Clause: ' + (quote.Includes_Termination_Clause__c ? 'Yes (Score: 90)' : 'No (Score: 110)'));
            }

            if (String.isNotBlank(quote.SBQQ__BillingFrequency__c)) {
                breakdownItems.add('Billing Frequency: ' + quote.SBQQ__BillingFrequency__c);
            }

            if (String.isNotBlank(quote.Software_Payment_Terms__c)) {
                breakdownItems.add('Payment Terms: ' + quote.Software_Payment_Terms__c);
            }

            String breakdown = 'Final Score: ' + finalScore + ' (Lowest component score)\n\nComponent Breakdown:\n';
            breakdown += String.join(breakdownItems, '\n');
            
            return breakdown;
        } catch (Exception e) {
            return 'Unable to generate breakdown: ' + e.getMessage();
        }
    }

    /**
     * @description Updates the Quote's totalContractMonths and firstSegmentMonths fields
     * @param quoteId The ID of the quote to update
     * @param totalContractMonths The total contract months value
     * @param firstSegmentMonths The first segment months value
     */
    @AuraEnabled
    public static void updateQuoteMonths(String quoteId, Integer totalContractMonths, Integer firstSegmentMonths) {
        try {
            if (String.isBlank(quoteId)) {
                throw new AuraHandledException('Quote ID is required');
            }

            SBQQ__Quote__c quote = new SBQQ__Quote__c(Id = quoteId);
            
            if (totalContractMonths != null) {
                quote.SBQQ__SubscriptionTerm__c = totalContractMonths;
            }
            
            if (firstSegmentMonths != null) {
                quote.First_Segment_Months__c = firstSegmentMonths;
            }
            
            update quote;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating quote months: ' + e.getMessage());
        }
    }

    /**
     * @description Retrieves all quotes accessible by the currently logged-in user that have both
     *              an Account and an Opportunity. This respects Salesforce sharing rules and returns 
     *              quotes the user can view based on ownership, sharing rules, and role hierarchy.
     *              Includes relevant fields for display in a list view, such as Quote Name,
     *              Account Name, Opportunity Name and Stage, Created Date, Last Modified Date, and Quote Stage.
     *              Also includes a flag to indicate if the associated Opportunity is open.
     * @return List<QuoteWrapper> A list of QuoteWrapper objects containing quote details.
     */
    @AuraEnabled(cacheable=true)
    public static List<QuoteWrapper> getUserQuotes() {
        List<QuoteWrapper> userQuotes = new List<QuoteWrapper>();
        try {
            // Query quotes accessible to the current user (respects sharing rules)
            // Filter to only include quotes with both Account and Opportunity
            // Using 'with sharing' ensures sharing rules are enforced
            for (SBQQ__Quote__c quote : [
                SELECT Id, Name, SBQQ__Account__c, SBQQ__Account__r.Name, 
                       SBQQ__Opportunity2__c, SBQQ__Opportunity2__r.Name,
                       SBQQ__Opportunity2__r.StageName, SBQQ__Opportunity2__r.IsClosed,
                       SBQQ__Opportunity2__r.OP4I_Deal_Id__c,
                       CreatedDate, LastModifiedDate, Quote_Stage__c, Owner.Name,
                       OP4I_Deal_URL__c
                FROM SBQQ__Quote__c
                WHERE SBQQ__Account__c != null 
                  AND SBQQ__Opportunity2__c != null
                ORDER BY LastModifiedDate DESC
                LIMIT 1000 // Limit to prevent governor limits
            ]) {
                userQuotes.add(new QuoteWrapper(quote));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching user quotes: ' + e.getMessage());
            throw new AuraHandledException('Error fetching quotes: ' + e.getMessage());
        }
        return userQuotes;
    }

    /**
     * @description Wrapper class for Quote data to be displayed in the list view.
     */
    public class QuoteWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountName;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String opportunityStage;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public String quoteStage;
        @AuraEnabled public Boolean isOpportunityOpen;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String op4iDealUrl;
        @AuraEnabled public String op4iDealId;

        public QuoteWrapper(SBQQ__Quote__c quote) {
            this.id = quote.Id;
            // Use Name if available, otherwise generate a display name from Account and Opportunity
            if (String.isNotBlank(quote.Name)) {
                this.name = quote.Name;
            } else {
                String accountName = quote.SBQQ__Account__r?.Name;
                String oppName = quote.SBQQ__Opportunity2__r?.Name;
                if (String.isNotBlank(accountName) && String.isNotBlank(oppName)) {
                    this.name = accountName + ' - ' + oppName;
                } else if (String.isNotBlank(accountName)) {
                    this.name = accountName + ' Quote';
                } else {
                    String quoteIdStr = String.valueOf(quote.Id);
                    this.name = 'Quote ' + quoteIdStr.substring(0, 8);
                }
            }
            this.accountName = quote.SBQQ__Account__r?.Name;
            this.opportunityName = quote.SBQQ__Opportunity2__r?.Name;
            this.opportunityStage = quote.SBQQ__Opportunity2__r?.StageName;
            this.createdDate = quote.CreatedDate;
            this.lastModifiedDate = quote.LastModifiedDate;
            this.quoteStage = quote.Quote_Stage__c;
            this.isOpportunityOpen = (quote.SBQQ__Opportunity2__r != null && !quote.SBQQ__Opportunity2__r.IsClosed);
            this.ownerName = quote.Owner?.Name;
            // OP4I_Deal_URL__c is a HYPERLINK formula field
            // When queried, it returns the URL part of the HYPERLINK formula
            // Parse it to extract just the URL if needed
            String dealUrl = quote.OP4I_Deal_URL__c;
            if (String.isNotBlank(dealUrl)) {
                // If it contains a HYPERLINK format, extract the URL
                // HYPERLINK formula returns: "URL,DisplayText" or just "URL"
                if (dealUrl.contains(',')) {
                    this.op4iDealUrl = dealUrl.split(',')[0].trim();
                } else {
                    this.op4iDealUrl = dealUrl.trim();
                }
            } else {
                this.op4iDealUrl = null;
            }
            // Get the Deal ID from the Opportunity
            this.op4iDealId = quote.SBQQ__Opportunity2__r?.OP4I_Deal_Id__c;
        }
    }

    /**
     * @description Wrapper class for Deal Quality Score result with breakdown
     */
    public class DealQualityScoreResult {
        @AuraEnabled public Integer score;
        @AuraEnabled public String breakdown;

        public DealQualityScoreResult(Integer score, String breakdown) {
            this.score = score;
            this.breakdown = breakdown;
        }
    }
}