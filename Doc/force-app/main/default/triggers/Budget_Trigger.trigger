trigger Budget_Trigger on Budget__c (before insert, before update, after insert, after update) {
	if(trigger.isBefore && trigger.isInsert) Budget_TriggerHandler.beforeInsert(trigger.new);
    if(trigger.isBefore && trigger.isUpdate) Budget_TriggerHandler.beforeUpdate(trigger.new);
    if(trigger.isAfter && trigger.isInsert) Budget_TriggerHandler.afterInsert(trigger.new);
    if(trigger.isAfter && trigger.isUpdate) Budget_TriggerHandler.afterUpdate(trigger.new);
}