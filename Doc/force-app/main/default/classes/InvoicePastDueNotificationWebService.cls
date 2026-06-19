/********************************************************************************     
 *  Name             :  InvoicePastDueNotificationWebService
 *  Author           :  Intapp
 *  Description      :  Utility class to send out invoice past due notifications. Executed via IB Web Service Action
 *  Change history   :
 *  Date            Author                      Description
 *  06/01/15        Alan Westley                Moved functionality to web service class for IB call 
 ********************************************************************************/
global class InvoicePastDueNotificationWebService {
/*
    webService static String Send30DayNotifications(Integer amount) {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 30 Days'];
        
        Id oweaID = null;
        OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
        if (owea.size() > 0) {
            oweaID = owea.get(0).Id;
        }
        
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Invoice__c> invoices = Database.query('SELECT Id, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c FROM Invoice__c ' +
            'WHERE Status__c = \'Open\' and Outstanding_Balance__c > USD' + amount + ' and Due_Date__c = N_DAYS_AGO:30');
        for(Invoice__c invoice: invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object
            
            if (oweaID != null) {
                mail.setOrgWideEmailAddressId(oweaID);
            } 
            else {
                mail.setSenderDisplayName('Jason Wood');//Sender would be owner of Profile
            }
            mail.setWhatId(invoice.Id);
            mail.setTargetObjectId('0035000001u6umd'); //Send to Jason Wood
            mail.setToAddresses(new String[]{'ar@intapp.com'});

            //if (invoice.Sales_Order_Type__c == 'Renewal') {
            //    mail.setTargetObjectId(invoice.CRD_Email__c);
            //}
            //else {
            //    mail.setTargetObjectId(invoice.Account__r.OwnerId); //target to Account Owner
            //}

            mail.setTemplateId(et.id);         
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }
        
        if (messages.size() > 0) {
            Messaging.sendEmail(messages);  //send emails
            return messages.size() + ' emails sent for 30 day';
        }
        else {
            return 'No emails sent for 30 day';
        }
    }

    webService static String  Send60DayNotifications(Integer amount) {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 60 Days'];

        Id oweaID = null;
        OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
        if (owea.size() > 0) {
            oweaID = owea.get(0).Id;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Invoice__c> invoices = Database.query('SELECT Id, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c FROM Invoice__c ' +
            'WHERE Status__c = \'Open\' and Outstanding_Balance__c > USD' + amount + ' and Due_Date__c = N_DAYS_AGO:60');
        for(Invoice__c invoice: invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object
             
            if (oweaID != null) {
                mail.setOrgWideEmailAddressId(oweaID);
            } 
            else {
                mail.setSenderDisplayName('Jason Wood');//Sender would be owner of Profile
            }
            
            mail.setWhatId(invoice.Id);
            mail.setTargetObjectId('0035000001u6umd'); //Send to Jason Wood
            mail.setToAddresses(new String[]{'ar@intapp.com'});

            if (invoice.Sales_Order_Type__c == 'Renewal') {
                mail.setCcAddresses(new String[]{'eldean.ward@intapp.com',invoice.CRD_Email__c});
            }
            //else {
            //    mail.setTargetObjectId(invoice.Account__r.OwnerId); //target to receipient
            //    mail.setToAddresses(new String[]{'dan.tacone@intapp.com'});
            //    //Add RVP
            //}

            mail.setTemplateId(et.id);           // pull the email template through id
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }
        
        if (messages.size() > 0) {
            Messaging.sendEmail(messages);  //send emails
            return messages.size() + ' emails sent for 60 day';
        }
        else {
            return 'No emails sent for 60 day';
        }
    }

    webService static String Send90DayNotifications(Integer amount) {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 90 Days'];
        
        Id oweaID = null;
        OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
        if (owea.size() > 0) {
            oweaID = owea.get(0).Id;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Invoice__c> invoices = Database.query('SELECT Id, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c FROM Invoice__c ' + 
            'WHERE Status__c = \'Open\' and Outstanding_Balance__c > USD' + amount + ' and Due_Date__c = N_DAYS_AGO:90');
        for(Invoice__c invoice: invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object
             
            if (oweaID != null) {
                mail.setOrgWideEmailAddressId(oweaID);
            } 
            else {            
                mail.setSenderDisplayName('Jason Wood');//Sender would be owner of Profile
            }
            
            mail.setWhatId(invoice.Id);
            mail.setTargetObjectId('0035000001u6umd'); //Send to Jason Wood
            mail.setToAddresses(new String[]{'ar@intapp.com'});
       
            if (invoice.Sales_Order_Type__c == 'Renewal') {
                mail.setCcAddresses(new String[]{'eldean.ward@intapp.com',invoice.CRD_Email__c});
            }
            //else {
            //    mail.setTargetObjectId(invoice.Account__r.OwnerId); //target to receipient
            //    mail.setToAddresses(new String[]{'dan.tacone@intapp.com','cteam@integrationappliance.com'});
            //    //Add RVP
            //}

            mail.setTemplateId(et.id);           // pull the email template through id
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }
        
        if (messages.size() > 0) {
            Messaging.sendEmail(messages);  //send emails
            return messages.size() + ' emails sent for 90 day';
        }
        else {
            return 'No emails sent for 90 day';
        }
    }  
    */
}