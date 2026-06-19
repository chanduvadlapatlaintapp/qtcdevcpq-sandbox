/**
 * @description       : This trigger will handle all the events on Address object.
 * @author            : Pankaj Kumar
 * @last modified on  : 07-07-2023
 * @last modified by  : Pankaj Kumar
 * Modifications Log
 * Ver   Date         Author         Modification
 * 1.0   07-07-2023   Pankaj Kumar   Initial Version
**/
trigger AddressTrigger on Address__c (before insert,before update,after insert,after update, before delete, after delete) {
    
    TriggerDispatcher.run('Address__c');
}