/**
* @description Test class for UserLookupController
* @author Pooja Hemrajani
* @jira
**/
@isTest
public with sharing class UserLookupControllerTest {

    @testSetup
    static void setupTestData() {
        List<User> users = new List<User>();
        for (Integer i = 1; i <= 3; i++) {
            users.add(new User(
                FirstName = 'Test',
                LastName = 'User' + i,
                Alias = 'tusr' + i,
                Email = 'testuser' + i + '@test.com',
                Username = 'testuser' + i + '@test.com.' + System.currentTimeMillis(),
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert users;
    }

    @isTest
    static void testSearchWithUserIdList() {
        List<User> users = [SELECT Id FROM User WHERE Email LIKE 'testuser%@test.com%'];
        List<String> userIds = new List<String>();
        for (User u : users) {
            userIds.add(u.Id);
        }

        Test.startTest();
        List<LookupSearchResult> results = UserLookupController.search('User', userIds);
        Test.stopTest();
    }

    @isTest
    static void testSearchWithoutUserIdList() {
        Test.startTest();
        List<LookupSearchResult> results = UserLookupController.search('User', null);
        Test.stopTest();
    }
}