@isTest
public class SubscriptionHelperTest {
	@testSetup static void TestSetup() {
		Account account = IntappTestObjectFactory.createAccount(true);

		Subscription__c primarysub = IntappTestObjectFactory.createSubscription(false);
		primarysub.Account__c = account.Id;
		primarysub.Primary_Subscription__c = true;
		primarysub.Product_Line__c = 'Wall Builder';
		insert primarysub;

		Subscription__c fromsub = IntappTestObjectFactory.createSubscription(false);
		fromsub.Account__c = account.Id;
		fromsub.Primary_Subscription__c = false;
		fromsub.Product_Line__c = 'Wall Builder';
		insert fromsub;

		Subscription__c fromsub2 = IntappTestObjectFactory.createSubscription(false);
		fromsub2.Account__c = account.Id;
		fromsub2.Primary_Subscription__c = false;
		fromsub2.Product_Line__c = 'Wall Builder';
		insert fromsub2;

		Opportunity opp = IntappTestObjectFactory.createOpportunity();
		opp.Subscription__c = fromsub.Id;
		insert opp;

		Task task = new Task();
		task.WhatId = fromsub.Id;
		task.Subject = 'Test task for testing';
		insert task;

		Event event = new Event();
		event.DurationInMinutes = 60;
		event.WhatId = fromsub.Id;
		event.ActivityDateTime = Datetime.now();
		event.Subject = 'Test event for testing';
		insert event;

		CR_Engagement__c cr = new CR_Engagement__c();
		cr.Subscription__c = fromsub.Id;
		insert cr;

		Contact primContact = IntappTestObjectFactory.createContact(false);
		insert primContact;
		Contact fromContact = IntappTestObjectFactory.createContact(false);
		insert fromContact;

		Subscription_Contact__c sc = new Subscription_Contact__c();
		sc.Subscription__c = primarysub.Id;
		sc.Contact__c = primContact.Id;
		insert sc;

		Subscription_Contact__c sc2 = new Subscription_Contact__c();
		sc2.Subscription__c = fromsub.Id;
		sc2.Contact__c = fromContact.Id;
		insert sc2;

		Invoice__c invoice = IntappTestObjectFactory.createInvoice(false);
		invoice.Account__c = account.Id;
		insert invoice;

		Invoice_Subscription_Link__c isl = new Invoice_Subscription_Link__c();
		isl.Invoice__c = invoice.Id;
		isl.Subscription__c = fromsub.Id;
		insert isl;
	}

	@isTest static void TestMergeSubscriptionsForAccount() {
		Account account = [Select Id, Intapp_Account_Number__c FROM Account LIMIT 1];
		SubscriptionHelper.MergeSubscriptionsForAccount(account.IntApp_Account_Number__c);
	}

	@isTest static void TestMergeSubscriptionsForPrimarySub() {
		Account account = [Select Id, Intapp_Account_Number__c FROM Account LIMIT 1];
		Subscription__c sub = [SELECT Id from Subscription__c WHERE Primary_Subscription__c = true AND Account__c = :account.Id LIMIT 1];

		Subscription__c fromsub2 = IntappTestObjectFactory.createSubscription(false);
		fromsub2.Account__c = account.Id;
		fromsub2.Primary_Subscription__c = false;
		fromsub2.Product_Line__c = 'Wall Builder';
		insert fromsub2;

		SubscriptionHelper.MergeSubscriptionsForPrimarySubscription(sub.Id);
	}

	//@isTest static void TestMergeSubscriptionsToTerms() {
		//List<Subscription__c> subs = [SELECT ID, Name, Product_Line__c, Account__c, Term_End_Date__c, Primary_Subscription__c from Subscription__c LIMIT 2];
		
		//Subscription__c primarySub; 
		//if (subs[0].Primary_Subscription__c == true)
		//{
			//primarySub = subs[0];
		//}
		//else {
			//primarySub = subs[1];
		//}

		//SubscriptionHelper.MergeSubscriptionsToTerms(primarySub.Id);
	//}

	@isTest static void TestCreateTermsForInvoices() {
		List<Subscription__c> subs = [SELECT ID, Name, Product_Line__c, Account__c, Term_End_Date__c, Primary_Subscription__c from Subscription__c LIMIT 2];
		
		Subscription__c primarySub; 
		if (subs[0].Primary_Subscription__c == true)
		{
			primarySub = subs[0];
		}
		else {
			primarySub = subs[1];
		}

		SubscriptionHelper.CreateTermsForInvoices(primarySub.Id);
	}

}