/**
 * @author : Sahal Mohamed
 * @date : 02/11/2025
 * @description : Utility class for plucking fields from a list
 */
@isTest
public without sharing class PluckTest {

    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    /**
     * @description Test Setup
     */
    @TestSetup
    private static void testSetup () {

        List<Account> accts = 
            (List<Account>)TestFactory.createSObjectList(
                new Account(), 3);

        // to fill in lookup field
        accts[0].ParentId = accts[1].Id;
        update accts[0];

        TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opp',
                AccountId = accts[0].Id
            ), 2
        );
    }

    /**********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/

    /**
     * @description tests the record id extract
     */
    @IsTest
    public static void extractRecordIds () {

        List<Account> accts = new List<Account>([
            SELECT Id, Name, ParentId 
            FROM Account ]);

        Test.startTest();

            Set<Id> extractedIds = Pluck.ids(accts);

        Test.stopTest();

        System.assert( extractedIds.size() == accts.size(),
            'Uh oh, it looks like the extract of ids did not return the expected result.');
    }

    /**
     * @description tests the id extract on a lookup field, extracted using a Schema.sObjectField
     */
    @IsTest
    public static void extractIdsSchema () {

        List<Account> accts = new List<Account>([
            SELECT Id, Name, ParentId 
            FROM Account ]);

        Test.startTest();

            Set<Id> extractedIds = Pluck.ids(Account.ParentId, accts);

        Test.stopTest();

        System.assert( extractedIds.size() > 0,
            'Uh oh, it looks like the extract of ids did not return the expected result.');
    }

    /**
     * @description tests the id extract on a lookup field, extracted using a field api name as a string
     */
    @IsTest
    public static void extractIdsString () {

        List<Account> accts = new List<Account>([
            SELECT Id, Name, ParentId 
            FROM Account ]);

        Test.startTest();

            Set<Id> extractedIds = Pluck.ids('ParentId', accts);

        Test.stopTest();

        System.assert( extractedIds.size() > 0,
            'Uh oh, it looks like the extract of ids did not return the expected result.');
    }

    /**
     * @description tests the string extract on a text field, extracted using a Schema.sObjectField
     */
    @IsTest
    public static void extractStringsSchema () {

        List<Account> accts = new List<Account>([
            SELECT Id, Name, ParentId 
            FROM Account ]);

        Test.startTest();

            Set<String> extractedStrings = Pluck.strings(Account.Name, accts);

        Test.stopTest();

        System.assert( extractedStrings.size() > 0,
            'Uh oh, it looks like the extract of strings did not return the expected result.');
    }

    /**
     * @description tests the string extract on a text field, extracted using a field api name as a string
     */
    @IsTest
    public static void extractStringsString () {

        List<Account> accts = new List<Account>([
            SELECT Id, Name, ParentId 
            FROM Account ]);

        Test.startTest();

            Set<String> extractedStrings = Pluck.strings('Name', accts);

        Test.stopTest();

        System.assert( extractedStrings.size() > 0,
            'Uh oh, it looks like the extract of strings did not return the expected result.');
    }

    /**
     * @description tests the values extract on a random field, extracted using a Schema.sObjectField
     */
    @IsTest
    public static void extractValues () {

        List<Account> accts = new List<Account>([
            SELECT Id, Name, ParentId 
            FROM Account ]);

        Test.startTest();

            List<Object> extractedIds = Pluck.values(Account.Name, accts);

        Test.stopTest();

        System.assert( extractedIds.size() > 0,
            'Uh oh, it looks like the extract of values did not return the expected result.');
    }

    /**
     * @description Unit test for validating the idMap method
     */
    @isTest
    static void testIdMap() {
        List<Opportunity> opps = [SELECT Id, AccountId FROM Opportunity];

        Test.startTest();

            Map<Id, List<Opportunity>> acctIdToOpps = Pluck.idMap(Opportunity.AccountId, opps);
        
            Test.stopTest();

        System.assertEquals(
            2, acctIdToOpps.get(opps[0].AccountId).size(), 
            'Uh oh, the id map has the incorrect number of entries.');
    }
    
    /**
     * @description Unit test for validating the stringMap method
     */
    @isTest
    static void testStringMap() {
        List<Opportunity> opps = [SELECT Id, AccountId FROM Opportunity];

        Test.startTest();
            
            Map<String, List<Opportunity>> acctIdToOpps = 
                Pluck.stringMap(Opportunity.AccountId, opps);

        Test.stopTest();

        System.assertEquals(
            2, acctIdToOpps.get(opps[0].AccountId).size(), 
            'Uh oh, the string map has the incorrect number of entries.');
    }
    
    /**
     * @description Unit test for validating the filter method
     */
    @isTest
    static void testFilter() {
        List<Opportunity> opps = [SELECT Id, AccountId FROM Opportunity];

        Test.startTest();
            // filter by a specific opp id
            List<Opportunity> filteredOpps = 
                Pluck.filter(Opportunity.Id, opps, opps[0].Id);

        Test.stopTest();

        System.assertEquals(
            1, filteredOpps.size(), 
            'Uh oh, the filtered list has the incorrect number of entries.');
    }

}