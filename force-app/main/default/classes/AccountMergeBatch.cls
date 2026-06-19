/**
 * @description Batch class to merge duplicate Accounts based on identifiers provided in a CSV file stored in Salesforce Files.
 * @details Reads a CSV by the given file title, parses pairs of surviving and duplicate account identifiers (either `Id` or `IntApp_Account_Number__c`),
 *          validates and maps Accounts, removes conflicting `AccountContactRelation` records when appropriate, attempts merges, and captures both success
 *          and exception outcomes. Results are written back to Salesforce Files as CSVs and links are emailed to the batch executor. Logging is performed
 *          via `Nebula.Logger` with persistence at logical checkpoints. Implements `Database.Stateful` to accumulate results across batch chunks.
 *
 * @example
 * // CSV File Format (upload to Salesforce Files with a unique title):
 * // -----------------------------------------------------------------
 * // SurvivingId,MergeId
 * // 001XXXXXXXXXXXX,001YYYYYYYYYYYY
 * // 001AAAAAAAAAA,001BBBBBBBBBBBB
 * //
 * // OR when using IntApp Account Numbers:
 * // SurvivingAccountNumber,MergeAccountNumber
 * // ACC-001,ACC-002
 * // ACC-003,ACC-004
 * //
 * // Sample Execution (Anonymous Apex):
 * // ----------------------------------
 * // Using Salesforce Account IDs:
 * // AccountMergeBatch batch = new AccountMergeBatch('AccountMergeFile', AccountMergeBatch.RecordIdentifier.ID);
 * // Database.executeBatch(batch, 1);
 * //
 * // Using IntApp Account Numbers:
 * // AccountMergeBatch batch = new AccountMergeBatch('AccountMergeFile', AccountMergeBatch.RecordIdentifier.INTAPPACCOUNTNUMBER);
 * // Database.executeBatch(batch, 1);
 * //
 * // Note: Batch size of 1 is recommended for account merges to avoid governor limits.
 */
public with sharing class AccountMergeBatch implements Database.Batchable<AccountMergeBatch.AccountDetail>, Database.Stateful {
    
    /***********************************************************************************************
    *
    * Properties
    *
    ***********************************************************************************************/
    public enum RecordIdentifier {
        ID,
        INTAPPACCOUNTNUMBER
    }
    
    private RecordIdentifier recordIdentity;
    private String fileName;
    private List<String> mergeErrorRows = new List<String>();
    private List<String> mergeSuccessRows = new List<String>();
    private AccountMergerHelper helper;
    
    /***********************************************************************************************
    *
    * Constructor
    *
    ***********************************************************************************************/
    /**
     * @description Initializes the batch with the CSV file title and the record identifier mode.
     * @param fileName Title of the CSV file in Salesforce Files to read.
     * @param recordIdentity Record identifier type (`RecordIdentifier.ID` or `RecordIdentifier.INTAPPACCOUNTNUMBER`).
     */
    public AccountMergeBatch(String fileName, RecordIdentifier recordIdentity) {
        this.recordIdentity = recordIdentity;
        this.fileName = fileName;
        this.helper = new AccountMergerHelper(fileName, recordIdentity, mergeErrorRows, mergeSuccessRows);
        
        Nebula.Logger.info('AccountMergeBatch initialized with fileName=' + fileName + ', recordIdentity=' + recordIdentity)
            .addTag('AccountMerge');
        Nebula.Logger.saveLog();
    }
    
    /***********************************************************************************************
    *
    * Batch Methods
    *
    ***********************************************************************************************/
    /**
     * @description Loads and parses the CSV from Salesforce Files and builds the iterable of account identifier pairs.
     * @param bc Batchable context.
     * @return Iterable of `AccountDetail` pairs constructed from the CSV rows.
     */
    public Iterable<AccountDetail> start(Database.BatchableContext bc) {
        List<AccountDetail> accountDetailList = helper.loadAccountPairs();
        
        Nebula.Logger.info('Batch start completed; account pairs loaded=' + accountDetailList.size())
            .addTag('AccountMerge');
        Nebula.Logger.saveLog();
        
        return accountDetailList;
    }
    
    /**
     * @description Executes account merge processing for the provided chunk of pairs. Delegates to helper for processing.
     * @param bc Batchable context.
     * @param accountDetailList List of `AccountDetail` pairs derived from the CSV.
     */
    public void execute(Database.BatchableContext bc, List<AccountDetail> accountDetailList) {
        helper.processAccountMerges(accountDetailList);
        Nebula.Logger.saveLog();
    }
    
    /**
     * @description Finalizes the batch run by delegating to helper for result processing and email notifications.
     * @param bc Batchable context.
     */
    public void finish(Database.BatchableContext bc) {
        try {
            helper.finalizeResults(bc);
        } catch (Exception e) {
            Nebula.Logger.error('Failed in finish() while processing results: ' + e.getMessage())
                .addTag('AccountMerge');
        }
        
        Nebula.Logger.info('Batch finish completed')
            .addTag('AccountMerge');
        Nebula.Logger.saveLog();
    }
    
    /***********************************************************************************************
    *
    * Data Structures
    *
    ***********************************************************************************************/
    /**
     * @description Data Transfer Object representing a merge instruction consisting of a surviving/master identifier and a duplicate identifier.
     */
    public without sharing class AccountDetail {
        public String survivingId;
        public String mergeId;
        
        /**
         * @description Constructs an AccountDetail instance with the specified identifiers.
         * @param survivingId The surviving account identifier (ID or IntApp_Account_Number__c).
         * @param mergeId The merge/duplicate account identifier (ID or IntApp_Account_Number__c).
         */
        public AccountDetail(String survivingId, String mergeId) {
            this.survivingId = survivingId;
            this.mergeId = mergeId;
        }
    }
}