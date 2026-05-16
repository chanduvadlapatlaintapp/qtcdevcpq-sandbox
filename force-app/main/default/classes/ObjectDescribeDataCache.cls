/**
 * @author : Sahal Mohamed
 * @date : 02/12/2025
 * @description : A data cache for object describes.
 * Schema calls are expensive and code appears to be 2-3x faster
 * by caching the describe vs fetching it each time
**/
public without sharing class ObjectDescribeDataCache {

    /***********************************************************************************************
    * 
    * Props
    *
    ***********************************************************************************************/

    private static Map<SObjectType,Schema.DescribeSObjectResult> storedObjDescribes;

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description Returns the describe results for the provided sobject type
    * @param objType - an object type to describe
    * @return Schema.DescribeSObjectResult - Describe results for the object type
    */
    public static Schema.DescribeSObjectResult getDescribe (SObjectType objType) {

        if (storedObjDescribes == null) {
            storedObjDescribes = new Map<SObjectType,Schema.DescribeSObjectResult>();
        }

        if (!storedObjDescribes.containsKey(objType)) {
            storedObjDescribes.put(objType, objType.getDescribe());
        }

        return storedObjDescribes.get(objType);
    }

}