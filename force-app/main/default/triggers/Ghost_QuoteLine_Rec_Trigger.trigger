/**
* @description       : This trigger will handle all the events on Ghost_QuoteLine_Reconciliation__c object.
* @author            : Ratan Paul
* @last modified on  : 09-09-2025
* @last modified by  : Ratan Paul
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   09-09-2025   Ratan Paul   Initial Version via BIZ-73446
**/
trigger Ghost_QuoteLine_Rec_Trigger on Ghost_QuoteLine_Reconciliation__c (before insert,before update,after insert,after update, before delete, after delete) {
	TriggerDispatcher.run('Ghost_QuoteLine_Reconciliation__c');
}