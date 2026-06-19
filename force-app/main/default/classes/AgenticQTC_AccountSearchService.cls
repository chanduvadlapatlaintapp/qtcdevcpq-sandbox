/**
 * @description Service for searching Salesforce Accounts using SOSL.
 *              Used by both the LWC account search component and the AI chat sidebar.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_AccountSearchService {

    private static final Integer MIN_SEARCH_LENGTH = 2;
    private static final Integer MAX_RESULTS = 20;
    // Mirrors AgenticQTC_ContractService.CONTRACT_SELECTION_STATUSES so the
    // account search and the downstream contract grid agree on eligibility.
    // Filtering on Status (the picklist label) — StatusCode only carries the
    // standard API code (Activated) and can't represent custom labels.
    private static final Set<String> CONTRACT_SELECTION_STATUSES = new Set<String>{
        'In Force', 'Partially Cancelled or superseded'
    };
    private static final String PRODUCT_TYPE_SOFTWARE = 'Software';

    /**
     * @description Searches accounts by name using SOSL, then keeps only those
     *              that have at least one eligible contract — i.e. Status is
     *              Activated or "Partially Cancelled or superseded", EndDate is
     *              today or later, and the contract holds at least one software
     *              subscription line (Product_Type__c = 'Software'). Same rules
     *              the contract grid will then apply when the user drills in,
     *              so the user never lands on an account with an empty list.
     * @param searchTerm The search string (minimum 2 characters)
     * @return List of AccountResult DTOs, in SOSL relevance order
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountResult> searchAccounts(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < MIN_SEARCH_LENGTH) {
            return new List<AccountResult>();
        }
        String sanitized = String.escapeSingleQuotes(searchTerm.trim());
        String soslQuery = 'FIND \'' + sanitized + '*\' IN NAME FIELDS RETURNING Account(Id, Name, BillingCity, BillingState WHERE Name != null) LIMIT ' + MAX_RESULTS;
        List<List<SObject>> results = Search.query(soslQuery);
        List<AccountResult> accounts = new List<AccountResult>();
        if (results.isEmpty() || results[0].isEmpty()) {
            return accounts;
        }

        Set<Id> candidateAccountIds = new Set<Id>();
        for (SObject obj : results[0]) {
            candidateAccountIds.add(((Account) obj).Id);
        }

        // Semi-join: among the SOSL candidates, find accounts that have at least
        // one eligible contract (right status + still active + has software
        // subscriptions). Aggregated by AccountId so we get distinct hits only.
        Set<Id> qualifiedAccountIds = new Set<Id>();
        for (AggregateResult ag : [
            SELECT AccountId
            FROM Contract
            WHERE AccountId IN :candidateAccountIds
            AND Status IN :CONTRACT_SELECTION_STATUSES
            AND EndDate >= TODAY
            AND Id IN (
                SELECT SBQQ__Contract__c
                FROM SBQQ__Subscription__c
                WHERE SBQQ__Contract__c != null
                AND SBQQ__Product__r.Product_Type__c = :PRODUCT_TYPE_SOFTWARE
            )
            WITH SECURITY_ENFORCED
            GROUP BY AccountId
        ]) {
            qualifiedAccountIds.add((Id) ag.get('AccountId'));
        }

        // Walk the original SOSL list so relevance ordering is preserved.
        for (SObject obj : results[0]) {
            Account acct = (Account) obj;
            if (qualifiedAccountIds.contains(acct.Id)) {
                accounts.add(new AccountResult(acct));
            }
        }
        return accounts;
    }

    /**
     * @description Lightweight DTO representing an Account search result.
     */
    public class AccountResult {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String location;

        /**
         * @description Constructs an AccountResult from an Account record.
         * @param acct The Account SObject; BillingCity and BillingState may be null.
         */
        public AccountResult(Account acct) {
            this.id = acct.Id;
            this.name = acct.Name;
            String city = acct.BillingCity != null ? acct.BillingCity : '';
            String state = acct.BillingState != null ? acct.BillingState : '';
            this.location = String.isNotBlank(city) && String.isNotBlank(state)
                ? city + ', ' + state
                : (city + state).trim();
        }
    }
}