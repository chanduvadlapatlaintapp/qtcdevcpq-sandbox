@isTest (SeeAllData = true)
public class Test_AccountOwnerChage {
    static testMethod void AccountOwnerChange() {
        Account acc = [Select Id from Account WHERE Name = 'Goodmans LLP' LIMIT 1];
        User u = [Select Id from User WHERE Alias = 'judya' LIMIT 1];
        acc.OwnerId = u.Id;
        update acc;
    }
}