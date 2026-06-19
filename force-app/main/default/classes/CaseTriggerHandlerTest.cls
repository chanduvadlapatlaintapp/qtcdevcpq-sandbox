/**
 * @description Test class for CaseTriggerHandler
 */
@isTest
public class CaseTriggerHandlerTest {

    static testMethod void TestMethod1(){
        String RecordTypeNme = Schema.SObjectType.case.getRecordTypeInfosByDeveloperName().get('Survey').getRecordTypeId();  
        String RecordTypeNmeExe = Schema.SObjectType.case.getRecordTypeInfosByDeveloperName().get('Executive_Support_Case').getRecordTypeId();      
        Account accObj = new Account();
        accObj.Name = 'TestAccount';
        accObj.Type = 'Prospect';
        insert accObj;
        
        Contact conObj = new Contact();
        conObj.lastname = 'TestContact';
        conObj.AccountId = accObj.id;
        insert conObj;
        
        Product_Line__c pli = new Product_Line__c();
        pli.Name = 'Conflicts';
        pli.Active__c = true;
        insert pli;
        
        Product_Ownership_Detail__c pOwn1 = new Product_Ownership_Detail__c();
        pOwn1.Account_Name__c =  accObj.id;
        pOwn1.Product_line_link__c = pli.id;
        pOwn1.Support_Level__c = 'Standard (Silver)';
        pOwn1.Status__c = 'Own it'; 
        insert pOwn1; 
        
        Product_Ownership_Detail__c pOwn2 = new Product_Ownership_Detail__c();
        pOwn2.Account_Name__c =  accObj.id;
        pOwn2.Product_line_link__c = pli.id;
        pOwn2.Support_Level__c = 'Premium (Platinum)';
        pOwn2.Status__c = 'Own it'; 
        insert pOwn2;
        
        Case cseObj1 = new Case();
        cseObj1.AccountId = accObj.Id;
        cseObj1.RecordTypeId = RecordTypeNme;
        cseObj1.PSCase_Kickoff_Meeting_Date__c = system.today();
        cseObj1.Support_Level_Conflicts_New__c = 'Test Support Level';
        insert cseObj1; 
        
        System.assertEquals(system.today(), cseObj1.PSCase_Kickoff_Meeting_Date__c);
        
        Case cseObj2 = new Case();
        cseObj2.AccountId = accObj.Id;
        cseObj2.RecordTypeId = RecordTypeNmeExe;
        cseObj2.Survey_ContactID__c = conObj.id;
        insert cseObj2;
        
        
        
    } 
    
    static testMethod void TestMethod2() {
        List<case> lstOfCases = new List<case>();
        Map<Id,Case> mapOfCases = new Map<Id,Case>();
        String RecordTypeNme = Schema.SObjectType.case.getRecordTypeInfosByDeveloperName().get('Survey').getRecordTypeId();       
        Account accObj = new Account();
        accObj.Name = 'TestAccount';
        accObj.Type = 'Prospect';
        insert accObj;
        
        Contact conObj = new Contact();
        conObj.lastname = 'TestContact';
        conObj.AccountId = accObj.id;
        insert conObj;
        
        Product_Line__c pli = new Product_Line__c();
        pli.Name = 'Test PLI';
        pli.Active__c = true;
        insert pli;
        
        Product_Ownership_Detail__c pOwn1 = new Product_Ownership_Detail__c();
        pOwn1.Account_Name__c =  accObj.id;
        pOwn1.Product_line_link__c = pli.id;
        pOwn1.Support_Level__c = 'Premium (Platinum)';
        pOwn1.Status__c = 'Own it'; 
        insert pOwn1; 
        
        Product_Ownership_Detail__c pOwn2 = new Product_Ownership_Detail__c();
        pOwn2.Account_Name__c =  accObj.id;
        pOwn2.Product_line_link__c = pli.id;
        pOwn2.Support_Level__c = 'Standard (Silver)';
        pOwn2.Status__c = 'Own it'; 
        insert pOwn2;   
        
        Case cseObj = new Case();
        cseObj.AccountId = accObj.Id;
        cseObj.RecordTypeId = RecordTypeNme;
        cseObj.PSCase_Kickoff_Meeting_Date__c = system.today() + 1;
        insert cseObj;
        
        System.assertEquals(system.today() + 1, cseObj.PSCase_Kickoff_Meeting_Date__c);
        lstOfCases.add(cseObj);
        mapOfCases.put(cseObj.id,cseObj);
        
        CaseTriggerHandler.AfterUnDelete(lstOfCases,mapOfCases);
        CaseTriggerHandler.UpdateSupportLevels(lstOfCases);
        delete cseObj;
        
    }
    
    /**
     * @author Manisha
     * @date 2025-05-05
     * @description This test verifies that the Case owner is reassigned to the FM Queue when 
     * the Case Type is updated to 'Finance Ops Support' during a before update trigger.
     * The owner should be set to the 'Finance Support' Queue.
     */
    @isTest
    static void testAssignToFMQueue() {

        Case caseBefore = (Case) TestFactory.buildSObject(
            new Case(
                Subject = 'Test Case',
                Status = 'New',
                Origin = 'Email'
            )
        );
        insert caseBefore;
        Test.startTest();
            caseBefore.Type = CaseConstants.TYPE_FINANCE_OPS_SUPPORT;
            update caseBefore;
        Test.stopTest();

        Case caseAfter = getUpdatedCase(caseBefore.Id);
        System.assertEquals(CaseTriggerHandler.financeQueueId, caseAfter.OwnerId, 'OwnerId should be set to FM Queue when Type changes to Finance Ops Support');
        System.assertEquals(CaseConstants.TYPE_FINANCE_OPS_SUPPORT, caseAfter.Type, 'The Type should be updated to Finance Ops Support');
    }

    /**
     * @description Getter method to retrieve the updated Case object after an update operation
     * @param caseId The Id of the Case to retrieve
     * @return The updated Case record
     */
    private static Case getUpdatedCase(Id caseId) {
        return [SELECT Id, OwnerId, Type FROM Case WHERE Id = :caseId];
    }
}