@isTest
public class OpportunityProductFlowClassTest {
    @isTest
    public static void testHandler(){
        Account acc = IntappTestObjectFactory.createAccount(true);
        Opportunity opp = IntappTestObjectFactory.createOpportunity();
        opp.Name= 'TestOppoty';
    	opp.AccountId = acc.Id;
        opp.StageName = '01. Qualify';
    	opp.Requested_Contract_Expiration__c = Date.today();
    	opp.Initial_Software_Term_Length_Months__c = 12;
    	insert opp;
        Id pricebookId = Test.getStandardPricebookId();
        Product2 prod = new Product2(
            Name = 'Intapp Integration Service: advanced',
            ProductCode = 'IS-01602',
            isActive = true
        );
        insert prod;
        
       PricebookEntry pbEntry = new PricebookEntry(
       Pricebook2Id = pricebookId,
       Product2Id = prod.Id,
       UnitPrice = 100.00,    
       IsActive = true
       );
       insert pbEntry;
      
       List<Id> listOliIds = new List<Id>();
       OpportunityLineItem oli = new OpportunityLineItem(
           OpportunityId = opp.Id,
           Quantity = 10,
           PricebookEntryId = pbEntry.Id,
           UnitPrice = 100,
           Customer_List_Price__c = 2000,
           CPI__c = 2,
           Recurring_Amount_Change__c = 800,
           Recurring_Adjustment__c =10,
           Opportunity_Prod_Updated__c = true,
           Active__c = true
       );
        insert oli;
        listOliIds.add(oli.Id);
        OpportunityProductFlowClass.createOP4IOliPayload(listOliIds);
	}
}