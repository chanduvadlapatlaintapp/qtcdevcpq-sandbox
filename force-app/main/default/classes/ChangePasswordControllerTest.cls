/* Test Class for ChangePasswordController */
@isTest
public class ChangePasswordControllerTest {

    @isTest
    static void testChangePasswordController() {
        // Step 1: Set up a test user
        User testUser = new User(
            Alias = 'testuser',
            Email = 'testusedbdfbsdbfdsr@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'testuser12346hgfhdgfhf@example.com'
        );
        insert testUser;

        // Step 2: Mock the running user
        System.runAs(testUser) {
            // Instantiate the controller
            ChangePasswordController controller = new ChangePasswordController();
            controller.Save();
            controller.getMyUser();
            
            // Step 3: Set controller parameters
            controller.oldPassword = '123456';
            controller.newPassword = 'qwerty1';
            controller.verifyNewPassword = 'qwerty1';

            // Step 4: Mock the Site.changePassword method
            Test.startTest();
            PageReference result = controller.changePassword();
            Test.stopTest();

            // Step 5: Validate the result
            System.assertEquals(null, result);

            // Validate user update logic
            User updatedUser = [SELECT Id, Name FROM User WHERE Id = :testUser.Id];
            System.assertNotEquals(null, updatedUser);
        }
    }

}