/********************************************************************************     
 *  Name             :  IdeaTriggerHandler
 *  Author           :  Anisha, Venkat
 *  Description      :  Handler class to control creation of new Idea by Customers.
 *
 *  Change history   :
 *  Date            Author                      Description
 *  02/14/2018      Anisha Dhekne               Moved New Idea Trigger functionality from NewIdeaCretion trigger
 *												to a separate class for better unit testing and used Apex Best Practices-
 *												bulkified the code.
 *  
 ********************************************************************************/
public class IdeaTriggerHandler{

	public void afterInsert(List<Idea> newRecords){
		NotifyNewIdea(newRecords);
	}

	private void NotifyNewIdea(List<Idea> newRecords){
		Map<Id, Idea> map_ideaId_idea = new Map<Id, Idea>();
		Map<Id, IdeaWrapper> map_ideaId_ideaWrapper = new Map<Id, IdeaWrapper>();
		Map<String, List<Id>> map_CategoryNames_listIdeaId = new Map<String, List<Id>>();
		
		for(Idea userIdea: [SELECT Id, Title, Body,
								   Idea.Categories, 
								   CreatedBy.Name, CreatedBy.Email, CreatedBy.Title, 
								   CreatedBy.Contact.Title, CreatedBy.Contact.AccountId,
								   CreatedBy.Contact.Account.Name
							  FROM Idea
							 WHERE Id in : newRecords]){
			
			IdeaWrapper iWrapper = new IdeaWrapper(userIdea.createdBy.Name, 
												   userIdea.createdBy.Title,
												   userIdea.createdBy.Email,
												   userIdea.createdBy.Contact.Title,
												   userIdea.createdBy.Contact.Account.Name,
												   userIdea.Categories);
			map_ideaId_ideaWrapper.put(userIdea.Id, iWrapper);
			map_ideaId_idea.put(userIdea.Id, userIdea);

			System.debug(userIdea.Categories);
			if(!map_CategoryNames_listIdeaId.containsKey(userIdea.Categories)){
				map_CategoryNames_listIdeaId.put(userIdea.Categories, new List<Id>{UserIdea.Id});
			}
			else{
				map_CategoryNames_listIdeaId.get(userIdea.Categories).add(userIdea.Id);
			}
		}

		List<Messaging.SingleEmailMessage> Mails = new List<Messaging.SingleEmailMessage>();
		
		// Maps group names to Category names and iterates over them.
		Map<String, String> map_grpNames_CategoryNames = new Map<String, String>();
		map_grpNames_CategoryNames.put('KCS_Flow', 'Intapp Flow');
		map_grpNames_CategoryNames.put('KCS Time', 'Intapp Time');
		map_grpNames_CategoryNames.put('KCS_Time_Cloud', 'Intapp Time Cloud');
		map_grpNames_CategoryNames.put('KCS Integration', 'Integration');		
		map_grpNames_CategoryNames.put('KCS Open Conflicts', 'Intapp Open Conflicts');
		map_grpNames_CategoryNames.put('KCS Open Intake', 'Intapp Open Intake');
		map_grpNames_CategoryNames.put('KCS Walls', 'Intapp Walls');
		

		// Maps user IDs to Category names and iterates over them.
		Map<Id, String> map_userId_CategoryNames = new Map<Id, String>();
	
		for(GroupMember grpMember: [SELECT userOrGroupId, Group.Name 
									  FROM GroupMember 
									 WHERE Group.Name in: map_grpNames_CategoryNames.keySet()]){
			
			if(map_CategoryNames_listIdeaId.containsKey(map_grpNames_CategoryNames.get(grpMember.Group.Name))){
				map_userId_CategoryNames.put(grpMember.userOrGroupId, map_grpNames_CategoryNames.get(grpMember.Group.Name));
			}
		}
		// Maps idea IDs to email List and iterates over them.
		Map<Id, List<String>> map_ideaId_emailList = new Map<Id, List<String>>();

		for(User usr: [SELECT Id, userEmailCustom__c
						 FROM User
						WHERE Id in : map_userId_CategoryNames.keySet()]){
			
			String CategoryName = map_userId_CategoryNames.get(usr.Id);

			for(Id ideaId: map_CategoryNames_listIdeaId.get(CategoryName)){
				if(!map_ideaId_emailList.containsKey(ideaId)){
					map_ideaId_emailList.put(ideaId, new List<String>{usr.userEmailCustom__c});
				}
				else{
					map_ideaId_emailList.get(ideaId).add(usr.userEmailCustom__c);
				}
			}
		}

		System.debug('map idea list email = ' + map_ideaId_emailList);
		System.debug('map idea = ' + map_ideaId_idea);
		for(Id ideaId: map_ideaId_idea.keyset()){
			Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
			 
			String ideaURL = 'https://na3.salesforce.com/ideas/viewIdea.apexp?id=' + ideaId;
			String portalURL = 'https://intapp.secure.force.com/portal/ideas/viewIdea.apexp?id=' + ideaId;
			
			IdeaWrapper iWrapper = map_ideaId_ideaWrapper.get(ideaId);
			Idea idea = new Idea();

			idea = map_ideaId_idea.get(ideaId);
			
			mail.setSubject('New Idea Created for ' + iWrapper.CategoryName);
			mail.setHtmlBody('The following Idea has been created for ' + iWrapper.CategoryName + ': <br/><br/>'
                        +'Title: <b> ' + idea.Title +' </b><br/>'
                        +'Description: ' + idea.Body + '<br/>'
                        +'Created by: ' + iWrapper.userName + '<br/>'              
                        +'Title: ' + iWrapper.userTitle + '<br/>'
                        +'Account: ' + iWrapper.contactAccountName + '<br/><br/>'
                        +'To view the new idea in Salesforce <a href='+ideaURL +'>click here.</a><br/>'
                        +'To view the new idea in the Customer Portal <a href='+portalURL +'>click here.</a>');

			mail.setToAddresses(map_ideaId_emailList.get(ideaId));
			mail.setSenderDisplayName('Salesforce Ideas');
			Mails.add(mail);
		}

		System.debug(Mails);
		System.debug(map_ideaId_emailList);
		Messaging.sendEmail(Mails);
		
		
	}
	//Wrapper class for assigning fields for the Idea table
	public class IdeaWrapper{
		public String userName;
		public String userTitle;
		public String userEmail;
		public String contactTitle;
		public String contactAccountName;
		public String CategoryName;

		public IdeaWrapper(String userName, String userTitle, String userEmail,
						   String contactTitle, String contactAccountName,
						   String CategoryName){
				this.userName = userName;
				this.userTitle = userTitle;
				this.userEmail = userEmail;
				this.contactTitle = contactTitle;
				this.contactAccountName = contactAccountName != null? contactAccountName : 'IntApp, Inc.';
				this.CategoryName = CategoryName;
		}
	}
}