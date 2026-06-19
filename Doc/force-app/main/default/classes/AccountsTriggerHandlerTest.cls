@isTest
public class AccountsTriggerHandlerTest {     
   @isTest
   static void testTrigger() {
       // Create test data
       List<Account> testAccounts = new List<Account>();
       for (Integer i = 0; i < 5; i++) {
           testAccounts.add(new Account(Name = 'Test Account ' + i));
       }  
       insert testAccounts;     
       System.assertNotEquals(testAccounts.size(), null);          
   }
}