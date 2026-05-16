/**
 * @description       : This test class will cover AddressTriggerHelperclass.
 * @author            : Pankaj Kumar
**/
@isTest
public class AddressTriggerHandlerTest {
   
    /*************************************************************
    * 
    * Test Setup
    * 
    ************************************************************/
    /**
     * @description This method is test setup method for Address object
     */
    @testSetup
    public static void setup(){
        List<Account> accList = TestDataFactory.createAccount(1,True);              
        List<Address__c> createAddress = TestDataFactory.createAddress(50,true,accList[0].Id);
        createAddress[0].Status__c = AddressConstants.PENDING_GOVERNANCE;
        createAddress[0].Default_Shipping_Address__c = false;
        createAddress[0].Default_Billing_Address__c = true;
        update createAddress[0];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestFactory.createSObject(
                new User(
                    UserName='BizApps.Integration@test.com',
                    FirstName = 'Biz Apps', 
                    LastName = 'Integration'
                ), 
                'AdminUserDefaults'
            );
        }
    }

    /*************************************************************
    * 
    * Test Methods
    * 
    ************************************************************/
    /**
     * @description This method is test method for Billing Address Check
    **/
    @isTest
    public static void testBillingAddressCreation(){
        List<User> createSalesUser = TestDataFactory.createSalesUser(1,false);
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<Address__c> createAddress=[Select id from Address__c limit 1];
        System.runAs(createSalesUser[0]){
            Test.startTest();
                List<Address__c> createBillingAddress = TestDataFactory.createBillingAddress(1,true,accList[0].Id);
            Test.stopTest();
            Address__c a =[Select id,Default_Billing_Address__c,Default_Shipping_Address__c from Address__c where id=:createAddress[0].id];
            System.assertEquals(false, a.Default_Billing_Address__c,  'Default Billing Address Not Updated');
            delete createBillingAddress;
            undelete createBillingAddress;
        }
    }

    /**
    * @description This method is test method for Shipping Address Check
    **/
    @isTest
    public static void testShippingAddressCreation(){
        List<User> createSalesUser = TestDataFactory.createSalesUser(1,false);
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<Address__c> createAddress = [Select id,Default_Shipping_Address__c from Address__c limit 1];
        System.runAs(createSalesUser[0]){
            Test.startTest();
                TestDataFactory.createShippingAddress(1,true,accList[0].Id);
            Test.stopTest();
            Address__c a =[Select id,Default_Shipping_Address__c,Default_Billing_Address__c from Address__c where id=:createAddress[0].id];
            System.assertEquals(false, a.Default_Shipping_Address__c, 'Default Shipping Address Not Updated');
            System.assertNotEquals(false, a.Default_Billing_Address__c, 'Default Billing Address Not Updated');
        }
    }

    /*
    * @description This method is test method for Account Address Change
    */
    @isTest
    public static void testHandleAccountAddressChange(){
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<User> getIntegrationUser = [SELECT Id FROM User WHERE Name = 'Biz Apps Integration' AND IsActive = true LIMIT 1];
        System.runAs(getIntegrationUser[0]){
            Test.startTest();
                accList[0].ShippingCountry = 'United States';
                accList[0].ShippingPostalCode = '12345';
                accList[0].ShippingCity = 'Test';
                accList[0].BillingStreet = 'Test';
                accList[0].BillingPostalCode = '12345';
                accList[0].BillingCity = 'Test';
                update accList[0];

            Test.stopTest();
        }
        List<Address__c> listOfAddress = [SELECT ID FROM Address__c WHERE Account__c = :accList[0].Id and Default_Shipping_Address__c = true];
        System.assertEquals(true, !listOfAddress.isEmpty(), 'Addresses Created');
    }

    /**
    * @description This method is test method for Account Address Shipping Change
    */
    @isTest
    public static void testHandleAccountAddressShippingChange(){
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<User> getIntegrationUser = [SELECT Id FROM User WHERE Name = 'Biz Apps Integration' AND IsActive = true LIMIT 1];
        System.runAs(getIntegrationUser[0]){
            Test.startTest();
                accList[0].ShippingCountry = 'United States';
                accList[0].ShippingPostalCode = '12345';
                accList[0].ShippingCity = 'Test';
                update accList[0];
            
            Test.stopTest();
        }
        List<Address__c> listOfAddress = [SELECT ID FROM Address__c WHERE Account__c = :accList[0].Id and Default_Shipping_Address__c = true];
        System.assertEquals(true, !listOfAddress.isEmpty(), 'Addresses Created');
    }
    
    /*
    * @description This method is test method for Account Address Billing Change
    */
    @isTest
    public static void testHandleAccountAddressBillingChange(){
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<User> getIntegrationUser = [SELECT Id FROM User WHERE Name = 'Biz Apps Integration' AND IsActive = true LIMIT 1];
        System.runAs(getIntegrationUser[0]){
            Test.startTest();
                accList[0].BillingStreet = 'Test';
                accList[0].BillingPostalCode = '12345';
                accList[0].BillingCity = 'Test';
                update accList[0];

            Test.stopTest();
        }
        
        List<Address__c> listOfAddress = [SELECT ID FROM Address__c WHERE Account__c = :accList[0].Id and Default_Shipping_Address__c = true];
        System.assertEquals(true, !listOfAddress.isEmpty(), 'Addresses Created');
    }
    
    /*
    * @description This method is test method for Account Address Shipping Updates Change
    */
    @isTest
    public static void testHandleAccountAddressBillingUpdatesChange(){
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<User> getIntegrationUser = [SELECT Id FROM User WHERE Name = 'Biz Apps Integration' AND IsActive = true LIMIT 1];
        System.runAs(getIntegrationUser[0]){
            Test.startTest();
                accList[0].BillingStreet = 'Test';
                accList[0].BillingPostalCode = '12345';
                accList[0].BillingCity = 'Test';
                update accList[0];

            Test.stopTest();
        }
        List<Address__c> listOfAddress = [SELECT ID FROM Address__c WHERE Account__c = :accList[0].Id and Default_Shipping_Address__c = true];
        //System.assertEquals(true, !listOfAddress.isEmpty(), 'Addresses Created');
    }
    
    /**
    * @description This method is test method for Default Shipping Address Creation
    */
    @isTest
    public static void testDefaultShippingAddressCreation(){
        List<User> createSalesUser = TestDataFactory.createSalesUser(1,false);
        List<Account> accList = [Select Id,Name From Account Limit 1];
        List<Address__c> createAddress = [Select id,Default_Shipping_Address__c from Address__c limit 1];
        System.runAs(createSalesUser[0]){
            Test.startTest();
                List<Address__c> createShippingAddress = TestDataFactory.createShippingAddress(1,true,accList[0].Id);
                createShippingAddress[0].Default_Shipping_Address__c = true;
                createShippingAddress[0].Default_Billing_Address__c = true;
                createShippingAddress[0].Status__c = AddressConstants.PENDING_GOVERNANCE;
                update createShippingAddress[0];
            Test.stopTest();
            Address__c a =[Select id,Default_Shipping_Address__c,Default_Billing_Address__c from Address__c where id=:createAddress[0].id];
            System.assertEquals(false, a.Default_Shipping_Address__c, 'Default Shipping Address Not Updated');
            System.assertNotEquals(false, a.Default_Billing_Address__c, 'Default Billing Address Not Updated');
        }
    }
}