@isTest 
private class TestSnapshotHistoricalPaymentData {
    
    @isTest
    private static void createSnapsnotInBatch() {
        Account a = (Account) SmartFactory.createSObject('Account');
        insert a;
        
        system.assertNotEquals(a, null, 'Account Present');
        
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = a.Id;
        insert c;
        
        Invoice__c i = (Invoice__c) SmartFactory.createSObject('Invoice__c');
        i.Account__c = a.Id;
        i.Related_OSA__c = c.Id;
        i.Amount_Credited__c = 100;
        i.NS_Dollar_Amount_Paid__c = 120;
        insert i;
        
        //Create payment snapshot
        String query = 'SELECT Id, Amount_Credited__c, NS_Dollar_Amount_Paid__c, CurrencyIsoCode FROM Invoice__c';
        SnapshotHistoricalPaymentData batch = new SnapshotHistoricalPaymentData(query, false, false, new Set<Id>(), false);
        Database.executeBatch(batch, 200);
    }
    
    @isTest
    private static void createSnapsnotInBatchUpdate() {
        Account a = (Account) SmartFactory.createSObject('Account');
        insert a;
        
        system.assertNotEquals(a, null, 'Account Present');
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = a.Id;
        insert c;
        
        Invoice__c i = (Invoice__c) SmartFactory.createSObject('Invoice__c');
        i.Account__c = a.Id;
        i.Related_OSA__c = c.Id;
        i.Amount_Credited__c = 100;
        i.NS_Dollar_Amount_Paid__c = 120;
        i.Date_Paid__c = date.today();
        insert i;
        
        NS_Payment__c j = (NS_Payment__c) SmartFactory.createSObject('NS_Payment__c');
        j.Invoice__c = i.Id;
        j.Name = 'Test';
        j.Transaction_Date__c = null;
        j.CurrencyIsoCode = 'USD';
        insert j;
        
        j.Name = 'Test2';
        update j;
        
        Test.startTest();
        //Create payment snapshot
        String query = 'SELECT Id, Amount_Credited__c, NS_Dollar_Amount_Paid__c, Date_Paid__c,CurrencyIsoCode,(Select Id,Transaction_Date__c,Invoice__c from NS_Payments__r ) FROM Invoice__c';
        SnapshotHistoricalPaymentData batch = new SnapshotHistoricalPaymentData(query, true, false, new Set<Id>(), false);
        Database.executeBatch(batch, 200);
        Test.stopTest();
        List<NS_Payment__c> paymentsToUpdate = [SELECT Id,Transaction_Date__c FROM NS_Payment__c WHERE Id =:j.Id];
        System.assertEquals(i.Date_Paid__c, paymentsToUpdate[0].Transaction_Date__c);
    } 
    
    @isTest
    private static void createSnapsnotInBatchDelete() {
        Account a = (Account) SmartFactory.createSObject('Account');
        insert a;
        
        system.assertNotEquals(a, null, 'Account Present');
        
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = a.Id;
        insert c;
        
        Invoice__c i = (Invoice__c) SmartFactory.createSObject('Invoice__c');
        i.Account__c = a.Id;
        i.Related_OSA__c = c.Id;
        i.Amount_Credited__c = 100;
        i.NS_Dollar_Amount_Paid__c = 120;
        i.Date_Paid__c = date.today();
        insert i;
        
        NS_Payment__c k = (NS_Payment__c) SmartFactory.createSObject('NS_Payment__c');
        k.Invoice__c = i.Id;
        k.Name = 'Test';
        k.Transaction_Date__c = null;
        insert k;
        
        delete k;
        
        //Create payment snapshot
        String query = 'SELECT Id, Amount_Credited__c, NS_Dollar_Amount_Paid__c, CurrencyIsoCode FROM Invoice__c';
        SnapshotHistoricalPaymentData batch = new SnapshotHistoricalPaymentData(query, false, false, new Set<Id>(), false);
        Database.executeBatch(batch, 200);
    }
    
    @isTest
    private static void insertNsPayment() {
        Account a = (Account) SmartFactory.createSObject('Account');
        insert a;
        
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = a.Id;
        insert c;
        
        Invoice__c i = (Invoice__c) SmartFactory.createSObject('Invoice__c');
        i.Account__c = a.Id;
        i.Related_OSA__c = c.Id;
        i.Amount_Credited__c = 100;
        i.NS_Dollar_Amount_Paid__c = 120;
        i.Date_Paid__c = date.today();
        insert i;
        
        NS_Payment__c d = (NS_Payment__c) SmartFactory.createSObject('NS_Payment__c');
        d.Invoice__c = i.Id;
        d.Name = 'Test';
        d.Transaction_Date__c = null;
        insert d;
        
        Test.startTest();
        //Create payment snapshot
        String query = 'SELECT Id, Amount_Credited__c, NS_Dollar_Amount_Paid__c, Date_Paid__c,CurrencyIsoCode,(Select Id,Transaction_Date__c,Invoice__c from NS_Payments__r ) FROM Invoice__c';
        SnapshotHistoricalPaymentData batch = new SnapshotHistoricalPaymentData(query, true, false, new Set<Id>(), false);
        Database.executeBatch(batch, 200);
        Test.stopTest();
        List<NS_Payment__c> paymentsToUpdate = [SELECT Id,Transaction_Date__c FROM NS_Payment__c WHERE Id =:d.Id];
        System.assertEquals(i.Date_Paid__c, paymentsToUpdate[0].Transaction_Date__c);
    }
}