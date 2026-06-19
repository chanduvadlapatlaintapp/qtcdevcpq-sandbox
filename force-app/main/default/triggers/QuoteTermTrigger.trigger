/**
* @description       : This trigger will handle all the events on Quote Term object.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
trigger QuoteTermTrigger on SBQQ__QuoteTerm__c (before insert, before update, after insert, after update, before delete, after delete, after undelete) {
    
    TriggerDispatcher.run('SBQQ__QuoteTerm__c');
    
}