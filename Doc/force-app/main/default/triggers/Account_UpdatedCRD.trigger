/*
Trigger Name: Account_UpdatedCRD
Description: 
Author/Date: Alan Westley
Release: 
Purpose: 
Change History:
Date			Author			Description
----------------------------------------------------------------------------------------------------------------------------
1/30/2018	    Venkat			Commenting out the whole trigger because it is inactive and hence reduces the code coverage
*/
trigger Account_UpdatedCRD on Account (before update) {
    /*
	List<Subscription__c> subsToUpdate = new List<Subscription__c>();
    
    for (Account a: Trigger.new)
    {
        Account oldAcct = Trigger.oldMap.Get(a.Id);
        
        if (oldAcct.CRD__c != a.CRD__c)
        {
            List<Subscription__c> subs = [SELECT Id, CRD__c FROM Subscription__c WHERE Account__c = :a.Id];
        
            for(Subscription__c sub: subs)
            {
                if (sub.CRD__c != a.CRD__c)
                {
                    sub.CRD__c = a.CRD__c;
                    subsToUpdate.add(sub);
                }
            }
        }
    }
    
    if (subsToUpdate.size() > 0)
    {
        update subsToUpdate;
    }
	*/
}