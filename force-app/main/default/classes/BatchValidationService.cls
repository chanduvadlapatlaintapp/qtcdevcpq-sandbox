/**
 * @description Service class to handle validation operations for batch processing workflows.
 * @details Provides centralized validation functionality for account pairs, cleanup inputs, CSV rows, and general data integrity checks.
 *          Implements comprehensive validation logic with detailed error logging to support robust batch processing operations.
 *          Designed to ensure data quality and prevent processing errors in complex merge workflows.
 * @author Sahal Mohamed
 */
public with sharing class BatchValidationService {
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
     * @description Validates that an AccountDetail pair has valid accounts in the lookup map.
     * @param ad AccountDetail pair to validate.
     * @param accountMap Map of identifier to Account records.
     * @return True if both surviving and merge accounts are found, false otherwise.
     */
    public static Boolean isValidAccountPair(AccountMergeBatch.AccountDetail ad, Map<String, Account> accountMap) {
        if (!accountMap.containsKey(ad.survivingId)) {
            Nebula.Logger.error('Surviving account not found for identifier=' + ad.survivingId)
                .addTag('AccountMerge');
            return false;
        }
        
        if (!accountMap.containsKey(ad.mergeId)) {
            Nebula.Logger.error('Duplicate account not found for identifier=' + ad.mergeId)
                .addTag('AccountMerge');
            return false;
        }
        
        return true;
    }
    
    /**
     * @description Validates input parameters for cleanup operations.
     * @param survivingAccountIds Set of surviving account Ids.
     * @param mergeAccountIds Set of accounts to be merged.
     * @return True if inputs are valid for cleanup, false otherwise.
     */
    public static Boolean isValidCleanupInput(Set<Id> survivingAccountIds, Set<Id> mergeAccountIds) {
        return survivingAccountIds != null && !survivingAccountIds.isEmpty() && 
               mergeAccountIds != null && !mergeAccountIds.isEmpty();
    }
    
    /**
     * @description Validates that a CSV row has the expected number of columns.
     * @param cols List of parsed columns from a CSV row.
     * @param expectedColumns Expected number of columns.
     * @return True if the row has the expected number of columns, false otherwise.
     */
    public static Boolean isValidCsvRow(List<String> cols, Integer expectedColumns) {
        return cols != null && cols.size() == expectedColumns;
    }
    
    /**
     * @description Validates that a collection is not null or empty.
     * @param items Collection to validate.
     * @return True if collection has items, false if null or empty.
     */
    public static Boolean hasItems(List<Object> items) {
        return items != null && !items.isEmpty();
    }
    
    /**
     * @description Validates that a string value is not null or blank.
     * @param value String value to validate.
     * @return True if value is not blank, false otherwise.
     */
    public static Boolean isNotBlank(String value) {
        return String.isNotBlank(value);
    }
}