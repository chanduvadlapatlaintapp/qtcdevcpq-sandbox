/**
 * @description       : Trigger for OpportunityLineItem
**/
trigger OpportunityProductTrigger on OpportunityLineItem (after delete, after insert, after undelete, after update, before insert, before update) {
    
    TriggerDispatcher.run('OpportunityLineItem');
}