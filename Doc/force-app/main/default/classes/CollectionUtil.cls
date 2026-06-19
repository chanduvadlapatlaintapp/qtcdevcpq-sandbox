/**
* @description Utility class for reusable methods for collections
* @author Sahal Mohamed
* @Created Date 02/12/2025
**/
public inherited sharing class CollectionUtil {
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
    * @description returns a set of record ids from the records List which are not present in existingIds
    * @param records 
    * @param existingIds
    * @return Set<Id>
    */
    public static Set<Id> getIdsNotInSet(List<SObject> records, Set<Id> existingIds) {
        Set<Id> idsNotInSet = new Set<Id>();
        for(SObject record : records) {
            if(!existingIds.contains(record.Id)) {
                idsNotInSet.add(record.Id);
            }
        }
        return idsNotInSet;
    }

    /**
    * @description returns a list of records from the records List which are not present in existingIds
    * @param records 
    * @param existingIds
    * @return List<SObject>
    */
    public static List<SObject> getRecordsNotInSet(List<SObject> records, Set<Id> existingIds) {
        List<SObject> recordsNotInSet = new List<SObject>();
        for(SObject record : records) {
            if(!existingIds.contains(record.Id)) {
                recordsNotInSet.add(record);
            }
        }
        return recordsNotInSet;
    }
}