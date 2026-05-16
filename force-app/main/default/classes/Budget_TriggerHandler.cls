public class Budget_TriggerHandler {
    
    public static void beforeInsert(List<Budget__c> budgets){
        linkWithProject(budgets);
    }  
    
    public static void beforeUpdate(List<Budget__c> budgets){
        linkWithProject(budgets);
    }
    
    public static void afterInsert(List<Budget__c> budgets){
        linkOppWithBudget(budgets);
    }  
    
    public static void afterUpdate(List<Budget__c> budgets){
        linkOppWithBudget(budgets);
    }
    
    public static void linkWithProject(List<Budget__c> budgets){
        Map<Id, Id> Map_OppId_ProjectId = new Map<Id, Id>();
        Set<String> OA_ProjectIds = new Set<String>();
        Map<String, Id> OA_Projects = new Map<String, Id>();
        
        for(Budget__c budget: budgets){    
            OA_ProjectIds.add(budget.OA_Project_Internal_ID__c);
            if(budget.Opportunity__c != null){
                //Opportunity:Project is Many:1
                Map_OppId_ProjectId.put(budget.Opportunity__c, null);
            }
        }
        
        for(Project__c proj : [Select Id, Open_Air_Project_ID__c 
                                from Project__c 
                                where Open_Air_Project_ID__c in : OA_ProjectIds]){
              OA_Projects.put(proj.Open_Air_Project_ID__c, proj.Id);                     
        }
        
        for(Opportunity opp: [Select Id, Project__c 
                              from Opportunity
                              where Id in : Map_OppId_ProjectId.keySet()]){
              Map_OppId_ProjectId.put(opp.Id, opp.Project__c);                                  
        }
        
        //Update Budgets with Project ID
        for(Budget__c budget: budgets){    
            if(budget.OA_Project_Internal_ID__c != null)
                budget.Project__c = OA_Projects.get(budget.OA_Project_Internal_ID__c);
            else if(budget.Opportunity__c != null)
                budget.Project__c = Map_OppId_ProjectId.containsKey(budget.Opportunity__c)? Map_OppId_ProjectId.get(budget.Opportunity__c) : null;

        }
    }
    
    public static void linkOppWithBudget(List<Budget__c> budgets){
        List<Opportunity> OppsToUpdate = new List<Opportunity>();
        Map<Id, Id> Map_OppId_BudgetId = new Map<Id, Id>();
        
        for(Budget__c budget: budgets){    
            if(budget.Opportunity__c != null){
                //Opportunity:Budget is 1:1
                Map_OppId_BudgetId.put(budget.Opportunity__c, budget.Id);
            }
        }
        
        for(Opportunity opp: [Select Id, Project__c, Budget__c
                              from Opportunity
                              where Id in : Map_OppId_BudgetId.keySet()]){
                                  opp.Budget__c = Map_OppId_BudgetId.containsKey(opp.Id)? Map_OppId_BudgetId.get(opp.Id) :null;
                                  OppsToUpdate.add(opp);
                              }
        
        if(OppsToUpdate.size() > 0) update OppsToUpdate;
    }
}