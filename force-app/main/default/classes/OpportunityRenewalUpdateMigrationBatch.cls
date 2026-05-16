global class OpportunityRenewalUpdateMigrationBatch implements Database.Batchable<sObject>{
    List<string> lstOfContractAssignment;
    global OpportunityRenewalUpdateMigrationBatch() {}

    global OpportunityRenewalUpdateMigrationBatch(List<string> lstOfContractNumbers){
        lstOfContractAssignment = lstOfContractNumbers ;
    }

    global Database.QueryLocator start(Database.BatchableContext bc){
        string endCondition;
        if (lstOfContractAssignment != null && !lstOfContractAssignment.isempty()) {
            for (string endDigit : lstOfContractAssignment) {
                endCondition = endCondition != null? (endCondition +  ' OR ContractNumber like \'%' + endDigit + '\'') :' ContractNumber like \'%' + endDigit + '\'';
            }
        } 
        String query = 'SELECT Id,Processing_Status__c,Migration_Status__c FROM Contract WHERE  Migration_Status__c = \'Renewal Ready\'';
        query = endCondition != null? query + ' AND (' + endCondition + ')' : query;
        system.debug('Start Query' +query);   
        return Database.getQueryLocator(query);        
    }
    
    global void execute(Database.BatchableContext bc, List<Contract> lstOfContracts){
        List<OpportunityLineItem> lstOfOppLineItemsToUpdate = new List<OpportunityLineItem>();
        List<Opportunity> lstOfOpportunityToUpdate = new List<Opportunity>();
        List<OP4I_Entitlement_Renewal_View__c> lstOfEntitlementRecords = new List<OP4I_Entitlement_Renewal_View__c>();
        Map<String,OP4I_Entitlement_Renewal_View__c> mapOfOsaToEntitlementRecords = new Map<String,OP4I_Entitlement_Renewal_View__c>(); 
        Map<String,String> mapOfOsaToRenewalDealId = new Map<String,String>();
        if(!lstOfContracts.IsEmpty())
        {
            lstOfEntitlementRecords = [Select Id,Error_Log__c,OSA__c,OSA__r.Processing_Status__c,Product_Id__c,Product_Instance__c,
                                       Quantity__c,Renewal_Deal_Id__c,Renewal_DLIP_Id__c,Renewal_Opportunity__c
                                       FROM OP4I_Entitlement_Renewal_View__c 
                                       WHERE OSA__c IN: lstOfContracts];
                                       
            if(!lstOfEntitlementRecords.IsEmpty()){ 
              for(OP4I_Entitlement_Renewal_View__c entitlemnt : lstOfEntitlementRecords)
              {
                mapOfOsaToEntitlementRecords.put(entitlemnt.OSA__c,entitlemnt); 
                mapOfOsaToRenewalDealId.put(entitlemnt.OSA__c,entitlemnt.Renewal_Deal_Id__c);               
              }
            }
            
            List<Opportunity> lstOfOpportunity = [Select Id,OP4I_Deal_Id__c,SBQQ__RenewedContract__c,(Select Id,Skip_OP4I_Sync__c FROM OpportunityLineItems) FROM Opportunity WHERE SBQQ__RenewedContract__c IN: lstOfContracts];
            if(!lstOfOpportunity.IsEmpty() && lstOfOpportunity.size() > 0){
              for(Opportunity oppObj : lstOfOpportunity){
                if(mapOfOsaToRenewalDealId.keyset().contains(oppObj.SBQQ__RenewedContract__c)){ 
                oppObj.OP4I_Deal_Id__c =  mapOfOsaToRenewalDealId.get(oppObj.SBQQ__RenewedContract__c);
                lstOfOpportunityToUpdate.add(oppObj);
                }
                
                List<OpportunityLineItem> lstOfOppLineItems = oppObj.OpportunityLineItems;
                if(!lstOfOppLineItems.IsEmpty() && lstOfOppLineItems.size() > 0){
                  for(OpportunityLineItem oli : lstOfOppLineItems){
                    system.debug('@@in S Loop');
                    oli.Skip_OP4I_Sync__c = true;
                    lstOfOppLineItemsToUpdate.add(oli);
                  }                                   
                }                   
              }
            }
         
            if(lstOfOppLineItemsToUpdate.size() > 0){
            Database.SaveResult[] updateOliResult = Database.update(lstOfOppLineItemsToUpdate, false); 
            HandleCustomException.logDatabaseErrorsForEntitlements(updateOliResult,mapOfOsaToEntitlementRecords);
            } 

            if(lstOfOpportunityToUpdate.size() > 0){
            Database.SaveResult[] updateOpportunityResult = Database.update(lstOfOpportunityToUpdate, false); 
            HandleCustomException.logDatabaseErrorsForEntitlements(updateOpportunityResult,mapOfOsaToEntitlementRecords);  
            }           
        }   
    }
    
    global void finish(Database.BatchableContext bc){
        
    }
}