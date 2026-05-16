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
    private static final Integer MAX_SEARCH_RESULTS = 20;
    private static final Integer DESCRIPTION_MAX_LEN = 120;
    private static final Integer SPECIAL_TERMS_MAX_LEN = 100;

    /**
     * @description Gets all activated contracts for an account.
     * @param accountId The Account record Id
     * @return List of ContractResult DTOs
     */
    /** Not cacheable so the OSA list always reflects newly created/activated contracts after seeding. */
    @AuraEnabled
    public static List<ContractResult> getActiveContracts(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException(ERR_ACCOUNT_REQUIRED);
        }
        List<Contract> contracts = [
            SELECT Id, Name, ContractNumber, OSA_Number__c, Status, StartDate, EndDate,
                   Account.Name, CustomerSignedId, CustomerSignedDate,
                   CompanySignedDate, ContractTerm, Description, SpecialTerms,
                   Owner.Name
            FROM Contract
            WHERE AccountId = :accountId
            AND StatusCode = :STATUS_CODE_ACTIVATED
            AND EndDate >= TODAY
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
     * @description Counts subscription lines and collects distinct product names per contract.
     */
    private static Map<Id, SubscriptionAgg> buildSubscriptionAggregates(Set<Id> contractIds) {
        Map<Id, SubscriptionAgg> result = new Map<Id, SubscriptionAgg>();
        if (contractIds == null || contractIds.isEmpty()) {
            return result;
        }
        for (Id cid : contractIds) {
            result.put(cid, new SubscriptionAgg());
        }
        for (SBQQ__Subscription__c sub : [
            SELECT SBQQ__Contract__c, SBQQ__ProductName__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c IN :contractIds
        ]) {
            SubscriptionAgg agg = result.get(sub.SBQQ__Contract__c);
            if (agg == null) {
                continue;
            }
            agg.lineCount++;
            if (String.isNotBlank(sub.SBQQ__ProductName__c)) {
                String pName = sub.SBQQ__ProductName__c;
                Integer existing = agg.productNameCounts.get(pName);
                agg.productNameCounts.put(pName, existing == null ? 1 : existing + 1);
            }
        }
        return result;
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
     */
    private class SubscriptionAgg {
        Integer lineCount = 0;
        Map<String, Integer> productNameCounts = new Map<String, Integer>();

        List<String> getFormattedProductNames() {
            if (productNameCounts.isEmpty()) return new List<String>();
            List<String> names = new List<String>(productNameCounts.keySet());
            names.sort();
            List<String> formatted = new List<String>();
            for (String name : names) {
                Integer cnt = productNameCounts.get(name);
                formatted.add(cnt > 1 ? (cnt + 'X ' + name) : name);
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
            } else {
                this.subscriptionCount = 0;
                this.productSummary = '';
                this.productNames = new List<String>();
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