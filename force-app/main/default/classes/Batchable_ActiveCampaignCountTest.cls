/*********************************************************************************************************     
 *  Name             :  Batchable_ActiveCampaignCountTest
 *  Author           :  Anisha
 *  Description      :  Handler class to control creation of new Idea by Customers.
 *
 *  Change history   :
 *  Date            Author                      Description
 *  05/09/2018      Anisha Dhekne               Test class for Batchable_Contact_ActiveCampaignCount
 *  
 *********************************************************************************************************/
 @isTest
private class Batchable_ActiveCampaignCountTest
{

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
        camp.Program_Type__c = 'Reputation/Awareness';
        camp.Segment_Focus__c = 'EMEA';
		insert camp;

		Campaign camp1 = (Campaign) SmartFactory.createSObject('Campaign');
		camp1.Name = 'test';
		camp1.IsActive = false;
		camp1.CurrencyIsoCode = 'USD';
		camp1.Type = 'Email';
        camp1.Program_Type__c = 'Funnel Development/Velocity';
        camp1.Segment_Focus__c = 'Global';
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
		System.assertEquals(con.Active_Campaign_Count__c, 0);
		
		test.startTest();
		Batchable_Contact_ActiveCampaignCount bca = new Batchable_Contact_ActiveCampaignCount('select id from Contact');
		//bca.query = bca.query + 'Limit 200';
		Id bcaId = Database.executeBatch(bca,200);
		test.stopTest();
	}
}