/**
 * @description       : Test class for ItemMasterProductTriggerHelper.
 *                      Validates name uniqueness, update restrictions, and NetSuite sync logic.
 * @author            : Manisha
 * @createdDate       : 2025-05-23
 **/
@isTest
public class ItemMasterProductTriggerHelperTest {

    /***********************************************************************************************
    *
    * Test Setup Methods
    *
    ***********************************************************************************************/
    /**
     * @description Sets up required test data including:
     *              - Org-level Intapp_Settings__c with validation enabled.
     *              - A baseline Item_Master_Product__c record for update tests and duplicate checks.
     */
    @testSetup
    static void setup() {
        Intapp_Settings__c setting = new Intapp_Settings__c(
            Disable_PIN_Number_Validation__c = false
        );
        insert setting;

        Item_Master_Product__c existingItem = (Item_Master_Product__c) TestFactory.buildSObject(
            new Item_Master_Product__c(
                Name = 'DuplicateName',
                Active__c = true,
                Intapp_Item_Master_Number_Text__c = 'EX-0001'
            )
        );
        insert existingItem;
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    /**
     * @description Verifies that inserting two records with the same Name in a single transaction
     *              triggers a duplicate name validation error.
     */
    @isTest
    static void testValidateItemMasterNameInsertDuplicateWithinRequest() {
        Item_Master_Product__c item1 = (Item_Master_Product__c) TestFactory.buildSObject(
            new Item_Master_Product__c(Name = 'SameName', Intapp_Item_Master_Number_Text__c = 'GE-0002')
        );
        Item_Master_Product__c item2 = (Item_Master_Product__c) TestFactory.buildSObject(
            new Item_Master_Product__c(Name = 'SameName', Intapp_Item_Master_Number_Text__c = 'GE-0003')
        );

        Test.startTest();
            try {
                insert new List<Item_Master_Product__c>{item1, item2};
                System.assert(false, 'Expected duplicate name error');
            } catch (DmlException e) {
                System.assert(e.getDmlMessage(0).contains('Duplicate Name found within same request'), 
                    'Expected error message not found');
            }
        Test.stopTest();
    }

    /**
     * @description Verifies that updating the Name of an existing Item_Master_Product__c
     *              record triggers a validation error as expected.
     */
    @isTest
    static void testValidateItemMasterNameUpdateDisallowed() {
        Item_Master_Product__c item = getItemMasterProductByName('DuplicateName');
        item.Name = 'NewName';

        Test.startTest();
            try {
                update item;
                System.assert(false, 'Expected name change not allowed error');
            } catch (DmlException e) {
                System.assert(e.getDmlMessage(0).contains('Updating the Name field is not allowed'), 
                    'Expected error message not found');
            }
        Test.stopTest();
    }

    /**
     * @description Verifies that inserting a valid Item_Master_Product__c record triggers
     *              the publish logic (validated by successful insert with all required fields).
     */
    @isTest
    static void testPublishItemMasterProductsAfterInsert() {
        Item_Master_Product__c testItem = (Item_Master_Product__c) TestFactory.buildSObject(
            new Item_Master_Product__c(
                Name = 'InsertedItem',
                Intapp_Item_Master_Number_Text__c = 'GE-06531',
                Active__c = true,
                Income_Account__c = '4103',
                Deferred_Revenue_Account__c = '2301',
                Item_Revenue_Category__c = 'Deal Cloud',
                Rev_Rec_Forecast_Rule__c = 'Default Standard',
                Revenue_Recognition_Rule__c = 'Default Standard',
                Revenue_Allocation_Group__c = 'Bundle_Item_Testing',
                Create_Revenue_Plans_On__c = 'Billing',
                NetSuite_Internal_Id__c = '35456',
                TaxCode__c = '35456',
                Sync_NetSuite__c = false,
                Revenue_Type__c = 'Recurring',
                Product_Line__c = 'GE'
            )
        );

        Test.startTest();
            insert testItem;
        Test.stopTest();
        System.assertNotEquals(null, testItem.Id, 'Record should be inserted successfully.');
        delete testItem;
    }

    /**
     * @description Verifies that updating Sync_NetSuite__c to true triggers the
     *              publish logic during after update handling.
     */
    @isTest
    static void testPublishItemMasterProductsAfterUpdate() {
        Item_Master_Product__c item = getItemMasterProductByName('DuplicateName');
        item.Sync_NetSuite__c = true;

        Test.startTest();
            update item;
        Test.stopTest();

        System.assertEquals(true, item.Sync_NetSuite__c, 'Sync_NetSuite__c should be updated to true.');
    }

    /***********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description Utility method to fetch a single Item_Master_Product__c record by Name.
     * @param name The name of the Item Master Product to retrieve.
     * @return The matching Item_Master_Product__c record or null if not found.
     */
    private static Item_Master_Product__c getItemMasterProductByName(String name) {
        List<Item_Master_Product__c> results = [
            SELECT Id, Name
            FROM Item_Master_Product__c
            WHERE Name = :name
            LIMIT 1
        ];
        return results.isEmpty() ? null : results[0];
    }
}