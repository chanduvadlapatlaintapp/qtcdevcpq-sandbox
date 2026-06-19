/*********************************************************************
    Add/Edit these constants to contain your email template names

    PLEASE NOTE THAT THESE MUST BE VISUALFORCE TEMPLATES TO WORK!   

    Also, the VF template must NOT have recipientType set 
    in the <messaging:emailTemplate> tag or you will get the error: 

    INVALID_ID_FIELD, WhatId is not available for sending emails to UserIds
***********************************************************************/
global class ContractApprovalReminderEmails implements Database.Batchable<sObject>,Database.Stateful, Schedulable {

    public static string ContractEmailTemplate = 'Contract_Pending_Approval_Notification';
    //static final Pending_Approval_Notification_Email__c CS = Pending_Approval_Notification_Email__c.getOrgDefaults();
    Id userId = UserInfo.getUserId();
    
    static OrgWideEmailAddress owa = [Select id, DisplayName, Address from OrgWideEmailAddress Where DisplayName = 'Contracts Operations' limit 1];
    
    //------------------------------------------------------------------------------------------------------
    // this method is used to get all reocrds that will be processed by execute method
    //------------------------------------------------------------------------------------------------------
    global Database.QueryLocator start(Database.BatchableContext bc) {
        String query;
        if (test.IsRunningTest() == true) {
            query = 'Select Id from User Where id=:userId';  
        } else {
            Set<Id> actorIds = new Set<Id>();
            for(ProcessInstanceWorkitem pi : [Select p.Actor.Email, p.Actor.Name, p.ActorId, p.OriginalActorId, p.Id
                                                From ProcessInstanceWorkitem p
                                                WHERE ProcessInstance.Status = 'Pending' AND ProcessInstance.IsDeleted = False
                                                AND ProcessInstance.SystemModStamp <= Today AND ProcessInstance.TargetObject.type='Contract']){
                actorIds.add(pi.ActorId);
            }
            query = 'Select Id from User where Id in :actorIds';
        }
        return  Database.getQueryLocator(query);
    } // querylocator start

    //------------------------------------------------------------------------------------------------------
    // find and process all pending approval requests that aren't deleted 
    // and are older than today
    //------------------------------------------------------------------------------------------------------
    global void execute(Database.BatchableContext BC, List<sObject> scope) {
        Set<Id> actorIds = new Set<Id> ();
        for (Sobject s : scope) {
            actorIds.add((Id)s.get('Id'));
        }
        
        String query    = 'Select p.ProcessInstance.Status, p.ProcessInstance.TargetObject.Name, p.ProcessInstance.TargetObjectId, p.ProcessInstance.TargetObject.Type, p.ProcessInstance.Id, p.ProcessInstanceId,p.Actor.Email, p.Actor.Name, p.ActorId, p.OriginalActorId, p.Id ' 
                                    + ' From ProcessInstanceWorkitem p'
                                    + ' WHERE ProcessInstance.Status = \'Pending\' AND ProcessInstance.IsDeleted = False    '
                                    + ' AND ProcessInstance.SystemModStamp <= Today AND ProcessInstance.TargetObject.type=\'Contract\''
                                    + ' And actor.Id in :actorIds'
                                    + ' Order by p.Actor.Email';
        
        if (test.isRunningTest())   {
            query   = 'Select p.ProcessInstance.Status, p.ProcessInstance.TargetObject.Name, p.ProcessInstance.TargetObjectId, p.ProcessInstance.TargetObject.Type, p.ProcessInstance.Id, p.ProcessInstanceId,p.Actor.Email, p.Actor.Name, p.ActorId, p.OriginalActorId, p.Id ' 
                            + ' From ProcessInstanceWorkitem p';
        }   
        
        List<ProcessInstanceWorkitem> lstWorkItems = Database.query(query);
        Map<String, List<ProcessInstanceWorkitem>> mapEmailWorkItems = new Map<String, List<ProcessInstanceWorkitem>> ();
        // loop thru results    
        for (SObject s : lstWorkItems) {
            ProcessInstanceWorkitem PIWItem = (ProcessInstanceWorkitem)s;
            if (!mapEmailWorkItems.containsKey(PIWItem.Actor.Email)) {
                mapEmailWorkItems.put(PIWItem.Actor.Email, new List<ProcessInstanceWorkitem> ());
            }
            mapEmailWorkItems.get(PIWItem.Actor.Email).add(PIWItem);
        } // loop thru scope which contains the process instance results
        
        if (lstWorkItems.size() > 0) {
            for (String actorEmail : mapEmailWorkItems.keySet()) {
                SendReminderEmail(actorEmail, mapEmailWorkItems.get(actorEmail));
            }
        }
    } // end SendReminders
    
    //------------------------------------------------------------------------------------------------------
    //finish
    //------------------------------------------------------------------------------------------------------
    global void finish(Database.BatchableContext info) {
    
    } // finish
    
    global void execute(SchedulableContext sc) {
        ContractApprovalReminderEmails b = new ContractApprovalReminderEmails(); 
        database.executebatch(b, 10);
    }
    
    //------------------------------------------------------------------------------------------------------
    // Send Remainder email
    //------------------------------------------------------------------------------------------------------
    public static void SendReminderEmail(String actorEmail, List<ProcessInstanceWorkitem> lstPendingApprovals) {        
        Id targetId = lstPendingApprovals.get(0).ProcessInstance.TargetObjectId;
        Id actorId = lstPendingApprovals.get(0).ActorId;
        
        // Make sure this transaction won't fail due to lack of daily capacity
        Messaging.reserveSingleEmailCapacity(1);
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();         
        String[] toAddresses;
        
        String ActorName = lstPendingApprovals.get(0).actor.Name;
        // email will be null during testing ...
        if (test.IsRunningTest() == true) {
            toAddresses = new String[] {'no-reply@salesforce.com'};
            email.setToAddresses(toAddresses);
        } else {
            toAddresses = new String[] {actorEmail};    
        } // prevent Email Exception due to null address during testing
        
        Id EmailTemplateID = FindEmailTemplateIDByDeveloperName(ContractEmailTemplate);
        if (EmailTemplateID != null) {
            // use our template
            email.setTemplateId(EmailTemplateID);
            email.saveAsActivity = false;
            // populate the template w/ object data
            email.setTargetObjectId(ActorID);
            email.setWhatId(TargetID);
        } else {
            // use a generic HTML email when no template is setup / found
            // get the current salesforce instance to build the link with
            string domain = URL.getSalesforceBaseUrl().toExternalForm();
            email.setToAddresses(toAddresses);
            // set the subject on the email
            email.setSubject('Reminder: Items pending your approval');
            
            String emailBody    = 'Dear ' + ActorName + ', <br/>' 
                                                + 'The following Contracts are still pending your approval:<br/>';
            emailBody += '<table> <tr><td>Contract Number</td><td>Contract link </td></tr>';
            for (ProcessInstanceWorkitem piwItem : lstPendingApprovals) {
                String TargetLink = domain + '/' + string.valueof(piwItem.ProcessInstance.TargetObjectId);
                emailBody += '<tr><td>' + piwItem.ProcessInstance.TargetObject.Name + '</td><td>' + '<a href=\'' + TargetLink + '\'>' + TargetLink + '</a>' + + '</td></tr>';   
            }
            emailBody += '<br/>Please DO NOT reply to this email.';                                      
            // set the body of the email
            email.setHTMLBody(emailBody);
        }
        /*
        if(CS.Email_for_CC__c != null && CS.Email_for_CC__c.trim() != ''){
            email.setCcAddresses(new List<String>{CS.Email_for_CC__c});
        }*/
        email.setCcAddresses(new List<String> {owa.Address});
        email.setOrgWideEmailAddressId(owa.Id);
        // send our email by creating an array of emails and calling the send email method.
        Messaging.SingleEmailMessage[] EmailsToSend = new Messaging.SingleEmailMessage[] { email };
        Messaging.sendEmail(EmailsToSend);
    }
    
    //------------------------------------------------------------------------------------------------------
    // this method could be moved to a utility class and made public . . . . 
    //------------------------------------------------------------------------------------------------------
    public static ID FindEmailTemplateIDByDeveloperName(string DeveloperName) {
        id EmailTemplateID;
        List<EmailTemplate> EmailTemplateResults = new List<EmailTemplate>(); 
        if (DeveloperName != null) {
            EmailTemplateResults = [SELECT Id, Name, DeveloperName, IsActive FROM EmailTemplate WHERE DeveloperName = :DeveloperName];
            if (EmailTemplateResults.size() > 0) {
                if (EmailTemplateResults[0].IsActive == true) {
                    EmailTemplateID = EmailTemplateResults[0].id;
                } // check for active email template
            } // check for null search results  
        } // check for blank name
        return EmailTemplateID;
    } // FindEmailTemplateIDByDeveloperName
    
} // end class