@isTest global class ServicesSOWOAuthTest {
//(seeAllData = true)
    global class MockHttpResponseGenerator implements HttpCalloutMock {
        global HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"access_token":"testaccesstoken","token_type":"bearer","expires_in":86399,"refresh_token":"testrefreshtoken"}');
            res.setStatusCode(200);
            return res;
        }
    }
    
    @future(callout=true) static void invoke() {
        ServicesSOWOAuth.getAuthToken();
        List<Services_SOW_Settings__c> l = [SELECT OAuth_Access_Token__c, OAuth_Access_Token_Expire_Date_Time__c, OAuth_Refresh_Token__c FROM 
            Services_SOW_Settings__c WHERE Name = 'Settings'];
        Services_SOW_Settings__c s2 = l[0];
        System.assertEquals(s2.OAuth_Access_Token__c,'testaccesstoken');
        System.assertEquals(s2.OAuth_Refresh_Token__c,'testrefreshtoken');
    }
    
    testmethod static void test1() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Services_SOW_Settings__c s1 = new Services_SOW_Settings__c();
        s1.Name = 'Settings';
        s1.OAuth_Access_Token__c = 'test';
        s1.OAuth_Refresh_Token__c = 'test';
        s1.OAuth_Access_Token_Expire_Date_Time__c = DateTime.now().addDays(-2);
        insert s1;
        invoke();
        
    }
  }