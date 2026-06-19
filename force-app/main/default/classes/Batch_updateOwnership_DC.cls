global class Batch_updateOwnership_DC implements Database.Batchable<sObject>, Database.Stateful {
	
    public String query;
    public String errors;
    
    public Batch_updateOwnership_DC(String query){
        this.query = query;
    }
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // collect the batches of records or objects to be passed to execute
        //this.query = String.isBlank(this.query)? 'SELECT Account_Name__c FROM Product_Ownership_detail__c': this.query;
        this.query = String.isBlank(this.query)? 'Select Id, Type,  DealCloud__c,Support_Level_DealCloud__c FROM Account WHERE Type = \'DealCloud Customer\' and SystemModStamp >= LAST_N_DAYS:2': this.query;
        return Database.getQueryLocator(query);
    }
    
    global void execute(Database.BatchableContext bc, List<Account> dcAccounts_list){
        // process each batch of records
        errors += Batch_updateOwnership_Handler.updateDCAccounts(dcAccounts_list);
        //POD_Handler.updateDealCloudCustomer(pod_list);
    }
    
    global void finish(Database.BatchableContext bc){
        // execute any post-processing operations
        Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].isSandbox;
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		mail.setSubject( isSandbox? '[SANDBOX] Errors: POD Ownership Batch': '[PROD] Errors: POD Ownership Batch');     
        mail.setToAddresses(new String[]{'venkat.sriram@intapp.com','srilakshmi.keesara@intapp.com'});
        mail.setSaveAsActivity(false);
        mail.setHtmlBody(errors);
        if(!String.isBlank(errors) && !Test.isRunningTest()){    
        	Messaging.sendEmail(new Messaging.Email[] { mail });
        }
    } 
}