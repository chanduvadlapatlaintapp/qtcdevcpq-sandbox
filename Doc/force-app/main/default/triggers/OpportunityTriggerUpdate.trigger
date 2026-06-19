/**
    * OpportunityTriggerUpdate - <description>
    * Created by BrainEngine Cloud Studio
    * @author: Alan Westley
    * @version: 1.0
    * This trigger handles updating the subscription's "Earliest won Opportunity Date" when the Opportunity Subscription lookup value changes
*/

trigger OpportunityTriggerUpdate on Opportunity (after update) {
    List<Subscription__c> subsToUpdate = new List<Subscription__c>();
    
    for (Opportunity opp: Trigger.new)
    {
        if (Trigger.oldMap.size() > 0)
        {
            Opportunity oldOpp = Trigger.oldMap.Get(opp.Id);
            
            if (oldOpp.Subscription__c != opp.Subscription__c && oldOpp.Subscription__c != null)
            {
                /*
                    Update old subscription:
                        Get old subscription. Run query to get new earliest won date
                */
                Subscription__c oldSubscription = [select Id, Earliest_Won_Opportunity__c FROM Subscription__c WHERE Id = :oldOpp.Subscription__c LIMIT 1];
                if (oldSubscription.Earliest_Won_Opportunity__c == oldOpp.Id)
                {
                    List<Opportunity> oldSubOpportunityList = [SELECT Id, CloseDate from Opportunity 
                                                    WHERE Subscription__c = :oldOpp.Subscription__c 
                                                    AND StageName = 'Closed Won' 
                                                    AND Id NOT IN (:Opp.Id)
                                                    ORDER BY CloseDate ASC LIMIT 1];
                    if (oldSubOpportunityList.size() > 0)
                    {

                        oldSubscription.Earliest_Won_Opportunity__c = oldSubOpportunityList[0].Id;
                        subsToUpdate.add(oldSubscription);
                    }
                }       
            }
        }
            
        /* 
            Update new subscription:
                Get new subscription. Run query to get new earliest won date
        */
        if (opp.Subscription__c != null)
        {
            //Get New Subscription information
            Subscription__c newSubscription = [select Id, Earliest_Won_Opportunity__c, Earliest_Won_Opportunity__r.CloseDate FROM Subscription__c WHERE Id = :opp.Subscription__c LIMIT 1];
            if (newSubscription.Earliest_Won_Opportunity__c == null)
            {
                newSubscription.Earliest_Won_Opportunity__c = opp.Id;
                subsToUpdate.add(newSubscription);
            }
            else
            {
                if (opp.CloseDate < newSubscription.Earliest_Won_Opportunity__r.CloseDate)
                {
                    newSubscription.Earliest_Won_Opportunity__c = opp.Id;
                    subsToUpdate.add(newSubscription);
                }
            }
        }   
    }
    
    if (subsToUpdate.size() > 0)
    {
        update subsToUpdate;
    }
}