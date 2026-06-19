/**
 * See https://github.com/financialforcedev/fflib-apex-common for more info
 *
 * Install library via 
 *   https://githubsfdeploy.herokuapp.com/app/githubdeploy/financialforcedev/fflib-apex-common
 */

/**
 * Encapsulates all behaviour logic relating to the Account object
 * 
 * For more guidelines and details see 
 *   https://developer.salesforce.com/page/Apex_Enterprise_Patterns_-_Domain_Layer
 *
 * 6/24: AW - This class is still under development
 **/
 /**
 Change History:
Date            Author          Description
----------------------------------------------------------------------------------------------------------------------------
1/30/2018       Venkat          #13466 - Ensure when CRD is changed, the new CRD is not null
**/
public class Accounts extends fflib_SObjectDomain 
{
    public Accounts(List<Account> records) 
    {
        super(records); 
        Configuration.disableTriggerCRUDSecurity();
    }

    public override void onValidate()
    {
        for(Account record : (List<Account>) Records)
        {
        }
    }

    public override void onValidate(Map<Id,SObject> existingRecords)
    {
        for(Account record : (List<Account>) Records)
        {
        }
    }

    public void someMethod()
    {
        for(Account record : (List<Account>) Records)
        {
        }       
    }

    public override void onBeforeInsert()
    {
        for(Account record : (List<Account>) Records)
        {
        }
        //IntegrationHandler.CreateProspect((List<Account>) Records);
    }
    
    public override void onAfterInsert()
    {
        for(Account record : (List<Account>) Records)
        {
        }
        //IntegrationHandler.CreateProspect((List<Account>) Records, trigger.isUpdate);
    }
    
    public override void OnBeforeUpdate(Map<Id,SObject> existingRecords)
    {
        //onStatusChangeRemoveAccountManager(existingRecords);
        onOwnerChangeUpdateContactOwners(existingRecords);
        onCRDChangeUpdateSubscriptionCRDs(existingRecords);
        onCRDChangeUpdateProjectCRDs(existingRecords);
        //OnProductOwnershipChange_UpdatePortfolio(existingRecords);
    }
    
    public override void OnAfterUpdate(Map<Id,SObject> existingRecords)
    {
        //IntegrationHandler.CreateProspect((List<Account>) Records, trigger.isUpdate);
    }
    //public void OnProductOwnershipChange_UpdatePortfolio(Map<Id,SObject> existingrecords)
    //{
        
    //  for (Account a: (List<Account>) Records)
    //  {
    //      Account oldAcct = (Account) existingrecords.get(a.Id);

    //      //If Time Capture Own It flag has changed, update Portfolio
    //      if (a.Intapp_Time_Capture__c == 'Own It' && a.Intapp_Time_Capture__c != oldAcct.Intapp_Time_Capture__c)
    //      {
    //          a.Time_Capture_Previous__c = a.Time_Capture__c;
    //          a.Time_Capture__c = 'Intapp Time';
    //      }   
        
    //      //If Time Entry Own It flag has changed, update Portfolio
    //      if (a.Intapp_Time__c == 'Own It' && a.Intapp_Time__c != oldAcct.Intapp_Time__c)
    //      {
    //          a.Time_Entry_Previous__c = a.Time_Entry__c;
    //          a.Time_Entry__c = 'Intapp Time';
    //      }   

    //      //If Walls Own It flag has changed, update Portfolio
    //      if (a.Wall_Builder__c == 'Own It' && a.Wall_Builder__c != oldAcct.Wall_Builder__c)
    //      {
    //          a.Confidentiality_Mgmt_Platform_Previous__c = a.Ethical_Walls_app__c;
    //          a.Ethical_Walls_app__c = 'IntApp Wall Builder';
    //      }

    //      //If Open Intake Own It flag has changed, update Portfolio
    //      if (a.IntApp_Open_Intake__c == 'Own It' && a.IntApp_Open_Intake__c != oldAcct.IntApp_Open_Intake__c)
    //      {
    //          a.Intake_Previous__c = a.Intake__c;
    //          a.Intake__c = 'Intapp Open - Intake';
    //      }   

    //      //If Open Conflicts Own It flag has changed, update Portfolio
    //      if (a.IntApp_Open_Conflicts__c == 'Own It' && a.IntApp_Open_Conflicts__c != oldAcct.IntApp_Open_Conflicts__c)
    //      {
    //          a.Conflicts_Software_Previous__c = a.Conflicts__c;
    //          a.Conflicts__c = 'Intapp Open - Conflicts';
    //      }       
    //  }
    //}

    public void onStatusChangeRemoveAccountManager(Map<Id, SObject> existingrecords){
        for (Account a: (List<Account>) Records){
            Account oldAcct = (Account) existingrecords.get(a.Id);// Trigger.oldMap.Get(a.Id);
            
            if (oldAcct.Type != a.Type && (a.Type == 'Customer - Lapsed' || a.Type == 'Dissolved - Customer')){
                a.CRD__c = null;            
            }
        }
    }

