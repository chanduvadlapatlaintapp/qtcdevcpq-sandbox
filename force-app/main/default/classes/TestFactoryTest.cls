/**
 * @author Sahal Mohamed
 * @date 02/11/2025
 * @description Test Class for Test Factory
 * @reference https://github.com/dhoechst/Salesforce-Test-Factory
 **/
@isTest
private class TestFactoryTest{

    /**
     * @description when Object Is Created Expect Default Fields Are Populated
     */
    @isTest
    static void whenObjectIsCreatedExpectDefaultFieldsArePopulatedTest(){
        //when
        Test.startTest();
            Account testAccount = (Account)TestFactory.createSObject(
                new Account(
                    Name = 'Test'
                )
            );
        Test.stopTest();
        //then
        System.assertEquals(true, testAccount.Name.startsWith('Test'), 'Expecting Default field value is set to specific value');
    }

    /**
     * @description when Object Is Created With Specific Defaults Set Expect Default Fields 
     *              Are Populated
     */
    @isTest
    static void whenObjectIsCreatedWithSpecificDefaultsSetExpectDefaultFieldsArePopulatedTest(){
        //when
        Test.startTest();
            Account testAccount = (Account)TestFactory.createSObject(
                new Account(
                    Name = 'Test Account'
                ), 'AccountDefaults');
        Test.stopTest();
        //then
        System.assertEquals(true, testAccount.Name.startsWith('Test Account'), 'Expecting Default field value is set to specific value');
    }

    /**
     * @description when List Of Objects are Created Expect Default Fields Are Populated
     */
    @isTest
    static void whenListOfObjectsIsCreatedExpectDefaultFieldsArePopulatedTest(){
        //when
        Test.startTest();
            Account[] testAccounts = (Account[])TestFactory.createSObjectList(
                new Account(
                    Name = 'Test Account'
                ), 130);
        Test.stopTest();
        //then
        System.assertEquals(130, testAccounts.size(), 'Account count must be 130');
        System.assertEquals('Test Account 0', testAccounts[0].Name, 'First Account Name not set correctly');
        System.assertEquals('Test Account 129', testAccounts[129].Name, 'Last Account Name not set correctly');
        for(Account testAccount : testAccounts){
            System.assert(testAccount.Name.startsWith('Test Account'), 'Expecting Default field value is set to specific value');
        }
    }

    /**
     * @description when List Of Object Is Inserted Expect Default Fields Are Populated
     */
    @isTest
    static void whenListOfObjectIsInsertedExpectDefaultFieldsArePopulatedTest(){
        //when
        Test.startTest();
            Account[] testAccounts = (Account[])TestFactory.createSObjectList(
                new Account(
                    Name = 'Test Account'
                ), 130);
        Test.stopTest();
        //then
        testAccounts = [SELECT Name FROM Account WHERE Id IN :testAccounts ORDER BY Name];
        System.assertEquals(130, testAccounts.size(), 'Account count must be 130');
        System.assertEquals('Test Account 0', testAccounts[0].Name, 'First Account Name not set correctly');
        for(Account testAccount : testAccounts){
            System.assert(testAccount.Name.startsWith('Test Account'), 'Expecting Default field value is set to specific value');
        }
    }

    /**
     * @description when List Of Objects are Created With Specific Defaults Set Expect Default Fields
     *              Are Populated
     */
    @isTest
    static void whenListOfObjectsIsCreatedWithSpecificDefaultsSetExpectDefaultFieldsArePopulatedTest(){
        //when
        Test.startTest();
            Account[] testAccounts = (Account[])TestFactory.createSObjectList(
              new Account(
                Name = 'Test Account'
              ), 130, 'AccountDefaults');
        Test.stopTest();
        //then
        System.assertEquals(130, testAccounts.size(), 'Account count must be 130');
        System.assertEquals('Test Account 0', testAccounts[0].Name, 'First Account Name not set correctly');
        System.assertEquals('Test Account 129', testAccounts[129].Name, 'Last Account Name not set correctly');
        for(Account testAccount : testAccounts){
            System.assert(testAccount.Name.startsWith('Test Account'), 'Expecting Default field value is set to specific value');
        }
    }

    /**
     * @description when List Of Objects are Inserted With Specific Defaults Set Expect Default Fields
     *              Are Populated Test
     */
    @isTest
    static void whenListOfObjectsIsInsertedWithSpecificDefaultsSetExpectDefaultFieldsArePopulatedTest(){
        //when
        Test.startTest();
            Account[] testAccounts = (Account[])TestFactory.createSObjectList(
                new Account(
                    Name = 'Test Account'
                ), 130, 'AccountDefaults');
        Test.stopTest();
        //then
        testAccounts = [SELECT Name FROM Account WHERE Id IN :testAccounts ORDER BY Name];
        System.assertEquals(130, testAccounts.size(), 'Account count must be 130');
        System.assertEquals('Test Account 0', testAccounts[0].Name, 'First Account Name not set correctly');
        for(Account testAccount : testAccounts){
            System.assert(testAccount.Name.startsWith('Test Account'), 'Expecting Default field value is set to specific value');
        }
    }
}