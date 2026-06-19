/********************************************************************************
*  Name             :  ContractOsaStatusServiceTest
*  Author           :  Sahal Mohamed
*  Description      :  Test class for ContractOsaStatusService (BIZ-68170).
*                      Covers CPQ Contract Status calculation, OSA Status sync,
*                      and Superseded_by_OSA propagation across sibling contracts.
*
*  Change history   :
*  Date          Author            Description
*  27/02/26      Sahal Mohamed     Created (BIZ-68170)
********************************************************************************/
@isTest
public class ContractOsaStatusServiceTest {

    /*****************************************************************************************
    *
    *  Test Setup
    *
    ******************************************************************************************/

    @testSetup
    static void setup() {
        Account acc = IntappTestObjectFactory.createaccount(true);

        // Contract 1: Active (today is between start and end)
        Contract con1 = IntappTestObjectFactory.createContract(acc.Id);
        con1.OSA_Number__c = 'OSA-TEST-001';
        con1.StartDate = Date.today().addDays(-30);
        con1.EndDate = Date.today().addDays(335);
        insert con1;
        con1.Status = 'In Force';
        update con1;

        // Contract 2: Same OSA number — sibling
        Contract con2 = IntappTestObjectFactory.createContract(acc.Id);
        con2.OSA_Number__c = 'OSA-TEST-001';
        con2.StartDate = Date.today().addDays(-30);
        con2.EndDate = Date.today().addDays(335);
        insert con2;
        con2.Status = 'In Force';
        update con2;

        // Contract 3: Different OSA — should NOT be affected by sibling sync
        Contract con3 = IntappTestObjectFactory.createContract(acc.Id);
        con3.OSA_Number__c = 'OSA-TEST-002';
        con3.StartDate = Date.today().addDays(-30);
        con3.EndDate = Date.today().addDays(335);
        insert con3;
        con3.Status = 'In Force';
        update con3;
    }

    /*****************************************************************************************
    *
    *  CPQ Contract Status Calculation Tests
    *
    ******************************************************************************************/

    @isTest
    static void testCpqStatus_ActiveWhenBetweenDates() {
        Contract con = [
            SELECT Id, CPQ_Contract_Status__c, StartDate, EndDate
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            LIMIT 1
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            con.CPQ_Contract_Status__c,
            'Contract between start and end date should be Active'
        );
    }

