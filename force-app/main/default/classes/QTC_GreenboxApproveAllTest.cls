@isTest
public class QTC_GreenboxApproveAllTest {
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
        
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.OP4I_Sales_Segment__c = '03-Legal EMEA';
        newQuote.SBQQ__Opportunity2__c = opportunity.Id;
        newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.ApprovalStatus__c = 'Pending';
        newQuote.SBQQ__StartDate__c = system.today();
        insert newQuote;
        
        
        
        
    }
    
    @isTest static void processRecords(){   
        Profile pr = [SELECT Id, Name FROM Profile WHERE Name = 'System Administrator'];
        //Contact con = [SELECT Id FROM Contact LIMIT 1]; 
        User user = new User(alias = 'test123', email='test123@noemail.com',
                             emailencodingkey='UTF-8', lastname='Testing', languagelocalekey='en_US',
                             localesidkey='en_US', profileid = pr.Id, country='United States',IsActive =true,
                             timezonesidkey='America/Los_Angeles', username='testrituNagi383@gmail.com');
        
        insert user;
        
        
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Approve_All'];
        
        PermissionSetAssignment psa = new PermissionSetAssignment(
            AssigneeId = user.Id,
            PermissionSetId = ps.Id
            
        );
        insert psa;
       
        Test.startTest();
        System.runAs(user) {
            System.assertEquals(true, FeatureManagement.checkPermission('Approve_All'));
            SBQQ__Quote__c quoteLst = [SELECT Id, ApprovalStatus__c FROM SBQQ__Quote__c LIMIT 1];
            List<String> quoteId = new List<String>();
            //for(SBQQ__Quote__c qt : quoteLst){
                quoteId.add(quoteLst.Id+'-$-');
            //}
            
            sbaa__Approval__c oApproval = new sbaa__Approval__c();
            oApproval.sbaa__Status__c = 'Assigned';
            oApproval.sbaa__AssignedTo__c = user.Id;
            oApproval.sbaa__ApprovedBy__c = user.Id;
            oApproval.sbaa__ApprovalStep__c = 1.00;
            oApproval.sbaa__RecordField__c = '1';
            oApproval.Quote__c = quoteLst.Id;
            insert oApproval;
            
            QTC_GreenboxApproveAll.approveAllOpenApprovals(quoteId); 
        }
        Test.stopTest();
    }
}