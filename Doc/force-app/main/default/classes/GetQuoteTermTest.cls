@isTest
private class GetQuoteTermTest {   
    
    @isTest
    static void testGetQuoteTerms() {
        Account account = (Account) SmartFactory.createSObject('Account');
        account.Industry = 'Test Industry';
        account.BillingCountry = 'Test';
        insert account;
        
        Contact con = (Contact) SmartFactory.createSObject('Contact');
        con.AccountId = account.Id; 
        insert con;
        
        Contract ctr = (Contract) SmartFactory.createSObject('Contract');
        ctr.AccountId = account.Id;
        insert ctr;
        
        Opportunity opportunity = (Opportunity) SmartFactory.createSObject('Opportunity');
        opportunity.AccountId = account.Id;
        opportunity.Associated_Contract_OSA__c = ctr.Id;
        opportunity.Contract_Signer__c = con.Id;
        opportunity.Requested_Contract_Expiration__c = Date.today();
        opportunity.Initial_Software_Term_Length_Months__c = 12;
        insert opportunity;
              
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.SBQQ__Opportunity2__c = opportunity.Id;
        newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = system.today();
        insert newQuote;
        
        GetQuoteTerm genObj = new GetQuoteTerm();
        genObj.relatedId = newQuote.Id;
        
        SBQQ__QuoteTerm__c qt1 = new SBQQ__QuoteTerm__c();
        qt1.SBQQ__Body__c = '<p>This is test body.</p>';
        qt1.SBQQ__Quote__c = newQuote.id;
        qt1.SBQQ__PrintOrder__c = 10;
        insert qt1;
        
        Test.startTest();
        List<SBQQ__QuoteTerm__c> lstQuoteTerms = genObj.getlstQuoteTerms();
        system.assertEquals(lstQuoteTerms[0].SBQQ__Body__c,'This is test body.');
        Test.stopTest();
    }
}