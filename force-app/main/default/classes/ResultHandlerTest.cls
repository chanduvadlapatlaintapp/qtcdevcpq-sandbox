/**
 * @author : Sahal Mohamed  
 * @date : 02/10/2025
 * @description : test class for the ResultHandler
**/

@isTest
public without sharing class ResultHandlerTest {


    /**********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/

    /**
     * @description -tests that the result handler is logging error records
     * */
    @IsTest
    public static void targetInsertTest () {

        List<Account> accts = 
            new List<Account>{
                new Account(Name = 'Test Account'),
                new Account(Id = '00130000001REHAAA4')
            };

        List<Database.SaveResult> results = 
            Database.insert(accts, false);

        Test.startTest();

            ResultHandler.logErrors('ResultHandler_Test', accts, results);
            ResultHandler.logErrorsAtFuture('ResultHandler_Test', accts, results);

        Test.stopTest();

        System.assertNotEquals(0, [SELECT Id FROM Error_Log__c WHERE Process__c = 'ResultHandler_Test'].size(),
            'Uh oh, it looks like the result handler isnt properly logging errors.');
    }

    /**
     * @description -tests that the result handler is logging error records
     * */
    @IsTest
    public static void targetUpsertTest () {

        List<Account> acctToUpsert = 
            new List<Account>{
                new Account(Name = 'Test Account2'),
                new Account()
            };

        List<Database.UpsertResult> upsertResults = 
            Database.upsert(acctToUpsert, false);

        Test.startTest();

            ResultHandler.logErrors('ResultHandlerUpsert_Test', acctToUpsert, upsertResults);
            ResultHandler.logErrorsAtFuture('ResultHandlerUpsert_Test', acctToUpsert, upsertResults);

        Test.stopTest();

        System.assertNotEquals(0, [SELECT Id FROM Error_Log__c WHERE Process__c = 'ResultHandlerUpsert_Test'].size(),
            'Uh oh, it looks like the result handler isnt properly logging errors.');
    }

    /**
     * @description -tests that the result handler is logging send email error records
     * */
    @isTest
    private static void targetEmailTest() {

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

        email.setSubject('ResultHandler_Test Email');
        email.setPlainTextBody('Test email for ResultHandler');
        email.setToAddresses( new String[] { 'test@confluent.io' } );

        Messaging.sendEmail( new Messaging.SingleEmailMessage[] { email } );

        List<Messaging.SendEmailResult> results = Messaging.SendEmail(new Messaging.Email[] { email });

        Test.startTest();

            ResultHandler.logErrors('ResultHandlerSendEmail_Test', results);

        Test.stopTest();

        System.assertEquals(0, [SELECT Id FROM Error_Log__c WHERE Process__c = 'ResultHandlerSendEmail_Test'].size(),
            'Uh oh, it looks like the result handler isnt properly logging errors.');
    }

    /**
     * @description -tests that the result handler is logging error records
     * */
    @IsTest
    public static void targetDeleteTest () {

        List<Lead> leadsToDelete = 
            new List<Lead>{
                new Lead(LastName = 'Test Lead3', Company = 'Test Company'),
                new Lead(LastName = 'Test Lead4', Company = 'Test Company')
            };
        insert leadsToDelete;
        delete leadsToDelete;

        List<Database.DeleteResult> deleteResults = 
            Database.delete(leadsToDelete, false);

        Test.startTest();

            ResultHandler.logErrors('ResultHandlerDelete_Test', leadsToDelete, deleteResults);
            ResultHandler.logErrorsAtFuture('ResultHandlerDelete_Test', leadsToDelete, deleteResults);
        Test.stopTest();

        System.assertNotEquals(0, [SELECT Id FROM Error_Log__c WHERE Process__c = 'ResultHandlerDelete_Test'].size(),
            'Uh oh, it looks like the result handler isnt properly logging errors.');
    }

}