/**
 * @description Apex controller for Field History LWC component
 * @author Sahal
 * @createdDate Jan-05-2026
 */
public with sharing class FieldHistoryController {
    
    /**
     * @description Retrieves field history records for a given parent record ID
     * @param parentRecordId The ID of the parent record
     * @return List of Field_History__c records ordered by Change_Date__c descending
     */
    @AuraEnabled(cacheable=true)
    public static List<Field_History__c> getFieldHistoryRecords(String parentRecordId) {
        if (String.isBlank(parentRecordId)) {
            return new List<Field_History__c>();
        }
        
        return [
            SELECT Id, 
                   Field_Name__c, 
                   Field_Label__c, 
                   Old_Value__c, 
                   New_Value__c, 
                   Changed_By__r.Name, 
                   Changed_By__r.Id,
                   Change_Date__c, 
                   Change_Type__c,
                   Parent_Object_Type__c,
                   CreatedDate
            FROM Field_History__c
            WHERE Parent_Record__c = :parentRecordId
            ORDER BY Change_Date__c DESC, CreatedDate DESC
            LIMIT 1000
        ];
    }
    
    /**
     * @description Gets the count of field history records for a given parent record ID
     * @param parentRecordId The ID of the parent record
     * @return Integer count of field history records
     */
    @AuraEnabled(cacheable=true)
    public static Integer getFieldHistoryCount(String parentRecordId) {
        if (String.isBlank(parentRecordId)) {
            return 0;
        }
        
        return [
            SELECT COUNT()
            FROM Field_History__c
            WHERE Parent_Record__c = :parentRecordId
        ];
    }
}