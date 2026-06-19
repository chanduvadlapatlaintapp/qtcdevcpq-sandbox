/**
* @description       : This class is a test class for ItemMasterProduct Trigger.
* @author            : Suresh Somu
**/
@isTest
public class ItemMasterProductTriggerTest {

    /**
    * @description : This method will handle Data Setup for test class.
    **/ 
    @testSetup
    static void setupData() {
        insert new Item_Master_Product__c(Name = 'ExistingName');
    }

    /**
    * @description : This method will handle test coverage for insert and update actions of Item Master Product trigger.
    **/ 
    @isTest
    private static void validateItemMasterNameTest() {
        Test.startTest();
            try {
                Item_Master_Product__c rec1 = new Item_Master_Product__c(Name = 'DupName');
                Item_Master_Product__c rec2 = new Item_Master_Product__c(Name = 'DupName');
                insert new List<Item_Master_Product__c>{rec1, rec2};
                System.assert(false, 'Expected error on name update');
            } catch (DmlException e) {
                String expected = 'Duplicate Name found within same request: DupName';
                String actual = e.getDmlMessage(0);
                System.assertEquals(true, actual.contains(expected),
                    'Expected error message to contain: "' + expected + '", but got: "' + actual + '"');
            }
            try {
                insert new Item_Master_Product__c(Name = 'ExistingName');
                System.assert(false, 'Expected error on name update');
            } catch (DmlException e) {
                String expected = 'A record with Name "ExistingName" already exists.';
                String actual = e.getDmlMessage(0);
                System.assertEquals(true, actual.contains(expected),
                    'Expected error message to contain: "' + expected + '", but got: "' + actual + '"');
            }
            
            Item_Master_Product__c rec = new Item_Master_Product__c(Name = 'OriginalName');
            insert rec;

            rec.Name = 'UpdatedName';

            try {
                update rec;
                System.assert(false, 'Expected error on name update');
            } catch (DmlException e) {
                String expected = 'Updating the Name field is not allowed.';
                String actual = e.getDmlMessage(0);
                System.assertEquals(true, actual.contains(expected),
                    'Expected error message to contain: "' + expected + '", but got: "' + actual + '"');
            }        
        Test.stopTest();
    }
}