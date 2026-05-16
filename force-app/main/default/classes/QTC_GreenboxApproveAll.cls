public without sharing class QTC_GreenboxApproveAll {
    @InvocableMethod(label='Approve all pending approvals')
    public static List<Id> approveAllOpenApprovals(List<String> lstQuoteId){
        List<sbaa__Approval__c> lstApprovals = new List<sbaa__Approval__c>();
        List<String> lstPendingApprovalStatuses = label.QTC_ApproveAllStatuses.split(',');
        List<SBQQ__Quote__c> quoteListToUpdate = new List<SBQQ__Quote__c>();
        Set<Id> quoteIdSet = new Set<Id>();
        lstApprovals = [SELECT Id,Name,Quote__c FROM sbaa__Approval__c WHERE Quote__c  =: lstQuoteId[0].substringBefore('-$-') AND sbaa__Status__c IN :lstPendingApprovalStatuses];
        if(FeatureManagement.checkPermission('Approve_All')){
            for(sbaa__Approval__c oApproval : lstApprovals){
                oApproval.sbaa__Status__c = 'Approved';
                oApproval.sbaa__CommentsLong__c = lstQuoteId[0].substringAfter('-$-');
                oApproval.sbaa__AssignedTo__c = userInfo.getUserId();
                oApproval.sbaa__ApprovedBy__c = userInfo.getUserId();
                quoteIdSet.add(oApproval.Quote__c);
                system.debug('============'+oApproval.Name);
            }
            for(Id quoteId: quoteIdSet){
                quoteListToUpdate.add(new SBQQ__Quote__c(Id=quoteId, ApprovalStatus__c = 'Approved'));
            }
            system.debug('========='+lstApprovals.size());
            update lstApprovals;
            update quoteListToUpdate;
        }        
        return null;
    }
}