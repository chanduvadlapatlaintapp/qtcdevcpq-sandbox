/**
 * Created By: Abhijeet Bhandari
 * Created On: 1/12/2024
 * Description: Tect class for ClsAsyncOpportunityUpdate to validate the invocable emthod and the future method.
 */
@isTest
private class ClsAsyncOpportunityUpdateTest {

    @TestSetup
    static void makeData(){
        List<Account> lstAccount = TestDataFactory.createAccount(1,true);   
        List<Opportunity> lstOpportunity = TestDataFactory.createOppty(1,lstAccount[0].Id,true);       
    }
    
    @isTest
    static void testAsyncOpportunityUpdateQuote() {        
        List<Account> lstAccount = [SELECT ID from Account WHERE Name LIKE '%Test Account%'];
        List<List<Opportunity>> lstOpportunityWrapped = new List<List<Opportunity>>();
        List<Opportunity> lstOpportunity = new List<Opportunity>();
        List<Opportunity> lstUpdatedOpportunity = new List<Opportunity>();
        Test.startTest();
            lstOpportunity = [SELECT Id, Deal_Type__c FROM Opportunity WHERE AccountId=:lstAccount[0].Id];
            lstOpportunityWrapped.add(lstOpportunity); 
            system.assert(String.isBlank(lstOpportunity[0].Deal_Type__c));            
            List<SBQQ__Quote__c> lstQuote = TestDataFactory.createQuote(1,lstOpportunity[0].Id,false);  
            lstQuote[0].Deal_Type__c = 'Expansion';
            lstQuote[0].SBQQ__Primary__c = false;          
            insert lstQuote;
            ClsAsyncOpportunityUpdate.updateOpportunities(lstOpportunityWrapped);     
        
            
        Test.stopTest();
    }
}