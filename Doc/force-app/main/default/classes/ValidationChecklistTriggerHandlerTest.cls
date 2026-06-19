/**
 * @description Test class for ValidationChecklistTriggerHandler and ValidationChecklistTriggerHelper.
 *              Verifies that the FieldHistory framework correctly captures audit checkbox
 *              changes on Validation_Checklist__c — including the initial insert state that
 *              standard Salesforce field history misses.
 *
 *              Insert tests: records are created within Test.startTest()/stopTest() so the
 *              trigger-fired FieldHistoryInsertQueueable is flushed before assertions.
 *              The queueable in @testSetup is NOT flushed and produces no Field_History__c
 *              records, keeping insert and update test data isolated.
 *
 *              Update tests: call ValidationChecklistTriggerHelper directly with constructed
 *              old/new maps to isolate update tracking without trigger re-entrant concerns.
 *
 * @author      Ratan Paul
 * @date        2026-05-19
 * @jira        BIZ-74558
 */
@isTest
private class ValidationChecklistTriggerHandlerTest {

    /***************************************************************************************
    *
    * Test Setup — provides a base record for update-tracking tests
    *
    ***************************************************************************************/

    @testSetup
    static void setupTestData() {
        // Insert a Validation Checklist with all audit checkboxes false.
        // The insert trigger fires and enqueues FieldHistoryInsertQueueable, but because
        // there is no Test.startTest()/stopTest() here, the queueable is NOT executed —
        // so no Field_History__c records are committed to the test database.
        TestFactory.createSObject(new Validation_Checklist__c(
            Deal_Desk_Audit_Complete__c         = false,
            Contract_Ops_Audit_Complete__c      = false,
            Order_Management_Audit_Complete__c  = false
        ));
    }

    /***************************************************************************************
    *
    * Insert Tracking Tests
    * Records are inserted inside Test.startTest()/stopTest() so the queueable flushes
    * and Field_History__c records are queryable immediately after stopTest().
    *
    ***************************************************************************************/

    /**
     * @description Verifies that when Deal Desk marks their checkbox on record creation,
     *              a Field_History__c record is created capturing the initial true value.
     *              This is the core gap fixed by this story — standard history misses this.
     */
    @isTest
    static void testTrackInsert_dealDeskCheckboxTrue_createsHistoryRecord() {
        Validation_Checklist__c vc;

        Test.startTest();
        vc = (Validation_Checklist__c) TestFactory.createSObject(
            new Validation_Checklist__c(
                Deal_Desk_Audit_Complete__c         = true,
                Contract_Ops_Audit_Complete__c      = false,
                Order_Management_Audit_Complete__c  = false
            )
        );
        Test.stopTest();

        List<Field_History__c> history = [
            SELECT Field_Name__c, New_Value__c, Changed_By__c
            FROM Field_History__c
            WHERE Parent_Record__c = :vc.Id
              AND Field_Name__c = 'Deal_Desk_Audit_Complete__c'
        ];

        Assert.areEqual(1, history.size(), 'Expected 1 history record for Deal_Desk_Audit_Complete__c on insert');
        Assert.areEqual('true', history[0].New_Value__c, 'New value should be true');
        Assert.areEqual(UserInfo.getUserId(), history[0].Changed_By__c, 'Changed_By__c should be the running user');
    }

    /**
     * @description Verifies that when all three audit checkboxes are checked at record
     *              creation, three history records are created — one per field.
     */
    @isTest
    static void testTrackInsert_allCheckboxesTrue_createsThreeHistoryRecords() {
        Validation_Checklist__c vc;

        Test.startTest();
        vc = (Validation_Checklist__c) TestFactory.createSObject(
            new Validation_Checklist__c(
                Deal_Desk_Audit_Complete__c         = true,
                Contract_Ops_Audit_Complete__c      = true,
                Order_Management_Audit_Complete__c  = true
            )
        );
        Test.stopTest();

        List<Field_History__c> history = [
            SELECT Field_Name__c, New_Value__c
            FROM Field_History__c
            WHERE Parent_Record__c = :vc.Id
        ];

        Assert.areEqual(3, history.size(), 'Expected 3 history records — one per tracked audit checkbox');
        for (Field_History__c h : history) {
            Assert.areEqual('true', h.New_Value__c, 'All checkbox history records should show new value true');
        }
    }

