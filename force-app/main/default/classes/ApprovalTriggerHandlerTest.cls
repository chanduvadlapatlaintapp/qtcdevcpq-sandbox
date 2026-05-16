@isTest
public class ApprovalTriggerHandlerTest {

 @testSetup
    static void setup(){
        Account account = (Account) SmartFactory.createSObject('Account');
        account.Industry = 'Test Industry';
        account.BillingCountry = 'Test';
        account.OP4I_Sales_Segment__c = '';
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
        
        Map<String, Map<String, RecordType>> RECORD_TYPES = new Map<String, Map<String, RecordType>> ();
        for (RecordType recType :[SELECT Id, SobjectType, DeveloperName FROM RecordType]) {
            
            if (!RECORD_TYPES.containsKey(recType.SobjectType)) {
                RECORD_TYPES.put(recType.SobjectType, new Map<String, RecordType> ());
            }
            RECORD_TYPES.get(recType.SobjectType).put(recType.DeveloperName, recType);
        }
        
        String recordTypeName = 'Draft_Quote';
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.OP4I_Sales_Segment__c = '03-Legal EMEA';
        newQuote.SBQQ__Opportunity2__c = opportunity.Id;
        newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = system.today();
        newQuote.RecordTypeId = RECORD_TYPES.get('SBQQ__Quote__c').get(recordTypeName).Id;
        insert newQuote;
    }
    private static List<SBQQ__Quote__c> getQuoteList(){
    return [SELECT Id
                  , SBQQ__Account__c
                  , Segment_Lead__c
                  , Industry_Sales_Lead__c
                  , Services_Segment_Lead__c
                  , SVP_Sales__c
                  , SVP_Services__c
                  , Industry_President__c
                  , COO__c
                  , SBQQ__Opportunity2__c
                  , SBQQ__SubscriptionTerm__c
                  , First_Segment_Months__c
                  , License_Basis__c
                  , OP4I_Sales_Segment__c
                  , ApprovalStatus__c,SBQQ__StartDate__c
                FROM SBQQ__Quote__c LIMIT 1];
    }
  	 @isTest static void processRecordsAfterUpdate(){
        List<SBQQ__Quote__c> newQuote = getQuoteList();
        SBAA__Approval__c approvalRec = new SBAA__Approval__c(Quote__c =newQuote[0].Id,OP4I_System_Id__c='Test',sbaa__RecordField__c='Quote__c',sbaa__ApprovalStep__c=1);
        insert approvalRec;
        approvalRec.sbaa__Status__c = 'Requested';
        update approvalRec;
       	System.assertEquals('Requested' , approvalRec.sbaa__Status__c);

     }
   
}