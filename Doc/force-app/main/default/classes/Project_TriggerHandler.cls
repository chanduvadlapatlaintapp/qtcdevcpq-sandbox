public class Project_TriggerHandler {
    
    public static void beforeInsert(List<Project__c> projects){
        linkWithAccount(projects);
    }
    
    public static void beforeUpdate(List<Project__c> projects){
        linkWithAccount(projects);
    }
    
    public static void afterInsert(List<Project__c> projects){
        linkOpptWithProject(projects);
    }
    
    public static void afterUpdate(List<Project__c> projects){
        linkOpptWithProject(projects);
    }
    
    public static void linkWithAccount(List<Project__c> projects){
        List<id> OppIds = new List<Id>();
        Map<Id, Id> map_oppId_accId = new Map<id, id>();
        for(Project__c proj: projects){
            if(proj.Opportunity__c != null){
                OppIds.add(proj.Opportunity__c);
            }
        }
        
        for(Opportunity opp: [Select Id, AccountId 
                                from Opportunity 
                               where Id in : OppIds]){
            map_oppId_accId.put(opp.Id, opp.AccountId);
        }
        
        for(Project__c proj: projects){
            if(proj.Opportunity__c != null && map_oppId_accId.containsKey(proj.Opportunity__c)){
                proj.Account__c = map_oppId_accId.get(proj.Opportunity__c);
            }
        }
    }
    
    public static void linkOpptWithProject(List<Project__c> projects){
        
        List<Opportunity> OppsToUpdate = new List<Opportunity>();
        Map<Id, Id> Map_OpportunityId_ProjectId = new Map<Id, Id>();
        
        for(Project__c proj: projects){
            if(proj.Opportunity__c != null)
                Map_OpportunityId_ProjectId.put(proj.Opportunity__c, proj.Id);    
        }
        
        for(Opportunity opp: [Select Id, Project__c
                             from Opportunity
                             where Id in : Map_OpportunityId_ProjectId.keyset()]){
                                  if(Map_OpportunityId_ProjectId.containsKey(opp.Id) && opp.Project__c !=  Map_OpportunityId_ProjectId.get(opp.Id)){
                                      opp.Project__c = Map_OpportunityId_ProjectId.containsKey(opp.Id)? Map_OpportunityId_ProjectId.get(opp.Id) : null;
                                      OppsToUpdate.add(opp);
                                  }
                              }
        
        if(OppsToUpdate.size() > 0){
            update OppsToUpdate;    
        }
    }
}