/**
 * @author  : Ratan Paul
 * @date    : 05/02/2025
 * @description : Controller to fetch related records for a given SObject based on dynamic filter field and value.
 *                Intended for use with a generic Lightning Web Component for related lists.
 * @jira    : BIZ-68163
 */
public with sharing class GenericRelatedListController {

    /**
     * @description 
     *    Fetches a list of related records from the specified object.
     *    1. Queries the base record using the record Id to get the filter field value.
     *    2. Uses that value to fetch all other records with the same filter field value (excluding the original).
     *
     * @param objectApiName       The API name of the object to query (e.g., 'Account', 'CustomObject__c').
     * @param fieldApiNames       Comma-separated field API names to retrieve (e.g., 'Name,Industry').
     * @param filterFieldApiName  The API name of the field used as a filter (e.g., 'Industry').
     * @param filterValue         The record Id from which to extract the filter field value.
     * 
     * @return List<SObject>      List of SObjects matching the filter criteria.
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getRelatedRecords(
        String objectApiName,
        String fieldApiNames,
        String filterFieldApiName,
        Id filterValue
    ) {

        // Get field metadata
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();

        List<String> selectFields = new List<String>();
        for (String fieldName : fieldApiNames.split(',')) {
            if (fieldMap.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                // If picklist, wrap with toLabel()
                if (fieldDescribe.getType() == Schema.DisplayType.Picklist) {
                    selectFields.add('toLabel(' + fieldName + ')');
                } else {
                    selectFields.add(fieldName);
                }
            }
        }
        // Query the base record to get the filter field's value
        String query = 'SELECT Id, ' + filterFieldApiName + 
                       ' FROM ' + objectApiName +
                       ' WHERE Id = :filterValue';
        List<SObject> lstObject = Database.query(query);

        // If no records found, return an empty list
        if (lstObject.isEmpty()) {
            return new List<SObject>();
        }

        // Step 2: Extract the filter field's value from the base record
        Object strData = lstObject[0].get(filterFieldApiName);
		if (strData == null) {
            return new List<SObject>();
        }
        // Step 3: Construct a dynamic query to get related records with matching filter field value
        String finalQuery = 'SELECT ' + String.join(selectFields, ', ') + 
                            ' FROM ' + objectApiName +
                            ' WHERE ' + filterFieldApiName + ' = :strData' +
                            ' AND Id != :filterValue'; // Exclude the original record
        // Return the related records
        return Database.query(finalQuery);
    }
}