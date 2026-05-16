@isTest
public class ApproverMatrixServiceInvocableTest {
    @testSetup
    static void setupTestData(){
        List<Approvers_Matrix__c> Matrix = new List<Approvers_Matrix__c>();
        Approvers_Matrix__c AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='SVP Services';
        AppMatrix.Deal_ACV_Upper_Limit__c = 11000;
        AppMatrix.Approver_User__c = userinfo.getUserId();
        Matrix.add(AppMatrix);
        AppMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix.Approver_Role__c ='Services Segment Lead';
        AppMatrix.Deal_ACV_Upper_Limit__c = 11000;
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
    
    @isTest static void getApproverUsersListVerify(){
        // Arrange
        List<GetApproverUsersRequestWrapper> wrapperList = new List<GetApproverUsersRequestWrapper>();
        GetApproverUsersRequestWrapper wrapper = new GetApproverUsersRequestWrapper();
        wrapper.SalesSegment = '03-Legal EMEA';
        wrapper.DealAcv = 11000;
        wrapperList.add(wrapper);
        
        // Act
        List<ApproverUsers> ApproverUsersList = ApproverMatrixServiceInvocable.getApproverUsersList(wrapperList);
        
        // Assert
        system.Assert(userinfo.getUserId() == ApproverUsersList[0].Services_Segment_Lead);
    }  
}