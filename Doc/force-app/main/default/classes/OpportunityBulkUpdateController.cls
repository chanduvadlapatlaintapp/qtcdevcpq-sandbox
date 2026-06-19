/**
 * @description  Apex controller for the Opportunity Bulk Update LWC.
 *               Provides filtered query and bulk save for Opportunity records.
 * @author       Yousef Alamin
 * @date         2026-03-17
 * @jira         BIZ-80919
 */
public with sharing class OpportunityBulkUpdateController {

    // =========================================================================
    // Constants
    // =========================================================================

    private static final Integer MAX_SAVE_RECORDS   = 200;
    private static final Integer RATE_LIMIT_MINUTES = 15;

    // =========================================================================
    // Inner Classes
    // =========================================================================

    /**
     * @description Per-record result returned after a bulk save operation.
     */
    public class SaveResult {
        @AuraEnabled public String  recordId     { get; set; }
        @AuraEnabled public Boolean success      { get; set; }
        @AuraEnabled public String  errorMessage { get; set; }

        public SaveResult(String recordId, Boolean success, String errorMessage) {
            this.recordId     = recordId;
            this.success      = success;
            this.errorMessage = errorMessage;
        }
    }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * @description Returns all active Users for Owner lookup picklists.
     * @return      List of Users with Id and Name.
     */
    @AuraEnabled(cacheable=true)
    public static List<User> getUsers() {
        return [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            ORDER BY Name ASC
            LIMIT 500
        ];
    }

    /**
     * @description Returns all available StageName picklist values from the schema.
     * @return      List of stage name strings.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getStageValues() {
        List<String> stages = new List<String>();
        for (Schema.PicklistEntry pe : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                stages.add(pe.getValue());
            }
        }
        return stages;
    }

    /**
     * @description Queries Opportunity records matching the supplied filters.
     *              Only Renewal and NextYear_MultiYear deal types are supported.
     * @param closeDateAfter   Minimum CloseDate (inclusive). Nullable.
     * @param createdDateAfter Minimum CreatedDate (inclusive). Nullable.
     * @param dealTypes        List of Deal_Type__c values to include.
     * @param stageName        StageName filter. Null = all stages.
     * @param nameSearch       Partial name match (LIKE %value%). Nullable.
     * @param opportunityId    Exact Opportunity Id filter. Nullable.
     * @return                 List of Opportunity records.
     */
    @AuraEnabled
    public static List<Opportunity> getOpportunities(
        Date closeDateAfter,
        DateTime createdDateAfter,
        List<String> dealTypes,
        String stageName,
        String nameSearch,
        String opportunityId
    ) {
        // Validate deal types
        Set<String> allowedTypes = new Set<String>{ 'Renewal', 'NextYear_MultiYear' };
        List<String> safeDealTypes = new List<String>();
        if (dealTypes != null) {
            for (String dt : dealTypes) {
                if (allowedTypes.contains(dt)) {
                    safeDealTypes.add(dt);
                }
            }
        }
        if (safeDealTypes.isEmpty()) {
            safeDealTypes.addAll(allowedTypes);
        }

        String query = 'SELECT Id, Name, Deal_Type__c, CloseDate, CreatedDate, '
            + 'StageName, OP4I_Deal_Owner__c, OP4I_Deal_Owner_Id__c, OP4I_Deal_Owner_Id__r.Name, '
            + 'OwnerId, Owner.Name '
            + 'FROM Opportunity '
            + 'WHERE Deal_Type__c IN :safeDealTypes';

        if (closeDateAfter != null) {
            query += ' AND CloseDate >= :closeDateAfter';
        }
        if (createdDateAfter != null) {
            query += ' AND CreatedDate >= :createdDateAfter';
        }
        if (String.isNotBlank(stageName)) {
            query += ' AND StageName = :stageName';
        }
        if (String.isNotBlank(nameSearch)) {
            nameSearch = '%' + String.escapeSingleQuotes(nameSearch) + '%';
            query += ' AND Name LIKE :nameSearch';
        }
        if (String.isNotBlank(opportunityId)) {
            query += ' AND Id = :opportunityId';
        }

        query += ' ORDER BY CloseDate DESC, Name ASC LIMIT 2000';

        return Database.query(query);
    }

    /**
     * @description Saves bulk updates to Opportunity records using partial-success DML.
     *              Enforces a 200-record maximum per save and a 15-minute per-user rate limit.
     *              Only CloseDate, StageName, OP4I_Deal_Owner__c, OP4I_Deal_Owner_Id__c,
     *              and OwnerId can be updated.
     * @param opportunitiesJson JSON string of records to update.
     * @return                  Per-record SaveResult list indicating success or failure.
     */
    @AuraEnabled
    public static List<SaveResult> saveOpportunities(String opportunitiesJson) {
        if (String.isBlank(opportunitiesJson)) {
            return new List<SaveResult>();
        }

        // ── Rate limit check ──────────────────────────────────────────────────
        BulkUpdateRateLimit__c rateLimit = BulkUpdateRateLimit__c.getInstance(UserInfo.getUserId());
        if (rateLimit != null && rateLimit.Last_Bulk_Save__c != null) {
            DateTime nextAllowed = rateLimit.Last_Bulk_Save__c.addMinutes(RATE_LIMIT_MINUTES);
            if (DateTime.now() < nextAllowed) {
                Long msRemaining   = nextAllowed.getTime() - DateTime.now().getTime();
                Long secsRemaining = msRemaining / 1000;
                Long minsLeft      = secsRemaining / 60;
                Long secsLeft      = Math.mod(secsRemaining, 60);
                throw new AuraHandledException(
                    'Rate limit active. Please wait '
                    + minsLeft + ' min ' + secsLeft + ' sec before saving again.'
                );
            }
        }

        // ── Parse payload ─────────────────────────────────────────────────────
        List<Object> rawList = (List<Object>) JSON.deserializeUntyped(opportunitiesJson);

        // ── 200-record cap ────────────────────────────────────────────────────
        if (rawList.size() > MAX_SAVE_RECORDS) {
            throw new AuraHandledException(
                'Bulk save is limited to ' + MAX_SAVE_RECORDS + ' records at a time. '
                + 'You attempted to save ' + rawList.size() + ' records. '
                + 'Please reduce your selection and try again.'
            );
        }

        Set<String> editableFields = new Set<String>{
            'CloseDate', 'StageName', 'OP4I_Deal_Owner__c',
            'OP4I_Deal_Owner_Id__c', 'OwnerId'
        };

        List<Opportunity> toUpdate   = new List<Opportunity>();
        List<String>      orderedIds = new List<String>();

        for (Object item : rawList) {
            Map<String, Object> fields = (Map<String, Object>) item;
            String recId = (String) fields.get('Id');
            if (String.isBlank(recId)) {
                continue;
            }

            Opportunity opp       = new Opportunity(Id = recId);
            Boolean     hasChanges = false;

            for (String fieldName : editableFields) {
                if (fields.containsKey(fieldName)) {
                    Object val = fields.get(fieldName);
                    if (fieldName == 'CloseDate' && val != null) {
                        opp.CloseDate = Date.valueOf((String) val);
                    } else {
                        opp.put(fieldName, val);
                    }
                    hasChanges = true;
                }
            }

            if (hasChanges) {
                toUpdate.add(opp);
                orderedIds.add(recId);
            }
        }

        if (toUpdate.isEmpty()) {
            return new List<SaveResult>();
        }

        // ── Partial-success DML ───────────────────────────────────────────────
        Database.SaveResult[] dmlResults = Database.update(toUpdate, false);

        List<SaveResult> results    = new List<SaveResult>();
        Boolean          anySuccess = false;

        for (Integer i = 0; i < dmlResults.size(); i++) {
            Database.SaveResult sr = dmlResults[i];
            if (sr.isSuccess()) {
                anySuccess = true;
                results.add(new SaveResult(orderedIds[i], true, null));
            } else {
                String errMsg = sr.getErrors()[0].getMessage();
                results.add(new SaveResult(orderedIds[i], false, errMsg));
            }
        }

        // ── Update rate limit timestamp (only when at least one record saved) ─
        if (anySuccess) {
            BulkUpdateRateLimit__c limitRecord = BulkUpdateRateLimit__c.getInstance(UserInfo.getUserId());
            if (limitRecord == null) {
                limitRecord = new BulkUpdateRateLimit__c(SetupOwnerId = UserInfo.getUserId());
            }
            limitRecord.Last_Bulk_Save__c = DateTime.now();
            upsert limitRecord;
        }

        return results;
    }
}