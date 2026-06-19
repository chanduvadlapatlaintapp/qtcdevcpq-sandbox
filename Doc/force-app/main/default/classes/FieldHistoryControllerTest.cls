/**
 * @description Test class for FieldHistoryController
 * @author Sahal
 * @createdDate Jan-05-2026
 */
@isTest
private class FieldHistoryControllerTest {
    
    /***************************************************************************************************
     *
     * Test Setup
     *
     **************************************************************************************************/
    @testSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            Industry = 'Technology'
        );
        insert testAccount;
        
        // Create field history records
        List<Field_History__c> historyRecords = new List<Field_History__c>();
        DateTime baseDate = DateTime.now();
        for (Integer i = 0; i < 5; i++) {
            historyRecords.add(new Field_History__c(
                Parent_Record__c = String.valueOf(testAccount.Id),
                Parent_Object_Type__c = 'Account',
                Field_Name__c = 'Name',
                Field_Label__c = 'Account Name',
                Old_Value__c = 'Old Value ' + i,
                New_Value__c = 'New Value ' + i,
                Change_Type__c = 'Update',
                Changed_By__c = UserInfo.getUserId(),
                Change_Date__c = baseDate.addMinutes(-i) // Different dates for sorting test
            ));
        }
        insert historyRecords;
    }
    
    /***********************************************************************************************************************
     *
     * Controller Tests
     *
     ************************************************************************************************************************/
    @isTest
    static void testGetFieldHistoryRecords() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        List<Field_History__c> historyRecords = FieldHistoryController.getFieldHistoryRecords(testAccount.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, historyRecords, 'History records should not be null');
        System.assert(historyRecords.size() > 0, 'Should return history records');
        System.assertEquals('Account', historyRecords[0].Parent_Object_Type__c, 'Should return records for Account');
        
        // Verify records are ordered by Change_Date__c descending
        if (historyRecords.size() > 1) {
            for (Integer i = 0; i < historyRecords.size() - 1; i++) {
                DateTime currentDate = historyRecords[i].Change_Date__c;
                DateTime nextDate = historyRecords[i + 1].Change_Date__c;
                if (currentDate != null && nextDate != null) {
                    System.assert(currentDate >= nextDate, 'Records should be in descending order by Change_Date__c');
                }
            }
        }
    }
    
    @isTest
    static void testGetFieldHistoryRecords_EmptyId() {
        Test.startTest();
        List<Field_History__c> historyRecords = FieldHistoryController.getFieldHistoryRecords('');
        Test.stopTest();
        
        System.assertNotEquals(null, historyRecords, 'Should return empty list, not null');
        System.assertEquals(0, historyRecords.size(), 'Should return empty list for empty ID');
    }
    
    @isTest
    static void testGetFieldHistoryRecords_NullId() {
        Test.startTest();
        List<Field_History__c> historyRecords = FieldHistoryController.getFieldHistoryRecords(null);
        Test.stopTest();
        
        System.assertNotEquals(null, historyRecords, 'Should return empty list, not null');
        System.assertEquals(0, historyRecords.size(), 'Should return empty list for null ID');
    }
    
    @isTest
    static void testGetFieldHistoryCount() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        Integer count = FieldHistoryController.getFieldHistoryCount(testAccount.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, count, 'Count should not be null');
        System.assert(count >= 0, 'Count should be non-negative');
        System.assert(count >= 5, 'Should return at least 5 records from test data');
    }
    
    @isTest
    static void testGetFieldHistoryCount_EmptyId() {
        Test.startTest();
        Integer count = FieldHistoryController.getFieldHistoryCount('');
        Test.stopTest();
        
        System.assertEquals(0, count, 'Should return 0 for empty ID');
    }
    
    @isTest
    static void testGetFieldHistoryCount_NullId() {
        Test.startTest();
        Integer count = FieldHistoryController.getFieldHistoryCount(null);
        Test.stopTest();
        
        System.assertEquals(0, count, 'Should return 0 for null ID');
    }
}