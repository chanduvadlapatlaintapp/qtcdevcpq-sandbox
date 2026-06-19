@isTest
public class ReportToAddressBatchTest {
    
    @isTest
    static void testSameAddressWithBilling() {
        // Create accounts
        List<Account> testAccts = new List<Account>();
        Account testAccount = IntappTestObjectFactory.createaccount(false);
        testAccount.Type = 'Client';
        testAccount.BillingCity = 'Idaho';
        testAccount.ShippingCity = 'Idaho';
        testAccount.BillingCountry = 'United States';
        testAccount.ShippingCountry = 'United States';
        testAccount.BillingStreet = '5012 Coulter Lane';
        testAccount.ShippingStreet = '5012 Coulter Lane';
        testAccount.BillingState = 'Alaska';
        testAccount.ShippingState = 'Alaska';
        testAccount.BillingPostalCode = '23005';
        testAccount.ShippingPostalCode = '23005';
        testAccts.add(testAccount);
        insert testAccts;

        Address__c address = new Address__c();
        address.Address__Street__s = '5012 Coulter Lane';
        address.Address__City__s = 'Idaho';
        address.Address__StateCode__s = 'AK';
        address.Address__CountryCode__s = 'US';
        address.Address__PostalCode__s = '23005';
        address.Type__c = 'Billing';
        address.Account__c = testAccount.Id;
        insert address;
        
        Test.startTest();
        ReportToAddressBatch reportToAddressBatchObj = new ReportToAddressBatch();
        Database.executeBatch(reportToAddressBatchObj, 10);
        Test.stopTest();
        System.assertEquals(1, testAccts.size());
    }
    
    @isTest
    static void testSameAddressWithShipping() {
        // Create accounts
        List<Account> testAccts = new List<Account>();
        Account testAccount = IntappTestObjectFactory.createaccount(false);
        testAccount.Type = 'Client';
        testAccount.BillingCity = 'Arlington';
        testAccount.ShippingCity = 'Arlington';
        testAccount.BillingCountry = 'United States';
        testAccount.ShippingCountry = 'United States';
        testAccount.BillingStreet = '4148 Coulter Lane';
        testAccount.ShippingStreet = '4148 Coulter Lane';
        testAccount.BillingState = 'Alaska';
        testAccount.ShippingState = 'Alaska';
        testAccount.BillingPostalCode =  '23005';
        testAccount.ShippingPostalCode = '23005';
        testAccts.add(testAccount);

        insert testAccts;
        
        Address__c address = new Address__c();
        address.Address__Street__s = '4148 Coulter Lane';
        address.Address__City__s = 'Arlington';
        address.Address__StateCode__s = 'ID';
        address.Address__CountryCode__s = 'US';
        address.Address__PostalCode__s = '23005';
        address.Type__c = 'Shipping';
        address.Account__c = testAccount.Id;
        insert address;
        
        Test.startTest();
        ReportToAddressBatch reportToAddressBatchObj = new ReportToAddressBatch();
        Database.executeBatch(reportToAddressBatchObj, 10);
        Test.stopTest();
        System.assertEquals(1, testAccts.size());
    }
    
    @isTest
    static void testDifferentAddress() {
        // Create accounts
        List<Account> testAccts = new List<Account>();
        Account testAccount = IntappTestObjectFactory.createaccount(false);
        testAccount.Type = 'Client';
        testAccount.BillingCity = 'Arlington';
        testAccount.ShippingCity = 'Chicago';
        testAccount.BillingCountry = 'United States';
        testAccount.ShippingCountry = 'United States';
        testAccount.BillingStreet = '4148 Coulter Lane';
        testAccount.ShippingStreet = '4028 Jewell Road';
        testAccount.BillingState = 'Alaska';
        testAccount.ShippingState = 'Idaho';
        testAccount.BillingPostalCode =  '23005';
        testAccount.ShippingPostalCode = '55404';
        testAccts.add(testAccount);

        insert testAccts;

        Address__c address = new Address__c();
        address.Address__Street__s = '4148 Coulter Lane';
        address.Address__City__s = 'Arlington';
        address.Address__StateCode__s = 'AK';
        address.Address__CountryCode__s = 'US';
        address.Address__PostalCode__s = '23005';
        address.Type__c = 'Shipping';
        address.Account__c = testAccount.Id;
        insert address;
        
        Address__c address1 = new Address__c();
        address1.Address__Street__s = '4028 Jewell Road';
        address1.Address__City__s = 'Chicago';
        address1.Address__StateCode__s = 'ID';
        address1.Address__CountryCode__s = 'US';
        address1.Address__PostalCode__s = '55404';
        address1.Type__c = 'Billing';
        address1.Account__c = testAccount.Id;
        insert address1;
        
        Test.startTest();
        ReportToAddressBatch reportToAddressBatchObj = new ReportToAddressBatch();
        Database.executeBatch(reportToAddressBatchObj, 10);
        Test.stopTest();
        System.assertEquals(1, testAccts.size());
    }
    
    @isTest
    static void testNoAddress() {
        // Create accounts
        List<Account> testAccts = new List<Account>();
        Account testAccount = IntappTestObjectFactory.createaccount(false);
        testAccount.Type = 'Client';
        testAccts.add(testAccount);

        insert testAccts;

        Test.startTest();
        ReportToAddressBatch reportToAddressBatchObj = new ReportToAddressBatch();
        Database.executeBatch(reportToAddressBatchObj, 10);
        Test.stopTest();
        System.assertEquals(1, testAccts.size());
    }
}