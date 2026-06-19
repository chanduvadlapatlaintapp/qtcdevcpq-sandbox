/**
 * @author : Sahal Mohamed
 * @date : 02/12/2025
 * @description : common utilities for working with record types
**/

public without sharing class RecordTypeUtil {

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description gets a record type id when given a record type developer name
    * @param obj
    * @param developerName
    * @return Id 
    */
    public static Id getRecordTypeId (SObjectType obj, String developerName) {
        
        if (String.isBlank(developerName)) { return null; }

        return ObjectDescribeDataCache.getDescribe(obj)
            .getRecordTypeInfosByDeveloperName()
                .get(developerName)
                    .getRecordTypeId();
    }

    /**
    * @description gets a record type developer name when given a record type id
    * @param obj
    * @param recordTypeId
    * @return String
    */
    public static String getRecordTypeDevName (SObjectType obj, Id recordTypeId) {

        if (String.isBlank(recordTypeId)) { return null; }

        return ObjectDescribeDataCache.getDescribe(obj)
            .getRecordTypeInfosById()
                .get(recordTypeId)
                    .getDeveloperName();
    }

}