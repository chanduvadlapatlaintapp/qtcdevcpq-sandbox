@isTest
public class PendingApprovalControllerTest {
    
    /**
    * @testSetup
    * Creates test user, account, and contract data using factory.
    */
    @testSetup
    static void setupData() {
        // Create User
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User usr = new User(
            Alias = 'testu',
            LastName = 'test',
            Email = 'approveruser@example.com',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'approveruser@example.com'
        );
        insert usr;
        
        // Create Account using factory
        List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
            new Account(Name = 'Test Account'),
            1,
            'AccountDefaults'
        );
        
        // Create Contract using factory
        List<Contract> contracts = (List<Contract>) TestFactory.createSObjectList(
            new Contract(
                AccountId = accounts[0].Id,
                StartDate = Date.today(),
                EndDate = Date.today().addMonths(6),
                Approval_Request_Notes__c = 'Pending approval notes',
                Approver_1__c = UserInfo.getUserId(),
                Approver_2__c = UserInfo.getUserId(),
                Approver_3__c = UserInfo.getUserId(),
                Approver_4__c = UserInfo.getUserId(),
                Approver_5__c = UserInfo.getUserId(),
                Approver_6__c = UserInfo.getUserId(),
                OwnerId      = UserInfo.getUserId()
            ),
            1,
            'ContractDefaults'
        );
        
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest(); 
        req.setObjectId(contracts[0].Id);
        req.setNextApproverIds(new List<Id>{ usr.Id }); 
        Approval.ProcessResult res = Approval.process(req);
        
    }
    
    @isTest
    static void testGetPendingApprovals() {
        User usr = [SELECT Id FROM User WHERE Email = 'approveruser@example.com' LIMIT 1];
        
        PendingApprovalController controller = new PendingApprovalController();
        controller.usrId = usr.Id;
        
        List<PendingApprovalController.resultWrapper> results = controller.getPendingApprovals();
        
        String baseDomain = controller.domain;
        System.assertNotEquals(null, baseDomain, 'Domain should not be null');
        
        System.debug('results '+results);
        if (!results.isEmpty()) {
            PendingApprovalController.resultWrapper wrapper = results[0];
            
            System.assertNotEquals(null, wrapper.contract, 'Contract in wrapper should not be null');
            System.assertNotEquals(null, wrapper.pwi, 'Workitem in wrapper should not be null');
        }
    }
    
}