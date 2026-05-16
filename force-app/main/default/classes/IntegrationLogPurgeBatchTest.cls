@isTest
private class IntegrationLogPurgeBatchTest {

    // Test method to cover the batch execution
    @isTest
    static void testBatchExecution() {
        // Create test data
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        Date sevenDaysAgo = Date.today().addDays(-10);
        logs.add(new Integration_Log__c(CreatedDate = sevenDaysAgo));
        insert logs;

        Test.startTest();
        // Instantiate and execute the batch class
        IntegrationLogPurgeBatch batchInstance = new IntegrationLogPurgeBatch();
        Id batchInstanceId = Database.executeBatch(batchInstance);
        Test.stopTest();

        // Assert that all records are deleted
        List<Integration_Log__c> remainingLogs = [SELECT Id FROM Integration_Log__c];
        System.assertEquals(0, remainingLogs.size(), 'Records were not deleted successfully.');
    }

    // Test method to cover the schedulable implementation
    @isTest
    static void testSchedulableMethod() {
        Test.startTest();

            // Execute method
            String cronLabel = System.Label.DeleteIntegrationLogsCronExpr; // Fire at midnight every day
            System.schedule('IntegrationLogPurgeBatchJob Test', cronLabel, new IntegrationLogPurgeBatch());
        Test.stopTest();
    }
}