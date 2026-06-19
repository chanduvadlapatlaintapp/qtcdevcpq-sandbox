trigger trHotListCaseCount on Case (after delete, after insert, after undelete, after update) {
Case[] cases;
        if (Trigger.isDelete)
            cases = Trigger.old;
        else
            cases = Trigger.new;

        // get list of accounts
        Set<ID> acctIds = new Set<ID>();
        for (Case cse : cases) {
                acctIds.add(cse.AccountId);
        }
       
        Map<ID, Case> casesForAccounts = new Map<ID, Case>([select Id
                                                                ,AccountId
                                                                from Case
                                                                where AccountId in :acctIds and 
                                                                	  Record_Type_Name__c = 'Executive Support' and
                                                                	  Status not in ('Closed - Resolved','Closed - Unresolved','Abandoned','Escalated to Engineering')]);

        Map<ID, Account> acctsToUpdate = new Map<ID, Account>([select Id
                                                                     ,Hot_List_Case_Count__c
                                                                      from Account
                                                                      where Id in :acctIds]);
                                                                    
        for (Account acct : acctsToUpdate.values()) {
            Set<ID> caseIds = new Set<ID>();
            for (Case cse : casesForAccounts.values()) {
                if (cse.AccountId == acct.Id)
                    caseIds.add(cse.Id);
            }
            if (acct.Hot_List_Case_Count__c != caseIds.size())
                acct.Hot_List_Case_Count__c = caseIds.size();
        }

        update acctsToUpdate.values(); 
}