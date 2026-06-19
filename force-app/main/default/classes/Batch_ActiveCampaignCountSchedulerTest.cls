@isTest 
private class Batch_ActiveCampaignCountSchedulerTest {

	@isTest
	private static void testName() {
		List<Contact> contacts = new List<Contact>();
       for (Integer i = 0; i < 200; i++) {
           Contact c = new Contact(LastName = 'TestContact' + i);
           c.Active_Campaign_Count__c = 1 + i;
           contacts.add(c);
       }
       insert contacts;
        Batch_ActiveCampaignCountScheduler scheduler = new Batch_ActiveCampaignCountScheduler();
        
		String cronExpr = '0 0 0 * * ?';
		test.startTest();

		System.schedule('Test Scheduler Job', cronExpr, scheduler);
		
		test.stopTest();
       
       Integer expectedCount = contacts.size();
       Integer actualCount = [SELECT COUNT() FROM Contact WHERE Active_Campaign_Count__c > 0];
       System.assertEquals(expectedCount, actualCount, 'Batch job did not process all contacts.');      
	}
}