/**
 * @description Test class for IntappMetadataHelper
 * @author      Manisha
 * @date        2025-06-30
 * @jira        BIZ-70776
 */
@isTest
public class IntappMetadataHelperTest {

    /**
     * @description Test method to verify GetPicklistValues works for a standard picklist field.
     * Uses Account.Industry which is a standard picklist in Salesforce.
     */
    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        List<String> picklistValues = IntappMetadataHelper.GetPicklistValues('Account', 'Industry');
        Test.stopTest();

        System.assertNotEquals(null, picklistValues, 'Picklist values should not be null');
        System.assert(!picklistValues.isEmpty(), 'Picklist values should not be empty');
    }

    /**
     * @description Negative test to ensure method handles invalid object/field names gracefully.
     */
    @isTest
    static void testInvalidInputs() {
        Test.startTest();
        try {
            List<String> result = IntappMetadataHelper.GetPicklistValues('InvalidObject', 'InvalidField');
            System.assert(false, 'Exception should have been thrown for invalid inputs.');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('null'), 'Expected null dereference on invalid describe.');
        }
        Test.stopTest();
    }
}