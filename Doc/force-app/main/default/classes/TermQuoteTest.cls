@isTest
public class TermQuoteTest {
    
    testmethod static void testTermQuotes(){
        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        quote.Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75);
        insert quote;
        
        Term_Quote__c termQuote = new Term_Quote__c();
        termQuote.Body__c = '<p>This is a test method </p>';
        termQuote.Quote__c = quote.Id;
        insert termQuote;
        
        termQuote.Body__c = '<p>This is test method testing..</p>';
        update termQuote;
        
        System.assertEquals(termQuote.Body__c,'<p>This is test method testing..</p>');
    } 

}