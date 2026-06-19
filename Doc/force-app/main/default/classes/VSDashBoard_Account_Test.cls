@isTest public class VSDashBoard_Account_Test {
    public static testMethod void runTests() {
        
        Account acc = new Account();
        acc.name = 'Test Account';
        acc.Type = 'Prospect';
        acc.RecordTypeId = Schema.sObjectType.Account.getRecordTypeInfosByName().get('Accounts - Accounting').getRecordTypeId();
        insert acc;
        
        Test.startTest();
        PageReference ref = Page.Account_Dashboard;
        ref.getParameters().put('id', acc.Id);
        Test.setCurrentPage(ref);
        VSDashBoard_Account controller = new VSDashBoard_Account();
        
        Account account = controller.getAccount();
        system.assertNotEquals(null,account,'Account is Present');
        
        List<Case> cases = controller.getCases();
        //system.Assert(cases.size() > 0);
        
        List<Subscription__c> subs = controller.getSubscriptions();
        //system.Assert(subs.size() > 0);        
        
        Test.stopTest();
    }
}