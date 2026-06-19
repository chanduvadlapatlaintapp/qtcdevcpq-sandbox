@isTest (seeAllData = true) global class ServicesSOWTest {


   global class MockHttpResponseGenerator implements HttpCalloutMock {
        global HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"access_token":"testaccesstoken","token_type":"bearer","expires_in":86399,"refresh_token":"testrefreshtoken"}');
            res.setStatusCode(200);
            return res;
        }
    }
    
    @future(callout=true) static void invoke2(String AccountId) {
        ServicesSOW.createSFServicesSOWObjectHelper('[ {"answerType":"text","questionName":"Account__c","textAnswer":"' + AccountId + '"} ]');
        Services_SOW__c s = [SELECT Account__r.Name FROM Services_SOW__c WHERE Account__c = :AccountId];
        System.assertEquals('testaccount-SOW test',s.Account__r.Name);
    }
    
    static void invoke(String OpportunityId, String AccountId) {
        ServicesSOW.createFlowRequestWithDefaultFieldsHelper(OpportunityId,true);
        invoke2(AccountId);
    }
    
    testmethod static void test1() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Account a = new Account();
        a.Name = 'testaccount-SOW test';
        insert a;
        Opportunity o = new Opportunity();
        o.AccountId = a.Id;
        RecordType r = [SELECT Id from RecordType WHERE Name = 'Sales - Legal' and SObjectType = 'Opportunity' LIMIT 1];
        o.RecordTypeId = r.Id;
        o.Name = 'TestOppName';
        o.Practice_Group__c = 'Risk & Compliance';
        o.Product_Line__c = 'Intapp Open - Intake';
        o.Package__c = 'Intapp Open: Intake - Engagement Letter Module';
        o.Type = 'Legal - New Product';
        o.RFP2__c = 'Funded';
        o.CloseDate = DateTime.newInstance(2017,1,30).date();
        o.StageName = 'TargetAccount';
        o.Review_Stage__c = 'Discussion with Seller';
        o.CurrencyIsoCode = 'USD';
        insert o;
        invoke(o.Id,a.Id);
        //System.assertNotEquals(o.Id,null);
        
    }
    
    
}