global with sharing class ScrubContactEmailBatch implements Database.Batchable<sObject> {
    global Database.QueryLocator start(Database.BatchableContext bc){
        String query = 'Select Id, Email FROM Contact WHERE Email != null AND (NOT(Email like \'%xxxx.com\'))';
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<Contact> contactList){
        List<Contact> contactUpdateList = new List<Contact>();
        for (Contact contact : contactList) {
            contact.Email = 'xxxxxx@xxxx.com';
        }
        Database.update(contactList,false);
    }

    global void finish(Database.BatchableContext bc){}
}