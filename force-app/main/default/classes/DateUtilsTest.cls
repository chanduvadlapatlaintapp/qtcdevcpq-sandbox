/**
 * @author : Suresh Kumar
 * @description : Test class for DateUtil class with locale-specific scenarios
 * @jira : BIZ-67254
 **/
@isTest
private class DateUtilsTest {

    private static User createUserWithLocale(String localeCode) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'testusr',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'LocaleTester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = localeCode,
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = 'testuser' + localeCode + '@example.com'
        );
        return u;
    }

    @isTest
    static void testValidDateConversionUS() {
        User enUser = createUserWithLocale('en_US');
        insert enUser;

        System.runAs(enUser) {
            String dateStr = '4/17/2025';
            Date expectedDate = Date.newInstance(2025, 4, 17);
            Date actualDate = DateUtils.stringToDate(dateStr);

            System.assertEquals(expectedDate, actualDate, 'Parsed date should match expected date for en_US locale.');
        }
    }

    @isTest
    static void testValidDateConversionGB() {
        User gbUser = createUserWithLocale('en_GB');
        insert gbUser;

        System.runAs(gbUser) {
            String dateStr = '4/17/2025';//OP4I always provides date in US Format
            Date expectedDate = Date.newInstance(2025, 4, 17);
            Date actualDate = DateUtils.stringToDate(dateStr);

            System.assertEquals(expectedDate, Date.Parse(actualDate.format()), 'Parsed date should match expected date for en_US locale.');
        
        }
    }

    @isTest
    static void testValidDateConversion() {
        // Positive test: Valid date string
        String dateStr = '4/17/2025';
        Date expectedDate = Date.newInstance(2025, 4, 17);
        Date actualDate = DateUtils.stringToDate(dateStr);
        
        System.assertEquals(expectedDate, actualDate, 'The parsed date should match the expected date.');
    }

    @isTest
    static void testInvalidFormatTooFewParts() {
        // Negative test: Not enough parts in the date string
        try {
            DateUtils.stringToDate('4/2025');
            System.assert(false, 'Expected an exception for invalid date format.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Date format must be MM/DD/YYYY'), 'Expected format error.');
        }
    }

    @isTest
    static void testInvalidFormatNonNumeric() {
        // Negative test: Non-numeric values
        try {
            DateUtils.stringToDate('April/17/2025');
            System.assert(false, 'Expected an exception for non-numeric input.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Invalid date string'), 'Expected parsing error.');
        }
    }

    @isTest
    static void testNullInput() {
        // Negative test: Null input
        try {
            DateUtils.stringToDate(null);
            System.assert(false, 'Expected an exception for null input.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('cannot be null or empty'), 'Expected null/empty error.');
        }
    }

    @isTest
    static void testEmptyStringInput() {
        // Negative test: Empty string input
        try {
            DateUtils.stringToDate('');
            System.assert(false, 'Expected an exception for empty string.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('cannot be null or empty'), 'Expected empty error.');
        }
    }
}