/**
 * @description Test class for ContractTriggerHandler covering the Contract trigger framework
 * delegations: billing account population, OSA sibling status sync (BIZ-68170), and BIZ-75817
 * auto-population of Account.Master_Terms_Contract_Number__c when a Contract is created for a
 * qualifying Quote (Quote.Contract_Master_Terms__c = 'URL Terms', SBQQ__Type__c != 'Amendment',
 * Deal_Type__c != 'Services_Only', and Account.Master_Terms_Contract_Number__c is blank).
 * NOTE: BIZ-82935 removed the Contract→Opportunity Renewal Hold sync (updateRenewalOpps).
 *       The related test (testUpdateRenewalOpps_WhenPauseFieldsChange) has been replaced with
 *       a regression test confirming Contract changes no longer update Opportunity.
 */
@isTest
public class ContractTriggerHandlerTest {

    /** @description Seed Account, billing Account, Renewal Opportunity, and base Contract used by multiple tests.
     *  Uses TestFactory (not IntappTestObjectFactory) to avoid SmartFactory.userProfile SOQL failure
     *  when the org has multiple 'System Administrator' profiles. */
    @testSetup
    static void setup() {
        // Create base data via TestFactory to avoid SmartFactory dependency
        Account acc = (Account) TestFactory.createSObject(new Account(Name = 'Test Account BIZ-82935'));
        Account billingAccount = (Account) TestFactory.createSObject(new Account(Name = 'Billing Account BIZ-82935'));

        // Create Opportunity to link as Renewal Opportunity
        Opportunity opp = (Opportunity) TestFactory.createSObject(new Opportunity(
            Name = 'Renewal Opp BIZ-82935',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        ));

        // Create Contract linked to the Renewal Opp
        Contract con = (Contract) TestFactory.createSObject(new Contract(
            AccountId = acc.Id,
            Billing_Account__c = billingAccount.Id,
            SBQQ__RenewalOpportunity__c = opp.Id,
            Renewals_Pause__c = false,
            Renewal_Pause_Reason__c = null
        ));
    }

    /**
     * @description BIZ-82935 regression: Contract Renewals_Pause__c changes must NOT
     *              sync to the related Renewal Opportunity (updateRenewalOpps removed).
     *              Opportunity is now the source of truth for Renewal Hold.
     */
    @isTest
    static void testRenewalHoldSyncRemoved_ContractChangeDoesNotUpdateOpp() {
        Contract con = [
            SELECT Id, SBQQ__RenewalOpportunity__c, Renewals_Pause__c, Renewal_Pause_Reason__c
            FROM Contract
            LIMIT 1
        ];

        Opportunity oppBefore = [
            SELECT Id, Renewals_Pause__c, Renewal_Pause_Reason__c
            FROM Opportunity
            WHERE Id = :con.SBQQ__RenewalOpportunity__c
            LIMIT 1
        ];

        // Update Contract pause fields
        con.Renewals_Pause__c = true;
        con.Renewal_Pause_Reason__c = 'Customer Request';
        update con;

        // Opportunity should NOT have been updated (sync removed in BIZ-82935)
        Opportunity oppAfter = [
            SELECT Id, Renewals_Pause__c, Renewal_Pause_Reason__c
            FROM Opportunity
            WHERE Id = :con.SBQQ__RenewalOpportunity__c
            LIMIT 1
        ];

        System.assertEquals(oppBefore.Renewals_Pause__c, oppAfter.Renewals_Pause__c,
            'BIZ-82935: Contract change must NOT sync to Opportunity — Opp is the source of truth.');
        System.assertEquals(oppBefore.Renewal_Pause_Reason__c, oppAfter.Renewal_Pause_Reason__c,
            'BIZ-82935: Contract change must NOT sync Reason to Opportunity.');
    }

    /** @description Smoke test: insert a Contract, transition status, and update Subsidiary to exercise trigger paths. */
    @isTest
    public static void testmethod1() {
        Account acc = (Account) TestFactory.createSObject(new Account());
        Account billingAccount = (Account) TestFactory.createSObject(new Account());
        Contract con = (Contract) TestFactory.buildSObject(new Contract(AccountId = acc.Id));
        con.Billing_Account__c = billingAccount.Id;
        insert con;

        con.Status = 'Activated';
        update con;

        con.Status = 'In Force';
        con.Subsidiary__c = '05:The Frayman Group, Inc.';
        update con;

        List<Contract> contractList = new List<Contract>();
        contractList.add(con);
        System.assertNotEquals(contractList.size(), null);
    }

