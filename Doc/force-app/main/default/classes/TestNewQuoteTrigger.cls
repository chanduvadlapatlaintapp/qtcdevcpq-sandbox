/**
* @author venkat.sriram@intapp.com
* @description test class for NewQuoteTrigger
*/ 
@isTest public class TestNewQuoteTrigger  {
	
	@isTest static void testCurrencyISOCodeUpdateonQuote() {
		Account acc = IntappTestObjectFactory.createAccount(true);

		Contact con = IntappTestObjectFactory.createContact(true);
		con.AccountId = acc.Id;
		update con;

		Contract ctr = IntappTestObjectFactory.createContract(acc.Id);
		insert ctr;

		Opportunity opp = IntappTestObjectFactory.createOpportunity();
		opp.AccountId = acc.Id;
		opp.Associated_Contract_OSA__c = ctr.Id;
		opp.Contract_Signer__c = con.Id;
		opp.Requested_Contract_Expiration__c = Date.today();
		opp.Initial_Software_Term_Length_Months__c = 12;
		insert opp;
		
		SBQQ__Quote__c newQuote = IntappTestObjectFactory.createSBQQQuote();
		newQuote.SBQQ__Opportunity2__c = opp.Id;
		newQuote.SBQQ__Account__c = acc.Id;
        newQuote.SBQQ__SubscriptionTerm__c =36;
        newQuote.First_Segment_Months__c = 12;
		newQuote.License_Basis__c = 'Lawyers';
		insert newQuote;
        
        // added by Sun 
        newQuote.First_Segment_Months__c = 24;
        update newQuote;
        
        System.assertEquals(opp.Associated_Contract_OSA__c, ctr.Id);
	}

}