/**
 * @description Service class to handle email operations for batch processing results.
 * @details Provides centralized email functionality for sending batch execution results to appropriate recipients.
 *          Handles recipient resolution, email construction, and delivery with comprehensive error handling and logging.
 *          Supports fallback mechanisms for recipient resolution and standardized email formatting for batch notifications.
 * @author Sahal Mohamed
 */
public with sharing class BatchEmailService {
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
     * @description Sends an email with batch results to the specified recipient.
     * @param bc Batchable context to resolve the batch executor.
     * @param subject Email subject line.
     * @param bodyLines List of content lines to include in the email body.
     */
    public static void sendResultEmail(Database.BatchableContext bc, String subject, List<String> bodyLines) {
        String recipientEmail = resolveRecipientEmail(bc);
        
        if (String.isBlank(recipientEmail)) {
            Nebula.Logger.error('No recipient email available to send batch results.');
            return;
        }
        
        Messaging.SingleEmailMessage mail = createEmail(recipientEmail, subject, bodyLines);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        Nebula.Logger.info('Sent batch results email to ' + recipientEmail);
    }
    
    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    /**
     * @description Resolves the recipient email address from batch context or falls back to current user.
     * @param bc Batchable context containing job information.
     * @return Email address of the recipient.
     */
    private static String resolveRecipientEmail(Database.BatchableContext bc) {
        try {
            AsyncApexJob job = [SELECT Id, CreatedBy.Email FROM AsyncApexJob WHERE Id = :bc.getJobId() LIMIT 1];
            return job.CreatedBy.Email;
        } catch (Exception eJob) {
            Nebula.Logger.error('Could not resolve batch executor email; falling back to current user. ' + eJob.getMessage());
            return UserInfo.getUserEmail();
        }
    }
    
    /**
     * @description Creates a formatted email message.
     * @param recipientEmail The recipient's email address.
     * @param subject The email subject.
     * @param bodyLines List of content lines for the email body.
     * @return Configured SingleEmailMessage instance.
     */
    private static Messaging.SingleEmailMessage createEmail(String recipientEmail, String subject, List<String> bodyLines) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { recipientEmail });
        mail.setSubject(subject);
        mail.setPlainTextBody('Hello,\n\nThe batch process completed. Results:\n\n' + String.join(bodyLines, '\n\n') + '\n\nRegards,\nBatch Process');
        return mail;
    }
}