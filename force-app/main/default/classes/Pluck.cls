/**
 * @author : Sahal Mohamed
 * @date : 02/11/2025
 * @description : Utility class for plucking fields from a list
 */
public without sharing class Pluck {
    /**********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/
    /**
     * @description : this extracts a set of record ids from the provided list
     *
     * @param objs - a list of objects to process
     * @return a set of ids extracted from the provided list
     */
    public static Set<Id> ids(List<sObject> objs) {
        Set<Id> uniqueValues = new Set<Id>();

        for (sObject obj : objs) {
            Id value = obj.Id;
            if (value != null) {
                uniqueValues.add(value);
            }
        }

        return uniqueValues;
    }

    /**
     * @description : this extracts a set of record ids from the given field for the provided list
     *
     * @param field - a field to extract an id from
     * @param objs - a list of objects to process
     * @return a set of ids extracted from the provided list
     */
    public static Set<Id> ids(Schema.sObjectField field, List<sObject> objs) {
        Set<Id> uniqueValues = new Set<Id>();

        for (sObject obj : objs) {
            Id value = (Id) pluckField(field, obj);
            if (value != null) {
                uniqueValues.add(value);
            }
        }

        return uniqueValues;
    }

    /**
     * @description : this extracts a set of record ids from the given field for the provided list
     *
     * @param field - a field to extract an id from
     * @param objs - a list of objects to process
     * @return a set of ids extracted from the provided list
     */
    public static Set<Id> ids(String field, List<sObject> objs) {
        Set<Id> uniqueValues = new Set<Id>();

        for (sObject obj : objs) {
            Id value = (Id) pluckField(field, obj);
            if (value != null) {
                uniqueValues.add(value);
            }
        }

        return uniqueValues;
    }

    /**
     * @description : this extracts a set of strings from the given field for the provided list
     *
     * @param field - a field to extract a string from
     * @param objs - a list of objects to process
     * @return a set of strings extracted from the provided list
     */
    public static Set<String> strings(
        Schema.sObjectField field,
        List<sObject> objs
    ) {
        Set<String> uniqueValues = new Set<String>();

        for (sObject obj : objs) {
            String value = (String) pluckField(field, obj);
            if (value != null) {
                uniqueValues.add(value);
            }
        }

        return uniqueValues;
    }

    /**
     * @description : this extracts a set of strings from the given field for the provided list
     *
     * @param field - a field to extract a string from
     * @param objs - a list of objects to process
     * @return a set of strings extracted from the provided list
     */
    public static Set<String> strings(String field, List<sObject> objs) {
        Set<String> uniqueValues = new Set<String>();

        for (sObject obj : objs) {
            String value = (String) pluckField(field, obj);
            if (value != null) {
                uniqueValues.add(value);
            }
        }

        return uniqueValues;
    }

    /**
     * @description : this extracts objects from the given field for the provided list
     *
     * @param field - a field to extract an id from
     * @param objs - a list of objects to process
     * @return a set of strings extracted from the provided list
     */
    public static List<Object> values(
        Schema.sObjectField field,
        List<sObject> objs
    ) {
        List<Object> values = new List<Object>();

        for (sObject obj : objs) {
            values.add(pluckField(field, obj));
        }

        return values;
    }

    /**
     * @description Used to extract a given Id field from a list of SObjects and returns
     *              a map indexed by the given field's value and a list of related SObjects
     *
     * @param field - an Id field to index the SObjects
     * @param sObjs - a list of SObjects to process
     * @return map of unique Ids to a list of SObjects
     */
    public static Map<Id, List<SObject>> idMap(
        Schema.SObjectField field,
        List<SObject> sObjs
    ) {
        Map<Id, List<SObject>> sObjMap = new Map<Id, List<SObject>>();

        for (SObject sObj : sObjs) {
            Id value = (Id) pluckField(field, sObj);

            if (sObjMap.containsKey(value)) {
                sObjMap.get(value).add(sObj);
            } else {
                sObjMap.put(value, new List<SObject>{ sObj });
            }
        }

        return sObjMap;
    }

    /**
     * @description Used to extract a given string field from a list of SObjects and returns
     *              a map indexed by the given field's value and a list of related SObjects
     *
     * @param field - a string field to index the SObjects
     * @param sObjs - a list of SObjects to process
     * @return map of unique strings to a list of SObjects
     */
    public static Map<String, List<SObject>> stringMap(
        Schema.SObjectField field,
        List<SObject> sObjs
    ) {
        Map<String, List<SObject>> sObjMap = new Map<String, List<SObject>>();

        for (SObject sObj : sObjs) {
            String value = (String) pluckField(field, sObj);

            if (sObjMap.containsKey(value)) {
                sObjMap.get(value).add(sObj);
            } else {
                sObjMap.put(value, new List<SObject>{ sObj });
            }
        }

        return sObjMap;
    }

    /**
     * @description Use to filter down a given list of SObjects by a given field's
     *              value by providing a field and a filter value along with the
     *              a list of SObjects
     *
     * @param field - a field to filter the SObjects
     * @param sObjs - a list of SObjects to filter
     * @param filter - a filter value
     * @return a list of SObjects filtered down by the given field and filter
     */
    public static List<SObject> filter(
        Schema.SObjectField field,
        List<SObject> sObjs,
        Object filter
    ) {
        List<SObject> filteredSObjs = new List<SObject>();

        for (SObject sObj : sObjs) {
            Object value = Pluck.pluckField(field, sObj);

            if (value == filter) {
                filteredSObjs.add(sObj);
            }
        }

        return filteredSObjs;
    }

    /**
     * @description Use to filter a list of SObjects by a field and a set of id filter values.
     *              If the field value is in the set of filter values, the SObject is added to
     *              the list of filtered SObjects to be returned
     *
     * @param field - a field to filter the SObjects
     * @param sObjs - a list of SObjects to filter
     * @param filters - a set of id values to filter by
     * @return a list of SObjects filtered down by the given field and filter values
     */
    public static List<SObject> filterByIds(
        Schema.SObjectField field,
        List<SObject> sObjs,
        Set<Id> filters
    ) {
        List<SObject> filteredSObjs = new List<SObject>();

        for (SObject sObj : sObjs) {
            Id value = (Id) Pluck.pluckField(field, sObj);
            if (filters.contains(value)) {
                filteredSObjs.add(sObj);
            }
        }

        return filteredSObjs;
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description This extracts a value from the given field reference for the provided object
     *
     * @param field - a field to extract a value from
     * @param obj - an object to process
     * @return a value extracted from the provided object
     */
    private static Object pluckField(Schema.sObjectField field, sObject obj) {
        return obj.get(field);
    }

    /**
     * @description This extracts a value from the given field string reference for the provided object
     *
     * @param field - a field to extract a value from
     * @param obj - an object to process
     * @return a value extracted from the provided object
     */
    private static Object pluckField(String field, sObject obj) {
        return obj.get(field);
    }
}