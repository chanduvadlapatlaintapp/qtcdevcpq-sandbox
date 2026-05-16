@isTest
public class DealEventTriggerHandlerTest {

  static testmethod void testMethod1() {
    Account account = IntappTestObjectfactory.createAccount(true);
        
    Contact con = (Contact) SmartFactory.createSObject('Contact');
    con.AccountId = account.Id; 
    insert con;
    
    Contract ctr = (Contract) SmartFactory.createSObject('Contract');
    ctr.AccountId = account.Id;
    insert ctr;
    
    Opportunity opportunity = (Opportunity) SmartFactory.createSObject('Opportunity');
    opportunity.AccountId = account.Id;
    opportunity.Associated_Contract_OSA__c = ctr.Id;
    opportunity.Contract_Signer__c = con.Id;
    opportunity.Requested_Contract_Expiration__c = Date.today();
    opportunity.Initial_Software_Term_Length_Months__c = 12;
    insert opportunity; 
    
    system.assertequals(opportunity.contactId,null);
  }
}