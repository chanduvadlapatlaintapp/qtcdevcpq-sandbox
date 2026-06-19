/*
    Controller Class for GreenBoxDisplay LWC component. created as part of BIZ-47960
*/
public without sharing class GreenBoxController {

    /*
    Method to fetch Approval matric custom metadata. created as part of BIZ-47960
    */
    @AuraEnabled(cacheable=true)
    public static List<Approval_Level_Matrix__mdt> getCustomMetadata(){
        try {
            List<Approval_Level_Matrix__mdt> mtdt;
            mtdt = new List<Approval_Level_Matrix__mdt>();
            mtdt = [Select Id,Approval_Level__c,Approver_Title__c From Approval_Level_Matrix__mdt];
            return mtdt;           
        } 
        catch (Exception e) {throw new AuraHandledException(e.getMessage());}
    }
    
}