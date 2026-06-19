public class ApproverMatrixServiceInvocable {
    @InvocableMethod(label='Get Approver Users List Invocable')
    public static List<ApproverUsers> getApproverUsersList(List<GetApproverUsersRequestWrapper> wrapperList){
        
        String salesSegment = wrapperList[0].salesSegment;
        Double dealAcv = wrapperList[0].DealAcv;
        List<ApproverUsers> approverUsersList = new List<ApproverUsers>();
        
        List<Approvers_Matrix__c> approversMatrices = [SELECT Id
                                                            , Sales_Segment__c
                                                            , Approver_Role__c
                                                            , Approver_User__c
                                                            , Deal_ACV_Upper_Limit__c 
                                                       FROM Approvers_Matrix__c
                                                       WHERE Sales_Segment__c = :salesSegment
                                                       ORDER BY  Deal_ACV_Upper_Limit__c 
                                                       ASC
                                                       NULLS LAST];

        Map<String, Id> roleApprovalMatrixMap = new Map<String, Id>();

        for(Approvers_Matrix__c matrix : approversMatrices){
            if(matrix.Deal_ACV_Upper_Limit__c != null
                && dealAcv <= matrix.Deal_ACV_Upper_Limit__c
                && !roleApprovalMatrixMap.containsKey(matrix.Approver_Role__c)){
                roleApprovalMatrixMap.put(matrix.Approver_Role__c, matrix.Approver_User__c);
            }
            else if(
                matrix.Deal_ACV_Upper_Limit__c == null
                && !roleApprovalMatrixMap.containsKey(matrix.Approver_Role__c)){
                roleApprovalMatrixMap.put(matrix.Approver_Role__c, matrix.Approver_User__c);
            }
        }
       
        ApproverUsers currentApproversMatrix = new ApproverUsers();
        for(Approvers_Matrix__c matrix : approversMatrices){
            
            if(matrix.Approver_Role__c == 'COO'){
                currentApproversMatrix.COO = roleApprovalMatrixMap.get(matrix.Approver_Role__c);
            }
            else if(matrix.Approver_Role__c == 'Segment Lead'){
                currentApproversMatrix.Segment_Lead = roleApprovalMatrixMap.get(matrix.Approver_Role__c);                
            }
            else if(matrix.Approver_Role__c == 'Industry Sales Lead'){
                currentApproversMatrix.Industry_Sales_Lead = roleApprovalMatrixMap.get(matrix.Approver_Role__c);
            }
            else if(matrix.Approver_Role__c == 'SVP Sales'){
                currentApproversMatrix.SVP_Sales = roleApprovalMatrixMap.get(matrix.Approver_Role__c);                
            }
            else if(matrix.Approver_Role__c == 'Industry President'){
                currentApproversMatrix.Industry_President = roleApprovalMatrixMap.get(matrix.Approver_Role__c);                
            }
            else if(matrix.Approver_Role__c == 'Services Segment Lead'){
                currentApproversMatrix.Services_Segment_Lead = roleApprovalMatrixMap.get(matrix.Approver_Role__c);                
            }
            else if(matrix.Approver_Role__c == 'SVP Services'){
                currentApproversMatrix.SVP_Services = roleApprovalMatrixMap.get(matrix.Approver_Role__c);                
            }
        }
        approverUsersList.add(currentApproversMatrix);
        return approverUsersList;
    }
}