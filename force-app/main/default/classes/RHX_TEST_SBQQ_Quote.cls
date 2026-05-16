@isTest(SeeAllData=true)
public class RHX_TEST_SBQQ_Quote {
	static testMethod void RHX_Testmethod() {
        List<sObject> sourceList = [SELECT Id 
			FROM SBQQ__Quote__c LIMIT 1];
        if(sourceList.size() == 0) {
            sourceList.add(
                    new SBQQ__Quote__c()
            );
        }
    	rh2.ParentUtil.UpsertRollupTestRecords( sourceList );
    }
}