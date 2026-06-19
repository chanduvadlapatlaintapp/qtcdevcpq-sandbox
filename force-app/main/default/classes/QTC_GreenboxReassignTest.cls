@isTest
public class QTC_GreenboxReassignTest {
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
        
        
        sbaa__Approval__c oApproval = new sbaa__Approval__c();
        oApproval.sbaa__Status__c = 'Pending';
        oApproval.sbaa__AssignedTo__c = userInfo.getUserId();
        oApproval.sbaa__ApprovedBy__c = userInfo.getUserId();
        oApproval.sbaa__ApprovalStep__c = 1.00;
        oApproval.sbaa__RecordField__c = '1';
        insert oApproval;
        
        
        sbaa__Approver__c approver = new sbaa__Approver__c();
        approver.sbaa__User__c = UserInfo.getUserId();
        insert approver;
    }
    
    @isTest static void processRecords(){  
        PermissionSetAssignment existingPs;
        for(PermissionSetAssignment psa : [SELECT Id FROM PermissionSetAssignment WHERE PermissionSet.Name = 'Reassign_Approval_To_Me' AND AssigneeId = :UserInfo.getUserId() LIMIT 1]) {
            existingPs = psa;
        }
        if(existingPs == null) {
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Reassign_Approval_To_Me'];
            PermissionSetAssignment psa = new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = ps.Id
            );
            insert psa;
        }
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<sbaa__Approval__c> approvalLst = [SELECT Id FROM sbaa__Approval__c];
            List<Id> approvalId = new List<Id>();
            for(sbaa__Approval__c qt : approvalLst){
                approvalId.add(qt.Id);
            }
            QTC_GreenboxReassign.reassignApproval(approvalId); 
        }
        // Query the approvals after running the method
        List<sbaa__Approval__c> approvalLstAfter = [SELECT Id, sbaa__AssignedTo__c FROM sbaa__Approval__c];
            
        // Assert that the approvals have been reassigned correctly
        for(sbaa__Approval__c approval : approvalLstAfter){
            System.assertEquals(UserInfo.getUserId(), approval.sbaa__AssignedTo__c, 'Approval should be reassigned to the current user');
        }
     }
}