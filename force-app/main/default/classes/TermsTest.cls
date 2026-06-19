@isTest(SeeAllData = true)
private class TermsTest {

	@isTest static void testUpdateProductCustomerTermStartDate() {
		Term__c term = (Term__c) SmartFactory.createSObject('Term__c');
		Date startDate = date.today();
		term.Start_Date__c = startDate;
		term.Product_Customer_Number__c = 'a1A50000000a3iGEAQ';
		insert term;

		Subscription__c sub = [SELECT Most_Recent_Term_Start_Date__c FROM Subscription__c WHERE Id = 'a1A50000000a3iGEAQ' LIMIT 1];

		system.assertEquals(sub.Most_Recent_Term_Start_Date__c, startDate, 'Dates match');
	}
}