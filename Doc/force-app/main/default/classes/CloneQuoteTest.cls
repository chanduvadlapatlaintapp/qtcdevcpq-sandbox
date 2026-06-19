/**
* @description       : Test class for CloneQuote
* @author            : Keerthan N
* Jira story : BIZ-47457//
**/
@isTest
public class CloneQuoteTest {
    
    @testSetup
    public static void setup(){
        
        List<AVA_MAPPER__Entity_Use_code__c> avaList = TestDataFactory.createEntityUseCode(1,True);
        List<Account> accList = TestDataFactory.createAccount(1,False);
        accList[0].AVA_MAPPER__Entity_Use_code__c = avaList[0].Id;
        Insert accList;
        
        Id pricebookId = Test.getStandardPricebookId();
        List<Opportunity> opptyList = TestDataFactory.createOppty(2,accList[0].Id,False);
        opptyList[0].Pricebook2Id = pricebookId;
        //opptyList[1].Pricebook2Id = pricebookId;
        Insert opptyList;
        List<Product2> prodObj = TestDataFactory.createProduct(1,false);
        Insert prodObj;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=pricebookId, Product2Id=prodObj[0].id, UnitPrice=1, IsActive=True);
        Insert pbe; 
        List<SBQQ__Quote__c> quoteList1 = TestDataFactory.createQuote(1,opptyList[0].Id,False);
        List<SBQQ__Quote__c> quoteList2 = TestDataFactory.createQuote(1,opptyList[1].Id,False);
        quoteList1[0].SBQQ__Account__c = accList[0].Id;
        quoteList1[0].Renewal_Quote_Type__c = System.Label.Auto_Renewal;
        quoteList1[0].SBQQ__Opportunity2__c = opptyList[0].Id;
        quoteList2[0].SBQQ__Account__c = accList[0].Id;
        quoteList2[0].SBQQ__Opportunity2__c = opptyList[1].Id;
        List<SBQQ__Quote__c> updateQuote = new List<SBQQ__Quote__c>();
        updateQuote.add(quoteList1[0]);
        //updateQuote.add(quoteList2[0]);
        Insert updateQuote;
        List<SBQQ__QuoteLine__c> quoteLineList1 = TestDataFactory.createQuoteLine(1,quoteList1[0].Id,prodObj[0].Id,False);
        List<SBQQ__QuoteLine__c> quoteLineList2 = TestDataFactory.createQuoteLine(1,quoteList2[0].Id,prodObj[0].Id,False);
        List<SBQQ__QuoteLine__c> insertQL = new List<SBQQ__QuoteLine__c>();
        insertQL.add(quoteLineList1[0]);
        //insertQL.add(quoteLineList2[0]);
        Insert insertQL;
        Test.startTest();
        List<Contract> contList = TestDataFactory.createContract(2,accList[0].Id,False);
        contList[0].SBQQ__Quote__c = updateQuote[0].Id;
        //contList[1].SBQQ__Quote__c = updateQuote[1].Id;
        Insert  contList;
        //List<Opportunity> opptyList1 = [Select Id From Opportunity];
        opptyList[0].SBQQ__RenewedContract__c = contList[0].Id;
        opptyList[1].SBQQ__RenewedContract__c = contList[1].Id;
        Update opptyList;
        Test.stopTest();
    }
    
    @istest
    private static void checkAndCreateQuoteTest(){
        List<Contract> contList = [Select Id From Contract];
        /*List<SBQQ__Quote__c> updateQuote = [Select Id,SBQQ__Opportunity2__c,SBQQ__Opportunity2__r.SBQQ__RenewedContract__c,Renewal_Quote_Type__c From SBQQ__Quote__c];
        System.debug('updateQuote : '+updateQuote);
        List<Opportunity> opptyList = [Select Id,SBQQ__RenewedContract__c From Opportunity];
        System.debug('opptyList : '+opptyList);
        List<Opportunity> opptyList = [Select Id From Opportunity];
        opptyList[0].SBQQ__RenewedContract__c = contList[0].Id;
        opptyList[1].SBQQ__RenewedContract__c = contList[1].Id;
        Update opptyList;*/
        List<Id> contIdList = new List<Id>();
        for(Contract con : contList){
            contIdList.add(con.Id);
        }
        List<CloneQuote.InputVariables> inputVarList = new List<CloneQuote.InputVariables>();
        CloneQuote.InputVariables inputVar = new CloneQuote.InputVariables();
        inputVar.contractIdList = contIdList;
        inputVar.startDate = system.Today()+20;
        inputVarList.add(inputVar);
        Test.startTest();
        	CloneQuote.duplicateQuote(inputVarList);
        Test.stopTest();
        List<SBQQ__Quote__c> quoteList = [Select Id,Name From SBQQ__Quote__c Limit 1];
        Assert.isTrue(quoteList.size() > 0, 'Quote Inserted');
    }
    
}