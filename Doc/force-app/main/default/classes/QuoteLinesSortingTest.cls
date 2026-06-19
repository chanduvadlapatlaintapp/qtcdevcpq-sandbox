@isTest
public class QuoteLinesSortingTest {
   @isTest
    static void testMethod1(){       
        Product2 prodObj = (Product2) SmartFactory.createSObject('Product2');
        prodObj.Name = 'Testproduct';
        prodObj.IsActive = true;
        prodObj.ProductCode = '123462';
        insert prodObj;
    
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.OP4I_Sales_Segment__c = '03-Legal EMEA';
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = system.today();
        newQuote.SBQQ__LastCalculatedOn__c = system.now();
        insert newQuote;
        
        SBQQ__QuoteLine__c testqli1 = new SBQQ__QuoteLine__c();
        testqli1.SBQQ__Quote__c = newQuote.Id;
        testqli1.SBQQ__Quantity__c = 1;        
        testqli1.SBQQ__Product__c = prodObj.id;
        testqli1.Print_at_Quote__c = true;
        testqli1.SBQQ__CustomerPrice__c = 25;
        testqli1.SBQQ__NetPrice__c = 10;
        insert testqli1;
        
        SBQQ__QuoteLine__c testqli2 = new SBQQ__QuoteLine__c();
        testqli2.SBQQ__Quote__c = newQuote.Id;
        testqli2.SBQQ__Quantity__c = 5;        
        testqli2.SBQQ__Product__c = prodObj.id;
        testqli2.Print_at_Quote__c = true;
        testqli2.SBQQ__CustomerPrice__c = 25;
        testqli2.SBQQ__NetPrice__c = 15;
        insert testqli2;       
        QuoteLinesSorting.sortQuoteLines(newQuote.id);
        
        Test.StartTest();
        SBQQ__QuoteLine__c qle1 = [Select Id,Quote_Line_Order__c FROM SBQQ__QuoteLine__c WHERE Id =: testqli1.Id];
        SBQQ__QuoteLine__c qle2 = [Select Id,Quote_Line_Order__c FROM SBQQ__QuoteLine__c WHERE Id =: testqli2.Id];
        System.assertEquals(qle2.Quote_Line_Order__c , 1);
        System.assertEquals(qle1.Quote_Line_Order__c , 2);
        Test.StopTest();
    }
}