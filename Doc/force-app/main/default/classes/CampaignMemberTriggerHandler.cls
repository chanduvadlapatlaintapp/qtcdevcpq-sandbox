public class CampaignMemberTriggerHandler{
    public static void run(List<CampaignMember> CampaignList){
    
    // Create Set to hold campaign_member ids
    
    Set<ID> s = new Set<ID>();
    for(CampaignMember mem: CampaignList)
    {
        s.Add(mem.ID);
    }
    
   //Create Map to get all intapp contacts so that we can assign task to Sales Rep
    Map<String,Id> name = new Map<String,Id>();
    List <user> users = [SELECT Name, ID, email FROM user where email like '%intapp.com%'];
    for (user u:users){
    name.put(u.Name,u.Id);
    }
    

    
    //Create map to get all campaign members which are available in campaign member set
   Map<ID, CampaignMember> m = new Map<ID,CampaignMember>([SELECT ContactId,campaign.id, email, Name,Campaign.Name,campaign.ParentId,CompanyOrAccount,Contact.Account.License_Band__c,Contact.Account.Sales_Development_Representative__c, Contact.Account.Sales_Development_Representative__r.email FROM CampaignMember WHERE Id IN :s and (campaign.ParentId ='70150000001AgF0AAK'or campaign.ParentId ='70150000001AgB7AAK')]);
        List<String> toAddresses = new List<String>();
        List <Task> createTask = new List <Task>();
        for(CampaignMember c: m.values()){
               Task newTask = new Task(); 
               newTask.subject = '  Follow Up:   ' + c.CompanyOrAccount  + '(' + c.Contact.Account.License_Band__c + ' ' + 'Lawyers'+ ')' + '   accessed   ' + c.Campaign.Name;
               newTask.WhoId = c.ContactId;
               newTask.status = 'Not Started';
               newTask.Priority = 'Low';
               newTask.Campaign_Follow_Up__c = 'Target';
               newTask.Purpose__c = 'Marketing';
               newTask.Purpose_Detail__c = '1.9 Other Marketing';
               newTask.OwnerId = c.Contact.Account.Sales_Development_Representative__c;
               newTask.ActivityDate = DateTime.now().date().addDays(5);
               if(c.campaign.ParentId != null){
                   newTask.WhatId = c.campaign.id ;
                   }
                   else
                   {
                   newTask.WhatId = c.campaign.ParentId;
                   }
                    
                   if (newTask.OwnerId == null){
                   newTask.OwnerID = '00550000006Rvo6AAC';  
               }
                string userEmail = 'Marketing_Operations@intapp.com';
                if(c.Contact.Account.Sales_Development_Representative__r.Email != null)				
	                userEmail = c.Contact.Account.Sales_Development_Representative__r.Email;
                //List<User> useremails = [select id, name, email from user where name =:c.Contact.Account.Sales_Development_Representative__c];
                //if (useremails.size() > 0) {
                //userEmail = useremails[0].email;
                //
               //else
               //
                 //userEmail = 'Marketing_Operations@intapp.com';
                //
               
               
               toAddresses.add (userEmail);
               createTask.add(newTask);   
                
        }
             //try {
                  insert createTask;
                 
                 // Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                  //mail.setToAddresses(toAddresses);
                 // mail.setSubject('Follow up on campaign task');
                //  String textBody = 'Follow Up Task' ;
                //  mail.setPlainTextBody(textBody);
               //   Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail}); 
                 // } 
              //}catch (Exception e) {DebugLogger.insertEntry('tt',userEmail.email);}  
              //
              //                     
    }
}

               //+ '      ' + URL.getSalesforceBaseUrl().toExternalForm() + '/' + t.Id
               // Map<Id,String> name = new Map<Id,String>();
                  //for (Task t:createTask){