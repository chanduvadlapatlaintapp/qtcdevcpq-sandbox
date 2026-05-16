public class ApproverMatrixService {
    
    
    public static Map<String, ApproverUsers> getApproverUsers(set<String> salesSegments){
        
        Map<String, ApproverUsers> approverUsersMap = new Map<String, ApproverUsers>();
        
        List<Approvers_Matrix__c> approversMatrices = [SELECT Id, Sales_Segment__c, Approver_Role__c, Approver_User__c 
                                                       FROM Approvers_Matrix__c
                                                       WHERE Sales_Segment__c 
                                                       IN :salesSegments ];
        system.debug('approversMatrices');
        for(Approvers_Matrix__c matrix : approversMatrices){
            ApproverUsers currentApproversMatrix = new ApproverUsers();
            if(approverUsersMap.containsKey(matrix.Sales_Segment__c)){
                currentApproversMatrix = approverUsersMap.get(matrix.Sales_Segment__c);
            }
            else{
                approverUsersMap.put(matrix.Sales_Segment__c, currentApproversMatrix);
            }
            
            if(matrix.Approver_Role__c == 'COO'){
                currentApproversMatrix.COO = matrix.Approver_User__c;
            }
            else if(matrix.Approver_Role__c == 'Segment Lead'){
                currentApproversMatrix.Segment_Lead = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'Industry Sales Lead'){
                currentApproversMatrix.Industry_Sales_Lead = matrix.Approver_User__c;
            }
            else if(matrix.Approver_Role__c == 'SVP Sales'){
                currentApproversMatrix.SVP_Sales = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'Industry President'){
                currentApproversMatrix.Industry_President = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'Services Segment Lead'){
                currentApproversMatrix.Services_Segment_Lead = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'SVP Services'){
                currentApproversMatrix.SVP_Services = matrix.Approver_User__c;                
            }
        }
        
        return approverUsersMap;
    }
    
    @InvocableMethod(label='Get Approver Users List')
    public static List<ApproverUsers> getApproverUsersList(List<String> salesSegments){
        
        List<ApproverUsers> approverUsersList = new List<ApproverUsers>();
        
        List<Approvers_Matrix__c> approversMatrices = [SELECT Id, Sales_Segment__c, Approver_Role__c, Approver_User__c 
                                                       FROM Approvers_Matrix__c
                                                       WHERE Sales_Segment__c 
                                                       IN :salesSegments ];
       
        ApproverUsers currentApproversMatrix = new ApproverUsers();
        for(Approvers_Matrix__c matrix : approversMatrices){
            
            if(matrix.Approver_Role__c == 'COO'){
                currentApproversMatrix.COO = matrix.Approver_User__c;
            }
            else if(matrix.Approver_Role__c == 'Segment Lead'){
                currentApproversMatrix.Segment_Lead = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'Industry Sales Lead'){
                currentApproversMatrix.Industry_Sales_Lead = matrix.Approver_User__c;
            }
            else if(matrix.Approver_Role__c == 'SVP Sales'){
                currentApproversMatrix.SVP_Sales = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'Industry President'){
                currentApproversMatrix.Industry_President = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'Services Segment Lead'){
                currentApproversMatrix.Services_Segment_Lead = matrix.Approver_User__c;                
            }
            else if(matrix.Approver_Role__c == 'SVP Services'){
                currentApproversMatrix.SVP_Services = matrix.Approver_User__c;                
            }
        }
        approverUsersList.add(currentApproversMatrix);
        return approverUsersList;
    }
}