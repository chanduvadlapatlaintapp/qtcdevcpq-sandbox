/********************************************************************************     
 *  Name             :  ContactTriggerHandler
 *  Description      :  1. Notifies admins when an contact is deleted
 *                      2. Publishes platform events for Contacts (BIZ-79981: only for
 *                         Billing Contacts). Include if (a) Billing_Contact__c is true
 *                         on new record, OR (b) was true on old record (notify when removed).
 *                         Field_Tracking__mdt in IntegrationUtility determines which field
 *                         changes trigger publish.
 *                                  
 *  Change history   :
 *  Date                Author                          Description
 *  11/29/16            Mitali Machra                   Created
 *  Need to add custom setting to add new users
 ********************************************************************************/
public class ContactTriggerHandler {

    public static void sendContactDeletedNotification(List <Contact> contacts){
        List<String> toAddresses = new List<String>();
        for(User u: [select email from User where Contact_Deletion_Notification__c = true and isActive = true]){
            toAddresses.add(u.email);
        }
        if(contacts.size()>0 && toAddresses.size()>0){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('Contact deleted');
            mail.setSaveAsActivity(false);
            String textBody = UserInfo.getName() +' ('+ UserInfo.getUserEmail() +') deleted the following contacts: \n';
            for(contact contact1: contacts)
            {
                //textBody += '\n  Contact ID: '+ contact1.Id;
                textBody += '\n ' + contact1.FirstName + ' ' + contact1.LastName;
            }
            mail.setPlainTextBody(textBody);
            System.debug('#### ContactTriggerHandler- sending notifications to: '+ toAddresses);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
        }
    }
    
    
    public static void disablePortalUserCheck(List<Contact> contacts) {
        /*
        List<User> usersToUpsert = new List<User>();
        
        for (Contact c: contacts) {
            if (c.PortalAccountNew__c == 'AccountDeprovisioned') {
                User u = [SELECT Id from User where ContactID = :c.Id LIMIT 1];
                u.IsActive = false;
                //u.Title = 'aaab';
                usersToUpsert.add(u);
                //DebugLogger__c d = new DebugLogger__c();
                //d.LogText__c = u.Id;
                //insert d;
            }
        }
        //DebugLogger__c d = new DebugLogger__c();
        //d.LogText__c = 'test3';
        //insert d;
        //update usersToUpsert;   
        */     
    }
    
    public static void contactAfterInsert(List<Contact> contactNewList) {
        List<Contact> eligible = filterBillingContacts(contactNewList, null);
        if (!eligible.isEmpty()) {
            IntegrationUtility.publishEligibleSobjectRecords(eligible, null, 'Contact');
        }
    }

    public static void contactAfterUpdate(List<Contact> contactNewList, Map<Id, Contact> contactOldMap) {
        List<Contact> eligible = filterBillingContacts(contactNewList, contactOldMap);
        if (!eligible.isEmpty()) {
            Map<Id, Contact> oldMapForEligible = new Map<Id, Contact>();
            for (Contact c : eligible) {
                if (contactOldMap != null && contactOldMap.containsKey(c.Id)) {
                    oldMapForEligible.put(c.Id, contactOldMap.get(c.Id));
                }
            }
            IntegrationUtility.publishEligibleSobjectRecords(eligible, oldMapForEligible, 'Contact');
        }
    }

    /**
     * BIZ-79981: Include Contact if (a) Billing_Contact__c is true on new record, OR
     * (b) was true on old record (to notify downstream when billing status is removed).
     * IntegrationUtility uses Field_Tracking__mdt to decide which field changes trigger publish.
     */
    @TestVisible
    private static List<Contact> filterBillingContacts(
            List<Contact> newContacts,
            Map<Id, Contact> oldMap) {
        List<Contact> eligible = new List<Contact>();
        for (Contact cNew : newContacts) {
            Boolean wasBilling = (oldMap != null && oldMap.containsKey(cNew.Id))
                ? (oldMap.get(cNew.Id).Billing_Contact__c == true)
                : false;
            if (cNew.Billing_Contact__c == true || wasBilling) {
                eligible.add(cNew);
            }
        }
        return eligible;
    }
}