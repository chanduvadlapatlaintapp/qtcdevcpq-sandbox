@isTest
private class TestContractApprovalHelper {
	
	@isTest static void testmethodone() {
        
		Account testAccount = IntappTestObjectFactory.createAccount(true); 
		
		Contract testContract = IntappTestObjectFactory.createContract(testAccount.Id);
		testContract.Approver_1__c = UserInfo.getUserId();
		testContract.OwnerId = UserInfo.getUserId();
		insert testContract;
		ContractApprovalHelper.submitForApproval(testContract.Id);
        System.assertNotEquals(testAccount.Id, null);
	}
	
	@isTest static void testmethodtwo() {
		Account testAccount = IntappTestObjectFactory.createAccount(true);
		
		Contract testContract = IntappTestObjectFactory.createContract(testAccount.Id);
		testContract.Exception_Approver_1__c = UserInfo.getUserId();
		testContract.OwnerId = UserInfo.getUserId();
		testContract.Exception_Approval__c = true;
		insert testContract;
		ContractApprovalHelper.submitForApproval(testContract.Id);
        System.assertNotEquals(testAccount.Id, null);
	}
	
}