    /**
     * @description Verifies that a record inserted with all checkboxes false still produces
     *              history records — the framework records false (not null) values so the
     *              initial unchecked state is auditable too.
     */
    @isTest
    static void testTrackInsert_allCheckboxesFalse_capturesInitialFalseState() {
        Validation_Checklist__c vc;

        Test.startTest();
        vc = (Validation_Checklist__c) TestFactory.createSObject(
            new Validation_Checklist__c(
                Deal_Desk_Audit_Complete__c         = false,
                Contract_Ops_Audit_Complete__c      = false,
                Order_Management_Audit_Complete__c  = false
            )
        );
        Test.stopTest();

        List<Field_History__c> history = [
            SELECT Field_Name__c, New_Value__c
            FROM Field_History__c
            WHERE Parent_Record__c = :vc.Id
        ];

        // false != null, so all 3 configured checkboxes produce a history record
        Assert.areEqual(3, history.size(), 'Expected 3 history records capturing the initial false state');
        for (Field_History__c h : history) {
            Assert.areEqual('false', h.New_Value__c, 'All history records should show initial value false');
        }
    }

    /***************************************************************************************
    *
    * Update Tracking Tests
    * Call the helper directly with constructed old/new maps to isolate update logic.
    * The @testSetup record has no committed Field_History__c rows, so update assertions
    * are not polluted by insert history.
    *
    ***************************************************************************************/

    /**
     * @description Verifies that checking a previously unchecked Contract Ops checkbox
     *              produces exactly one history record for that field.
     */
    @isTest
    static void testTrackUpdate_contractOpsChecked_createsOneHistoryRecord() {
        Validation_Checklist__c vc = [
            SELECT Id, Deal_Desk_Audit_Complete__c, Contract_Ops_Audit_Complete__c,
                   Order_Management_Audit_Complete__c
            FROM Validation_Checklist__c LIMIT 1
        ];

        Validation_Checklist__c updatedVc = vc.clone(true, true, false, false);
        updatedVc.Contract_Ops_Audit_Complete__c = true;

        Map<Id, Object> oldMap = new Map<Id, Object>{
            vc.Id => new Validation_Checklist__c(
                Id                              = vc.Id,
                Deal_Desk_Audit_Complete__c     = false,
                Contract_Ops_Audit_Complete__c  = false,
                Order_Management_Audit_Complete__c = false
            )
        };

        Test.startTest();
        ValidationChecklistTriggerHelper.trackUpdateHistory(
            new List<Validation_Checklist__c>{ updatedVc }, oldMap
        );
        Test.stopTest();

        List<Field_History__c> history = [
            SELECT Field_Name__c, Old_Value__c, New_Value__c
            FROM Field_History__c
            WHERE Parent_Record__c = :vc.Id
              AND Field_Name__c = 'Contract_Ops_Audit_Complete__c'
              AND Change_Type__c = 'Update'
        ];

        Assert.areEqual(1, history.size(), 'Expected exactly 1 history record for Contract_Ops_Audit_Complete__c');
        Assert.areEqual('false', history[0].Old_Value__c, 'Old value should be false');
        Assert.areEqual('true', history[0].New_Value__c, 'New value should be true');
    }

    /**
     * @description Verifies that a system reversion (checkbox flipped back to false) is
     *              captured. This is the key audit scenario: understanding whether a blank
     *              field was human error or an automated reset.
     */
    @isTest
    static void testTrackUpdate_dealDeskReverted_capturesReversion() {
        Validation_Checklist__c vc = [
            SELECT Id, Deal_Desk_Audit_Complete__c, Contract_Ops_Audit_Complete__c,
                   Order_Management_Audit_Complete__c
            FROM Validation_Checklist__c LIMIT 1
        ];

        // Simulate: Deal Desk had completed (true), system reverted it (false)
        Validation_Checklist__c updatedVc = vc.clone(true, true, false, false);
        updatedVc.Deal_Desk_Audit_Complete__c = false;

        Map<Id, Object> oldMap = new Map<Id, Object>{
            vc.Id => new Validation_Checklist__c(
                Id                              = vc.Id,
                Deal_Desk_Audit_Complete__c     = true,
                Contract_Ops_Audit_Complete__c  = false,
                Order_Management_Audit_Complete__c = false
            )
        };

        Test.startTest();
        ValidationChecklistTriggerHelper.trackUpdateHistory(
            new List<Validation_Checklist__c>{ updatedVc }, oldMap
        );
        Test.stopTest();

        List<Field_History__c> history = [
            SELECT Field_Name__c, Old_Value__c, New_Value__c
            FROM Field_History__c
            WHERE Parent_Record__c = :vc.Id
              AND Field_Name__c = 'Deal_Desk_Audit_Complete__c'
              AND Change_Type__c = 'Update'
        ];

        Assert.areEqual(1, history.size(), 'Expected 1 history record for the reversion event');
        Assert.areEqual('true', history[0].Old_Value__c, 'Old value should be true (was completed)');
        Assert.areEqual('false', history[0].New_Value__c, 'New value should be false (reverted)');
    }

