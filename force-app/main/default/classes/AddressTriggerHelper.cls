/**
* @description       : This class is a Helper class for AddressTrigger.
* @author            : Sahal Mohamed
* Created Date       : Mar-17-2025
*                      V-1.1 - Modified By Pooja Hemrajani - BIZ-68205
**/
public inherited sharing class AddressTriggerHelper {

    // Added to stop Recursion
    private static Boolean updatesFromIntegration = true;

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description : This method will handle Address Name update on Address object.
    * @author Pankaj Kumar | 10-20-2023 
    * @param newAddressList 
    * @param oldMap
    * @param isInsert
    **/    
    public static void addressNameUpdate(List<Address__c> newAddressList,Map<Id,Address__c> oldMap,boolean isInsert){       
        
        List<Address__c> addList = new List<Address__c>();
        Set<id> newAddIds = new Set<id>();
        for(Address__c address : newAddressList){
            newAddIds.add(address.Id);
        }
        Map<Id, Address__c> mapIdAddress= new Map<Id, Address__c>([SELECT Id, Address__c,Account__c,Default_Billing_Address__c,Default_Shipping_Address__c
                                                                     FROM Address__c WHERE Id =:newAddIds]);
        for(Address__c address : newAddressList){
            Account acc = new Account();                
            acc.Id = address.Account__c;
            Address__c ad = mapIdAddress.get(address.Id);
            Address add = (Address)ad.Address__c;
            Address__c oldAddress = (!isInsert) ? oldMap.get(address.Id) : new Address__c();
            if((isInsert && isAddressPopulated(address)) ||
                (!isInsert && isAddressChanged(address, oldAddress))){
                    Address__c a = new Address__c();
                    a.Name = address.Address__City__s + '-' + add.getState() + '-' + address.Address__PostalCode__s;
                    a.Country__c = add.getCountry();
                    a.Id = address.Id;
                    addList.add(a);
            }
        }
        if(!addList.isEmpty()){
            // Update addresses
            List<Database.SaveResult> results = Database.update(addList, false);
            ResultHandler.logErrors('AddressTriggerHandler addressNameUpdate', addList, results);
        }

    }

    /**
    * @description : This method will handle RestrictInactiveStatusForDefaultAddress on Address object.
    * @author Pankaj Kumar | 10-20-2023 
    * @param newAddressList 
    * @param oldMap 
    * @param isInsert
    **/    
    public static void addressStatusInactive(List<Address__c> newAddressList,Map<Id,Address__c> oldMap,boolean isInsert){
        Set<Id> accIds = new Set<Id>();
        Set<Id> newAddrId = new Set<Id>();
        Map<Id, Id> mapAccAddress = new Map<Id, Id>();
        for(Address__c addr: newAddressList){
            if(addr.Default_Billing_Address__c== false && addr.Default_Billing_Address__c==false 
            && oldMap.get(addr.Id).Status__c!=addr.Status__c && addr.Status__c == 'Inactive'){
                accIds.add(addr.Account__c);
                newAddrId.add(addr.Id);
            }
        }
        List<Address__c> adrList = [SELECT Id, Default_Billing_Address__c, Default_Shipping_Address__c, Account__c 
                                    FROM Address__c 
                                    WHERE Account__c =:accIds AND (Default_Billing_Address__c = true OR Default_Shipping_Address__c = true) AND Id NOT IN :newAddrId];
        
        if(adrList != null){
            for(Address__c adr : adrList){
                mapAccAddress.put(adr.Account__c, adr.Id);
            }
        }
        for(Address__c addr: newAddressList){
            if(addr.Default_Billing_Address__c == false && addr.Default_Shipping_Address__c == false 
                && oldMap.get(addr.Id).Status__c != addr.Status__c && addr.Status__c == 'Inactive' && !mapAccAddress.containsKey(addr.Account__c)){
                addr.addError('Please create a new address with Default Billing / Shipping Address checked before updating the Status to Inactive.');
            }
        }   
    }   

    /**
    * @description : Created as part of BIZ-45061. This method will handle default billing address & default shipping address type selection/deselection automation.
    * @author Pankaj Kumar | 07-07-2023 
    * @param newAddressList 
    * @param oldMap 
    * @param isInsert 
    **/
    public static void defaultAddressDeselection(List<Address__c> newAddressList,Map<Id,Address__c> oldMap,boolean isInsert){
        
        Set<Id> accIds = new Set<Id>();
        Set<id> addId = new Set<Id>();
        Map<Id, Address__c> oldAddressUpdateMap = new Map<Id, Address__c>();
        List<Address__c> addList = new List<Address__c>();
        List<Address__c> addrList = null;
        Map<String,List<Address__c>> mapAccAddressList = new Map<String,List<Address__c>>();
        for(Address__c addr: newAddressList){
            if(isInsert && addr.Account__c!=null && (addr.Default_Billing_Address__c==true || addr.Default_Shipping_Address__c==true)){
                accIds.add(addr.Account__c);
                addId.add(addr.Id);
            }else if(!isInsert && ((addr.Default_Billing_Address__c!=oldMap.get(addr.Id).Default_Billing_Address__c) 
                                    ||(addr.Default_Shipping_Address__c!=oldMap.get(addr.Id).Default_Shipping_Address__c))
                        && addr.Account__c!=null){
                            accIds.add(addr.Account__c);
                            addId.add(addr.Id);
                        }
        }
        if(!accIds.isEmpty()){
            addrList = [SELECT Id, Account__c, Default_Billing_Address__c, Default_Shipping_Address__c 
                        FROM Address__c 
                        WHERE Account__c = :accIds AND (Default_Billing_Address__c = true OR Default_Shipping_Address__c = true) AND Id NOT IN :addId];
        }
        if(addrList!=null && !addrList.isEmpty()){ 
            for(Address__c addr : addrList){
                if(mapAccAddressList.containsKey(addr.Account__c)){
                    addList = mapAccAddressList.get(addr.Account__c);
                    addList.add(addr);
                    mapAccAddressList.put(addr.Account__c,addList);
                }else{                
                    mapAccAddressList.put(addr.Account__c,new List<Address__c>{addr});
                }
            }
            for(Address__c addr : newAddressList){
                for(Address__c addres : mapAccAddressList.get(addr.Account__c)){
                    //Added as part of BIZ-67475
                    Boolean isValueChanged = false;
                    if((isInsert || (!isInsert && (addr.Default_Billing_Address__c != oldMap.get(addr.Id).Default_Billing_Address__c)))
                        && addr.Account__c != null && addr.Default_Billing_Address__c && addres.Default_Billing_Address__c){
                            Address__c existingAddress = addres;
                            if(oldAddressUpdateMap.containsKey(addres.Id)){
                                existingAddress = oldAddressUpdateMap.get(addres.Id);
                            }
                            existingAddress.Default_Billing_Address__c = false; 
                            oldAddressUpdateMap.put(existingAddress.Id, existingAddress);                  
                        }
                    if((isInsert || (!isInsert && (addr.Default_Shipping_Address__c != oldMap.get(addr.Id).Default_Shipping_Address__c)))
                        && addr.Account__c != null && addr.Default_Shipping_Address__c && addres.Default_Shipping_Address__c){
                        Address__c existingAddress = addres;
                        if(oldAddressUpdateMap.containsKey(addres.Id)){
                            existingAddress = oldAddressUpdateMap.get(addres.Id);
                        }
                        existingAddress.Default_Shipping_Address__c = false;  
                        oldAddressUpdateMap.put(existingAddress.Id, existingAddress); 
                    }
                } 
            }
            // Update addresses
            if(oldAddressUpdateMap != null){
                updatesFromIntegration = false;
                List<Database.SaveResult> results = Database.update(oldAddressUpdateMap.values(), false);
                ResultHandler.logErrors('AddressTriggerHandler defaultAddressDeselection', oldAddressUpdateMap.values(), results);
            }
        }

    } 
    
    /**
    * @description :  Created as part of BIZ-45062. This method will handle billing & shipping address population on Account object.
    * @author Pankaj Kumar | 07-07-2023 
    * @param newAddressList 
    * @param oldMap 
    * @param isInsert 
    **/  
    public static void defaultAddressPopulation(List<Address__c> newAddressList, Map<Id,Address__c> oldMap, Boolean isInsert){
        Map<Id, Account> accMap = new Map<Id, Account>();
        Set<Id> newAddIds = new Set<Id>();
        for(Address__c address : newAddressList){
            if(String.isNotBlank(address.Account__c)) {
                newAddIds.add(address.Id);
            }
        }

        Map<Id,Address__c> mapIdAddress= new Map<Id,Address__c>([SELECT Id, Address__c,Account__c,Default_Billing_Address__c,Default_Shipping_Address__c FROM Address__c WHERE Id = :newAddIds]);

        for(Address__c addr : newAddressList){                
            Account acc  = new Account();
            if(accMap.containsKey(addr.Account__c)){
                acc = accMap.get(addr.Account__c);
            }           
            Address__c ad = mapIdAddress.get(addr.Id);
            Address add; 
            if (ad != null && ad.Address__c != null) {
                add = (Address)ad.Address__c;
            }
            Address__c oldAddress = (!isInsert) ? oldMap.get(addr.Id) : new Address__c();
            if(isInsert || (!isInsert && isAddressDefaultsChanged(addr, oldAddress))){
                if(addr.Default_Billing_Address__c){
                    acc.BillingCity = addr.Address__City__s;
                    acc.BillingPostalCode = addr.Address__PostalCode__s;
                    acc.BillingStreet = addr.Address__Street__s;
                    if (add != null) {
                        acc.BillingCountry = add.getCountry();
                        acc.BillingState = add.getStateCode();
                    }
                    acc.DefaultBillingAddress__c = addr.Id;
                }
                if(addr.Default_Shipping_Address__c){
                    acc.ShippingCity = addr.Address__City__s;
                    if (add != null) {
                        acc.ShippingCountry = add.getCountry();
                        acc.ShippingState = add.getStateCode();
                    }
                    acc.ShippingPostalCode = addr.Address__PostalCode__s;
                    acc.ShippingStreet = addr.Address__Street__s;
                    acc.DefaultShippingAddress__c = addr.Id;
                }   
                acc.Id = addr.Account__c;
                accMap.put(acc.Id, acc);
            }
        }

        // Update accounts with default addresses
        updatesFromIntegration = false;
        List<Database.SaveResult> results = Database.update(accMap.values(), false);
        ResultHandler.logErrors('AddressTriggerHandler defaultAddressPopulation', accMap.values(), results);
    }

    /**
    * @description Update order addresses
    * @param newAddressList 
    * @param oldMap 
    **/ 
    public static void updateOrders(List<Address__c> newAddressList, Map<Id,Address__c> oldMap){
        Set<Id> accIds = new Set<Id>();
        Map<Id,Address__c> addressMap = new Map<Id, Address__c>();
        for(Address__c addr: newAddressList){
            if(addr.Default_Billing_Address__c || addr.Default_Shipping_Address__c){
                accIds.add(addr.Account__c);
                addressMap.put(addr.Account__c, addr);
            }
        }        
        
        List<Order> orderLstToUpdate = new List<Order>();
        for(Order ord : [SELECT Id,Status,SBQQ__Quote__r.Software_Delivery_Contact__c, SBQQ__Quote__r.Invoicing_Contact__c , SBQQ__Quote__r.OSA_Signature_Date__c,SBQQ__Quote__r.Booking_Date__c,SBQQ__Quote__r.Renewal_Quote_Type__c,
                            CreatedDate,AccountId, Billing_Attention__c, Billing_Addressee__c, Billing_Phone__c,Shipping_Phone__c,Shipping_Attention__c, Shipping_Address__c 
                        FROM Order 
                        WHERE AccountId IN :accIds AND Status = :OrderConstants.STATUS_DRAFT]){

            Address__c address = addressMap.get(ord.AccountId);
            if(ord.SBQQ__Quote__r.OSA_Signature_Date__c != null && ord.SBQQ__Quote__r.Booking_Date__c != null && ord.SBQQ__Quote__r.Software_Delivery_Contact__c != null && ord.SBQQ__Quote__r.Invoicing_Contact__c != null){
                if(address.Default_Billing_Address__c){
                    ord.Billing_Attention__c = address.Billing_Attn__c;
                    ord.Billing_Addressee__c = address.Addressee__c;
                    ord.Billing_Phone__c = address.Phone__c; 
                    
                }
                if(address.Default_Shipping_Address__c){
                    ord.Shipping_Attention__c = address.Billing_Attn__c;
                    ord.Shipping_Address__c = address.Addressee__c;
                    ord.Shipping_Phone__c = address.Phone__c;
                    
                }
                orderLstToUpdate.add(ord); 
            }
            
        }
        // Update order addresses
        List<Database.SaveResult> results = Database.update(orderLstToUpdate, false);
        ResultHandler.logErrors('AddressTriggerHandler updateOrders', orderLstToUpdate, results);
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /**
    * @description Returns true if address defaults changed, false otherwise
    *              V1.1 - Updated the conditions to include city, postalcode, state and street changes - Pooja Hemrajani - BIZ-68195
    * @param address 
    * @param oldAddress
    * @return Boolean - True if default address changed, false otherwise 
    **/
    private static Boolean isAddressDefaultsChanged(Address__c address, Address__c oldAddress) {
        return (
            ((address.Default_Billing_Address__c != oldAddress.Default_Billing_Address__c) 
                || (address.Default_Shipping_Address__c != oldAddress.Default_Shipping_Address__c)
                || (address.Address__City__s != oldAddress.Address__City__s)
                || (address.Address__PostalCode__s != oldAddress.Address__PostalCode__s)
                || (address.Address__StateCode__s != oldAddress.Address__StateCode__s)
                || (address.Address__Street__s != oldAddress.Address__Street__s)
                || (address.Address__CountryCode__s != oldAddress.Address__CountryCode__s))
            && (address.Default_Billing_Address__c || address.Default_Shipping_Address__c)
        );
    }

    /**
    * @description Returns true if address fields are  changed, false otherwise
    * @param address 
    * @param oldAddress
    * @return Boolean - True if address changed, false otherwise 
    **/
    private static Boolean isAddressChanged(Address__c address, Address__c oldAddress) {
        return (address.Address__City__s!= oldAddress.Address__City__s || address.Address__CountryCode__s != oldAddress.Address__CountryCode__s || 
        address.Address__PostalCode__s != oldAddress.Address__PostalCode__s || address.Address__StateCode__s != oldAddress.Address__StateCode__s);
    }

    /**
    * @description Returns true if address fields are populated
    * @param address 
    * @return Boolean
    **/
    private static Boolean isAddressPopulated(Address__c address) {
        return (address.Address__City__s != null || address.Address__PostalCode__s != null || address.Address__StateCode__s != null || address.Address__CountryCode__s != null);
    }

    /**
    * @description When the Billing Address is updated on an Account by the Integration User, Salesforce should update the existing Default Billing Address. If none exists or if the default billing address is the same as the default shipping address, a new Address record should be created with Default Billing Address = true.
    * @param newAccounts 
    * @param mapOfOldAccounts
    * @return void 
    **/
    public static void handleAccountAddressChange(List<Account> newAccounts, Map<Id, Account> mapOfOldAccounts) {
        
        if(!updatesFromIntegration){
            return;
        }
        
        String bizAppUserName = Label.Biz_App_UserName;

        // Query the User object to get the ID of the 'Biz Apps Integration' user
        List<User> integrationUsersList = [SELECT Id FROM User WHERE Name = :bizAppUserName AND IsActive = true LIMIT 1];

        if (integrationUsersList.isEmpty()) {
            return; // Exit if the user is not active or doesn't exist
        }

        // Query to get both Country and State information from custom metadata
        List<Country_Info__mdt> countryStateList = [
            SELECT Id, DeveloperName, MasterLabel, Language, NamespacePrefix, Label, QualifiedApiName, SystemModstamp,
                Country_Code__c, Country_Label__c, State_Code__c, State_Label__c
            FROM Country_Info__mdt
        ];

        // Maps to store Country and State data
        Map<String, String> countryMap = new Map<String, String>();
        Map<String, String> stateMap = new Map<String, String>();

        // Populating the maps with duplicate checks
        for (Country_Info__mdt record : countryStateList) {
            if (record.Country_Label__c != null && record.Country_Code__c != null) {
                // Check if the country already exists before adding
                if (!countryMap.containsKey(record.Country_Label__c)) {
                    countryMap.put(record.Country_Label__c, record.Country_Code__c);
                }
            }
            if (record.State_Label__c != null && record.State_Code__c != null) {
                // Check if the state already exists before adding
                if (!stateMap.containsKey(record.State_Label__c)) {
                    stateMap.put(record.State_Label__c, record.State_Code__c);
                }
            }
        }

        Id integrationUserId = integrationUsersList[0].Id;
        Map<Id, Account> accountData = new Map<Id, Account>();
        Map<Id, Boolean> accountDataWithBillingChanged = new Map<Id, Boolean>();
        Map<Id, Boolean> accountDataWithShippingChanged = new Map<Id, Boolean>();
        Map<Id, Address__c> addressToBeUpdated = new Map<Id, Address__c>();
        List<Address__c> listOfAddressToBeUpdatedOrInserted = new List<Address__c>();
    
        for (Account acc : newAccounts) {
            if (mapOfOldAccounts == null 
                    || (mapOfOldAccounts != null 
                    && (acc.BillingCity != mapOfOldAccounts.get(acc.Id).BillingCity
                        || acc.BillingCountry != mapOfOldAccounts.get(acc.Id).BillingCountry
                        || acc.BillingState != mapOfOldAccounts.get(acc.Id).BillingState
                        || acc.BillingStreet != mapOfOldAccounts.get(acc.Id).BillingStreet
                        || acc.BillingPostalCode != mapOfOldAccounts.get(acc.Id).BillingPostalCode))
                && UserInfo.getUserId() == integrationUserId) {
                if(!accountData.containsKey(acc.Id)){
                    accountData.put(acc.Id, acc);
                }
                accountDataWithBillingChanged.put(acc.Id, true);
            }
            if (mapOfOldAccounts == null 
                    || (mapOfOldAccounts != null 
                    && (acc.ShippingCity != mapOfOldAccounts.get(acc.Id).ShippingCity
                        || acc.ShippingCountry != mapOfOldAccounts.get(acc.Id).ShippingCountry
                        || acc.ShippingPostalCode != mapOfOldAccounts.get(acc.Id).ShippingPostalCode
                        || acc.ShippingState != mapOfOldAccounts.get(acc.Id).ShippingState
                        || acc.ShippingStreet != mapOfOldAccounts.get(acc.Id).ShippingStreet))
                && UserInfo.getUserId() == integrationUserId) {
                if(!accountData.containsKey(acc.Id)){
                    accountData.put(acc.Id, acc);
                }
                accountDataWithShippingChanged.put(acc.Id, true);
            }
        }

        if(accountData.isEmpty()){
            return;
        }
    
        // Query all related Address__c records for the given account IDs
        List<Address__c> addresses = [
            SELECT Id, Account__c, Address__City__s, Address__PostalCode__s, Address__Street__s,
                   Address__CountryCode__s, Address__StateCode__s, 
                   Default_Billing_Address__c, Default_Shipping_Address__c, Status__c
            FROM Address__c 
            WHERE Status__c != :AddressConstants.VERIFICATION_APPROVED 
            AND Account__c IN :accountData.keySet()
        ];
    
        Map<Id, List<Address__c>> addressMap = new Map<Id, List<Address__c>>();
        Map<Id, Address__c> singleBothDefaultsMap = new Map<Id, Address__c>();
        Map<Id, Address__c> defaultShippingMap = new Map<Id, Address__c>();
        Map<Id, Address__c> defaultBillingMap = new Map<Id, Address__c>();
        if(!addresses.isEmpty()){
            for (Address__c addr : addresses) {
                if(!addressMap.containsKey(addr.Account__c)){
                    addressMap.put(addr.Account__c, new List<Address__c>());
                }
                addressMap.get(addr.Account__c).add(addr);
                if (addr.Default_Billing_Address__c && addr.Default_Shipping_Address__c) {
                    singleBothDefaultsMap.put(addr.Account__c, addr);
                }
                if (addr.Default_Billing_Address__c && !addr.Default_Shipping_Address__c){
                    defaultBillingMap.put(addr.Account__c, addr);
                }
                if (!addr.Default_Billing_Address__c && addr.Default_Shipping_Address__c){
                    defaultShippingMap.put(addr.Account__c, addr);
                }

            }
        }

        for (Account accData : accountData.values()) {

            Boolean isDefaultBillingUpdated = false;
            Boolean isDefaultShippingUpdated = false;

            if(addressMap != null && addressMap.containsKey(accData.Id)){

                for (Address__c addr : addressMap.get(accData.Id)) {

                    if (accountDataWithBillingChanged != null && accountDataWithBillingChanged.containsKey(accData.Id) && accountDataWithBillingChanged.get(accData.Id) && isBillingAddressMatched(accData, addr, stateMap, countryMap)) {
                        if (!addr.Default_Billing_Address__c) {
                            Address__c existingAddr = addr;
                            if(addressToBeUpdated.containsKey(addr.Id)){
                                existingAddr = addressToBeUpdated.put(addr.Id, addr);
                            }
                            existingAddr.Default_Billing_Address__c = true;
                            existingAddr.Status__c = AddressConstants.PENDING_GOVERNANCE;
                            addressToBeUpdated.put(existingAddr.Id, existingAddr);
                        }
                        isDefaultBillingUpdated = true;
                    } 
        
                    if (accountDataWithShippingChanged != null && accountDataWithShippingChanged.containsKey(accData.Id) && accountDataWithShippingChanged.get(accData.Id) && isShippingAddressMatched(accData, addr, stateMap, countryMap)) {
                        if (!addr.Default_Shipping_Address__c) {
                            Address__c existingAddr = addr;
                            if(addressToBeUpdated.containsKey(addr.Id)){
                                existingAddr = addressToBeUpdated.put(addr.Id, addr);
                            }
                            existingAddr.Default_Shipping_Address__c = true;
                            existingAddr.Status__c = AddressConstants.PENDING_GOVERNANCE;
                            addressToBeUpdated.put(existingAddr.Id, existingAddr);
                        }
                        isDefaultShippingUpdated = true;
                    }
                }
            }
            
    
            Boolean isSameAddress = accData.BillingStreet == accData.ShippingStreet &&
                            accData.BillingCity == accData.ShippingCity &&
                            accData.BillingPostalCode == accData.ShippingPostalCode &&
                            accData.ShippingCountry == accData.BillingCountry &&
                            accData.ShippingState == accData.BillingState;

            if (!isDefaultBillingUpdated && !isDefaultShippingUpdated 
                && accountDataWithBillingChanged != null && accountDataWithBillingChanged.containsKey(accData.Id) && accountDataWithBillingChanged.get(accData.Id)
                && accountDataWithShippingChanged != null && accountDataWithShippingChanged.containsKey(accData.Id) && accountDataWithShippingChanged.get(accData.Id)
                && ((singleBothDefaultsMap != null && singleBothDefaultsMap.containsKey(accData.Id)) || isSameAddress)) {

                if(isSameAddress){

                    if(singleBothDefaultsMap != null && singleBothDefaultsMap.containsKey(accData.Id)) {

                        Address__c addr = singleBothDefaultsMap.get(accData.Id);
                        updateAddressFields(addr, accData, countryMap, stateMap, true);
                        listOfAddressToBeUpdatedOrInserted.add(addr);
                        isDefaultBillingUpdated = true;
                        isDefaultShippingUpdated = true;
                    } else {
                        listOfAddressToBeUpdatedOrInserted.addAll(createOrPopulateBillingAndShippingAddress(accData, true, true, countryMap, stateMap));
                        isDefaultBillingUpdated = true;
                        isDefaultShippingUpdated = true;
                    }
                } else {

                    if(singleBothDefaultsMap != null && singleBothDefaultsMap.containsKey(accData.Id)) {
                        Address__c addr = singleBothDefaultsMap.get(accData.Id);
                        updateAddressFields(addr, accData, countryMap, stateMap, true);
                        listOfAddressToBeUpdatedOrInserted.add(addr);
                        addr.Default_Shipping_Address__c = false;
                        listOfAddressToBeUpdatedOrInserted.addAll(createOrPopulateBillingAndShippingAddress(accData, false, true, countryMap, stateMap));
                        isDefaultBillingUpdated = true;
                        isDefaultShippingUpdated = true;
                    }
                }
            } 
            if (!isDefaultBillingUpdated && accountDataWithBillingChanged != null && accountDataWithBillingChanged.containsKey(accData.Id) && accountDataWithBillingChanged.get(accData.Id)) {

                if(defaultBillingMap != null && defaultBillingMap.containsKey(accData.Id)){
                    Address__c addr = defaultBillingMap.get(accData.Id);
                    updateAddressFields(addr, accData, countryMap, stateMap, true);
                    listOfAddressToBeUpdatedOrInserted.add(addr);
                    isDefaultBillingUpdated = true;
                } else {
                    listOfAddressToBeUpdatedOrInserted.addAll(createOrPopulateBillingAndShippingAddress(accData, true, false, countryMap, stateMap));
                }
            } 
            if (!isDefaultShippingUpdated && accountDataWithShippingChanged != null && accountDataWithShippingChanged.containsKey(accData.Id) && accountDataWithShippingChanged.get(accData.Id)) {
                if(defaultShippingMap != null && defaultShippingMap.containsKey(accData.Id)){
                    Address__c addr = defaultShippingMap.get(accData.Id);
                    updateAddressFields(addr, accData, countryMap, stateMap, false);
                    listOfAddressToBeUpdatedOrInserted.add(addr);
                    isDefaultShippingUpdated = true;
                } else{
                    listOfAddressToBeUpdatedOrInserted.addAll(createOrPopulateBillingAndShippingAddress(accData, false, true, countryMap, stateMap));
                }
            }
        }
    
        if (!listOfAddressToBeUpdatedOrInserted.isEmpty()) {
            List<Database.UpsertResult> results = Database.upsert(listOfAddressToBeUpdatedOrInserted, false);
            ResultHandler.logErrors('AddressTriggerHandler handleAccountAddressChange', listOfAddressToBeUpdatedOrInserted, results);
        }
        if (!addressToBeUpdated.values().isEmpty()) {
            List<Database.UpsertResult> updateResults = Database.upsert(addressToBeUpdated.values(), false);
            ResultHandler.logErrors('AddressTriggerHandler handleAccountAddressChange Update Case', addressToBeUpdated.values(), updateResults);
        }
    }
    
    /**
     * @description This method checks if the Billing Address of an Account matches the provided Address record. 
     * It compares the street, city, and postal code fields to determine a match.
     * @param acc The Account record containing the Billing Address details.
     * @param addr The Address__c record to compare against the Account's Billing Address.
     * @return Boolean Returns true if the Billing Address fields (street, city, postal code) match; otherwise, returns false.
     **/
    private static Boolean isBillingAddressMatched(Account acc, Address__c addr, Map<String, String> stateMap, Map<String, String> countryMap) {
        
        return acc.BillingStreet == addr.Address__Street__s
            && acc.BillingCity == addr.Address__City__s
            && acc.BillingPostalCode == addr.Address__PostalCode__s 
            && addr.Address__CountryCode__s == ((countryMap != null && countryMap.containsKey(acc.BillingCountry)) ? countryMap.get(acc.BillingCountry) : (acc.BillingCountry != null ? acc.BillingCountry : ''))
            && addr.Address__StateCode__s == ((acc.BillingCountry == AddressConstants.UNITES_STATES && stateMap!= null && stateMap.containsKey(acc.BillingState)) ? stateMap.get(acc.BillingState) : (acc.BillingState != null ? acc.BillingState : ''));
    }
    
    /**
     * @description This method checks if the Shipping Address of an Account matches the provided Address record. 
     * It compares the street, city, and postal code fields to determine a match.
     * @param acc The Account record containing the Shipping Address details.
     * @param addr The Address__c record to compare against the Account's Shipping Address.
     * @return Boolean Returns true if the Shipping Address fields (street, city, postal code) match; otherwise, returns false.
     **/
    private static Boolean isShippingAddressMatched(Account acc, Address__c addr, Map<String, String> stateMap, Map<String, String> countryMap) {
        return acc.ShippingStreet == addr.Address__Street__s
            && acc.ShippingCity == addr.Address__City__s
            && acc.ShippingPostalCode == addr.Address__PostalCode__s
            && addr.Address__CountryCode__s == ((countryMap != null && countryMap.containsKey(acc.ShippingCountry)) ? countryMap.get(acc.ShippingCountry) : (acc.ShippingCountry != null ? acc.ShippingCountry : ''))
            && addr.Address__StateCode__s == ((acc.ShippingCountry == AddressConstants.UNITES_STATES && stateMap!= null && stateMap.containsKey(acc.ShippingState)) ? stateMap.get(acc.ShippingState) : (acc.ShippingState != null ? acc.ShippingState : ''));
    }
    
    /**
     * @description This method creates or populates Address__c records for Billing and Shipping addresses based on the provided Account data. 
     * It checks if the Billing and Shipping addresses are the same. If they are, a single Address record with both default billing and shipping flags is created. 
     * Otherwise, separate Address records are created for Billing and/or Shipping addresses based on the addBilling and addShipping flags.
     * @param accData The Account record containing Billing and Shipping address details.
     * @param addBilling Boolean flag to determine if a Billing Address should be created.
     * @param addShipping Boolean flag to determine if a Shipping Address should be created.
     * @return List<Address__c> Returns a list of Address__c records created based on the provided conditions.
     **/
    private static List<Address__c> createOrPopulateBillingAndShippingAddress(Account accData, Boolean addBilling, Boolean addShipping, Map<String, String> countryMap, Map<String, String> stateMap) {

        List<Address__c> addressList = new List<Address__c>();
    
        if (addBilling && addShipping) {
            addressList.add(new Address__c(
                Account__c = accData.Id,
                Address__Street__s = accData.BillingStreet,
                Address__City__s = accData.BillingCity,
                Address__PostalCode__s = accData.BillingPostalCode,
                Address__CountryCode__s = (countryMap != null && countryMap.containsKey(accData.BillingCountry)) ? countryMap.get(accData.BillingCountry) : null,
                Address__StateCode__s = (accData.BillingCountry == AddressConstants.UNITES_STATES && stateMap!= null && stateMap.containsKey(accData.BillingState)) ? stateMap.get(accData.BillingState) : null,
                Default_Billing_Address__c = true,
                Default_Shipping_Address__c = true,
                Status__c = AddressConstants.PENDING_GOVERNANCE
            ));
        } else {
            if (addBilling) {
                addressList.add(new Address__c(
                    Account__c = accData.Id,
                    Address__Street__s = accData.BillingStreet,
                    Address__City__s = accData.BillingCity,
                    Address__PostalCode__s = accData.BillingPostalCode,
                    Address__CountryCode__s = (countryMap != null && countryMap.containsKey(accData.BillingCountry)) ? countryMap.get(accData.BillingCountry) : null,
                    Address__StateCode__s = (accData.BillingCountry == AddressConstants.UNITES_STATES && stateMap!= null && stateMap.containsKey(accData.BillingState)) ? stateMap.get(accData.BillingState) : null,
                    Default_Billing_Address__c = true,
                    Status__c = AddressConstants.PENDING_GOVERNANCE
                ));
            }
            if (addShipping) {
                addressList.add(new Address__c(
                    Account__c = accData.Id,
                    Address__Street__s = accData.ShippingStreet,
                    Address__City__s = accData.ShippingCity,
                    Address__PostalCode__s = accData.ShippingPostalCode,
                    Address__CountryCode__s = (countryMap != null && countryMap.containsKey(accData.ShippingCountry)) ? countryMap.get(accData.ShippingCountry) : null,
                    Address__StateCode__s = (accData.ShippingCountry == AddressConstants.UNITES_STATES && stateMap!= null && stateMap.containsKey(accData.ShippingState)) ? stateMap.get(accData.ShippingState) : null,
                    Default_Shipping_Address__c = true,
                    Status__c = AddressConstants.PENDING_GOVERNANCE
                ));
            }
        }
        return addressList;
    }    

    /**
     * @description Updates the address fields with values from the account
     * @param addr The address record to update
     * @param acc The account containing the new values
     * @param countryMap Map of country labels to codes
     * @param stateMap Map of state labels to codes
     * @param isBilling Whether to use billing or shipping address fields
     */
    private static void updateAddressFields(Address__c addr, Account acc, Map<String, String> countryMap, Map<String, String> stateMap, Boolean isBilling) {
        if (isBilling) {
            addr.Address__Street__s = acc.BillingStreet;
            addr.Address__City__s = acc.BillingCity;
            addr.Address__PostalCode__s = acc.BillingPostalCode;
            addr.Address__CountryCode__s = (countryMap != null && countryMap.containsKey(acc.BillingCountry)) ? countryMap.get(acc.BillingCountry) : null;
            addr.Address__StateCode__s = (acc.BillingCountry == AddressConstants.UNITES_STATES && stateMap != null && stateMap.containsKey(acc.BillingState)) ? stateMap.get(acc.BillingState) : null;
        } else {
            addr.Address__Street__s = acc.ShippingStreet;
            addr.Address__City__s = acc.ShippingCity;
            addr.Address__PostalCode__s = acc.ShippingPostalCode;
            addr.Address__CountryCode__s = (countryMap != null && countryMap.containsKey(acc.ShippingCountry)) ? countryMap.get(acc.ShippingCountry) : null;
            addr.Address__StateCode__s = (acc.ShippingCountry == AddressConstants.UNITES_STATES && stateMap != null && stateMap.containsKey(acc.ShippingState)) ? stateMap.get(acc.ShippingState) : null;
        }
        addr.Status__c = AddressConstants.PENDING_GOVERNANCE;
    }
}