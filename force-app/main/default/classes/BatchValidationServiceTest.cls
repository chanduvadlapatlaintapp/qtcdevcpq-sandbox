/**
 * @description Test class for BatchValidationService.
 * @details Tests validation logic for account pairs, cleanup inputs, CSV rows, and general data integrity checks.
 * @author Sahal Mohamed
 * @createdDate 2026-01-13
 */
@isTest
public class BatchValidationServiceTest {

    /***********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/

    /**
     * @description Tests isValidAccountPair with valid and invalid inputs.
     */
    @isTest
    static void testIsValidAccountPair() {
        // Setup data
        Account a1 = new Account(Id = '001000000000001AAA', Name = 'A1');
        Account a2 = new Account(Id = '001000000000002AAA', Name = 'A2');
        
        Map<String, Account> accountMap = new Map<String, Account>{
            'id1' => a1,
            'id2' => a2
        };

        AccountMergeBatch.AccountDetail validPair = new AccountMergeBatch.AccountDetail('id1', 'id2');
        AccountMergeBatch.AccountDetail invalidSurviving = new AccountMergeBatch.AccountDetail('invalid', 'id2');
        AccountMergeBatch.AccountDetail invalidMerge = new AccountMergeBatch.AccountDetail('id1', 'invalid');

        Test.startTest();
        Boolean isValid = BatchValidationService.isValidAccountPair(validPair, accountMap);
        Boolean isInvalid1 = BatchValidationService.isValidAccountPair(invalidSurviving, accountMap);
        Boolean isInvalid2 = BatchValidationService.isValidAccountPair(invalidMerge, accountMap);
        Test.stopTest();

        System.assertEquals(true, isValid, 'Should be valid when both IDs exist in map');
        System.assertEquals(false, isInvalid1, 'Should be invalid when surviving ID missing');
        System.assertEquals(false, isInvalid2, 'Should be invalid when merge ID missing');
    }

    /**
     * @description Tests isValidCleanupInput with various set combinations.
     */
    @isTest
    static void testIsValidCleanupInput() {
        Set<Id> ids1 = new Set<Id>{'001000000000001AAA'};
        Set<Id> ids2 = new Set<Id>{'001000000000002AAA'};
        Set<Id> emptySet = new Set<Id>();

        Test.startTest();
        Boolean valid = BatchValidationService.isValidCleanupInput(ids1, ids2);
        Boolean invalidEmpty1 = BatchValidationService.isValidCleanupInput(emptySet, ids2);
        Boolean invalidEmpty2 = BatchValidationService.isValidCleanupInput(ids1, emptySet);
        Boolean invalidNull1 = BatchValidationService.isValidCleanupInput(null, ids2);
        Boolean invalidNull2 = BatchValidationService.isValidCleanupInput(ids1, null);
        Test.stopTest();

        System.assertEquals(true, valid, 'Should be valid with populated sets');
        System.assertEquals(false, invalidEmpty1, 'Should be invalid with empty surviving set');
        System.assertEquals(false, invalidEmpty2, 'Should be invalid with empty merge set');
        System.assertEquals(false, invalidNull1, 'Should be invalid with null surviving set');
        System.assertEquals(false, invalidNull2, 'Should be invalid with null merge set');
    }

    /**
     * @description Tests isValidCsvRow for correct column counts.
     */
    @isTest
    static void testIsValidCsvRow() {
        List<String> row3 = new List<String>{'a', 'b', 'c'};
        List<String> row2 = new List<String>{'a', 'b'};

        Test.startTest();
        Boolean valid = BatchValidationService.isValidCsvRow(row3, 3);
        Boolean invalidCount = BatchValidationService.isValidCsvRow(row2, 3);
        Boolean invalidNull = BatchValidationService.isValidCsvRow(null, 3);
        Test.stopTest();

        System.assertEquals(true, valid, 'Should be valid when size matches expected');
        System.assertEquals(false, invalidCount, 'Should be invalid when size differs');
        System.assertEquals(false, invalidNull, 'Should be invalid when row is null');
    }

    /**
     * @description Tests hasItems for list validation.
     */
    @isTest
    static void testHasItems() {
        List<String> populated = new List<String>{'item'};
        List<String> empty = new List<String>();

        Test.startTest();
        Boolean hasItems = BatchValidationService.hasItems(populated);
        Boolean noItems = BatchValidationService.hasItems(empty);
        Boolean nullItems = BatchValidationService.hasItems(null);
        Test.stopTest();

        System.assertEquals(true, hasItems, 'Should be true for populated list');
        System.assertEquals(false, noItems, 'Should be false for empty list');
        System.assertEquals(false, nullItems, 'Should be false for null list');
    }

    /**
     * @description Tests isNotBlank for string validation.
     */
    @isTest
    static void testIsNotBlank() {
        Test.startTest();
        Boolean notBlank = BatchValidationService.isNotBlank('value');
        Boolean blank = BatchValidationService.isNotBlank('');
        Boolean nullStr = BatchValidationService.isNotBlank(null);
        Test.stopTest();

        System.assertEquals(true, notBlank, 'Should be true for non-blank string');
        System.assertEquals(false, blank, 'Should be false for empty string');
        System.assertEquals(false, nullStr, 'Should be false for null string');
    }
}