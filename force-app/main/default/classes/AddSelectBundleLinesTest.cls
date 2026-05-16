/**
* @description       : Test Class to cover AddSelectBundleLines
* @author            : Dhiraj Kumar - KPMG
* @date              : 2023-12-19
* Story              : BIZ-51772
*
**/
@isTest
public class AddSelectBundleLinesTest {
@testSetup
    public static void setup(){
        SBQQ.TriggerControl.disable();
        List<Product2> parentProd = TestDataFactory.createProdList('Intapp Risk & Compliance PIN-01670',1,false);
        parentProd[0].ProductCode = 'BU-01408';
        parentProd[0].Is_Select_Bundle__c = true;
        insert parentProd;
        
        List<Product2> childProd = TestDataFactory.createProdList('Intapp Billstream Cloud PIN-01879',20,true);
        PricebookEntry parntProdPriceBookEntry = TestDataFactory.createPricebookEntry(parentProd[0].Id,true);
        SBQQ__Dimension__c parntProdPriceBookDimension = TestDataFactory.createPricebookDimension(parentProd[0].Id,true);
        List<PricebookEntry> childpriceBookEntry = TestDataFactory.createPricebookEntryList(childProd,true);   
        List<SBQQ__ProductOption__c> childProdOptions = TestDataFactory.createProdOptionsList(parentProd[0].Id,childProd,true);
        
        List<Account> accList = TestDataFactory.createAccount(1,True);              
        //List<Opportunity> opportunityList = TestDataFactory.createOppty(2, accList[0].Id, true);
        List<SBQQ__Quote__c> quoteList1 = TestDataFactory.createQuote(1, null, true);
        //List<SBQQ__Quote__c> quoteList2 = TestDataFactory.createQuote(1, opportunityList[1].Id, true);
        
        List<SBQQ__QuoteLine__c> parentquoteLineList = TestDataFactory.createQuoteLine(1,quoteList1[0].Id,parentProd[0].Id,false);  
        parentquoteLineList[0].Is_Select_Bundle__c = true;
        List<SBQQ__QuoteLine__c> childquoteLineList = TestDataFactory.createQuoteLineList(20,quoteList1[0].Id,childProd,false);
        System.assertequals(20,childquoteLineList.size());
        List<SBQQ__QuoteLine__c> childquoteLineListToUpdate= new List<SBQQ__QuoteLine__c>();
        
        childquoteLineList.addAll(parentquoteLineList);
        insert childquoteLineList;
        System.assertequals(21,childquoteLineList.size());
        SBQQ.TriggerControl.enable();
    }
    /**
    * ***********************************************************
    * This method is test method for addSelectBundle
    * ***********************************************************
    */
    @isTest
    public static void testAddSelectBundle(){      
  		
        
        try
        {
            Test.startTest();
            SBQQ.TriggerControl.disable();
            Id parentId = null;
            List<SBQQ__Quote__c> quoteList = [SELECT Id, Name FROM SBQQ__Quote__c];
            List<SBQQ__QuoteLine__c> quoteLineList = [SELECT Id, Name, SBQQ__ProductCode__c,SBQQ__RequiredBy__c FROM SBQQ__QuoteLine__c];
            List<SBQQ__QuoteLine__c> quoteLineListToUpdate = new List<SBQQ__QuoteLine__c>();
            for(SBQQ__QuoteLine__c quoteLine : quoteLineList)
            {
                if(quoteLine.SBQQ__ProductCode__c == 'BU-01408'){
                    parentId = quoteLine.Id;
                }
            }
            
            for(SBQQ__QuoteLine__c quoteLine : quoteLineList)
            {
                if(quoteLine.SBQQ__ProductCode__c != 'BU-01408'){
                    quoteLine.SBQQ__RequiredBy__c = parentId;
                    quoteLine.Segment_Index_Custom__c ='1';
                    quoteLineListToUpdate.add(quoteLine);
                }
            }
            update quoteLineListToUpdate;
			AddSelectBundleLines.createSelectLineandTermQuotesRecords(quoteList[0].Id);
            AddSelectBundleLines.generateCongaURL(quoteList[0].Id);
            quoteList[0].Quote_Stage__c='Finalize OSA';
            update quoteList[0];
            AddSelectBundleLines.generateCongaURL(quoteList[0].Id);
            System.assertEquals(1,quoteList.size());
            SBQQ.TriggerControl.enable();  
            Test.stopTest();
        }
        catch(Exception ex)
        {
            System.debug('Exception Caught at :'+ ex.getMessage() );
        }
         
        
    }
    @isTest
    public static void testgenerateCongaURL(){       
        SBQQ.TriggerControl.disable();
        try
        {
            Test.startTest();
            Id parentId = null;
            List<SBQQ__Quote__c> quoteList = [SELECT Id, Name FROM SBQQ__Quote__c];
            List<SBQQ__QuoteLine__c> quoteLineList = [SELECT Id, Name, SBQQ__ProductCode__c,SBQQ__RequiredBy__c FROM SBQQ__QuoteLine__c];
            List<SBQQ__QuoteLine__c> quoteLineListToUpdate = new List<SBQQ__QuoteLine__c>();
           /* APXTConga4__Conga_Query__c cQuery = new APXTConga4__Conga_Query__c();
            cQuery.APXTConga4__Key__c ='0_12345';
            cQuery.APXTConga4__Name__c = 'TestQuery';
            cQuery.APXTConga4__Query__c = 'SELECT Id, Name FROM SBQQ__Quote__c';
            insert cQuery;*/
            APXTConga4__Conga_Solution__c cSol= new APXTConga4__Conga_Solution__c();
            cSol.Name = 'Pricing Proposal Document';
            insert cSol;
            APXTConga4__Conga_Solution_Query__c cSolQuery= new APXTConga4__Conga_Solution_Query__c();
            //cSolQuery.APXTConga4__Conga_Query__c = cQuery.Id;
            cSolQuery.APXTConga4__Conga_Solution__c = cSol.Id;
            insert cSolQuery;
            quoteList[0].Quote_Stage__c='Pricing Proposal';
            update quoteList[0];
            AddSelectBundleLines.generateCongaURL(quoteList[0].Id);
            quoteList[0].Quote_Stage__c='Finalize OSA';
            update quoteList[0];
            AddSelectBundleLines.generateCongaURL(quoteList[0].Id);
            quoteList[0].SBQQ__WatermarkShown__c=true;
            update quoteList[0];
            AddSelectBundleLines.generateCongaURL(quoteList[0].Id);
            System.assertEquals(1,quoteList.size());
            Test.stopTest();
        }
        catch(Exception ex)
        {
            System.debug('Exception Caught at :'+ ex.getMessage() );
        }
           SBQQ.TriggerControl.enable();   
        
    }
}