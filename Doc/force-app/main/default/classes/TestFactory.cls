/**
 * @author Sahal Mohamed
 * @date 02/11/2025
 * @description a test factory to facilitate the testing of business logic in apex
 * @reference https://github.com/dhoechst/Salesforce-Test-Factory
 **/
@isTest
public without sharing class TestFactory {

    /**********************************************************************************************
    *
    * Private Props
    *
    ***********************************************************************************************/

    private final static String DEFAULTS_PREFIX = 'TestFactoryDefaults.';
    private final static String DEFAULTS_SUFFIX = 'Defaults';
    private final static String NAMESTRING = 'Name';

    // Display Type Returns
    private final static String TYPE_STRING  = 'String';
    private final static String TYPE_INTEGER = 'Integer';
    private final static String TYPE_DOUBLE  = 'Double';

    /**********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
     * @description create an object using the standard definition for the object
     *              note : if no standard definition is available then none is used, 
     *              no exceptions are thrown
     * @param sObj
     * @return SObject
     */
    public static SObject createSObject(SObject sObj) {
        SObject retObject = buildSObject(sObj);
        insert retObject;
        return retObject;
    }

    /**
     * @description creates an object using the provided defaults class (aka object template)
     * @param sObj
     * @param objectDefaultsClass
     * @return SObject
     */
    public static SObject createSObject(SObject sObj, String objectDefaultsClass) {
        SObject retObject = buildSObject(sObj, objectDefaultsClass);
        insert retObject;
        return retObject;
    }

    /**
     * @description creates a list of objects using the standard definition for the object
     *              note : if no standard definition is available then none is used, 
     *              no exceptions are thrown
     * @param sObj
     * @param numberOfObjects
     * @return SObject
     */
    public static List<SObject> createSObjectList(SObject sObj, Integer numberOfObjects) {
        List<SObject> retList = buildSObjectList(sObj, numberOfObjects, (String)null);
        insert retList;
        return retList;
    }

    /**
     * @description  creates a list of objects using the provided defaults class (aka object template)
     * @param sObj
     * @param numberOfObjects
     * @param objectDefaultsClass
     * @return List<SObject>
     */
    public static List<SObject> createSObjectList(SObject sObj, Integer numberOfObjects, String objectDefaultsClass) {
        List<SObject> retList = buildSObjectList(sObj, numberOfObjects, objectDefaultsClass);
        insert retList;
        return retList;
    }

    /**
     * @description  initializes a SObject
     * @param sObj
     * @return SObject
     */
    public static SObject buildSObject(SObject sObj) {

        String objectDefaultsClass = getDefaultsClassName(sObj);

        // If there is a class that exists for the default values, then use them
        if(Type.forName(objectDefaultsClass) != null) {
            sObj = buildSObject(sObj, objectDefaultsClass);
        }

        return sObj;
    }

    /**
     * @description  build SObject using the provided defaults class (aka object template)
     * @param sObj
     * @param objectDefaultsClass
     * @return SObject
     */
    public static SObject buildSObject(SObject sObj, String objectDefaultsClass) {

        objectDefaultsClass = getDefaultsClassName(objectDefaultsClass);

        // Create an instance of the defaults class so we can get the Map of field defaults
        Type t = Type.forName(objectDefaultsClass);
        if(t == null) {
            Throw new TestFactoryException('Invalid defaults class.');
        }
        FieldDefaults defaults = (FieldDefaults)t.newInstance();
        addFieldDefaults(sObj, defaults.getFieldDefaults());
        return sObj;
    }

    /**
     * @description buils list of objects at a total of number provided
     * @param sObj
     * @param numberOfObjects
     * @return List<SObject>
     */
    public static List<SObject> buildSObjectList(SObject sObj, Integer numberOfObjects) {
        return buildSObjectList(sObj, numberOfObjects, (String)null);
    }

    /**
     * @description builds an object list using the provided defaults class (aka object template)
     * @param sObj
     * @param numberOfObjects
     * @param objectDefaultsClass
     * @return SObject
     */
    public static List<SObject> buildSObjectList(SObject sObj, Integer numberOfObjects, String objectDefaultsClass) {
        List<SObject> sObjs = new List<SObject> {};
        SObject newObj;
        Type defClass;
        FieldDefaults defaults;

        // Get one copy of the object
        if(objectDefaultsClass == null) {
            newObj = buildSObject(sObj);

            String defaultDefName = getDefaultsClassName(sObj);
            defClass = Type.forName( defaultDefName );

            if (defClass != null) {
                defaults = (FieldDefaults)defClass.newInstance();
            }
        }
        else if (Type.forName(objectDefaultsClass) == null) {

            String defaultDefName = getDefaultsClassName(objectDefaultsClass);

            newObj = buildSObject(sObj, defaultDefName);

            defClass = Type.forName( defaultDefName );
            if (defClass != null) {
                defaults = (FieldDefaults)defClass.newInstance();
            }
        }
        else {
            newObj = buildSObject(sObj, objectDefaultsClass);

            defClass = Type.forName( objectDefaultsClass );
            if (defClass != null) {
                defaults = (FieldDefaults)defClass.newInstance();
            }
        }

        Schema.SObjectField nameField = getNameField(sObj);
        Boolean nameIsAutoNumber = isNameFieldAutoNumber(nameField);

        // Clone the object the number of times requested. Increment the name field so each record is unique
        for(Integer i = 0; i < numberOfObjects; i++) {
            SObject clonedSObj = newObj.clone(false, true);

            if(!nameIsAutoNumber && nameField != null) {
                clonedSObj.put(nameField, (String)clonedSObj.get(nameField) + ' ' + i);
            }

            if (defaults != null && !defaults.getUniqueFields().isEmpty()) {
                incrementFields(clonedSObj, defaults.getUniqueFields(), i);
            }

            sObjs.add(clonedSObj);
        }
        return sObjs;
    }

    /**********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/

    /**
     * @description method to add field defaults
     * @param sObj
     * @param defaults
     */
    private static void addFieldDefaults(SObject sObj, Map<Schema.SObjectField, Object> defaults) {
        // Loop through the map of fields and if they weren't specifically assigned, fill them.
        Map<String, Object> populatedFields = sObj.getPopulatedFieldsAsMap();
        for(Schema.SObjectField field : defaults.keySet()) {
            if(!populatedFields.containsKey(String.valueOf(field))) {
                sObj.put(field, defaults.get(field));
            }
        }
    }

    /**
     * @description method to increment fields
     * @param sObj
     * @param fields
     * @param index
     */
    private static void incrementFields(SObject sObj, Set<Schema.SObjectField> fields, Integer index) {
        // Loop through the map of fields and if they are null on the object, fill them.
        for (Schema.SObjectField field : fields) {
            if (sObj.get(field) != null) {

                String fieldtype = getFieldType( field );

                if (fieldtype == TYPE_STRING) {
                    sObj.put(field, sObj.get(field) + '-' + String.valueOf(index));
                }
                else if (fieldtype == TYPE_INTEGER) {
                    sObj.put(field, Integer.valueOf(sObj.get(field)) + index);
                }
                else if (fieldtype == TYPE_DOUBLE) {
                    sObj.put(field, Double.valueOf(sObj.get(field)) + (Double)index);
                }
                else {
                    Throw new TestFactoryException('Incompatible field type for: ' + field);
                }
            }
        }
    }

    /**
     * @description method to get field type
     * @param field
     * @return String
     */
    private static String getFieldType(Schema.SObjectField field) {

        Schema.DescribeFieldResult dfr = field.getDescribe();

        if (dfr.getType() == Schema.DisplayType.String){
            return TYPE_STRING;
        }
        else if (dfr.getType() == Schema.DisplayType.Integer) {
            return TYPE_INTEGER;
        }
        else if (dfr.getType() == Schema.DisplayType.Currency) {
            return TYPE_DOUBLE;
        }
        else if (dfr.getType() == Schema.DisplayType.Double) {
            return TYPE_DOUBLE;
        }
        else if (dfr.getType() == Schema.DisplayType.Email) {
            return TYPE_STRING;
        }
        else { 
            return null;
        }
    }

    /**
     * @description method to get name field
     * @param sObj
     * @return Schema.SObjectField
     */
    private static Schema.SObjectField getNameField (SObject sObj) {

        // Get the name field for the object
        String nameField = String.valueOf(nameFieldMap.get(sObj.getSObjectType()));

        if (nameField == null) {
            nameField = NAMESTRING;
        }

        // Check the SObject's field Name metadata and return if it is an auto number
        Schema.DescribeSObjectResult sobjResult = sObj.getSObjectType().getDescribe();
        Map<String, Schema.SObjectField> sobjectFields = sobjResult.fields.getMap();
        Schema.SObjectField field = sobjectFields.get(nameField);

        return field;
    }

    /**
     * @description method to check if field is AutoNumber
     * @param field
     * @return Boolean
     */
    private static Boolean isNameFieldAutoNumber(Schema.SObjectField field) {

        Schema.DescribeFieldResult fieldResult = field != null ? field.getDescribe() : null;
        return fieldResult != null && (fieldResult.isAutoNumber() || !fieldResult.isUpdateable());
    }

    // When we create a list of SObjects, we need to have a unique field for the insert if there isn't an autonumber field.
    // Usually we use the Name field, but some objects don't have a name field.
    private static Map<Schema.SObjectType, Schema.SObjectField> nameFieldMap = new Map<Schema.SObjectType, Schema.SObjectField> {
        Lead.sObjectType => Lead.LastName,
        Contact.sObjectType => Contact.LastName,
        Case.sObjectType => Case.CaseNumber, //this is the autonumber field
        User.sObjectType => User.LastName, 
        Lead.sObjectType => Lead.LastName    
    };

    private static String getDefaultsClassName (SObject sObj) {

        // Check what type of object we are creating and add any defaults that are needed.
        String objectName = String.valueOf(sObj.getSObjectType());

        // Construct the default values class. Salesforce doesn't allow '__' in class names
        String defaultClassName = objectName.replaceAll('__(c|C)$|__', '') + DEFAULTS_SUFFIX;
        
        return getDefaultsClassName( defaultClassName );
    }

    /**
     * @description get DefaultsClass Name
     * @param className
     * @return String
     */
    private static String getDefaultsClassName (String className) {
        
        String retValue;

        if (className != null 
            && !className.contains(DEFAULTS_PREFIX)) {

            retValue = DEFAULTS_PREFIX + className;
        }
        else {
            retValue = className;
        }
        
        return retValue;
    }

    /**********************************************************************************************
    *
    * Inner Classes
    *
    ***********************************************************************************************/

    /**
     * @description FieldDefaults Interface
     */
    public interface FieldDefaults {

        /**
         * @description getFieldDefaults abstract method
         * @return Map<Schema.SObjectField, Object>
         */
        Map<Schema.SObjectField, Object> getFieldDefaults();

        /**
         * @description getUniqueFields abstract method
         * @return Set<Schema.SObjectField>
         */
        Set<Schema.SObjectField> getUniqueFields();
    }

    /**********************************************************************************************
    *
    * Exceptions
    *
    ***********************************************************************************************/

    /**
     * @description Exception Class
     */
    public class TestFactoryException extends Exception {}

    /**********************SAMPLE USE CASE *********************************************************
    // The TestFactory will pre-fill all the fields we typically need
    Account acountObj = (Account)TestFactory.createSObject(
        new Account()
    );
    insert acountObj;

    // You can also set values to be used. Any values set in the constructor will override the defaults
    Opportunity o = (Opportunity)TestFactory.createSObject(
        new Opportunity(
            AccountId = acountObj.Id
        )
    );

    // You can also specify a specific set of overrides for different scenarios
    Account a = (Account)TestFactory.createSObject(new Account(
        Name = 'Test'
    ), 'PersonAccountDefaults');

    // Finally, get a bunch of records for testing bulk
    List<Account> accountList = (Lis<Account>)TestFactory.createSObjectList(
        new Account(
            Name = 'Test'
        ), 200);

    // You can initialize objects instead of inserting them like this
    Account accountObj = (Account) TestFactory.buildSObject(
        new Account(
            Name = 'Test'
        )
    );
    List<Contact> contactList = (List<Contact>) TestFactory.createSObjectList(
        new Contact(
            AccountID = a.Id
        ), 200
    );
    ******************************************************************************************/

}