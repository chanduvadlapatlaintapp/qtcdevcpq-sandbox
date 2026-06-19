/**
 * @description Generic handler class for tracking field history changes on any Salesforce object
 * @author Sahal
 * @createdDate Jan-05-2026
 *
 * Usage:
 * In your trigger handler's afterUpdate method, call:
 * FieldHistoryHandler.trackFieldChanges(Trigger.new, Trigger.oldMap, 'Account');
 */
public with sharing class FieldHistoryHandler {

    /**
     * @description Tracks field changes for updated records
     * @param newRecords List of new records (Trigger.new)
     * @param oldRecordsMap Map of old records (Trigger.oldMap)
     * @param objectApiName The API name of the object being tracked
     */
    public static void trackFieldChanges(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap, String objectApiName) {
        if (newRecords == null || newRecords.isEmpty() || oldRecordsMap == null || oldRecordsMap.isEmpty()) {
            return;
        }

        Set<String> fieldsToTrack = FieldHistoryService.getFieldsToTrack(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = FieldHistoryService.getFieldDescribeMap(objectApiName);

        if (fieldsToTrack.isEmpty() || fieldMap.isEmpty()) {
            Nebula.Logger.warn('No active field history config found for ' + objectApiName + '. Skipping update tracking.')
                .addTag('FieldHistory');
            Nebula.Logger.saveLog();
            return;
        }

        Nebula.Logger.info('Tracking ' + fieldsToTrack.size() + ' fields on ' + newRecords.size() + ' ' + objectApiName + ' update(s)')
            .addTag('FieldHistory');

        List<Field_History__c> historyRecords = processUpdateChanges(newRecords, oldRecordsMap, objectApiName, fieldsToTrack, fieldMap);

        Nebula.Logger.info('Detected ' + historyRecords.size() + ' field change(s) on ' + objectApiName)
            .addTag('FieldHistory');
        Nebula.Logger.saveLog();

        FieldHistoryHelper.enqueueHistoryRecords(historyRecords, 'trackFieldChanges');
    }

    /**
     * @description Processes field changes for updated records
     * @param newRecords List of new records
     * @param oldRecordsMap Map of old records
     * @param objectApiName The API name of the object
     * @param fieldsToTrack Set of field API names to track
     * @param fieldMap Map of field API names to SObjectField
     * @return List of Field_History__c records
     */
    @SuppressWarnings('PMD.ExcessiveParameterList') private static List<Field_History__c> processUpdateChanges(
        List<SObject> newRecords,
        Map<Id, SObject> oldRecordsMap,
        String objectApiName,
        Set<String> fieldsToTrack,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        List<Field_History__c> historyRecords = new List<Field_History__c>();
        Id currentUserId = UserInfo.getUserId();

        for (SObject newRecord : newRecords) {
            SObject oldRecord = oldRecordsMap.get(newRecord.Id);
            if (oldRecord == null) {
                continue;
            }
            historyRecords.addAll(processRecordUpdate(newRecord, oldRecord, objectApiName, fieldsToTrack, fieldMap, currentUserId));
        }
        return historyRecords;
    }

    /**
     * @description Processes field changes for a single updated record
     * @param newRecord The new record
     * @param oldRecord The old record
     * @param objectApiName The API name of the object
     * @param fieldsToTrack Set of field API names to track
     * @param fieldMap Map of field API names to SObjectField
     * @param currentUserId The ID of the current user
     * @return List of Field_History__c records for this record
     */
    @SuppressWarnings('PMD.ExcessiveParameterList') private static List<Field_History__c> processRecordUpdate(
        SObject newRecord,
        SObject oldRecord,
        String objectApiName,
        Set<String> fieldsToTrack,
        Map<String, Schema.SObjectField> fieldMap,
        Id currentUserId
    ) {
        List<Field_History__c> historyRecords = new List<Field_History__c>();

        for (String fieldApiName : fieldsToTrack) {
            Field_History__c history = processFieldUpdate(newRecord, oldRecord, objectApiName, fieldApiName, fieldMap, currentUserId);
            if (history != null) {
                historyRecords.add(history);
            }
        }
        return historyRecords;
    }

    /**
     * @description Processes a single field update
     * @param newRecord The new record
     * @param oldRecord The old record
     * @param objectApiName The API name of the object
     * @param fieldApiName The API name of the field
     * @param fieldMap Map of field API names to SObjectField
     * @param currentUserId The ID of the current user
     * @return Field_History__c record if change detected, null otherwise
     */
    @SuppressWarnings('PMD.ExcessiveParameterList') private static Field_History__c processFieldUpdate(
        SObject newRecord,
        SObject oldRecord,
        String objectApiName,
        String fieldApiName,
        Map<String, Schema.SObjectField> fieldMap,
        Id currentUserId
    ) {
        Schema.DescribeFieldResult fieldDescribe = FieldHistoryHelper.getFieldDescribeForUpdate(fieldApiName, fieldMap);
        if (fieldDescribe == null) {
            return null;
        }

        Object oldValue = oldRecord.get(fieldDescribe.getName());
        Object newValue = newRecord.get(fieldDescribe.getName());

        if (!FieldHistoryHelper.hasValueChanged(oldValue, newValue)) {
            return null;
        }

        return FieldHistoryHelper.createUpdateHistoryRecord(newRecord.Id, objectApiName, fieldDescribe, oldValue, newValue, currentUserId);
    }

    /**
     * @description Tracks field values for newly inserted records
     * @param newRecords List of new records (Trigger.new)
     * @param objectApiName The API name of the object being tracked
     */
    public static void trackFieldChangesOnInsert(List<SObject> newRecords, String objectApiName) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        Set<String> fieldsToTrack = FieldHistoryService.getFieldsToTrack(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = FieldHistoryService.getFieldDescribeMap(objectApiName);

        if (fieldsToTrack.isEmpty() || fieldMap.isEmpty()) {
            Nebula.Logger.warn('No active field history config found for ' + objectApiName + '. Skipping insert tracking.')
                .addTag('FieldHistory');
            Nebula.Logger.saveLog();
            return;
        }

        Nebula.Logger.info('Tracking ' + fieldsToTrack.size() + ' fields on ' + newRecords.size() + ' ' + objectApiName + ' insert(s)')
            .addTag('FieldHistory');

        List<Field_History__c> historyRecords = processInsertChanges(newRecords, objectApiName, fieldsToTrack, fieldMap);

        Nebula.Logger.info('Captured ' + historyRecords.size() + ' initial field value(s) on ' + objectApiName)
            .addTag('FieldHistory');
        Nebula.Logger.saveLog();

        FieldHistoryHelper.enqueueHistoryRecords(historyRecords, 'trackFieldChangesOnInsert');
    }

    /**
     * @description Processes field changes for inserted records
     * @param newRecords List of new records
     * @param objectApiName The API name of the object
     * @param fieldsToTrack Set of field API names to track
     * @param fieldMap Map of field API names to SObjectField
     * @return List of Field_History__c records
     */
    @SuppressWarnings('PMD.ExcessiveParameterList') private static List<Field_History__c> processInsertChanges(
        List<SObject> newRecords,
        String objectApiName,
        Set<String> fieldsToTrack,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        List<Field_History__c> historyRecords = new List<Field_History__c>();
        Id currentUserId = UserInfo.getUserId();

        for (SObject newRecord : newRecords) {
            historyRecords.addAll(processRecordInsert(newRecord, objectApiName, fieldsToTrack, fieldMap, currentUserId));
        }
        return historyRecords;
    }

    /**
     * @description Processes field changes for a single inserted record
     * @param newRecord The new record
     * @param objectApiName The API name of the object
     * @param fieldsToTrack Set of field API names to track
     * @param fieldMap Map of field API names to SObjectField
     * @param currentUserId The ID of the current user
     * @return List of Field_History__c records for this record
     */
    @SuppressWarnings('PMD.ExcessiveParameterList') private static List<Field_History__c> processRecordInsert(
        SObject newRecord,
        String objectApiName,
        Set<String> fieldsToTrack,
        Map<String, Schema.SObjectField> fieldMap,
        Id currentUserId
    ) {
        List<Field_History__c> historyRecords = new List<Field_History__c>();

        for (String fieldApiName : fieldsToTrack) {
            Field_History__c history = processFieldInsert(newRecord, objectApiName, fieldApiName, fieldMap, currentUserId);
            if (history != null) {
                historyRecords.add(history);
            }
        }
        return historyRecords;
    }

    /**
     * @description Processes a single field insert
     * @param newRecord The new record
     * @param objectApiName The API name of the object
     * @param fieldApiName The API name of the field
     * @param fieldMap Map of field API names to SObjectField
     * @param currentUserId The ID of the current user
     * @return Field_History__c record if value exists, null otherwise
     */
    @SuppressWarnings('PMD.ExcessiveParameterList') private static Field_History__c processFieldInsert(
        SObject newRecord,
        String objectApiName,
        String fieldApiName,
        Map<String, Schema.SObjectField> fieldMap,
        Id currentUserId
    ) {
        Schema.DescribeFieldResult fieldDescribe = FieldHistoryHelper.getFieldDescribeForInsert(fieldApiName, fieldMap);
        if (fieldDescribe == null) {
            return null;
        }

        Object newValue = newRecord.get(fieldDescribe.getName());
        if (newValue == null) {
            return null;
        }

        return FieldHistoryHelper.createInsertHistoryRecord(newRecord.Id, objectApiName, fieldDescribe, newValue, currentUserId);
    }
}