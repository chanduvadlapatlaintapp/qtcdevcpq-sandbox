/**
 * @description Test class for CollectionUtil utility methods.
 *              Covers both getIdsNotInSet and getRecordsNotInSet.
 * @author      Manisha
 * @date        2025-07-02
 * @jira        N/A
 */
@isTest
private class CollectionUtilTest {

    /**
     * @description Test for getIdsNotInSet and getRecordsNotInSet using factory-generated Account records.
     */
    @isTest
    static void testCollectionUtilMethods() {
        // Create 3 accounts using TestFactory
        List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
            new Account(Name = 'Test Account'),
            3,
            'AccountDefaults'
        );

        // Create a set with only the first account ID to simulate exclusion
        Set<Id> existingIds = new Set<Id>{ accounts[0].Id };

        // Call getIdsNotInSet
        Set<Id> resultIds = CollectionUtil.getIdsNotInSet(accounts, existingIds);
        System.assertEquals(2, resultIds.size(), 'Should return 2 IDs not in the existing set');
        System.assert(!resultIds.contains(accounts[0].Id), 'Should not include already existing ID');

        // Call getRecordsNotInSet
        List<SObject> resultRecords = CollectionUtil.getRecordsNotInSet(accounts, existingIds);
        System.assertEquals(2, resultRecords.size(), 'Should return 2 records not in the existing set');
        for (SObject sObj : resultRecords) {
            System.assert(!existingIds.contains(sObj.Id), 'Returned record should not be in the excluded ID set');
        }
    }
}