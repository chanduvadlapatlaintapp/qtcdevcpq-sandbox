/**
 * @author Manisha
 * @date 22/04/2025
 * @description Test class for StringUtil utility class
 * @jira N/A
 */
@isTest
private class StringUtilTest {

    /**********************************************************************************************
    *
    * Test Method: testGenerateUniqueString
    * @description Verifies that generateUniqueString returns a non-null, non-empty unique string.
    *
    ***********************************************************************************************/
    @isTest
    static void testGenerateUniqueString() {
        Test.startTest();

        String uniqueStr1 = StringUtil.generateUniqueString();
        String uniqueStr2 = StringUtil.generateUniqueString();

        Test.stopTest();

        System.debug('Generated Unique String 1: ' + uniqueStr1);
        System.debug('Generated Unique String 2: ' + uniqueStr2);

        System.assertNotEquals(null, uniqueStr1, 'Generated string should not be null');
        System.assertNotEquals('', uniqueStr1, 'Generated string should not be empty');
        System.assertNotEquals(null, uniqueStr2, 'Second generated string should not be null');
        System.assertNotEquals('', uniqueStr2, 'Second generated string should not be empty');
        System.assertNotEquals(uniqueStr1, uniqueStr2, 'Each call should produce a unique value');
    }
}