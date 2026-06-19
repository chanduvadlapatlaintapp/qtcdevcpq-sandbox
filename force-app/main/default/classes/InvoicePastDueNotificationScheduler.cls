/********************************************************************************     
 *  Name             :  InvoicePastDueNotificationScheduler
 *  Author           :  Intapp
 *  Description      :  Schedulable class to send out invoice past due notifications
 *
 *  Change history   :
 *  Date            Author                      Description
 *  04/07/15        Alan Westley                Separated out InvoicePastNotificationHandler class for better unit testing 
 ********************************************************************************/
global class InvoicePastDueNotificationScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        InvoicePastDueNotificationHandler handler = new InvoicePastDueNotificationHandler();
        handler.SendNotifications();
    }

    //public void SendTestNotification()
    //{
    //    EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 30 Days'];
    //    List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
    //    Invoice__c invoice = [SELECT Id, Name, Account_Name__c, Related_OSA__r.ContractNumber, OSA_Name__c, Status__c, Due_Date__c 
    //        FROM Invoice__c WHERE Id = 'a1750000001oEIRAA2'];

    //    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object
         
    //    mail.setSenderDisplayName('Jason Wood');    //Sender would be owner of Profile
    //    mail.setTargetObjectIds('0035000000ej4Cf');         //target to receipient
    //    mail.setWhatId(invoice.Id);
    //    mail.setTemplateId(et.id);                  // pull the email template through id
    //    messages.add(mail);
        
    //    Messaging.sendEmail(messages);  //send emails
    //}

    //public void Send30DayNotificationsTEST() {
    //    EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice 30 Days Past Due'];
    //    List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
    //    List<Invoice__c> invoices = [SELECT Id, Name, Account__r.Name, Account__r.OwnerId, Account__r.CRD__c, Sales_Order_Type__c, 
    //        Related_OSA__r.ContractNumber, OSA_Name__c, Status__c, Due_Date__c 
    //        FROM Invoice__c WHERE Status__c = 'Open' and Due_Date__c = N_DAYS_AGO:30];
    //    for(Invoice__c invoice: invoices)
    //    {
    //        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object
    //        List<Id> recipients = new List<Id> ();
    //        if (invoice.Sales_Order_Type__c == 'Renewal') {
    //            recipients.add(invoice.Account__r.CRD__c);
    //        }
    //        else {
    //            recipients.add(invoice.Account__r.OwnerId);
    //        }
    //        mail.setTargetObjectIds(recipients); 
    //        mail.setWhatIds(invoice.Id);
    //        mail.setTemplateId(et.Id);
    //        mail.setSaveAsActivity(false);
    //        mail.setSenderDisplayName('Jason Wood');//Sender would be owner of Profile

    //        messages.add(mail);
    //    }
        
    //    Messaging.sendEmail(messages);  //send emails
    //}

}