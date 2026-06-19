@isTest
public class OpporRenewalUpdateMigrationBatch_test {
    //creating test setup method
    @testSetup
    static void setup() {
  
        // creating test user, account, opportunity
        User testUser = IntappTestObjectFactory.createUser();
        insert testUser;
        
        Account testAccount = new Account(
            Name = 'test account'
        );
        insert testAccount;
        
        Opportunity oppTest = new Opportunity(
            Name = 'test opp'
        );
                
        List<Opportunity> lstopp = new List<Opportunity>();
        lstopp.add(oppTest);
        
        List<Contract> contracts = new List<Contract>();
        for (Integer i = 0; i < 5; i++) {
            contracts.add(new Contract(
                Migration_Status__c = 'Renewal Ready',
                EndDate = Date.today().addDays(100),
                SBQQ__RenewalForecast__c = false,
                SBQQ__RenewalQuoted__c = false,
                AccountId = testAccount.Id, 
                SBQQ__Opportunity__c = lstopp[0].Id
            ));
        }
        insert contracts;
        
        
        // create related Entitlement Renewal View records
        List<OP4I_Entitlement_Renewal_View__c> entitlements = new List<OP4I_Entitlement_Renewal_View__c>();
        for (Contract contract : contracts) {
            OP4I_Entitlement_Renewal_View__c entitlement = new OP4I_Entitlement_Renewal_View__c(
                OSA__c = contract.Id,
                Renewal_Deal_Id__c = 'RenewalDeal' + contract.ContractNumber
            );
            entitlements.add(entitlement);
        }
        insert entitlements;

        List<Opportunity> opportunityList = TestDataFactory.createOppty(1, testAccount.Id, true);
        opportunityList[0].SBQQ__RenewedContract__c = contracts[0].Id;
        update opportunityList;
        
        Product2 prodObj = IntappTestObjectFactory.createProduct(true);
        prodObj.Name = 'TestProd';
        update prodObj;
        
        Id pricebookId = Test.getStandardPricebookId();
        
        PricebookEntry pbEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prodObj.Id,
            UnitPrice = 100.00,    
            IsActive = true
        );
        insert pbEntry;
        
        // Create Opportunity Line Items for the Opportunities
        List<OpportunityLineItem> oppLineItems = new List<OpportunityLineItem>();
        for (Opportunity opp : opportunityList) {
            OpportunityLineItem oli = new OpportunityLineItem(
                OpportunityId = opp.Id,
                Quantity = 10,
                PricebookEntryId = pbEntry.Id,
                UnitPrice = 100,
                Customer_List_Price__c = 110,
                CPI__c = 1.2,
                Recurring_Amount_Change__c = 50,
                Recurring_Adjustment__c = 10,
                Active__c = true
            );
            oppLineItems.add(oli);
        }
        insert oppLineItems;
        
        Product2 prodObj1 = IntappTestObjectFactory.createProduct(true);
        prodObj1.Name = 'TestProd1';
        update prodObj1;
        
        SBQQ__Quote__c quoteObj = IntappTestObjectFactory.createSBQQQuote();
        insert quoteObj;
        
        OP4I_Entitlement_View__c entitlement = new OP4I_Entitlement_View__c();
        entitlement.Associated_OSA__c = contracts[0].id;
        entitlement.Start_Date__c = Date.newInstance(2021, 4, 1);
        entitlement.End_Date__c = Date.newInstance(2022, 3, 31);
        entitlement.Sale_Price__c = 20.22;
        entitlement.Product_Type__c = 'Software';
        entitlement.DLI_Product__c = prodObj.id;
        entitlement.DLIP_Product__c = prodObj1.id;
        entitlement.Billing_Frequency__c = 'Annual';
        entitlement.Quote__c = quoteObj.Id;
        entitlement.Opportunity__c = lstopp[0].Id;
        insert entitlement;
        
        OP4I_Entitlement_Renewal_View__c op4i = new OP4I_Entitlement_Renewal_View__c(
            OSA__c = contracts[0].id,
            Product_Id__c = 'test'
        );
        
        List<OP4I_Entitlement_Renewal_View__c> lstOfEntitlementRecords = new List<OP4I_Entitlement_Renewal_View__c>();
        lstOfEntitlementRecords.add(op4i);
    }
    
    @isTest
    static void testBatchWithContractNumbers() {
        
        List<Contract> contracts = [SELECT ContractNumber,Migration_Status__c FROM Contract];
        List<String> contractNumbers = new List<String>();
        for (Contract con : contracts) {
            contractNumbers.add(con.ContractNumber.substring(con.ContractNumber.length() - 1));
        }
        // Initialize the batch with specific contract numbers
        OpportunityRenewalUpdateMigrationBatch batch = new OpportunityRenewalUpdateMigrationBatch(contractNumbers);
        Test.startTest();
        ID batchProcessId = Database.executeBatch(batch);
        Test.stopTest();
        System.assertEquals('Renewal Ready', contracts[0].Migration_Status__c);
        
    }
    
    /* @isTest
static void testBatchWithContractNumbers2() {

test.startTest();
List<Contract> lstOfContracts = new List<Contract>();
product2 prodTest = [Select Id FROM Product2 WHERE Name = 'TestProd1' LIMIT 1] ;
prodTest.IsActive = true;
prodTest.SBQQ__SubscriptionPricing__c = 'Fixed Price';
prodTest.SBQQ__SubscriptionTerm__c = 12;
prodTest.SBQQ__SubscriptionType__c = 'Renewable';
prodTest.SBQQ__ChargeType__c = 'Recurring';
prodTest.SBQQ__BillingFrequency__c = 'Annual';
prodTest.SBQQ__BillingType__c = 'Arrears';
update prodTest;

Contract contr = [Select Id,contractNumber FROM Contract LIMIT 1];
contr.Status = 'Activated';
lstOfContracts.add(contr);
update lstOfContracts;
lstOfContracts[0].Status = 'In Force';
lstOfContracts[0].Subsidiary__c = '05:400 TFG - US';
lstOfContracts[0].Processing_Status__c = 'Parent Quote Line Created';
update lstOfContracts[0];

SBQQ__Quote__c quoteObj = [Select Id FROM SBQQ__Quote__c LIMIT 1];
quoteObj.Migration_Contract__c = lstOfContracts[0].id;
update quoteObj;

Opportunity oppObj = IntappTestObjectFactory.createOpportunity();   
oppObj.Migration_Contract__c = lstOfContracts[0].id;
insert oppObj;

OP4I_Entitlement_View__c entitlementUpd = [Select Id,Start_Date__c,End_Date__c FROM OP4I_Entitlement_View__c LIMIT 1];
entitlementUpd.Start_Date__c = null;
entitlementUpd.End_Date__c = null;
update entitlementUpd;

List<string> lstOfContractNumbers = new List<String>();
lstOfContractNumbers.add(lstOfContracts[0].ContractNumber);

OpportunityRenewalUpdateMigrationBatch qliObj = new OpportunityRenewalUpdateMigrationBatch(lstOfContractNumbers);
database.executebatch(qliObj,1); 
test.stopTest(); 




}*/
    
}