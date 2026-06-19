@isTest()
public class ScrubContactEmailBatchTest {
    @isTest()
    public static void testContactScrub() {
        List<Contact> contactList = new List<Contact>();
        Contact contact1 = IntappTestObjectFactory.createContact(false);
        contact1.Email = 'test@test.com';
        contactList.add(contact1);

        Contact contact2 = IntappTestObjectFactory.createContact(false);
        contact2.Email = 'test2@xxxx.com';
        contactList.add(contact2);

        Contact contact3 = IntappTestObjectFactory.createContact(false);
        contactList.add(contact3);

        insert contactList;

        Test.startTest();
        Database.executeBatch(new ScrubContactEmailBatch());
        Test.stopTest();

        System.assertEquals('xxxxxx@xxxx.com', [SELECT email FROM Contact WHERE Id = :contact1.Id].Email);

    }
}