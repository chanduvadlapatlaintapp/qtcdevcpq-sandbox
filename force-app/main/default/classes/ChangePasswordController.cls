/**
 * An apex page controller that exposes the change password functionality
 */
public without sharing class ChangePasswordController {
    public String oldPassword {get; set;}
    public String newPassword {get; set;}
    public String verifyNewPassword {get; set;}
    
    private final User myUser;
    
    
    public User Save() {
    
    update myUser;
    return null;
    }
    
    public PageReference changePassword() {
    
    return Site.changePassword(newPassword, verifyNewPassword, oldpassword);    

    }

    public User getMyUser() {
    return myUser;
    }
             
    
    public ChangePasswordController() {
   
            myUser = [SELECT Id, Name, DigestQA__c, DigestProductNews__c FROM USER WHERE Id = :UserInfo.getUserId()];  
        
    }
    
    public static testMethod void testChangePasswordController() {
        // Instantiate a new controller with all parameters in the page
        ChangePasswordController controller = new ChangePasswordController();
        controller.oldPassword = '123456';
        controller.newPassword = 'qwerty1'; 
        controller.verifyNewPassword = 'qwerty1';                
        
        System.assertEquals(controller.changePassword(),null);                           
    }
   
}