global class Batch_updateOwnership_DC_Scheduler implements schedulable{

    global void execute(SchedulableContext sc){
        Batch_updateOwnership_DC dc_accounts = new Batch_updateOwnership_DC('');
        database.executebatch(dc_accounts);
    }
    
}