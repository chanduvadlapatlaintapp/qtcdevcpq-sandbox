@isTest
public class WaveQuotasControllerTest {

    //considered test setup 
    //to avoid mixed DML between setup and non setup objects
  @testSetup static void TestUsers() {
          User u1 = new User(
         ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
         LastName = 'last',
         Email = 'puser000@ps.com',
         Username = 'puser000@ps.com' + System.currentTimeMillis(),
         CompanyName = 'ApostleTech',
         Title = 'title',
         Alias = 'alias',
         TimeZoneSidKey = 'America/Los_Angeles',
         EmailEncodingKey = 'UTF-8',
         LanguageLocaleKey = 'en_US',
         LocaleSidKey = 'en_US'
         
    );

    User u2 = new User(
         ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator'].Id,
         LastName = 'last123',
         Email = 'puser0001@ps.com',
         Username = 'puser0001@ps.com' + System.currentTimeMillis(),
         CompanyName = 'ApostleTech',
         Title = 'title1',
         Alias = 'alias1',
         TimeZoneSidKey = 'America/Los_Angeles',
         EmailEncodingKey = 'UTF-8',
         LanguageLocaleKey = 'en_US',
         LocaleSidKey = 'en_US'
         
    );

    insert u1;
    insert u2;
    
  }
  
  static testMethod void validateHelloWorld() {

user usr1 = [select id,Email,Username from user WHERE Email='puser000@ps.com' limit 1];
user usr2 = [select id,Email,Username from user WHERE Email='puser0001@ps.com' limit 1];




    Wave_Quota__c Wqta1 = new Wave_Quota__c();
    Wqta1.Sales_Rep__c = usr1.id;
    //Wqta1.Practice__c = 
    Wqta1.FY_Year__c = '2017';
    Wqta1.Quota_Amount__c = 10;
    Wqta1.Quarter__c = 'Q1';

    Wave_Quota__c Wqta2 = new Wave_Quota__c();
    Wqta2.Sales_Rep__c = usr1.id;
    //Wqta2.Practice__c = 
    Wqta2.FY_Year__c = '2017';
    Wqta2.Quota_Amount__c = 10;
    Wqta2.Quarter__c = 'Q2';


    Wave_Quota__c Wqta3 = new Wave_Quota__c();
    Wqta3.Sales_Rep__c = usr2.id;
    //Wqta3.Practice__c = 
    Wqta3.FY_Year__c = '2017';
    Wqta3.Quota_Amount__c = 10;
    Wqta3.Quarter__c = 'Q3';

    Wave_Quota__c Wqta4 = new Wave_Quota__c();
    Wqta4.Sales_Rep__c = usr2.id;
    //Wqta4.Practice__c = 
    Wqta4.FY_Year__c = '2017';
    Wqta4.Quota_Amount__c = 10;
    Wqta4.Quarter__c = 'Q4';

    list<Wave_Quota__c> tempWaves = new list<Wave_Quota__c>{Wqta1, Wqta2, Wqta3, Wqta4};
    insert tempWaves;

    
    test.startTest();
    
    WaveQuotasController tempWave = new WaveQuotasController();
        tempWave.repsFilter();
        tempWave.practiseFilter();
        tempWave.getFicalOptions();
        tempWave.getQuarterOptions();
        tempWave.updateRecords();
        
    test.stopTest();

}
}