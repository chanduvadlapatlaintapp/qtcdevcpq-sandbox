/*********************************************************************************************************     
 *  Name             :  Batchable_ActiveCampaignCountTest
 *  Author           :  Anisha
 *  Description      :  Test class for Scheduler Batch_ActiveCampaignCountScheduler
 *
 *  Change history   :
 *  Date            Author                      Description
 *  05/10/2018      Anisha Dhekne               Created
 *********************************************************************************************************/
@isTest
private class Batchable_ACCSchedulerTest {

	@isTest
	private static void testName() {
		User usr = (User) SmartFactory.createSObject('User');
		insert usr;

		List<CampaignMember> list_cm = new List<CampaignMember> ();
		List<Campaign> list_camp = new List<Campaign> ();

		Contact con = (Contact) SmartFactory.createSObject('Contact');
		insert con;

		Campaign camp = (Campaign) SmartFactory.createSObject('Campaign');
		camp.Name = 'test';
		camp.IsActive = false;
		camp.CurrencyIsoCode = 'USD';
		camp.Type = 'Email';
        camp.Program_Type__c = 'Funnel Development/Velocity';
        camp.Segment_Focus__c = 'Global';
		insert camp;

		Campaign camp1 = (Campaign) SmartFactory.createSObject('Campaign');
		camp1.Name = 'test';
		camp1.IsActive = false;
		camp1.CurrencyIsoCode = 'USD';
		camp1.Type = 'Email';
        camp1.Program_Type__c = 'Reputation/Awareness';
        camp1.Segment_Focus__c = 'EMEA';
		insert camp1;

		CampaignMember cmpmem = (CampaignMember) SmartFactory.createSObject('CampaignMember');
		cmpmem.ContactId = con.Id;
		cmpmem.CampaignId = camp.Id;
		list_cm.add(cmpmem);

		CampaignMember cmpmem1 = (CampaignMember) SmartFactory.createSObject('CampaignMember');
		cmpmem1.ContactId = con.Id;
		cmpmem1.CampaignId = camp1.Id;
		list_cm.add(cmpmem1);

		System.runAs(usr)
		{
			insert list_cm;
		}
		con.Active_Campaign_Count__c = [Select Active_Campaign_Count__c from Contact where Id = :con.Id].Active_Campaign_Count__c;
		update(list_camp);
		update(list_cm);

		String cronExpr = '0 0 0 15 3 ? 2026';
		test.startTest();
		//Batch_ActiveCampaignCountScheduler bca = new Batch_ActiveCampaignCountScheduler();
		String jobId =	System.schedule('Batch_ActiveCampaignCountScheduler', cronExpr, new Batch_ActiveCampaignCountScheduler());
		//bca.query = bca.query + 'Limit 200';
		//Id bcaId = Database.executeBatch(bca,200);
		//Database.executeBatch(bca);
		test.stopTest();
	}
}