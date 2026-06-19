//@isTest(SeeAllData = true)
@isTest
private class SmartFactoryTest {
   @isTest static void testSmartFactory() {
       
       map<String, set<String>> includedFields = new map<String, set<String>>{
		'Account' => new set<String>{'BillingCountry','BillingState','AccountCSM_Health_Rating_Last_Modified__c','Assets_Under_Management_AUM__c','Hot_List_Case_Count__c','ReferenceEdge_license_band__c','Phone','Electronic_Signature_Software__c',' Fee_Split_A_A__c','RecordTypeId'}		
	};
        SmartFactory.includedFields = includedFields;
       List<SObject> objects = SmartFactory.createSObjectList('Account', false, 2);
       System.assertEquals(objects.size(), 2);
   }
   @isTest static void testSmartFactory1() {
       // Test creation of various SObjects
       map<String, set<String>> includedFields = new map<String, set<String>>{
		'SBQQ__Quote__c' => new set<String>{'Quality_Issues_Level_1_Deal__c'}		
	};
        
       List<SObject> objects = SmartFactory.createSObjectList('SBQQ__Quote__c', false, 1);
       System.assertEquals(objects.size(), 1);
   }
  
   @isTest static void testSmartFactory2() {
       // Test creation of SObjects with different field values
       List<SObject> objects = SmartFactory.createSObjectList('Account', false, 1);
       System.assertEquals(objects.size(), 1);
       Opportunity opp = (Opportunity)SmartFactory.createSObject('Opportunity');
       
   }
  
   @isTest static void testSmartFactory3() { 
      //Test creation of SObjects with different cascading options
        List<SObject> objects = SmartFactory.createSObjectList('Contact', false, 2);
        System.assertEquals(objects.size(), 2);
   }
   @isTest static void testSmartFactory4() {
       // Test creation of SObjects with excluded fields
       List<SObject> objects = SmartFactory.createSObjectList('User', false, 2);
       System.assertEquals(objects.size(), 2);
   }
  
}