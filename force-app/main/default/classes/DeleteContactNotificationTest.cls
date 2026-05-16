@isTest
public class DeleteContactNotificationTest {

	static testmethod void test() {
		Contact contact = IntappTestObjectFactory.createContact(true);
		System.debug(contact.ID);
		delete contact;
		}
}