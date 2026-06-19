/**
 * @description Service for retrieving Contract and Subscription data.
 *              Provides active contract lookups and detailed contract views
 *              including CPQ subscription line items.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_ContractService {

    private static final String ERR_ACCOUNT_REQUIRED = 'Account ID is required';
    private static final String ERR_CONTRACT_REQUIRED = 'Contract ID is required';
    private static final String ERR_CONTRACT_NUMBER_REQUIRED = 'Contract number is required';
    private static final String STATUS_CODE_ACTIVATED = 'Activated';
    // Status (picklist label) values eligible for the contract-selection grid.
    // StatusCode only carries the underlying API code (Activated), so custom
    // labels like "Partially Cancelled" / "Superseded" must be filtered via Status.
    private static final Set<String> CONTRACT_SELECTION_STATUSES = new Set<String>{
        'In Force', 'Partially Cancelled or superseded'
    };
    private static final String PRODUCT_TYPE_SOFTWARE = 'Software';
    private static final Integer MAX_SEARCH_RESULTS = 20;
    private static final Integer DESCRIPTION_MAX_LEN = 120;
    private static final Integer SPECIAL_TERMS_MAX_LEN = 100;

    /**
     * @description Gets all activated contracts for an account.
     * @param accountId The Account record Id
     * @return List of ContractResult DTOs
     */
    /** Not cacheable so the OSA list always reflects newly created/activated contracts after seeding.
     *  Filters applied so the user only sees contracts they can actually amend:
     *    a. Status is Activated, Partially Cancelled, or Superseded.
     *    b. The contract has at least one software subscription line
     *       (SBQQ__Subscription__c whose Product Type is 'Software').
     *    c. End date is in the future. */
    @AuraEnabled
    public static List<ContractResult> getActiveContracts(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException(ERR_ACCOUNT_REQUIRED);
        }
        List<Contract> contracts = [
            SELECT Id, Name, ContractNumber, OSA_Number__c, Status, StartDate, EndDate,
                   CurrencyIsoCode,
                   Account.Name, CustomerSignedId, CustomerSignedDate,
                   CompanySignedDate, ContractTerm, Description, SpecialTerms,
                   Owner.Name
            FROM Contract
            WHERE AccountId = :accountId
            AND Status IN :CONTRACT_SELECTION_STATUSES
            AND EndDate >= TODAY
            AND Id IN (
                SELECT SBQQ__Contract__c
                FROM SBQQ__Subscription__c
                WHERE SBQQ__Contract__c != null
                AND SBQQ__Product__r.Product_Type__c = :PRODUCT_TYPE_SOFTWARE
            )
            /* Oldest / legacy first: ascending contract number (e.g. CONT-050314 before CONT-050332) */
            ORDER BY ContractNumber ASC NULLS LAST
            LIMIT 100
        ];
        return toContractResults(contracts);
    }

    /**
     * @description Gets detailed contract information including subscriptions.
     * @param contractId The Contract record Id
     * @return ContractDetail DTO with subscription list
     */
    @AuraEnabled(cacheable=true)
    public static ContractDetail getContractDetail(String contractId) {
        if (String.isBlank(contractId)) {
            throw new AuraHandledException(ERR_CONTRACT_REQUIRED);
        }
        Contract c = [
            SELECT Id, ContractNumber, Status, StartDate, EndDate,
                   Account.Name, AccountId,
                   CustomerSignedId, CustomerSignedDate
            FROM Contract
            WHERE Id = :contractId
            LIMIT 1
        ];
        ContractDetail detail = new ContractDetail();
        detail.id = c.Id;
        detail.contractNumber = c.ContractNumber;
        detail.status = c.Status;
        detail.startDate = c.StartDate;
        detail.endDate = c.EndDate;
        detail.accountName = c.Account != null ? c.Account.Name : '';
        detail.accountId = c.AccountId;
        detail.productSummary = '';

        List<SBQQ__Subscription__c> subs = [
            SELECT Id, SBQQ__ProductName__c, SBQQ__Quantity__c,
                   SBQQ__NetPrice__c, SBQQ__ListPrice__c,
                   SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c,
                   SBQQ__SegmentLabel__c, SBQQ__SegmentStartDate__c,
                   SBQQ__SegmentEndDate__c, SBQQ__Product__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c = :contractId
            ORDER BY SBQQ__ProductName__c, SBQQ__SegmentIndex__c
        ];
        detail.subscriptions = new List<SubscriptionInfo>();
        for (SBQQ__Subscription__c sub : subs) {
            detail.subscriptions.add(new SubscriptionInfo(sub));
        }
        return detail;
    }

    /**
     * @description Searches contracts by contract number (partial match).
     *              Enables the AI chatbot to find a contract when the user provides
     *              only a contract number without specifying the account.
     * @param contractNumber Full or partial contract number to search for
     * @return List of ContractResult DTOs including account names
     */
    @AuraEnabled(cacheable=true)
    public static List<ContractResult> searchContractsByNumber(String contractNumber) {
        if (String.isBlank(contractNumber)) {
            throw new AuraHandledException(ERR_CONTRACT_NUMBER_REQUIRED);
        }
        String term = '%' + String.escapeSingleQuotes(contractNumber.trim()) + '%';
        List<Contract> contracts = [
            SELECT Id, Name, ContractNumber, OSA_Number__c, Status, StartDate, EndDate,
                   CurrencyIsoCode,
                   Account.Name, CustomerSignedId, CustomerSignedDate,
                   CompanySignedDate, ContractTerm, Description, SpecialTerms,
                   Owner.Name
            FROM Contract
            WHERE ContractNumber LIKE :term
            AND StatusCode = :STATUS_CODE_ACTIVATED
            ORDER BY ContractNumber ASC NULLS LAST
            LIMIT :MAX_SEARCH_RESULTS
        ];
        return toContractResults(contracts);
    }

    /**
     * @description Builds ContractResult rows with subscription aggregates.
     */
    private static List<ContractResult> toContractResults(List<Contract> contracts) {
        List<ContractResult> results = new List<ContractResult>();
        if (contracts.isEmpty()) {
            return results;
        }
        Set<Id> contractIds = new Set<Id>();
        for (Contract c : contracts) {
            contractIds.add(c.Id);
        }
        Map<Id, SubscriptionAgg> aggByContract = buildSubscriptionAggregates(contractIds);
        for (Contract c : contracts) {
            results.add(new ContractResult(c, aggByContract.get(c.Id)));
        }
        return results;
    }

    /**
     * @description Counts subscription lines and builds the current-year product display per
     *              contract, plus the current-year ACV total and full-contract TCV
     *              (software lines only).
     *
     *              Product display rule (drives the LWC "Products" column):
     *                For each product, sum SBQQ__Quantity__c across ALL current-year software
     *                subscription lines. The result is rendered as "{qty}x {ProductName}" by
     *                SubscriptionAgg.
     *
     *              Current-year: TODAY falls inside [SegmentStartDate, SegmentEndDate].
     *              Subscriptions with null segment dates (non-MDQ / single-year contracts)
     *              are included since the contract itself is filtered to EndDate >= TODAY.
     *
     *              Amendment model (BIZ-82982): in this CPQ org a quantity increase is stored
     *              as an ADD-ON subscription carrying only the incremental delta, co-termed
     *              from the amendment date to the segment end. The original baseline line
     *              stays active with its full-segment dates and original quantity, and the
     *              add-on points its SBQQ__RevisedSubscription__c back at the baseline. The
     *              true current quantity is therefore baseline + Σ deltas — i.e. the SUM of
     *              every current-segment line (e.g. 3 + 1 + 1 = 5). We must NOT skip the
     *              baseline as "superseded", or the display under-reports the increase
     *              (showing 2x — just the deltas — instead of 5x).
     *
     *              subscriptionCount remains a raw line count (used elsewhere as a sanity
     *              metric) — it is NOT filtered by current-year.
     */
    private static Map<Id, SubscriptionAgg> buildSubscriptionAggregates(Set<Id> contractIds) {
        Map<Id, SubscriptionAgg> result = new Map<Id, SubscriptionAgg>();
        if (contractIds == null || contractIds.isEmpty()) {
            return result;
        }
        for (Id cid : contractIds) {
            result.put(cid, new SubscriptionAgg());
        }
        Date today = Date.today();
        List<SBQQ__Subscription__c> subs = [
            SELECT Id, SBQQ__Contract__c, SBQQ__Product__c, SBQQ__ProductName__c,
                   SBQQ__Quantity__c, SBQQ__SegmentQuantity__c,
                   SBQQ__NetPrice__c, SBQQ__ProrateMultiplier__c,
                   SBQQ__SegmentStartDate__c, SBQQ__SegmentEndDate__c,
                   SBQQ__Product__r.Product_Type__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c IN :contractIds
            AND SBQQ__Product__r.Product_Type__c = :PRODUCT_TYPE_SOFTWARE
        ];
        // Per (contract, product), the line that represents the CURRENT amendment state in the
        // current segment — latest SBQQ__SegmentStartDate__c, tie-broken by higher
        // SBQQ__SegmentQuantity__c. Used for the ACV calculation after the loop.
        Map<String, SBQQ__Subscription__c> acvCurrentLineByKey = new Map<String, SBQQ__Subscription__c>();
        for (SBQQ__Subscription__c sub : subs) {
            SubscriptionAgg agg = result.get(sub.SBQQ__Contract__c);
            if (agg == null) {
                continue;
            }
            agg.lineCount++;
            Date segStart = sub.SBQQ__SegmentStartDate__c;
            Date segEnd = sub.SBQQ__SegmentEndDate__c;
            Boolean isCurrentYear = (segStart == null || segStart <= today)
                                 && (segEnd == null || segEnd >= today);
            if (isCurrentYear && String.isNotBlank(sub.SBQQ__ProductName__c)) {
                String pName = sub.SBQQ__ProductName__c;
                Decimal qty = sub.SBQQ__Quantity__c == null ? 0 : sub.SBQQ__Quantity__c;
                Decimal existing = agg.productNameQuantities.get(pName);
                agg.productNameQuantities.put(pName, existing == null ? qty : existing + qty);
            }
            // Track the current-state line per (contract, product) for the ACV calc after the
            // loop. When quantity grows mid-segment via co-term amendments, CPQ creates extra
            // lines whose raw NetPrice is prorated; SBQQ__SegmentQuantity__c on the latest line
            // already carries the full current quantity, so the ACV annualizes that single line
            // rather than summing lines (summing over-counts replacements and under-counts ramp /
            // carry-forward lines — verified against the org's subscription data).
            if (isCurrentYear && sub.SBQQ__Product__c != null) {
                String acvKey = sub.SBQQ__Contract__c + '|' + sub.SBQQ__Product__c;
                SBQQ__Subscription__c bestSoFar = acvCurrentLineByKey.get(acvKey);
                if (bestSoFar == null || isMoreCurrent(sub, bestSoFar)) {
                    acvCurrentLineByKey.put(acvKey, sub);
                }
            }
            // Subscription TCV = SBQQ__NetPrice__c × SBQQ__Quantity__c across every software
            // line of every segment (baseline + amendment deltas). Surfaced on the amendment
            // quote editor as the *initial* TCV value before the user makes any quantity
            // edits — see agenticQtcQuoteEditor.totalTcv.
            if (sub.SBQQ__NetPrice__c != null && sub.SBQQ__Quantity__c != null) {
                agg.subscriptionTcv = (agg.subscriptionTcv == null ? 0 : agg.subscriptionTcv)
                                    + (sub.SBQQ__NetPrice__c * sub.SBQQ__Quantity__c);
            }
        }
        // ACV (Annual Contract Value) per contract = Σ over each product's current-state line
        // of (SBQQ__NetPrice__c / SBQQ__ProrateMultiplier__c) × 12 × SBQQ__SegmentQuantity__c.
        // NetPrice/ProrateMultiplier recovers the per-unit MONTHLY rate (ProrateMultiplier is the
        // number of months in the line's period — 12 for a full year), ×12 annualizes it, and
        // SegmentQuantity is the current total quantity for that product/segment. Derived from
        // NetPrice because the SBQQ__Subscription__c.ACV__c formula relies on
        // Customer_Sale_Price_Per_Month__c, which is blank for migrated subscriptions.
        for (SBQQ__Subscription__c line : acvCurrentLineByKey.values()) {
            SubscriptionAgg agg = result.get(line.SBQQ__Contract__c);
            if (agg == null) {
                continue;
            }
            Decimal segQty = line.SBQQ__SegmentQuantity__c != null
                ? line.SBQQ__SegmentQuantity__c
                : line.SBQQ__Quantity__c;
            if (line.SBQQ__NetPrice__c == null || segQty == null) {
                continue;
            }
            Decimal pm = line.SBQQ__ProrateMultiplier__c;
            Decimal annualUnitPrice = (pm != null && pm != 0)
                ? (line.SBQQ__NetPrice__c / pm) * 12
                : line.SBQQ__NetPrice__c;
            agg.currentYearAcv = (agg.currentYearAcv == null ? 0 : agg.currentYearAcv)
                               + (annualUnitPrice * segQty);
        }
        return result;
    }

    /**
     * @description True when candidate represents a more current amendment state than incumbent
     *              for the same product in the current segment: a later SBQQ__SegmentStartDate__c
     *              wins (a non-null date beats a null one); on a tie the higher
     *              SBQQ__SegmentQuantity__c wins (the line carrying the full current quantity).
     */
    private static Boolean isMoreCurrent(SBQQ__Subscription__c candidate, SBQQ__Subscription__c incumbent) {
        Date cStart = candidate.SBQQ__SegmentStartDate__c;
        Date iStart = incumbent.SBQQ__SegmentStartDate__c;
        if (cStart != iStart) {
            if (cStart == null) {
                return false;
            }
            if (iStart == null) {
                return true;
            }
            return cStart > iStart;
        }
        Decimal cQty = candidate.SBQQ__SegmentQuantity__c == null ? -1 : candidate.SBQQ__SegmentQuantity__c;
        Decimal iQty = incumbent.SBQQ__SegmentQuantity__c == null ? -1 : incumbent.SBQQ__SegmentQuantity__c;
        return cQty > iQty;
    }

    private static String buildTermLabel(Contract c) {
        if (c.ContractTerm != null && c.ContractTerm > 0) {
            return String.valueOf(c.ContractTerm) + ' months';
        }
        if (c.StartDate != null && c.EndDate != null) {
            Integer months = c.StartDate.monthsBetween(c.EndDate);
            if (months != null && months >= 0) {
                return '~' + months + ' mo (from dates)';
            }
        }
        return '';
    }

    private static String truncateDescription(String description) {
        if (String.isBlank(description)) {
            return '';
        }
        String t = description.trim();
        if (t.length() <= DESCRIPTION_MAX_LEN) {
            return t;
        }
        return t.substring(0, DESCRIPTION_MAX_LEN) + '\u2026';
    }

    private static String truncateSpecialTerms(String specialTerms) {
        if (String.isBlank(specialTerms)) {
            return '';
        }
        String t = specialTerms.trim().replaceAll('\\s+', ' ');
        if (t.length() <= SPECIAL_TERMS_MAX_LEN) {
            return t;
        }
        return t.substring(0, SPECIAL_TERMS_MAX_LEN) + '\u2026';
    }

    /**
     * @description Per-contract subscription aggregates for list DTOs.
     *              productNameQuantities holds the summed current-year quantity per product
     *              (baseline + amendment deltas) after the current-year filter applied upstream.
     */
    private class SubscriptionAgg {
        Integer lineCount = 0;
        Map<String, Decimal> productNameQuantities = new Map<String, Decimal>();
        Decimal currentYearAcv;
        Decimal subscriptionTcv;

        List<String> getFormattedProductNames() {
            if (productNameQuantities.isEmpty()) return new List<String>();
            List<String> names = new List<String>(productNameQuantities.keySet());
            names.sort();
            List<String> formatted = new List<String>();
            for (String name : names) {
                Decimal qty = productNameQuantities.get(name);
                formatted.add(formatQuantity(qty) + 'x ' + name);
            }
            return formatted;
        }

        String buildProductSummary() {
            List<String> formatted = getFormattedProductNames();
            if (formatted.isEmpty()) return '';
            if (formatted.size() <= 3) return String.join(formatted, ', ');
            List<String> firstThree = new List<String>{ formatted[0], formatted[1], formatted[2] };
            Integer more = formatted.size() - 3;
            return String.join(firstThree, ', ') + ' (+' + more + ' more)';
        }
    }

    /**
     * @description Renders a quantity as an integer string when it has no fractional part
     *              (the common CPQ case — "15x" not "15.00x"), otherwise as its decimal form.
     */
    private static String formatQuantity(Decimal qty) {
        if (qty == null) return '0';
        if (qty == qty.setScale(0)) {
            return String.valueOf(qty.longValue());
        }
        return String.valueOf(qty);
    }

    /**
     * @description DTO representing a contract summary for list views and search results.
     */
    public class ContractResult {
        @AuraEnabled public String id;
        /** Standard Contract Name field */
        @AuraEnabled public String contractName;
        @AuraEnabled public String contractNumber;
        @AuraEnabled public String osaNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String accountName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Date companySignedDate;
        @AuraEnabled public String productSummary;
        @AuraEnabled public List<String> productNames;
        @AuraEnabled public Integer subscriptionCount;
        @AuraEnabled public Date customerSignedDate;
        @AuraEnabled public String termLabel;
        @AuraEnabled public String descriptionShort;
        @AuraEnabled public String specialTermsShort;
        @AuraEnabled public Decimal currentYearAcv;
        /** Sum of SBQQ__NetPrice__c × SBQQ__Quantity__c across latest-in-chain subscriptions.
         *  Used as the initial TCV display on a fresh amendment before the user touches quantity. */
        @AuraEnabled public Decimal subscriptionTcv;
        /** ISO 4217 currency code from Contract.CurrencyIsoCode (e.g. "USD", "EUR").
         *  Drives the currency display in every monetary cell of the OSA selector grid
         *  and is forwarded to the quote editor so the same code applies to all metric
         *  tiles and the MDQ term group's per-segment values. */
        @AuraEnabled public String currencyIsoCode;

        /**
         * @description Constructs a ContractResult from a Contract SObject and subscription aggregates.
         * @param c The Contract record with Account relationship loaded
         * @param agg Subscription aggregate for this contract (may be null)
         */
        public ContractResult(Contract c, SubscriptionAgg agg) {
            this.id = c.Id;
            this.contractName = c.Name;
            this.contractNumber = c.ContractNumber;
            this.osaNumber = c.OSA_Number__c;
            this.status = c.Status;
            this.startDate = c.StartDate;
            this.endDate = c.EndDate;
            this.currencyIsoCode = c.CurrencyIsoCode;
            this.accountName = c.Account != null ? c.Account.Name : '';
            this.ownerName = c.Owner != null ? c.Owner.Name : '';
            this.customerSignedDate = c.CustomerSignedDate;
            this.companySignedDate = c.CompanySignedDate;
            this.termLabel = buildTermLabel(c);
            this.descriptionShort = truncateDescription(c.Description);
            this.specialTermsShort = truncateSpecialTerms(c.SpecialTerms);
            if (agg != null) {
                this.subscriptionCount = agg.lineCount;
                this.productSummary = agg.buildProductSummary();
                this.productNames = agg.getFormattedProductNames();
                this.currentYearAcv = agg.currentYearAcv;
                this.subscriptionTcv = agg.subscriptionTcv;
            } else {
                this.subscriptionCount = 0;
                this.productSummary = '';
                this.productNames = new List<String>();
                this.currentYearAcv = null;
                this.subscriptionTcv = null;
            }
        }
    }

    /**
     * @description DTO representing detailed contract information including subscriptions.
     */
    public class ContractDetail {
        @AuraEnabled public String id;
        @AuraEnabled public String contractNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountId;
        @AuraEnabled public String productSummary;
        @AuraEnabled public List<SubscriptionInfo> subscriptions;
    }

    /**
     * @description DTO representing a single CPQ subscription line on a contract.
     */
    public class SubscriptionInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String productName;
        @AuraEnabled public String productId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal netPrice;
        @AuraEnabled public Decimal listPrice;
        @AuraEnabled public Integer segmentIndex;
        @AuraEnabled public String segmentLabel;
        @AuraEnabled public Date segmentStartDate;
        @AuraEnabled public Date segmentEndDate;

        /**
         * @description Constructs a SubscriptionInfo from a Subscription SObject.
         * @param sub The SBQQ__Subscription__c record
         */
        public SubscriptionInfo(SBQQ__Subscription__c sub) {
            this.id = sub.Id;
            this.productName = sub.SBQQ__ProductName__c;
            this.productId = sub.SBQQ__Product__c;
            this.quantity = sub.SBQQ__Quantity__c;
            this.netPrice = sub.SBQQ__NetPrice__c;
            this.listPrice = sub.SBQQ__ListPrice__c;
            this.segmentIndex = sub.SBQQ__SegmentIndex__c != null ? (Integer) sub.SBQQ__SegmentIndex__c : 0;
            this.segmentLabel = sub.SBQQ__SegmentLabel__c;
            this.segmentStartDate = sub.SBQQ__SegmentStartDate__c;
            this.segmentEndDate = sub.SBQQ__SegmentEndDate__c;
        }
    }
}