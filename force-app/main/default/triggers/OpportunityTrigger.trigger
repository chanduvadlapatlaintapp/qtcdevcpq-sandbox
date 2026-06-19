/**
 @description
  This trigger is used to handle the Opportunity object events.
  It uses the TriggerDispatcher class to manage the trigger events.
**/
trigger OpportunityTrigger on Opportunity (before insert,before update,after insert,after update, before delete, after delete) {
    TriggerDispatcher.run('Opportunity');
}