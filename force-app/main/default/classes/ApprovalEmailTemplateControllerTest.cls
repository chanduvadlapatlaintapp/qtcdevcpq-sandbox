/**
* @author      : Manisha
* @date        : 15/04/2025
* @description : Test class for ApprovalEmailTemplateController
* @jira        : BIZ-68135
**/
@isTest
public class ApprovalEmailTemplateControllerTest {
    
    /***********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
     /**
    * @description Insert shared test data using TestDataFactory
	*/
    @testSetup
    public static void setup() {
        // Create an admin user for testing
        User adminUser = (User)TestFactory.createSObject(
            new User(
                LastName = 'RetryContractRenewalBatchTest',
                Email = 'admin@test.com'
            ), 'AdminUserDefaults');
        System.runAs(adminUser) {
            
            // Create an Account
            Account objAcc = (Account)TestFactory.createSObject(
                new Account(
                    Name = 'Test MS'
                ), 'AccountDefaults');
            
            // Create test Opportunities
            List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
                new Opportunity(
                    Name = 'Test Opportunity', 
                    StageName = OpportunityConstants.STAGE_PROSPECTING,
                    CloseDate = Date.today().addMonths(1),
                    OwnerId = adminUser.Id,
                    AccountId = objAcc.Id
                ), 3, 'OpportunityDefaults'
            );
            
            SBQQ.TriggerControl.disable();
            // Create test Quotes associated with Opportunities (SBQQ__Opportunity2__c)
            List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
            for (Opportunity opp : opportunities) {
                List<SBQQ__Quote__c> quote = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
                    new SBQQ__Quote__c(
                        SBQQ__Primary__c = true, 
                        SBQQ__Opportunity2__c = opportunities[0].Id 
                    ), 1,'SBQQQuoteDefaults'
                );
                quotes.addAll(quote);
            }
            
            sbaa__ApprovalChain__c approvalChain = (sbaa__ApprovalChain__c) TestFactory.buildSObject(
                new sbaa__ApprovalChain__c(
                    Name = 'Test Approval Chain'
                )
            );
            insert approvalChain;
            
            // Step 2: Create Prior Approvals (Steps 1 and 2)
            List<sbaa__Approval__c> priorApprovals = new List<sbaa__Approval__c>();
            for (Integer i = 0; i <= 2; i++) {
                sbaa__Approval__c priorApproval = (sbaa__Approval__c) TestFactory.buildSObject(
                    new sbaa__Approval__c(
                        sbaa__ApprovalChain__c = approvalChain.Id,
                        sbaa__Status__c = ApprovalConstants.STATUS_APPROVED,
                        sbaa__CommentsLong__c = 'Approved comment ' + i,
                        sbaa__ApprovalStep__c = i,
                        Quote__c = quotes[0].Id, // assumes Quote already exists
                        sbaa__AssignedTo__c = UserInfo.getUserId()
                    )
                );
                priorApprovals.add(priorApproval);
            }
            insert priorApprovals;
            
            // Step 3: Create the next (Pending) Approval (Step 3)
            sbaa__Approval__c nextApproval = (sbaa__Approval__c) TestFactory.buildSObject(
                new sbaa__Approval__c(
                    sbaa__ApprovalChain__c = approvalChain.Id,
                    sbaa__Status__c = ApprovalConstants.STATUS_ASSIGNED,
                    sbaa__CommentsLong__c = 'Pending approval',
                    sbaa__ApprovalStep__c = 3,
                    Quote__c = quotes[0].Id,
                    sbaa__AssignedTo__c = UserInfo.getUserId()
                )
            );
            insert nextApproval;
            SBQQ.TriggerControl.enable();
        }
    }
    
    /***********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/
    
    /**
    * @description Unit test for getPriorApprovals() method
    */
    @isTest
    static void testGetPriorApprovals() {
        SBQQ__Quote__c quote = getQuote();
        
        Test.startTest();
            ApprovalEmailTemplateController controller = new ApprovalEmailTemplateController();
            controller.quoteId = quote.Id;
            List<sbaa__Approval__c> results = controller.getPriorApprovals();
        Test.stopTest();
        
        System.assertEquals(3, results.size(), 'Should return 3 approved approvals');
        System.assertEquals('Approved comment 0', results[0].sbaa__CommentsLong__c, 'Approved comment is different');
    }
    
    /**
    * @description Unit test for getNextApproverName() method
    */
    @isTest
    static void testGetNextApproverName() {
        List<sbaa__Approval__c> approvals = getApprovals(ApprovalConstants.STATUS_APPROVED);
        SBQQ__Quote__c quote = getQuote();
        sbaa__Approval__c currentApproval = approvals[0];
        
        Test.startTest();
            ApprovalEmailTemplateController controller = new ApprovalEmailTemplateController();
            controller.approvalId = currentApproval.Id;
            controller.quoteId = quote.Id;
            String nextApproverName = controller.getNextApproverName();
        Test.stopTest();
        
        System.assertNotEquals(null, nextApproverName, 'Next approver name should not be null');
    }

    /***********************************************************************************************
    *
    * Getter Methods
    *
    ***********************************************************************************************/
    /**
    * @description getter for quote
    * @return SBQQ__Quote__c
    */
    private static SBQQ__Quote__c getQuote() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
    }

    /**
    * @description getter for approvals
    * @param status
    * @return List<sbaa__Approval__c>
    */
    private static List<sbaa__Approval__c> getApprovals(String status) {
        return [SELECT Id, Quote__c 
                FROM sbaa__Approval__c 
                WHERE sbaa__Status__c = :status 
                ORDER BY sbaa__ApprovalStep__c ASC];
    }
    
}