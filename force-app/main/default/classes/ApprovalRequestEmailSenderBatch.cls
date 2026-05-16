/**
 * @description Batch class for triggering Emails for Pendig Approvals
 * @author Suresh Kumar
 * @jira BIZ-68914
 */
public without sharing class ApprovalRequestEmailSenderBatch implements Database.Batchable<sObject>, Schedulable, Database.Stateful {
    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    private String query;
    private Integer scopeSize;
    private Id emailTemplateId;

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    
    /**
    * @description parameterized Constructor
    * @param scopeSize
    * @param emailTemplateId
    **/
    public ApprovalRequestEmailSenderBatch(Integer scopeSize, String emailTemplateId) {
        this.query = getDefaultQuery();
        this.scopeSize = scopeSize ?? 50;
        this.emailTemplateId = Id.valueOf(emailTemplateId);
    }
    /**
    * @description parameterized Constructor
    * @param query
    * @param scopeSize
    * @param emailTemplateId
    **/
    public ApprovalRequestEmailSenderBatch(String query, Integer scopeSize, String emailTemplateId) {
        this.query = query;
        this.scopeSize = scopeSize;
        this.emailTemplateId = Id.valueOf(emailTemplateId);
    }

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description Method that can be used to override the query and scope size
    * @param query
    * @param scopeSize
    * @param emailTemplateId
    **/
    public void executeBatch(String query, Integer scopeSize, String emailTemplateId) {
        ApprovalRequestEmailSenderBatch obj;
        if(query == null){
            obj = new ApprovalRequestEmailSenderBatch(scopeSize, emailTemplateId);
        }
        else {
            obj = new ApprovalRequestEmailSenderBatch(query, scopeSize, emailTemplateId);
        }
        
        Database.executeBatch(obj, scopeSize);
    }

    /***********************************************************************************************
    *
    * Batch Methods
    *
    ***********************************************************************************************/
    /**
    * @description start method
    * @param bc
    * @return Database.QueryLocator
    */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query renewal letters that need to be processed
        String query = this.query;
        return Database.getQueryLocator(query);
    }

    /**
     * @description Method to send email for pending approvals.
     * @param context BatchableContext
     * @param scope List of User
     */
    public void execute(Database.BatchableContext context, List<User> scope) {
        List<User> users = (List<User>) scope;
    
        String currentDate = Datetime.now().format('MM-dd-yyyy hh:mm a');
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
    
        for (User user : users) {
            Messaging.SingleEmailMessage mail = Messaging.renderStoredEmailTemplate(emailTemplateId, user.Id, user.Id);
            mail.setSaveAsActivity(false);
            mail.setSubject('[URGENT] Action required: you have outstanding OSA approvals at ' + currentDate);
            emailsToSend.add(mail);
        }
    
        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.sendEmail(emailsToSend);
                ApprovalRequestEmailSenderBatchTest.emailStatus = true;
            } catch (Exception e) {
                ApprovalRequestEmailSenderBatchTest.emailStatus = false;
            }
        }
    }

    /**
     * @description Finish Method for optional logging
     */
    public void finish(Database.BatchableContext context) {
    }

    /***********************************************************************************************
    *
    * Schedulable Methods
    *
    ***********************************************************************************************/
    /**
    * @description execute method
    * @param sc
    **/
    public void execute(SchedulableContext sc) {
        // Execute the batch job
        executeBatch(this.query, this.scopeSize, this.emailTemplateId);
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /**
    * @description set the default query
    * @return String
    **/
    private String getDefaultQuery() {
        String defaultQuery;
        Set<Id> userIdSet = ApprovalRequestController.getRelevantUserIdsFromApprovals();
    
        if (!userIdSet.isEmpty()) {
            List<String> userIdStrings = new List<String>();
            for (Id userId : userIdSet) {
                userIdStrings.add(String.valueOf(userId));
            }
    
            String idList = '\'' + String.join(userIdStrings, '\', \'') + '\'';
            defaultQuery = 'SELECT Id, Name, Email FROM User WHERE Id IN (' + idList + ')';
        } else {
            defaultQuery = 'SELECT Id, Name, Email FROM User WHERE Id = null'; // Always returns no rows
        }
    
        return defaultQuery;
    }
    

}