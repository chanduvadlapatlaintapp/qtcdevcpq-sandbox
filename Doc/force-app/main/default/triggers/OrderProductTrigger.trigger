/**
* @description       : This trigger will handle all the events on Order Product object.
**/
trigger OrderProductTrigger on OrderItem (before insert,before update,after insert,after update, before delete, after delete) {
    TriggerDispatcher.run('OrderItem');
}