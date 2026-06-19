public class QuoteApprovalTriggerBatch implements Database.Batchable<sObject>, Database.Stateful,Schedulable { 
    @TestVisible
    private final String JOB_NAME;
    private final String QUOTE_APPROVAL_STATUS_APPROVED = 'Approved';
    private final String QUOTE_APPROVAL_STATUS_PENDING = 'Pending'; 
    private final String QUOTE_APPROVAL_STATUS_ERROR = 'Error'; 
    public static Boolean coverException = false;
    
    public QuoteApprovalTriggerBatch(){ 
        JOB_NAME = 'Quote Approval Trigger Batch'; 
    } 
    
    public QuoteApprovalTriggerBatch(String jobName){ 
        JOB_NAME = jobName; 
    } 
    
    public Database.querylocator start(Database.BatchableContext BC){ 
        set<string> productCodesToExclude = new set<string>{
            'GE-01554','GE-01567','GE-01647','GE-01646','BU-01408'
        };
        String queryForQuotes = 'SELECT Id' 
                                        + ', Name'
                                        + ', Number_of_QLIs__c'
                                        + ', Number_of_DLIs__c'
                                        + ', Counter__c'
                                        + ', ApprovalStatus__c'
                                        + ', Deal_ACV__c'
                                        + ', OP4I_Deal_Synced__c'
                                        + ', SBQQ__Uncalculated__c'
                                        + ', OP4I_OSA_Request_Received__c'
                                        + ', Submit_For_Approval__c'
                                        + ', Trigger_Quote_Calculation__c'
                                        + ', QLI_Update_Date_Time__c'
                                        + ', (SELECT Id FROM SBQQ__LineItems__r WHERE SBQQ__ProductCode__c NOT IN :productCodesToExclude) '
                                + ' FROM SBQQ__Quote__c'
                                + ' WHERE  OP4I_OSA_Request_Received__c = true'
                                        + ' AND  OP4I_Deal_Synced__c = true'
                                        + ' AND ApprovalStatus__c != :QUOTE_APPROVAL_STATUS_ERROR';                      
        return Database.getQueryLocator(queryForQuotes); 
    } 
    
    public void execute(Database.BatchableContext BC, List<sObject> sObjList){ 
        if(sObjList != null && !sObjList.isEmpty()){ 
            List<SBQQ__Quote__c> quoteToUpdate = new List<SBQQ__Quote__c>(); 
            Generic_Key_Value_Setting__mdt approvalErrorMaxRetrySetting = Generic_Key_Value_Setting__mdt.getInstance('Approval_Error_Max_Retry');
            
            Integer approvalErrorMaxRetry = Integer.valueOf(approvalErrorMaxRetrySetting.Value__c);
            for(sobject sobj: sObjList){
                SBQQ__Quote__c quoteObj = (SBQQ__Quote__c) sobj;
                //new quote instance to update to make sure we only update the required fields not all queried ones.
                SBQQ__Quote__c quoteObjUpdate = new SBQQ__Quote__c(Id = quoteObj.Id);
                try{ 
                    if(Test.isRunningTest() && coverException == true){
                        Integer exceptionVariable = 1/0;
                        }
                    if(quoteObj.Number_of_DLIs__c == quoteObj.Number_of_QLIs__c
                        && quoteObj.ApprovalStatus__c != QUOTE_APPROVAL_STATUS_APPROVED){
                        
                        if(quoteObj.Submit_For_Approval__c == true && quoteObj.QLI_Update_Date_Time__c < Datetime.Now().addMinutes(-2)){     
                            if(quoteObj.Deal_ACV__c == null){
                                quoteObjUpdate.ApprovalStatus__c = QUOTE_APPROVAL_STATUS_APPROVED;
                                quoteObjUpdate.OP4I_OSA_Request_Received__c = false;
                                quoteObjUpdate.OP4I_Deal_Synced__c = false;
                                quoteToUpdate.add(quoteObjUpdate );
                            } else{ 
                                                        
                                SBAA.ApprovalAPI.submit(quoteObj.id, SBAA__Approval__c.Quote__c); 
                                //quoteObj.ApprovalStatus__c = QUOTE_APPROVAL_STATUS_PENDING;
                                quoteObjUpdate.OP4I_OSA_Request_Received__c = false;
                                quoteObjUpdate.OP4I_Deal_Synced__c = false;
                                quoteToUpdate.add(quoteObjUpdate );
                                
                            }
                        } else {
                            quoteObjUpdate.QLI_Update_Date_Time__c = quoteObj.QLI_Update_Date_Time__c == null? Datetime.now() : quoteObj.QLI_Update_Date_Time__c;
                            quoteObjUpdate.Trigger_Quote_Calculation__c = !quoteObj.Trigger_Quote_Calculation__c;
                            quoteToUpdate.add(quoteObjUpdate );
                        }
                        
                    } else if(quoteObj.Number_of_DLIs__c != quoteObj.Number_of_QLIs__c
                        ||(quoteObj.SBQQ__Uncalculated__c == true)){
                        
                        if (quoteObj.Number_of_DLIs__c == quoteObj.SBQQ__LineItems__r.Size()) {
                            quoteObjUpdate.Trigger_Quote_Calculation__c = !quoteObj.Trigger_Quote_Calculation__c;
                            quoteToUpdate.add(quoteObjUpdate );
                        } else {
                            Decimal Counter = quoteObj.Counter__c == null ? 0 : quoteObj.Counter__c;
                            if(quoteObj.ApprovalStatus__c != QUOTE_APPROVAL_STATUS_ERROR){
                                Counter += 1;
                                quoteObjUpdate.Counter__c = Counter;
                                quoteToUpdate.add(quoteObjUpdate );
                            }
                        
                            if(Counter >= approvalErrorMaxRetry 
                                && (quoteObj.ApprovalStatus__c == QUOTE_APPROVAL_STATUS_PENDING 
                                    || string.isBlank(quoteObj.ApprovalStatus__c)) 
                            ){
                                quoteObjUpdate.ApprovalStatus__c = QUOTE_APPROVAL_STATUS_ERROR;   
                            }    
                        }    
                    }

                    
                }
                catch(Exception ex){
                    system.debug('ex--->'+ex.getMessage());
                    system.debug('ex--->'+ex.getStackTraceString());
                    Decimal Counter = quoteObj.Counter__c == null ? 0 : quoteObj.Counter__c;
                    if (quoteObj.ApprovalStatus__c != QUOTE_APPROVAL_STATUS_ERROR)
                    {
                        Counter += 1;
                        quoteObjUpdate.Counter__c = Counter;
                        quoteToUpdate.add(quoteObjUpdate );
                    }
                    if(Counter >= approvalErrorMaxRetry && quoteObj.ApprovalStatus__c == QUOTE_APPROVAL_STATUS_PENDING 
                        || string.isBlank(quoteObj.ApprovalStatus__c)
                    ){
                        quoteObjUpdate.ApprovalStatus__c = QUOTE_APPROVAL_STATUS_ERROR;   
                    }

                    /*Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                    message.toAddresses = new String[] { 'amol.sable@intapp.com' };
                    //message.optOutPolicy = 'FILTER';
                    message.subject = 'Approval Batch Error for ' + quoteObj.Name;
                    message.setHtmlBody('Message : ' + ex.getMessage() + '\n stacktrace : ' + ex.getStackTraceString());
                    Messaging.SingleEmailMessage[] messages =   new List<Messaging.SingleEmailMessage> {message};
                    Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);*/
                    
                }
            }
            
            if(!quoteToUpdate.isEmpty()){
                Database.update(quoteToUpdate);
            }
        }
    } 
    
    public void finish(Database.BatchableContext context) 
    { 
        abortAndCreateNewJob(context); 
    } 
    
    public void execute(SchedulableContext sc)  
    { 
        QuoteApprovalTriggerBatch batch = new QuoteApprovalTriggerBatch(); 
        database.executebatch(batch, 1); 
    } 
    
    //Aborts the existing scheduled job. Then calls rescheduleJob to reschedule this job. 
    private void abortAndCreateNewJob(Database.BatchableContext context) 
    { 
        if (context == null){ 
            return; 
        } 
        
        //Need to query CronJobDetail to find our currently active scheduled job 
        List<CronJobDetail> cronJobDetails = [SELECT Id FROM CronJobDetail WHERE Name=  
                                                :JOB_NAME LIMIT 1]; 
        
        if (cronJobDetails.isEmpty()){ 
            return; 
        } 
        
        //Need to find the corresponding cron trigger to be able to abort the scheduled job 
        List<CronTrigger> cronTriggers = [SELECT Id FROM CronTrigger WHERE  
                                            CronJobDetailId = :cronJobDetails[0].Id LIMIT 1]; 
        
        if(cronTriggers.isEmpty()){ 
            return; 
        } 
        
        try{ 
            //Aborts the job current setup for this scheduled class 
            System.abortJob(cronTriggers[0].Id); 
        
            // Reschedules this job for one minute in the future. 
            Generic_Key_Value_Setting__mdt configurableScheduleMetadata = Generic_Key_Value_Setting__mdt.getInstance('Quote_Approval_Job_Interval_Minute'); 
    
            Integer jobInterval = Integer.valueOf(configurableScheduleMetadata.Value__c); 
            Datetime sysTime = System.now().addMinutes(jobInterval); 
            String cronExpression = '' + sysTime.second() + ' ' + sysTime.minute() + ' ' +
                sysTime.hour() + ' ' + sysTime.day() + ' ' + sysTime.month() + ' ? ' +   sysTime.year(); 
            
            System.schedule(JOB_NAME, cronExpression, new QuoteApprovalTriggerBatch()); 
        } 
        
        catch (Exception e){ 
            System.debug('Error Aborting Quote Approval Trigger Batch: ' + e.getMessage()); 
        } 
    } 
}