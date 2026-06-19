@isTest(seealldata=true)
public class IntegrationUtilityTest {
@isTest
    static void testMethod1(){
  /*  Field_Tracking__mdt fieldTrack = new Field_Tracking__mdt();
    fieldTrack.Field_Api_Name__c = 'Id';
    fieldTrack.Object_Name__c = 'Opportunity'; */
  //  insert fieldTrack;
    
    Account account = (Account) SmartFactory.createSObject('Account');
    account.Industry = 'Test Industry';
    account.BillingCountry = 'Test';
    account.OP4I_Sales_Segment__c = '01-Legal - APAC';
    insert account;
    
  /*  Contact con = (Contact) SmartFactory.createSObject('Contact');
    con.AccountId = account.Id; 
    insert con;
    
    Contract ctr = (Contract) SmartFactory.createSObject('Contract');
    ctr.AccountId = account.Id;
    insert ctr; */
    
  //  Opportunity oppObj = new Opportunity();
  //  oppObj.AccountId = account.Id;
  //  oppObj.Associated_Contract_OSA__c = ctr.Id;
  //  oppObj.Contract_Signer__c = con.Id;
  //  oppObj.Requested_Contract_Expiration__c = Date.today();
  //  oppObj.Initial_Software_Term_Length_Months__c = 12;
  /*  oppObj.Type = 'Accounting Adjustment';
    oppObj.CloseDate = System.today();
    oppObj.StageName = 'Qualify';
    oppObj.Name = 'TestnewOpp';
    insert oppObj; */
    
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
      //  newQuote.OP4I_Sales_Segment__c = '03-Legal EMEA';
     //   newQuote.SBQQ__Opportunity2__c = opportunity.Id;
     //   newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = system.today();
        insert newQuote;
        System.assertEquals('Lawyers',newQuote.License_Basis__c); 
  //  IntegrationUtility.publishsObjectRecord(newQuote,'SBQQ__Quote__c');  
       
    }   
}