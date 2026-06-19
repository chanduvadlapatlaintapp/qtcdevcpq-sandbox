trigger DealEventTrigger on DealEvent__e (after insert) {
 //calling the trigger handler
    if(Trigger.isAfter && Trigger.isInsert){
        system.debug('inside after insert event');
        DealEventTriggerHandler.processEventForLogging(trigger.new);
    }
}