@isTest
public class ApproverMatrixServiceTest {
    @testSetup
    static void setupTestData(){
        List<Approvers_Matrix__c> Matrix = new List<Approvers_Matrix__c>();
        Approvers_Matrix__c AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='SVP Services';
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='Services Segment Lead';
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='Industry President';
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='Industry Sales Lead';
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='Segment Lead';
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='COO';
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='SVP Sales';
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        insert Matrix;
       
    }
    
    @isTest static void getApproverUsersList_Verify(){
        // Arrange
        List<Approvers_Matrix__c> AppMatrix1 = [Select id
                                                ,Approver_Role__c
                                                ,Sales_Segment__c
                                                ,Approver_User__c 
                                                From Approvers_Matrix__c];
        
        List<ApproverUsers> approverUsersList = new List<ApproverUsers>();
        
        // Act
        approverUsersList = ApproverMatrixService.getApproverUsersList(new List<string>{'03-Legal EMEA'});
        
        // Assert
        system.Assert(userinfo.getUserId() == approverUsersList[0].Services_Segment_Lead);
    }    
    
    @isTest static void getApproverUsers_Verify(){
        // Arrange
        List<Approvers_Matrix__c> approversMatrices = [Select id
                                                       ,Approver_Role__c
                                                       ,Sales_Segment__c
                                                       ,Approver_User__c 
                                                       From Approvers_Matrix__c
                                                       WHERE Sales_Segment__c ='03-Legal EMEA'];
        
        Map<String, ApproverUsers> approverUsersMap = new Map<String, ApproverUsers>();
        ApproverUsers currentApproversMatrix = new ApproverUsers();
		
        // Act
		approverUsersMap = ApproverMatrixService.getApproverUsers(new set<string>{'03-Legal EMEA'});

        for(Approvers_Matrix__c matrix : approversMatrices){
            if(approverUsersMap.containsKey(matrix.Sales_Segment__c)){
                currentApproversMatrix = approverUsersMap.get(matrix.Sales_Segment__c);
            }
        }
        
        // Assert
        system.Assert(userinfo.getUserId() == currentApproversMatrix.Services_Segment_Lead);
    }    
}