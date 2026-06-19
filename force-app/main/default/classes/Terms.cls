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
 * 6/15/2016: AW - First Release
 **/
public class Terms extends fflib_SObjectDomain
{
	public Terms(List<Term__c> records)
	{
		super(records);
		Configuration.disableTriggerCRUDSecurity();
	}

	public override void onAfterInsert()
	{
		UpdateProductCustomerTermStartDate();
	}

	public override void OnBeforeUpdate(Map<Id, SObject> existingRecords)
	{
		UpdateProductCustomerTermStartDate();
	}

	public void UpdateProductCustomerTermStartDate()
	{
		List<Subscription__c> subsToUpdate = new List<Subscription__c> ();

		for (Term__c t : (List<Term__c>) Records)
		{
			Subscription__c sub = [SELECT Most_Recent_Term_Start_Date__c FROM Subscription__c WHERE Id = :t.Product_Customer_Number__c LIMIT 1];

			List<Term__c> mostrecentterm = [SELECT ID, Start_Date__c from Term__c
			                                WHERE Product_Customer_Number__c = :t.Product_Customer_Number__c
			                                AND Start_Date__c != null
			                                ORDER BY Start_Date__c desc];

			if (mostrecentterm.size() > 0) {
				if (sub.Most_Recent_Term_Start_Date__c != mostrecentterm[0].Start_Date__c)
				{
					sub.Most_Recent_Term_Start_Date__c = mostrecentterm[0].Start_Date__c;
					subsToUpdate.add(sub);
				}
			}
		}

		if (subsToUpdate.size() > 0)
		{
			update subsToUpdate;
		}
	}

	public class Constructor implements fflib_SObjectDomain.IConstructable
	{
		public fflib_SObjectDomain construct(List<SObject> sObjectList)
		{
			return new Terms(sObjectList);
		}
	}
}