    public void onCRDChangeUpdateSubscriptionCRDs(Map<Id, SObject> existingRecords) {
   	List<Subscription__c> subsToUpdate = new List<Subscription__c>();

   Set<Id> accountIdsToUpdate = new Set<Id>();

   for (Account a : (List<Account>) Records) {
       Account oldAcct = (Account) existingRecords.get(a.Id);

       if (oldAcct.CRD__c != a.CRD__c) {
           accountIdsToUpdate.add(a.Id); 
       }
   }

   Map<Id, List<Subscription__c>> accountSubscriptionsMap = new Map<Id, List<Subscription__c>>();
        List<Subscription__c> subscription = new list<Subscription__c>();
        if(accountIdsToUpdate != null){     
    subscription = [SELECT Id, CRD__c, Account__c FROM Subscription__c WHERE Account__c IN :accountIdsToUpdate];
        }
        if(subscription.size()>0){
   for (Subscription__c sub : subscription) {
       if (!accountSubscriptionsMap.containsKey(sub.Account__c)) {
           accountSubscriptionsMap.put(sub.Account__c, new List<Subscription__c>());
       }
       accountSubscriptionsMap.get(sub.Account__c).add(sub);
   }
  }

   for (Account a : (List<Account>) Records) {
       List<Subscription__c> subs = accountSubscriptionsMap.get(a.Id);
       if (subs != null) {
           for (Subscription__c sub : subs) {
               if (sub.CRD__c != a.CRD__c) {
                   sub.CRD__c = a.CRD__c;
                   subsToUpdate.add(sub);
               }
           }
       }
   }

   if (!subsToUpdate.isEmpty()) {
       update subsToUpdate;
   }
}

    //#13466 FIX - Optimized the whole function
    public void onCRDChangeUpdateProjectCRDs(Map<Id, SObject> existingRecords) {
   Map<Id, String> accIdcrdEmailMap = new Map<Id, String>();
   Map<Id, Set<Id>> userIdAccIdMap = new Map<Id, Set<Id>>();

   for (Account a : (List<Account>) Records) {
       Account oldAcct = (Account) existingRecords.get(a.Id);
       if (oldAcct.CRD__c != a.CRD__c) {
           if (a.CRD__c == null) {
               accIdcrdEmailMap.put(a.Id, null);
           } else {
               if (!userIdAccIdMap.containsKey(a.CRD__c)) {
                   userIdAccIdMap.put(a.CRD__c, new Set<Id>{a.Id});
               } else {
                   userIdAccIdMap.get(a.CRD__c).add(a.Id);
               }
           }
       }
   }

   Map<Id, String> userIdEmailMap = new Map<Id, String>();
   List<User> user = [SELECT Id, Email FROM User WHERE Id IN :userIdAccIdMap.keySet()];     
   for (User crdUser : user) {
       userIdEmailMap.put(crdUser.Id, crdUser.Email);
   }

   for (Id crdUserId : userIdAccIdMap.keySet()) {
       Set<Id> accIds = userIdAccIdMap.get(crdUserId);
       String userEmail = userIdEmailMap.get(crdUserId);
       for (Id accId : accIds) {
           accIdcrdEmailMap.put(accId, userEmail);
       }
   }
}

public void onOwnerChangeUpdateContactOwners(Map<Id, SObject> existingRecords) {
    List<Contact> contactsToUpdate = new List<Contact>();
    Set<Id> accountIds = new Set<Id>();
    for (Account a : (List<Account>) Records) {
        Account oldAcct = (Account) existingRecords.get(a.Id);
        if (oldAcct.OwnerID != a.OwnerId) {
            accountIds.add(a.Id);
        }
    }
    List<Contact> contact = [SELECT Id, OwnerId, AccountId FROM Contact WHERE AccountId IN :accountIds];
    if (!accountIds.isEmpty()) {
        Map<Id, List<Contact>> accountToContactsMap = new Map<Id, List<Contact>>();
        for (Contact c : contact) {
            if (!accountToContactsMap.containsKey(c.AccountId)) {
                accountToContactsMap.put(c.AccountId, new List<Contact>());
            }
            accountToContactsMap.get(c.AccountId).add(c);
        }
        for (Account a : (List<Account>) Records) {
            if (accountToContactsMap.containsKey(a.Id)) {
                List<Contact> contacts = accountToContactsMap.get(a.Id);
                for (Contact c : contacts) {
                    if (c.OwnerId != a.OwnerId) {
                        c.OwnerId = a.OwnerId;
                        c.Apex_Context__c = true;
                        contactsToUpdate.add(c);
                    }
                }
            }
        }

        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
    }
}

    public class Constructor implements fflib_SObjectDomain.IConstructable
    {
        public fflib_SObjectDomain construct(List<SObject> sObjectList)
        {
            return new Accounts(sObjectList);
        }
    }   
}