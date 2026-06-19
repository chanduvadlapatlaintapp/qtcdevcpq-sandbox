/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an organization are executed whenever Apex code is deployed
 * to a production organization to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production organization. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the organization size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class TestContractApprovalReminderEmails {
	//------------------------------------------------------------------------------------------------------
	//Test Method
	//------------------------------------------------------------------------------------------------------
	static testmethod void testSendReminderEmailsWithTemplate() {
		Account testAccount = IntappTestObjectFactory.createAccount(true);
		
		Contract testContract = IntappTestObjectFactory.createContract(testAccount.Id);
		testContract.Approver_1__c = UserInfo.getUserId();
		testContract.Approver_2__c = UserInfo.getUserId();	
		testContract.Approver_3__c = UserInfo.getUserId();	
		testContract.Approver_4__c = UserInfo.getUserId();	
		testContract.Approver_5__c = UserInfo.getUserId();
        testContract.Approver_6__c = UserInfo.getUserId();
		testContract.OwnerId = UserInfo.getUserId();
		insert testContract;
		
		// Create an approval for the account and submit
		Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest(); 
		req.setObjectId(testContract.ID);	
        req.setNextApproverIds(new List<Id>{UserInfo.getUserId()});
		Approval.ProcessResult res = Approval.Process(req);
		System.assert(res.isSuccess());	 

		// End create test data 
		Test.startTest();
		ContractApprovalReminderEmails aRE = new ContractApprovalReminderEmails();
		// the batch size can be no larger than 10 due to current apex email limits
		integer batchSize = 1;
		database.executebatch(ARE, batchSize);
		//increase code coverage by directly calling the method
		//since it won't get called in testing due to null values returned during testing only
		//I am using a standard salesforce sample here but need to change this if you removed the sample 
		ContractApprovalReminderEmails.FindEmailTemplateIDByDeveloperName('ContactFollowUpSAMPLE');
		//SendReminderEmail();
		Test.stopTest();
	} // end test method
	
	//------------------------------------------------------------------------------------------------------
	//Test Method
	//------------------------------------------------------------------------------------------------------
	static testmethod void testSendReminderEmailsWithoutTemplate() {
		ContractApprovalReminderEmails.ContractEmailTemplate = null;
		Account testAccount = IntappTestObjectFactory.createAccount(true); 
		
		Contract testContract = IntappTestObjectFactory.createContract(testAccount.Id);
		testContract.Approver_1__c = UserInfo.getUserId();
		testContract.Approver_2__c = UserInfo.getUserId();	
		testContract.Approver_3__c = UserInfo.getUserId();	
		testContract.Approver_4__c = UserInfo.getUserId();	
		testContract.Approver_5__c = UserInfo.getUserId();	
        testContract.Approver_6__c = UserInfo.getUserId();
		testContract.OwnerId = UserInfo.getUserId();
		insert testContract;
		
		// Create an approval for the account and submit
		Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest(); 
		req.setObjectId(testContract.ID);	
        req.setNextApproverIds(new List<Id>{UserInfo.getUserId()});
		Approval.ProcessResult res = Approval.Process(req);
		System.assert(res.isSuccess());	 

		/* End create test data */
		Test.startTest();
		ContractApprovalReminderEmails aRE = new ContractApprovalReminderEmails();
		// the batch size can be no larger than 10 due to current apex email limits
		integer batchSize = 1;
		database.executebatch(ARE, batchSize);
		//increase code coverage by directly calling the method
		//since it won't get called in testing due to null values returned during testing only
		//I am using a standard salesforce sample here but need to change this if you removed the sample 
		ContractApprovalReminderEmails.FindEmailTemplateIDByDeveloperName('ContactFollowUpSAMPLE');
		//SendReminderEmail();
		Test.stopTest();
	} // end test method	*/

}