trigger UpdateContactOwners on Account (before update) {
    List<Contact> contactsToUpdate = new List<Contact>();
    
    for (Account a: Trigger.new)
    {
        Account oldAcct = Trigger.oldMap.Get(a.Id);
        
        if (oldAcct.OwnerID != a.OwnerId)
        {       
            List<Contact> contacts = [SELECT Id, OwnerId FROM Contact WHERE AccountId = :a.Id];
            
            if ((contactsToUpdate.size() + contacts.size() > 10000) && contactsToUpdate.size() > 0)
            {
                update contactsToUpdate;
                contactsToUpdate.clear();
            }

            for(Contact c: contacts)
            {
                if (c.OwnerId!= a.OwnerId)
                {
                    c.OwnerId = a.OwnerId;
                    c.Apex_Context__c = true;
                    contactsToUpdate.add(c);
                }
            }
           
       }
    }
    
    if (contactsToUpdate.size() > 0)
    { 
    update contactsToUpdate;
    }
}