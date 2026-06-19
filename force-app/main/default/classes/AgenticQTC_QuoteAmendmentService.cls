/**
 * @description Service layer for CPQ amendment quote operations including creation,
 *              line retrieval, quantity/ACV updates, and price calculation.
 *              Supports a dual-path approach: direct SOQL/DML (default) or CPQ
 *              ServiceRouter APIs, controlled via AgenticQTC_Config__mdt.
 *              When CPQ API mode is enabled and a call fails, the service automatically
 *              falls back to the DML path.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_QuoteAmendmentService {

    private static final String STATUS_DRAFT = 'Draft';
    private static final String TYPE_AMENDMENT = 'Amendment';
    private static final String STAGE_QUALIFY = 'Qualify';
    private static final String DEAL_TYPE_ADD_ON = 'Add-On';
    private static final String ERR_CONTRACT_REQUIRED = 'Contract ID is required';
    private static final String ERR_QUOTE_REQUIRED = 'Quote ID is required';
    private static final String ERR_QUOTE_LINE_REQUIRED = 'Quote ID and Quote Line ID are required';

    /**
     * @description Retrieves an existing draft amendment quote for a contract or creates
     *              a new one. Uses CPQ ContractAmender API if configured, with DML fallback.
     * @param contractId The Contract record Id
     * @return QuoteInfo DTO representing the amendment quote
     */
    @AuraEnabled
    public static QuoteInfo getOrCreateAmendmentQuote(String contractId) {
        if (String.isBlank(contractId)) {
            throw new AuraHandledException(ERR_CONTRACT_REQUIRED);
        }

        List<SBQQ__Quote__c> existingQuotes = [
            SELECT Id, Name, SBQQ__Status__c, SBQQ__StartDate__c,
                   SBQQ__Account__c, SBQQ__MasterContract__c,
                   SBQQ__Opportunity2__c,
                   Invoicing_Contact__r.Name, Invoicing_Contact__r.Email,
                   Software_Delivery_Contact__r.Name, Software_Delivery_Contact__r.Email
            FROM SBQQ__Quote__c
            WHERE SBQQ__MasterContract__c = :contractId
            AND SBQQ__Status__c = :STATUS_DRAFT
            AND SBQQ__Type__c = :TYPE_AMENDMENT
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!existingQuotes.isEmpty()) {
            return buildQuoteInfo(existingQuotes[0]);
        }

        try {
            return createAmendmentViaCpqApi(contractId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CPQ API amendment failed: ' + e.getMessage());
            throw new AuraHandledException('CPQ API failed — amendment quote could not be created. ' + e.getMessage());
        }
        // return createAmendmentManually(contractId);
    }

    /**
     * @description Creates an amendment quote using the CPQ ServiceRouter ContractAmender API.
     * @param contractId The Contract record Id
     * @return QuoteInfo DTO
     */
    private static QuoteInfo createAmendmentViaCpqApi(String contractId) {
        String quoteJson = SBQQ.ServiceRouter.load('SBQQ.ContractManipulationAPI.ContractAmender', contractId, null);
        Map<String, Object> model = (Map<String, Object>) JSON.deserializeUntyped(quoteJson);
        // VK - ContractAmender nests the quote record under 'record'; fall back to top-level 'Id' for older CPQ versions
        Map<String, Object> quoteRecord = (Map<String, Object>) model.get('record'); // VK
        String quoteId = quoteRecord != null ? getString(quoteRecord, 'Id') : null; // VK
        if (String.isBlank(quoteId)) {
            quoteId = getString(model, 'Id'); // VK
        }
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('CPQ ContractAmender returned no quote Id');
        }
        SBQQ__Quote__c q = [
            SELECT Id, Name, SBQQ__Status__c, SBQQ__StartDate__c,
                   SBQQ__Account__c, SBQQ__MasterContract__c,
                   SBQQ__Opportunity2__c,
                   Invoicing_Contact__r.Name, Invoicing_Contact__r.Email,
                   Software_Delivery_Contact__r.Name, Software_Delivery_Contact__r.Email
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        stampCreatedBySimplifiedQuoting(q.Id);
        return buildQuoteInfo(q);
    }

    /**
     * @description Creates an amendment quote using direct DML — builds Opportunity,
     *              Quote, and QuoteLines from the contract's subscriptions.
     * @param contractId The Contract record Id
     * @return QuoteInfo DTO
     */
    @testVisible
    private static QuoteInfo createAmendmentManually(String contractId) {
        Contract con = [
            SELECT Id, ContractNumber, AccountId, StartDate, EndDate,
                   ContractTerm, SBQQ__AmendmentPricebookId__c,
                   Account.Name
            FROM Contract WHERE Id = :contractId WITH SECURITY_ENFORCED LIMIT 1
        ];

        Opportunity opp = new Opportunity(
            AccountId = con.AccountId,
            Name = TYPE_AMENDMENT + ' - ' + con.ContractNumber + ' - ' + con.Account.Name,
            StageName = STAGE_QUALIFY,
            CloseDate = Date.today().addDays(30),
            Type = TYPE_AMENDMENT,
            SBQQ__AmendedContract__c = contractId,
            Pricebook2Id = con.SBQQ__AmendmentPricebookId__c,
            Created_by_Simplified_Quoting__c = true
        );
        insert opp;

        Date amendStart = Date.today();
        Date contractEnd = con.EndDate;
        if (contractEnd == null && con.StartDate != null && con.ContractTerm != null) {
            contractEnd = con.StartDate.addMonths(con.ContractTerm);
        }

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = con.AccountId,
            SBQQ__MasterContract__c = contractId,
            SBQQ__Type__c = TYPE_AMENDMENT,
            SBQQ__Status__c = STATUS_DRAFT,
            SBQQ__StartDate__c = amendStart,
            SBQQ__EndDate__c = contractEnd,
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Primary__c = true,
            SBQQ__PricebookId__c = con.SBQQ__AmendmentPricebookId__c
        );
        insert quote;

        opp.SBQQ__PrimaryQuote__c = quote.Id;
        update opp;

        List<SBQQ__Subscription__c> subs = [
            SELECT Id, SBQQ__Product__c, SBQQ__ProductName__c,
                   SBQQ__Quantity__c, SBQQ__ListPrice__c, SBQQ__NetPrice__c,
                   SBQQ__SubscriptionStartDate__c, SBQQ__SubscriptionEndDate__c,
                   SBQQ__Product__r.ProductCode
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c = :contractId
            WITH SECURITY_ENFORCED
            ORDER BY SBQQ__ProductName__c
            LIMIT 50000
        ];

        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();
        Integer lineNum = 1;
        for (SBQQ__Subscription__c sub : subs) {
            Decimal qty = sub.SBQQ__Quantity__c != null ? sub.SBQQ__Quantity__c : 0;
            Decimal price = sub.SBQQ__ListPrice__c != null ? sub.SBQQ__ListPrice__c : 0;
            lines.add(new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id,
                SBQQ__Product__c = sub.SBQQ__Product__c,
                SBQQ__Quantity__c = qty,
                SBQQ__PriorQuantity__c = qty,
                SBQQ__ListPrice__c = price,
                SBQQ__NetPrice__c = qty * price,
                SBQQ__CustomerPrice__c = price,
                SBQQ__Number__c = lineNum++,
                SBQQ__UpgradedSubscription__c = sub.Id,
                SBQQ__StartDate__c = amendStart,
                SBQQ__EndDate__c = sub.SBQQ__SubscriptionEndDate__c != null
                    ? sub.SBQQ__SubscriptionEndDate__c : contractEnd
            ));
        }
        if (!lines.isEmpty()) {
            insert lines;
        }

        SBQQ__Quote__c newQuote = [
            SELECT Id, Name, SBQQ__Status__c, SBQQ__StartDate__c,
                   SBQQ__Account__c, SBQQ__MasterContract__c,
                   SBQQ__Opportunity2__c,
                   Invoicing_Contact__r.Name, Invoicing_Contact__r.Email,
                   Software_Delivery_Contact__r.Name, Software_Delivery_Contact__r.Email
            FROM SBQQ__Quote__c WHERE Id = :quote.Id WITH SECURITY_ENFORCED LIMIT 1
        ];
        return buildQuoteInfo(newQuote);
    }

    /**
     * @description Retrieves all quote lines for a given quote.
     *              Uses CPQ QuoteReader API if configured, with DML fallback.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of QuoteLineInfo DTOs
     */
    // @AuraEnabled // VK - moved to AgenticQTC_AmendContractController
    public static List<QuoteLineInfo> getQuoteLines(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        return getQuoteLinesViaCpqApi(quoteId); // VK - always use CPQ API
        // VK - DML fallback commented out
        // if (AgenticQTC_ConfigService.useCpqApis()) {
        //     try {
        //         return getQuoteLinesViaCpqApi(quoteId);
        //     } catch (Exception e) {
        //         System.debug(LoggingLevel.WARN, 'CPQ QuoteReader failed, falling back to DML: ' + e.getMessage());
        //     }
        // }
        // return getQuoteLinesViaDml(quoteId);
    }

    /**
     * @description Retrieves quote lines via the CPQ QuoteReader ServiceRouter API.
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of QuoteLineInfo DTOs parsed from the CPQ JSON model
     */
    private static List<QuoteLineInfo> getQuoteLinesViaCpqApi(String quoteId) {
        String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
        Map<String, Object> model = (Map<String, Object>) JSON.deserializeUntyped(quoteJson);
        return parseLineItems(model);
    }

    /**
     * @description Retrieves quote lines via direct SOQL (DML path fallback).
     * @param quoteId The SBQQ__Quote__c record Id
     * @return List of QuoteLineInfo DTOs built from SObject records
     */
    private static List<QuoteLineInfo> getQuoteLinesViaDml(String quoteId) {
        // If Per_Integrations__c lives on Product2 in your org instead of directly
        // on SBQQ__QuoteLine__c, change the SELECT token to:
        //     SBQQ__Product__r.Per_Integrations__c
        // and update buildQuoteLineInfoFromRecord() to read it from that path.
        List<SBQQ__QuoteLine__c> qLines = [
            SELECT Id, SBQQ__Product__c, SBQQ__ProductName__c, SBQQ__ProductCode__c,
                   SBQQ__Quantity__c, SBQQ__PriorQuantity__c, SBQQ__NetPrice__c, SBQQ__NetTotal__c,
                   SBQQ__ListPrice__c, SBQQ__CustomerPrice__c, SBQQ__Discount__c,
                   SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c, SBQQ__SegmentLabel__c,
                   SBQQ__StartDate__c, SBQQ__EndDate__c, ACV__c, ACV_Change__c,
                   SBQQ__ChargeType__c, SBQQ__Number__c, Customer_Sale_Price_Per_Month__c,
                   Per_Integrations__c, SBQQ__Bundle__c, CPQ_Option_Type__c,
                   SBQQ__RequiredBy__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY SBQQ__Number__c, SBQQ__ProductName__c
            LIMIT 50000
        ];

        List<QuoteLineInfo> results = new List<QuoteLineInfo>();
        for (SBQQ__QuoteLine__c ql : qLines) {
            results.add(buildQuoteLineInfoFromRecord(ql));
        }
        return results;
    }

    /**
     * @description Updates the quantity on a single quote line and recalculates NetPrice.
     *              Uses CPQ API if configured, with DML fallback.
     * @param quoteId The parent quote Id
     * @param quoteLineId The quote line Id to update
     * @param newQuantity The new quantity value
     * @return List of refreshed QuoteLineInfo DTOs
     */
    // @AuraEnabled // VK - not called directly from LWC; controller has its own updateQuoteLineQuantity
    public static List<QuoteLineInfo> updateQuoteLineQuantity(String quoteId, String quoteLineId, Decimal newQuantity) {
        if (String.isBlank(quoteId) || String.isBlank(quoteLineId)) {
            throw new AuraHandledException(ERR_QUOTE_LINE_REQUIRED);
        }

        return updateQuoteLineQuantityViaCpqApi(quoteId, quoteLineId, newQuantity); // VK - CPQ API only
        // VK - DML fallback commented out
        // if (AgenticQTC_ConfigService.useCpqApis()) {
        //     try {
        //         return updateQuoteLineQuantityViaCpqApi(quoteId, quoteLineId, newQuantity);
        //     } catch (Exception e) {
        //         System.debug(LoggingLevel.WARN, 'CPQ update qty failed, falling back to DML: ' + e.getMessage());
        //     }
        // }
        // return updateQuoteLineQuantityViaDml(quoteId, quoteLineId, newQuantity);
    }

    /**
     * @description Updates quantity via the CPQ QuoteReader/QuoteSaver APIs.
     * @param quoteId The parent quote Id
     * @param quoteLineId The specific line to update
     * @param newQuantity The new quantity value
     * @return List of refreshed QuoteLineInfo DTOs
     */
    private static List<QuoteLineInfo> updateQuoteLineQuantityViaCpqApi(String quoteId, String quoteLineId, Decimal newQuantity) {
        String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
        Map<String, Object> model = (Map<String, Object>) JSON.deserializeUntyped(quoteJson);
        List<Object> lineItems = (List<Object>) model.get('lineItems');
        if (lineItems != null) {
            for (Object item : lineItems) {
                Map<String, Object> li = (Map<String, Object>) item;
                Map<String, Object> rec = (Map<String, Object>) li.get('record');
                if (getString(rec, 'Id') == quoteLineId) {
                    rec.put('SBQQ__Quantity__c', newQuantity);
                    break;
                }
            }
        }
        String savedJson = SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', JSON.serialize(model));
        Map<String, Object> savedModel = (Map<String, Object>) JSON.deserializeUntyped(savedJson);
        return parseLineItems(savedModel);
    }

    /**
     * @description Updates quantity via direct DML and recalculates NetPrice.
     * @param quoteId The parent quote Id
     * @param quoteLineId The specific line to update
     * @param newQuantity The new quantity value
     * @return List of refreshed QuoteLineInfo DTOs
     */
    @testVisible
    private static List<QuoteLineInfo> updateQuoteLineQuantityViaDml(String quoteId, String quoteLineId, Decimal newQuantity) {
        SBQQ__QuoteLine__c existing = [
            SELECT Id, SBQQ__ListPrice__c FROM SBQQ__QuoteLine__c
            WHERE Id = :quoteLineId WITH SECURITY_ENFORCED LIMIT 1
        ];
        Decimal price = existing.SBQQ__ListPrice__c != null ? existing.SBQQ__ListPrice__c : 0;
        Decimal qty = newQuantity != null ? newQuantity : 0;

        SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
            Id = quoteLineId,
            SBQQ__Quantity__c = qty,
            SBQQ__NetPrice__c = qty * price,
            SBQQ__CustomerPrice__c = price
        );
        update ql;

        return getQuoteLinesViaDml(quoteId);
    }

    /**
     * @description Updates the ACV Change value on a single quote line.
     *              Uses CPQ API if configured, with DML fallback.
     * @param quoteId The parent quote Id
     * @param quoteLineId The quote line Id to update
     * @param acvChange The new ACV Change value
     * @return List of refreshed QuoteLineInfo DTOs
     */
    // @AuraEnabled // VK - moved to AgenticQTC_AmendContractController
    public static List<QuoteLineInfo> updateQuoteLineAcvChange(String quoteId, String quoteLineId, Decimal acvChange) {
        if (String.isBlank(quoteId) || String.isBlank(quoteLineId)) {
            throw new AuraHandledException(ERR_QUOTE_LINE_REQUIRED);
        }

        SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
            Id = quoteLineId,
            ACV_Change__c = acvChange
        );
        update ql;

        return getQuoteLines(quoteId);
    }

    /**
     * @description Updates quantity for an MDQ segment. When applyToAllSegments is true,
     *              all segments sharing the same segmentKey are updated to the same quantity.
     *              Uses CPQ API if configured, with DML fallback.
     * @param quoteId The parent quote Id
     * @param quoteLineId The specific segment line to update
     * @param newQuantity The new quantity value
     * @param segmentKey The SBQQ__SegmentKey__c shared by all segments of this MDQ product
     * @param applyToAllSegments If true, updates all segments with the same segmentKey
     * @return List of refreshed QuoteLineInfo DTOs
     */
    // @AuraEnabled // VK - not called directly from LWC; controller has its own updateMdqSegmentQuantity
    public static List<QuoteLineInfo> updateMdqSegmentQuantity(
            String quoteId, String quoteLineId, Decimal newQuantity,
            String segmentKey, Boolean applyToAllSegments) {
        if (String.isBlank(quoteId) || String.isBlank(quoteLineId)) {
            throw new AuraHandledException(ERR_QUOTE_LINE_REQUIRED);
        }

        if (applyToAllSegments == true && String.isNotBlank(segmentKey)) {
            return updateAllMdqSegmentsViaCpqApi(quoteId, segmentKey, newQuantity); // VK - CPQ API only
            // VK - DML fallback commented out
            // if (AgenticQTC_ConfigService.useCpqApis()) {
            //     try {
            //         return updateAllMdqSegmentsViaCpqApi(quoteId, segmentKey, newQuantity);
            //     } catch (Exception e) {
            //         System.debug(LoggingLevel.WARN, 'CPQ MDQ bulk update failed, falling back to DML: ' + e.getMessage());
            //     }
            // }
            // return updateAllMdqSegmentsViaDml(quoteId, segmentKey, newQuantity);
        }

        return updateQuoteLineQuantity(quoteId, quoteLineId, newQuantity);
    }

    private static List<QuoteLineInfo> updateAllMdqSegmentsViaCpqApi(String quoteId, String segmentKey, Decimal newQuantity) {
        String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
        Map<String, Object> model = (Map<String, Object>) JSON.deserializeUntyped(quoteJson);
        List<Object> lineItems = (List<Object>) model.get('lineItems');
        if (lineItems != null) {
            for (Object item : lineItems) {
                Map<String, Object> li = (Map<String, Object>) item;
                Map<String, Object> rec = (Map<String, Object>) li.get('record');
                if (segmentKey.equals(getString(rec, 'SBQQ__SegmentKey__c'))) {
                    rec.put('SBQQ__Quantity__c', newQuantity);
                }
            }
        }
        String savedJson = SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', JSON.serialize(model));
        Map<String, Object> savedModel = (Map<String, Object>) JSON.deserializeUntyped(savedJson);
        return parseLineItems(savedModel);
    }
    
    @testVisible
    private static List<QuoteLineInfo> updateAllMdqSegmentsViaDml(String quoteId, String segmentKey, Decimal newQuantity) {
        List<SBQQ__QuoteLine__c> segmentLines = [
            SELECT Id, SBQQ__ListPrice__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId AND SBQQ__SegmentKey__c = :segmentKey
            WITH SECURITY_ENFORCED
            LIMIT 50000
        ];

        List<SBQQ__QuoteLine__c> toUpdate = new List<SBQQ__QuoteLine__c>();
        Decimal qty = newQuantity != null ? newQuantity : 0;
        for (SBQQ__QuoteLine__c seg : segmentLines) {
            Decimal price = seg.SBQQ__ListPrice__c != null ? seg.SBQQ__ListPrice__c : 0;
            toUpdate.add(new SBQQ__QuoteLine__c(
                Id = seg.Id,
                SBQQ__Quantity__c = qty,
                SBQQ__NetPrice__c = qty * price,
                SBQQ__CustomerPrice__c = price
            ));
        }
        update toUpdate;

        return getQuoteLinesViaDml(quoteId);
    }

    /**
     * @description Applies a discount to a quote line. Supports two modes:
     *              - Percentage discount: pass discountPercent (e.g. 50 for 50% off)
     *              - Flat per-unit amount: pass discountAmount (e.g. 20 for $20 off per seat)
     *              If both are provided, percentage takes precedence.
     *              Recalculates SBQQ__NetPrice__c and SBQQ__CustomerPrice__c after applying.
     * @param quoteId The parent quote Id
     * @param quoteLineId The quote line Id to update
     * @param discountPercent Percentage discount (0-100), or null to use flat amount
     * @param discountAmount Per-unit dollar discount, or null to use percentage
     * @return List of refreshed QuoteLineInfo DTOs
     */
    @AuraEnabled
    public static List<QuoteLineInfo> updateQuoteLineDiscount(
            String quoteId, String quoteLineId,
            Decimal discountPercent, Decimal discountAmount) {
        if (String.isBlank(quoteId) || String.isBlank(quoteLineId)) {
            throw new AuraHandledException(ERR_QUOTE_LINE_REQUIRED);
        }

        SBQQ__QuoteLine__c existing = [
            SELECT Id, SBQQ__ListPrice__c, SBQQ__Quantity__c
            FROM SBQQ__QuoteLine__c WHERE Id = :quoteLineId WITH SECURITY_ENFORCED LIMIT 1
        ];
        Decimal listPrice = existing.SBQQ__ListPrice__c != null ? existing.SBQQ__ListPrice__c : 0;
        Decimal qty = existing.SBQQ__Quantity__c != null ? existing.SBQQ__Quantity__c : 0;

        Decimal effectivePercent = 0;
        if (discountPercent != null) {
            effectivePercent = discountPercent;
        } else if (discountAmount != null && listPrice > 0) {
            effectivePercent = (discountAmount / listPrice) * 100;
        }

        Decimal customerPrice = listPrice * (1 - effectivePercent / 100);
        Decimal netPrice = customerPrice * qty;

        SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
            Id = quoteLineId,
            SBQQ__Discount__c = effectivePercent,
            SBQQ__CustomerPrice__c = customerPrice,
            SBQQ__NetPrice__c = netPrice
        );
        update ql;

        return getQuoteLinesViaDml(quoteId);
    }

    /**
     * @description Calculates quote line pricing for all lines on a quote.
     *              Uses CPQ QuoteCalculator API if configured, with DML fallback.
     * @param quoteId The SBQQ__Quote__c record Id
     */
    // @AuraEnabled // VK - moved to AgenticQTC_AmendContractController
    public static void calculateQuote(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        calculateQuoteViaCpqApi(quoteId); // VK - CPQ API only
        // VK - DML fallback commented out
        // if (AgenticQTC_ConfigService.useCpqApis()) {
        //     try {
        //         calculateQuoteViaCpqApi(quoteId);
        //         return;
        //     } catch (Exception e) {
        //         System.debug(LoggingLevel.WARN, 'CPQ Calculator failed, falling back to DML: ' + e.getMessage());
        //     }
        // }
        // calculateQuoteViaDml(quoteId);
    }

    /**
     * @description Calculates quote prices via the CPQ QuoteCalculator API.
     * @param quoteId The SBQQ__Quote__c record Id
     */
    @testVisible
    private static void calculateQuoteViaCpqApi(String quoteId) {
        String quoteJson = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
        SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', quoteId, quoteJson);
    }

    /**
     * @description Calculates quote prices via direct DML (qty * listPrice).
     * @param quoteId The SBQQ__Quote__c record Id
     */
    @testVisible
    private static void calculateQuoteViaDml(String quoteId) {
        List<SBQQ__QuoteLine__c> lines = [
            SELECT Id, SBQQ__Quantity__c, SBQQ__ListPrice__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 50000
        ];
        List<SBQQ__QuoteLine__c> toUpdate = new List<SBQQ__QuoteLine__c>();
        for (SBQQ__QuoteLine__c ql : lines) {
            Decimal qty = ql.SBQQ__Quantity__c != null ? ql.SBQQ__Quantity__c : 0;
            Decimal price = ql.SBQQ__ListPrice__c != null ? ql.SBQQ__ListPrice__c : 0;
            toUpdate.add(new SBQQ__QuoteLine__c(
                Id = ql.Id,
                SBQQ__NetPrice__c = qty * price,
                SBQQ__CustomerPrice__c = price
            ));
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Updates the start date on an amendment quote.
     * @param quoteId The SBQQ__Quote__c record Id
     * @param startDate The new start date
     */
    // @AuraEnabled // VK - moved to AgenticQTC_AmendContractController
    public static void updateQuoteStartDate(String quoteId, Date startDate) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }

        SBQQ__Quote__c q = new SBQQ__Quote__c(
            Id = quoteId,
            SBQQ__StartDate__c = startDate
        );
        update q;
    }

    // ─── CPQ JSON Helpers ───────────────────────────────────────────────

    /**
     * @description Parses the CPQ JSON model's lineItems array into QuoteLineInfo DTOs.
     *              Recurses into nested lineItems to capture MDQ segments (SegmentIndex > 1). // VK
     * @param model The deserialized CPQ quote model
     * @return List of QuoteLineInfo DTOs
     */
    @testVisible
    private static List<QuoteLineInfo> parseLineItems(Map<String, Object> model) {
        List<Object> lineItems = (List<Object>) model.get('lineItems');
        List<QuoteLineInfo> results = new List<QuoteLineInfo>();
        if (lineItems == null) {
            return results;
        }
        collectLineItems(lineItems, results); // VK - delegate to recursive helper
        return results;
    }

    // VK - recursive helper so MDQ segments nested inside a parent lineItem are also collected
    @testVisible
    private static void collectLineItems(List<Object> lineItems, List<QuoteLineInfo> results) {
        for (Object item : lineItems) {
            if (item == null) continue;
            try { // VK - wrapped in try/catch so a bad entry never aborts remaining lines
                Map<String, Object> lineItem = (Map<String, Object>) item;
                Map<String, Object> rec = (Map<String, Object>) lineItem.get('record');
                if (rec == null) {
                    System.debug(LoggingLevel.WARN, 'AgenticQTC_QuoteAmendmentService: CPQ lineItem missing record map, skipping.');
                } else {
                    results.add(buildQuoteLineInfoFromMap(rec));
                }
                // VK - recurse into nested lineItems to pick up MDQ segments (SegmentIndex > 1)
                List<Object> nested = (List<Object>) lineItem.get('lineItems');
                if (nested != null && !nested.isEmpty()) {
                    collectLineItems(nested, results); // VK
                }
            } catch (Exception e) { // VK
                System.debug(LoggingLevel.ERROR, 'AgenticQTC_QuoteAmendmentService: Failed to parse CPQ lineItem, skipping. Error: ' + e.getMessage() + ' | Item: ' + JSON.serialize(item)); // VK
            }
        }
    }

    /**
     * @description Builds a QuoteLineInfo DTO from a CPQ JSON record map.
     * @param rec The deserialized record map from CPQ lineItem
     * @return QuoteLineInfo with all fields and computed values populated
     */
    @testVisible
    private static QuoteLineInfo buildQuoteLineInfoFromMap(Map<String, Object> rec) {
        QuoteLineInfo info = new QuoteLineInfo();
        info.id = getString(rec, 'Id');
        info.productId = getString(rec, 'SBQQ__Product__c');
        info.productName = getString(rec, 'SBQQ__ProductName__c');
        info.productCode = getString(rec, 'SBQQ__ProductCode__c');
        info.quantity = getDecimalVal(rec, 'SBQQ__Quantity__c');
        info.priorQuantity = getDecimalVal(rec, 'SBQQ__PriorQuantity__c');
        info.netPrice = getDecimalVal(rec, 'SBQQ__NetPrice__c');
        info.netTotal = getDecimalVal(rec, 'SBQQ__NetTotal__c');
        info.listPrice = getDecimalVal(rec, 'SBQQ__ListPrice__c');
        info.customerPrice = getDecimalVal(rec, 'SBQQ__CustomerPrice__c');
        info.discount = getDecimalVal(rec, 'SBQQ__Discount__c');
        info.segmentIndex = getIntegerVal(rec, 'SBQQ__SegmentIndex__c');
        info.segmentKey = getString(rec, 'SBQQ__SegmentKey__c');
        info.segmentLabel = getString(rec, 'SBQQ__SegmentLabel__c');
        info.startDate = getDateVal(rec, 'SBQQ__StartDate__c');
        info.endDate = getDateVal(rec, 'SBQQ__EndDate__c');
        info.acv = getDecimalVal(rec, 'ACV__c');
        info.acvChange = getDecimalVal(rec, 'ACV_Change__c');
        info.chargeType = getString(rec, 'SBQQ__ChargeType__c');
        info.customerSalePricePerMonth = getDecimalVal(rec, 'Customer_Sale_Price_Per_Month__c');
        info.meterType = getString(rec, 'Per_Integrations__c');
        Object bundleRaw = rec.get('SBQQ__Bundle__c');
        info.isBundle = bundleRaw instanceof Boolean ? (Boolean) bundleRaw : false;
        info.cpqOptionType = getString(rec, 'CPQ_Option_Type__c');
        info.requiredBy = getString(rec, 'SBQQ__RequiredBy__c');
        populateComputedFields(info);
        return info;
    }

    // ─── Record-to-DTO Builder ──────────────────────────────────────────

    /**
     * @description Builds a QuoteLineInfo DTO from a SBQQ__QuoteLine__c SObject.
     * @param ql The quote line record with all required fields queried
     * @return QuoteLineInfo with all fields and computed values populated
     */
    @testVisible
    private static QuoteLineInfo buildQuoteLineInfoFromRecord(SBQQ__QuoteLine__c ql) {
        QuoteLineInfo info = new QuoteLineInfo();
        info.id = ql.Id;
        info.productId = ql.SBQQ__Product__c;
        info.productName = ql.SBQQ__ProductName__c;
        info.productCode = ql.SBQQ__ProductCode__c;
        info.quantity = ql.SBQQ__Quantity__c;
        info.priorQuantity = ql.SBQQ__PriorQuantity__c;
        info.netPrice = ql.SBQQ__NetPrice__c;
        info.netTotal = ql.SBQQ__NetTotal__c;
        info.listPrice = ql.SBQQ__ListPrice__c;
        info.customerPrice = ql.SBQQ__CustomerPrice__c;
        info.discount = ql.SBQQ__Discount__c;
        info.segmentIndex = ql.SBQQ__SegmentIndex__c != null ? (Integer) ql.SBQQ__SegmentIndex__c : 0;
        info.segmentKey = ql.SBQQ__SegmentKey__c;
        info.segmentLabel = ql.SBQQ__SegmentLabel__c;
        info.startDate = ql.SBQQ__StartDate__c;
        info.endDate = ql.SBQQ__EndDate__c;
        info.acv = ql.ACV__c;
        info.acvChange = ql.ACV_Change__c;
        info.chargeType = ql.SBQQ__ChargeType__c;
        info.customerSalePricePerMonth = ql.Customer_Sale_Price_Per_Month__c;
        // If Per_Integrations__c is on Product2 instead, use: ql.SBQQ__Product__r.Per_Integrations__c
        info.meterType = ql.Per_Integrations__c;
        info.isBundle = ql.SBQQ__Bundle__c == true;
        info.cpqOptionType = ql.CPQ_Option_Type__c;
        info.requiredBy = ql.SBQQ__RequiredBy__c;
        populateComputedFields(info);
        return info;
    }

    /**
     * @description Sets totalCost, isLocked, and approvalRequired on a QuoteLineInfo DTO.
     */
    @testVisible
    private static void populateComputedFields(QuoteLineInfo info) {
        Decimal qty = info.quantity != null ? info.quantity : 0;
        Decimal priorQty = info.priorQuantity != null ? info.priorQuantity : 0;
        info.totalCost = info.netPrice != null ? info.netPrice : 0;
        info.isLocked = info.endDate != null && info.endDate < Date.today();

        if (qty < priorQty) {
            info.approvalRequired = 'Required';
        } else if (priorQty == 0) {
            info.approvalRequired = 'Required';
        } else {
            info.approvalRequired = 'Not Required';
        }
    }

    /**
     * @description Builds a QuoteInfo DTO from a SBQQ__Quote__c SObject.
     * @param quote The quote record
     * @return QuoteInfo with id, name, status, and relationship Ids
     */
    @testVisible
    private static QuoteInfo buildQuoteInfo(SBQQ__Quote__c quote) {
        QuoteInfo info = new QuoteInfo();
        info.id = quote.Id;
        info.name = quote.Name;
        info.status = quote.SBQQ__Status__c;
        info.startDate = quote.SBQQ__StartDate__c;
        info.accountId = quote.SBQQ__Account__c;
        info.contractId = quote.SBQQ__MasterContract__c;
        info.opportunityId = quote.SBQQ__Opportunity2__c;

        if (quote.Invoicing_Contact__r != null) {
            info.invoicingContactName = quote.Invoicing_Contact__r.Name;
            info.invoicingContactEmail = quote.Invoicing_Contact__r.Email;
        }
        if (quote.Software_Delivery_Contact__r != null) {
            info.softwareDeliveryContactName = quote.Software_Delivery_Contact__r.Name;
            info.softwareDeliveryContactEmail = quote.Software_Delivery_Contact__r.Email;
        }

        /*try {
            AgenticQTC_ApprovalLogicService.ApprovalSummary approval =
                AgenticQTC_ApprovalLogicService.evaluateQuoteApproval(quote.Id);
            info.approvalReasons = approval.reasons;
        } catch (Exception e) {
            info.approvalReasons = new List<String>();
        }*/

        try {
          //  info.dealQualityScore = DealQualityScoreCalculator.calculateScoreWithCalculatedFields(quote.Id, 0, 0);VK
        } catch (Exception e) {
            info.dealQualityScore = null;
        }

        return info;
    }

    // ─── Type-safe JSON accessors ───────────────────────────────────────

    /**
     * @description Type-safe Decimal extractor from a generic object map.
     *              Handles Integer, Long, Double, and String inputs.
     * @param m The source map
     * @param key The key to extract
     * @return Decimal value, or null if missing or unparseable
     */
    @testVisible
    private static Decimal getDecimalVal(Map<String, Object> m, String key) {
        Object val = m.get(key);
        if (val == null) return null;
        if (val instanceof Decimal) return (Decimal) val;
        if (val instanceof Integer) return Decimal.valueOf((Integer) val);
        if (val instanceof Long) return Decimal.valueOf((Long) val);
        if (val instanceof Double) return Decimal.valueOf((Double) val);
        try { return Decimal.valueOf(String.valueOf(val)); } catch (Exception e) { return null; }
    }

    /**
     * @description Type-safe Integer extractor via Decimal conversion.
     * @param m The source map
     * @param key The key to extract
     * @return Integer value, or 0 if missing
     */
    @testVisible
    private static Integer getIntegerVal(Map<String, Object> m, String key) {
        Decimal d = getDecimalVal(m, key);
        return d != null ? d.intValue() : 0;
    }

    /**
     * @description Safely extracts a String from a generic object map.
     * @param m The source map
     * @param key The key to extract
     * @return String value, or null if missing
     */
    @testVisible
    private static String getString(Map<String, Object> m, String key) {
        Object val = m.get(key);
        return val != null ? String.valueOf(val) : null;
    }

    /**
     * @description Type-safe Date extractor from a generic object map.
     * @param m The source map
     * @param key The key to extract
     * @return Date value, or null if missing or unparseable
     */
    @testVisible
    private static Date getDateVal(Map<String, Object> m, String key) {
        Object val = m.get(key);
        if (val == null) return null;
        if (val instanceof Date) return (Date) val;
        try { return Date.valueOf(String.valueOf(val)); } catch (Exception e) { return null; }
    }

    // ─── Controller-delegated service methods ──────────────────────────

    /**
     * @description Returns draft amendment quotes for a contract whose end date is today
     *              or later. Fed into the OSA selector's "existing draft" picker modal so
     *              users can reuse an in-progress amendment instead of re-amending.
     * @param contractId The Contract record Id whose drafts to list
     * @return List of DraftQuoteOption rows (id, name, dealId, endDate) — never null
     */
    public static List<DraftQuoteOption> getDraftQuotesForContract(String contractId) {
        List<DraftQuoteOption> results = new List<DraftQuoteOption>();
        if (String.isBlank(contractId)) {
            return results;
        }
        for (SBQQ__Quote__c q : [
            SELECT Id, Name, SBQQ__StartDate__c, SBQQ__EndDate__c
            FROM SBQQ__Quote__c
            WHERE SBQQ__MasterContract__c = :contractId
            AND SBQQ__Status__c = :STATUS_DRAFT
            AND SBQQ__Type__c = :TYPE_AMENDMENT
            AND Deal_Type__c = :DEAL_TYPE_ADD_ON
            AND (NOT Opportunity_Stage__c LIKE '%Closed%')
            AND SBQQ__EndDate__c >= TODAY
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            DraftQuoteOption opt = new DraftQuoteOption();
            opt.id        = q.Id;
            opt.name      = q.Name;
            opt.startDate = q.SBQQ__StartDate__c != null ? String.valueOf(q.SBQQ__StartDate__c) : null;
            opt.endDate   = q.SBQQ__EndDate__c   != null ? String.valueOf(q.SBQQ__EndDate__c)   : null;
            results.add(opt);
        }
        return results;
    }

    /**
     * @description Reads an existing draft amendment quote and its lines via pure SOQL,
     *              with NO CPQ amend / calculate / save round-trip. Used by the OSA selector
     *              "Existing Draft Quotes" picker flow so the editor can display a draft's
     *              data without re-running the amendment process. Returns the same
     *              AmendmentQuoteInfo shape as createAmendmentQuote so the LWC can consume
     *              both paths through the same code.
     * @param quoteId The existing draft SBQQ__Quote__c Id chosen by the user
     * @return AmendmentQuoteInfo with id, name, status, today's start date and lines
     */
    public static AmendmentQuoteInfo loadExistingDraftQuote(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }
        List<SBQQ__Quote__c> quotes = [
            SELECT Id, Name, SBQQ__Status__c, SBQQ__StartDate__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            throw new AuraHandledException('Quote not found: ' + quoteId);
        }
        SBQQ__Quote__c q = quotes[0];
        // Pass the saved start date through as-is. Past dates within the current
        // segment are valid per the date-validation story — the LWC will fall
        // back to today only when no value is saved on the quote record.
        AmendmentQuoteInfo info = new AmendmentQuoteInfo();
        info.id        = q.Id;
        info.name      = q.Name;
        info.status    = q.SBQQ__Status__c;
        info.startDate = q.SBQQ__StartDate__c != null ? String.valueOf(q.SBQQ__StartDate__c) : null;
        info.lines     = getQuoteLinesByQuoteId(quoteId);
        return info;
    }

    /**
     * @description Pure-SOQL read of all QuoteLines for a quote, returned as the same
     *              QuoteLineInfo DTOs the CPQ-backed reader produces. Used by the
     *              "reuse existing draft" flow — does NOT call any CPQ ServiceRouter
     *              API and therefore cannot trigger an amendment / re-price.
     * @param quoteId The SBQQ__Quote__c Id whose lines to fetch
     * @return List of QuoteLineInfo DTOs sorted by line number / product name
     */
    public static List<QuoteLineInfo> getQuoteLinesByQuoteId(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException(ERR_QUOTE_REQUIRED);
        }
        List<SBQQ__QuoteLine__c> qLines = [
            SELECT Id, SBQQ__Product__c, SBQQ__ProductName__c, SBQQ__ProductCode__c,
                   SBQQ__Quantity__c, SBQQ__PriorQuantity__c, SBQQ__NetPrice__c, SBQQ__NetTotal__c,
                   SBQQ__ListPrice__c, SBQQ__CustomerPrice__c, SBQQ__Discount__c,
                   SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c, SBQQ__SegmentLabel__c,
                   SBQQ__StartDate__c, SBQQ__EndDate__c, ACV__c, ACV_Change__c,
                   SBQQ__ChargeType__c, SBQQ__Number__c, Customer_Sale_Price_Per_Month__c,
                   Per_Integrations__c, SBQQ__Bundle__c, CPQ_Option_Type__c,
                   SBQQ__RequiredBy__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY SBQQ__Number__c, SBQQ__ProductName__c
            LIMIT 50000
        ];
        List<QuoteLineInfo> results = new List<QuoteLineInfo>();
        for (SBQQ__QuoteLine__c ql : qLines) {
            results.add(buildQuoteLineInfoFromRecord(ql));
        }
        return results;
    }

    /**
     * @description Creates a CPQ amendment quote for the given contract and returns
     *              the AmendmentQuoteInfo DTO needed by the LWC quote editor.
     * @param contractId The Contract record Id
     * @return AmendmentQuoteInfo with id, name, status and startDate
     */
    public static AmendmentQuoteInfo createAmendmentQuote(String contractId) {
        Map<String, Object> amendmentModel = AgenticQTC_CPQAmendmentService.amendAndUpdateLines(
            Id.valueOf(contractId),
            new Map<Id, Map<String, Object>>()
        );
        Id amendmentQuoteId = AgenticQTC_CPQAPIUtils.getQuoteId(amendmentModel);
        if (amendmentQuoteId == null) {
            throw new AuraHandledException('CPQ amendment returned no quote Id');
        }
        stampCreatedBySimplifiedQuoting(amendmentQuoteId);
        SBQQ__Quote__c q = AgenticQTC_CPQAmendmentService.getQuoteById(amendmentQuoteId);
        AmendmentQuoteInfo info = new AmendmentQuoteInfo();
        info.id        = q.Id;
        info.name      = q.Name;
        info.status    = q.SBQQ__Status__c;
        info.startDate = q.SBQQ__StartDate__c != null ? String.valueOf(q.SBQQ__StartDate__c) : null;
        // VK - parse the lines straight from the amender's response so the LWC doesn't
        // need to fire a separate QuoteReader round-trip on init.
        info.lines     = parseLineItems(amendmentModel);
        return info;
    }

    /**
     * @description Creates a new CPQ amendment quote for the contract and applies
     *              user-specified quantity changes keyed by subscription Id.
     * @param contractId    The Contract record Id
     * @param quantitiesJson JSON-serialised Map<subscriptionId, newQuantity>
     * @return The new amendment SBQQ__Quote__c Id as a String
     */
    public static String createAmendmentWithQuantities(String contractId, String quantitiesJson) {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(quantitiesJson);
        Map<Id, Map<String, Object>> fieldValuesBySubscriptionId = new Map<Id, Map<String, Object>>();
        for (String k : raw.keySet()) {
            fieldValuesBySubscriptionId.put(
                Id.valueOf(k),
                new Map<String, Object>{ 'SBQQ__Quantity__c' => Decimal.valueOf(String.valueOf(raw.get(k))) }
            );
        }
        Map<String, Object> amendmentModel =
            AgenticQTC_CPQAmendmentService.amendAndUpdateLines(Id.valueOf(contractId), fieldValuesBySubscriptionId);
        Id amendmentQuoteId = AgenticQTC_CPQAPIUtils.getQuoteId(amendmentModel);
        if (amendmentQuoteId == null) {
            throw new AuraHandledException('CPQ amendment returned no quote Id');
        }
        stampCreatedBySimplifiedQuoting(amendmentQuoteId);
        return String.valueOf(amendmentQuoteId);
    }

    /**
     * @description Marks the Opportunity behind the given amendment quote as created by
     *              Simplified (Agentic) Quoting. When true, OP4I platform events publish for
     *              the Opportunity (and its Opportunity Products) regardless of Deal Type,
     *              including Add-On. The field is registered in Field_Tracking__mdt so this
     *              update re-fires the Opportunity DealEvent__e even though CPQ created the
     *              Opportunity earlier in the transaction.
     * @param quoteId The amendment SBQQ__Quote__c Id whose Opportunity should be flagged
     */
    @testVisible
    private static void stampCreatedBySimplifiedQuoting(Id quoteId) {
        if (quoteId == null) {
            return;
        }
        List<SBQQ__Quote__c> quotes = [
            SELECT SBQQ__Opportunity2__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (quotes.isEmpty() || quotes[0].SBQQ__Opportunity2__c == null) {
            return;
        }
        try {
            update new Opportunity(
                Id = quotes[0].SBQQ__Opportunity2__c,
                Created_by_Simplified_Quoting__c = true
            );
        } catch (Exception e) {
            Nebula.Logger.error('stampCreatedBySimplifiedQuoting failed for quote ' + quoteId + ': ' + e.getMessage(), e)
                .addTag('AgenticQTC_QuoteAmendmentService').addTag('Amendment').setRecordId(quoteId);
            Nebula.Logger.saveLog();
        }
    }

    /**
     * @description Updates the quantity for a single quote line via direct DML (no CPQ API).
     *              CPQ calculate + save is deferred until the user clicks Save.
     * @param quoteId     The SBQQ__Quote__c Id
     * @param quoteLineId The SBQQ__QuoteLine__c Id to update
     * @param newQuantity The new quantity value
     * @return Refreshed list of QuoteLineInfo DTOs
     */
    public static List<QuoteLineInfo> applyLineQuantityUpdate(
            String quoteId, String quoteLineId, Decimal newQuantity) {
        return updateQuoteLineQuantityViaDml(quoteId, quoteLineId, newQuantity);
    }

    /**
     * @description Updates the quantity for an MDQ segment, or all segments sharing
     *              a segmentKey when applyToAllSegments is true, via direct DML (no CPQ API).
     *              CPQ calculate + save is deferred until the user clicks Save.
     * @param quoteId            The SBQQ__Quote__c Id
     * @param quoteLineId        The specific segment SBQQ__QuoteLine__c Id to update
     * @param newQuantity        The new quantity value
     * @param segmentKey         The SBQQ__SegmentKey__c shared by all segments of this product
     * @param applyToAllSegments When true, all segments with the same segmentKey are updated
     * @return Refreshed list of QuoteLineInfo DTOs
     */
    public static List<QuoteLineInfo> applyMdqSegmentQuantityUpdate(
            String quoteId, String quoteLineId, Decimal newQuantity,
            String segmentKey, Boolean applyToAllSegments) {
        if (applyToAllSegments == true && String.isNotBlank(segmentKey)) {
            return updateAllMdqSegmentsViaDml(quoteId, segmentKey, newQuantity);
        }
        return updateQuoteLineQuantityViaDml(quoteId, quoteLineId, newQuantity);
    }

    /**
     * @description Applies all pending quantity changes for a quote in a single call,
     *              then returns the refreshed set of QuoteLineInfo DTOs.
     * @param quoteId     The SBQQ__Quote__c Id
     * @param changesJson JSON array of { lineId, quantity, segmentKey?, applyToAll? }
     * @return Refreshed list of QuoteLineInfo DTOs
     */
    public static List<QuoteLineInfo> saveQuantityChanges(String quoteId, String changesJson) {
        Map<Id, Map<String, Object>> fieldValuesByLineId = new Map<Id, Map<String, Object>>();
        if (String.isNotBlank(changesJson)) {
            List<Object> changes = (List<Object>) JSON.deserializeUntyped(changesJson);
            for (Object changeObj : changes) {
                Map<String, Object> change   = (Map<String, Object>) changeObj;
                String  lineId      = (String)  change.get('lineId');
                Decimal quantity    = Decimal.valueOf(String.valueOf(change.get('quantity')));
                Boolean applyToAll  = change.get('applyToAll') == true;
                String  segmentKey  = (String)  change.get('segmentKey');
                if (applyToAll && String.isNotBlank(segmentKey)) {
                    for (SBQQ__QuoteLine__c seg : AgenticQTC_CPQAmendmentService.getSegmentLines(Id.valueOf(quoteId), segmentKey)) {
                        fieldValuesByLineId.put(seg.Id, new Map<String, Object>{ 'SBQQ__Quantity__c' => quantity });
                    }
                } else {
                    fieldValuesByLineId.put(Id.valueOf(lineId), new Map<String, Object>{ 'SBQQ__Quantity__c' => quantity });
                }
            }
        }
        AgenticQTC_CPQAmendmentService.updateQuoteAndLines(Id.valueOf(quoteId),null, fieldValuesByLineId);
        return getQuoteLines(quoteId);
    }

    /**
     * @description Combined save used by the LWC when the user clicks Save:
     *              applies pending quantity changes AND quote-header changes
     *              (start date, invoicing contact, software delivery contact) in a
     *              single CPQ round-trip via AgenticQTC_CPQAmendmentService.updateQuoteAndLines.
     *              Returns the refreshed quote lines AND a fresh QuoteDetailsInfo so
     *              the LWC can map the persisted values back onto its local state.
     *              Inputs are taken from the LWC's current state — the caller is the
     *              source of truth, so each field is always written (idempotent if
     *              unchanged).
     * @param quoteId                   The SBQQ__Quote__c Id
     * @param changesJson               JSON array of { lineId, quantity, segmentKey?, applyToAll? }
     * @param startDate                 The current start-date value to persist (nullable)
     * @param invoicingContactId        The current invoicing contact Id to persist (blank clears)
     * @param softwareDeliveryContactId The current delivery contact Id to persist (blank clears)
     * @return QuoteSaveResult { lines, details } reflecting the saved state
     */
    public static QuoteSaveResult saveQuoteChanges(String quoteId, String changesJson,
            Date startDate, String invoicingContactId, String softwareDeliveryContactId) {
        Map<Id, Map<String, Object>> fieldValuesByLineId = buildLineQuantityChanges(quoteId, changesJson);

        Map<String, Object> headerFieldValues = new Map<String, Object>{
            'SBQQ__StartDate__c'           => startDate,
            'Invoicing_Contact__c'         => String.isBlank(invoicingContactId)
                                                ? null : Id.valueOf(invoicingContactId),
            'Software_Delivery_Contact__c' => String.isBlank(softwareDeliveryContactId)
                                                ? null : Id.valueOf(softwareDeliveryContactId)
        };

        AgenticQTC_CPQAmendmentService.updateQuoteAndLines(Id.valueOf(quoteId), headerFieldValues, fieldValuesByLineId);

        // BIZ-83493: advance the quote to 'Finalize OSA' on Save (simplified quoting tool only).
        // Replaces the previous advance at document generation time. Runs synchronously in the
        // same transaction as the CPQ save above, so a validation failure here (e.g. unverified
        // addresses, missing Contract Master Terms) propagates and rolls the whole save back —
        // nothing is persisted and the exact org message reaches the user (surfaced by the
        // controller). Standard QLE is unaffected because this path is reachable only from the tool.
        advanceToFinalizeOsa(quoteId);

        QuoteSaveResult result = new QuoteSaveResult();
        result.lines   = getQuoteLines(quoteId);
        result.details = getQuoteDetails(quoteId);
        return result;
    }

    /**
     * @description Advances the quote to the 'Finalize OSA' stage as part of a simplified-tool
     *              Save. Guarded on the current value so a re-save of an already-finalized quote
     *              does not re-trip the ISCHANGED(Quote_Stage__c) address-verification rule or
     *              re-fire stage-driven flows. Intentionally NOT wrapped in try/catch: a validation
     *              DmlException must propagate so the entire synchronous save (CPQ round-trip
     *              included) rolls back, satisfying "nothing saved on validation error". BIZ-83493
     * @param quoteId The SBQQ__Quote__c Id
     */
    @testVisible
    private static void advanceToFinalizeOsa(String quoteId) {
        SBQQ__Quote__c q = [
            SELECT Id, Quote_Stage__c
            FROM   SBQQ__Quote__c
            WHERE  Id = :quoteId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];
        if (q.Quote_Stage__c != QuoteConstants.STATUS_FINALIZE_OSA) {
            q.Quote_Stage__c = QuoteConstants.STATUS_FINALIZE_OSA;
            update q;
        }
    }

    /**
     * @description Shared helper that parses the LWC's changesJson payload into the
     *              `Map<lineId, fieldValues>` shape AgenticQTC_CPQAmendmentService expects. Honours
     *              `applyToAll` by expanding into every QuoteLine that shares the segmentKey.
     */
    @testVisible
    private static Map<Id, Map<String, Object>> buildLineQuantityChanges(String quoteId, String changesJson) {
        Map<Id, Map<String, Object>> fieldValuesByLineId = new Map<Id, Map<String, Object>>();
        if (String.isBlank(changesJson)) {
            return fieldValuesByLineId;
        }
        List<Object> changes = (List<Object>) JSON.deserializeUntyped(changesJson);
        for (Object changeObj : changes) {
            Map<String, Object> change   = (Map<String, Object>) changeObj;
            String  lineId      = (String)  change.get('lineId');
            Decimal quantity    = Decimal.valueOf(String.valueOf(change.get('quantity')));
            Boolean applyToAll  = change.get('applyToAll') == true;
            String  segmentKey  = (String)  change.get('segmentKey');
            if (applyToAll && String.isNotBlank(segmentKey)) {
                for (SBQQ__QuoteLine__c seg : AgenticQTC_CPQAmendmentService.getSegmentLines(Id.valueOf(quoteId), segmentKey)) {
                    fieldValuesByLineId.put(seg.Id, new Map<String, Object>{ 'SBQQ__Quantity__c' => quantity });
                }
            } else {
                fieldValuesByLineId.put(Id.valueOf(lineId), new Map<String, Object>{ 'SBQQ__Quantity__c' => quantity });
            }
        }
        return fieldValuesByLineId;
    }

    /**
     * @description Retrieves quote-level display fields for the amendment editor.
     * @param quoteId The SBQQ__Quote__c Id
     * @return QuoteDetailsInfo DTO
     */
    public static QuoteDetailsInfo getQuoteDetails(String quoteId) {
        SBQQ__Quote__c q = [
            SELECT SBQQ__StartDate__c, SBQQ__SubscriptionTerm__c, First_Segment_Months__c,
                   SBQQ__CustomerDiscount__c, SBQQ__BillingFrequency__c,
                   SBQQ__PaymentTerms__c, ApprovalStatus__c, Deal_Quality_Score__c,
                   Min_year_on_year_committed_spend__c,
                   Invoicing_Contact__c,
                   Invoicing_Contact__r.Name, Invoicing_Contact__r.Email, Invoicing_Contact__r.Title,
                   Invoicing_Contact__r.Account.Name,
                   Software_Delivery_Contact__c,
                   Software_Delivery_Contact__r.Name, Software_Delivery_Contact__r.Email, Software_Delivery_Contact__r.Title,
                   Software_Delivery_Contact__r.Account.Name
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        QuoteDetailsInfo info    = new QuoteDetailsInfo();
        info.startDate           = q.SBQQ__StartDate__c != null ? String.valueOf(q.SBQQ__StartDate__c) : null;
        info.subscriptionTerm    = q.SBQQ__SubscriptionTerm__c;
        info.firstSegmentMonths  = q.First_Segment_Months__c;
        info.discount            = q.SBQQ__CustomerDiscount__c;
        info.billingFrequency    = q.SBQQ__BillingFrequency__c;
        info.paymentTerms        = q.SBQQ__PaymentTerms__c;
        info.invoicingContactId  = q.Invoicing_Contact__c;
        if (q.Invoicing_Contact__r != null) {
            info.invoicingContactName        = q.Invoicing_Contact__r.Name;
            info.invoicingContactEmail       = q.Invoicing_Contact__r.Email;
            info.invoicingContactTitle       = q.Invoicing_Contact__r.Title;
            info.invoicingContactAccountName = q.Invoicing_Contact__r.Account != null
                ? q.Invoicing_Contact__r.Account.Name : null;
        }
        info.softwareDeliveryContactId = q.Software_Delivery_Contact__c;
        if (q.Software_Delivery_Contact__r != null) {
            info.softwareDeliveryContactName        = q.Software_Delivery_Contact__r.Name;
            info.softwareDeliveryContactEmail       = q.Software_Delivery_Contact__r.Email;
            info.softwareDeliveryContactTitle       = q.Software_Delivery_Contact__r.Title;
            info.softwareDeliveryContactAccountName = q.Software_Delivery_Contact__r.Account != null
                ? q.Software_Delivery_Contact__r.Account.Name : null;
        }
        info.approvalStatus = q.ApprovalStatus__c;
        info.dealQualityScore = q.Deal_Quality_Score__c;
        info.minYoyCommittedSpend = q.Min_year_on_year_committed_spend__c;
        return info;
    }

    // ─── Contact picker (Invoicing / Software Delivery Contact) ─────────

    /**
     * @description Returns contacts on the given account for the quote editor's
     *              Select Contact modal. Sorted by name; LWC re-orders so the
     *              currently selected contact is shown first.
     * @param accountId The Account Id (already known to the LWC; not re-derived from the quote)
     * @return List of ContactOption DTOs (id, name, email, title)
     */
    public static List<ContactOption> getAccountContacts(String accountId) {
        List<ContactOption> options = new List<ContactOption>();
        if (String.isBlank(accountId)) {
            return options;
        }
        //if filter based on account needed AccountId = :accountId
        for (Contact c : [
            SELECT Id, Name, Email, Title, Account.Name
            FROM Contact
            WHERE Email != null
            AND AccountId != null
            AND AccountId = :accountId
            AND Name != null
            AND (NOT Name LIKE '%NO LONGER AT FIRM%')
            AND (NOT Email LIKE '%noreply%')
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            ContactOption opt = new ContactOption();
            opt.id          = c.Id;
            opt.name        = c.Name;
            opt.email       = c.Email;
            opt.title       = c.Title;
            opt.accountName = c.Account != null ? c.Account.Name : null;
            options.add(opt);
        }
        return options;
    }

    /**
     * @description Server-side fallback for the contact picker. The LWC only calls this
     *              when its locally-cached 1000 contacts contain no match for the user's
     *              search term. Filters by `Name LIKE %term%` so the picker can surface
     *              contacts that weren't part of the initial page. LWC sends the raw
     *              user input; this method trims surrounding whitespace.
     * @param searchTerm Free-text term entered in the picker's search box (untrimmed).
     * @return List of ContactOption DTOs (id, name, email, title). Empty when the term
     *         is blank, whitespace-only, or contains only SOQL wildcard characters.
     */
    public static List<ContactOption> searchContacts(String searchTerm) {
        List<ContactOption> options = new List<ContactOption>();
        if (String.isBlank(searchTerm)) {
            return options;
        }
        // Trim whitespace, then strip SOQL LIKE wildcards / escape char so the user
        // can't broaden the pattern beyond their typed text. Bind variable handles
        // single-quote escaping.
        String cleaned = searchTerm.trim().replaceAll('[%_\\\\]', '');
        if (String.isBlank(cleaned)) {
            return options;
        }
        String pattern = '%' + cleaned + '%';
        for (Contact c : [
            SELECT Id, Name, Email, Title, Account.Name
            FROM Contact
            WHERE Email != null
            AND AccountId != null
            AND Name != null
            AND Name LIKE :pattern
            AND (NOT Name LIKE '%NO LONGER AT FIRM%')
            AND (NOT Email LIKE '%noreply%')
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            ContactOption opt = new ContactOption();
            opt.id          = c.Id;
            opt.name        = c.Name;
            opt.email       = c.Email;
            opt.title       = c.Title;
            opt.accountName = c.Account != null ? c.Account.Name : null;
            options.add(opt);
        }
        return options;
    }

    /**
     * @description Updates the invoicing or software delivery contact lookup on the quote.
     *              Pass a blank contactId to clear the field.
     *              No longer called from the LWC after 2026-05-12 — contact changes are now
     *              batched through saveQuoteChanges and persisted in the combined CPQ save.
     *              Method retained for any direct Apex callers / future use.
     * @param quoteId     The SBQQ__Quote__c Id
     * @param contactType "invoicing" or "delivery"
     * @param contactId   The Contact Id to assign (or blank/null to clear)
     */
    // public static void updateQuoteContact(String quoteId, String contactType, String contactId) {
    //     if (String.isBlank(quoteId)) {
    //         throw new AuraHandledException(ERR_QUOTE_REQUIRED);
    //     }
    //     SBQQ__Quote__c q = new SBQQ__Quote__c(Id = quoteId);
    //     Id newContactId = String.isBlank(contactId) ? null : Id.valueOf(contactId);
    //     if ('invoicing'.equalsIgnoreCase(contactType)) {
    //         q.Invoicing_Contact__c = newContactId;
    //     } else if ('delivery'.equalsIgnoreCase(contactType)) {
    //         q.Software_Delivery_Contact__c = newContactId;
    //     } else {
    //         throw new AuraHandledException('Unsupported contact type: ' + contactType);
    //     }
    //     update q;
    // }

    /**
     * @description Placeholder for SFA field update — implementation pending.
     * @param quoteId The SBQQ__Quote__c Id
     * @param sfa     The new SFA value
     */
    public static void updateQuoteSfa(String quoteId, Boolean sfa) {
        // SFA__c field update pending field availability confirmation
        // update new SBQQ__Quote__c(Id = quoteId, SFA__c = sfa);
    }

    /**
     * @description Sets ApprovalStatus__c to 'Approved' when the caller has already
     *              confirmed (via SBAA preview) that no approval rules apply to this quote.
     *              No-ops if the quote is already Approved.
     * @param quoteId The SBQQ__Quote__c Id
     */
    public static void autoApproveIfNotRequired(Id quoteId) {
        SBQQ__Quote__c q = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :quoteId LIMIT 1];
        if (q.ApprovalStatus__c == QuoteConstants.STATUS_APPROVED) return;
        q.ApprovalStatus__c = QuoteConstants.STATUS_APPROVED;
        update q;
    }

    public static List<SBQQ__QuoteLine__c> getCurrentSegment(String quoteId) {
        List<SBQQ__QuoteLine__c> lines = [
            SELECT Id, SBQQ__SegmentKey__c, SBQQ__UpgradedSubscription__r.SBQQ__SegmentStartDate__c, SBQQ__UpgradedSubscription__r.SBQQ__SegmentEndDate__c, SBQQ__UpgradedSubscription__r.SBQQ__StartDate__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            AND SBQQ__UpgradedSubscription__c != null
            Order By SBQQ__UpgradedSubscription__r.SBQQ__SegmentStartDate__c, SBQQ__UpgradedSubscription__r.SBQQ__StartDate__c 
            LIMIT 1
        ];
        return lines;
    }

    // ─── DTOs ───────────────────────────────────────────────────────────

    /**
     * @description DTO returned by createAmendmentQuote — lightweight summary for the LWC header.
     */
    public class AmendmentQuoteInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String startDate;
        // VK - lines parsed from the ContractAmender response. Lets the LWC skip the
        // extra QuoteReader round-trip that loadLines() would have made on init.
        @AuraEnabled public List<QuoteLineInfo> lines;
    }

    /**
     * @description DTO returned by getQuoteDetails — quote-level display fields for the editor.
     */
    public class QuoteDetailsInfo {
        @AuraEnabled public String  startDate;
        @AuraEnabled public Decimal subscriptionTerm;
        @AuraEnabled public Decimal firstSegmentMonths;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public String  billingFrequency;
        @AuraEnabled public String  paymentTerms;
        @AuraEnabled public Boolean sfa;
        @AuraEnabled public String  invoicingContactId;
        @AuraEnabled public String  invoicingContactName;
        @AuraEnabled public String  invoicingContactEmail;
        @AuraEnabled public String  invoicingContactTitle;
        @AuraEnabled public String  invoicingContactAccountName;
        @AuraEnabled public String  softwareDeliveryContactId;
        @AuraEnabled public String  softwareDeliveryContactName;
        @AuraEnabled public String  softwareDeliveryContactEmail;
        @AuraEnabled public String  softwareDeliveryContactTitle;
        @AuraEnabled public String  softwareDeliveryContactAccountName;
        @AuraEnabled public String  approvalStatus;
        @AuraEnabled public Decimal dealQualityScore;
        /** SBQQ__Quote__c.Min_year_on_year_committed_spend__c — drives the YoY Uplift
         *  tile in the editor's metrics bar. CPQ recalculates this on Save, and the
         *  saveQuoteChanges response re-runs getQuoteDetails so the UI picks up the
         *  fresh value automatically. */
        @AuraEnabled public Decimal minYoyCommittedSpend;
    }

    /**
     * @description DTO returned by saveQuoteChanges — carries both the refreshed quote lines
     *              and a fresh QuoteDetailsInfo so the LWC can re-map persisted values back
     *              onto its local state in a single response.
     */
    public class QuoteSaveResult {
        @AuraEnabled public List<QuoteLineInfo> lines;
        @AuraEnabled public QuoteDetailsInfo details;
    }

    /**
     * @description DTO returned by getDraftQuotesForContract — one row per existing draft
     *              quote shown in the OSA selector's "Existing Draft Quotes" modal.
     */
    public class DraftQuoteOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String startDate;
        @AuraEnabled public String endDate;
    }

    /**
     * @description DTO returned by getAccountContacts — a single contact row for the picker modal.
     */
    public class ContactOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String title;
        @AuraEnabled public String accountName;
    }

    /**
     * @description DTO representing an amendment quote summary.
     */
    public class QuoteInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public String accountId;
        @AuraEnabled public String contractId;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String invoicingContactName;
        @AuraEnabled public String invoicingContactEmail;
        @AuraEnabled public String softwareDeliveryContactName;
        @AuraEnabled public String softwareDeliveryContactEmail;
        @AuraEnabled public Integer dealQualityScore;
        @AuraEnabled public List<String> approvalReasons;
    }

    /**
     * @description DTO representing a quote line with pricing, discount, and approval status.
     *              Includes computed fields: totalCost, isLocked, approvalRequired.
     */
    public class QuoteLineInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal priorQuantity;
        @AuraEnabled public Decimal netPrice;
        @AuraEnabled public Decimal netTotal;
        @AuraEnabled public Decimal listPrice;
        @AuraEnabled public Decimal customerPrice;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Integer segmentIndex;
        @AuraEnabled public String segmentKey;
        @AuraEnabled public String segmentLabel;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Decimal acv;
        @AuraEnabled public Decimal acvChange;
        @AuraEnabled public String chargeType;
        @AuraEnabled public Decimal customerSalePricePerMonth;
        @AuraEnabled public String approvalRequired;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public Decimal totalCost;
        @AuraEnabled public String meterType;
        @AuraEnabled public Boolean isBundle;
        @AuraEnabled public String cpqOptionType;
        @AuraEnabled public String requiredBy;
    }
}