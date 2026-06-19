/**
* @description       : This trigger handles all events on Term Quote object (Term_Quote__c).
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
trigger TermQuotesTrigger on Term_Quote__c (before insert, before update, after insert, after update, before delete, after delete, after undelete) {
    
    TriggerDispatcher.run('Term_Quote__c');
    
}