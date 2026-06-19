public with sharing class PendingApprovalController {
    public id usrId{get;set;}
    
    //String TargetLink = domain + '/' + string.valueof(piwItem.ProcessInstance.TargetObjectId);
    public string domain{get{return URL.getSalesforceBaseUrl().toExternalForm();}set;}
    
    public Class resultWrapper {
        public Contract contract {get;set;}
        public ProcessInstanceWorkitem pwi{get;set;}
        
        public resultWrapper (Contract contract, ProcessInstanceWorkitem pwi) {
            this.contract = contract;
            this.pwi = pwi;
        }
    }
    
    public List<resultWrapper> getPendingApprovals() {
        List<resultWrapper> lstResults = new List<resultWrapper> ();
        if (usrId != null) {
            List<ProcessInstanceWorkitem> lstPWI = [Select  p.ProcessInstance.Status, p.ProcessInstance.TargetObject.Name, 
                                                            p.ProcessInstance.TargetObjectId, p.ProcessInstance.TargetObject.Type, p.ProcessInstance.Id, 
                                                            p.ProcessInstanceId, p.Actor.Email, p.Actor.Name, p.ActorId, p.OriginalActorId, 
                                                            p.Id, ProcessInstance.CreatedDate
                                                    From ProcessInstanceWorkitem p
                                                    WHERE ProcessInstance.Status = 'Pending' AND ProcessInstance.IsDeleted = False  
                                                    AND ProcessInstance.SystemModStamp <= Today AND ProcessInstance.TargetObject.type='Contract'
                                                    And actor.Id = :usrId
                                                    Order by p.Actor.Email];
            Set<Id> contractIds = new Set<Id> ();
            for (ProcessInstanceWorkitem pwi : lstPWI) {
                contractIds.add(pwi.ProcessInstance.TargetObjectId);                                                                
            }
            
            Map<Id, Contract> mapContract = new Map<Id, Contract> (
                [   Select id, Account.Name, ContractNumber, Status, EndDate, Approval_Request_Notes__c
                    From Contract 
                    Where id in :contractIds]);
            
            for (ProcessInstanceWorkitem pwi : lstPWI) {
                lstResults.add(new resultWrapper (mapContract.get(pwi.ProcessInstance.TargetObjectId), pwi));                                                                       
            }
        }
        return lstResults;
    }
    
}