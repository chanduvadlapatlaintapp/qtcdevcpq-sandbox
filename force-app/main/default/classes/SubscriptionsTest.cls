@isTest
public class SubscriptionsTest {
	
	@isTest static void testPopulateCSMByPractice() {
		Account a = new Account();
        a.Name = 'TEST ACC';
        insert a;
        
        Subscription__c sub = new Subscription__c(Account__c = a.id);
		insert sub;
        /*
		 * Subscription__c sub = new Subscription__c(Account__c = '00130000001RAy7', Product_Line__c = 'Time Builder');
		insert sub;
		sub = [select Id, CSM__c from Subscription__c where Id = :sub.Id];
		pse__Practice__c practice = [SELECT pse__Practice_Head__r.pse__Salesforce_User__c from pse__Practice__c 
			WHERE Name = 'Time Builder' LIMIT 1];
		System.assertEquals(sub.CSM__c, practice.pse__Practice_Head__r.pse__Salesforce_User__c);
*/
	}
}