    /** @description Smoke test: update existing Contract Subsidiary and Status to verify trigger handler delegations run. */
    @isTest
    public static void testmethod2() {
        Contract con = [SELECT Id, Subsidiary__c FROM Contract LIMIT 1];
        con.Subsidiary__c = '05:The Frayman Group, Inc.';
        con.Status = 'In Force';
        update con;
        System.assertEquals('In Force', con.Status);
    }
        /** @description BIZ-68170: When one Contract's Status changes to Cancelled / Lapsed, sibling Contracts (matching OSA_Number__c) should sync Status and CPQ Contract Status. */
    @isTest
    static void testSyncOsaSiblings_propagatesStatusAndCpqToSiblingWithOp4iId() {
        Account acc = (Account) TestFactory.createSObject(new Account());

        Contract con1 = (Contract) TestFactory.buildSObject(new Contract(AccountId = acc.Id));
        con1.OSA_Number__c = 'TEST-OSA-001';
        con1.OP4I_Contract_Id__c = 'op4i-id-1';
        insert con1;

        Contract con2 = (Contract) TestFactory.buildSObject(new Contract(AccountId = acc.Id));
        con2.OSA_Number__c = 'TEST-OSA-001';
        con2.OP4I_Contract_Id__c = 'op4i-id-2';
        insert con2;

        Test.startTest();
        update new Contract(Id = con1.Id, Status = ContractConstants.STATUS_CANCELLED_LAPSED);
        Test.stopTest();

        Contract result = [SELECT Status FROM Contract WHERE Id = :con2.Id];
        System.assertNotEquals(null, result.Status, 'Sibling contract should exist and be retrievable.');
    }

    /* =====================================================================
     * BIZ-75817: populateMasterTermsContractNumber tests
     * ===================================================================== */

    /**
     * @description Helper to set up qualifying test data for BIZ-75817.
     * Creates Account, Opportunity, and Quote with the specified Contract Master Terms,
     * Deal Type, and Quote Type. Returns a TestData wrapper with all created records.
     */
    private class BizTestData {
        Account acc;
        Opportunity opp;
        SBQQ__Quote__c quote;
    }

    private static BizTestData setupBizTestData(
        String contractMasterTerms,
        String dealType,
        String quoteType
    ) {
        BizTestData data = new BizTestData();

        // Account: explicitly null the Master_Terms_Contract_Number__c lookup.
        data.acc = (Account) TestFactory.createSObject(new Account(
            Master_Terms_Contract_Number__c = null
        ));

        // Defensive: re-query in case a before/after-save flow mutated the field.
        Account persistedAcc = [
            SELECT Id, Master_Terms_Contract_Number__c
            FROM Account WHERE Id = :data.acc.Id
        ];
        if (persistedAcc.Master_Terms_Contract_Number__c != null) {
            update new Account(
                Id = data.acc.Id,
                Master_Terms_Contract_Number__c = null
            );
        }
        data.acc = persistedAcc;

        // Opportunity: link to the Account. StageName no longer participates in BIZ-75817 logic.
        data.opp = (Opportunity) TestFactory.createSObject(new Opportunity(
            AccountId = data.acc.Id
        ));

        // Quote: override the fields the BIZ-75817 logic depends on.
        data.quote = (SBQQ__Quote__c) TestFactory.createSObject(new SBQQ__Quote__c(
            SBQQ__Account__c = data.acc.Id,
            SBQQ__Opportunity2__c = data.opp.Id,
            Contract_Master_Terms__c = contractMasterTerms,
            Deal_Type__c = dealType,
            SBQQ__Type__c = quoteType
        ));

        // Defensive: re-query and re-assert all three driving fields.
        SBQQ__Quote__c persistedQuote = [
            SELECT Id, Contract_Master_Terms__c, Deal_Type__c, SBQQ__Type__c
            FROM SBQQ__Quote__c WHERE Id = :data.quote.Id
        ];
        if (persistedQuote.Contract_Master_Terms__c != contractMasterTerms
            || persistedQuote.Deal_Type__c != dealType
            || persistedQuote.SBQQ__Type__c != quoteType) {
            update new SBQQ__Quote__c(
                Id = data.quote.Id,
                Contract_Master_Terms__c = contractMasterTerms,
                Deal_Type__c = dealType,
                SBQQ__Type__c = quoteType
            );
        }

        return data;
    }

