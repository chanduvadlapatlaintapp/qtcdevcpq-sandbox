/**
 * @description Test class for Accounts
 * @author      Manisha
 * @date        2025-06-30
 * @jira        BIZ-70776
 */
@isTest
public class AccountsTest {
    
    @testSetup
    static void setupTestData() {
        List<User> userList = new List<User>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            for (Integer i = 1; i <= 4; i++) {
                User u = (User)TestFactory.buildSObject(
                    new User(LastName = 'TestUser' + i),
                    'AdminUserDefaults'
                );
                userList.add(u);
            }
            insert userList;
        }

        Account account = (Account)TestFactory.buildSObject(
            new Account(
                Name = 'Intapp',
                Type = 'Customer',
                CRD__c = userList.get(1).Id,
                OwnerId = userList.get(3).Id,
                Create_Prospect__c = '01',
                BillingStreet = '123 Street',
                BillingCity = 'New York',
                BillingPostalCode = '10001',
                BillingCountry = 'United States',
                BillingState = 'NY',
                ShippingStreet = '456 Avenue',
                ShippingCity = 'New York',
                ShippingPostalCode = '10001',
                ShippingCountry = 'United States',
                ShippingState = 'NY'
            ),
            'AccountDefaults'
        );
        insert account;

        Subscription__c sub = new Subscription__c(
            Account__c = account.Id,
            //CRD__c = userList.get(1).Id,
            Product_Line__c = 'Time'
        );
        insert sub;

        Contact contact1 = new Contact(
            AccountId = account.Id,
            //OwnerId = userList.get(1).Id,
            LastName = 'Primary Contact'
        );
        insert contact1;
    }
    
    @isTest static void testAccountDomainBehavior() {
        Account account = getAccount('Intapp');
        User crdUser2 = getUser('TestUser2');
        Account accountToUpdate = account.clone(false, true, false, false);
        accountToUpdate.Id = account.Id;
        account.Type = 'Customer - Lapsed';     
        account.CRD__c = crdUser2.Id;            
        account.OwnerId = crdUser2.Id;         

        Test.startTest();
        update account;
        Accounts acc = new Accounts(new List<Account>{account});
        acc.onvalidate();
        acc.onValidate(new Map<Id, Account>{account.Id => accountToUpdate});
        acc.onBeforeInsert();
        acc.onAfterInsert();
        acc.OnBeforeUpdate(new Map<Id, Account>{account.Id => accountToUpdate});
        acc.OnAfterUpdate(new Map<Id, Account>{account.Id => accountToUpdate});
        acc.someMethod();
        acc.onStatusChangeRemoveAccountManager(new Map<Id, Account>{account.Id => accountToUpdate});
        Test.stopTest();

        Subscription__c updatedSub = [SELECT CRD__c FROM Subscription__c LIMIT 1];
        System.assertEquals(crdUser2.Id, updatedSub.CRD__c, 'Subscription CRD should match Account CRD');

        Contact updatedContact = [SELECT OwnerId FROM Contact WHERE LastName = 'Primary Contact'];
        System.assertEquals(crdUser2.Id, updatedContact.OwnerId, 'Contact Owner should match new Account Owner');
    }
    
    /**
     * @description getter for Account
     * @param accName
     * @return Account
     */
    private static Account getAccount(String accName) {
        try {
            return [SELECT Id FROM Account WHERE Name = :accName LIMIT 1];
        } catch (QueryException e) {
            return null;
        }
    }
    
    /**
     * @description getter for User
     * @param userName
     * @return User
     */
    private static User getUser(String lastName) {
        try {
            return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
        } catch (QueryException e) {
            return null;
        }
    }
}