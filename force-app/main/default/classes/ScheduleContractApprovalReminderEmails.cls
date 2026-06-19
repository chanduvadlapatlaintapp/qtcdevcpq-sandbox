global class ScheduleContractApprovalReminderEmails implements Schedulable {
 
 // Run the job every day at 9 am
    public static String CRON_EXP = '0 0 9 * * ?';
 
  global void execute(SchedulableContext ctx) {  
   
   ContractApprovalReminderEmails ARE = new ContractApprovalReminderEmails();
   // the batch size can be no larger than 10 due to current apex email limits
   integer batchSize = 10;
   database.executebatch(ARE, batchSize);
   
  } // execute 
  
    static testmethod void TestcheduleContractApprovalReminderEmails() {
  Test.startTest();
   
       // Schedule the test job  
        String jobId = System.schedule('TestScheduleContractApprovalReminderEmails',
                ScheduleContractApprovalReminderEmails.CRON_EXP, 
                 new ScheduleContractApprovalReminderEmails());
                  
     // Get the information from the CronTrigger API object  
        CronTrigger ct = [SELECT id, CronExpression, TimesTriggered, 
           NextFireTime
           FROM CronTrigger WHERE id = :jobId];
   
     // Verify the expressions are the same  
        System.assertEquals(ScheduleContractApprovalReminderEmails.CRON_EXP, 
           ct.CronExpression);
   
     // Verify the job has not run  
        System.assertEquals(0, ct.TimesTriggered);
         
     Test.stopTest();    
   } // CRON test method
    
} // end ScheduleContractApprovalReminderEmails class