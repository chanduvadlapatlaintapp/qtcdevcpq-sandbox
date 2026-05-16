/**
 * An apex page controller that exposes the site login functionality
 */
global with sharing class SiteLoginController {
    global String username {get; set;}
    global String password {get; set;}

    global PageReference login() {
        String startUrl = System.currentPageReference().getParameters().get('startURL');
        if (System.currentPageReference().getParameters().containsKey('refURL')) {
        	startUrl = System.currentPageReference().getParameters().get('refURL');
        	if (startURL.contains('/portal')) {
        		startUrl = startURL.substring(startURL.indexOf('/portal') + 7);
        	}
        }
        System.debug('=====' + startUrl);
        
        return Site.login(username, password, startUrl);
    }
    
   	global SiteLoginController () {}
    
    global static testMethod void testSiteLoginController () {
        // Instantiate a new controller with all parameters in the page
        SiteLoginController controller = new SiteLoginController ();
        controller.username = 'test@salesforce.com';
        controller.password = '123456'; 
                
        System.assertEquals(controller.login(),null);                           
    }    
}