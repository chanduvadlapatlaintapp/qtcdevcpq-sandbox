/**
 * @description       : Trigger for order
**/
trigger OrderTrigger on Order (before insert,before update,after insert,after update, before delete, after delete) {
    
    TriggerDispatcher.run('Order');
}