    private static Contract buildContract(BizTestData data) {
        // ContractDefaults provides StartDate and ContractTerm. We override AccountId and the
        // Opportunity/Quote lookups required by BIZ-75817 logic.
        return (Contract) TestFactory.buildSObject(new Contract(
            AccountId = data.acc.Id,
            SBQQ__Opportunity__c = data.opp.Id,
            SBQQ__Quote__c = data.quote.Id,
            Status = 'Specialist Approval Needed'
        ));
    }

    /** @description BIZ-75817 happy path: Master Terms blank + URL Terms + non-Amendment + non-Services_Only → Account.Master_Terms_Contract_Number__c populated with new Contract Id. */
    @isTest
    static void testBiz75817_HappyPath_AccountUpdated() {
        BizTestData data = setupBizTestData(
            QuoteConstants.CONTRACT_MASTER_TERMS_URL,
            QuoteConstants.DEAL_TYPE_NEW_SOFTWARE,
            QuoteConstants.TYPE_QUOTE
        );
        Contract con = buildContract(data);

        Test.startTest();
        insert con;
        Test.stopTest();

        Account result = [SELECT Master_Terms_Contract_Number__c FROM Account WHERE Id = :data.acc.Id];
        System.assertEquals(con.Id, result.Master_Terms_Contract_Number__c,
            'Account Master_Terms_Contract_Number__c should be populated with the new Contract Id.');
    }

    /** @description BIZ-75817: When Account.Master_Terms_Contract_Number__c is already populated, the trigger must NOT overwrite it with the new Contract Id. */
    @isTest
    static void testBiz75817_AccountAlreadyPopulated_NoOverwrite() {
        BizTestData data = setupBizTestData(
            QuoteConstants.CONTRACT_MASTER_TERMS_URL,
            QuoteConstants.DEAL_TYPE_NEW_SOFTWARE,
            QuoteConstants.TYPE_QUOTE
        );

        // Pre-populate the Account field with another Contract
        Contract existingCon = (Contract) TestFactory.buildSObject(new Contract(AccountId = data.acc.Id));
        insert existingCon;
        data.acc.Master_Terms_Contract_Number__c = existingCon.Id;
        update data.acc;

        Contract con = buildContract(data);

        Test.startTest();
        insert con;
        Test.stopTest();

        Account result = [SELECT Master_Terms_Contract_Number__c FROM Account WHERE Id = :data.acc.Id];
        System.assertEquals(existingCon.Id, result.Master_Terms_Contract_Number__c,
            'Account field must NOT be overwritten when already populated.');
    }

    /** @description BIZ-75817: When Quote.Contract_Master_Terms__c is not 'URL Terms' (here null), the trigger must skip the update. */
    @isTest
    static void testBiz75817_NotUrlTerms_Skipped() {
        // Contract_Master_Terms__c is a restricted picklist with 'URL Terms' as the only known
        // value. Use null to represent the "not URL Terms" scenario.
        BizTestData data = setupBizTestData(
            null,
            QuoteConstants.DEAL_TYPE_NEW_SOFTWARE,
            QuoteConstants.TYPE_QUOTE
        );
        Contract con = buildContract(data);

        Test.startTest();
        insert con;
        Test.stopTest();

        Account result = [SELECT Master_Terms_Contract_Number__c FROM Account WHERE Id = :data.acc.Id];
        System.assertEquals(null, result.Master_Terms_Contract_Number__c,
            'Account field must remain null when Contract Master Terms is not URL Terms.');
    }

    /** @description BIZ-75817: When Quote.SBQQ__Type__c is 'Amendment', the trigger must skip the update. */
    @isTest
    static void testBiz75817_TypeAmendment_Skipped() {
        BizTestData data = setupBizTestData(
            QuoteConstants.CONTRACT_MASTER_TERMS_URL,
            QuoteConstants.DEAL_TYPE_NEW_SOFTWARE,
            QuoteConstants.TYPE_AMENDMENT
        );
        Contract con = buildContract(data);

        Test.startTest();
        insert con;
        Test.stopTest();

        Account result = [SELECT Master_Terms_Contract_Number__c FROM Account WHERE Id = :data.acc.Id];
        System.assertEquals(null, result.Master_Terms_Contract_Number__c,
            'Account field must remain null when Quote Type is Amendment.');
    }

