/**
 * @description Trigger for Validation_Checklist__c — delegates all events to TriggerDispatcher.
 *              Routes to ValidationChecklistTriggerHandler via TriggerSettings__mdt.
 * @author      Ratan Paul
 * @date        2026-05-19
 * @jira        BIZ-74558
 */
trigger Validation_ChecklistTrigger on Validation_Checklist__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    TriggerDispatcher.run('Validation_Checklist__c');
}