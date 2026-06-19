public class AssignDefaultApproversController {
    String contractId;
    public boolean isError {get; set;}
    //public Flow.Interview.Contract_Approvers_Assignment_Flow flow;
    private final String APPROVAL_STATUS_PENDING = 'Pending';
    private final String APPROVAL_STATUS_APPROVED = 'Approved';
    
    ApexPages.StandardController standardController;

    public AssignDefaultApproversController(ApexPages.StandardController standardController){
        this.standardController = standardController;
        contractId = ApexPages.currentPage().getParameters().get('id');
        isError = false;
    }
    
    public PageReference doProcessContractDefaultApprovers(){
        
        try{
            Contract contract = [SELECT Id
                                 , Approval_Status__c
                                 , SBQQ__Quote__r.ApprovalStatus__c 
                                FROM Contract
                                WHERE Id = :contractId LIMIT 1];
            
            if(contract.SBQQ__Quote__c == null 
               || (contract.SBQQ__Quote__r.ApprovalStatus__c != APPROVAL_STATUS_APPROVED 
                  && contract.SBQQ__Quote__r.ApprovalStatus__c != APPROVAL_STATUS_PENDING)){
                isError = true;
                String errorMsg = System.Label.Error_on_Contract_Assigned;
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR, errorMsg));
            }
            else if(contract.Approval_Status__c == APPROVAL_STATUS_PENDING){
                isError = true;
                String errorMsg1 = System.Label.Error_on_Approval_Status;
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR, errorMsg1));
            }
            else{
                map<String, String> recordMap = new map<String, String>();
                recordMap.put('recordId', contractId);
                // flow = new Flow.Interview.Contract_Approvers_Assignment_Flow(recordMap);
                // flow.start();
                PageReference pageref = new PageReference('/'+contractId);
                pageref.setRedirect(true);
                return pageref;
            }
            
            return null;
        }
        catch(Exception ex){
            isError = true;
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR, ex.getMessage() ));
        }
        return null;
    }
    
    public PageReference goBack(){
        PageReference pageref = new PageReference('/'+contractId);
        pageref.setRedirect(true);
        return pageref;
    }
}