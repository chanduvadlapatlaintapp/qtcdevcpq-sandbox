/**
 * @description Trigger for Item_Master_Product__c object
 */
trigger ItemMasterProductTrigger on Item_Master_Product__c (before insert,before update,after insert,after update, before delete, after delete) {
    // Call the TriggerDispatcher class to handle the trigger events
    TriggerDispatcher.run('Item_Master_Product__c');
}