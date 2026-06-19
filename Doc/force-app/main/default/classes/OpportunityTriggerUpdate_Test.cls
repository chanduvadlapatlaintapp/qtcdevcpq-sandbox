@isTest (SeeAllData = true)
private class OpportunityTriggerUpdate_Test {
	static testMethod void TestOpportunityUpdate() {
		List <Opportunity> ops = [SELECT Id from Opportunity where IntApp_Opportunity_Number__c = 'O502350'];
		if (ops.size() > 0)
		{
			Opportunity o = ops[0];
			Subscription__c sub = [select Id from Subscription__c where Name = 'S-0001107' LIMIT 1];
			o.Subscription__c = sub.Id;
			o.Validation_Exception__c = true;
			update o;
		}
	}
}