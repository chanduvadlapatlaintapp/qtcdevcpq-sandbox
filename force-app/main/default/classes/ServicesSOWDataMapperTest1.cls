@isTest(seeAllData = true) global class ServicesSOWDataMapperTest1 {

   global class MockHttpResponseGenerator implements HttpCalloutMock {
        global HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"access_token":"testaccesstoken","token_type":"bearer","expires_in":86399,"refresh_token":"testrefreshtoken"}');
            res.setStatusCode(200);
            return res;
        }
    }

    static String getjsonValue(String jsonData, String fieldName) {
        ServicesSOWAnswers answers = (ServicesSOWAnswers)JSON.deserialize(jsonData,ServicesSOWAnswers.class);
        for (ServicesSOWAnswer ans: answers.answers) {
            if (ans.questionName == fieldName) {
                if (ans.textAnswer != null)
                    return ans.textAnswer;
                if (ans.numericAnswer != null)
                    return ans.numericAnswer; 
                else if (ans.booleanAnswer != null)
                    return ans.booleanAnswer;
                else if (ans.dateAnswer != null)
                    return ans.dateAnswer; 
                else if (ans.textListAnswer != null)
                    return ans.textListAnswer[0];
            }
        }
        return 'ERROR';
    }
    
    
    static Account createAccount() {
        Account a = IntappTestObjectFactory.createAccount(true);
        a.Support_Level_Intapp_Time__c = 'Premium (Platinum)';
        a.Support_Level_Intapp_Open_Intake__c = 'Standard (Silver)';
        a.Support_Level_Intapp_Open_Conflicts__c = 'Standard (Silver)';
        a.Support_Level_Integration_Builder__c = 'Premium (Platinum)';
        a.Support_Level_Rekoop__c = 'Premium (Gold)';
        a.Support_Level_Wall_Builder__c = 'Lapsed';
        update a;
        return a;
    }
    
    static Opportunity createLegalLegacyOpportunity(Account a) {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Opportunity o = new Opportunity();
        o.AccountId = a.Id;
        RecordType r = [SELECT Id from RecordType WHERE Name = 'Legal - Legacy' and SObjectType = 'Opportunity' LIMIT 1];
        o.RecordTypeId = r.Id;
        o.Name = 'TestOppName';
        //o.Practice_Group__c = 'Revenue Practice';
        o.Product_Line__c = 'Intapp Time';
        o.Package__c = 'Services - Time Entry';
        o.Type = 'Legal - New Product';
        o.RFP2__c = 'Funded';
        o.CloseDate = DateTime.newInstance(2017,1,30).date();
        o.StageName = 'TargetAccount';
        o.Review_Stage__c = 'Discussion with Seller';
        o.CurrencyIsoCode = 'USD';
        insert o;
        return o;
        }
    
    static Opportunity createLegalOpenOpportunity(Account a) {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Opportunity o = new Opportunity();
        o.AccountId = a.Id;
        RecordType r = [SELECT Id from RecordType WHERE Name = 'Sales - Legal' and SObjectType = 'Opportunity' LIMIT 1];
        o.RecordTypeId = r.Id;
        o.Name = 'TestOppName';
        //o.Practice_Group__c = 'Risk Practice';
        o.Product_Line__c = 'Intapp Open - Intake';
        o.Package__c = 'Intapp Open: Intake - Engagement Letter Module';
        o.Type = 'Legal - New Product';
        o.RFP2__c = 'Funded';
        o.CloseDate = DateTime.newInstance(2017,1,30).date();
        o.StageName = 'TargetAccount';
        o.Review_Stage__c = 'Discussion with Seller';
        o.CurrencyIsoCode = 'USD';
        insert o;
        return o;
        }
        
    static Opportunity createLegalTimeOpportunity(Account a) {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Opportunity o = new Opportunity();
        o.AccountId = a.Id;
        RecordType r = [SELECT Id from RecordType WHERE Name = 'Sales - Legal' and SObjectType = 'Opportunity' LIMIT 1];
        o.RecordTypeId = r.Id;
        o.Name = 'TestOppName';
       // o.Practice_Group__c = 'Revenue Practice';
        o.Product_Line__c = 'Intapp Time';
        o.Package__c = 'Services - Time Capture';
        o.Type = 'Legal - New Product';
        o.RFP2__c = 'Funded';
        o.CloseDate = DateTime.newInstance(2017,1,30).date();
        o.StageName = 'TargetAccount';
        o.Review_Stage__c = 'Discussion with Seller';
        o.CurrencyIsoCode = 'USD';
        insert o;
        return o;
        }
        
    static Opportunity createLegalWallsOpportunity(Account a) {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Opportunity o = new Opportunity();
        o.AccountId = a.Id;
        RecordType r = [SELECT Id from RecordType WHERE Name = 'Sales - Legal' and SObjectType = 'Opportunity' LIMIT 1];
        o.RecordTypeId = r.Id;
        o.Name = 'TestOppName';
       // o.Practice_Group__c = 'Risk Practice';
        o.Product_Line__c = 'Wall Builder';
        o.Package__c = 'Services';
        o.Type = 'Legal - New Product';
        o.RFP2__c = 'Funded';
        o.CloseDate = DateTime.newInstance(2017,1,30).date();
        o.StageName = 'TargetAccount';
        o.Review_Stage__c = 'Discussion with Seller';
        o.CurrencyIsoCode = 'USD';
        insert o;
        return o;
        }

    static Opportunity createLegalIntegrationOpportunity(Account a) {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Opportunity o = new Opportunity();
        o.AccountId = a.Id;
        RecordType r = [SELECT Id from RecordType WHERE Name = 'Sales - Legal' and SObjectType = 'Opportunity' LIMIT 1];
        o.RecordTypeId = r.Id;
        o.Name = 'TestOppName';
        //o.Practice_Group__c = 'Integration Practice';
        o.Product_Line__c = 'Integration Builder';
        o.Package__c = 'Services';
        o.Type = 'Legal - New Product';
        o.RFP2__c = 'Funded';
        o.CloseDate = DateTime.newInstance(2017,1,30).date();
        o.StageName = 'TargetAccount';
        o.Review_Stage__c = 'Discussion with Seller';
        o.CurrencyIsoCode = 'USD';
        insert o;
        return o;
        }
        
        /*
        ServicesSOWDataMapper dm = new ServicesSOWDataMapper(o.Id);
        String dmJSON = dm.getMappings();
        System.assertEquals('testaccount',getJSONValue(dmJSON,'Account__c'));
        System.assertEquals('North America',getJSONValue(dmJSON,'Geography__c'));
        System.assertEquals('Intapp Open: Intake (Engagement Letters)',getJSONValue(dmJSON,'Product__c'));
        System.assertEquals('3.0.0',getJSONValue(dmJSON,'Production_Version__c'));
        System.assertEquals('USA:United States San Francisco',getJSONValue(dmJSON,'Billing_Country_City__c'));
        System.assertEquals('Standard (Silver)',getJSONValue(dmJSON,'Extended_Or_Premium_Support__c'));
        */
        //ServicesSOW.createFlowRequestWithDefaultFields1(o.Id);
        //ServicesSOW.createSFServicesSOWObject('');
   
    
    testmethod static void testProductVersion() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account a = createAccount();
        Account aq;
        Opportunity o;
              
        o = createLegalOpenOpportunity(a);
        ServicesSOWDataMapper dm = new ServicesSOWDataMapper(o.Id);
        String dmJSON;
        try{
            dmJSON = dm.getMappings();
        aq = [SELECT Open_Version__r.Name from Account WHERE Id = :a.Id LIMIT 1];
        if(dmJSON != '')
            System.assertEquals(aq.Open_Version__r.Name,getJSONValue(dmJSON,'Production_Version__c'));
   		 
       
        o = createLegalTimeOpportunity(a);
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        aq = [SELECT TB_Version__r.Name from Account WHERE Id = :a.Id LIMIT 1];
        if(dmJSON != '')
            System.assertEquals(aq.TB_Version__r.Name,getJSONValue(dmJSON,'Production_Version__c'));
        
        o = createLegalLegacyOpportunity(a);
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        aq = [SELECT TE_Version__r.Name from Account WHERE Id = :a.Id LIMIT 1];
        if(dmJSON != '')
            System.assertEquals(aq.TE_Version__r.Name,getJSONValue(dmJSON,'Production_Version__c'));
    }catch(exception e)
        {
            Assert.isNotNull(e);
        }
        
        /*
        o.Product_Line__c = 'Intapp Time: Total Time Management';
        update o;
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        System.assertEquals('3.0.0',getJSONValue(dmJSON,'Production_Version__c'));
        
        o.Product_Line__c = 'Intapp Walls';
        update o;
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        System.assertEquals('6.1.0',getJSONValue(dmJSON,'Production_Version__c'));
        */
    }
    testmethod static void testSupportLevel() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account a = createAccount();
        Opportunity o;
        ServicesSOWDataMapper dm;
        String dmJSON;

        o = createLegalIntegrationOpportunity(a);
        o.Product_Line__c = 'Integration Builder';
        o.Package__c = 'Services';
        update o;
        try{
            dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        if(dmJSON != '')
            System.assertEquals(a.Support_Level_Integration_Builder__c,getJSONValue(dmJSON,'Extended_Or_Premium_Support__c'));
    	
        o = createLegalOpenOpportunity(a);
        o.Product_Line__c = 'Intapp Open - Conflicts';
        o.Package__c = 'Services';
        update o;
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        if(dmJSON != '')
            System.assertEquals(a.Support_Level_Intapp_Open_Conflicts__c,getJSONValue(dmJSON,'Extended_Or_Premium_Support__c'));

        o = createLegalOpenOpportunity(a);
        o.Product_Line__c = 'Intapp Open - Intake';
        o.Package__c = 'Services';
        update o;
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        if(dmJSON != '')
            System.assertEquals(a.Support_Level_Intapp_Open_Intake__c,getJSONValue(dmJSON,'Extended_Or_Premium_Support__c'));
    }catch(exception e)
        {
            Assert.isNotNull(e);
        }
        
        }
    
    testmethod static void testSupportLevel2() {
        Account a = createAccount();
        Opportunity o;
        ServicesSOWDataMapper dm;
        String dmJSON;
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        o = createLegalTimeOpportunity(a);
        o.Product_Line__c = 'Intapp Time - Cloud';
        o.Package__c = 'Services';
        update o;
        try{
        dm = new ServicesSOWDataMapper(o.Id);
        
            dmJSON = dm.getMappings();
        if(dmJSON != '')
            System.assertEquals(a.Support_Level_Rekoop__c,getJSONValue(dmJSON,'Extended_Or_Premium_Support__c'));
        
        o = createLegalLegacyOpportunity(a);
        o.Product_Line__c = 'Intapp Time';
        o.Package__c = 'Services - Intapp Time';
        update o;
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        if(dmJSON != '')
            System.assertEquals(a.Support_Level_Intapp_Time__c,getJSONValue(dmJSON,'Extended_Or_Premium_Support__c'));

        o = createLegalWallsOpportunity(a);
        o.Product_Line__c = 'Wall Builder';
        o.Package__c = 'Services';
        update o;
        dm = new ServicesSOWDataMapper(o.Id);
        dmJSON = dm.getMappings();
        if(dmJSON != '')
            System.assertEquals(a.Support_Level_Wall_Builder__c,getJSONValue(dmJSON,'Extended_Or_Premium_Support__c'));
        
        
        }catch(exception e)
        {
            Assert.isNotNull(e);
        }
    }
}