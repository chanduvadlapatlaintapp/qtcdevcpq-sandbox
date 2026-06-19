/**
 * @description Helper class for field history tracking operations
 * @author Sahal
 * @createdDate Jan-05-2026
 */
public with sharing class FieldHistoryHelper {

    /**
     * @description Gets and validates field describe for update operations
     * @param fieldApiName The API name of the field
     * @param fieldMap Map of field API names to SObjectField
     * @return Schema.DescribeFieldResult if valid for update, null otherwise
     */
    public static Schema.DescribeFieldResult getFieldDescribeForUpdate(
        String fieldApiName,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(fieldApiName, fieldMap);
        if (fieldDescribe == null) {
            return null;
        }
        return (fieldDescribe.isAccessible() && fieldDescribe.isUpdateable()) ? fieldDescribe : null;
    }

    /**
     * @description Gets and validates field describe for insert operations
     * @param fieldApiName The API name of the field
     * @param fieldMap Map of field API names to SObjectField
     * @return Schema.DescribeFieldResult if valid for insert, null otherwise
     */
    public static Schema.DescribeFieldResult getFieldDescribeForInsert(
        String fieldApiName,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(fieldApiName, fieldMap);
        if (fieldDescribe == null) {
            return null;
        }
        return fieldDescribe.isAccessible() ? fieldDescribe : null;
    }

    /**
     * @description Gets field describe from field map
     * @param fieldApiName The API name of the field
     * @param fieldMap Map of field API names to SObjectField
     * @return Schema.DescribeFieldResult if found, null otherwise
     */
    private static Schema.DescribeFieldResult getFieldDescribe(
        String fieldApiName,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        String lowerFieldName = fieldApiName.toLowerCase();
        if (!fieldMap.containsKey(lowerFieldName)) {
            Nebula.Logger.warn('Field "' + fieldApiName + '" not found on object. Check Field_History_Config__mdt configuration.')
                .addTag('FieldHistory');
            return null;
        }
        return fieldMap.get(lowerFieldName).getDescribe();
    }

    /**
     * @description Checks if a field value has changed
     * @param oldValue The old value
     * @param newValue The new value
     * @return true if values are different
     */
    public static Boolean hasValueChanged(Object oldValue, Object newValue) {
        if (oldValue == null && newValue == null) {
            return false;
        }
        return oldValue != newValue;
    }

    /**
     * @description Creates a Field_History__c record for an update operation
     * @param recordId The ID of the record
     * @param objectApiName The API name of the object
     * @param fieldDescribe The field describe result
     * @param oldValue The old field value
     * @param newValue The new field value
     * @param changedById The ID of the user who made the change
     * @return Field_History__c record or null if error
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static Field_History__c createUpdateHistoryRecord(
        Id recordId,
        String objectApiName,
        Schema.DescribeFieldResult fieldDescribe,
        Object oldValue,
        Object newValue,
        Id changedById
    ) {
        return createHistoryRecord(recordId, objectApiName, fieldDescribe, oldValue, newValue, changedById, 'Update');
    }

    /**
     * @description Creates a Field_History__c record for an insert operation
     * @param recordId The ID of the record
     * @param objectApiName The API name of the object
     * @param fieldDescribe The field describe result
     * @param newValue The new field value
     * @param changedById The ID of the user who made the change
     * @return Field_History__c record or null if error
     */
    public static Field_History__c createInsertHistoryRecord(
        Id recordId,
        String objectApiName,
        Schema.DescribeFieldResult fieldDescribe,
        Object newValue,
        Id changedById
    ) {
        return createHistoryRecord(recordId, objectApiName, fieldDescribe, null, newValue, changedById, 'Insert');
    }

    /**
     * @description Creates a Field_History__c record
     * @param recordId The ID of the record
     * @param objectApiName The API name of the object
     * @param fieldDescribe The field describe result
     * @param oldValue The old field value
     * @param newValue The new field value
     * @param changedById The ID of the user who made the change
     * @param changeType The type of change (Insert, Update, Delete)
     * @return Field_History__c record or null if error
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Field_History__c createHistoryRecord(
        Id recordId,
        String objectApiName,
        Schema.DescribeFieldResult fieldDescribe,
        Object oldValue,
        Object newValue,
        Id changedById,
        String changeType
    ) {
        try {
            Field_History__c history = new Field_History__c();
            history.Parent_Record__c = String.valueOf(recordId);
            history.Parent_Object_Type__c = objectApiName;
            history.Field_Name__c = fieldDescribe.getName();
            history.Field_Label__c = FieldHistoryService.getFieldLabel(objectApiName, fieldDescribe.getName());
            history.Old_Value__c = FieldHistoryService.formatFieldValue(oldValue, fieldDescribe);
            history.New_Value__c = FieldHistoryService.formatFieldValue(newValue, fieldDescribe);
            history.Changed_By__c = changedById;
            history.Change_Type__c = changeType;
            history.Change_Date__c = System.now();
            return history;
        } catch (Exception e) {
            Nebula.Logger.error('Error creating field history record for ' + objectApiName + '.' + fieldDescribe.getName())
                .setExceptionDetails(e)
                .addTag('FieldHistory');
            Nebula.Logger.saveLog();
            return null;
        }
    }

    /**
     * @description Enqueues history records for asynchronous insertion
     * @param historyRecords List of Field_History__c records
     * @param methodName The name of the calling method for logging
     */
    public static void enqueueHistoryRecords(List<Field_History__c> historyRecords, String methodName) {
        if (historyRecords == null || historyRecords.isEmpty()) {
            return;
        }
        try {
            // BIZ-80556: When the host trigger fires inside an async context
            // (@future / queueable / batch / scheduled), Salesforce caps queueable
            // chaining at 1 per parent transaction. Callers that do multiple DMLs
            // (e.g. CloneOptyWithLineItems's two OLI inserts) would enqueue 2+
            // queueables and trip the limit. Inline-insert in async context — the
            // parent is already async, so audit insert participates in that same
            // transaction's DML budget instead of a separate queueable.
            if (System.isFuture() || System.isQueueable() || System.isBatch() || System.isScheduled()) {
                Nebula.Logger.info('Inline inserting ' + historyRecords.size() + ' field history records via ' + methodName + ' (async context)')
                    .addTag('FieldHistory');
                Database.insert(historyRecords, false);
                Nebula.Logger.saveLog();
                return;
            }
            Nebula.Logger.info('Enqueueing ' + historyRecords.size() + ' field history records via ' + methodName)
                .addTag('FieldHistory');
            System.enqueueJob(new FieldHistoryInsertQueueable(historyRecords));
            Nebula.Logger.saveLog();
        } catch (Exception e) {
            Nebula.Logger.error('Error enqueueing field history records via ' + methodName)
                .setExceptionDetails(e)
                .addTag('FieldHistory');
            Nebula.Logger.saveLog();
        }
    }
}