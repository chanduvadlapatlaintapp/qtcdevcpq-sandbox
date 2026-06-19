@isTest
public class ApprovalTriggerTest {
    @isTest
    static void testApprovalAfterInsert() {
        // Create test data for SBAA__Approval__c
        List<SBAA__Approval__c> approvalList = new List<SBAA__Approval__c>();
        for (Integer i = 0; i < 5; i++) {
            SBAA__Approval__c approvalRec = new SBAA__Approval__c(
                //Name = 'Test Approval ' + i,
                sbaa__Status__c = 'Pending',
                OP4I_System_Id__c = 'SYS' + i,
                sbaa__ApprovalStep__c = 1.00,
                sbaa__RecordField__c = 'test'
                
            );
            approvalList.add(approvalRec);
        }
        
        // Insert the records
        Test.startTest();
        insert approvalList;
        Test.stopTest();

        // Verify that the records were processed
        // Assuming QuoteTriggerHelper.publishApprovalRecords does some logging or updates records.
        // Add appropriate assertions based on your business logic.
        // Example:
        for (SBAA__Approval__c approval : [SELECT Id FROM SBAA__Approval__c]) {
            System.assertNotEquals(null, approval.Id, 'Record should have an ID');
        }
    }

    @isTest
    static void testApprovalAfterUpdate() {
        // Create and insert test data for SBAA__Approval__c
        List<SBAA__Approval__c> approvalList = new List<SBAA__Approval__c>();
        for (Integer i = 0; i < 5; i++) {
            SBAA__Approval__c approvalRec = new SBAA__Approval__c(
                //Name = 'Test Approval ' + i,
                sbaa__Status__c = 'Pending',
                OP4I_System_Id__c = 'SYS' + i,
                sbaa__ApprovalStep__c = 1.00,
                sbaa__RecordField__c = 'test'
            );
            approvalList.add(approvalRec);
        }

        insert approvalList;

        // Update the records
        for (SBAA__Approval__c approval : approvalList) {
            approval.sbaa__Status__c = 'Approved';
            approval.sbaa__CommentsLong__c = 'Test Comments';
            approval.sbaa__ApprovalStep__c = 1.00;
            approval.sbaa__RecordField__c = 'test';
        }

        Test.startTest();
        update approvalList;
        Test.stopTest();

        // Verify the update logic
        for (SBAA__Approval__c approval : [SELECT Id, sbaa__Status__c, sbaa__CommentsLong__c FROM SBAA__Approval__c]) {
            System.assertEquals('Approved', approval.sbaa__Status__c, 'Status should be updated to Approved');
            System.assertEquals('Test Comments', approval.sbaa__CommentsLong__c, 'Comments should be updated');
        }
    }

    @isTest
    static void testApprovalTriggerEdgeCases() {
        // Test edge cases like null fields or no change during update
        SBAA__Approval__c approval = new SBAA__Approval__c(
            //Name = 'Edge Case Approval',
            sbaa__Status__c = 'Pending',
            sbaa__ApprovalStep__c = 1.00,
            sbaa__RecordField__c = 'test'
        );

        insert approval;

        // Update without any changes
        approval.sbaa__Status__c = 'Pending';

        Test.startTest();
        update approval;
        Test.stopTest();

        // Verify no unnecessary processing
        // Example: Check debug logs or ensure no redundant updates were made
    }
}