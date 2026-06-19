/**
* @description       : This trigger will handle all the events on Quote object.
* @author            : Pooja Hemrajani
* @last modified on  : 03-20-2025
* @last modified by  : Pooja Hemrajani
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   03-20-2025   Pooja Hemrajani   Initial Version via BIZ-66415
**/
trigger QuoteTrigger on SBQQ__Quote__c (before insert,before update,after insert,after update, before delete, after delete) {
    
    TriggerDispatcher.run('SBQQ__Quote__c');
    
}