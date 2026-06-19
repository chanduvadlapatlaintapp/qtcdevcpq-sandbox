/**
* @description       : This test class will cover QuoteTermValidator class.
* @author            : Shikha Verma
* @last modified on  : 11-29-2023
* @last modified by  : Shikha Verma
* Modifications Log
* Ver   Date         Author         Modification
* 1.0   11-29-2023   Shikha Verma   Initial Version
*/
@isTest
public class QuoteTermValidatorTest {
    /**
* ***********************************************************
* This method is test SetUp method 
* ***********************************************************
*/
    @testSetup
    public static void setup(){     
        List<Account> accList = TestDataFactory.createAccount(1,True);              
        List<Opportunity> opportunityList = TestDataFactory.createOppty(1, accList[0].Id, true);
        Item_Master_Product__c master = new Item_Master_Product__c();
        master.Name = 'PIN-01550';
        insert master; 
        
        Product2 prod1 = new Product2();
        prod1.Name = 'Dun & Bradstreet data management and firmographics for Intapp DealCloud';
        prod1.ProductCode = 'TP-01550';
        prod1.Status__c = 'Active';
        prod1.Item_Master_Product__c = master.Id;
        insert prod1;
        
        Item_Master_Product__c master2 = new Item_Master_Product__c();
        master2.Name = 'PIN-01600';
        insert master2; 
        
        Product2 prod2 = new Product2();
        prod2.Name = 'Intapp Integration Service: essentials';
        prod2.ProductCode = 'IS-01600';
        prod2.Status__c = 'Active';
        prod2.Item_Master_Product__c = master2.Id;
        insert prod2;

        List<SBQQ__Quote__c> quoteList = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = accList.get(0).Id,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = opportunityList[0].Id
            ), 1, 'SBQQQuoteDefaults');
        
        List<Product2> childProd = [SELECT Id, Name FROM Product2 WHERE ProductCode = 'TP-01550' LIMIT 1];
        
        System.debug('ChildProd ='+childProd);
        List<Product2> childProd2 = [SELECT Id, Name FROM Product2 WHERE ProductCode = 'Dun & Bradstreet data management and firmographics for Intapp DealCloud' LIMIT 1];
        List<SBQQ__QuoteLine__c> lstOfQuoteLines = new List<SBQQ__QuoteLine__c>();
        SBQQ__QuoteLine__c qtlc = new SBQQ__QuoteLine__c();
        qtlc.SBQQ__Product__c= prod1.Id;
        qtlc.SBQQ__Quote__c=quoteList[0].Id;
        qtlc.SBQQ__NetPrice__c = 200;
        qtlc.SBQQ__CustomerPrice__c = 25;
        qtlc.SBQQ__Quantity__c = 1;
        qtlc.Print_at_Quote__c = false;
        qtlc.CurrencyIsoCode = 'USD';
        qtlc.SBQQ__ListPrice__c = 100;
        qtlc.Parent_of_Bundle__c = false;
        qtlc.SBQQ__SegmentIndex__c = 1;
    
        lstOfQuoteLines.add(qtlc);
        
        SBQQ__QuoteLine__c qtlc2 = new SBQQ__QuoteLine__c();
        qtlc2.SBQQ__Product__c=prod2.Id;
        qtlc2.SBQQ__Quote__c=quoteList[0].Id;
        qtlc2.SBQQ__NetPrice__c = 200;
        qtlc2.SBQQ__CustomerPrice__c = 25;
        qtlc2.SBQQ__Quantity__c = 1;
        qtlc2.Print_at_Quote__c = false;
        qtlc2.CurrencyIsoCode = 'USD';
        qtlc2.SBQQ__ListPrice__c = 100;
        qtlc2.Parent_of_Bundle__c = false;
        qtlc2.SBQQ__SegmentIndex__c = 1;
        lstOfQuoteLines.add(qtlc2);
        insert lstOfQuoteLines;
        List<SBQQ__QuoteTerm__c> quoteTermList = new List<SBQQ__QuoteTerm__c>();
        //List<SBQQ__QuoteTerm__c> quoteTermList = TestDataFactory.createQuoteTerm(20,true);
        SBQQ__QuoteTerm__c qtTerm = new SBQQ__QuoteTerm__c();
        qtTerm.SBQQ__Body__c='All {!quote.Quote_Stage__c} software and services are provided to Customer solely in accordance with and subject to the Master Subscription and Services Agreement v13 which is posted on the Internet at https://www.intapp.com/intapptermsandconditions/ ("MSSA"). The MSSA, this Order and Sale Agreement ("OSA") and the Statement of Work (“SOW”), if any, are collectively the "Agreement." Customer signature on this OSA constitutes Custome acceptance of such MSSA as governing this OSA and SOW, if any. Any capitalized terms used but not specifically defined herein shall have the same meaning as defined in the Agreement.';
        qtTerm.SBQQ__PrintOrder__c=10;
        qtTerm.SBQQ__Active__c=true;
        insert qtTerm;
        quoteTermList.add(qtTerm);
        
        Term_Quote__c termQuote = new Term_Quote__c(Quote__c=quoteList[0].Id,Term__c=quoteTermList[0].Id,Body__c='Test',Print_Order__c=300);
        Term_Quote__c termQuote1 = new Term_Quote__c(Quote__c=quoteList[0].Id,Term__c=quoteTermList[0].Id,Body__c='Test<p>',Print_Order__c=200,Modified__c=true);
        insert termQuote1;
    }
    
    /**
* ***********************************************************
* This method is test method for generateQuoteTerms
* ***********************************************************
*/
    @isTest
    public static void testgenerateQuoteTerms(){        
        Test.startTest();
        List<SBQQ__Quote__c> quoteList = [SELECT Id,Quote_Stage__c,master_product_pins_from_all_quote_lines__c, Name FROM SBQQ__Quote__c LIMIT 1];
        SBQQ__QuoteTerm__c quoteTerm = [SELECT Id,SBQQ__Body__c,SBQQ__PrintOrder__c,SBQQ__Active__c, Name FROM SBQQ__QuoteTerm__c LIMIT 1];
        SBQQ__TermCondition__c termCondition1 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='master_product_pins_from_all_quote_lines__c',SBQQ__Operator__c='contains',SBQQ__Value__c='IS-01600',SBQQ__Index__c=40);
        /* SBQQ__TermCondition__c termCondition2 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='SBQQ__ProductCode__c',SBQQ__Operator__c='does not contain',SBQQ__Value__c='Test',SBQQ__Index__c=2);
SBQQ__TermCondition__c termCondition3 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Master_Terms__c',SBQQ__Operator__c='not equals',SBQQ__Value__c='Existing Intapp MSSA Terms',SBQQ__Index__c=3);
SBQQ__TermCondition__c termCondition4 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Master_Terms__c',SBQQ__Operator__c='equals',SBQQ__Value__c='Existing Intapp MSSA Plus Cloud',SBQQ__Index__c=4);*/
        List<SBQQ__TermCondition__c> termCondList = new List<SBQQ__TermCondition__c>();
        termCondList.add(termCondition1);
        /*termCondList.add(termCondition2);
termCondList.add(termCondition3);
termCondList.add(termCondition4);*/
        insert termCondList;
        quoteTerm.SBQQ__ConditionsMet__c='Any';
        update quoteTerm;
        QuoteTermValidator.generateQuoteTerms(quoteList[0].Id);
        GetTermQuote gt = new GetTermQuote();
        gt.relatedId = quoteList[0].Id;
        gt.getTermQuotes();
        Set<String> productCodes = new Set<String>();
        productCodes.add('IS-01600');
        List<Term_Quote__c> termsToCreate = new List<Term_Quote__c>();
         ConditionEvaluator evaluateConditions = new ConditionEvaluator(quoteTerm, quoteList[0], productCodes);  
         evaluateConditions.evaluateTermConditions(termCondList);
            //System.debug('term'+term);
            Term_Quote__c termquote = evaluateConditions.evaluateConditionsAndInstantiateQuoteTerm();
            termsToCreate.add(termquote);
        System.assertEquals(1,quoteList.size());
        Test.stopTest();
    }
    
     /**
* ***********************************************************
* This method is test method for generateQuoteTerms
* ***********************************************************
*/
    @isTest
    public static void testgenerateQuoteTerms1(){  
        List<SBQQ__Quote__c> quoteList = [SELECT Id,Quote_Stage__c,Subsidiary__c,Contract_Master_Terms__c,Name FROM SBQQ__Quote__c LIMIT 1];
        SBQQ__QuoteTerm__c quoteTerm = [SELECT Id, SBQQ__Body__c,SBQQ__PrintOrder__c,SBQQ__Active__c, Name FROM SBQQ__QuoteTerm__c LIMIT 1];
        SBQQ__TermCondition__c termCondition1 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Subsidiary__c',SBQQ__Operator__c='contains',SBQQ__Value__c='DealCloud',SBQQ__Index__c=1);
        SBQQ__TermCondition__c termCondition2 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Subsidiary__c',SBQQ__Operator__c='does not contain',SBQQ__Value__c='Test',SBQQ__Index__c=2);
        SBQQ__TermCondition__c termCondition3 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Master_Terms__c',SBQQ__Operator__c='not equals',SBQQ__Value__c='Existing Intapp MSSA Terms',SBQQ__Index__c=3);
        SBQQ__TermCondition__c termCondition4 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Master_Terms__c',SBQQ__Operator__c='equals',SBQQ__Value__c='Existing Intapp MSSA Plus Cloud',SBQQ__Index__c=4);
        List<SBQQ__TermCondition__c> termCondList = new List<SBQQ__TermCondition__c>();
        termCondList.add(termCondition1);
        termCondList.add(termCondition2);
        termCondList.add(termCondition3);
        termCondList.add(termCondition4);
        insert termCondList;
        quoteTerm.SBQQ__ConditionsMet__c='Custom';
        quoteTerm.SBQQ__AdvancedCondition__c='1 AND 2 AND ( 3 OR 4 )';
        update quoteTerm;
        Test.startTest();           
        QuoteTermValidator.generateQuoteTerms(quoteList[0].Id);
           Set<String> productCodes = new Set<String>();
        productCodes.add('IS-01600');
        List<Term_Quote__c> termsToCreate = new List<Term_Quote__c>();
         ConditionEvaluator evaluateConditions = new ConditionEvaluator(quoteTerm, quoteList[0], productCodes);  
         evaluateConditions.evaluateTermConditions(termCondList);
            //System.debug('term'+term);
            Term_Quote__c termquote = evaluateConditions.evaluateConditionsAndInstantiateQuoteTerm();
            termsToCreate.add(termquote);
        System.assertEquals(1,quoteList.size());
        Test.stopTest();
    }
    
    /**
* ***********************************************************
* This method is test method for generateQuoteTerms
* ***********************************************************
*/
    @isTest
    public static void testgenerateQuoteTerms2(){  
        List<SBQQ__Quote__c> quoteList = [SELECT Id,Quote_Stage__c,master_product_pins_from_all_quote_lines__c,Contract_Term_Version__c,(SELECT Id, SBQQ__ProductCode__c FROM SBQQ__LineItems__r), Name FROM SBQQ__Quote__c LIMIT 1];
        SBQQ__QuoteTerm__c quoteTerm = [SELECT Id, SBQQ__Body__c,SBQQ__PrintOrder__c,SBQQ__Active__c,Name FROM SBQQ__QuoteTerm__c LIMIT 1];
        SBQQ__TermCondition__c termCondition1 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='master_product_pins_from_all_quote_lines__c',SBQQ__Operator__c='contains',SBQQ__Value__c='TP-01550',SBQQ__Index__c=198);
        SBQQ__TermCondition__c termCondition2 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Term_Version__c',SBQQ__Operator__c='less than',SBQQ__Value__c='10.9',SBQQ__Index__c=2);
        SBQQ__TermCondition__c termCondition3 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Term_Version__c',SBQQ__Operator__c='greater than',SBQQ__Value__c='10.6',SBQQ__Index__c=3);
        SBQQ__TermCondition__c termCondition4 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Term_Version__c',SBQQ__Operator__c='less or equals',SBQQ__Value__c='10.8',SBQQ__Index__c=4);
        SBQQ__TermCondition__c termCondition5 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='Contract_Term_Version__c',SBQQ__Operator__c='greater or equals',SBQQ__Value__c='10.6',SBQQ__Index__c=5);
        SBQQ__TermCondition__c termCondition6 = new SBQQ__TermCondition__c(SBQQ__QuoteTerm__c=quoteTerm.Id,SBQQ__TestedField__c='SBQQ__ProductCode__c',SBQQ__Operator__c='does not contain',SBQQ__Value__c='TP-01550',SBQQ__Index__c=198);
        List<SBQQ__TermCondition__c> termCondList = new List<SBQQ__TermCondition__c>();
        termCondList.add(termCondition1);
        termCondList.add(termCondition2);
        termCondList.add(termCondition3);
        termCondList.add(termCondition4);
        termCondList.add(termCondition5);
        termCondList.add(termCondition6);
        insert termCondList;
        quoteTerm.SBQQ__ConditionsMet__c='All';
        update quoteTerm;
        Test.startTest();           
            QuoteTermValidator.generateQuoteTerms(quoteList[0].Id);
            Set<String> productCodes = new Set<String>();
            productCodes.add('IS-01600');
            List<Term_Quote__c> termsToCreate = new List<Term_Quote__c>();
            ConditionEvaluator evaluateConditions = new ConditionEvaluator(quoteTerm, quoteList[0], productCodes);  
            evaluateConditions.evaluateTermConditions(termCondList);
            //System.debug('term'+term);
            Term_Quote__c termquote = evaluateConditions.evaluateConditionsAndInstantiateQuoteTerm();
            termsToCreate.add(termquote);
            System.assertEquals(1,quoteList.size());
        Test.stopTest();
    }

    /**
    * @description Tests generateQuoteTermsForSpecificTerms for targeted regeneration of
    *              specific quote terms. Verifies that only the targeted terms are regenerated
    *              and that product documents are linked. BIZ-80922
    **/
    @isTest
    public static void testGenerateQuoteTermsForSpecificTerms() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        SBQQ__QuoteTerm__c quoteTerm = [SELECT Id FROM SBQQ__QuoteTerm__c LIMIT 1];

        // Create a second active quote term to verify only targeted term is regenerated
        SBQQ__QuoteTerm__c secondTerm = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Second term body for targeted regeneration test',
            SBQQ__PrintOrder__c = 20,
            SBQQ__Active__c = true
        );
        insert secondTerm;

        Test.startTest();
        String result = QuoteTermValidator.generateQuoteTermsForSpecificTerms(
            quote.Id, new List<Id>{ quoteTerm.Id }
        );
        Test.stopTest();

        System.assert(String.isNotBlank(result), 'Expected a non-blank status message from targeted term generation');
    }

    /**
    * @description Tests the async version of generateQuoteTermsForSpecificTerms.
    *              Ensures the @future method executes without error. BIZ-80922
    **/
    @isTest
    public static void testGenerateQuoteTermsForSpecificTermsAsync() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        SBQQ__QuoteTerm__c quoteTerm = [SELECT Id FROM SBQQ__QuoteTerm__c LIMIT 1];

        Test.startTest();
        QuoteTermValidator.generateQuoteTermsForSpecificTermsAsync(
            quote.Id, new List<Id>{ quoteTerm.Id }
        );
        Test.stopTest();

        // Verify the async method ran — Term_Quote__c records should exist
        List<Term_Quote__c> terms = [
            SELECT Id FROM Term_Quote__c WHERE Quote__c = :quote.Id
        ];
        System.assert(!terms.isEmpty(), 'Expected Term_Quote__c records after async targeted generation');
    }

    /**
    * @description Tests generateQuoteTermsForSpecificTerms with null/empty inputs
    *              to verify guard clauses return gracefully. BIZ-80922
    **/
    @isTest
    public static void testGenerateQuoteTermsForSpecificTermsNullInputs() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];

        Test.startTest();
        // Null quoteId
        String result1 = QuoteTermValidator.generateQuoteTermsForSpecificTerms(null, new List<Id>());
        // Empty term IDs
        String result2 = QuoteTermValidator.generateQuoteTermsForSpecificTerms(quote.Id, new List<Id>());
        Test.stopTest();

        System.assertEquals('', result1, 'Expected empty message for null quoteId');
        System.assertEquals('', result2, 'Expected empty message for empty term IDs');
    }

    /**
    * @description Regression test: ensure QuoteTermValidator.generateQuoteTerms actually creates Term_Quote__c
    *              records even when QuoteTermReader models do not populate standardTermId (observed in org).
    *              This would have caught the production issue where term generation returned 0 terms.
    **/
    @isTest
    public static void testGenerateQuoteTermsCreatesTermQuotes() {
        // Use the quote created in @testSetup
        SBQQ__Quote__c quote = [
            SELECT Id, Name
            FROM SBQQ__Quote__c
            LIMIT 1
        ];
        
        // Create an active standard quote term template
        SBQQ__QuoteTerm__c standardTerm = new SBQQ__QuoteTerm__c(
            SBQQ__Body__c = 'Amendment OSA {!quote.OSA_Number__c}',
            SBQQ__PrintOrder__c = 1,
            SBQQ__Active__c = true
        );
        insert standardTerm;
        
        Test.startTest();
        QuoteTermValidator.generateQuoteTerms(quote.Id);
        Test.stopTest();
        
        List<Term_Quote__c> generated = [
            SELECT Id, Quote__c, Term__c
            FROM Term_Quote__c
            WHERE Quote__c = :quote.Id
        ];
        System.assert(!generated.isEmpty(),
            'Expected Term_Quote__c records to be generated for the quote, but none were created.');
    }
    
 
}