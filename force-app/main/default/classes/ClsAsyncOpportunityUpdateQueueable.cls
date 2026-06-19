public class ClsAsyncOpportunityUpdateQueueable implements Queueable{
    private List<Opportunity> lstOpportunity;
    private Id opportunityId;

    public ClsAsyncOpportunityUpdateQueueable(List<Opportunity> lstOpportunity, Id opportunityId){
        this.lstOpportunity = lstOpportunity;
        this.opportunityId = opportunityId;
    }
    
    public void execute(QueueableContext context) {
        Database.SaveResult[] results;
        try{            
            results = Database.update(lstOpportunity);
        }
        catch(Exception e){
            HandleCustomException.logDatabaseErrors(results);
        }     
    }
}