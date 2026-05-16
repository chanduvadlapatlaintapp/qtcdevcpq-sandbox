/**
* @description       : This class is a Helper class for ApprovalTrigger.
* @author            : Business Applications
* Created Date       : 
**/
public class ApprovalTriggerHandler {
    public Static void approvalAfterInsert(list<SBAA__Approval__c> approvalNewList) {
        Set<Id> approvalIdSet = new Set<Id>();
        for(SBAA__Approval__c approvalRec: approvalNewList){
            approvalIdSet.add(approvalRec.Id);
        }
        //Updated By - BIZ-66415
        //QuoteTriggerHandler.publishApprovalRecords(approvalIdSet);
        QuoteTriggerHelper.publishApprovalRecords(approvalIdSet);
    }
    
    public Static void approvalAfterUpdate(list<SBAA__Approval__c> approvalNewList,Map<Id,SBAA__Approval__c> approvalOldMap) {
        Set<Id> approvalIdSet = new Set<Id>();
        for(SBAA__Approval__c approvalRec : approvalNewList){
            if((approvalRec.OP4I_System_Id__c != null || approvalRec.OP4I_Error__c != null) 
                && (approvalRec.sbaa__AssignedTo__c != approvalOldMap.get(approvalRec.Id).sbaa__AssignedTo__c 
                    || approvalRec.sbaa__ApprovedBy__c != approvalOldMap.get(approvalRec.Id).sbaa__ApprovedBy__c
                    || approvalRec.sbaa__Status__c != approvalOldMap.get(approvalRec.Id).sbaa__Status__c
                    || approvalRec.sbaa__CommentsLong__c != approvalOldMap.get(approvalRec.Id).sbaa__CommentsLong__c)
                 ){
                    approvalIdSet.add(approvalRec.Id);
                }
        }
        //Updated By - BIZ-66415
        //QuoteTriggerHandler.publishApprovalRecords(approvalIdSet);
        QuoteTriggerHelper.publishApprovalRecords(approvalIdSet);
    }   
}