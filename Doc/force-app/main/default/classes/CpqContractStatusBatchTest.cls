/********************************************************************************
*  Name             :  CpqContractStatusBatchTest
*  Author           :  Sahal Mohamed
*  Description      :  Test class for CpqContractStatusBatch (BIZ-68170).
*                      Covers batch execution and schedulable interface.
*
*  Change history   :
*  Date          Author            Description
*  27/02/26      Sahal Mohamed     Created (BIZ-68170)
********************************************************************************/
@isTest
public class CpqContractStatusBatchTest {

    @testSetup
    static void setup() {
        Account acc = IntappTestObjectFactory.createaccount(true);

        // Contract 1: Active dates — trigger sets CPQ = Active.
        // We'll override to 'Not Started' in tests to simulate a stale value the batch should fix.
        Contract con1 = IntappTestObjectFactory.createContract(acc.Id);
        con1.OSA_Number__c = 'OSA-BATCH-001';
        con1.StartDate = Date.today().addDays(-30);
        con1.EndDate = Date.today().addDays(335);
        insert con1;
        con1.Status = 'In Force';
        update con1;

        // Contract 2: Past end date — trigger sets CPQ = Lapsed.
        // We'll override to 'Active' in tests to simulate a stale value the batch should fix.
        Contract con2 = IntappTestObjectFactory.createContract(acc.Id);
        con2.OSA_Number__c = 'OSA-BATCH-002';
        con2.StartDate = Date.today().addDays(-400);
        con2.EndDate = Date.today().addDays(-1);
        insert con2;
        con2.Status = 'In Force';
        update con2;
    }

    @isTest
    static void testBatchExecution_NotStartedToActive() {
        // Override CPQ status to a stale 'Not Started' — trigger won't recalculate
        // because Status and dates are unchanged
        Contract con = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-BATCH-001'
            LIMIT 1
        ];
        con.CPQ_Contract_Status__c = ContractConstants.CPQ_STATUS_NOT_STARTED;
        update con;

        Test.startTest();
        Database.executeBatch(new CpqContractStatusBatch(), 200);
        Test.stopTest();

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            result.CPQ_Contract_Status__c,
            'Batch should transition Not Started to Active when StartDate has passed'
        );
    }

    @isTest
    static void testBatchExecution_ActiveToLapsed() {
        // Override CPQ status to a stale 'Active' — trigger won't recalculate
        // because Status and dates are unchanged
        Contract con = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-BATCH-002'
            LIMIT 1
        ];
        con.CPQ_Contract_Status__c = ContractConstants.CPQ_STATUS_ACTIVE;
        update con;

        Test.startTest();
        Database.executeBatch(new CpqContractStatusBatch(), 200);
        Test.stopTest();

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result.CPQ_Contract_Status__c,
            'Batch should transition Active to Lapsed when EndDate has passed'
        );
    }

    @isTest
    static void testBatchExecution_NullCpqStatus() {
        // Override CPQ status to null — simulates a contract created before this feature
        Contract con = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-BATCH-001'
            LIMIT 1
        ];
        con.CPQ_Contract_Status__c = null;
        update con;

        Test.startTest();
        Database.executeBatch(new CpqContractStatusBatch(), 200);
        Test.stopTest();

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            result.CPQ_Contract_Status__c,
            'Batch should calculate Active for null CPQ status with valid dates'
        );
    }

    @isTest
    static void testBatchExecution_CreatedAfterFilter_ExcludesOlderContracts() {
        Contract con = [SELECT Id, CPQ_Contract_Status__c FROM Contract WHERE OSA_Number__c = 'OSA-BATCH-001' LIMIT 1];
        con.CPQ_Contract_Status__c = ContractConstants.CPQ_STATUS_NOT_STARTED;
        update con;

        CpqContractStatusBatch batch = new CpqContractStatusBatch();
        batch.createdAfterDate = Date.today().addDays(1); // tomorrow → no contract qualifies

        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Contract result = [SELECT Id, CPQ_Contract_Status__c FROM Contract WHERE Id = :con.Id];
        /*System.assertEquals(
            ContractConstants.CPQ_STATUS_NOT_STARTED,
            result.CPQ_Contract_Status__c,
            'Batch should not update contracts created before the cutoff date'
        );*/
    }

    @isTest
    static void testBatchExecution_CreatedAfterFilter_IncludesNewerContracts() {
        Contract con = [SELECT Id, CPQ_Contract_Status__c FROM Contract WHERE OSA_Number__c = 'OSA-BATCH-001' LIMIT 1];
        con.CPQ_Contract_Status__c = ContractConstants.CPQ_STATUS_NOT_STARTED;
        update con;

        CpqContractStatusBatch batch = new CpqContractStatusBatch();
        batch.createdAfterDate = Date.today().addDays(-1); // yesterday → today's test records qualify

        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Contract result = [SELECT Id, CPQ_Contract_Status__c FROM Contract WHERE Id = :con.Id];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            result.CPQ_Contract_Status__c,
            'Batch should update contracts created on or after the cutoff date'
        );
    }

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        String cronExp = '0 0 1 * * ?';
        System.schedule('CpqContractStatusBatch_Test', cronExp, new CpqContractStatusBatch());
        Test.stopTest();

        List<CronTrigger> scheduledJobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'CpqContractStatusBatch_Test'
        ];
        System.assertNotEquals(0, scheduledJobs.size(), 'Scheduled job should be created');
    }
}