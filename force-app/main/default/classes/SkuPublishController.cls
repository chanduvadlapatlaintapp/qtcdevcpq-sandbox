/**
 * @description Controller for the Publish Changes feature in the SKU Management App.
 *              Provides methods to manage change sets (staging sessions) and submit
 *              them for review/processing.
 *
 * @author      Sahal Mohamed
 * @date        2026-03-10
 * @jira        BIZ-80418
 */
public with sharing class SkuPublishController {

    // ─── Public Constants ────────────────────────────────────────────────

    private static final Integer RECENT_DAYS = 30;

    // ─── Wrapper Classes ─────────────────────────────────────────────────

    /**
     * @description Lightweight wrapper for change set (session) list display.
     */
    public class ChangeSetSummary {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdByName;
        @AuraEnabled public Integer entryCount;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String finalizedBy;
    }

    /**
     * @description Wrapper for individual change entries within a change set.
     */
    public class ChangeEntry {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String recordName;
        @AuraEnabled public String operationType;
        @AuraEnabled public String gearsetExternalId;
    }

    /**
     * @description Wrapper for the detail view of a change set.
     */
    public class ChangeSetDetail {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String finalizedBy;
        @AuraEnabled public List<ChangeEntry> entries;
    }

    // ─── Public AuraEnabled Methods ──────────────────────────────────────

    /**
     * @description Returns recent change sets for the current user (last 30 days).
     * @return List of ChangeSetSummary wrappers
     */
    @AuraEnabled(cacheable=true)
    public static List<ChangeSetSummary> getChangeSets() {
        Date cutoff = Date.today().addDays(-RECENT_DAYS);

        List<SKU_Config_Staging__c> sessions = [
            SELECT Id, Name, Status__c, CreatedDate, CreatedBy.Name,
                   Error_Message__c, Finalized_By__c,
                   (SELECT Id FROM Staging_Entries__r)
            FROM SKU_Config_Staging__c
            WHERE CreatedDate >= :cutoff
              AND CreatedById = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        List<ChangeSetSummary> result = new List<ChangeSetSummary>();
        for (SKU_Config_Staging__c session : sessions) {
            ChangeSetSummary summary = new ChangeSetSummary();
            summary.recordId = session.Id;
            summary.name = session.Name;
            summary.status = session.Status__c;
            summary.createdDate = session.CreatedDate;
            summary.createdByName = session.CreatedBy.Name;
            summary.entryCount = session.Staging_Entries__r.size();
            summary.errorMessage = session.Error_Message__c;
            summary.finalizedBy = session.Finalized_By__c;
            result.add(summary);
        }

        return result;
    }

    /**
     * @description Creates a new change set (staging session) with Open status.
     * @return The Id of the newly created change set
     */
    @AuraEnabled
    public static Id createChangeSet() {
        SKU_Config_Staging__c session = new SKU_Config_Staging__c(
            Session_Id__c = generateSessionId(),
            Status__c = SKUConfigStagingBatch.STATUS_OPEN
        );
        insert session;
        Nebula.Logger.info('Change set created: ' + session.Id + ' (' + session.Session_Id__c + ')')
            .addTag('SkuPublishController')
            .setRecordId(session.Id);
        Nebula.Logger.saveLog();
        return session.Id;
    }

    /**
     * @description Adds a change entry to an existing change set.
     * @param sessionId  The parent change set Id
     * @param objectApiName  API name of the object (e.g., Product2)
     * @param recordName  Display name of the record
     * @param gearsetExternalId  Gearset external Id for file path derivation
     * @param jsonContent  Full JSON content for the .gs.json file
     * @param operationType  Create, Update, or Delete
     * @return The Id of the newly created entry
     */
    @AuraEnabled
    public static Id addChangeEntry(
        Id sessionId,
        String objectApiName,
        String recordName,
        String gearsetExternalId,
        String jsonContent,
        String operationType
    ) {
        // Validate session is still Open
        SKU_Config_Staging__c session = [
            SELECT Id, Status__c
            FROM SKU_Config_Staging__c
            WHERE Id = :sessionId
            LIMIT 1
        ];

        if (session.Status__c != SKUConfigStagingBatch.STATUS_OPEN) {
            String msg = 'Cannot add entries to a change set with status: ' + session.Status__c;
            AuraHandledException ex = new AuraHandledException(msg);
            ex.setMessage(msg);
            throw ex;
        }

        SKU_Config_Staging_Entry__c entry = new SKU_Config_Staging_Entry__c(
            Staging__c = sessionId,
            Object_API_Name__c = objectApiName,
            Record_Name__c = recordName,
            Gearset_External_Id__c = gearsetExternalId,
            JSON_Content__c = jsonContent,
            Operation_Type__c = operationType
        );
        insert entry;
        return entry.Id;
    }

    /**
     * @description Returns the full detail of a change set including all entries.
     * @param sessionId  The change set Id
     * @return ChangeSetDetail wrapper with entries
     */
    @AuraEnabled(cacheable=true)
    public static ChangeSetDetail getChangeSetDetail(Id sessionId) {
        SKU_Config_Staging__c session = [
            SELECT Id, Name, Status__c, CreatedDate, CreatedBy.Name,
                   Error_Message__c, Finalized_By__c,
                   (SELECT Id, Object_API_Name__c, Record_Name__c,
                           Gearset_External_Id__c, Operation_Type__c
                    FROM Staging_Entries__r
                    ORDER BY Object_API_Name__c, Record_Name__c)
            FROM SKU_Config_Staging__c
            WHERE Id = :sessionId
            LIMIT 1
        ];

        ChangeSetDetail detail = new ChangeSetDetail();
        detail.recordId = session.Id;
        detail.name = session.Name;
        detail.status = session.Status__c;
        detail.createdDate = session.CreatedDate;
        detail.createdByName = session.CreatedBy.Name;
        detail.errorMessage = session.Error_Message__c;
        detail.finalizedBy = session.Finalized_By__c;

        detail.entries = new List<ChangeEntry>();
        for (SKU_Config_Staging_Entry__c e : session.Staging_Entries__r) {
            ChangeEntry entry = new ChangeEntry();
            entry.recordId = e.Id;
            entry.objectApiName = e.Object_API_Name__c;
            entry.recordName = e.Record_Name__c;
            entry.operationType = e.Operation_Type__c;
            entry.gearsetExternalId = e.Gearset_External_Id__c;
            detail.entries.add(entry);
        }

        return detail;
    }

    /**
     * @description Submits a change set for review. Transitions status to Pending,
     *              sets Finalized_By to User, and kicks off the batch processor.
     * @param sessionId  The change set Id to submit
     * @return The updated status string
     */
    @AuraEnabled
    public static String submitForReview(Id sessionId) {
        SKU_Config_Staging__c session = [
            SELECT Id, Status__c
            FROM SKU_Config_Staging__c
            WHERE Id = :sessionId
            LIMIT 1
        ];

        if (session.Status__c != SKUConfigStagingBatch.STATUS_OPEN) {
            String msg = 'Only Draft change sets can be submitted. Current status: ' + session.Status__c;
            Nebula.Logger.warn('Submit rejected — session ' + sessionId + ' status: ' + session.Status__c)
                .addTag('SkuPublishController')
                .setRecordId(sessionId);
            Nebula.Logger.saveLog();
            AuraHandledException ex = new AuraHandledException(msg);
            ex.setMessage(msg);
            throw ex;
        }

        session.Status__c = SKUConfigStagingBatch.STATUS_PENDING;
        session.Finalized_By__c = SKUConfigStagingBatch.FINALIZED_BY_USER;
        update session;

        Nebula.Logger.info('Change set submitted for review: ' + sessionId)
            .addTag('SkuPublishController')
            .setRecordId(sessionId);
        Nebula.Logger.saveLog();

        // Kick off the batch processor (skip in test context to avoid callout errors)
        if (!Test.isRunningTest()) {
            Database.executeBatch(new SKUConfigStagingBatch(), 1);
        }

        return SKUConfigStagingBatch.STATUS_PENDING;
    }

    /**
     * @description Lightweight status poll for a change set. Used by the LWC
     *              to check if processing has completed.
     * @param sessionId  The change set Id
     * @return ChangeSetSummary with current status
     */
    @AuraEnabled
    public static ChangeSetSummary getChangeSetStatus(Id sessionId) {
        SKU_Config_Staging__c session = [
            SELECT Id, Name, Status__c, Error_Message__c, Finalized_By__c,
                   CreatedDate, CreatedBy.Name,
                   (SELECT Id FROM Staging_Entries__r)
            FROM SKU_Config_Staging__c
            WHERE Id = :sessionId
            LIMIT 1
        ];

        ChangeSetSummary summary = new ChangeSetSummary();
        summary.recordId = session.Id;
        summary.name = session.Name;
        summary.status = session.Status__c;
        summary.createdDate = session.CreatedDate;
        summary.createdByName = session.CreatedBy.Name;
        summary.entryCount = session.Staging_Entries__r.size();
        summary.errorMessage = session.Error_Message__c;
        summary.finalizedBy = session.Finalized_By__c;
        return summary;
    }

    // ─── Private Helpers ─────────────────────────────────────────────────

    /**
     * @description Generates a UUID-style session identifier.
     * @return A unique session Id string
     */
    @TestVisible
    private static String generateSessionId() {
        Blob randomBytes = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(randomBytes);
        return hex.substring(0, 8) + '-'
             + hex.substring(8, 12) + '-'
             + hex.substring(12, 16) + '-'
             + hex.substring(16, 20) + '-'
             + hex.substring(20, 32);
    }
}