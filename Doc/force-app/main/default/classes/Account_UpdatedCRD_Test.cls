@isTest (SeeAllData = true)
public class Account_UpdatedCRD_Test {
    static testMethod void testUpdateAccountCRD()
    {
        List<Account> accts = [SELECT Id from Account where Id = '00130000000WLqDAAW'];
        if (accts.size() > 0)
            {
            Account a = accts[0];
            List<User> users = [SELECT Id from User where name='Alan Westley'];
            if (users.size() > 0)
            {
                a.CRD__c = users[0].Id;
                update a;
            }
        }
    }
}