trigger Project_Trigger on Project__c (before insert, before update, after insert, after update) {
	if(trigger.isafter && trigger.isInsert) Project_TriggerHandler.afterInsert(trigger.new);
    if(trigger.isafter && trigger.isUpdate) Project_TriggerHandler.afterUpdate(trigger.new);
    if(trigger.isbefore && trigger.isInsert) Project_TriggerHandler.beforeInsert(trigger.new);
    if(trigger.isbefore && trigger.isUpdate) Project_TriggerHandler.beforeUpdate(trigger.new);
}