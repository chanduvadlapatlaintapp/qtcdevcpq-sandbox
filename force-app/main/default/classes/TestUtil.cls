/*******************************************************************************
Name      : TestUtil
Purpose   : Contains Utility Methods for Test Classes
Date      : 28-Mar-2012
********************************************************************************/

@isTest(seeAllData=true)
public without sharing class TestUtil {
	
   public static Account createAccount() {
  	  Account account = IntappTestObjectFactory.createAccount(true);
  	  return account;
  }

   public static Account createAccount(Boolean bIsCreate) {
      Account account = IntappTestObjectFactory.createAccount(bIsCreate);
      return account;
   }

  public static User createUser(Boolean isInsert) {
  Profile p = [SELECT Id FROM Profile WHERE Name='Standard User']; 
  
  User u = new User(Alias = 'standt', Email='standarduser@intapp.com', 
            EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='standarduser@intapp.com');
  if(isInsert) {
    insert u;
  }
  return u;

  }
    
  public static Contact createContact(Id accId, Boolean isInsert) {
     Contact contact   = new Contact();
     contact.LastName  = 'test name';
     contact.FirstName = 'Test First';
     contact.Accountid = accId; 
     contact.RecordTypeId = 'Conatct';
     contact.CurrencyIsoCode = 'USD';
     if(isInsert) {
        insert contact;
     }
     return contact;
  }
  
  public static Item_Master_Product__c createItemMaster(Boolean isInsert) {
     Item_Master_Product__c item   = new Item_Master_Product__c();
     item.Item_Name__c  = 'test name';
     item.CurrencyIsoCode = 'USD';
     
     if(isInsert) {
        insert item;
     }
     return item;
  }
  
  public static ACV_Allocation__c createAcvAllocation(Id itemMaster , Double percent , Boolean isInsert) {
     ACV_Allocation__c acvLocation   = new ACV_Allocation__c();
     acvLocation.Product_Line__c = 'Wall Builder';
     acvLocation.Percent_Allocation__c = percent;
     acvLocation.Item_Master_Product__c = itemMaster;
     acvLocation.CurrencyIsoCode = 'USD';
     
     if(isInsert) {
        insert acvLocation;
     }
     return acvLocation;
  }
  
  public static Product2 createProduct(Boolean isInsert) {
     Product2 prod = new Product2();
     prod.Name = 'Test Prd1';
     prod.Family = 'Major';
     if(isInsert) {
       insert prod;
     }
     return prod;
  }
  
  public static Id priceBook2Id;
  
  static {
      priceBook2Id = [Select id from Pricebook2 where IsStandard = true Limit 1][0].Id;
  }
  
  //-----------------------------------------------------------------------------------------------------------
  //Returns PriceBookEntry Record
  //-----------------------------------------------------------------------------------------------------------
  //-------------------------------------------------------------------------------------------------------------
  public static PricebookEntry createPriceBookEntry(Id prodId, Double unitPrice, Boolean isInsert) {
      PricebookEntry pbEntry = new PricebookEntry ();
     pbEntry.product2id = prodId;
     pbEntry.UnitPrice = unitPrice;
     pbEntry.IsActive = true;
     pbEntry.pricebook2id = priceBook2Id;
     pbEntry.UseStandardPrice = false;
    
    if(isInsert) {
       insert pbEntry;
    }
    return pbEntry;
  }
  
  public static Campaign createCampaign(Boolean isInsert) {
     Campaign cmp = new Campaign();
     cmp.Name = 'Test campaign';
     
     if(isInsert) {        
       insert cmp;   
     }
     return cmp; 
  }
  
  public static Opportunity createOpportunity(Id accId, Boolean isInsert) {
     Opportunity opp = new Opportunity();
     opp.name = 'Test Opportunity ';
     opp.AccountId = accId; 
     //opp.Practice_Group__c = 'Operations & Finance'; //Commented for deployment since this change was done recently and we were not aware of this change.
     opp.Practice_Group__c = 'Revenue Practice';
     opp.stageName = 'Target Account';
     opp.CloseDate = Date.newInstance(2006,10,10);
     opp.ForecastCategoryName = 'Pipeline';
     opp.License_Type__c = 'Annual';
     opp.CurrencyIsoCode = 'USD';
     opp.Type = 'Cancellation - CPI';
     //opp.Campaign = Campaign.Id;
     opp.CloseDate = Date.today();
     if(isInsert) {        
       insert opp;   
     }
     return opp;        
  }
  
  public static OpportunityLineItem createOpportunityLineItem(Id oppId, Id pbEntryId, double unitPrice, Boolean isInsert) {
     OpportunityLineItem oli = new OpportunityLineItem();
    oli.opportunityid = oppId; 
    oli.pricebookentryid = pbEntryId; 
    oli.unitprice = unitPrice;
    oli.quantity  = 2;
    if(isInsert) {
       insert oli;
    }
    return oli;
  }
}