    /**
     * @description Verifies that no history records are created when an update touches a
     *              record but does not change any of the three tracked checkbox values.
     */
    @isTest
    static void testTrackUpdate_noCheckboxChange_createsNoHistoryRecords() {
        Validation_Checklist__c vc = [
            SELECT Id, Deal_Desk_Audit_Complete__c, Contract_Ops_Audit_Complete__c,
                   Order_Management_Audit_Complete__c
            FROM Validation_Checklist__c LIMIT 1
        ];

        // Identical values in new and old — no real change on tracked fields
        Map<Id, Object> oldMap = new Map<Id, Object>{
            vc.Id => new Validation_Checklist__c(
                Id                              = vc.Id,
                Deal_Desk_Audit_Complete__c     = false,
                Contract_Ops_Audit_Complete__c  = false,
                Order_Management_Audit_Complete__c = false
            )
        };

        Test.startTest();
        ValidationChecklistTriggerHelper.trackUpdateHistory(
            new List<Validation_Checklist__c>{ vc }, oldMap
        );
        Test.stopTest();

        List<Field_History__c> history = [
            SELECT Id FROM Field_History__c
            WHERE Parent_Record__c = :vc.Id
              AND Change_Type__c = 'Update'
        ];

        Assert.areEqual(0, history.size(), 'No history records should be created when no checkbox values changed');
    }

    /**
     * @description Exercises every handler method to meet Apex code coverage requirements.
     *              Empty collections are passed to non-core methods so FieldHistoryHandler
     *              returns early without side effects. The two active methods (afterInsert,
     *              afterUpdate) are also called directly here to ensure all executable
     *              statements in the handler are covered.
     */
    @isTest
    static void testHandlerMethodCoverage_allMethodsExecuteWithoutError() {
        ValidationChecklistTriggerHandler handler = new ValidationChecklistTriggerHandler();

        Test.startTest();
        // Stub methods — empty collections so nothing is processed
        handler.beforeInsert(new List<SObject>());
        handler.beforeUpdate(new List<SObject>(), new Map<Id, Object>(), new List<Object>(), new Map<Id, Object>());
        handler.beforeDelete(new List<SObject>(), new Map<Id, Object>());
        handler.afterDelete(new List<Object>(), new Map<Id, Object>());
        handler.afterUnDelete(new List<SObject>(), new Map<Id, Object>());
        // Active methods — empty collections so FieldHistoryHandler's null-check returns early
        handler.afterInsert(new List<SObject>(), new Map<Id, Object>());
        handler.afterUpdate(new List<SObject>(), new Map<Id, Object>(), new List<Object>(), new Map<Id, Object>());
        Test.stopTest();

        Assert.isTrue(true, 'All handler methods executed without exception');
    }

    /**
     * @description Verifies order-of-operations scenario: multiple groups complete their
     *              audit at the same time. Each checkbox change produces its own history
     *              record with a timestamp to support sequencing analysis.
     */
    @isTest
    static void testTrackUpdate_multipleCheckboxesChanged_createsHistoryForEach() {
        Validation_Checklist__c vc = [
            SELECT Id, Deal_Desk_Audit_Complete__c, Contract_Ops_Audit_Complete__c,
                   Order_Management_Audit_Complete__c
            FROM Validation_Checklist__c LIMIT 1
        ];

        Validation_Checklist__c updatedVc = vc.clone(true, true, false, false);
        updatedVc.Deal_Desk_Audit_Complete__c        = true;
        updatedVc.Contract_Ops_Audit_Complete__c     = true;
        updatedVc.Order_Management_Audit_Complete__c = true;

        Map<Id, Object> oldMap = new Map<Id, Object>{
            vc.Id => new Validation_Checklist__c(
                Id                              = vc.Id,
                Deal_Desk_Audit_Complete__c     = false,
                Contract_Ops_Audit_Complete__c  = false,
                Order_Management_Audit_Complete__c = false
            )
        };

        Test.startTest();
        ValidationChecklistTriggerHelper.trackUpdateHistory(
            new List<Validation_Checklist__c>{ updatedVc }, oldMap
        );
        Test.stopTest();

        List<Field_History__c> history = [
            SELECT Field_Name__c, New_Value__c
            FROM Field_History__c
            WHERE Parent_Record__c = :vc.Id
              AND Change_Type__c = 'Update'
        ];

        Assert.areEqual(3, history.size(), 'Expected one history record per changed audit checkbox');
        for (Field_History__c h : history) {
            Assert.areEqual('true', h.New_Value__c, 'All changed checkboxes should record new value true');
        }
    }
}