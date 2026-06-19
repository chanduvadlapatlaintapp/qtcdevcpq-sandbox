/**
 * @description Test class for ApprovalTriggerHandler and ApprovalTriggerHelper.
 *              Covers the trigger framework migration and new timestamp stamping logic.
 * @author      Business Applications
 * @date        2026-05-15
 * @jira        BIZ-73147
 **/
@IsTest
public class ApprovalTriggerHandlerTest {

    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/

    @TestSetup
    static void setup() {
        Account acc = (Account) TestFactory.createSObject(new Account());

        Opportunity opp = (Opportunity) TestFactory.createSObject(
            new Opportunity(AccountId = acc.Id)
        );

        TestFactory.createSObject(new SBQQ__Quote__c(
            SBQQ__Account__c      = acc.Id,
            SBQQ__Opportunity2__c = opp.Id
        ));
    }

    /***********************************************************************************************
    *
    * Helper
    *
    ***********************************************************************************************/

    private static SBAA__Approval__c buildApproval(String status) {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        return new SBAA__Approval__c(
            Quote__c              = quote.Id,
            sbaa__RecordField__c  = 'Quote__c',
            sbaa__ApprovalStep__c = 1,
            sbaa__Status__c       = status
        );
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/

    /**
     * @description Insert with status Requested — Approval_Requested__c should be stamped.
     **/
    @IsTest
    static void testRequestedTimestampOnInsert() {
        SBAA__Approval__c approval = buildApproval(ApprovalConstants.STATUS_REQUESTED);

        Test.startTest();
        TestFactory.createSObject(approval);
        Test.stopTest();

        approval = [SELECT Approval_Requested__c, Approval_Received__c FROM SBAA__Approval__c WHERE Id = :approval.Id];
        System.assertNotEquals(null, approval.Approval_Requested__c, 'Approval_Requested__c should be stamped on insert with status Requested');
        System.assertEquals(null, approval.Approval_Received__c, 'Approval_Received__c should not be set on insert');
    }

    /**
     * @description Insert with status Assigned — neither timestamp should be stamped.
     **/
    @IsTest
    static void testNoTimestampOnInsertWithAssignedStatus() {
        SBAA__Approval__c approval = buildApproval(ApprovalConstants.STATUS_ASSIGNED);

        Test.startTest();
        TestFactory.createSObject(approval);
        Test.stopTest();

        approval = [SELECT Approval_Requested__c, Approval_Received__c FROM SBAA__Approval__c WHERE Id = :approval.Id];
        System.assertEquals(null, approval.Approval_Requested__c, 'Approval_Requested__c should not be set when status is Assigned');
        System.assertEquals(null, approval.Approval_Received__c, 'Approval_Received__c should not be set when status is Assigned');
    }

    /**
     * @description Status updated to Requested — Approval_Requested__c should be stamped.
     **/
    @IsTest
    static void testRequestedTimestampOnStatusChange() {
        SBAA__Approval__c approval = buildApproval(ApprovalConstants.STATUS_ASSIGNED);
        TestFactory.createSObject(approval);

        Test.startTest();
        approval.sbaa__Status__c = ApprovalConstants.STATUS_REQUESTED;
        update approval;
        Test.stopTest();

        approval = [SELECT Approval_Requested__c FROM SBAA__Approval__c WHERE Id = :approval.Id];
        System.assertNotEquals(null, approval.Approval_Requested__c, 'Approval_Requested__c should be stamped when status changes to Requested');
    }

    /**
     * @description Status updated to Approved — Approval_Received__c should be stamped.
     **/
    @IsTest
    static void testReceivedTimestampOnApproved() {
        SBAA__Approval__c approval = buildApproval(ApprovalConstants.STATUS_REQUESTED);
        TestFactory.createSObject(approval);

        Test.startTest();
        approval.sbaa__Status__c = ApprovalConstants.STATUS_APPROVED;
        update approval;
        Test.stopTest();

        approval = [SELECT Approval_Received__c FROM SBAA__Approval__c WHERE Id = :approval.Id];
        System.assertNotEquals(null, approval.Approval_Received__c, 'Approval_Received__c should be stamped when status changes to Approved');
    }

    /**
     * @description Unrelated field update — neither timestamp should be affected.
     **/
    @IsTest
    static void testNoTimestampOnUnrelatedUpdate() {
        SBAA__Approval__c approval = buildApproval(ApprovalConstants.STATUS_ASSIGNED);
        TestFactory.createSObject(approval);

        Test.startTest();
        approval.sbaa__CommentsLong__c = 'Updated comment';
        update approval;
        Test.stopTest();

        approval = [SELECT Approval_Requested__c, Approval_Received__c FROM SBAA__Approval__c WHERE Id = :approval.Id];
        System.assertEquals(null, approval.Approval_Requested__c, 'Approval_Requested__c should not be set on unrelated update');
        System.assertEquals(null, approval.Approval_Received__c, 'Approval_Received__c should not be set on unrelated update');
    }
}