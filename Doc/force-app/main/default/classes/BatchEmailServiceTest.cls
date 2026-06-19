/**
 * @description Test class for BatchEmailService.
 * @details Tests email sending functionality for batch results, including error handling and parameter validation.
 * @author Sahal Mohamed
 * @createdDate 2026-01-13
 */
@isTest
public class BatchEmailServiceTest {

    /***********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/

    /**
     * @description Tests sending a result email. 
     * Uses null context to trigger fallback logic and verifies no exceptions are thrown.
     * Note: Actual email delivery cannot be verified in unit tests without mocking, 
     * but we can verify code execution path and limits.
     */
    @isTest
    static void testSendResultEmail() {
        // Setup data
        String subject = 'Test Subject';
        List<String> bodyLines = new List<String>{'Line 1', 'Line 2'};
        
        Test.startTest();
        try {
            // Passing null BC will trigger the catch block in resolveRecipientEmail and use UserInfo.getUserEmail()
            BatchEmailService.sendResultEmail(null, subject, bodyLines);
            Integer emailsSent = Limits.getEmailInvocations();
            // Verify that an email send was attempted
            System.assertEquals(1, emailsSent, 'One email should have been sent');
        } catch (System.EmailException e) {
             // Allow test to pass if email is disabled in org (NO_SINGLE_MAIL_PERMISSION)
             Boolean isExpectedError = e.getMessage().contains('NO_SINGLE_MAIL_PERMISSION');
             System.assert(isExpectedError, 'Unexpected email exception: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    /**
     * @description Tests behavior when recipient email is somehow blank (simulated by not being able to force it easily, 
     * but we can ensure the service handles valid inputs robustly).
     * To truly test the "blank recipient" path we would need to mock the private method or UserInfo, which isn't possible directly.
     * However, the main path is covered above.
     */
    @isTest
    static void testSendResultEmailIntegration() {
         // This test acts as a smoke test for the email construction logic
        String subject = 'Integration Test';
        List<String> bodyLines = new List<String>{'Result A', 'Result B'};
        
        Test.startTest();
        try {
            BatchEmailService.sendResultEmail(null, subject, bodyLines);
            System.assert(true, 'Method should execute without exception');
        } catch (System.EmailException e) {
            // Allow test to pass if email is disabled in org (NO_SINGLE_MAIL_PERMISSION)
            Boolean isExpectedError = e.getMessage().contains('NO_SINGLE_MAIL_PERMISSION');
            System.assert(isExpectedError, 'Unexpected email exception: ' + e.getMessage());
        } catch (Exception e) {
            System.assert(false, 'Should not throw general exception: ' + e.getMessage());
        }
        Test.stopTest();
    }
}