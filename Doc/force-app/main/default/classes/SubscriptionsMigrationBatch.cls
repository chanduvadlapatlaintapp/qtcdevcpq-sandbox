/**
 * @description       : Script for transforming and loading Subscriptions from OP4I Entitlement View records.
 * @author            : Micah Gerger
 * @group             : QTC
 * @last modified on  : 08-16-2024
 * @last modified by  : Micah Gerger
**/
global class SubscriptionsMigrationBatch implements Database.Batchable<sObject> {
    Map<String, SBQQ__Subscription__c> mapOfContractToSubscriptionCreate = new Map<String, SBQQ__Subscription__c>();
    Map<String, date> bundlemapOfProductStartDate = new Map<String, date>();
    Map<String, date> bundlemapOfProductEndDate = new Map<String, date>();
    Map<String, date> nonBundlemapOfProductStartDate = new Map<String, date>();
    Map<String, date> nonBundlemapOfProductEndDate = new Map<String, date>();
    Map<String, String> mapOfDateToEntitlmnt = new Map<String, String>();
    Map<String, Date> mapOfContractToEndDate = new Map<String, Date>();
    List<Contract> lstOfContractsToUpdateNew = new List<Contract>();
    Map<string, string> mapOfDateToQLE = new Map<string, string>();
    Set<id> productIds = new Set<id>();
    Set<id> priceBookIds = new Set<id>();
    Set<string> currencySet = new Set<string>();
    Product2 bundleProdId;
    List<string> lstOfContractAssignment;
    List<Contract> lstOfContractsToUpdate = new List<Contract>();
    List<String> emailAddresses;
    
    // Variables to store summaries
    Integer recordsCreated = 0;
    Integer recordsUpdated = 0;
    Integer recordsErrored = 0;
    Integer entitlementsProcessed = 0;
    Integer entitlementsErrored = 0;
    List<String> errorDetails = new List<String>();

    global SubscriptionsMigrationBatch() {}

    global SubscriptionsMigrationBatch(List<string> lstOfContractNumbers, List<String> emailAddresses) {
        lstOfContractAssignment = lstOfContractNumbers;
        this.emailAddresses = emailAddresses;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        string endCondition;
        if (lstOfContractAssignment != null && !lstOfContractAssignment.isEmpty()) {
            for (string endDigit : lstOfContractAssignment) {
                endCondition = endCondition != null ? (endCondition + ' OR ContractNumber like \'%' + endDigit + '\'') : ' ContractNumber like \'%' + endDigit + '\'';
            }
        }
        String query = 'SELECT Id, Processing_Status__c, Migration_Status__c, SBQQ__Quote__c, Legacy_Quote_Id__c, Is_Migrated_Contract__c,SBQQ__Opportunity__c FROM Contract WHERE Migration_Status__c = \'Ready\'';
        query = endCondition != null ? query + ' AND (' + endCondition + ')' : query;
        system.debug('Start Query: ' + query);
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<Contract> lstOfContracts) {
        
        // Handle Contract header values
        List<Contract> contractsToUpdate = new List<Contract>();

        List<OP4I_Entitlement_View__c> lstOfEntitlementRecords = new List<OP4I_Entitlement_View__c>();
        List<SBQQ__Subscription__c> lstOfSubscriptionsToInsert = new List<SBQQ__Subscription__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsErrorLogUpd = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementBundle = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementNotBundle = new List<OP4I_Entitlement_View__c>();
        List<OP4I_Entitlement_View__c> lstOfOneTimeEntitlements = new List<OP4I_Entitlement_View__c>();
        Map<string, string> mapOfBundleEntitlementToSubscription = new Map<string, string>();
        Map<string, Id> productPricbookEntryMap = new Map<String, Id>();
        PriceBook2 priceBookId = [select Id from Pricebook2 where Name =: Label.MigrationPriceBookName LIMIT 1]; 
        
        // Build a Set of Contract IDs from lstOfContracts
        Set<Id> contractIds = new Set<Id>();
        for (Contract c : lstOfContracts) {
            contractIds.add(c.Id);
        }

        // Query DLI and DLIP products for all OP4I_Entitlement_View__c for these contracts
        List<OP4I_Entitlement_View__c> entitlementViews = [
            SELECT Id, DLI_Product__c, DLIP_Product__c, Associated_OSA__c
            FROM OP4I_Entitlement_View__c
            WHERE Associated_OSA__c IN :contractIds
        ];

        // Map of contractId → Set of [DLI_Product__c, DLIP_Product__c] pairs
        Map<Id, Boolean> contractHasProductMismatch = new Map<Id, Boolean>();

        // Check each entitlement record for mismatched products
        for (OP4I_Entitlement_View__c ev : entitlementViews) {
            if (ev.DLI_Product__c != ev.DLIP_Product__c) {
                contractHasProductMismatch.put(ev.Associated_OSA__c, true);
            }
        }

        // Exclude contracts with any product mismatch from lstOfContracts
        List<Contract> filteredContracts = new List<Contract>();
        for (Contract c : lstOfContracts) {
            // Only include contracts with NO mismatch
            if (!contractHasProductMismatch.containsKey(c.Id)) {
                filteredContracts.add(c);
            }
        }

        // Now use filteredContracts in the rest of your batch logic
        lstOfContracts = filteredContracts;
        
        if (!lstOfContracts.isEmpty()) {
            lstOfEntitlementRecords = [SELECT Id, DLIP_Id__c, DLI_Id__c, Account__c, Total_Contract_Months__c, One_Time_Credit__c, Billing_Frequency__c, DLI_Price__c,Subscription_Term__c,Associated_OSA__r.SBQQ__RenewalTerm__c,Associated_OSA__r.AccountId,
                           Quantity__c, Start_Date__c, End_Date__c, Associated_OSA__c, Include_in_Select_Bundle__c, Product_Instance__c, DLI_Product__r.Product_Type__c, DLIP_Product__r.Product_Type__c,Associated_OSA__r.Shipping_Account__c,OP4I_Deal_Id__c,
                           Account__r.Name, Associated_OSA__r.ContractNumber, Processing_Status__c, DLI_Product__r.SBQQ__SubscriptionPricing__c, DLIP_Product__r.SBQQ__SubscriptionPricing__c,Error_Log__c, DLI_Product__r.SBQQ__SubscriptionTerm__c,Deal_Type__c,
                           DLI_Product__c, DLI_Product__r.SBQQ__BillingType__c, DLIP_Product__r.SBQQ__BillingType__c, DLI_Product__r.SBQQ__ChargeType__c, DLIP_Product__r.SBQQ__ChargeType__c, CurrencyIsoCode, DLIP_Product__c, Entitlement_Id__c, Sale_Price__c, 
                           Meter_Type__c, Segment_Index__c, Associated_OSA__r.Migration_Status__c, Support_Level__c, DLIP_Product__r.SBQQ__SubscriptionType__c,Associated_OSA__r.Deal_Type__c,Line_of_Business__c,Associated_OSA__r.OSA_Customer_Name__c,  
                           DLI_Product__r.SBQQ__SubscriptionType__c, Associated_OSA__r.Processing_Status__c, DLI_Product__r.SBQQ__PricingMethod__c, parent_subscription__c, DLIP_Product__r.SBQQ__PricingMethod__c, 
                           Additional_Discount__c, Software_License_Term__c, Associated_OSA__r.OSA_Number__c, Associated_OSA__r.Line_of_Business__c, Associated_OSA__r.Software_Payment_Terms__c,Associated_OSA__r.BillingFrequency__c,
                           Associated_OSA__r.Software_Days_Payment_Due_Renewal__c, Associated_OSA__r.Software_Billing_Frequency_Renewal__c, Renewal_Payment_Terms__c, Renewal_Billing_Frequency__c, Payment_Terms__c 
                           FROM OP4I_Entitlement_View__c WHERE Associated_OSA__c IN :lstOfContracts ORDER BY DLI_Product__c ASC];
            
            if(!lstOfEntitlementRecords.isEmpty() && lstOfEntitlementRecords.size() > 0){
              for(OP4I_Entitlement_View__c entlmnt : lstOfEntitlementRecords){
                if(mapOfContractToEndDate!=null && mapOfContractToEndDate.containskey(entlmnt.Associated_OSA__c)){
                  if(entlmnt.End_Date__c > mapOfContractToEndDate.get(entlmnt.Associated_OSA__c)){
                    mapOfContractToEndDate.put(entlmnt.Associated_OSA__c,entlmnt.End_Date__c);
                  }                                     
                }
                else{
                  mapOfContractToEndDate.put(entlmnt.Associated_OSA__c,entlmnt.End_Date__c);    
                    
                }                         
              }
              system.debug('@@snehalMapEndDate' +mapOfContractToEndDate);
            }

            
        for(Contract contract : lstOfContracts) {
          if (contract.SBQQ__Quote__c != null || contract.SBQQ__Opportunity__c != null){
              if(contract.SBQQ__Quote__c != null){
              contract.Legacy_Quote_Id__c = contract.SBQQ__Quote__c;
              contract.SBQQ__Quote__c = null;
              }
              if(contract.SBQQ__Opportunity__c != null){
              contract.SBQQ__Opportunity__c = null;
              }
              }
              contract.SBQQ__RenewalPricebookId__c = priceBookId.id;
              contract.SBQQ__AmendmentPricebookId__c = priceBookId.id;
              contract.Is_Migrated_Contract__c = true;
              contractsToUpdate.add(contract);
          }        
        contractsToUpdate.addall(updateContractEndDate(lstOfContracts,mapOfContractToEndDate));
        system.debug('@@contrsnehal'+contractsToUpdate[0].enddate);
        if (!contractsToUpdate.isEmpty()) {
            SBQQ.TriggerControl.disable();
            Set<Contract> setOfContrIds = new Set<Contract>();
            List<Contract> resultContrUpd = new List<Contract>();
            setOfContrIds.addAll(contractsToUpdate);
            resultContrUpd.addAll(setOfContrIds);   
            update resultContrUpd;
            system.debug('@@snehalUpdContr' +resultContrUpd[0].enddate);
            SBQQ.TriggerControl.enable();
            system.debug('@@snehalUpdContrdis' +resultContrUpd[0].enddate);
            recordsUpdated += resultContrUpd.size();
        }

            if (!lstOfEntitlementRecords.isEmpty()) {
                for (OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords) {
                    if (entitlement.DLI_Product__r.SBQQ__ChargeType__c == 'One-Time') {
                        lstOfOneTimeEntitlements.add(entitlement);
                    }
                    else if (entitlement.Include_in_Select_Bundle__c == true) {
                        lstOfEntitlementBundle.add(entitlement);
                        mapOfBundleEntitlementToSubscription.put(entitlement.Id, entitlement.Associated_OSA__c);
                    } else {
                        lstOfEntitlementNotBundle.add(entitlement);
                    }
                }

                if (!lstOfEntitlementBundle.isEmpty()) {
                    bundleProdId = [SELECT Id FROM Product2 WHERE Name = 'Intapp Select Bundle' AND IsActive = true LIMIT 1];
                    setStartAndEndDateForBundle(lstOfEntitlementBundle, productIds, priceBookIds, currencySet, bundlemapOfProductStartDate, bundlemapOfProductEndDate);
                }

                if (!lstOfEntitlementNotBundle.isEmpty()) {
                    setStartAndEndDateForNonBundle(lstOfEntitlementNotBundle, productIds, priceBookIds, currencySet, nonBundlemapOfProductStartDate, nonBundlemapOfProductEndDate);
                }
            }
        }

        for (PriceBookEntry priceEntry : [SELECT Id, Pricebook2Id, Product2Id, CurrencyIsoCode FROM PriceBookEntry WHERE Product2Id IN: productIds AND Pricebook2Id IN: priceBookIds]) {
            productPricbookEntryMap.put(priceEntry.Product2Id + '-' + priceEntry.Pricebook2Id + '-' + priceEntry.CurrencyIsoCode, priceEntry.Id);
        }

        system.debug('currencySet--->' + currencySet);
        system.debug('priceBookIds--->' + priceBookIds);
        system.debug('productIds--->' + productIds);

        Map<string, Id> dimentionMap = new Map<string, Id>();
        for (SBQQ__Dimension__c dimention : [SELECT Id, CurrencyIsoCode, SBQQ__Product__c FROM SBQQ__Dimension__c WHERE CurrencyIsoCode IN :currencySet AND SBQQ__Product__c IN :productIds]) {
            string key = dimention.CurrencyIsoCode + dimention.SBQQ__Product__c;
            system.debug('key--->' + key);
            dimentionMap.put(key, dimention.Id);
        }

        if (!lstOfOneTimeEntitlements.isEmpty()) {
            createOneTimeSubscriptions(lstOfOneTimeEntitlements, lstOfSubscriptionsToInsert, lstOfEntitlementRecordsUpd);
        }        

        // Creating Parent Subscriptions
        if (!lstOfEntitlementBundle.isEmpty()) {
            system.debug('in loop1');
            lstOfSubscriptionsToInsert.add(createParentSubscription(lstOfEntitlementBundle[0], productPricbookEntryMap, dimentionMap, mapOfContractToEndDate,bundlemapOfProductStartDate, bundlemapOfProductEndDate, bundleProdId));
            for (OP4I_Entitlement_View__c entitlement : lstOfEntitlementBundle) {
                entitlement.Processing_Status__c = 'Parent Subscription Created';
                entitlement.Associated_OSA__r.Processing_Status__c = 'Parent Subscription Created';
                lstOfEntitlementRecordsUpd.add(entitlement);
                if (!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r)) {
                    lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                }
                        entitlementsProcessed++;
            }
        }

        if (!lstOfEntitlementNotBundle.isEmpty()) {
            string key = '';
            for (OP4I_Entitlement_View__c entitlement : lstOfEntitlementNotBundle) {
                if (entitlement.DLI_Product__c != null) {
                    if (entitlement.Start_Date__c == null && entitlement.End_Date__c == null) {
                        lstOfSubscriptionsToInsert.add(createParentSubscription(entitlement, productPricbookEntryMap, dimentionMap, mapOfContractToEndDate,null, null, null));
                        mapOfContractToSubscriptionCreate.put(entitlement.Associated_OSA__c, lstOfSubscriptionsToInsert[0]);
                        entitlement.Processing_Status__c = 'Parent Subscription Created';
                        entitlement.Associated_OSA__r.SBQQ__RenewalTerm__c = 12;
                        entitlement.Associated_OSA__r.Deal_Type__c = entitlement.Deal_Type__c;
                        entitlement.Associated_OSA__r.CurrencyISOCode = entitlement.CurrencyISOCode;
                        entitlement.Associated_OSA__r.Shipping_Account__c = entitlement.Associated_OSA__r.OSA_Customer_Name__c;
                        entitlement.Associated_OSA__r.Migration_Status__c = 'Migrated';
                        entitlement.Associated_OSA__r.OSA_Number__c = entitlement.Associated_OSA__r.ContractNumber;
                        entitlement.Associated_OSA__r.Line_of_Business__c = entitlement.Line_of_Business__c;
                        if(entitlement.Deal_Type__c == 'Renewal'){
                        entitlement.Associated_OSA__r.Software_Payment_Terms__c = entitlement.Renewal_Payment_Terms__c;
                        entitlement.Associated_OSA__r.BillingFrequency__c = entitlement.Renewal_Billing_Frequency__c;
                        }
                        else{
                        entitlement.Associated_OSA__r.Software_Payment_Terms__c = entitlement.Payment_Terms__c; 
                        entitlement.Associated_OSA__r.BillingFrequency__c = entitlement.Billing_Frequency__c;
                        }
                        entitlement.Associated_OSA__r.Software_Days_Payment_Due_Renewal__c = entitlement.Renewal_Payment_Terms__c;
                        entitlement.Associated_OSA__r.Software_Billing_Frequency_Renewal__c = entitlement.Renewal_Billing_Frequency__c;
                        lstOfEntitlementRecordsUpd.add(entitlement);
                        if (!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r)) {
                            lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                        }
                        entitlementsProcessed++;
                    } else {
                        key = entitlement.DLI_Product__c + String.valueOf(entitlement.Start_Date__c) + String.valueOf(entitlement.End_Date__c) + String.valueOf(entitlement.Product_Instance__c);
                        system.debug('@@key info' + key);
                        if (!mapOfDateToEntitlmnt.containsKey(key)) {
                            system.debug('in loop');
                            mapOfDateToEntitlmnt.put(key, entitlement.Id);
                            system.debug('inside subscription loop');
                            lstOfSubscriptionsToInsert.add(createParentSubscription(entitlement, productPricbookEntryMap, dimentionMap,mapOfContractToEndDate, null, null, null));
                            mapOfContractToSubscriptionCreate.put(entitlement.Associated_OSA__c, lstOfSubscriptionsToInsert[0]);
                            entitlement.Processing_Status__c = 'Parent Subscription Created';
                            entitlement.Associated_OSA__r.Processing_Status__c = 'Parent Subscription Created';
                            entitlement.Associated_OSA__r.SBQQ__RenewalTerm__c = 12;
                            entitlement.Associated_OSA__r.Deal_Type__c = entitlement.Deal_Type__c;
                            entitlement.Associated_OSA__r.CurrencyISOCode = entitlement.CurrencyISOCode;
                            entitlement.Associated_OSA__r.Shipping_Account__c = entitlement.Associated_OSA__r.OSA_Customer_Name__c;
                            entitlement.Associated_OSA__r.Migration_Status__c = 'Migrated';
                            entitlement.Associated_OSA__r.OSA_Number__c = entitlement.Associated_OSA__r.ContractNumber;
                            entitlement.Associated_OSA__r.Line_of_Business__c = entitlement.Line_of_Business__c;
                            if(entitlement.Deal_Type__c == 'Renewal'){
                            entitlement.Associated_OSA__r.Software_Payment_Terms__c = entitlement.Renewal_Payment_Terms__c;
                            entitlement.Associated_OSA__r.BillingFrequency__c = entitlement.Renewal_Billing_Frequency__c;
                            }
                            else{
                            entitlement.Associated_OSA__r.Software_Payment_Terms__c = entitlement.Payment_Terms__c; 
                            entitlement.Associated_OSA__r.BillingFrequency__c = entitlement.Billing_Frequency__c;
                            }
                            entitlement.Associated_OSA__r.Software_Days_Payment_Due_Renewal__c = entitlement.Renewal_Payment_Terms__c;
                            entitlement.Associated_OSA__r.Software_Billing_Frequency_Renewal__c = entitlement.Renewal_Billing_Frequency__c;
                            lstOfEntitlementRecordsUpd.add(entitlement);
                            if (!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r)) {
                                lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                            }
                            entitlementsProcessed++;
                        }
                    }
                }
            }
        }
        system.debug('@@entitlement date' + lstOfSubscriptionsToInsert);
        List<Contract> resultContrUpdLst = new List<Contract>();
        if (!lstOfEntitlementRecordsErrorLogUpd.isEmpty()) {
            update lstOfEntitlementRecordsErrorLogUpd;
            entitlementsErrored += lstOfEntitlementRecordsErrorLogUpd.size();
        }

        if (!lstOfSubscriptionsToInsert.isEmpty()) {
            SBQQ.TriggerControl.disable();
            insertSubscriptionsAndEntitlement(lstOfSubscriptionsToInsert, lstOfEntitlementRecordsUpd, mapOfContractToSubscriptionCreate, bundleProdId, lstOfContractsToUpdate);
            SBQQ.TriggerControl.enable();
            recordsCreated += lstOfSubscriptionsToInsert.size();
        }

        if (!lstOfContractsToUpdate.isEmpty()) {
            SBQQ.TriggerControl.disable();
            Set<Contract> setOfContrIdsNew = new Set<Contract>();
            setOfContrIdsNew.addAll(lstOfContractsToUpdate);
            resultContrUpdLst.addAll(setOfContrIdsNew); 
            update resultContrUpdLst;
            SBQQ.TriggerControl.enable();
            recordsUpdated += resultContrUpdLst.size();
        } 

        // Create Child Subscriptions
        if (!lstOfEntitlementRecords.isEmpty()) {
            SBQQ.TriggerControl.disable();
            system.debug('@@in disable loop');
            createChildSubscriptions(lstOfEntitlementRecords, productPricbookEntryMap, dimentionMap, mapOfDateToEntitlmnt, resultContrUpdLst);
            SBQQ.TriggerControl.enable();
        }
    }

    global void finish(Database.BatchableContext bc) {
        if (emailAddresses != null && !emailAddresses.isEmpty()) {
            system.debug('@@Sending Email');
            sendSummaryEmail();
        }
    }

    global void sendSummaryEmail() {
        String subject = 'Subscriptions Migration Summary';
        String body = 'Migration Process Summary:\n\n';
        body += 'Number of Subscriptions Created: ' + recordsCreated + '\n';
        body += 'Number of Contracts Updated: ' + recordsUpdated + '\n';
        body += 'Number of OP4I Entitlement View Records Processed Successfully: ' + entitlementsProcessed + '\n';
        body += 'Number of OP4I Entitlement View Records Errored: ' + entitlementsErrored + '\n';
        body += 'Number of Errors: ' + recordsErrored + '\n\n';
        if (!errorDetails.isEmpty()) {
            body += 'Error Details:\n';
            body += String.join(errorDetails, '\n');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(emailAddresses);
        mail.setSubject(subject);
        mail.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        system.debug('@@Email Sent');
    }

    private void createOneTimeSubscriptions(List<OP4I_Entitlement_View__c> oneTimeEntitlements, List<SBQQ__Subscription__c> lstOfSubscriptionsToInsert,
                                            List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd) {
        for (OP4I_Entitlement_View__c entitlement : oneTimeEntitlements) {
            SBQQ__Subscription__c subscription = new SBQQ__Subscription__c();
            subscription.SBQQ__Account__c = entitlement.Associated_OSA__r.AccountId;
            subscription.SBQQ__Product__c = entitlement.DLI_Product__c;
            subscription.SBQQ__Contract__c = entitlement.Associated_OSA__c;
            subscription.CurrencyIsoCode = entitlement.CurrencyIsoCode;
            subscription.SBQQ__Quantity__c = entitlement.Quantity__c;
            subscription.SBQQ__ListPrice__c = entitlement.Sale_Price__c;
            subscription.SBQQ__CustomerPrice__c = entitlement.Sale_Price__c;
            subscription.SBQQ__RegularPrice__c = entitlement.Sale_Price__c;
            subscription.SBQQ__NetPrice__c = entitlement.Sale_Price__c;
            subscription.SBQQ__SubscriptionType__c = 'One-Time';
            subscription.SBQQ__ProductSubscriptionType__c = 'One-Time';
            subscription.SBQQ__SubscriptionPricing__c = 'One-Time';
            subscription.SBQQ__ProrateMultiplier__c = 1.0;

            lstOfSubscriptionsToInsert.add(subscription);
            mapOfContractToSubscriptionCreate.put(entitlement.Associated_OSA__c, lstOfSubscriptionsToInsert[0]);

            entitlement.Processing_Status__c = 'One-Time Subscription Created';
            entitlement.Associated_OSA__r.CurrencyISOCode = entitlement.CurrencyISOCode;
            entitlement.Associated_OSA__r.Shipping_Account__c = entitlement.Associated_OSA__r.OSA_Customer_Name__c;
            entitlement.Associated_OSA__r.Migration_Status__c = 'Migrated';
            entitlement.Associated_OSA__r.OSA_Number__c = entitlement.Associated_OSA__r.ContractNumber;
            entitlement.Associated_OSA__r.Line_of_Business__c = entitlement.Line_of_Business__c;

            lstOfEntitlementRecordsUpd.add(entitlement);
    
            if (!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r)) {
                lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
            }
            entitlementsProcessed++;
        }
    }    

    global SBQQ__Subscription__c createParentSubscription(OP4I_Entitlement_View__c entitlement, Map<string, Id> productPricbookEntryMap, Map<string, Id> dimentionMap,Map<String, Date> mapOfContractToEndDate, Map<string, date> bundlemapOfProductStartDate, Map<string, date> bundlemapOfProductEndDate, Product2 bundleProdId) {
        SBQQ__Subscription__c subscriptionMigration = new SBQQ__Subscription__c();
        subscriptionMigration.SBQQ__Account__c = entitlement.Associated_OSA__r.AccountId;
        subscriptionMigration.Originating_Deal_ID__c = entitlement.OP4I_Deal_Id__c;
        subscriptionMigration.SBQQ__Contract__c = entitlement.Associated_OSA__c;
        subscriptionMigration.SBQQ__Product__c = entitlement.DLI_Product__c;
        subscriptionMigration.SBQQ__Number__c = Integer.valueOf(entitlement.Segment_Index__c);
        subscriptionMigration.SBQQ__Quantity__c = entitlement.Quantity__c;
        subscriptionMigration.SBQQ__RenewalQuantity__c = entitlement.Quantity__c;
        subscriptionMigration.SBQQ__PricingMethod__c = entitlement.DLI_Product__r.SBQQ__PricingMethod__c;
        
        if(entitlement.DLI_Product__c != entitlement.DLIP_Product__c){
        subscriptionMigration.SBQQ__NetPrice__c = entitlement.DLI_Price__c; 
        subscriptionMigration.SBQQ__ListPrice__c = entitlement.DLI_Price__c;    
        subscriptionMigration.SBQQ__RegularPrice__c = entitlement.DLI_Price__c; 
        subscriptionMigration.DLI_Price__c = entitlement.DLI_Price__c;    
        subscriptionMigration.SBQQ__CustomerPrice__c = entitlement.DLI_Price__c;        
        }
        else{
        subscriptionMigration.SBQQ__NetPrice__c = entitlement.Sale_Price__c;
        subscriptionMigration.SBQQ__ListPrice__c = entitlement.Sale_Price__c;
        subscriptionMigration.SBQQ__RegularPrice__c = entitlement.Sale_Price__c;
        subscriptionMigration.DLI_Price__c = entitlement.Sale_Price__c;
        subscriptionMigration.SBQQ__CustomerPrice__c = entitlement.Sale_Price__c;
        }
     // subscriptionMigration.SBQQ__ProrateMultiplier__c = 1;
        subscriptionMigration.SBQQ__SubscriptionPricing__c = entitlement.DLI_Product__r.SBQQ__SubscriptionPricing__c;
        subscriptionMigration.SBQQ__ProductSubscriptionType__c = entitlement.DLI_Product__r.SBQQ__SubscriptionType__c;
        subscriptionMigration.SBQQ__SubscriptionType__c = entitlement.DLI_Product__r.SBQQ__SubscriptionType__c;
        subscriptionMigration.SBQQ__SubscriptionStartDate__c = entitlement.Start_Date__c;
      //  subscriptionMigration.SBQQ__SubscriptionEndDate__c = entitlement.Associated_OSA__r.EndDate;
        subscriptionMigration.SBQQ__SubscriptionEndDate__c = mapOfContractToEndDate.get(entitlement.Associated_OSA__c);
        subscriptionMigration.DLI_Id__c = entitlement.DLI_Id__c;
        subscriptionMigration.DLIP_Id__c = entitlement.DLIP_Id__c;
        subscriptionMigration.Entitlement_Id__c = entitlement.Entitlement_Id__c;
        subscriptionMigration.DLIP_Product_Type__c = entitlement.DLIP_Product__r.Product_Type__c;
        subscriptionMigration.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c;
        subscriptionMigration.CurrencyIsoCode = entitlement.CurrencyIsoCode;
        subscriptionMigration.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c;
        subscriptionMigration.SBQQ__ChargeType__c = entitlement.DLI_Product__r.SBQQ__ChargeType__c;
        subscriptionMigration.SBQQ__BillingType__c = entitlement.DLI_Product__r.SBQQ__BillingType__c;
        subscriptionMigration.Support_Level__c = entitlement.Support_Level__c;
        subscriptionMigration.Per_Integrations__c = entitlement.Meter_Type__c;
        
        /* Add List Price Derivation Step here
        if(entitlement.Additional_Discount__c != null) {
            subscriptionMigration.SBQQ__AdditionalDiscountAmount__c = entitlement.Additional_Discount__c;
            subscriptionMigration.SBQQ__ListPrice__c = 
        }
        */

        if (entitlement.Include_in_Select_Bundle__c == true) {
            subscriptionMigration.SBQQ__Quantity__c = 1;
            subscriptionMigration.SBQQ__SubscriptionStartDate__c = bundlemapOfProductStartDate.get(entitlement.DLI_Product__c);
            subscriptionMigration.SBQQ__SubscriptionEndDate__c = bundlemapOfProductEndDate.get(entitlement.DLI_Product__c);
            subscriptionMigration.SBQQ__Product__c = bundleProdId.Id;
        }

        if (subscriptionMigration.SBQQ__SegmentIndex__c != null && entitlement.Include_in_Select_Bundle__c == false) {
            string key = subscriptionMigration.CurrencyIsoCode + subscriptionMigration.SBQQ__Product__c;
            if (entitlement.DLI_Product__r.SBQQ__ChargeType__c != 'One-Time') {
                subscriptionMigration.SBQQ__Dimension__c = dimentionMap.get(key);
            }
            subscriptionMigration.SBQQ__SegmentKey__c = subscriptionMigration.SBQQ__Product__c + '|' + String.valueOf(entitlement.Product_Instance__c);
            subscriptionMigration.SBQQ__SegmentLabel__c = 'Year  ' + entitlement.Segment_Index__c;
            subscriptionMigration.SBQQ__SegmentQuantity__c = entitlement.Quantity__c;
            subscriptionMigration.SBQQ__SegmentStartDate__c = entitlement.Start_Date__c;
            subscriptionMigration.SBQQ__SegmentEndDate__c = entitlement.End_Date__c;
        }

        //Calculate prorate multiplier
       // subscriptionMigration.SBQQ__ProrateMultiplier__c = calculateProrateMultiplier(entitlement.Start_Date__c, entitlement.End_Date__c, subscriptionMigration.SBQQ__SubscriptionStartDate__c, subscriptionMigration.SBQQ__SubscriptionEndDate__c);
          subscriptionMigration.SBQQ__ProrateMultiplier__c = entitlement.Subscription_Term__c;
        return subscriptionMigration;
    }

    global void insertSubscriptionsAndEntitlement(List<SBQQ__Subscription__c> lstOfSubscriptionsToInsert, List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd, Map<String, SBQQ__Subscription__c> mapOfContractToSubscriptionCreate, Product2 bundleProdId, List<Contract> lstOfContractsToUpdate) {
        List<OP4I_Entitlement_View__c> entitlementListToUpd = new List<OP4I_Entitlement_View__c>();
        Set<Id> setOfQLEIds = new Set<Id>();
        List<SBQQ__Subscription__c> lstOfSubscriptions = new List<SBQQ__Subscription__c>();
        Map<String, String> mapOfQliTOProduct = new Map<String, String>();
        Database.SaveResult[] subscriptionInsertResult = Database.insert(lstOfSubscriptionsToInsert, false);

        map<string, string> resultMap = HandleCustomException.logMigrationDatabaseError(
            subscriptionInsertResult,
            mapOfContractToSubscriptionCreate,
            'SBQQ__Product__c,SBQQ__SubscriptionStartDate__c,SBQQ__SubscriptionEndDate__c',
            lstOfSubscriptionsToInsert
        );

        for (Database.SaveResult sr : subscriptionInsertResult) {
            if (sr.isSuccess()) {
                System.debug('Record Create/Update was Successful' + sr.getId());
                setOfQLEIds.add(sr.getId());
            } else {
                recordsErrored++;
                errorDetails.add('Error on Subscription Id: ' + sr.getId() + ' - ' + sr.getErrors()[0].getMessage());
            }
        }

        if (setOfQLEIds != null) {
            lstOfSubscriptions = [SELECT Id, SBQQ__Product__c, SBQQ__SegmentStartDate__c, SBQQ__Contract__c, SBQQ__SegmentEndDate__c FROM SBQQ__Subscription__c WHERE ID IN: setOfQLEIds];
            for (SBQQ__Subscription__c subscriptionObj : lstOfSubscriptions) {
                mapOfQliTOProduct.put(subscriptionObj.SBQQ__Product__c, subscriptionObj.Id);
                string key = subscriptionObj.SBQQ__Product__c + String.valueOf(subscriptionObj.SBQQ__SegmentStartDate__c) + String.valueOf(subscriptionObj.SBQQ__SegmentEndDate__c);
                mapOfDateToQLE.put(key, subscriptionObj.Id);
            }
        }

        string keyFields = 'DLI_Product__c,Start_Date__c,End_Date__c';
        for (OP4I_Entitlement_View__c entitlmnt : lstOfEntitlementRecordsUpd) {
            string keyQLE = entitlmnt.DLI_Product__c + String.valueOf(entitlmnt.Start_Date__c) + String.ValueOf(entitlmnt.End_Date__c);
            if (entitlmnt.DLI_Product__c != entitlmnt.DLIP_Product__c && entitlmnt.Include_in_Select_Bundle__c == false) {
                entitlmnt.Parent_Subscription__c = mapOfDateToQLE.get(keyQLE);
            } else if (entitlmnt.Include_in_Select_Bundle__c == true) {
                entitlmnt.Parent_Subscription__c = mapOfQliTOProduct.get(bundleProdId.Id);
            }

            string key = HandleCustomException.getKey(keyFields, entitlmnt);
            if (resultMap.containsKey(key)) {
                entitlmnt.Error_Log__c = resultMap.get(key);
                entitlmnt.Processing_Status__c = 'Parent Subscription Creation failed';
                entitlmnt.Associated_OSA__r.Processing_Status__c = 'Parent Subscription Creation failed';
                recordsErrored++;
                entitlementsErrored++;
                errorDetails.add('Entitlement Error on Id: ' + entitlmnt.Id + ' - ' + entitlmnt.Error_Log__c);
            }

            entitlementListToUpd.add(entitlmnt);
        }

        system.debug('@@Entitlement Parent Subscription' + subscriptionInsertResult[0].getId());
        system.debug('@@Entitlement List' + entitlementListToUpd);
        SBQQ.TriggerControl.disable();
        Database.SaveResult[] entitlementListOpp = Database.update(entitlementListToUpd, false);
        SBQQ.TriggerControl.enable();
        HandleCustomException.logDatabaseErrors(entitlementListOpp);

      //  updateContractsForRenewals(lstOfContractsToUpdate, lstOfSubscriptions);
    }

    global void updateContractsForRenewals(List<Contract> lstOfContractsToUpdate, List<SBQQ__Subscription__c> lstOfSubscriptions) {
        for (Contract contract : lstOfContractsToUpdate) {
            Date earliestStartDate;
            Date latestEndDate;
            for (SBQQ__Subscription__c subscription : lstOfSubscriptions) {
                if (subscription.SBQQ__Contract__c == contract.Id) {
                    if (earliestStartDate == null || subscription.SBQQ__SubscriptionStartDate__c < earliestStartDate) {
                        earliestStartDate = subscription.SBQQ__SubscriptionStartDate__c;
                    }
                    if (latestEndDate == null || subscription.SBQQ__SubscriptionEndDate__c > latestEndDate) {
                        latestEndDate = subscription.SBQQ__SubscriptionEndDate__c;
                    }
                }
            }
            contract.StartDate = earliestStartDate;
            contract.EndDate = latestEndDate;
            //contract.SBQQ__RenewalTerm__c = ; // Example value, adjust as needed
            contract.SBQQ__AmendmentRenewalBehavior__c = 'Latest End Date'; 
        }
        update lstOfContractsToUpdate;
    }
    
    global List<Contract> updateContractEndDate(List<Contract> lstOfContractsToUpdate, Map<String, Date> mapOfContractToEndDate) {
        for (Contract contr : lstOfContractsToUpdate) {
          if(mapOfContractToEndDate.containskey(contr.id)){
            contr.EndDate = mapOfContractToEndDate.get(contr.Id);
            lstOfContractsToUpdateNew.add(contr);
          }                     
        }
        system.debug('@@snehalinEnd' +lstOfContractsToUpdateNew[0].enddate);
        return lstOfContractsToUpdateNew;
    }       

    global static void setStartAndEndDateForNonBundle(List<OP4I_Entitlement_View__c> lstOfEntitlementNotBundle, Set<id> productIds, Set<id> priceBookIds, Set<string> currencySet, Map<string, date> nonBundlemapOfProductStartDate, Map<string, date> nonBundlemapOfProductEndDate) {
        if (!lstOfEntitlementNotBundle.isEmpty()) {
            for (OP4I_Entitlement_View__c entitlement : lstOfEntitlementNotBundle) {
                priceBookIds.add(entitlement.DLIP_Product__c);
                currencySet.add(entitlement.CurrencyIsoCode);
                productIds.add(entitlement.DLI_Product__c);
                productIds.add(entitlement.DLIP_Product__c);
                if (nonBundlemapOfProductStartDate != null && nonBundlemapOfProductStartDate.containsKey(entitlement.DLI_Product__c)) {
                    if (nonBundlemapOfProductStartDate.get(entitlement.DLI_Product__c) > entitlement.Start_Date__c) {
                        nonBundlemapOfProductStartDate.put(entitlement.DLI_Product__c, entitlement.Start_Date__c);
                    }
                } else {
                    nonBundlemapOfProductStartDate.put(entitlement.DLI_Product__c, entitlement.Start_Date__c);
                }
                if (nonBundlemapOfProductEndDate != null && nonBundlemapOfProductEndDate.containsKey(entitlement.DLI_Product__c)) {
                    if (nonBundlemapOfProductEndDate.get(entitlement.DLI_Product__c) < entitlement.End_Date__c) {
                        nonBundlemapOfProductEndDate.put(entitlement.DLI_Product__c, entitlement.End_Date__c);
                    }
                } else {
                    nonBundlemapOfProductEndDate.put(entitlement.DLI_Product__c, entitlement.End_Date__c);
                }
            }
        }
    }

    global static void setStartAndEndDateForBundle(List<OP4I_Entitlement_View__c> lstOfEntitlementBundle, Set<id> productIds, Set<id> priceBookIds, Set<string> currencySet, Map<string, date> bundlemapOfProductStartDate, Map<string, date> bundlemapOfProductEndDate) {
        if (!lstOfEntitlementBundle.isEmpty()) {
            for (OP4I_Entitlement_View__c entitlement : lstOfEntitlementBundle) {
                priceBookIds.add(entitlement.DLIP_Product__c);
                currencySet.add(entitlement.CurrencyIsoCode);
                productIds.add(entitlement.DLI_Product__c);
                productIds.add(entitlement.DLIP_Product__c);
                if (bundlemapOfProductStartDate.containsKey(entitlement.DLI_Product__c)) {
                    if (bundlemapOfProductStartDate.get(entitlement.DLI_Product__c) > entitlement.Start_Date__c) {
                        bundlemapOfProductStartDate.put(entitlement.DLI_Product__c, entitlement.Start_Date__c);
                    }
                } else {
                    bundlemapOfProductStartDate.put(entitlement.DLI_Product__c, entitlement.Start_Date__c);
                }

                if (bundlemapOfProductEndDate.containsKey(entitlement.DLI_Product__c)) {
                    if (bundlemapOfProductEndDate.get(entitlement.DLI_Product__c) < entitlement.End_Date__c) {
                        bundlemapOfProductEndDate.put(entitlement.DLI_Product__c, entitlement.End_Date__c);
                    }
                } else {
                    bundlemapOfProductEndDate.put(entitlement.DLI_Product__c, entitlement.End_Date__c);
                }
            }
        }
    }

    global void createChildSubscriptions(List<OP4I_Entitlement_View__c> lstOfEntitlementRecords, Map<String, Id> productPricbookEntryMap, Map<String, Id> dimentionMap, Map<String, String> mapOfDateToEntitlmnt, List<Contract> lstOfContractsToUpdate) {
        List<SBQQ__Subscription__c> lstOfSubscriptionsToInsertChild = new List<SBQQ__Subscription__c>();
        List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd = new List<OP4I_Entitlement_View__c>();
        Map<SBQQ__Subscription__c, String> mapOfQliToRequiredByToProduct = new Map<SBQQ__Subscription__c, String>();
        Set<id> setOfQuoteIds = new Set<id>();
        set<id> setOfContractIds = new set<id>();

        if (!lstOfEntitlementRecords.isEmpty()) {
            for (OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords) {
                if (entitlement.DLIP_Product__c != null && entitlement.DLI_Product__c != entitlement.DLIP_Product__c) {
                    SBQQ__Subscription__c subscriptionChild = createChildSubscription(entitlement, productPricbookEntryMap, dimentionMap, mapOfContractToEndDate);
                    if (entitlement.Parent_Subscription__c == null) {
                        setOfQuoteIds.add(subscriptionChild.SBQQ__Contract__c);
                        mapOfQliToRequiredByToProduct.put(subscriptionChild, entitlement.DLI_Product__c);
                    }
                    lstOfSubscriptionsToInsertChild.add(subscriptionChild);
                    entitlement.Processing_Status__c = 'Child Subscription Created';
                    entitlement.Associated_OSA__r.Processing_Status__c = 'Child Subscription Created';
                    lstOfEntitlementRecordsUpd.add(entitlement);
                    if (!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r)) {
                        lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                    }
                    entitlementsProcessed++;
                }
            }
            
            if(lstOfSubscriptionsToInsertChild.size() == 0){
                system.debug('@@in contr upd loop 1');
                if(lstOfContractsToUpdate.size() > 0){
                    system.debug('@@in contr upd loop 2');
                    for(Contract contr : lstOfContractsToUpdate){
                    contr.Migration_Status__c = 'Migrated';                     
                    }
                    Set<Contract> setOfContrIdsNewUpd = new Set<Contract>();
                    List<Contract> resultContrUpdLstt = new List<Contract>();
                    setOfContrIdsNewUpd.addAll(lstOfContractsToUpdate);
                    resultContrUpdLstt.addAll(setOfContrIdsNewUpd); 
                    update resultContrUpdLstt;
                //  Database.SaveResult[] contrUpdateListFinal = Database.update(resultContrUpdLstt, false);
                //  HandleCustomException.logDatabaseErrors(contrUpdateListFinal);                
                }                       
            }
        }

        if (!lstOfSubscriptionsToInsertChild.isEmpty()) {
            insertChildSubscriptions(lstOfSubscriptionsToInsertChild, lstOfEntitlementRecordsUpd, mapOfQliToRequiredByToProduct);
            recordsCreated += lstOfSubscriptionsToInsertChild.size();
        }
    }

    global SBQQ__Subscription__c createChildSubscription(OP4I_Entitlement_View__c entitlement, Map<String, Id> productPricbookEntryMap, Map<String, Id> dimentionMap,Map<String, Date> mapOfContractToEndDate) {
        SBQQ__Subscription__c subscriptionChild = new SBQQ__Subscription__c();
        subscriptionChild.SBQQ__Account__c = entitlement.Associated_OSA__r.AccountId;
        subscriptionChild.Originating_Deal_ID__c = entitlement.OP4I_Deal_Id__c;
        subscriptionChild.SBQQ__Contract__c = entitlement.Associated_OSA__c;
        subscriptionChild.SBQQ__RootId__c = entitlement.Parent_Subscription__c;
        subscriptionChild.SBQQ__Product__c = entitlement.DLIP_Product__c;
        subscriptionChild.SBQQ__Number__c = Integer.valueOf(entitlement.Segment_Index__c);
        subscriptionChild.SBQQ__Quantity__c = entitlement.Quantity__c;
        subscriptionChild.SBQQ__RenewalQuantity__c = entitlement.Quantity__c;
        subscriptionChild.SBQQ__PricingMethod__c = entitlement.DLIP_Product__r.SBQQ__PricingMethod__c;
        subscriptionChild.SBQQ__ListPrice__c = entitlement.Sale_Price__c;
        subscriptionChild.SBQQ__CustomerPrice__c = entitlement.Sale_Price__c;
        subscriptionChild.SBQQ__NetPrice__c = entitlement.Sale_Price__c;
        //subscriptionChild.SBQQ__ProrateMultiplier__c = 1;
        subscriptionChild.SBQQ__SubscriptionPricing__c = entitlement.DLIP_Product__r.SBQQ__SubscriptionPricing__c;
        subscriptionChild.SBQQ__ProductSubscriptionType__c = entitlement.DLIP_Product__r.SBQQ__SubscriptionType__c;
        subscriptionChild.SBQQ__SubscriptionType__c = entitlement.DLIP_Product__r.SBQQ__SubscriptionType__c;
        subscriptionChild.SBQQ__SubscriptionStartDate__c = entitlement.Start_Date__c;
      //  subscriptionChild.SBQQ__SubscriptionEndDate__c = entitlement.Associated_OSA__r.EndDate;
        subscriptionChild.SBQQ__SubscriptionEndDate__c = mapOfContractToEndDate.get(entitlement.Associated_OSA__c);
        subscriptionChild.SBQQ__RequiredByProduct__c = entitlement.DLI_Product__c;
      //  subscriptionChild.SBQQ__RequiredById__c = entitlement.Parent_Subscription__c;
        subscriptionChild.SBQQ__RequiredById__c = mapOfDateToQLE.get(entitlement.DLI_Product__c + String.ValueOf(entitlement.Start_Date__c) + string.ValueOf(entitlement.End_Date__c));
        subscriptionChild.DLI_Id__c = entitlement.DLI_Id__c;
        subscriptionChild.DLIP_Id__c = entitlement.DLIP_Id__c;
        subscriptionChild.Entitlement_Id__c = entitlement.Entitlement_Id__c;
        subscriptionChild.DLIP_Product_Type__c = entitlement.DLIP_Product__r.Product_Type__c;
        subscriptionChild.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c;
        subscriptionChild.SBQQ__ChargeType__c = entitlement.DLIP_Product__r.SBQQ__ChargeType__c;
        subscriptionChild.SBQQ__BillingType__c = entitlement.DLIP_Product__r.SBQQ__BillingType__c;
        subscriptionChild.Support_Level__c = entitlement.Support_Level__c;
        subscriptionChild.Per_Integrations__c = entitlement.Meter_Type__c;
        subscriptionChild.SBQQ__RegularPrice__c = entitlement.Sale_Price__c;

        //Add List Price derivation here as well
        if (entitlement.Additional_Discount__c != null) {
            subscriptionChild.SBQQ__AdditionalDiscountAmount__c = entitlement.Additional_Discount__c;
        }

        subscriptionChild.CurrencyIsoCode = entitlement.CurrencyIsoCode;

        if (subscriptionChild.SBQQ__SegmentIndex__c != null) {
            string key = subscriptionChild.CurrencyIsoCode + subscriptionChild.SBQQ__Product__c;
            if (entitlement.DLIP_Product__r.SBQQ__ChargeType__c != 'One-Time') {
                subscriptionChild.SBQQ__Dimension__c = dimentionMap.get(key);
            }
            subscriptionChild.SBQQ__SegmentKey__c = subscriptionChild.SBQQ__Product__c + '|' + String.valueOf(entitlement.Product_Instance__c);
            subscriptionChild.SBQQ__SegmentLabel__c = 'Year  ' + entitlement.Segment_Index__c; //added extra space
            subscriptionChild.SBQQ__SegmentQuantity__c = entitlement.Quantity__c;
            subscriptionChild.SBQQ__SegmentStartDate__c = entitlement.Start_Date__c;
            subscriptionChild.SBQQ__SegmentEndDate__c = entitlement.End_Date__c;
        }

         // Prorate Multiplier Calculation
        // subscriptionChild.SBQQ__ProrateMultiplier__c = calculateProrateMultiplier(entitlement.Start_Date__c, entitlement.End_Date__c, subscriptionChild.SBQQ__SubscriptionStartDate__c, subscriptionChild.SBQQ__SubscriptionEndDate__c);
            subscriptionChild.SBQQ__ProrateMultiplier__c = entitlement.Subscription_Term__c;
        return subscriptionChild;
    }
    
    // Method to calculate prorate multipler
    private Integer calculateProrateMultiplier(Date segmentStartDate, Date segmentEndDate, Date subscriptionStartDate, Date subscriptionEndDate) {
        Date startDate;
        Date endDate;

        // Determine which dates to use: Segment dates if populated, otherwise Subscription dates
        if (segmentStartDate != null && segmentEndDate != null) {
            startDate = segmentStartDate;
            endDate = segmentEndDate;
        } else {
            startDate = subscriptionStartDate;
            endDate = subscriptionEndDate;
        }

        // Ensure both dates are populated
        if (startDate != null && endDate != null) {
            Integer startYear = startDate.year();
            Integer startMonth = startDate.month();
            Integer endYear = endDate.year();
            Integer endMonth = endDate.month();

            // Calculate the difference in months
            Integer monthDifference = (endYear - startYear) * 12 + (endMonth - startMonth);
            return monthDifference > 0 ? monthDifference : 1; // Ensure at least 1 month
        }

        // If dates are not valid, return a default multiplier of 1
        return 1;
    }

    global void insertChildSubscriptions(List<SBQQ__Subscription__c> lstOfSubscriptionsToInsertChild, List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd, Map<SBQQ__Subscription__c, String> mapOfQliToRequiredByToProduct) {
        List<SBQQ__Subscription__c> lstOfSubscriptionsToInsertChildUpd = new List<SBQQ__Subscription__c>();
        Set<Id> setOfQuoteIds = new Set<Id>();
        set<Id> setOfContractIds = new set<Id>();
        List<Contract> lstOfContractsToUpdate = new List<Contract>();

        Database.SaveResult[] subscriptionInsertResult = Database.insert(lstOfSubscriptionsToInsertChild, false);
        for (Database.SaveResult sr : subscriptionInsertResult) {
            if (sr.isSuccess()) {
                System.debug('Record Create/Update was Successful' + sr.getId());
                setOfQuoteIds.add(sr.getId());
            } else {
                recordsErrored++;
                errorDetails.add('Error on Subscription Id: ' + sr.getId() + ' - ' + sr.getErrors()[0].getMessage());
            }
        }
        system.debug('@@snehal' +setOfQuoteIds);

        if (setOfQuoteIds != null && !setOfQuoteIds.isEmpty()) {
            List<SBQQ__Subscription__c> lstOfSubscriptionsRequiredByNull = [SELECT Id, SBQQ__Contract__c,SBQQ__Contract__r.Migration_Status__c, SBQQ__Product__c, SBQQ__SubscriptionStartDate__c, SBQQ__SubscriptionEndDate__c,SBQQ__SegmentStartDate__c,SBQQ__SegmentEndDate__c FROM SBQQ__Subscription__c WHERE Id IN: mapOfQliToRequiredByToProduct.values()];
            Map<String, String> mapOfDateToQleId = new Map<String, String>();
            if (!lstOfSubscriptionsRequiredByNull.IsEmpty()) {
                system.debug('@@in subs loop');
                for (SBQQ__Subscription__c subReq : lstOfSubscriptionsRequiredByNull) {
                    mapOfDateToQleId.put(subReq.SBQQ__Product__c + String.ValueOf(subReq.SBQQ__SegmentStartDate__c) + String.ValueOf(subReq.SBQQ__SegmentEndDate__c), subReq.id);
                    subReq.SBQQ__Contract__r.Migration_Status__c = 'Migrated';
                    setOfContractIds.add(subReq.SBQQ__Contract__c);
                }
            }
            if (!lstOfSubscriptionsToInsertChild.isEmpty()) {
                for (SBQQ__Subscription__c sub : lstOfSubscriptionsToInsertChild) {
                    if (sub.SBQQ__RequiredById__c == null) {
                        sub.SBQQ__RequiredById__c = mapOfDateToQLE.get(mapOfQliToRequiredByToProduct.get(sub) + String.ValueOf(sub.SBQQ__SegmentStartDate__c) + String.ValueOf(sub.SBQQ__SegmentEndDate__c));
                    }
                    lstOfSubscriptionsToInsertChildUpd.add(sub);
                }
            }
            if(setOfContractIds.size() > 0){
            system.debug('@@in contr upd loop');
            List<Contract> lstOfContractsToUpdateFinal = [Select Id FROM Contract WHERE ID IN: setOfContractIds];
              if(!lstOfContractsToUpdateFinal.IsEmpty() && lstOfContractsToUpdateFinal.size() > 0){
                SBQQ.TriggerControl.disable();
                Database.SaveResult[] contrUpdateListFinal = Database.update(lstOfContractsToUpdateFinal, false);
                SBQQ.TriggerControl.enable();
                HandleCustomException.logDatabaseErrors(contrUpdateListFinal);                
              }                     
            }
        }

      /*  if (lstOfSubscriptionsToInsertChildUpd != null && !lstOfSubscriptionsToInsertChildUpd.isEmpty()) {
            update lstOfSubscriptionsToInsertChildUpd;
        } */

        Database.SaveResult[] entitlementListOpp = Database.update(lstOfEntitlementRecordsUpd, false);
        HandleCustomException.logDatabaseErrors(entitlementListOpp);
    }
}