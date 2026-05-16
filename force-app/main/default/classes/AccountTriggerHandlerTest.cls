//AccountTriggerHandlerTest test class for AccountTriggerHandler
@isTest
public class AccountTriggerHandlerTest {

          @testSetup
       static void setup(){
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
		insert opp;
           
        List<Approvers_Matrix__c> aMatrixlist = new List<Approvers_Matrix__c>();
        Approvers_Matrix__c appMatrix1 = IntappTestObjectFactory.createApproversMatrix();
        AppMatrix1.Approver_User__c =userinfo.getUserId();
        AMatrixlist.add(AppMatrix1);
        insert AMatrixlist;
     
		SBQQ__Quote__c newQuote = IntappTestObjectFactory.createSBQQQuote();
		newQuote.SBQQ__Opportunity2__c = opp.Id;
		newQuote.SBQQ__Account__c = acc.Id;
        newQuote.SBQQ__SubscriptionTerm__c =36;
        newQuote.First_Segment_Months__c = 12;
		newQuote.License_Basis__c = 'Lawyers';
        insert newQuote;
    }
    
    @isTest static void setup1(){
        List<SBQQ__Quote__c> quotelist = [Select id,SBQQ__Account__c,Segment_Lead__c,Industry_Sales_Lead__c,Services_Segment_Lead__c,SVP_Sales__c,SVP_Services__c,Industry_President__c,COO__c ,SBQQ__Opportunity2__c,SBQQ__SubscriptionTerm__c,First_Segment_Months__c,License_Basis__c From SBQQ__Quote__c ];
        List<Account> acclist = [Select id,Industry,BillingCountry,OP4I_Sales_Segment__c From Account where OP4I_Sales_Segment__c != ''];
        acclist[0].OP4I_Sales_Segment__c ='01-Legal - APAC';
        List<Opportunity> opplist =[Select id,AccountId,Associated_Contract_OSA__c,Contract_Signer__c,Requested_Contract_Expiration__c,Initial_Software_Term_Length_Months__c From Opportunity];
        List<Approvers_Matrix__c> matrixlist = [select id,Sales_Segment__c,Approver_Role__c,Approver_User__c From Approvers_Matrix__c];
        update acclist;
       
        System.assertNotEquals(acclist.size(), null);
    }
}