global class ContractsRenewalMigrationBatch implements Database.Batchable<sObject>{
    List<string> lstOfContractAssignment;
    global ContractsRenewalMigrationBatch() {}

    global ContractsRenewalMigrationBatch(List<string> lstOfContractNumbers){
        lstOfContractAssignment = lstOfContractNumbers ;
    }

    global Database.QueryLocator start(Database.BatchableContext bc){
        string endCondition;
        if (lstOfContractAssignment != null && !lstOfContractAssignment.isempty()) {
            for (string endDigit : lstOfContractAssignment) {
                endCondition = endCondition != null? (endCondition +  ' OR ContractNumber like \'%' + endDigit + '\'') :' ContractNumber like \'%' + endDigit + '\'';
            }
        } 
        String query = 'SELECT Id,Processing_Status__c,SBQQ__RenewalForecast__c,Enddate,SBQQ__RenewalQuoted__c FROM Contract WHERE Migration_Status__c = \'Renewal Ready\'';
        query = endCondition != null? query + ' AND (' + endCondition + ')' : query;
        system.debug('Start Query' +query);   
        return Database.getQueryLocator(query);        
    }
    
    global void execute(Database.BatchableContext bc, List<Contract> lstOfContracts){
        List<Contract> lstOfUpdatedContracts = new List<Contract>();
        List<OP4I_Entitlement_Renewal_View__c> lstOfEntitlementRecords = new List<OP4I_Entitlement_Renewal_View__c>();
        Map<String,OP4I_Entitlement_Renewal_View__c> mapOfOsaToEntitlementRecords = new Map<String,OP4I_Entitlement_Renewal_View__c>(); 
        List<OP4I_Entitlement_Renewal_View__c> lstOfEntitlementRecordsUpd = new List<OP4I_Entitlement_Renewal_View__c>();
        set<string> setOfContractIds = new set<string>();
        Map<String,Decimal> mapOfOsaToRenewalUplift = new Map<String,Decimal>();
        if(!lstOfContracts.IsEmpty())
        {
            lstOfEntitlementRecords = [Select Id,Error_Log__c,OSA__c,OSA__r.Processing_Status__c,Product_Id__c,Product_Instance__c,
                                       Quantity__c,Renewal_Deal_Id__c,Renewal_DLIP_Id__c,Renewal_Opportunity__c,Renewal_Uplift__c
                                       FROM OP4I_Entitlement_Renewal_View__c 
                                       WHERE OSA__c IN: lstOfContracts];
                                       
            if(!lstOfEntitlementRecords.IsEmpty()){ 
              for(OP4I_Entitlement_Renewal_View__c entitlemnt : lstOfEntitlementRecords)
              {
                mapOfOsaToEntitlementRecords.put(entitlemnt.OSA__c,entitlemnt);
                mapOfOsaToRenewalUplift.put(entitlemnt.OSA__c,entitlemnt.Renewal_Uplift__c);            
              }
            }
            
            if(!lstOfContracts.IsEmpty() && lstOfContracts.size() > 0){
              for(Contract contrObj : lstOfContracts){
                if(mapOfOsaToRenewalUplift.get(contrObj.id) != null){             
                contrObj.SBQQ__RenewalUpliftRate__c = mapOfOsaToRenewalUplift.get(contrObj.id); 
                }               
                contrObj.SBQQ__RenewalForecast__c = true;
                if(system.today().daysBetween(contrObj.Enddate) < 90){
                contrObj.SBQQ__RenewalQuoted__c = true;                         
                }
                lstOfUpdatedContracts.add(contrObj);
              }                             
            }
            
            if(lstOfUpdatedContracts.size() > 0){
            updateContract(lstOfUpdatedContracts,mapOfOsaToEntitlementRecords);
            }                      
        }   
    }
    
    global void finish(Database.BatchableContext bc){
        
    }
    global static void updateContract(List<Contract> lstOfUpdatedContracts,Map<String,OP4I_Entitlement_Renewal_View__c> mapOfOsaToEntitlementRecords){
        Database.SaveResult[] updateContractResult = Database.update(lstOfUpdatedContracts, false); 
        map<string,string> resultMap = HandleCustomException.logMigrationDatabaseError(
            updateContractResult,
            mapOfOsaToEntitlementRecords,
            'Id',
            lstOfUpdatedContracts
        );   
        string keyFields = 'OSA__c';
        for(OP4I_Entitlement_Renewal_View__c entitlement : mapOfOsaToEntitlementRecords.values()) {          
            string key = HandleCustomException.getKey(keyFields, entitlement);
            if (resultMap.containsKey(key)) {
                entitlement.Error_Log__c = resultMap.get(key);
                entitlement.OSA__r.Processing_Status__c = 'Contract Updation Failed';
            }
        }
        
        Database.SaveResult[] entitlementLst = Database.update(mapOfOsaToEntitlementRecords.values(), false);
        HandleCustomException.logDatabaseErrorsForEntitlements(entitlementLst,mapOfOsaToEntitlementRecords);  
    }
}