@isTest
public class QuoteApproveAllExtControllerTest {
	@testSetup
    static void setup(){
        Account account = IntappTestObjectfactory.createAccount(true);
        
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
        
        Profile profile = [select id from profile where name='System Administrator' LIMIT 1]; 
        User user = createuser('Testing', '', 'test@testintapp.com', profile.Id, 'intapp_1', 'UTF-8', 'en_US', 'en_US', 'America/Los_Angeles', 'stdtusr@testintapp.com', '', true);
        
        Approvers_Matrix__c appMatrix1 = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix1.Sales_Segment__c = '25-FS AM - NA IB Midmarket';
        AppMatrix1.Approver_Role__c = 'Segment Lead';
        AppMatrix1.Approver_User__c = user.Id;
        insert AppMatrix1;
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket';
        newQuote.SBQQ__Opportunity2__c = opportunity.Id;
        newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.Subsidiary__c = '01:200 Integration Appliance (US)';
        newQuote.Bill_To_Account__c =  account.Id;
        newQuote.Ship_To_Account__c =  account.Id;
        newQuote.Quote_Stage__c = 'Configure Products';
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = system.today();
        newQuote.ApprovalStatus__c='Error';
        insert newQuote;
        newQuote.ApprovalStatus__c='Pending';
        newQuote.Counter__c=20;
        update newQuote; 
        system.assertEquals('Pending',newQuote.ApprovalStatus__c);
        

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
      
       	SBQQ__Quote__c quoteLst = [SELECT Id, ApprovalStatus__c FROM SBQQ__Quote__c LIMIT 1];
            
        PageReference pageRef = new PageReference('/'+quoteLst.id);
        Test.setCurrentPage(pageRef);
       	ApexPages.StandardController sc = new ApexPages.StandardController(quoteLst);
        QuoteApproveAllExtController myController = new QuoteApproveAllExtController(sc);
        System.assertEquals(true, FeatureManagement.checkPermission('Approve_All'));
        myController.messageConfirmed();
       	myController.submit();    
           
        }
        Test.stopTest();
    }
    
      private static User createUser(String lastName, string firstName, string email, String profileId, 
                                   string alias, String emailEncodingKey, string languageLocaleKey,
                                   string localeSidKey, string timeZoneSidKey, string userName,
                                   string communityNickname, Boolean create){
                                       User user = new User();
                                       user.LastName = lastName;
                                       user.FirstName = firstName;
                                       user.Email = email;
                                       user.EmailEncodingKey = emailEncodingKey;
                                       user.LanguageLocaleKey = languageLocaleKey;
                                       user.LocaleSidKey = localeSidKey;
                                       user.TimeZoneSidKey = timeZoneSidKey;
                                       user.ProfileId = profileId;
                                       user.Alias = alias;
                                       user.UserName = userName;
                                       user.CommunityNickname = communityNickname + '-' + (Math.random() * 10000);
                                       if(create)
                                       {
                                           insert user;
                                       }
                                       return user;
                                   }
    
}