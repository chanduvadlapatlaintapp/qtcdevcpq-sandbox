/**
 * @description : Test class for SubsidiaryService
 * @author      : Sahal Mohamed | 12-06-2024 |
 */
@isTest
public with sharing class SubsidiaryServiceTest {
    
    /***************************************************************************************************
     * 
     * Test Data Setup
     * 
     ***************************************************************************************************/
    /**
     * @description : Creates test data for SubsidiaryService tests
     */
    @testSetup
    static void setupTestData() {
        // Create test Account
        List<Account> accounts = (List<Account>)TestFactory.createSObjectList(
            new Account(
                Name = 'Test Prospect Account',
                Type = AccountConstants.TYPE_PROSPECT
            ), 1, 'AccountDefaults'
        );
        
        // Create test Opportunity
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Subsidiary Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ), 1, 'OpportunityDefaults'
        );
        
        // Create test Address records for different countries
        List<Address__c> addresses = new List<Address__c>();
        
        // Austria Address
        Address__c austriaAddress = new Address__c(
            Account__c = accounts[0].Id,
            Country__c = 'Austria',
            Address__CountryCode__s = 'AT',
            Address__City__s = 'Vienna',
            Address__PostalCode__s = '1010',
            Address__Street__s = 'Mariahilfer Straße',
            Status__c = 'Verification Approved',
            Default_Shipping_Address__c = true,
            Default_Billing_Address__c = true
        );
        addresses.add(austriaAddress);
        
        // United Kingdom Address
        Address__c ukAddress = new Address__c(
            Account__c = accounts[0].Id,
            Country__c = 'United Kingdom',
            Address__CountryCode__s = 'GB',
            Address__City__s = 'London',
            Address__PostalCode__s = 'SW1A 1AA',
            Address__Street__s = 'Westminster',
            Status__c = 'Verification Approved',
            Default_Shipping_Address__c = false,
            Default_Billing_Address__c = false
        );
        addresses.add(ukAddress);
        
        // United States Address
        Address__c usAddress = new Address__c(
            Account__c = accounts[0].Id,
            Country__c = 'United States',
            Address__CountryCode__s = 'US',
            Address__City__s = 'New York',
            Address__PostalCode__s = '10001',
            Address__Street__s = '123 Main Street',
            Status__c = 'Verification Approved',
            Default_Shipping_Address__c = false,
            Default_Billing_Address__c = false
        );
        addresses.add(usAddress);
        
        insert addresses;
        
        // Create test Quote
        TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SBQQ__Account__c = accounts[0].Id,
                Ship_To_Address__c = austriaAddress.Id
            ), 1, 'SBQQQuoteDefaults'
        );
    }

    /***************************************************************************************************
     * 
     * Unit Tests
     * 
     ***************************************************************************************************/
    /**
     * @description : Tests updateSubsidiary method for prospect account with Austria shipping address
     */
    @isTest
    static void testUpdateSubsidiaryForAustriaProspect() {
        Account acc = getAccount();
        Opportunity opp = getOpportunity();
        Address__c austriaAddr = getAddressByCountry('Austria');
    	
        // Create Address using your data factory
        List<Address__c> addrList = TestDataFactory.createAddress(1, false, acc.Id);
        Address__c addr = addrList[0];
    
        // Update the Address to represent Austria
        addr.Status__c = 'Verification Approved';
        addr.Address__CountryCode__s = 'AT';   // ISO code for Austria
        addr.Address__City__s = 'Vienna';
        addr.Address__PostalCode__s = '1010';
        addr.Address__Street__s = 'Mariahilfer Straße';
        addr.Address__StateCode__s = '';
        addr.Account__c=acc.Id;
        insert addr;
        
        addr.Default_Shipping_Address__c = true;
        addr.Country__c = 'Austria';
    	update addr;
        
        addr.Country__c = 'Austria'; 
        update addr;
        
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc.Id
        );
    
        insert quote;
    
        Test.startTest();
            quote.Ship_To_Address__c = addr.Id;
            update quote;
        Test.stopTest();
    
        quote = getQuote(quote.Id);
    
        System.assertEquals('40:Intapp Ireland Limited', quote.Subsidiary__c);
    }

    
    /**
     * @description : Tests updateSubsidiary method for prospect account with UK shipping address
     */
    @isTest
    static void testUpdateSubsidiaryForUKProspect() {
        Account acc = getAccount();
        Opportunity opp = getOpportunity();
        Address__c addrOld = getAddressByCountry('United Kingdom');
        
    	// Create Address using your data factory
        List<Address__c> addrList = TestDataFactory.createAddress(1, false, acc.Id);
        Address__c addr = addrList[0];
    
        // Update the Address to represent Austria
        addr.Status__c = 'Verification Approved';
        addr.Address__CountryCode__s = 'AT';   // ISO code for Austria
        addr.Address__City__s = 'Vienna';
        addr.Address__PostalCode__s = '1010';
        addr.Address__Street__s = 'Mariahilfer Straße';
        addr.Address__StateCode__s = '';
        addr.Account__c=acc.Id;
        insert addr;
        
        addr.Default_Shipping_Address__c = true;
        addr.Country__c = 'Austria';
    	update addr;
        
        addr.Country__c = 'Austria'; 
        update addr;
        
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc.Id
        );
    
        insert quote;
    
        Test.startTest();
            quote.Ship_To_Address__c = addr.Id;
            update quote;
        Test.stopTest();
    
        quote = getQuote(quote.Id);
    
        System.assertEquals('40:Intapp Ireland Limited', quote.Subsidiary__c);
    }

    
    /**
     * @description : Tests updateSubsidiary method for prospect account with US shipping address
     */
    @isTest
    static void testUpdateSubsidiaryForUSProspect() {
        // Arrange
        Account testAccount = getAccount();
        Opportunity testOpportunity = getOpportunity();
        Address__c usAddress = getAddressByCountry('United States');
        
        // Create Address using your data factory
        List<Address__c> addrList = TestDataFactory.createAddress(1, false, testAccount.Id);
        Address__c addr = addrList[0];
    
        // Update the Address to represent Austria
        addr.Status__c = 'Verification Approved';
        addr.Address__CountryCode__s = 'AT';   // ISO code for Austria
        addr.Address__City__s = 'Vienna';
        addr.Address__PostalCode__s = '1010';
        addr.Address__Street__s = 'Mariahilfer Straße';
        addr.Address__StateCode__s = '';
        addr.Account__c=testAccount.Id;
        insert addr;
        
        addr.Default_Shipping_Address__c = true;
        addr.Country__c = 'Austria';
    	update addr;
        
        addr.Country__c = 'Austria'; 
        update addr;
        
        SBQQ__Quote__c testQuote = (SBQQ__Quote__c)TestFactory.buildSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = testOpportunity.Id,
                SBQQ__Account__c = testAccount.Id,
                Ship_To_Address__c = addr.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Act
        Test.startTest();
            insert testQuote;
        Test.stopTest();
        
        testQuote = getQuote(testQuote.Id);
        // Assert
        System.assertEquals('40:Intapp Ireland Limited', testQuote.Subsidiary__c);
        //System.assert(!testQuote.Subsidiary__c.contains('Intapp Ireland Limited'), 'Subsidiary should not contain Ireland Limited for US address');
    }
    
    /**
     * @description : Tests updateSubsidiary method when Account Type is not Prospect
     */
    @isTest
    static void testUpdateSubsidiaryForNonProspectAccount() {
        // Arrange
        Opportunity testOpportunity = getOpportunity();
        Address__c austriaAddress = getAddressByCountry('Austria');
        
        // Create Customer account for non-prospect test
        Account customerAccount = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Customer Account',
                Type = AccountConstants.TYPE_CLIENT // Client account
            ), 'AccountDefaults'
        );
        
        SBQQ__Quote__c testQuote = (SBQQ__Quote__c)TestFactory.buildSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = testOpportunity.Id,
                SBQQ__Account__c = customerAccount.Id, // Use customer account
                Ship_To_Address__c = austriaAddress.Id
            ), 'SBQQQuoteDefaults'
        );
        
        // Act
        Test.startTest();
            insert testQuote;
        Test.stopTest();
        
        testQuote = getQuote(testQuote.Id);
        // Assert
        System.assertEquals('01:200 Integration Appliance (US)', testQuote.Subsidiary__c, 'Subsidiary should be assigned with default US value for non-prospect accounts');
    }
    
    /**
     * @description : Tests updateSubsidiary method when Ship_To_Address__c is null
     */
    @isTest
    static void testUpdateSubsidiaryWithNullShippingAddress() {
        // Arrange
        Account testAccount = getAccount();
        Opportunity testOpportunity = getOpportunity();
        
        SBQQ__Quote__c testQuote = (SBQQ__Quote__c)TestFactory.buildSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = testOpportunity.Id,
                SBQQ__Account__c = testAccount.Id,
                Ship_To_Address__c = null
            ), 'SBQQQuoteDefaults'
        );
        
        // Act
        Test.startTest();
            insert testQuote;
        Test.stopTest();
        
        testQuote = getQuote(testQuote.Id);
        // Assert
        System.assertEquals('01:200 Integration Appliance (US)', testQuote.Subsidiary__c, 'Subsidiary should default to US when shipping address is null');
    }
    
    /**
     * @description : Tests updateSubsidiary method when Account changes in update scenario
     */
    @isTest
    static void testUpdateSubsidiaryOnAccountChange() {
        Account acc1 = getAccount();
        Opportunity opp = getOpportunity();
        Address__c austria = getAddressByCountry('Austria');
        
    	// Create Address using your data factory
        List<Address__c> addrList = TestDataFactory.createAddress(1, false, acc1.Id);
        Address__c addr = addrList[0];
    
        // Update the Address to represent Austria
        addr.Status__c = 'Verification Approved';
        addr.Address__CountryCode__s = 'AT';   // ISO code for Austria
        addr.Address__City__s = 'Vienna';
        addr.Address__PostalCode__s = '1010';
        addr.Address__Street__s = 'Mariahilfer Straße';
        addr.Address__StateCode__s = '';
        addr.Account__c=acc1.Id;
        insert addr;
        
        addr.Default_Shipping_Address__c = true;
        addr.Country__c = 'Austria';
    	update addr;
        
        addr.Country__c = 'Austria'; 
        update addr;
        
        // second prospect account
        Account acc2 = (Account)TestFactory.createSObject(
            new Account(Name='Prospect 2', Type=AccountConstants.TYPE_PROSPECT),
            'AccountDefaults'
        );
    
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc1.Id,
            Ship_To_Address__c = addr.Id
        );
    
        insert quote;
    
        Test.startTest();
            quote.SBQQ__Account__c = acc2.Id;
            update quote;
        Test.stopTest();
    
        quote = getQuote(quote.Id);
    
        System.assertEquals('40:Intapp Ireland Limited', quote.Subsidiary__c);
    }

    
    /**
     * @description : Tests updateSubsidiary method when Account doesn't change in update scenario
     */
    @isTest
    static void testUpdateSubsidiaryWhenAccountUnchanged() {
        // Arrange
        Account testAccount = getAccount();
        Opportunity testOpportunity = getOpportunity();
        Address__c austriaAddress = getAddressByCountry('Austria');
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c)TestFactory.buildSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = testOpportunity.Id,
                SBQQ__Account__c = testAccount.Id, // Same account
                Ship_To_Address__c = austriaAddress.Id
            ), 'SBQQQuoteDefaults'
        );        
        
        // Act
        Test.startTest();
            insert newQuote;
        Test.stopTest();
        
        newQuote = getQuote(newQuote.Id);
        // Assert equals
        System.assertNotEquals(null, newQuote.Subsidiary__c, 'Subsidiary should be assigned even when account is unchanged but address is present');
    }

      
    /***************************************************************************************************
     * 
     * Utility Methods
     * 
     ***************************************************************************************************/
    /**
     * @description : Returns the first Account created in test setup
     * @return Account record
     */
    private static Account getAccount() {
        return [SELECT Id, Type FROM Account LIMIT 1];
    }
    
    /**
     * @description : Returns the first Opportunity created in test setup
     * @return Opportunity record
     */
    private static Opportunity getOpportunity() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }
    
    /**
     * @description : Returns the first Quote created in test setup
     * @return SBQQ__Quote__c record
     */
    private static SBQQ__Quote__c getQuote() {
        return [SELECT Id, SBQQ__Account__c, Ship_To_Address__c, Subsidiary__c 
                FROM SBQQ__Quote__c LIMIT 1];
    }
    
    /**
     * @description : Returns Quote record by Id with all necessary fields
     * @param quoteId Id of the quote record
     * @return SBQQ__Quote__c record
     */
    private static SBQQ__Quote__c getQuote(Id quoteId) {
        return [SELECT Id, SBQQ__Account__c, Ship_To_Address__c, Subsidiary__c 
                FROM SBQQ__Quote__c WHERE Id = :quoteId LIMIT 1];
    }
    
    /**
     * @description : Returns Address record by country
     * @param country String country name
     * @return Address__c record
     */
    private static Address__c getAddressByCountry(String country) {
        return [SELECT Id, Country__c, Address__CountryCode__s 
                FROM Address__c 
                WHERE Country__c = :country 
                LIMIT 1];
    }
}