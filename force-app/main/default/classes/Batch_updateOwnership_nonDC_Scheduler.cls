global class Batch_updateOwnership_nonDC_Scheduler implements schedulable{

    global void execute(SchedulableContext sc){
        Batch_updateOwnership_nonDC intapp_accounts = new Batch_updateOwnership_nonDC('');
        database.executebatch(intapp_accounts);
    }
    
}