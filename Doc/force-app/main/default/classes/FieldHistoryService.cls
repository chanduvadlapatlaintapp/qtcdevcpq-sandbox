/**
 * @description Service class for field history tracking functionality
 * @author Sahal
 * @createdDate Jan-05-2026
 */
public with sharing class FieldHistoryService {
    
    private static Map<String, Set<String>> configCache = new Map<String, Set<String>>();
    private static Map<String, Map<String, Schema.SObjectField>> fieldDescribeCache = new Map<String, Map<String, Schema.SObjectField>>();
    
    /**
     * @description Gets the fields to track for a given object from custom metadata
     * @param objectApiName The API name of the object
     * @return Set of field API names to track
     */
    public static Set<String> getFieldsToTrack(String objectApiName) {
        // Check cache first
        if (configCache.containsKey(objectApiName)) {
            return configCache.get(objectApiName);
        }
        
        Set<String> fieldsToTrack = new Set<String>();
        
        try {
            // Query custom metadata for the object configuration
            List<Field_History_Config__mdt> configs = [
                SELECT Fields_to_Track__c, Is_Active__c
                FROM Field_History_Config__mdt
                WHERE Object_API_Name__c = :objectApiName
                AND Is_Active__c = true
                LIMIT 1
            ];
            
            if (!configs.isEmpty() && String.isNotBlank(configs[0].Fields_to_Track__c)) {
                // Parse comma-separated or newline-separated field names
                String fieldsString = configs[0].Fields_to_Track__c;
                List<String> fieldList = new List<String>();
                
                // Handle both comma and newline separators
                if (fieldsString.contains(',')) {
                    fieldList = fieldsString.split(',');
                } else if (fieldsString.contains('\n')) {
                    fieldList = fieldsString.split('\n');
                } else {
                    fieldList.add(fieldsString);
                }
                
                // Trim and add to set
                for (String field : fieldList) {
                    String trimmedField = field.trim();
                    if (String.isNotBlank(trimmedField)) {
                        fieldsToTrack.add(trimmedField.toLowerCase());
                    }
                }
            }
        } catch (Exception e) {
            Nebula.Logger.error('Error retrieving field history config for ' + objectApiName)
                .setExceptionDetails(e)
                .addTag('FieldHistory');
            Nebula.Logger.saveLog();
        }
        
        // Cache the result
        configCache.put(objectApiName, fieldsToTrack);
        return fieldsToTrack;
    }
    
    /**
     * @description Gets the field describe map for an object (cached)
     * @param objectApiName The API name of the object
     * @return Map of field API name (lowercase) to Schema.SObjectField
     */
    public static Map<String, Schema.SObjectField> getFieldDescribeMap(String objectApiName) {
        if (fieldDescribeCache.containsKey(objectApiName)) {
            return fieldDescribeCache.get(objectApiName);
        }
        
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            return new Map<String, Schema.SObjectField>();
        }
        
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> lowerCaseFieldMap = new Map<String, Schema.SObjectField>();
        
        for (String fieldName : fieldMap.keySet()) {
            lowerCaseFieldMap.put(fieldName.toLowerCase(), fieldMap.get(fieldName));
        }
        
        fieldDescribeCache.put(objectApiName, lowerCaseFieldMap);
        return lowerCaseFieldMap;
    }
    
    /**
     * @description Gets the display label for a field
     * @param objectApiName The API name of the object
     * @param fieldApiName The API name of the field
     * @return The field label or API name if label not found
     */
    public static String getFieldLabel(String objectApiName, String fieldApiName) {
        Map<String, Schema.SObjectField> fieldMap = getFieldDescribeMap(objectApiName);
        String lowerFieldName = fieldApiName.toLowerCase();
        
        if (fieldMap.containsKey(lowerFieldName)) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(lowerFieldName).getDescribe();
            return fieldDescribe.getLabel();
        }
        
        return fieldApiName;
    }
    
    /**
     * @description Formats a field value for storage in history record
     * @param fieldValue The field value to format
     * @param fieldDescribe The field describe result
     * @return Formatted string representation of the value
     */
    public static String formatFieldValue(Object fieldValue, Schema.DescribeFieldResult fieldDescribe) {
        if (fieldValue == null) {
            return '';
        }
        
        Schema.DisplayType displayType = fieldDescribe.getType();
        
        try {
            switch on displayType {
                when BOOLEAN {
                    return String.valueOf(fieldValue);
                }
                when DATE {
                    Date d = (Date) fieldValue;
                    return String.valueOf(d);
                }
                when DATETIME {
                    DateTime dt = (DateTime) fieldValue;
                    return String.valueOf(dt);
                }
                when TIME {
                    Time t = (Time) fieldValue;
                    return String.valueOf(t);
                }
                when CURRENCY, DOUBLE, INTEGER, LONG, PERCENT {
                    return String.valueOf(fieldValue);
                }
                when REFERENCE {
                    Id refId = (Id) fieldValue;
                    return refId;
                }
                when PICKLIST, MULTIPICKLIST {
                    return String.valueOf(fieldValue);
                }
                when EMAIL, PHONE, URL, STRING, TEXTAREA {
                    String strValue = String.valueOf(fieldValue);
                    // Truncate if too long (131072 is max for Long Text Area)
                    if (strValue.length() > 131000) {
                        return strValue.substring(0, 131000) + '... (truncated)';
                    }
                    return strValue;
                }
                when else {
                    return String.valueOf(fieldValue);
                }
            }
        } catch (Exception e) {
            Nebula.Logger.warn('Error formatting field value for ' + fieldDescribe.getName() + ': ' + e.getMessage())
                .addTag('FieldHistory');
            Nebula.Logger.saveLog();
            return String.valueOf(fieldValue);
        }
    }
    
    /**
     * @description Clears the configuration cache (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        configCache.clear();
        fieldDescribeCache.clear();
    }
}