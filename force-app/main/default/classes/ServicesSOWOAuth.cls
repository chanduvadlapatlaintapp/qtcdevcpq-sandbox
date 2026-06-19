global class ServicesSOWOAuth { 

    global class RefreshTokenResponse {
        public String access_token;
        public String refresh_token;
    }
    
    global class ServicesSOWOAuthException extends Exception { }

    private static Services_SOW_Settings__c settings;
    
    public static void init() {
        List<Services_SOW_Settings__c> l = [SELECT OAuth_Access_Token__c, OAuth_Access_Token_Expire_Date_Time__c, OAuth_Refresh_Token__c,
            OAuth_Client_Id__c,OAuth_Client_Secret__c FROM Services_SOW_Settings__c WHERE Name = 'Settings'];
        settings = l[0];
        if (l == null)
            throw new ServicesSOWOAuthException('Services_SOW_Settings_c object doesnt exist');
        else if ( (settings.OAuth_Access_Token__c == null) || 
                  (settings.OAuth_Refresh_Token__c == null) )
            throw new ServicesSOWOAuthException('One or more field values in Services_SOW_Settings_c object is blank');                  
    }
    
    public static boolean accessTokenIsExpired() {
        if (DateTime.now() > settings.OAuth_Access_Token_Expire_Date_Time__c)
            return true;
        else
            return false;
        }
    
    public static void exchangeRefreshTokenForNewAuthToken() {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');

        req.setEndpoint('https://intappprod.open.intapp.com/auth/oauth/token');
        req.setBody('grant_type=refresh_token&tenant_id=intappprod&refresh_token=' + settings.OAuth_Refresh_Token__c  +
            '&client_id=' + settings.OAuth_Client_Id__c + '&client_secret=' + settings.OAuth_Client_Secret__c);
        req.setHeader('Content-Type','application/x-www-form-urlencoded');
        Http http = new Http();
        
        HTTPResponse res = http.send(req);
        RefreshTokenResponse r = (RefreshTokenResponse)JSON.deserialize(res.getBody(),RefreshTokenResponse.class);
        System.debug(r);
        settings.OAuth_Access_Token_Expire_Date_Time__c = DateTime.now().addDays(1);
        settings.OAuth_Access_Token__c = r.access_token;
        settings.OAuth_Refresh_Token__c = r.refresh_token;
        update settings;
        }
   
    public static String getAuthToken() {
        init();
        if (accessTokenIsExpired())
            exchangeRefreshTokenForNewAuthToken();
        return settings.OAuth_Access_Token__c;
    }
    
    webservice static String getAuthTokenWS() {
        return getAuthToken();
    }
 
}