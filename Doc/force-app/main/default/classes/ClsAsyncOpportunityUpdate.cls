public class ClsAsyncOpportunityUpdate {
    
    @InvocableMethod(label='Update Opportunity Async' description='Updates the Opportunities specified and returns the IDs of the Opportunities' category= 'Opportunity')
    public static void updateOpportunities(List<List<Opportunity>> lstOpportunity) {
        List<Opportunity> lstSingleOpportunity = new List<Opportunity>();
        lstSingleOpportunity = lstOpportunity[0]; 
        if(lstSingleOpportunity[0].id != null){
            System.enqueueJob(new ClsAsyncOpportunityUpdateQueueable(lstSingleOpportunity,lstSingleOpportunity[0].id));
        }               
    }

}