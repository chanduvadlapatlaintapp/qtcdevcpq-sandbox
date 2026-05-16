/**
 * @author  : Ratan Paul
 * @date    : 05/02/2025
 * @description : Test class for GenericRelatedListController Ensures Query returns correct results.
 * @jira    : BIZ-68163
 */
@isTest
public class GenericRelatedListControllerTest {

    @isTest
    static void testGetRelatedRecords() {
        // Create initial Accounts with common Industry to simulate "related" field
        Account acc1 = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account 1', 
                Industry = 'Technology'
            ), 'AccountDefaults'
        );
        Account acc2 = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account 2', 
                Industry = 'Technology'
            ), 'AccountDefaults'
        );
        Account acc3 = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account 3', 
                Industry = 'Finance'
            ), 'AccountDefaults'
        );

        Test.startTest();

        // Call the method under test
        List<SObject> relatedRecords = GenericRelatedListController.getRelatedRecords(
            'Account',
            'Name,Industry',
            'Industry',
            acc1.Id
        );

        Test.stopTest();

        // Verify results
        System.assertNotEquals(null, relatedRecords, 'Expected non-null related records');
        System.assertEquals(1, relatedRecords.size(), 'Only one other record with matching Industry should be returned');

        Account returnedAcc = (Account) relatedRecords[0];
        System.assertEquals('Technology', returnedAcc.Industry);
        System.assertNotEquals(acc1.Id, returnedAcc.Id); // ensure original is excluded
    }
}