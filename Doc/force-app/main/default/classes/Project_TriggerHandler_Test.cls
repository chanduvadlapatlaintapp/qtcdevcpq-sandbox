@isTest
public class Project_TriggerHandler_Test {
	static testMethod void test_onInsert(){
    	Opportunity opp = (Opportunity) SmartFactory.createSObject('Opportunity');
        insert opp;
        
        Project__c prj = (Project__c) SmartFactory.createSObject('Project__c');
        prj.Opportunity__c = opp.id;
        insert prj;
    }
}