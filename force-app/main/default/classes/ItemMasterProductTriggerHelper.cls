/**
* @description       : This class is a Helper class for ItemMasterProduct Trigger.
* @author            : Suresh Somu
**/
public inherited sharing class ItemMasterProductTriggerHelper {
    
    /**********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/
    /**
     * 
     * @description This method is used to validate insert or update Name field.
     * @param newRecords List of new records
     * @param oldRecords map of old records
     */
    public static void validateItemMasterName(List<Item_Master_Product__c> newRecords, Map<Id, Item_Master_Product__c> oldRecords) {
        Intapp_Settings__c setting = Intapp_Settings__c.getOrgDefaults();
        if(setting.Disable_PIN_Number_Validation__c){
            return;
        }
        Set<String> incomingNames = new Set<String>();
        Boolean isInsert = (oldRecords == null);

        for (Item_Master_Product__c rec : newRecords) {
            Boolean isNameChanged = !isInsert && (rec.Name != oldRecords.get(rec.Id).Name);
            if (incomingNames.contains(rec.Name)) {
                rec.addError('Duplicate Name found within same request: ' + rec.Name);
            } else if(!isInsert && isNameChanged) {
                rec.addError('Updating the Name field is not allowed.');
            } else {
                incomingNames.add(rec.Name);
            }
        }

        Map<String, String> existingNamesMap = getExistingNamesMap(incomingNames);
        
        for (Item_Master_Product__c newRec : newRecords) {
            if (nameExists(existingNamesMap, newRec, isInsert)) {
                newRec.addError('A record with Name "' + newRec.Name + '" already exists.');
            }
        }
    }
    
    /**
    * @description Handles the after update logic for Item_Master_Product__c records.
    *              It identifies records that need to be published to the external system based on changes in Sync_NetSuite__c field
    *              or presence of a NetSuite Internal ID.
    *              Calls IntegrationUtility to publish those records accordingly.
    *
    * @param itemMasterList The list of new Item_Master_Product__c records after update.
    * @param itemMasterOldMap A map of old Item_Master_Product__c records before update, keyed by record Id.
    */
    public static void publishItemMasterProductsAfterUpdate(List<Item_Master_Product__c> itemMasterList,Map<Id, Item_Master_Product__c> itemMasterOldMap) {
        List<Item_Master_Product__c> syncList = new List<Item_Master_Product__c>();
        List<Item_Master_Product__c> createList = new List<Item_Master_Product__c>();
        
        for (Item_Master_Product__c imp : itemMasterList) {
            Item_Master_Product__c oldImp = itemMasterOldMap.get(imp.Id);
            if (imp.Sync_NetSuite__c == true && imp.Sync_NetSuite__c != oldImp.Sync_NetSuite__c) {
                    syncList.add(imp);
            }
            
            Boolean triggerCheckedNow = imp.Trigger_to_NS__c == true && imp.Trigger_to_NS__c != oldImp.Trigger_to_NS__c;     
            if (triggerCheckedNow && imp.NetSuite_Internal_Id__c == null) {
                createList.add(imp);
            }
        }
        
        if (!createList.isEmpty()) {
            IntegrationUtility.publishsObjectRecords(createList, 'Item_Master_Product__c');
        }
        
        if (!syncList.isEmpty()) {
            IntegrationUtility.publishsObjectRecords(syncList, 'Item_Master_Product__c');
        }
    }

    
    /**
    * @description Handles the after insert logic for Item_Master_Product__c records.
    *              Publishes all inserted records to the external system using IntegrationUtility.
    *
    * @param itemMasterList The list of newly inserted Item_Master_Product__c records.
    */
    public static void publishItemMasterProductsAfterInsert(List<Item_Master_Product__c> itemMasterList) {
        List<Item_Master_Product__c> createList = new List<Item_Master_Product__c>();
        
        for (Item_Master_Product__c imp : itemMasterList) {
            if (imp.Trigger_to_NS__c == true && imp.NetSuite_Internal_Id__c == null) {
                createList.add(imp);
            }
        }
        
        if (!createList.isEmpty()) {
            IntegrationUtility.publishEligibleSobjectRecords(createList, null, 'Item_Master_Product__c');
        }
    }
    
    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/
    /**
     * @description This method checks if the name already exists in the map.
     * @param existingNamesMap Map of existing names
     * @param newRec The new record being processed
     * @param isInsert Boolean indicating if this is an insert operation
     * @return Boolean indicating if the name exists
     */
    private static Boolean nameExists(Map<String, String> existingNamesMap,Item_Master_Product__c newRec,Boolean isInsert) {
        Boolean nameExists = existingNamesMap.containsKey(newRec.Name);
        return (isInsert &&  nameExists) || 
                (!isInsert && nameExists && existingNamesMap.get(newRec.Name) != newRec.Id);
    }

    /**
     * @description This method retrieves existing names from the database.
     * @param incomingNames Set of incoming names
     * @return Map of existing names
     */
    private static Map<String, String> getExistingNamesMap(Set<String> incomingNames) {
        Map<String, String> existingNamesMap = new Map<String, String>();
        for (Item_Master_Product__c item : [SELECT Id, Name 
                                            FROM Item_Master_Product__c 
                                            WHERE Name IN :incomingNames]) {
            existingNamesMap.put(item.Name, item.Id);
        }
        return existingNamesMap;
    }
}