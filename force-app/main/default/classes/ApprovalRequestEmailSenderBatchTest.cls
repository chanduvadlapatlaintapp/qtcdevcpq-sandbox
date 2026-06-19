/** 
@description
    This class contains unit tests for the ApprovalRequestEmailSenderBatch class.
    It includes test methods for batch execution and schedulable execution.
    The test methods validate the functionality of the batch class and ensure that it behaves as expected.
* */
@isTest
public class ApprovalRequestEmailSenderBatchTest {

    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/
    public static Boolean emailStatus = false;

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    /** 
    @description
        This method sets up the test data for the ApprovalRequestEmailSenderBatchTest class.
        It creates a test user and an approval record for the batch to process.
    */
    @testSetup
    static void setupTestData() {
        // Create a test user
        User testUser = (User)TestFactory.createSObject(
            new User(
                LastName='ApprovalRequestEmailSenderBatchTest'
            ),
            'CRMOpsUserDefaults'
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            sbaa__Approver__c approver = (sbaa__Approver__c)TestFactory.createSObject(
                new sbaa__Approver__c(
                    Name = 'Main Approver', 
                    sbaa__User__c = testUser.Id
                )
            );

            // insert approval
            TestFactory.createSObject(
                new sbaa__Approval__c(
                    sbaa__Status__c = 'Requested',
                    sbaa__ApprovalStep__c = 1,
                    sbaa__RecordField__c = 'Name',
                    sbaa__Approver__c = approver.Id
                )
            );
        }
    }

    /**
     * @description
        This method tests the execution of the ApprovalRequestEmailSenderBatch class.
        It verifies that the batch processes the approval records correctly and sends emails.
        It uses a test user and an email template to simulate the batch execution.
    */
    @isTest
    static void testBatchExecution() {
        // Get test data
        EmailTemplate et = getEmailTemplate('PendingApprovalRequests');

        // Instantiate batch class
        ApprovalRequestEmailSenderBatch batch = new ApprovalRequestEmailSenderBatch(1, et.Id);

        // Execute the batch
        Test.startTest();
            Database.executeBatch(batch, 1);
        Test.stopTest();

        System.assertEquals(true, ApprovalRequestEmailSenderBatchTest.emailStatus, 'Batch did not execute successfully');
    }

    /**
     * @description
        This method tests the schedulable execution of the ApprovalRequestEmailSenderBatch class.
        It verifies that the scheduled job processes the approval records correctly and sends emails.
        It uses a test user and an email template to simulate the schedulable execution.
     */
    @isTest
    static void testSchedulableExecution() {
        // Get test data
        EmailTemplate et = getEmailTemplate('PendingApprovalRequests');
        User testUser = getUser('ApprovalRequestEmailSenderBatchTest');

        // Create and schedule job
        String cronExp = '0 0 5 * * ?';
        String query = 'SELECT Id, Name, Email FROM User WHERE Id = \'' + testUser.Id + '\'';
        ApprovalRequestEmailSenderBatch sched = new ApprovalRequestEmailSenderBatch(
            query, 1, et.Id
        );

        Test.startTest();
            System.schedule('Test Scheduled Batch Job', cronExp, sched);
            sched.execute(null);
        Test.stopTest();

        System.assertEquals(true, ApprovalRequestEmailSenderBatchTest.emailStatus, 'Batch did not execute successfully');
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /** 
    * @description getter for user
    * @param lastName
    * @return User
    */
    private static User getUser(String lastName) {
        // Fetch the test user
        List<User> users = [SELECT Id, Name, Email FROM User WHERE LastName = :lastName LIMIT 1];
        return users.isEmpty() ? null : users[0];
    }

    /** 
    * @description getter for email template
    * @param templateName
    * @return EmailTemplate
    */
    private static EmailTemplate getEmailTemplate(String templateName) {
        // Fetch the test email template
        List<EmailTemplate> emailTemplates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];
        return emailTemplates.isEmpty() ? null : emailTemplates[0];
    }
}