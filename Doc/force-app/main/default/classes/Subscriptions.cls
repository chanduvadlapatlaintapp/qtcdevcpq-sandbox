/**
 * See https://github.com/financialforcedev/fflib-apex-common for more info
 *
 * Install library via 
 *   https://githubsfdeploy.herokuapp.com/app/githubdeploy/financialforcedev/fflib-apex-common
 */

/**
 * Encapsulates all behaviour logic relating to the Subscription__c object
 * 
 * For more guidelines and details see 
 *   https://developer.salesforce.com/page/Apex_Enterprise_Patterns_-_Domain_Layer
 *
 **/
public class Subscriptions extends fflib_SObjectDomain 
{
	public Subscriptions(List<Subscription__c> records) 
	{
		super(records);	
	}

	public override void onValidate()
	{
		for(Subscription__c record : (List<Subscription__c>) Records)
		{
		}
	}

	public override void onValidate(Map<Id,SObject> existingRecords)
	{
		for(Subscription__c record : (List<Subscription__c>) Records)
		{
		}
	}

	public override void onBeforeInsert()
	{
		PopulateCSMByPractice();
	}

	public void someMethod()
	{
		for(Subscription__c record : (List<Subscription__c>) Records)
		{
		}		
	}

	public void PopulateCSMByPractice()
	{
        /*
		//Identify which product lines to check
		Set<String> productLinesToCheck = new Set<String>{'Integration Builder', 'Wall Builder', 'Time', 'DTE'};
		
		//Map product lines to practice heads
		Map<String, Id> practiceOwners = new Map<String, Id>();
		List<pse__Practice__c> practices = [SELECT Id, Name, pse__Practice_Head__c FROM pse__Practice__c];
		system.debug('AW - Result count: ' + practices.size());
		for(pse__Practice__c prac : practices) {
			practiceOwners.put(prac.Name, prac.pse__Practice_Head__c);
		}
		
		//Update Subscriptions according to Practice Owner
		for (Subscription__c sub : (List<Subscription__c>)Records)
		{
			String practiceName = '';
			String productLine = sub.Product_Line__c;
			if (productLine.contains('Integration Builder')) { practiceName = 'Integration Builder'; }
			if (productLine.contains('Wall Builder')) { practiceName = 'Wall Builder'; }
			if (productLine.contains('DTE')) { practiceName = 'DTE'; }
			if (productLine.contains('Time')) { practiceName = 'Time'; }

			//Find Practice (based on Product Line)
			Id owner = practiceOwners.get(practiceName);
			system.debug('AW - Practice Owner is: ' + owner);
			if (owner != null)
			{
				//Retrieve contact record for Practice Owner
				Contact ownerContact = [SELECT Id, Name, pse__Salesforce_User__c FROM Contact where Id = :owner];
				system.debug('AW - Contact is: ' + ownerContact.Name);
				//Find User ID for Practice Head Contact
				User user = [SELECT Id, Name From User WHERE Id = :ownerContact.pse__Salesforce_User__c];
				system.debug('AW - User is: ' + user);
				if (user != null)
				{
					sub.CSM__c = user.Id;
				}
			}
		}
*/
	}

	public class Constructor implements fflib_SObjectDomain.IConstructable
	{
		public fflib_SObjectDomain construct(List<SObject> sObjectList)
		{
			return new Subscriptions(sObjectList);
		}
	}	
}