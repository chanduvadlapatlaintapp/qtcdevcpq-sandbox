/**
 * @description
 * This class tests the ApprovalRequestController class.
 */
@isTest
private class ApprovalRequestControllerTest {
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
                LastName='ApprovalRequestControllerTest'
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
            
            // Create an Account
            Account testAccount = (Account)TestFactory.createSObject(
                new Account(Name = 'test acc1'), 
                'AccountDefaults'
            );
            
            // Create an Opportunity
            Opportunity testOpportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                CloseDate = Date.today(),
                AccountId = testAccount.Id,
                //SBQQ__RenewedContract__c = testContract.Id,
                OP4I_Auto_Number_Deal_ID__c = '12345'
            ), 'OpportunityDefaults');


            SBQQ__Quote__c testQuote = new SBQQ__Quote__c(
                    SBQQ__Opportunity2__c = testOpportunity.Id,
                    SBQQ__Account__c = testOpportunity.AccountId
                );
            Insert testQuote;
            
            // insert approval
            TestFactory.createSObject(
                new sbaa__Approval__c(
                    sbaa__Status__c = 'Requested',
                    sbaa__ApprovalStep__c = 1,
                    sbaa__RecordField__c = 'Name',
                    sbaa__Approver__c = approver.Id,
                    Quote__c = testQuote.Id
                )
            );
        }
    }

    /**
     * @description
        This method tests the execution of the ApprovalRequestEmailSenderBatch class.
     */
    @isTest
    static void testGetRelevantUserIdsFromApprovals() {
        Test.startTest();
        Set<Id> resultUserIds = ApprovalRequestController.getRelevantUserIdsFromApprovals();
        Test.stopTest();

        User testUser = getUser('ApprovalRequestControllerTest');

        System.assert(resultUserIds.contains(testUser.Id), 'Expected test user ID in result');
        System.assertEquals(1, resultUserIds.size(), 'Should contain only one unique user ID');
    }

    /**
     * @description
        This method tests the execution of the ApprovalRequestEmailSenderBatch class.
     */
    @isTest
    static void testApprovalRequestController() {
        // Use runAs to simulate context
        User testUser = getUser('ApprovalRequestControllerTest');
        System.runAs(testUser) {
            Test.startTest();
            
            ApprovalRequestController controller = new ApprovalRequestController();
            controller.usrId = testUser.Id;

            List<ApprovalRequestController.ApprovalWrapper> wrappers = controller.approvalRequests;
            Test.stopTest();

            // Assertions
            System.assertNotEquals(null, wrappers, 'Approval wrappers should not be null');
            System.assertEquals(1, wrappers.size(), 'Should return 1 approval wrapper');
        }
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
}