/**
 * @description       : This test class will cover CloneOptyWithLineItems class.
 * @author            : Pankaj Kumar
 * @last modified on  : 09-21-2023
 * @last modified by  : Pankaj Kumar
 * Modifications Log
 * Ver   Date         Author         Modification
 * 1.0   07-07-2023   Pankaj Kumar   Initial Version
*/
@isTest
public class CloneOptyWithLineItemsTest {
   
    @testSetup
    public static void setup(){
        List<Account> createAccountsList = TestDataFactory.createAccount(1,true);
        List<Opportunity> createOpptyList = TestDataFactory.createOppty(1,createAccountsList[0].id,false);
        createOpptyList[0].Quote_Start_Date__c = system.today();
        createOpptyList[0].First_Segment_Months__c = 12;
        createOpptyList[0].Deal_Reconciliation_Notes_OP4I__c = 'BIZ-80556 base note – should NOT carry to NYMY';
        insert createOpptyList;
        Id pricebookId = Test.getStandardPricebookId();
        List<SBQQ__Quote__c> createQuoteList = TestDataFactory.createQuote(1,createOpptyList[0].id,false);
        createQuoteList[0].SBQQ__Primary__c=true;
        createQuoteList[0].SBQQ__Opportunity2__c=createOpptyList[0].id;
        //createQuoteList[0].SBQQ__BillingFrequency__c='Annual';
        createQuoteList[0].SBQQ__PricebookId__c=pricebookId;
        insert createQuoteList;
        List<Product2> productList = TestDataFactory.createProduct(1,true);  
            
        PricebookEntry createPricebookEntry= TestDataFactory.createPricebookEntry(productList[0].id,true);
        SBQQ__Dimension__c createPricebookDimension= TestDataFactory.createPricebookDimension(productList[0].id,true);
        List<SBQQ__QuoteLine__c> createQuoteLineList = TestDataFactory.createQuoteLine(5,createQuoteList[0].id,productList[0].id,false);
        createQuoteLineList[0].SBQQ__PricebookEntryId__c=createPricebookEntry.Id;
        insert createQuoteLineList;
    }
    @isTest
    public static void testOptyClosedWon(){
        List<Opportunity> opList = [Select Id,StageName From Opportunity Limit 1];
        List<SBQQ__Quote__c> qlList = [Select Id,Quote_Stage__c From SBQQ__Quote__c Limit 1];
        Test.startTest();
        List<Id> newId= new List<Id>();
        newId.add(opList[0].id);
        CloneOptyWithLineItems.cloneOpp(newId);
        Test.stopTest();

        // BIZ-80556: Deal_Reconciliation_Notes_OP4I__c must not be cloned to the new NYMY.
        List<Opportunity> nymyOpps = [
            SELECT Id, Deal_Reconciliation_Notes_OP4I__c
            FROM Opportunity
            WHERE Deal_Type__c = 'NextYear_MultiYear'
              AND Related_Opportunity__c = :opList[0].Id
        ];
        System.assertEquals(1, nymyOpps.size(), 'Expected exactly one cloned NYMY opportunity');
        System.assertEquals(null, nymyOpps[0].Deal_Reconciliation_Notes_OP4I__c,
            'Deal_Reconciliation_Notes_OP4I__c should not carry over to the cloned NYMY');
    }
}