/**
 * @description  Test class for OpportunityBulkUpdateController.
 * @author       Yousef Alamin
 * @date         2026-03-17
 * @jira         BIZ-80919
 */
@isTest
private class OpportunityBulkUpdateControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = (Account) TestFactory.createSObject(new Account(Name = 'Test Account'));

        TestFactory.createSObject(new Opportunity(
            Name        = 'Renewal Opp Test',
            AccountId   = acc.Id,
            StageName   = 'Qualify',
            CloseDate   = Date.today().addDays(30),
            Deal_Type__c = 'Renewal'
        ));

        TestFactory.createSObject(new Opportunity(
            Name        = 'MultiYear Opp Test',
            AccountId   = acc.Id,
            StageName   = 'Qualify',
            CloseDate   = Date.today().addDays(60),
            Deal_Type__c = 'NextYear_MultiYear'
        ));
    }

    // =========================================================================
    // Query Tests
    // =========================================================================

    @isTest
    static void testGetStageValues() {
        List<String> stages = OpportunityBulkUpdateController.getStageValues();
        System.assert(!stages.isEmpty(), 'Should return at least one stage value');
    }

    @isTest
    static void testGetOpportunities_AllFilters() {
        List<Opportunity> results = OpportunityBulkUpdateController.getOpportunities(
            Date.today().addDays(-1),
            DateTime.now().addDays(-30),
            new List<String>{ 'Renewal', 'NextYear_MultiYear' },
            'Qualify',
            'Test',
            null
        );
        System.assertEquals(2, results.size(), 'Should return 2 opportunities');
    }

    @isTest
    static void testGetOpportunities_ById() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Deal_Type__c = 'Renewal' LIMIT 1];
        List<Opportunity> results = OpportunityBulkUpdateController.getOpportunities(
            null, null, null, null, null, opp.Id
        );
        System.assertEquals(1, results.size(), 'Should return 1 opportunity by Id');
    }

    @isTest
    static void testGetOpportunities_InvalidDealType() {
        List<Opportunity> results = OpportunityBulkUpdateController.getOpportunities(
            null, null, new List<String>{ 'InvalidType' }, null, null, null
        );
        // Falls back to allowed types
        System.assert(results.size() >= 2, 'Should fall back to all allowed deal types');
    }

    // =========================================================================
    // Save Tests
    // =========================================================================

    @isTest
    static void testSaveOpportunities() {
        Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Deal_Type__c = 'Renewal' LIMIT 1];
        String jsonStr = '[{"Id":"' + opp.Id + '","StageName":"Pending Closure"}]';

        Test.startTest();
        List<OpportunityBulkUpdateController.SaveResult> results =
            OpportunityBulkUpdateController.saveOpportunities(jsonStr);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one SaveResult');
        System.assert(results[0].success, 'Record should have saved successfully');
        System.assertEquals(null, results[0].errorMessage, 'No error message expected on success');

        Opportunity updated = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Pending Closure', updated.StageName, 'Stage should be updated');
    }

    @isTest
    static void testSaveOpportunities_BlankJson() {
        List<OpportunityBulkUpdateController.SaveResult> r1 =
            OpportunityBulkUpdateController.saveOpportunities('');
        List<OpportunityBulkUpdateController.SaveResult> r2 =
            OpportunityBulkUpdateController.saveOpportunities(null);

        System.assertEquals(0, r1.size(), 'Blank JSON should return empty list');
        System.assertEquals(0, r2.size(), 'Null JSON should return empty list');
    }

    @isTest
    static void testSaveOpportunities_IgnoresDisallowedFields() {
        Opportunity opp = [SELECT Id, Name FROM Opportunity WHERE Deal_Type__c = 'Renewal' LIMIT 1];
        String originalName = opp.Name;

        String jsonStr = '[{"Id":"' + opp.Id + '","Name":"Hacked Name"}]';

        Test.startTest();
        OpportunityBulkUpdateController.saveOpportunities(jsonStr);
        Test.stopTest();

        Opportunity unchanged = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(originalName, unchanged.Name, 'Name should not change');
    }

    @isTest
    static void testSaveOpportunities_ExceedsRecordLimit() {
        // Build a JSON payload with 201 entries (fake IDs — only testing the cap check)
        List<String> entries = new List<String>();
        for (Integer i = 0; i < 201; i++) {
            entries.add('{"Id":"006000000000' + String.valueOf(i).leftPad(3, '0') + 'AAA","StageName":"Qualify"}');
        }
        String jsonStr = '[' + String.join(entries, ',') + ']';

        Test.startTest();
        try {
            OpportunityBulkUpdateController.saveOpportunities(jsonStr);
            System.assert(false, 'Expected AuraHandledException for exceeding record limit');
        } catch (AuraHandledException ex) {
            System.assert(
                ex.getMessage().contains('200'),
                'Error message should reference the 200-record limit'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveOpportunities_RateLimit() {
        // Simulate a save that just happened by inserting a rate limit record with now()
        BulkUpdateRateLimit__c rl = new BulkUpdateRateLimit__c(
            SetupOwnerId      = UserInfo.getUserId(),
            Last_Bulk_Save__c = DateTime.now()
        );
        insert rl;

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Deal_Type__c = 'Renewal' LIMIT 1];
        String jsonStr = '[{"Id":"' + opp.Id + '","StageName":"Qualify"}]';

        Test.startTest();
        try {
            OpportunityBulkUpdateController.saveOpportunities(jsonStr);
            System.assert(false, 'Expected AuraHandledException for rate limit');
        } catch (AuraHandledException ex) {
            System.assert(
                ex.getMessage().contains('Rate limit'),
                'Error message should mention rate limit'
            );
        }
        Test.stopTest();
    }
}