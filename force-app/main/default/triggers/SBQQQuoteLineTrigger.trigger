/**
* @description       : This trigger will handle all the events on Quote Line object.
* @author            : Pooja Hemrajani
* @last modified on  : 03-20-2025
* @last modified by  : Pooja Hemrajani
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   03-20-2025   Pooja Hemrajani   Initial Version via BIZ-66416
**/
trigger SBQQQuoteLineTrigger on SBQQ__QuoteLine__c (after delete, after insert, after update, after undelete, before delete, before insert, before update) {
    
    TriggerDispatcher.run('SBQQ__QuoteLine__c');
    
}