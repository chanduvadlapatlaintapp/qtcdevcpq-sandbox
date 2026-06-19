@isTest
public class Batch_Historical_ProductLine_Test {
	
    @testSetup static void createTestData() {
		Product_Line__c p1 = (Product_Line__c) SmartFactory.createSObject('Product_Line__c');
        p1.name = 'Walls';
        p1.Active__c = true;
        
        Product_Line__c p2 = (Product_Line__c) SmartFactory.createSObject('Product_Line__c');
        p2.name = 'Time';
        p2.Active__c = true;
        
        Product_Line__c p3 = (Product_Line__c) SmartFactory.createSObject('Product_Line__c');
        p3.name = 'Other';
        p3.Active__c = true;
        
        insert p1;
        insert p2;
        insert p3;
        
        Account a = IntappTestObjectFactory.createAccount(true);
        
        Contract c = IntappTestObjectFactory.createContract(a.Id);
    	insert c;
        
        Contact u = IntappTestObjectFactory.createContact(true);
        
        Opportunity o = IntappTestObjectFactory.createOpportunity();
        o.Client_Contact__c = u.Id;
        o.AccountId = a.Id;
        o.Associated_Contract_OSA__c = c.id;
        insert o;
        
        // Opportunity_Product_Component__c opc1 = (Opportunity_Product_Component__c) SmartFactory.createSObject('Opportunity_Product_Component__c');
        // opc1.Opportunity__c = o.Id;
        // opc1.Product_Line__c = 'Walls';
        // opc1.Recurring_Amount_Change__c = 200.00;
    
        // Opportunity_Product_Component__c opc2 = (Opportunity_Product_Component__c) SmartFactory.createSObject('Opportunity_Product_Component__c');
        // opc2.Opportunity__c = o.Id;
        // opc2.Product_Line__c = 'Time';
        // opc2.Recurring_Amount_Change__c = 400.00;

        // insert opc1;
        // insert opc2;
        
        Opportunity o2 = IntappTestObjectFactory.createOpportunity();
        o2.Client_Contact__c = u.Id;
        o2.AccountId = a.Id;
        o2.Associated_Contract_OSA__c = c.id;
        insert o2;
    }
    
    // static testMethod void Test_Batch_Historical_OPCProductLineRollup() {
    //     String query = 'Select Id from Opportunity';
    // 	Batch_Historical_UpdateOppProdLines b1 = new Batch_Historical_UpdateOppProdLines(query, null);
    //     Database.executeBatch(b1);
    // }
    
    static testMethod void testBatchHistoricalUpdateProductLine() {
        String sObjectType = 'Opportunity';
        String oldFieldName = 'Product_Line__c';
        String newFieldName = 'Product_LineNew__c';
        Map<String, String> mapProductlineLookup = new Map<String, String>();
        mapProductlineLookup.put('Walls', 'Walls');
        
        String query = 'Select Id, name, ' + oldFieldName + ',' + newFieldName + ' from Opportunity';
    	//(String query, String sObjectType, String oldFieldName, String newFieldName, Map<String, String> mapProductlineLookup, Set<Integer> bToSkip)
        Batch_Historical_UpdateProductLine b2 = new Batch_Historical_UpdateProductLine(query, sObjectType, oldFieldName, newFieldName, mapProductlineLookup, null);
        Database.executeBatch(b2);
        System.assert(b2!=null);
    }
}