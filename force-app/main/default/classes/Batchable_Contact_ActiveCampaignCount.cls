/**
@description Batch to count ACC on contact
@author venkat.sriram@intapp.com
@instructions To run this, go to Execute Anonymous and type - 
String query = 'SELECT Id from Contact';
Batchable_Contact_ActiveCampaignCount batch = new Batchable_Contact_ActiveCampaignCount(query, 200);
Database.executeBatch(batch);
*/

global class Batchable_Contact_ActiveCampaignCount implements Database.Batchable<SObject> {
	
	global String query;
	global List<Contact> list_moreThanFiveACC;
	
	global Batchable_Contact_ActiveCampaignCount(String query) {
		this.query = query;	
		list_moreThanFiveACC = new List<Contact>();
	}
	
	/**
	 * @description gets invoked when the batch job starts
	 * @param context contains the job ID
	 * @returns the record set as a QueryLocator object that will be batched for execution
	 */ 
	global Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocator(query);
	}

	/**
	 * @description gets invoked when the batch job executes and operates on one batch of records. Contains or calls the main execution logic for the batch job.
	 * @param context contains the job ID
	 * @param scope contains the batch of records to process.
	 */ 
   	global void execute(Database.BatchableContext context, List<Contact> scope) {
		List<Contact> List_ContactsToUpdate = new List<Contact>();
		for(Contact c: [Select Id, Name, Active_Campaign_Count__c,
								   (Select Id, Campaign.isActive, Campaign.Type
									  FROM CampaignMembers)
						  FROM Contact 
						 WHERE Id in : scope]){
				
				c.Active_Campaign_Count__c = 0;
				
				for(CampaignMember cm : c.CampaignMembers){
					if(cm.Campaign.isActive && cm.Campaign.Type != 'Inbound' && cm.Campaign.Type != 'Intapp Advisory Board Member Meeting' 
                       && cm.Campaign.Type != 'Customer Care' && cm.Campaign.Type != 'Public Relations'){
						c.Active_Campaign_Count__c += 1;		
					}
				}

				if(c.Active_Campaign_Count__c > 5){
					list_moreThanFiveACC.add(c);
				}
				
				List_ContactsToUpdate.add(c);				
		}
		
		Database.SaveResult[] SRList = new List<Database.SaveResult>();

		if(List_ContactsToUpdate.size() > 0){
			SRList = Database.update(List_ContactsToUpdate, false); //update listname
		}

		List<Integration_Error__c> ErrorsList = new List<Integration_Error__c>();

		for(Integer i=0;i<SRList.size();i++){
			if(!SRList[i].isSuccess()){
				for(Database.Error err : SRList[i].getErrors()) {
					Integration_Error__c er = new Integration_Error__c();
					er.Name = 'ACC Update Failed for ' + List_ContactsToUpdate[i].Id;
					er.Details__c = 'Error updating ACC for Contact'+ List_ContactsToUpdate[i] + ' : '  + err.getStatusCode() + ' ' + err.getMessage()+ ' ' + err.getFields();
					ErrorsList.add(er);	
				}
			}
		}

		if(ErrorsList.size() > 0) insert ErrorsList;

	}
	
	/**
	 * @description gets invoked when the batch job finishes. Place any clean up code in this method.
	 * @param context contains the job ID
	 */ 
	global void finish(Database.BatchableContext context) {
		//list_moreThanFiveACC
		//if(list_moreThanFiveACC.size() > 0){
			//List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
			//Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
			//mail.setReplyTo('anisha.dhekne@intapp.com');
			////mail.setToAddresses(new String[] { 'anisha.dhekne@intapp.com', 'venkat.sriram@intapp.com' });
			//mail.setSenderDisplayName('Salesforce Reporting');
			//mail.setSubject('Active Campaign Count Reached Limit for following Contacts');
			//String textBody = '';
			//for(Contact c: list_moreThanFiveACC){
				//textBody +=  'Active Campaign Count for-' + c.Name + ' (' + c.Id +') is: ' + c.Active_Campaign_Count__c + '<br/>';
			//}
			//mail.setHtmlBody(textBody);
			//mails.add(mail);
			//Messaging.sendEmail(mails);
		//}
	}
}