    @isTest
    static void testCpqStatus_NotStartedWhenFutureStart() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contract con = IntappTestObjectFactory.createContract(acc.Id);
        con.OSA_Number__c = 'OSA-TEST-FUTURE';
        con.StartDate = Date.today().addDays(30);
        con.EndDate = Date.today().addDays(395);
        insert con;

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_NOT_STARTED,
            result.CPQ_Contract_Status__c,
            'Contract with future start date should be Not Started'
        );
    }

    @isTest
    static void testCpqStatus_LapsedWhenPastEndDate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contract con = IntappTestObjectFactory.createContract(acc.Id);
        con.OSA_Number__c = 'OSA-TEST-PAST';
        con.StartDate = Date.today().addDays(-400);
        con.EndDate = Date.today().addDays(-5);
        insert con;

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result.CPQ_Contract_Status__c,
            'Contract past end date should be Lapsed'
        );
    }

    @isTest
    static void testCpqStatus_LapsedWhenStatusCancelled() {
        Contract con = [
            SELECT Id, Status, CPQ_Contract_Status__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-002'
            LIMIT 1
        ];

        Test.startTest();
        con.Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        update con;
        Test.stopTest();

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result.CPQ_Contract_Status__c,
            'Cancelled/Lapsed OSA Status should force CPQ status to Lapsed'
        );
    }

    @isTest
    static void testCpqStatus_LapsedWhenStatusSuperseded() {
        Contract con = [
            SELECT Id, Status, CPQ_Contract_Status__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-002'
            LIMIT 1
        ];

        Test.startTest();
        con.Status = ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT;
        update con;
        Test.stopTest();

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result.CPQ_Contract_Status__c,
            'Superseded OSA Status should force CPQ status to Lapsed'
        );
    }

    /*****************************************************************************************
    *
    *  OSA Status Sync Tests
    *
    ******************************************************************************************/

    @isTest
    static void testOsaStatusSync_SiblingsUpdated() {
        List<Contract> siblings = [
            SELECT Id, Status, OSA_Number__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            ORDER BY CreatedDate
        ];
        System.assertEquals(2, siblings.size(), 'Should have 2 sibling contracts');

        Test.startTest();
        siblings[0].Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        update siblings[0];
        Test.stopTest();

        Contract sibling = [
            SELECT Id, Status, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :siblings[1].Id
        ];
        System.assertEquals(
            ContractConstants.STATUS_CANCELLED_LAPSED,
            sibling.Status,
            'Sibling contract should have synced OSA Status'
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            sibling.CPQ_Contract_Status__c,
            'Sibling CPQ status should be Lapsed after cancellation sync'
        );
    }

    @isTest
    static void testOsaStatusSync_DifferentOsaNotAffected() {
        Contract con1 = [
            SELECT Id, Status, OSA_Number__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            LIMIT 1
        ];

        Test.startTest();
        con1.Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        update con1;
        Test.stopTest();

        Contract unrelated = [
            SELECT Id, Status, CPQ_Contract_Status__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-002'
            LIMIT 1
        ];
        System.assertEquals(
            ContractConstants.STATUS_INFORCE,
            unrelated.Status,
            'Contract with different OSA number should NOT be affected'
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            unrelated.CPQ_Contract_Status__c,
            'Unrelated contract CPQ status should remain Active'
        );
    }

    /*****************************************************************************************
    *
    *  Superseded_by_OSA Propagation Tests
    *
    ******************************************************************************************/

    @isTest
    static void testSupersededByOsa_PropagatedToSiblings() {
        // Create a target contract to use as Superseded_by_OSA reference
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contract target = IntappTestObjectFactory.createContract(acc.Id);
        target.OSA_Number__c = 'OSA-SUPERSEDE-TARGET';
        target.StartDate = Date.today().addDays(-30);
        target.EndDate = Date.today().addDays(335);
        insert target;
        target.Status = 'In Force';
        update target;

        List<Contract> siblings = [
            SELECT Id, Superseded_by_OSA__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            ORDER BY CreatedDate
        ];

        Test.startTest();
        ContractTriggerHandler.firstCallUpdate = false;
        siblings[0].Superseded_by_OSA__c = target.Id;
        update siblings[0];
        Test.stopTest();

        Contract sibling = [
            SELECT Id, Superseded_by_OSA__c
            FROM Contract
            WHERE Id = :siblings[1].Id
        ];
        System.assertEquals(
            target.Id,
            sibling.Superseded_by_OSA__c,
            'Superseded_by_OSA should propagate to sibling contracts'
        );
    }

    /*****************************************************************************************
    *
    *  calculateCpqStatus Unit Tests
    *
    ******************************************************************************************/

    @isTest
    static void testCalculateCpqStatus_NullDates() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_INFORCE, null, null
        );
        System.assertEquals(null, result, 'Null dates with In Force status should return null');
    }

    @isTest
    static void testCalculateCpqStatus_CancelledOverridesDates() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_CANCELLED_LAPSED,
            Date.today().addDays(-30),
            Date.today().addDays(335)
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result,
            'Cancelled status should override dates and return Lapsed'
        );
    }

    @isTest
    static void testCalculateCpqStatus_ActiveWithOnlyStartDate() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_INFORCE,
            Date.today().addDays(-30),
            null
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            result,
            'Contract with start date in past and no end date should be Active'
        );
    }

    @isTest
    static void testCalculateCpqStatus_SupersededOverridesDates() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT,
            Date.today().addDays(-30),
            Date.today().addDays(335)
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result,
            'Superseded status should override dates and return Lapsed'
        );
    }

    @isTest
    static void testCalculateCpqStatus_NotStartedFutureDate() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_INFORCE,
            Date.today().addDays(30),
            Date.today().addDays(395)
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_NOT_STARTED,
            result,
            'Future start date should return Not Started'
        );
    }

    @isTest
    static void testCalculateCpqStatus_LapsedPastEndDate() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_INFORCE,
            Date.today().addDays(-400),
            Date.today().addDays(-5)
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result,
            'Past end date should return Lapsed'
        );
    }

    @isTest
    static void testCalculateCpqStatus_ActiveBetweenDates() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_INFORCE,
            Date.today().addDays(-30),
            Date.today().addDays(335)
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            result,
            'Date between start and end should return Active'
        );
    }

    @isTest
    static void testCalculateCpqStatus_OnlyEndDateNoStart() {
        String result = ContractOsaStatusService.calculateCpqStatus(
            ContractConstants.STATUS_INFORCE,
            null,
            Date.today().addDays(335)
        );
        System.assertEquals(null, result, 'Only end date with no start date should return null');
    }

    /*****************************************************************************************
    *
    *  recalculateCpqStatusByDate Tests
    *
    ******************************************************************************************/

    @isTest
    static void testRecalculateCpqStatusByDate_ChangesDetected() {
        List<Contract> contracts = [
            SELECT Id, Status, CPQ_Contract_Status__c, StartDate, EndDate
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            LIMIT 1
        ];
        // Force a stale value to simulate overnight transition
        contracts[0].CPQ_Contract_Status__c = ContractConstants.CPQ_STATUS_NOT_STARTED;

        Test.startTest();
        List<Contract> changed = ContractOsaStatusService.recalculateCpqStatusByDate(contracts);
        Test.stopTest();

        System.assertEquals(1, changed.size(), 'Should detect 1 contract needing update');
        System.assertEquals(
            ContractConstants.CPQ_STATUS_ACTIVE,
            changed[0].CPQ_Contract_Status__c,
            'Should recalculate to Active'
        );
    }

    @isTest
    static void testRecalculateCpqStatusByDate_NoChanges() {
        List<Contract> contracts = [
            SELECT Id, Status, CPQ_Contract_Status__c, StartDate, EndDate
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            LIMIT 1
        ];
        // CPQ status already correct

        Test.startTest();
        List<Contract> changed = ContractOsaStatusService.recalculateCpqStatusByDate(contracts);
        Test.stopTest();

        System.assertEquals(0, changed.size(), 'No contracts should need update');
    }

    /*****************************************************************************************
    *
    *  syncOsaSiblings Edge Case Tests
    *
    ******************************************************************************************/

    @isTest
    static void testSyncOsaSiblings_BlankOsaNumber() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contract con = IntappTestObjectFactory.createContract(acc.Id);
        con.OSA_Number__c = '';
        con.StartDate = Date.today().addDays(-30);
        con.EndDate = Date.today().addDays(335);
        insert con;
        con.Status = 'In Force';
        update con;

        // Update with no OSA number — syncOsaSiblings should skip this record
        Test.startTest();
        ContractTriggerHandler.firstCallUpdate = false;
        con.Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        update con;
        Test.stopTest();

        // Verify sibling contracts with OSA-TEST-001 are unaffected
        Contract sibling = [
            SELECT Id, Status
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            LIMIT 1
        ];
        System.assertEquals(
            ContractConstants.STATUS_INFORCE,
            sibling.Status,
            'Blank OSA contract should not trigger sibling sync'
        );
    }

    @isTest
    static void testSyncOsaSiblings_NoSiblings() {
        // OSA-TEST-002 has only 1 contract — no siblings to sync
        Contract con = [
            SELECT Id, Status, OSA_Number__c
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-002'
            LIMIT 1
        ];

        Test.startTest();
        con.Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        update con;
        Test.stopTest();

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            result.CPQ_Contract_Status__c,
            'Contract with no siblings should still update its own CPQ status'
        );
    }

    @isTest
    static void testSyncOsaSiblings_BulkDmlSameOsa() {
        // P1 fix test: when two contracts with the same OSA Number are in the same bulk DML,
        // siblings that didn't originate the status change should still receive propagated values.
        List<Contract> siblings = [
            SELECT Id, Status, OSA_Number__c, Description
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-001'
            ORDER BY CreatedDate
        ];
        System.assertEquals(2, siblings.size(), 'Should have 2 sibling contracts');

        Test.startTest();
        ContractTriggerHandler.firstCallUpdate = false;
        // Contract 0 changes Status; Contract 1 changes only Description (unrelated)
        siblings[0].Status = ContractConstants.STATUS_CANCELLED_LAPSED;
        siblings[1].Description = 'Unrelated change';
        update siblings;
        Test.stopTest();

        Contract sibling = [
            SELECT Id, Status, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :siblings[1].Id
        ];
        System.assertEquals(
            ContractConstants.STATUS_CANCELLED_LAPSED,
            sibling.Status,
            'Sibling in same bulk DML should receive propagated OSA Status'
        );
        System.assertEquals(
            ContractConstants.CPQ_STATUS_LAPSED,
            sibling.CPQ_Contract_Status__c,
            'Sibling CPQ status should be Lapsed after bulk sync'
        );
    }

    @isTest
    static void testSetCpqContractStatus_NoChangeOnUnrelatedUpdate() {
        // Update a field that is NOT Status or dates — CPQ status should remain unchanged
        Contract con = [
            SELECT Id, Status, CPQ_Contract_Status__c, Description
            FROM Contract
            WHERE OSA_Number__c = 'OSA-TEST-002'
            LIMIT 1
        ];
        String originalCpqStatus = con.CPQ_Contract_Status__c;

        Test.startTest();
        con.Description = 'Updated description only';
        update con;
        Test.stopTest();

        Contract result = [
            SELECT Id, CPQ_Contract_Status__c
            FROM Contract
            WHERE Id = :con.Id
        ];
        System.assertEquals(
            originalCpqStatus,
            result.CPQ_Contract_Status__c,
            'CPQ status should not change when Status and dates are unchanged'
        );
    }
}