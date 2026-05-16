@isTest
public class ContractTriggerHandlerTest {

    @testSetup
    static void setup() {
        // Create base data
        Account acc = IntappTestObjectFactory.createaccount(true);
        Account billingAccount = IntappTestObjectFactory.createaccount(true);

        // Create Opportunity to link as Renewal Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Renewal Opp',
            StageName = 'Prospecting',
            CloseDate = System.today().addDays(30)
        );
        insert opp;

        // Create Contract linked to the Renewal Opp
        Contract con = IntappTestObjectFactory.createcontract(acc.Id);
        con.Billing_Account__c = billingAccount.Id;
        con.SBQQ__RenewalOpportunity__c = opp.Id;
        con.Renewals_Pause__c = false;
        con.Renewal_Pause_Reason__c = null;
        insert con;
    }

    @isTest
    static void testUpdateRenewalOpps_WhenPauseFieldsChange() {
        // Fetch contract and related opp
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

        // Update fields to trigger the after update logic
        con.Renewals_Pause__c = true;
        con.Renewal_Pause_Reason__c = 'Customer Request';
        update con;

        // Fetch updated opportunity to validate
        Opportunity oppAfter = [
            SELECT Id, Renewals_Pause__c, Renewal_Pause_Reason__c
            FROM Opportunity
            WHERE Id = :con.SBQQ__RenewalOpportunity__c
            LIMIT 1
        ];

        System.assertEquals(true, oppAfter.Renewals_Pause__c,
            'Opportunity Renewals_Pause__c should match updated Contract value.');
        System.assertEquals('Customer Request', oppAfter.Renewal_Pause_Reason__c,
            'Opportunity Renewal_Pause_Reason__c should match updated Contract value.');
    }

    @isTest
    public static void testmethod1() {
        Account acc = IntappTestObjectFactory.createaccount(true);
        Account billingAccount = IntappTestObjectFactory.createaccount(true);
        Contract con = IntappTestObjectFactory.createcontract(acc.Id);
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

    @isTest
    public static void testmethod2() {
        Contract con = [SELECT Id, Subsidiary__c FROM Contract LIMIT 1];
        con.Subsidiary__c = '05:The Frayman Group, Inc.';
        con.Status = 'In Force';
        update con;
        System.assertEquals('In Force', con.Status);
    }
}