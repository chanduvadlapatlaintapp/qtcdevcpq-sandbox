/********************************************************************************     
 *  Name             :  ContactTriggerHandlerTest
 *  Description      :  Tests for ContactTriggerHandler (deletion notification, BIZ-79981 platform event eligibility).
 *  Change history   :
 *  11/29/16            Anisha Dhekne                   Created test class for Contact Trigger
 ***************************************************************************************************/
@isTest
class ContactTriggerHandlerTest {

	@isTest
	static void testsendContactDeletedNotification() {
		List<User> list_User = new List<User> ();
		List<Contact> list_contacts = new List<Contact> ();

		Account acc1 = new Account();
		acc1 = IntappTestObjectFactory.createAccount(false);

		acc1.Name = 'test';
		insert acc1;

		User usr1 = (User) SmartFactory.createSObject('User');
		//usr1.ContactId = [Select Id from Contact LIMIT 1].Id;
		usr1.Contact_Deletion_Notification__c = true;
		usr1.isActive = true;
		usr1.Email = 'anisha.dhekne@intapp.com';
		list_User.add(usr1);
		insert list_User;

		Contact con1 = (Contact) SmartFactory.createSObject('Contact');
		//	con1.Id = [Select Id from Contact LIMIT 1].Id;
		con1.AccountId = acc1.Id;
		con1.FirstName = 'testfirstname';
		con1.LastName = 'testlastname';
		con1.CurrencyIsoCode = 'USD';
		list_contacts.add(con1);

		insert list_contacts;


		System.runAs(usr1) {
			delete list_contacts;
		}
	}

	// BIZ-79981: filterBillingContacts – 5 scenarios per Solution Design
	@isTest
	static void filterBillingContacts_billingContactOnInsert_included() {
		Account acc = (Account) TestFactory.createSObject(new Account());
		Contact c = (Contact) TestFactory.createSObject(new Contact(AccountId = acc.Id, Billing_Contact__c = true));
		List<Contact> eligible = ContactTriggerHandler.filterBillingContacts(new List<Contact>{ c }, null);
		System.assertEquals(1, eligible.size(), 'Billing contact on insert should be included');
	}

	@isTest
	static void filterBillingContacts_billingCheckboxChecked_included() {
		Account acc = (Account) TestFactory.createSObject(new Account());
		Contact cOld = (Contact) TestFactory.createSObject(new Contact(AccountId = acc.Id, Billing_Contact__c = false));
		Contact cNew = cOld.clone(true, true, true, true);
		cNew.Billing_Contact__c = true;
		Map<Id, Contact> oldMap = new Map<Id, Contact>{ cOld.Id => cOld };
		List<Contact> eligible = ContactTriggerHandler.filterBillingContacts(new List<Contact>{ cNew }, oldMap);
		System.assertEquals(1, eligible.size(), 'Contact when billing checkbox checked should be included');
	}

	@isTest
	static void filterBillingContacts_billingCheckboxUnchecked_included() {
		Account acc = (Account) TestFactory.createSObject(new Account());
		Contact cOld = (Contact) TestFactory.createSObject(new Contact(AccountId = acc.Id, Billing_Contact__c = true));
		Contact cNew = cOld.clone(true, true, true, true);
		cNew.Billing_Contact__c = false;
		Map<Id, Contact> oldMap = new Map<Id, Contact>{ cOld.Id => cOld };
		List<Contact> eligible = ContactTriggerHandler.filterBillingContacts(new List<Contact>{ cNew }, oldMap);
		System.assertEquals(1, eligible.size(), 'Contact when billing checkbox unchecked should be included (notify downstream)');
	}

	@isTest
	static void filterBillingContacts_nonBillingUpdate_excluded() {
		Account acc = (Account) TestFactory.createSObject(new Account());
		Contact cOld = (Contact) TestFactory.createSObject(new Contact(AccountId = acc.Id, Billing_Contact__c = false));
		Contact cNew = cOld.clone(true, true, true, true);
		cNew.FirstName = 'Changed';
		Map<Id, Contact> oldMap = new Map<Id, Contact>{ cOld.Id => cOld };
		List<Contact> eligible = ContactTriggerHandler.filterBillingContacts(new List<Contact>{ cNew }, oldMap);
		System.assertEquals(0, eligible.size(), 'Non-billing contact update should be excluded');
	}

	@isTest
	static void filterBillingContacts_existingBillingContactWithFieldChanges_included() {
		Account acc = (Account) TestFactory.createSObject(new Account());
		Contact cOld = (Contact) TestFactory.createSObject(new Contact(
			AccountId = acc.Id, Billing_Contact__c = true, FirstName = 'A', Phone = '111'));
		Contact cNew = cOld.clone(true, true, true, true);
		cNew.Phone = '222';
		Map<Id, Contact> oldMap = new Map<Id, Contact>{ cOld.Id => cOld };
		List<Contact> eligible = ContactTriggerHandler.filterBillingContacts(new List<Contact>{ cNew }, oldMap);
		System.assertEquals(1, eligible.size(), 'Existing billing contact with field change should be included');
	}
}