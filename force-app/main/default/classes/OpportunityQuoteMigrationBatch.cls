//Batch Opportunity creation for Migration Data
global class OpportunityQuoteMigrationBatch implements Database.Batchable<sObject> {
    List<string> lstOfContractAssignment;
    global OpportunityQuoteMigrationBatch(List<string> lstOfContractNumbers){
      lstOfContractAssignment = lstOfContractNumbers ;
    }
    global OpportunityQuoteMigrationBatch() {}

    global Database.QueryLocator start(Database.BatchableContext bc){
        string endCondition;
        if (lstOfContractAssignment != null && !lstOfContractAssignment.isempty()) {
            for (string endDigit : lstOfContractAssignment) {
                endCondition = endCondition != null? (endCondition +  ' OR ContractNumber like \'%' + endDigit + '\'') :' ContractNumber like \'%' + endDigit + '\'';
            }
        } 
        String query = 'SELECT Id,Migration_Status__c,ContractNumber '
                     + 'FROM Contract WHERE Migration_Status__c = \'Ready\'';            
        query = endCondition != null? query + ' AND (' + endCondition + ')' : query;
        system.debug('Start Query' +query);     
        return Database.getQueryLocator(query);        
    }
    
    global void execute(Database.BatchableContext bc, List<Contract> lstOfContracts){
        List<OP4I_Entitlement_View__c> lstOfEntitlementToProcessOpportunity = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementToProcessQuote = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementsExistingOpp = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementsExistingQuote = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementRecords = new List<OP4I_Entitlement_View__c>();
        List<Contract> lstOfContractsToUpdate = new List<Contract>();
        set<id> setOfContractIds = new set<id>();
        Map<String,Opportunity> mapOfContractToOpportunity = new Map<String,Opportunity>();
        Map<String,SBQQ__Quote__c> mapOfContractToQuote = new Map<String,SBQQ__Quote__c>();
        Map<String,Opportunity> mapOfContractToOpportunityCreate = new Map<String,Opportunity>();
        Map<String,SBQQ__Quote__c> mapOfContractToQuoteCreate = new Map<String,SBQQ__Quote__c>();
        if(!lstOfContracts.IsEmpty())
        {
            
          system.debug('listOfOCntracts' +lstOfContracts[0].ContractNumber);    
          lstOfEntitlementRecords = [SELECT Id,DLIP_Id__c,Account__c,CurrencyIsoCode,Associated_OSA__c,Account__r.Name,Associated_OSA__r.ContractNumber,Opportunity__c,Renewal_Payment_Terms__c,
                                    Processing_Status__c,Start_Date__c,Deal_Type__c,Total_Contract_Months__c,First_Segment_Months__c,Billing_Frequency__c,Renewal_Billing_Frequency__c,
                                    Payment_Terms__c,Associated_OSA__r.Migration_Status__c,Associated_OSA__r.Processing_Status__c,End_Date__c,Sales_Segment__c,Line_of_Business__c
                                    FROM OP4I_Entitlement_View__c WHERE Associated_OSA__c IN: lstOfContracts ORDER BY Start_Date__c ASC NULLS LAST];  
            if(!lstOfEntitlementRecords.IsEmpty()){                                 
              for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords)
              {
                setOfContractIds.add(entitlement.Associated_OSA__c); 
                entitlement.Migration_Status__c = 'In Processing'; 
                entitlement.Associated_OSA__r.Migration_Status__c = 'In Processing';
                entitlement.Error_Log__c = '';
                if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r))
                {
                  lstOfContractsToUpdate.add(entitlement.Associated_OSA__r); 
                }             
              }
              update lstOfEntitlementRecords;
              update lstOfContractsToUpdate;
            } 
            
            List<Opportunity> existingOpp = [Select Id,Migration_Contract__c FROM Opportunity WHERE Migration_Contract__c IN: setOfContractIds];
            if(!existingOpp.IsEmpty())
            {
            for(Opportunity oppObj : existingOpp)
            {
            mapOfContractToOpportunity.put(oppObj.Migration_Contract__c , oppObj);
            }
            }
            
            for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords)
            {             
            if(mapOfContractToOpportunity.containskey(entitlement.Associated_OSA__c))
            {
            entitlement.Opportunity__c = mapOfContractToOpportunity.get(entitlement.Associated_OSA__c).id;
            entitlement.Processing_Status__c = 'Opportunity Created';
            entitlement.Associated_OSA__r.Processing_Status__c = 'Opportunity Created';
            lstOfEntitlementsExistingOpp.add(entitlement);
            if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r))
            {
              lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
            }
            }
            else
            {
                if(!mapOfContractToOpportunityCreate.containskey(entitlement.Associated_OSA__c))
                { 
                Opportunity migrateOpportunity = createOpportunity(entitlement);
                mapOfContractToOpportunityCreate.put(entitlement.Associated_OSA__c,migrateOpportunity);
                }   
                lstOfEntitlementToProcessOpportunity.add(entitlement);               
            }           
            }
            
            if(!lstOfEntitlementsExistingOpp.IsEmpty())
            {
              update lstOfEntitlementsExistingOpp;
            }
            
            if(!lstOfContractsToUpdate.IsEmpty())
            {
              update lstOfContractsToUpdate;    
            }
                
            if(!mapOfContractToOpportunityCreate.IsEmpty())
            {                    
            updateOpportunityAndEntitlement(mapOfContractToOpportunityCreate,lstOfEntitlementToProcessOpportunity);
            }
                    
            List<SBQQ__Quote__c> existingQuote = [Select Id,Migration_Contract__c FROM SBQQ__Quote__c WHERE Migration_Contract__c IN: setOfContractIds];
            if(!existingQuote.IsEmpty())
            {
            for(SBQQ__Quote__c quoteObj : existingQuote)
            {
            mapOfContractToQuote.put(quoteObj.Migration_Contract__c , quoteObj);
            }
            }
            
            for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords)
            {             
            if(mapOfContractToQuote.containskey(entitlement.Associated_OSA__c))
            {
                entitlement.Quote__c = mapOfContractToQuote.get(entitlement.Associated_OSA__c).id;
                entitlement.Processing_Status__c = 'Quote Created';
                entitlement.Associated_OSA__r.Processing_Status__c = 'Quote Created';
                lstOfEntitlementsExistingQuote.add(entitlement);
                if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r))
                {
                  lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                }
            }
            else
            {
            if(!mapOfContractToQuoteCreate.containskey(entitlement.Associated_OSA__c))
            { 
            SBQQ__Quote__c migrateQuote = createQuote(entitlement , entitlement.Opportunity__c);
            mapOfContractToQuoteCreate.put(entitlement.Associated_OSA__c,migrateQuote);
            } 
            lstOfEntitlementToProcessQuote.add(entitlement);             
            }            
            }
            
            if(!lstOfEntitlementsExistingQuote.IsEmpty())
            {
            update lstOfEntitlementsExistingQuote;
            }
            
            if(!lstOfContractsToUpdate.IsEmpty())
            {
              update lstOfContractsToUpdate;    
            }
                
            if(!mapOfContractToQuoteCreate.IsEmpty())
            {                    
            updateQuoteAndEntitlement(mapOfContractToQuoteCreate,lstOfEntitlementToProcessQuote);
            }
        }         
    }
    
    global void finish(Database.BatchableContext bc){
       
    }
       
    global static opportunity createOpportunity(OP4I_Entitlement_View__c entitlement)
    {
        Opportunity oppMigration = new Opportunity();
        String oppName = entitlement.Account__r.Name + '' + '|' + '' + entitlement.Associated_OSA__r.ContractNumber + '' + '|' + '' + 'Migration Opportunity';        
        String opportunityName = OppName.length()>80 ? OppName.substring(0,80) : OppName;
        oppMigration.Name = opportunityName;    
        oppMigration.AccountId = entitlement.Account__c;
        oppMigration.CloseDate = system.today();
        oppMigration.StageName = 'Closed - Migration';
        oppMigration.RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                                .get('Migration_Opportunity').getRecordTypeId();
        oppMigration.Migration_Contract__c = entitlement.Associated_OSA__c;
        oppMigration.CurrencyIsoCode = entitlement.CurrencyIsoCode;
        return oppMigration;    
    }  

   global static SBQQ__Quote__c createQuote(OP4I_Entitlement_View__c entitlement , Id oppMigrationId)
   {
        SBQQ__Quote__c quoteMigration = new SBQQ__Quote__c();
        quoteMigration.SBQQ__Account__c = entitlement.Account__c;
        quoteMigration.SBQQ__StartDate__c = entitlement.Start_Date__c;
        quoteMigration.SBQQ__Opportunity2__c = oppMigrationId;
        quoteMigration.SBQQ__Type__c = 'Migration Quote';
        quoteMigration.CurrencyIsoCode = entitlement.CurrencyIsoCode;
        quoteMigration.OP4I_Sales_Segment__c = entitlement.Sales_Segment__c;
        quoteMigration.Line_of_Business__c = entitlement.Line_of_Business__c;
        quoteMigration.SBQQ__FirstSegmentTermEndDate__c = entitlement.End_Date__c;
        if(entitlement.Deal_Type__c == 'Renewal')
        {
            quoteMigration.SBQQ__BillingFrequency__c = entitlement.Renewal_Billing_Frequency__c;    
            quoteMigration.Software_Payment_Terms__c = entitlement.Renewal_Payment_Terms__c; 
            quoteMigration.SBQQ__PaymentTerms__c = entitlement.Renewal_Payment_Terms__c;            
            quoteMigration.SBQQ__SubscriptionTerm__c = 12;
            quoteMigration.First_Segment_Months__c = 12;
        }
        else
        {
        if(entitlement.Billing_Frequency__c == 'Annually')
        {
        quoteMigration.SBQQ__BillingFrequency__c = 'Annual';
        }
        else
        {
        quoteMigration.SBQQ__BillingFrequency__c =entitlement.Billing_Frequency__c;
        }
        quoteMigration.Software_Payment_Terms__c = entitlement.Payment_Terms__c; 
        quoteMigration.SBQQ__PaymentTerms__c = entitlement.Payment_Terms__c; 
            quoteMigration.SBQQ__SubscriptionTerm__c = entitlement.Total_Contract_Months__c;
            quoteMigration.First_Segment_Months__c = entitlement.First_Segment_Months__c;
        }
        quoteMigration.SBQQ__Primary__c = true;
        quoteMigration.Migration_Contract__c = entitlement.Associated_OSA__c;     
        return quoteMigration;  
    } 


    global static void updateOpportunityAndEntitlement(Map<String,Opportunity> mapOfContractToOpportunityCreate,List<OP4I_Entitlement_View__c> lstOfEntitlementToProcessOpportunity)
    {
        List<Contract> lstOfContractsToUpdate = new List<Contract>();
        List<Opportunity> opportunityList = mapOfContractToOpportunityCreate.values();
        Database.SaveResult[] opportunitySaveResultList = Database.insert(opportunityList,false); 
        map<string,string> resultMap = HandleCustomException.logMigrationDatabaseError(
            opportunitySaveResultList,
            mapOfContractToOpportunityCreate,
            'Migration_Contract__c',
            opportunityList
        );
        
        string keyFields = 'Associated_OSA__c';
        for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementToProcessOpportunity) {             
            if(mapOfContractToOpportunityCreate.containskey(entitlement.Associated_OSA__c)) {
                string key = HandleCustomException.getKey(keyFields, entitlement);
                if (resultMap.containsKey(key)) {
                    entitlement.Processing_Status__c = 'Opportunity Creation Failed';
                    entitlement.Error_Log__c = resultMap.get(key);
                    entitlement.Associated_OSA__r.Processing_Status__c = 'Opportunity Creation Failed';
                } else {
                    entitlement.Opportunity__c = mapOfContractToOpportunityCreate.get(entitlement.Associated_OSA__c).id;
                    entitlement.Processing_Status__c = 'Opportunity Created';
                    entitlement.Associated_OSA__r.Processing_Status__c = 'Opportunity Created';
                }

                if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r)) {
                    lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                }
            }
        }

        Database.SaveResult[] entitlementListOpp = Database.update(lstOfEntitlementToProcessOpportunity, false);
        HandleCustomException.logDatabaseErrors(entitlementListOpp); 
        
        Database.SaveResult[] contrList = Database.update(lstOfContractsToUpdate, false);
        HandleCustomException.logDatabaseErrors(contrList);         
    }   

    global static void updateQuoteAndEntitlement(Map<String,SBQQ__Quote__c> mapOfContractToQuoteCreate,List<OP4I_Entitlement_View__c> lstOfEntitlementToProcessQuote)
    {
        List<Contract> lstOfContractsToUpdate = new List<Contract>();
        List<SBQQ__Quote__c> quoteList = mapOfContractToQuoteCreate.values();
        Database.SaveResult[] quoteSaveResultList = Database.insert(quoteList, false); 
        //HandleCustomException.logDatabaseErrorsForEntitlements(quoteList,mapOfContractToQuoteCreate);
        map<string,string> resultMap = HandleCustomException.logMigrationDatabaseError(
            quoteSaveResultList,
            mapOfContractToQuoteCreate,
            'Migration_Contract__c',
            quoteList
        );
        
        string keyFields = 'Associated_OSA__c';
        for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementToProcessQuote) {             
            if(mapOfContractToQuoteCreate.containskey(entitlement.Associated_OSA__c)){
                string key = HandleCustomException.getKey(keyFields, entitlement);
                if (resultMap.containsKey(key)) {
                    entitlement.Processing_Status__c = 'Quote Creation Failed';
                    entitlement.Error_Log__c = resultMap.get(key);
                    entitlement.Associated_OSA__r.Processing_Status__c = 'Quote Creation Failed';
                } else {
                    entitlement.Quote__c = mapOfContractToQuoteCreate.get(entitlement.Associated_OSA__c).id;
                    entitlement.Processing_Status__c = 'Quote Created';
                    entitlement.Associated_OSA__r.Processing_Status__c = 'Quote Created';
                }

                if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r)) {
                    lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                }
            }
        }
        
        Database.SaveResult[] entitlementListQuote = Database.update(lstOfEntitlementToProcessQuote, false);
        HandleCustomException.logDatabaseErrors(entitlementListQuote);

        Database.SaveResult[] contrList = Database.update(lstOfContractsToUpdate, false);
        HandleCustomException.logDatabaseErrors(contrList);     
    }       
}