/**
 * @description Service class to handle Account lookup operations with different identifier types for batch processing.
 * @details Provides centralized Account query functionality supporting both Id and IntApp_Account_Number__c identifiers.
 *          Optimizes database queries by building lookup maps for efficient resolution during merge operations.
 *          Designed to support flexible account identification strategies in batch merge workflows.
 */
public with sharing class AccountLookupService {
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
     * @description Builds a lookup map from identifiers to Account records based on the specified identifier type.
     * @param accountIds Set of account identifiers to look up.
     * @param identifierType Type of identifier (ID or INTAPPACCOUNTNUMBER).
     * @return Map keyed by identifier string to Account records.
     */
    public static Map<String, Account> buildAccountMap(Set<String> accountIds, AccountMergeBatch.RecordIdentifier identifierType) {
        Map<String, Account> accountMap = new Map<String, Account>();
        
        if (accountIds == null || accountIds.isEmpty()) {
            return accountMap;
        }
        
        if (AccountMergeBatch.RecordIdentifier.ID == identifierType) {
            return buildMapById(accountIds);
        } else {
            return buildMapByAccountNumber(accountIds);
        }
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Builds a lookup map from Account Ids to Account records.
     * @param accountIds Set of Account Ids.
     * @return Map keyed by Account Id.
     */
    private static Map<String, Account> buildMapById(Set<String> accountIds) {
        Map<String, Account> accountMap = new Map<String, Account>();
        for (Account a : [SELECT Id, Name, IntApp_Account_Number__c FROM Account WHERE Id IN :accountIds]) {
            accountMap.put(a.Id, a);
        }
        return accountMap;
    }
    
    /**
     * @description Builds account map using IntApp_Account_Number__c as the key.
     * @param accountNumbers Set of Account Numbers.
     * @return Map keyed by Account Number.
     */
    private static Map<String, Account> buildMapByAccountNumber(Set<String> accountNumbers) {
        Map<String, Account> accountMap = new Map<String, Account>();
        for (Account a : [SELECT Id, Name, IntApp_Account_Number__c FROM Account WHERE IntApp_Account_Number__c IN :accountNumbers]) {
            accountMap.put(a.IntApp_Account_Number__c, a);
        }
        return accountMap;
    }
}