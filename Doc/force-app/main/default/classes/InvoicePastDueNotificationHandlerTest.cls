@isTest(seeAllData=true)
private class InvoicePastDueNotificationHandlerTest {
    
    @isTest static void TestInvoicePastDueHandler() {
        User u = TestUtil.createUser(true);
        Account a = TestUtil.CreateAccount(false);
        a.CRD__c = u.Id;
        insert a;

        List<Invoice__c> invoices = new List<Invoice__c>();
        
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice1', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-30)));
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice2', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-60)));
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice3', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-90)));
        invoices.add(new Invoice__c(Amount_Invoiced__c= 1200, Account__c = a.Id, Name = 'Invoice5', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-113)));
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice4', Outstanding_Balance__c = 1100.00, Date_Paid__c = date.today().addDays(-1), 
                    Due_Date__c = date.today().addDays(-95)));
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice5', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-30),Sales_Order_Type__c = 'Services Agreement'));
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice6', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-60),Sales_Order_Type__c = 'Services Agreement'));
        
        //updates
        invoices.add(new Invoice__c(Amount_Invoiced__c = 10, Account__c = a.Id, Name = 'Invoice1A',Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-60), 
                                   Date_Paid__c = Date.today().addDays(-1), Is_Deleted_in_NS__c = False));
        
        insert invoices;
        
        List<NS_Payment__c> payments = new List<NS_Payment__c>();
        
        for(Invoice__c invoice: invoices ){
            payments.add(new NS_Payment__c(Amount__c = 10, Invoice__c = invoice.id, Transaction_Date__c = Date.today().addDays(-1), Type__c = 'Payment'));
        }
        
        
        insert payments;
        
        invoices = new List<invoice__c>();
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice2A', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-30),Sales_Order_Type__c = 'Services Agreement'));
        invoices.add(new Invoice__c(Amount_Invoiced__c = 1200, Account__c = a.Id, Name = 'Invoice2B', Outstanding_Balance__c = 1100.00, Due_Date__c = date.today().addDays(-60),Sales_Order_Type__c = 'Services Agreement'));
        invoices.add(new Invoice__c(CurrencyISOCode = 'USD', Amount_Invoiced__c = 5000, Account__c = a.Id, Name = 'Invoice2C', Due_Date__c = date.today().addDays(-90),
                                    Sales_Order_Type__c = 'Renewal'));
        invoices.add(new Invoice__c(CurrencyISOCode = 'USD', Amount_Invoiced__c = 5000, Account__c = a.Id, Name = 'Invoice2C', Due_Date__c = date.today().addDays(-113),
                                    Sales_Order_Type__c = 'Renewal'));
        
        insert invoices;
        
        InvoicePastDueNotificationHandler handler = new InvoicePastDueNotificationHandler();
        handler.SendNotifications();
    }

   /*
    @isTest static void TestInvoicePastDueWebService() {
        InvoicePastDueNotificationWebService.Send30DayNotifications(1000);
        InvoicePastDueNotificationWebService.Send60DayNotifications(1000);
        InvoicePastDueNotificationWebService.Send90DayNotifications(1000);
    }
    */
}