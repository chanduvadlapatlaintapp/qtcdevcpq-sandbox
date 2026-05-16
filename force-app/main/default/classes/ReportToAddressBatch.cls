public class ReportToAddressBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        String query = '';
            query = '' 
              + ' SELECT Id'
                + '      , Name'
                + '      , BillingAddress, BillingStreet'
                + '      , BillingCity, BillingState'
                + '      , BillingPostalCode, BillingCountry'
                + '      , ShippingAddress, ShippingStreet '
                + '      , ShippingCity, ShippingState'
                + '      , ShippingPostalCode, ShippingCountry'
                + '   FROM Account WHERE Type = \'Client\'';
                
            return Database.getQueryLocator(query);
        }
    
    public void execute(Database.BatchableContext bc, List<Account> lstOfAccounts){
        Map<String,Address__c> accountToAddressMap = new Map<String,Address__c>();

        //fetch country mapping data
        Map<string,string> countryCodeMap = new Map<string,string>();
        Map<string,string> stateCountryWiseCodeMap = new Map<string,string>();
        Map<string,string> stateCodeMap = new Map<string,string>();
        set<string> countryCodes = new set<string>();
        set<string> stateCodes = new set<string>();
        for (Country_Info__mdt countryInfo : [
            SELECT Id 
                 , Country_Code__c
                 , Country_Label__c
                 , State_Code__c
                 , State_Label__c
              FROM Country_Info__mdt
        ]) {
            countryCodes.add(countryInfo.Country_Code__c);
            stateCodes.add(countryInfo.State_Code__c);
            countryCodeMap.put(getValue(countryInfo.Country_Label__c).toLowerCase(),countryInfo.Country_Code__c);
            stateCountryWiseCodeMap.put(getValue(countryInfo.Country_Code__c).toLowerCase() + '-' +getValue(countryInfo.State_Label__c).toLowerCase(),countryInfo.State_Code__c);
        }
        
        List<Address__c> addressUpsertList = new list<Address__c>();
        for(Address__c addressRecord : [
            SELECT Id
                 , Account__c
                 , Address__City__s
                 , Type__c 
                 , Address__CountryCode__s
                 , Address__Street__s
                 , Address__StateCode__s
                 , Address__PostalCode__s 
                 , Is_State_Code_blank__c   
                 , Is_Country_Code_blank__c 
                 , Default_Billing_Address__c
                 , Default_Shipping_Address__c
                 , Status__c                 
              FROM Address__c 
              WHERE Account__c IN: lstOfAccounts
        ]){
            string addressLine = getValue(addressRecord.Address__Street__s) + getValue(addressRecord.Address__City__s)
                + getValue(addressRecord.Address__StateCode__s) + getValue(addressRecord.Address__CountryCode__s) +getValue(addressRecord.Address__PostalCode__s);
            
            accountToAddressMap.put(addressRecord.Account__c + '-' + addressLine, addressRecord);
        }
        
        for (Account account : lstOfAccounts) {
            string billingCountryCode =  countryCodes.contains(account.BillingCountry)? account.BillingCountry : getValue(getCountryCode(countryCodeMap,account.BillingCountry));
            string billingStateCode = stateCodes.contains(account.BillingState)? account.BillingState : getValue(getStateCode(stateCountryWiseCodeMap,billingCountryCode,account.BillingState));
            string shippingCountryCode = countryCodes.contains(account.ShippingCountry)? account.ShippingCountry : getValue(getCountryCode(countryCodeMap,account.ShippingCountry));
            string shippingStateCode = stateCodes.contains(account.ShippingState)? account.ShippingState : getValue(getStateCode(stateCountryWiseCodeMap,shippingCountryCode,account.ShippingState));
            string billingAddress = getValue(account.BillingStreet) + getValue(account.BillingCity)
                + billingStateCode + billingCountryCode +getValue(account.BillingPostalCode);
            string shippingAddress = getValue(account.ShippingStreet) + getValue(account.ShippingCity)
                + shippingStateCode + shippingCountryCode +getValue(account.ShippingPostalCode);
            boolean sameAddress = string.isNotBlank(billingAddress) && billingAddress == shippingAddress? true :false;
            
            system.debug('@@statecode' +billingStateCode);
            system.debug('@@countrycode' +billingCountryCode);
            //check if same and already present?
            if (sameAddress == true && accountToAddressMap.containsKey(account.Id + '-' +billingAddress)) {
                Address__c existingAddress = accountToAddressMap.get(account.Id + '-' +billingAddress);
                if (!'Both'.equalsIgnoreCase(existingAddress.Type__c) ) {
                    existingAddress.Type__c = 'Both';
                    existingAddress.Name = existingAddress.Address__City__s + '-' + existingAddress.Address__StateCode__s + '-' + existingAddress.Address__PostalCode__s;
                    if(existingAddress.Is_State_Code_blank__c != true && existingAddress.Is_Country_Code_blank__c != true){
                    existingAddress.Default_Billing_Address__c = true;
                    existingAddress.Default_Shipping_Address__c = true;
                    existingAddress.Status__c = 'Verification Approved';
                    }
                    addressUpsertList.add(existingAddress);
                    System.debug('addressUpsertList--133--->'+addressUpsertList);
                }
            } else {
                if (sameAddress == true) {
                    Address__c address = getBillingAddress(account,'Both',billingStateCode,billingCountryCode);
                    addressUpsertList.add(address);
                    accountToAddressMap.put(account.Id + '-' + billingAddress,address);
                } else {
                  //check if billing address present and it also present in existing address?
                  if (string.isNotBlank(billingAddress) && accountToAddressMap.containsKey(account.Id + '-' +billingAddress)) {
                        //update type if it is not both or billing
                        Address__c existingAddress = accountToAddressMap.get(account.Id + '-' +billingAddress);
                        existingAddress.Name = existingAddress.Address__City__s + '-' + existingAddress.Address__StateCode__s + '-' + existingAddress.Address__PostalCode__s;
                        if ( string.isNotBlank(existingAddress.Type__c) 
                            && !'Both'.equalsIgnoreCase(existingAddress.Type__c)
                            && !'Billing'.equalsIgnoreCase(existingAddress.Type__c)){
                            existingAddress.Type__c = 'Both';
                            if(existingAddress.Is_State_Code_blank__c != true && existingAddress.Is_Country_Code_blank__c != true){
                            existingAddress.Status__c = 'Verification Approved';
                            existingAddress.Default_Billing_Address__c = true;
                            existingAddress.Default_Shipping_Address__c = true;
                            }
                            addressUpsertList.add(existingAddress);
                            System.debug('addressUpsertList--159--->'+addressUpsertList);
                        }
                    } else {
                        //not found so create one
                        Address__c address = getBillingAddress(account,'Billing',billingStateCode,billingCountryCode);
                        addressUpsertList.add(address);
                        accountToAddressMap.put(account.Id + '-' + billingAddress,address);
                        System.debug('addressUpsertList--171--->'+addressUpsertList);
                    }
                    //check if shipping address present and it also present in existing address?
                  if (string.isNotBlank(shippingAddress) && accountToAddressMap.containsKey(account.Id + '-' +shippingAddress)) {
                        //update type if it is not both or billing
                        Address__c existingAddress = accountToAddressMap.get(account.Id + '-' +shippingAddress);
                        existingAddress.Name = existingAddress.Address__City__s + '-' + existingAddress.Address__StateCode__s + '-' + existingAddress.Address__PostalCode__s;
                        if ( string.isNotBlank(existingAddress.Type__c) 
                            && !'Both'.equalsIgnoreCase(existingAddress.Type__c)
                            && !'Shipping'.equalsIgnoreCase(existingAddress.Type__c) 
                        ) {
                            existingAddress.Type__c = 'Both';
                            if(existingAddress.Is_State_Code_blank__c != true && existingAddress.Is_Country_Code_blank__c != true){
                            existingAddress.Status__c = 'Verification Approved';
                            existingAddress.Default_Billing_Address__c = true;
                            existingAddress.Default_Shipping_Address__c = true;
                            }
                            addressUpsertList.add(existingAddress);
                        }
                    } else {
                        //not found so create one
                        Address__c address = getShippingAddress(account,shippingStateCode,shippingCountryCode);
                        addressUpsertList.add(address);
                        accountToAddressMap.put(account.Id + '-' + shippingAddress,address);
                        System.debug('addressUpsertList--in shipping loop--->'+addressUpsertList);
                    }
                }
            }
        }
        
        System.debug('addressUpsertList--'+addressUpsertList);      
        if (!addressUpsertList.isEmpty() && addressUpsertList.size() > 0) {
            try{
              Database.upsert(addressUpsertList,false);
            }
            catch(Exception ex){
             system.debug('@@snehal exception' +ex);    
                
            }
        }
    }

    public Address__c getBillingAddress(Account account,string addressType,string stateCode, string countryCode) {
        Address__c address = new Address__c();
        address.Address__Street__s = account.BillingStreet;
        address.Address__City__s = account.BillingCity;
        if((string.isblank(stateCode) || stateCode == null || stateCode == '')
            && (string.isNotBlank(account.BillingState) || account.BillingState != null)){
        address.Is_State_Code_blank__c = true;
        }
        address.Address__StateCode__s = stateCode;  
        
        if(string.isblank(countryCode) || countryCode == null || countryCode == ''){
        address.Is_Country_Code_blank__c = true;
        }
        address.Address__CountryCode__s = countryCode;  
        address.Address__PostalCode__s = account.BillingPostalCode;     
        address.Type__c = addressType;
        
        if(address.Is_State_Code_blank__c != true && address.Is_Country_Code_blank__c != true){
          address.Status__c = 'Verification Approved';
          if(address.Type__c == 'Billing'){
          address.Default_Billing_Address__c = true;
          }
          else if(address.Type__c == 'Both'){
          address.Default_Billing_Address__c = true;
          address.Default_Shipping_Address__c = true;         
          }
        }
        address.Name = address.Address__City__s + '-' + address.Address__StateCode__s + '-' + address.Address__PostalCode__s;
        address.Account__c = account.Id;
        return address;
    }

    public Address__c getShippingAddress(Account account,string stateCode, string countryCode) {
        Address__c address = new Address__c();
        address.Address__Street__s = account.ShippingStreet;
        address.Address__City__s = account.ShippingCity;
        if((string.isblank(stateCode) || stateCode == null ||  stateCode == '')
           && (string.isNotBlank(account.ShippingState) || account.ShippingState != null)){
        address.Is_State_Code_blank__c = true;
        }
        address.Address__StateCode__s = stateCode;  
        
        if(string.isblank(countryCode) || countryCode == null || countryCode == ''){
        address.Is_Country_Code_blank__c = true;
        }
        address.Address__CountryCode__s = countryCode;  

        address.Address__PostalCode__s = account.ShippingPostalCode;
        address.Type__c = 'Shipping';
        
        if(address.Is_State_Code_blank__c != true && address.Is_Country_Code_blank__c != true){
        address.Status__c = 'Verification Approved';
        if(address.Type__c == 'Shipping'){
        address.Default_Shipping_Address__c = true;
        }
        }
        address.Account__c = account.Id;
        address.Name = address.Address__City__s + '-' + address.Address__StateCode__s + '-' + address.Address__PostalCode__s;
        return address;
    }

    public string getCountryCode(Map<string,string> countryCodeMap,String country) {
        country = string.isNotBlank(country)? country.toLowerCase() : country;
        return string.isNotBlank(country) && countryCodeMap.containsKey(country)? countryCodeMap.get(country) : null;
    }

    public string getStateCode(Map<string,string> stateCountryWiseCodeMap,String country,String state) {
        country = string.isNotBlank(country)? country.toLowerCase() : country;
        state = string.isNotBlank(state)? state.toLowerCase() : state;
        string key = getValue(country) + '-' + getValue(state);
        return stateCountryWiseCodeMap.containsKey(key)? stateCountryWiseCodeMap.get(key) : null;
    }
    
    public string getValue(string data){
        return data != null? data : '';
    }
    
    public void finish(Database.BatchableContext bc){
    }
}