/********************************************************************************     
 *  Name             :  InvoicePastDueNotificationHandler
 *  Author           :  Intapp
 *  Description      :  Utility class to send out invoice past due notifications. Executed via Scheduled Apex (InvoicePastDueNotificationScheduler)
 *
 *  Change history   :
 *  Date            Author                      Description
 *  04/07/15        Alan Westley                Moved notification functionality to separate class for better unit testing 
 *  08/26/15        Alan Westley                Added Send90DayInvoicePaidNotification method for Process Builder
 *  10/24/16        Scott Schwarz               Added Send113DayInvoiceNotification method
 *  02/21/17        Mitali Machra               Added "Renewal-Exception" Salesorder type notification
 *  03/31/17        Scott Schwarz               Added Send90DayNotificationsToGeoLeads method
 *                                              Changed Send90DayPaidNotifications to Send60DayPaidNotifications
 *                                              Removed send to CRD email in GeoLeads methods
 *  04/20/018       Anisha Dhekne               Replaced the picklist Status__c with the formula field Invoice_Status__c 
 *                                              Replaced the Outstanding_Balance__c to Outstanding_Bln__c   
 *  05/13/2020      Venkat Sriram               Include Account Owner and Owner's Manager in notification for 30,60,90,113 notifications
 *  05/13/2020      Venkat Sriram               Removed Ryan Dillon from Notification
    
*******************************************************************************************************************************/
public with sharing class InvoicePastDueNotificationHandler {
    //private boolean testing = true;

    public void SendNotifications() {
        Send30DayNotifications();
        Send60DayNotifications();
        Send30DayNotificationsToGeoLeads();
        Send60DayNotificationsToGeoLeads();
        Send90DayNotificationsToGeoLeads();
        Send90DayNotifications();
        Send60DayPaidNotifications();
        Send113DayNotifications();
    }

    public void Send60DayPaidNotifications()
    {
        System.Debug('Starting Send60DayInvoicePaidNotification method');

        List<Invoice__c> invoices = [SELECT Id, Name, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c FROM Invoice__c
                                     WHERE Days_Past_Due__c > 60 and Date_Paid__c = YESTERDAY and Invoice_Status__c<> 'Open' and(NOT Sales_Order_Type__c LIKE '%Services%') AND Is_Deleted_in_NS__c = FALSE];

        if (invoices.size() > 0)

        {
            EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = '60+ Past Due Invoice Status Change'];

            Id oweaID = null;
            OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
            if (owea.size() > 0) {
                oweaID = owea.get(0).Id;
            }

            List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();

            System.Debug('InvoicePaidNotification - ' + invoices.size() + ' invoiced found');
            for (Invoice__c invoice : invoices)
            {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object

                if (oweaID != null) {
                    mail.setOrgWideEmailAddressId(oweaID);
                }
                else {
                    mail.setSenderDisplayName('Jason Wood'); //Sender would be owner of Profile
                }

                mail.setWhatId(invoice.Id);
                mail.setTargetObjectId('00350000022flbV'); //Send to Jennifer Richard

                if(invoice.CRD_Email__c != null)
                    mail.setToAddresses(new String[] { invoice.CRD_Email__c });
                
                mail.setCcAddresses(new String[] { 'eldean.ward@intapp.com', 'ar@intapp.com', 'jason.wood@intapp.com', 'jennifer.richard@intapp.com' });

                mail.setTemplateId(et.id); // pull the email template through id
                mail.setSaveAsActivity(false);
                messages.add(mail);
            }

            if (messages.size() > 0 && !test.isRunningTest()) {
                System.debug('InvoicePaidNotification - Sending emails');
                Messaging.sendEmail(messages); //send emails
            }
        }

        System.debug('Ending InvoicePaidNotification');
    }

    //@InvocableMethod
    //public static void Send90DayInvoicePaidNotification(List<ID> invoiceIds)
    //{
    //System.Debug('Starting Send90DayInvoicePaidNotification method');
    //EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = '90+ Past Due Invoice Status Change'];

    //Id oweaID = null;
    //OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
    //if (owea.size() > 0) {
    //oweaID = owea.get(0).Id;
    //}

    //List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
    //List<Invoice__c> invoices = [SELECT Id, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c FROM Invoice__c 
    //WHERE ID in :invoiceIds];

    //System.Debug('InvoicePaidNotification - ' + invoices.size() + ' invoiced found');
    //for(Invoice__c invoice: invoices)
    //{
    //Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object

    //if (oweaID != null) {
    //mail.setOrgWideEmailAddressId(oweaID);
    //} 
    //else {            
    //mail.setSenderDisplayName('Jason Wood');//Sender would be owner of Profile
    //}

    //mail.setWhatId(invoice.Id);
    //mail.setTargetObjectId('0035000001u6umd'); //Send to Jason Wood
    //mail.setToAddresses(new String[]{invoice.CRD_Email__c});
    //mail.setTemplateId(et.id);           // pull the email template through id
    //mail.setSaveAsActivity(false);
    //messages.add(mail);
    //}

    //if (messages.size() > 0) {
    //System.debug('InvoicePaidNotification - Sending emails');
    //Messaging.sendEmail(messages);  //send emails
    //}
    //System.debug('Ending InvoicePaidNotification');
    //}

    public void Send30DayNotifications() {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 30 Days'];

        Id oweaID = null;
        OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
        if (owea.size() > 0) {
            oweaID = owea.get(0).Id;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();
        List<Invoice__c> invoices = [SELECT Id, Account__r.OwnerId, Account__r.Owner.Email, Account__r.Owner.Manager.Email, Sales_Order_Type__c, CRD_Email__c FROM Invoice__c
                                     WHERE Invoice_Status__c = 'Open' and Outstanding_Bln__c > USD5000 and Due_Date__c = N_DAYS_AGO : 30 AND Is_Deleted_in_NS__c = FALSE];

        for (Invoice__c invoice : invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object
            
            if (oweaID != null) {
                mail.setOrgWideEmailAddressId(oweaID);
            }
            else {
                mail.setSenderDisplayName('Jason Wood'); //Sender would be owner of Profile
            }
            mail.setWhatId(invoice.Id);
            mail.setTargetObjectId('00350000022flbV'); //Send to Jennifer Richard
            
            //FD TICKET #55563 - Include account owner and owner's manager in email list  
            List<String> to_addresses = new List<String>();
            to_addresses.add('ar@intapp.com');
            if(invoice.Account__r.Owner.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Email);
            
            if(invoice.Account__r.Owner.Manager.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Manager.Email);
            
            mail.setToAddresses(to_addresses);
            //FD TICKET #55563 - Include account owner and owner's manager in email list  
            
            mail.setCcAddresses(new String[] { 'jason.wood@intapp.com' });

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

        if (messages.size() > 0 && !test.isRunningTest()) {
            Messaging.sendEmail(messages); //send emails
        }
    }

    public void Send60DayNotifications() {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 60 Days'];

        Id oweaID = null;
        OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
        if (owea.size() > 0) {
            oweaID = owea.get(0).Id;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();
        List<Invoice__c> invoices = [SELECT Id, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c,
                                     Account__r.Owner.Email, Account__r.Owner.Manager.Email
                                     FROM Invoice__c
                                     WHERE Invoice_Status__c = 'Open' and Outstanding_Bln__c > USD5000
                                     and Due_Date__c = N_DAYS_AGO : 60
                                     and(NOT Sales_Order_Type__c LIKE '%Services%') AND Is_Deleted_in_NS__c = FALSE];
        for (Invoice__c invoice : invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object

            if (oweaID != null) {
                mail.setOrgWideEmailAddressId(oweaID);
            }
            else {
                mail.setSenderDisplayName('Jason Wood'); //Sender would be owner of Profile
            }

            mail.setWhatId(invoice.Id);
            mail.setTargetObjectId('00350000022flbV'); //Send to Jennifer Richard
            //mail.setToAddresses(new String[]{'ar@intapp.com'});
            //mail.setToAddresses(new String[] { invoice.CRD_Email__c });
            
            //FD TICKET #55563 - Include account owner and owner's manager in email list  
            List<String> to_addresses = new List<String>();
            if(invoice.CRD_Email__c != null)
                to_addresses.add(invoice.CRD_Email__c);
            
            if(invoice.Account__r.Owner.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Email);
            
            if(invoice.Account__r.Owner.Manager.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Manager.Email);
            
            mail.setToAddresses(to_addresses);
            //FD TICKET #55563 - Include account owner and owner's manager in email list  
            
            mail.setCcAddresses(new String[] { 'eldean.ward@intapp.com', 'jason.wood@intapp.com', 'jennifer.richard@intapp.com', 'ar@intapp.com' });
            messages.add(mail);

            //else
            // mail.setCcAddresses(new String[]{'jason.wood@intapp.com'});
            //else {
            //    mail.setTargetObjectId(invoice.Account__r.OwnerId); //target to receipient
            //    mail.setToAddresses(new String[]{'dan.tacone@intapp.com'});
            //    //Add RVP
            //}

            mail.setTemplateId(et.id); // pull the email template through id
            mail.setSaveAsActivity(false);

        }

        if (messages.size() > 0 && !test.isRunningTest()) {
            Messaging.sendEmail(messages); //send emails
        }
    }

    public void Send30DayNotificationsToGeoLeads() {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Service Invoice Past Due 30 Days'];

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();
        List<Invoice__c> invoices = [SELECT Id, Name, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c, account__r.geography__c FROM Invoice__c
                                     WHERE Due_Date__c = N_DAYS_AGO : 30 and Sales_Order_Type__c like '%Services%'
                                     and Invoice_Status__c = 'Open' AND Is_Deleted_in_NS__c = FALSE];

        for (Invoice__c invoice : invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object
            mail.setWhatId(invoice.Id);

            mail.setToAddresses(new String[] { 'ar@intapp.com' });

            if (invoice.account__r.geography__c == 'EMEA' || invoice.account__r.geography__c == 'APAC' || invoice.account__r.geography__c == 'Worldwide') {
                mail.setCcAddresses(new String[] { 'orest.skoropad@intapp.com', 'aleksandr.malyshenko@intapp.com' });
                mail.setTargetObjectId('0035000001jPcuY'); // Send to Kshama Swamy
            }
            else {
                mail.setCcAddresses(new String[] { 'kshama.swamy@intapp.com'});
                mail.setTargetObjectId('0035000001jPcuY'); //Send to Kshama Swamy
            }

            mail.setSenderDisplayName('Jason Wood');
            mail.setTemplateId(et.id); // pull the email template through id
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }

        if (messages.size() > 0 && !test.isRunningTest()) {
            Messaging.sendEmail(messages); //send emails
        }
    }

    public void Send60DayNotificationsToGeoLeads() {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Services Invoice Past Due 60 Days'];

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();
        List<Invoice__c> invoices = [SELECT Id, Name, Account__r.OwnerId, Account__r.CRD__c, Sales_Order_Type__c, CRD_Email__c, account__r.geography__c FROM Invoice__c
                                     WHERE Due_Date__c = N_DAYS_AGO : 60 and Sales_Order_Type__c like '%Services%'
                                     and Invoice_Status__c = 'Open' AND Is_Deleted_in_NS__c = FALSE];

        for (Invoice__c invoice : invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object

            mail.setSenderDisplayName('Jason Wood'); //Sender would be owner of Profile
            mail.setWhatId(invoice.Id);
            mail.setToAddresses(new String[] { 'ar@intapp.com' });
            if (invoice.account__r.geography__c == 'EMEA' || invoice.account__r.geography__c == 'APAC' || invoice.account__r.geography__c == 'Worldwide') {
                mail.setCcAddresses(new String[] { 'orest.skoropad@intapp.com', 'aleksandr.malyshenko@intapp.com' });
                mail.setTargetObjectId('0035000001jPcuY'); // Send to Kshama Swamy
            }
            else {
                mail.setCcAddresses(new String[] { 'kshama.swamy@intapp.com' });
                mail.setTargetObjectId('0035000001jPcuY'); //Send to Kshama Swamy
            }
            mail.setTemplateId(et.id); // pull the email template through id
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }

        if (messages.size() > 0 && !test.isRunningTest()) {
            Messaging.sendEmail(messages); //send emails
        }
    }

    public void Send90DayNotificationsToGeoLeads() {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Services Invoice Past Due 90 Days'];

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();
        List<Invoice__c> invoices = [SELECT Id, Name, Account__r.OwnerId, Account__r.CRD__c, Sales_Order_Type__c, CRD_Email__c, account__r.geography__c FROM Invoice__c
                                     WHERE Due_Date__c = N_DAYS_AGO : 90 and Sales_Order_Type__c like '%Services%'
                                     and Invoice_Status__c = 'Open' AND Is_Deleted_in_NS__c = FALSE];

        for (Invoice__c invoice : invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object

            mail.setSenderDisplayName('Jason Wood'); //Sender would be owner of Profile
            mail.setWhatId(invoice.Id);
            mail.setToAddresses(new String[] { 'ar@intapp.com' });
            if (invoice.account__r.geography__c == 'EMEA' || invoice.account__r.geography__c == 'APAC' || invoice.account__r.geography__c == 'Worldwide') {
                mail.setCcAddresses(new String[] { 'orest.skoropad@intapp.com', 'aleksandr.malyshenko@intapp.com', 'nguyen.dinh@intapp.com' });
                mail.setTargetObjectId('0035000001jPcuY'); // Send to Kshama Swamy
            }
            else {
                mail.setCcAddresses(new String[] { 'kshama.swamy@intapp.com', 'nguyen.dinh@intapp.com' });
                mail.setTargetObjectId('0035000001jPcuY'); //Send to Kshama Swamy
            }
            mail.setTemplateId(et.id); // pull the email template through id
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }

        if (messages.size() > 0 && !test.isRunningTest()) {
            Messaging.sendEmail(messages); //send emails
        }
    }


    public void Send90DayNotifications() {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 90 Days'];

        Id oweaID = null;
        OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
        if (owea.size() > 0) {
            oweaID = owea.get(0).Id;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();
        List<Invoice__c> invoices = [SELECT Id, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c,
                                     Account__r.Owner.Email, Account__r.Owner.Manager.Email
                                     FROM Invoice__c
                                     WHERE Invoice_Status__c = 'Open' and Outstanding_Bln__c > USD1000 and Due_Date__c = N_DAYS_AGO : 90
                                     and(NOT Sales_Order_Type__c LIKE '%Services%') AND Is_Deleted_in_NS__c = FALSE];
        for (Invoice__c invoice : invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object

            if (oweaID != null) {
                mail.setOrgWideEmailAddressId(oweaID);
            }
            else {
                mail.setSenderDisplayName('Jason Wood'); //Sender would be owner of Profile
            }

            mail.setWhatId(invoice.Id);
            mail.setTargetObjectId('00350000022flbV'); //Send to Jennifer Richard
            
            //FD TICKET #55563 - Include account owner and owner's manager in email list  
            List<String> to_addresses = new List<String>();
            if(invoice.CRD_Email__c != null)
                to_addresses.add(invoice.CRD_Email__c);
            
            if(invoice.Account__r.Owner.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Email);
            
            if(invoice.Account__r.Owner.Manager.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Manager.Email);
            
            mail.setToAddresses(to_addresses);
            
            //mail.setToAddresses(new String[] { invoice.CRD_Email__c });
            //mail.setToAddresses(new String[]{'ar@intapp.com'});
            mail.setCcAddresses(new String[] { 'eldean.ward@intapp.com', 'ar@intapp.com', 'jason.wood@intapp.com', 'jennifer.richard@intapp.com', 'nguyen.dinh@intapp.com' });

            //else
            // mail.setCcAddresses(new String[]{'jason.wood@intapp.com'});
            //else {
            //    mail.setTargetObjectId(invoice.Account__r.OwnerId); //target to receipient
            //    mail.setToAddresses(new String[]{'dan.tacone@intapp.com','cteam@integrationappliance.com'});
            //    //Add RVP
            //}

            mail.setTemplateId(et.id); // pull the email template through id
            mail.setSaveAsActivity(false);
            messages.add(mail);
        }

        if (messages.size() > 0 && !test.isRunningTest()) {
            Messaging.sendEmail(messages); //send emails
        }
    }

    public void Send113DayNotifications() {
        EmailTemplate et = [SELECT id FROM EmailTemplate WHERE Name = 'Invoice Past Due 113 Days'];

        Id oweaID = null;
        OrgWideEmailAddress[] owea = [select Id from OrgWideEmailAddress where Address = 'jason.wood@intapp.com'];
        if (owea.size() > 0) {
            oweaID = owea.get(0).Id;
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage> ();
        List<Invoice__c> invoices = [SELECT Id, Account__r.OwnerId, Sales_Order_Type__c, CRD_Email__c,
                                     Account__r.Owner.Email, Account__r.Owner.Manager.Email
                                     FROM Invoice__c
                                     WHERE Invoice_Status__c = 'Open' and Outstanding_Bln__c > USD1000 and Due_Date__c = N_DAYS_AGO : 113 and(NOT Sales_Order_Type__c LIKE '%Services%') AND Is_Deleted_in_NS__c = FALSE];
        for (Invoice__c invoice : invoices)
        {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage(); // new mail object

            if (oweaID != null) {
                mail.setOrgWideEmailAddressId(oweaID);
            }
            else {
                mail.setSenderDisplayName('Jason Wood'); //Sender would be owner of Profile
            }

            mail.setWhatId(invoice.Id);
            mail.setTargetObjectId('00350000022flbV'); //Send to Jennifer Richard
            //mail.setToAddresses(new String[]{'ar@intapp.com'});

            //mail.setToAddresses(new String[] { invoice.CRD_Email__c });
            //FD TICKET #55563 - Include account owner and owner's manager in email list  
            List<String> to_addresses = new List<String>();
            if(invoice.CRD_Email__c != null)
                to_addresses.add(invoice.CRD_Email__c);
            
            if(invoice.Account__r.Owner.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Email);
            
            if(invoice.Account__r.Owner.Manager.Email != null)
                to_addresses.add(invoice.Account__r.Owner.Manager.Email);
            
            mail.setToAddresses(to_addresses);
            //FD TICKET #55563 - Include account owner and owner's manager in email list  
            
            mail.setCcAddresses(new String[] { 'eldean.ward@intapp.com', 'jason.wood@intapp.com', 'jennifer.richard@intapp.com', 'ar@intapp.com', 'nguyen.dinh@intapp.com' });
            messages.add(mail);

            //else
            // mail.setCcAddresses(new String[]{'jason.wood@intapp.com'});
            //else {
            //    mail.setTargetObjectId(invoice.Account__r.OwnerId); //target to receipient
            //    mail.setToAddresses(new String[]{'dan.tacone@intapp.com','cteam@integrationappliance.com'});
            //    //Add RVP
            //}

            mail.setTemplateId(et.id); // pull the email template through id
            mail.setSaveAsActivity(false);

        }

        if (messages.size() > 0 && !test.isRunningTest()) {
            Messaging.sendEmail(messages); //send emails
        }
    }

}