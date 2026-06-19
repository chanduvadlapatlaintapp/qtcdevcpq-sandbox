/**
* @description       : This trigger will handle all the events on Subscription object.
* @author            : Sonali Kakade
* @last modified on  : 06-23-2025
* @last modified by  : Sonali Kakade
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   06-23-2025   Sonali Kakade     Initial Version via BIZ-67339
**/
trigger SubscriptionTrigger on SBQQ__Subscription__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    
    TriggerDispatcher.run('SBQQ__Subscription__c');
    
}