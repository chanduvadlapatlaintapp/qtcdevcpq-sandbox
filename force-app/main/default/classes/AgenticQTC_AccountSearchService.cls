/**
 * @description Service for searching Salesforce Accounts using SOSL.
 *              Used by both the LWC account search component and the AI chat sidebar.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_AccountSearchService {

    private static final Integer MIN_SEARCH_LENGTH = 2;
    private static final Integer MAX_RESULTS = 20;

    /**
     * @description Searches accounts by name using SOSL.
     * @param searchTerm The search string (minimum 2 characters)
     * @return List of AccountResult DTOs
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
        if (!results.isEmpty()) {
            for (SObject obj : results[0]) {
                accounts.add(new AccountResult((Account) obj));
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