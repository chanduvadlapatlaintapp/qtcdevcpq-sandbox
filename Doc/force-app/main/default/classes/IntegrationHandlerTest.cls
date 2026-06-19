@isTest
public class IntegrationHandlerTest {

    @isTest
    public static void testAccUpdate() {
        // Create initial Account
        Account acc = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Original Name',
                ShippingStreet = 'Ship Street',
                ShippingCity = 'Ship City',
                ShippingPostalCode = '20002',
                ShippingCountry = 'CountryY',
                Subsidiaries__c = 'Subsidiary1',
                Subsidiary__c = '01:200 Integration Appliance (US)',
                AVA_MAPPER__Business_Identification_Number__c = 'BID456'
            ), 'AccountDefaults'
        );
        
        // Prepare the old map with original values
        Account accOld = acc.clone(false, true, false, false);
        accOld.Name = 'Original Name';
        accOld.VAT_Number__c = 'OldVAT';
        accOld.Invoicing_Email__c = 'old@example.com';
        accOld.BillingCountry = 'OldCountry';
        accOld.BillingStreet = 'OldStreet';
        accOld.BillingState = 'OldState';
        accOld.BillingPostalCode = 'OldPostal';
        accOld.ShippingCountry = 'OldShipCountry';
        accOld.ShippingStreet = 'OldShipStreet';
        accOld.ShippingCity = 'OldShipCity';
        accOld.ShippingState = 'OldShipState';
        accOld.ShippingPostalCode = 'OldShipPostal';
        accOld.AVA_MAPPER__Business_Identification_Number__c = 'OldBID';
        accOld.Subsidiaries__c = 'Subsidiary1';
        accOld.Subsidiary__c = '01:200 Integration Appliance (US)';

        Map<Id, Account> oldMap = new Map<Id, Account>{ acc.Id => accOld };
		
        acc.ShippingStreet = 'NewShipStreet';
        acc.ShippingCity = 'NewShipCity';
        acc.ShippingState = 'NewShipState';
        acc.ShippingPostalCode = 'NewShipPostal';
        acc.AVA_MAPPER__Business_Identification_Number__c = 'NewBID';
        update acc;

        List<Account> newList = new List<Account>{ acc };

        Test.startTest();
        IntegrationHandler.accountEventAfterUpdate(newList, oldMap);
        Test.stopTest();

        System.assertEquals('NewBID', acc.AVA_MAPPER__Business_Identification_Number__c); // Ensure changes applied
    }
}