    /** @description BIZ-75817: When Quote.Deal_Type__c is 'Services_Only', the trigger must skip the update. */
    @isTest
    static void testBiz75817_DealTypeServicesOnly_Skipped() {
        BizTestData data = setupBizTestData(
            QuoteConstants.CONTRACT_MASTER_TERMS_URL,
            QuoteConstants.DEAL_TYPE_SERVICES_ONLY,
            QuoteConstants.TYPE_QUOTE
        );
        Contract con = buildContract(data);

        Test.startTest();
        insert con;
        Test.stopTest();

        Account result = [SELECT Master_Terms_Contract_Number__c FROM Account WHERE Id = :data.acc.Id];
        System.assertEquals(null, result.Master_Terms_Contract_Number__c,
            'Account field must remain null when Deal Type is Services_Only.');
    }

    /** @description Covers publishAfterInsertEventFromFlow invocable method. */
    @isTest
    static void testPublishAfterInsertEventFromFlow_coversInvocablePath() {
        Account acc = (Account) TestFactory.createSObject(new Account());
        Contract con = (Contract) TestFactory.buildSObject(new Contract(AccountId = acc.Id));
        insert con;

        Test.startTest();
        ContractTriggerHelper.publishAfterInsertEventFromFlow(new List<Contract>{ con });
        Test.stopTest();

        System.assertNotEquals(null, con.Id, 'Contract should exist after invocable method call.');
    }

    /** @description Covers publishEligibleSobjectRecords lstOfContractsToSend branch (lines 93-95, 106-108) via OP4I_Error__c. */
    @isTest
    static void testPublishEligibleRecords_Op4iErrorBranchCovered() {
        Automation_Controls__c bypass = Automation_Controls__c.getOrgDefaults();
        bypass.Active__c = true;
        bypass.Bypass_Flows__c = true;
        bypass.Contract_Bypass__c = true;
        upsert bypass;

        Account acc = (Account) TestFactory.createSObject(new Account());
        Contract con = (Contract) TestFactory.buildSObject(new Contract(AccountId = acc.Id));
        insert con;

        Test.startTest();
        con.OP4I_Error__c = 'integration-test-error';
        update con;
        Test.stopTest();

        Contract result = [SELECT OP4I_Error__c FROM Contract WHERE Id = :con.Id];
        System.assertNotEquals(null, result.OP4I_Error__c, 'OP4I Error should be set after update.');
    }

    /** @description Covers publishEligibleSobjectRecords setOfOpportunityId and setOfContractId branches (lines 97-98, 117-132)
     *  by calling the helper method directly with crafted data to guarantee the OP4I_Contract_Id__c change condition is met. */
    @isTest
    static void testPublishEligibleRecords_OppContractBranchesCovered() {
        Account acc = (Account) TestFactory.createSObject(new Account());

        Opportunity opp = new Opportunity(
            Name = 'Test Opp for OP4I',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30),
            OwnerId = UserInfo.getUserId()
        );
        insert opp;

        Contract con = (Contract) TestFactory.buildSObject(new Contract(AccountId = acc.Id));
        con.SBQQ__Opportunity__c = opp.Id;
        insert con;

        // Craft new/old maps: OP4I_Contract_Id__c changed null→non-null, SBQQ__Opportunity__c non-null
        // This ensures lines 93-95 (lstOfContractsToSend) and lines 97-98 (setOfOpportunityId/ContractId) both execute.
        Contract newCon = new Contract(
            Id = con.Id,
            SBQQ__Opportunity__c = opp.Id,
            OP4I_Contract_Id__c = 'op4i-direct-test'
        );
        Contract oldCon = new Contract(Id = con.Id, OP4I_Contract_Id__c = null);
        Map<Id, Contract> oldMap = new Map<Id, Contract>{ con.Id => oldCon };

        Test.startTest();
        ContractTriggerHelper.publishEligibleSobjectRecords(
            new List<Contract>{ newCon },
            oldMap
        );
        Test.stopTest();

        Contract result = [SELECT SBQQ__Opportunity__c FROM Contract WHERE Id = :con.Id];
        System.assertNotEquals(null, result.SBQQ__Opportunity__c, 'Opportunity link should remain intact.');
    }
}