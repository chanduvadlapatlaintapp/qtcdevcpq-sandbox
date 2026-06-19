/**
* @description This trigger will handle all the events on Quote Document object.
**/
trigger QuoteDocumentTrigger on SBQQ__QuoteDocument__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    
    TriggerDispatcher.run('SBQQ__QuoteDocument__c');
    
}