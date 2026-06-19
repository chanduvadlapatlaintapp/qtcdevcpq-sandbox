/**
 * @description Helper class that encapsulates the core account merging logic for batch processing operations.
 * @details This helper handles CSV processing, account validation, merge execution, relation cleanup, and result reporting.
 *          Designed to be stateful to accumulate results across batch chunks and provide comprehensive logging throughout
 *          the merge process. Serves as the primary business logic component for the AccountMergeBatch, implementing
 *          complex merge workflows while maintaining separation of concerns and high testability.
 */
public with sharing class AccountMergerHelper {
    
    /***********************************************************************************************
    *
    * Properties
    *
    ***********************************************************************************************/
    private AccountMergeBatch.RecordIdentifier recordIdentity;
    private String fileName;
    private List<String> mergeErrorRows;
    private List<String> mergeSuccessRows;
    
    /***********************************************************************************************
    *
    * Constructor
    *
    ***********************************************************************************************/
    /**
     * @description Initializes the helper with required parameters.
     * @param fileName CSV file name to process.
     * @param recordIdentity Record identifier type.
     * @param mergeErrorRows List to collect error rows.
     * @param mergeSuccessRows List to collect success rows.
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public AccountMergerHelper(String fileName, AccountMergeBatch.RecordIdentifier recordIdentity, 
                              List<String> mergeErrorRows, List<String> mergeSuccessRows) {
        this.fileName = fileName;
        this.recordIdentity = recordIdentity;
        this.mergeErrorRows = mergeErrorRows;
        this.mergeSuccessRows = mergeSuccessRows;
        
        Nebula.Logger.info('AccountMergerHelper initialized with fileName=' + fileName + ', recordIdentity=' + recordIdentity)
            .addTag('AccountMerge');
    }
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
     * @description Processes CSV file and returns account detail pairs for batch processing.
     * @return List of AccountDetail pairs from the CSV file.
     */
    public List<AccountMergeBatch.AccountDetail> loadAccountPairs() {
        ContentVersion csvFile = BatchFileService.fetchCsvFile(fileName);
        if (csvFile == null) {
            Nebula.Logger.info('No CSV file found for fileName=' + fileName)
                .addTag('AccountMerge');
            return new List<AccountMergeBatch.AccountDetail>();
        }
        
        String fileData = csvFile.VersionData.toString();
        if (!BatchValidationService.isNotBlank(fileData)) {
            Nebula.Logger.info('CSV file is empty for fileName=' + fileName)
                .addTag('AccountMerge');
            return new List<AccountMergeBatch.AccountDetail>();
        }
        
        return parseAccountPairs(fileData);
    }
    
    /**
     * @description Processes a batch chunk of account pairs, performing merges and capturing results.
     * @param accountDetailList List of account pairs to process in this chunk.
     */
    public void processAccountMerges(List<AccountMergeBatch.AccountDetail> accountDetailList) {
        if (accountDetailList == null || accountDetailList.isEmpty()) {
            Nebula.Logger.info('No account pairs to process in this chunk')
                .addTag('AccountMerge');
            return;
        }
        
        Nebula.Logger.info('Processing account merge chunk; pairs=' + accountDetailList.size())
            .addTag('AccountMerge');
        
        Set<String> accountIds = collectAccountIdentifiers(accountDetailList);
        Map<String, Account> accountMap = AccountLookupService.buildAccountMap(accountIds, recordIdentity);
        
        if (accountMap.isEmpty()) {
            Nebula.Logger.info('No valid accounts found for identifiers; skipping chunk')
                .addTag('AccountMerge');
            return;
        }
        
        MergeContext ctx = prepareMergeContext(accountDetailList, accountMap);
        executeAccountMerges(ctx);
        
        Nebula.Logger.info('Chunk processed; successes=' + mergeSuccessRows.size() + ', errors=' + mergeErrorRows.size())
            .addTag('AccountMerge');
    }
    
    /**
     * @description Finalizes processing by creating result files and sending email notifications.
     * @param bc Batchable context for email recipient resolution.
     */
    public void finalizeResults(Database.BatchableContext bc) {
        List<String> resultSummaries = new List<String>();
        
        if (!mergeErrorRows.isEmpty()) {
            resultSummaries.add(createErrorResultFile());
        }
        
        if (!mergeSuccessRows.isEmpty()) {
            resultSummaries.add(createSuccessResultFile());
        }
        
        if (!resultSummaries.isEmpty()) {
            BatchEmailService.sendResultEmail(bc, 'Account Merge Results', resultSummaries);
            Nebula.Logger.info('Results finalized and emailed; files=' + resultSummaries.size())
                .addTag('AccountMerge');
        } else {
            Nebula.Logger.info('No results to report')
                .addTag('AccountMerge');
        }
    }
    
    
    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    /**
     * @description Parses CSV file data into a list of AccountDetail pairs.
     * @param fileData The CSV file content as a string to parse.
     * @return List of AccountDetail objects parsed from the CSV data.
     */
    private List<AccountMergeBatch.AccountDetail> parseAccountPairs(String fileData) {
        List<AccountMergeBatch.AccountDetail> accountDetailList = new List<AccountMergeBatch.AccountDetail>();
        
        List<String> rows = CsvUtilityService.splitIntoRows(fileData);
        Nebula.Logger.info('Parsing CSV rows; count=' + rows.size())
            .addTag('AccountMerge');
        
        for (String row : rows) {
            AccountMergeBatch.AccountDetail detail = parseAccountDetailRow(row);
            if (detail != null) {
                accountDetailList.add(detail);
            }
        }
        
        Nebula.Logger.info('Parsed account pairs; valid pairs=' + accountDetailList.size())
            .addTag('AccountMerge');
        return accountDetailList;
    }
    
    /**
     * @description Parses a single CSV row into an AccountDetail object.
     * @param row CSV row string to parse.
     * @return AccountDetail object if row has valid format, null otherwise.
     */
    private AccountMergeBatch.AccountDetail parseAccountDetailRow(String row) {
        List<String> cols = CsvUtilityService.parseRow(row);
        
        if (BatchValidationService.isValidCsvRow(cols, 2)) {
            return new AccountMergeBatch.AccountDetail(cols[0], cols[1]);
        }
        
        return null;
    }
    
    /**
     * @description Collects all unique account identifiers from the provided account detail pairs.
     * @param accountDetailList List of account pairs to extract identifiers from.
     * @return Set of unique account identifier strings (both surviving and merge identifiers).
     */
    private Set<String> collectAccountIdentifiers(List<AccountMergeBatch.AccountDetail> accountDetailList) {
        Set<String> accountIds = new Set<String>();
        
        for (AccountMergeBatch.AccountDetail ad : accountDetailList) {
            accountIds.add(ad.survivingId);
            accountIds.add(ad.mergeId);
        }
        
        Nebula.Logger.debug('Collected unique identifiers; count=' + accountIds.size())
            .addTag('AccountMerge');
        return accountIds;
    }
    
    /**
     * @description Validates account pairs and builds a MergeContext with surviving/duplicate IDs and mappings.
     * @param accountDetailList List of account pairs to validate and process.
     * @param accountMap Map of identifier to Account records for validation.
     * @return MergeContext containing validated account IDs and merge mappings.
     */
    private MergeContext prepareMergeContext(List<AccountMergeBatch.AccountDetail> accountDetailList, Map<String, Account> accountMap) {
        MergeContext ctx = new MergeContext();
        
        for (AccountMergeBatch.AccountDetail ad : accountDetailList) {
            if (BatchValidationService.isValidAccountPair(ad, accountMap)) {
                Id survivingId = accountMap.get(ad.survivingId).Id;
                Id mergeId = accountMap.get(ad.mergeId).Id;
                
                ctx.survivingAccountIds.add(survivingId);
                ctx.mergeAccountIds.add(mergeId);
                ctx.mergeToSurvivingMap.put(mergeId, survivingId);
            }
        }
        
        Nebula.Logger.info('Prepared merge context; valid pairs=' + ctx.mergeToSurvivingMap.size())
            .addTag('AccountMerge');
        return ctx;
    }
    
    /**
     * @description Executes the complete account merge process including cleanup and DML operations.
     * @param ctx MergeContext containing the accounts to merge and their relationships.
     */
    private void executeAccountMerges(MergeContext ctx) {
        if (ctx.mergeToSurvivingMap.isEmpty()) {
            return;
        }
        
        cleanupAccountContactRelations(ctx);
        performAccountMerges(ctx.mergeToSurvivingMap);
    }
    
    /**
     * @description Cleans up conflicting AccountContactRelation records before performing merges.
     * @param ctx MergeContext containing account IDs and mapping information.
     */
    private void cleanupAccountContactRelations(MergeContext ctx) {
        if (ctx.survivingAccountIds.isEmpty()) {
            return;
        }
        
        ContactRelationCleaner cleaner = new ContactRelationCleaner();
        cleaner.cleanup(ctx.survivingAccountIds, ctx.mergeAccountIds, ctx.mergeToSurvivingMap);
    }
    
    /**
     * @description Performs DML merge operations for each duplicate-to-surviving account pair.
     *              Note: Merge operations must be performed individually to handle errors per record
     *              and to respect Salesforce's merge governor limits (3 records per merge operation).
     * @param mergeToSurvivingMap Map of duplicate Account ID to surviving Account ID.
     */
    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private void performAccountMerges(Map<Id, Id> mergeToSurvivingMap) {
        for (Id mergeAccountId : mergeToSurvivingMap.keySet()) {
            Id survivingAccountId = mergeToSurvivingMap.get(mergeAccountId);
            
            try {
                merge new Account(Id = survivingAccountId) new Account(Id = mergeAccountId);
                recordMergeSuccess(survivingAccountId, mergeAccountId);
            } catch (Exception ex) {
                recordMergeError(survivingAccountId, mergeAccountId, ex);
            }
        }
    }
    
    /**
     * @description Records a successful merge operation to the success results list.
     * @param survivingAccountId ID of the surviving account.
     * @param mergeAccountId ID of the merged (duplicate) account.
     */
    private void recordMergeSuccess(Id survivingAccountId, Id mergeAccountId) {
        String successRow = CsvUtilityService.csvEscape(String.valueOf(survivingAccountId)) + ',' + 
                           CsvUtilityService.csvEscape(String.valueOf(mergeAccountId));
        mergeSuccessRows.add(successRow);
    }
    
    /**
     * @description Records a failed merge operation to the error results list and logs the error.
     * @param survivingAccountId ID of the surviving account.
     * @param mergeAccountId ID of the duplicate account that failed to merge.
     * @param ex Exception that occurred during the merge attempt.
     */
    private void recordMergeError(Id survivingAccountId, Id mergeAccountId, Exception ex) {
        Nebula.Logger.error('Account merge failed; survivingId=' + survivingAccountId + ', mergeId=' + mergeAccountId + ', error=' + ex.getMessage())
            .setRecordId(survivingAccountId)
            .addTag('AccountMerge');
        
        String errorRow = CsvUtilityService.csvEscape(String.valueOf(survivingAccountId)) + ',' + 
                         CsvUtilityService.csvEscape(String.valueOf(mergeAccountId)) + ',' +
                         CsvUtilityService.csvEscape(ex.getMessage());
        mergeErrorRows.add(errorRow);
    }
    
    /**
     * @description Creates a CSV file containing merge error records and returns a formatted summary.
     * @return Summary string with file information and Lightning URL.
     */
    private String createErrorResultFile() {
        String title = 'AccountMergeExceptions_' + Datetime.now().format('yyyyMMdd_HHmmss');
        String csvContent = CsvUtilityService.createCsvContent('MasterAccountId,DuplicateAccountId,ErrorMessage', mergeErrorRows);
        String fileUrl = BatchFileService.createCsvFile(title, csvContent);
        
        return BatchFileService.createResultSummary('Exceptions', title, mergeErrorRows.size(), fileUrl);
    }
    
    /**
     * @description Creates a CSV file containing successful merge records and returns a formatted summary.
     * @return Summary string with file information and Lightning URL.
     */
    private String createSuccessResultFile() {
        String title = 'AccountMergeSuccesses_' + Datetime.now().format('yyyyMMdd_HHmmss');
        String csvContent = CsvUtilityService.createCsvContent('MasterAccountId,DuplicateAccountId', mergeSuccessRows);
        String fileUrl = BatchFileService.createCsvFile(title, csvContent);
        
        return BatchFileService.createResultSummary('Successes', title, mergeSuccessRows.size(), fileUrl);
    }
    
    
    /***********************************************************************************************
    *
    * Inner Helper Classes
    *
    ***********************************************************************************************/
    /**
     * @description Aggregates IDs and maps needed to perform merges within a batch chunk.
     */
    private class MergeContext {
        public Set<Id> survivingAccountIds = new Set<Id>();
        public Set<Id> mergeAccountIds = new Set<Id>();
        public Map<Id, Id> mergeToSurvivingMap = new Map<Id, Id>();
    }
    
    /**
     * @description Handles cleanup of AccountContactRelation records to prevent merge conflicts.
     */
    private with sharing class ContactRelationCleaner {
        /**
         * @description Cleans up AccountContactRelation records to prevent conflicts during account merges.
         * @param survivingAccountIds Set of account IDs that will remain after the merge.
         * @param mergeAccountIds Set of account IDs that will be merged (deleted).
         * @param mergeToSurvivingMap Map of merge account ID to surviving account ID.
         */
        public void cleanup(Set<Id> survivingAccountIds, Set<Id> mergeAccountIds, Map<Id, Id> mergeToSurvivingMap) {
            if (!BatchValidationService.isValidCleanupInput(survivingAccountIds, mergeAccountIds)) {
                return;
            }
            
            Map<String, AccountContactRelation> existingRelations = buildExistingRelationsMap(survivingAccountIds);
            Set<Id> contactIds = extractContactIds(existingRelations);
            
            if (contactIds.isEmpty()) {
                return;
            }
            
            List<AccountContactRelation> toDelete = collectRelationsToDelete(mergeAccountIds, contactIds, mergeToSurvivingMap, existingRelations);
            
            if (!toDelete.isEmpty()) {
                deleteRelations(toDelete);
            }
        }
        
        /**
         * @description Builds a map of existing AccountContactRelation records for surviving accounts.
         * @param survivingAccountIds Set of account IDs that will survive the merge.
         * @return Map keyed by 'AccountId-ContactId' containing existing relations.
         */
        private Map<String, AccountContactRelation> buildExistingRelationsMap(Set<Id> survivingAccountIds) {
            Map<String, AccountContactRelation> existingMap = new Map<String, AccountContactRelation>();
            
            for (AccountContactRelation acr : [
                SELECT Id, AccountId, ContactId, IsDirect
                FROM AccountContactRelation
                WHERE AccountId IN :survivingAccountIds
            ]) {
                existingMap.put(acr.AccountId + '-' + acr.ContactId, acr);
            }
            
            return existingMap;
        }
        
        /**
         * @description Extracts contact IDs from existing AccountContactRelation records.
         * @param existingRelations Map of existing relations keyed by account-contact combination.
         * @return Set of contact IDs involved in existing relations.
         */
        private Set<Id> extractContactIds(Map<String, AccountContactRelation> existingRelations) {
            Set<Id> contactIds = new Set<Id>();
            
            for (AccountContactRelation acr : existingRelations.values()) {
                contactIds.add(acr.ContactId);
            }
            
            return contactIds;
        }
        
        /**
         * @description Identifies AccountContactRelation records that must be deleted to prevent merge conflicts.
         * @param mergeAccountIds Set of account IDs being merged.
         * @param contactIds Set of contact IDs involved in relations.
         * @param mergeToSurvivingMap Map from merged account ID to surviving account ID.
         * @param existingRelations Map of existing relations on surviving accounts.
         * @return List of relations to delete before merge.
         */
        @SuppressWarnings('PMD.ExcessiveParameterList')
        private List<AccountContactRelation> collectRelationsToDelete(Set<Id> mergeAccountIds, Set<Id> contactIds,
                                                                     Map<Id, Id> mergeToSurvivingMap, Map<String, AccountContactRelation> existingRelations) {
            List<AccountContactRelation> toDelete = new List<AccountContactRelation>();
            
            for (AccountContactRelation acr : [
                SELECT Id, AccountId, ContactId, IsDirect
                FROM AccountContactRelation
                WHERE AccountId IN :mergeAccountIds AND ContactId IN :contactIds
            ]) {
                AccountContactRelation relationToDelete = determineRelationToDelete(acr, mergeToSurvivingMap, existingRelations);
                if (relationToDelete != null) {
                    toDelete.add(relationToDelete);
                }
            }
            
            return toDelete;
        }
        
        /**
         * @description Determines which AccountContactRelation should be deleted based on direct/indirect status.
         * @param duplicateRelation The relation on the account being merged.
         * @param mergeToSurvivingMap Map to resolve surviving account for the duplicate.
         * @param existingMap Map of existing relations on surviving accounts.
         * @return The relation to delete, or null if no deletion needed.
         */
        /**
         * @description Determines which AccountContactRelation should be deleted based on direct/indirect status.
         * @param duplicateRelation The relation on the account being merged.
         * @param mergeToSurvivingMap Map to resolve surviving account for the duplicate.
         * @param existingMap Map of existing relations on surviving accounts.
         * @return The relation to delete, or null if no deletion needed.
         */
        private AccountContactRelation determineRelationToDelete(AccountContactRelation duplicateRelation, 
                                                               Map<Id, Id> mergeToSurvivingMap,
                                                               Map<String, AccountContactRelation> existingMap) {
            Id survivingAccountId = mergeToSurvivingMap.get(duplicateRelation.AccountId);
            if (survivingAccountId == null) {
                return null;
            }
            
            String relationKey = survivingAccountId + '-' + duplicateRelation.ContactId;
            if (!existingMap.containsKey(relationKey)) {
                return null;
            }
            
            // If duplicate relation is indirect, delete it; if direct, delete existing relation
            return duplicateRelation.IsDirect == false ? duplicateRelation : existingMap.get(relationKey);
        }
        
        /**
         * @description Performs DML delete operation on the specified AccountContactRelation records.
         * @param toDelete List of relations to delete.
         */
        /**
         * @description Performs DML delete operation on the specified AccountContactRelation records.
         * @param toDelete List of relations to delete.
         */
        private void deleteRelations(List<AccountContactRelation> toDelete) {
            try {
                Nebula.Logger.info('Deleting conflicting AccountContactRelation records; count=' + toDelete.size())
                    .addTag('AccountMerge');
                delete toDelete;
            } catch (Exception e) {
                Nebula.Logger.error('Failed to delete AccountContactRelation records: ' + e.getMessage())
                    .addTag('AccountMerge');
            }
        }
    }
}