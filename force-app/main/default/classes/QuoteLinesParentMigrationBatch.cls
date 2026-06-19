global class QuoteLinesParentMigrationBatch implements Database.Batchable<sObject>{
  List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsertChild = new List<SBQQ__QuoteLine__c>();
  Map<String,SBQQ__QuoteLine__c> mapOfContractToQuoteLineCreate = new Map<String,SBQQ__QuoteLine__c>();
  Map<string,date> bundlemapOfProductStartDate = new Map<string,date>();
  Map<string,date> bundlemapOfProductEndDate = new Map<string,date>();
  Map<string,date> nonBundlemapOfProductStartDate = new Map<string,date>();
  Map<string,date> nonBundlemapOfProductEndDate = new Map<string,date>();
  Set<id> productIds = new set<id>();
  set<id> priceBookIds = new set<id>(); 
  set<string> currencySet = new set<string>();
  Product2 bundleProdId = new Product2();
  List<string> lstOfContractAssignment;
  global QuoteLinesParentMigrationBatch() {}

  global QuoteLinesParentMigrationBatch(List<string> lstOfContractNumbers){
      lstOfContractAssignment = lstOfContractNumbers ;
  }

  global Database.QueryLocator start(Database.BatchableContext bc){
      string endCondition;
      if (lstOfContractAssignment != null && !lstOfContractAssignment.isempty()) {
          for (string endDigit : lstOfContractAssignment) {
              endCondition = endCondition != null? (endCondition +  ' OR ContractNumber like \'%' + endDigit + '\'') :' ContractNumber like \'%' + endDigit + '\'';
          }
      } 
      String query = 'SELECT Id,Processing_Status__c FROM Contract WHERE Processing_Status__c = \'Quote Created\'';
      query = endCondition != null? query + ' AND (' + endCondition + ')' : query;
      system.debug('Start Query' +query);   
      return Database.getQueryLocator(query);        
  }

  global void execute(Database.BatchableContext bc, List<Contract> lstOfContracts){
      List<OP4I_Entitlement_View__c> lstOfEntitlementRecords = new List<OP4I_Entitlement_View__c>();
      List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsert = new List<SBQQ__QuoteLine__c>();
      List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd = new List<OP4I_Entitlement_View__c>(); 
      List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsErrorLogUpd = new List<OP4I_Entitlement_View__c>(); 
      List<OP4I_Entitlement_View__c> lstOfEntitlementsNotBundle = new List<OP4I_Entitlement_View__c>(); 
      List<OP4I_Entitlement_View__c> lstOfEntitlementBundle = new List<OP4I_Entitlement_View__c>();
      List<OP4I_Entitlement_View__c> lstOfEntitlementNotBundle = new List<OP4I_Entitlement_View__c>();
      List<SBQQ__QuoteLine__c> lstOfQuoteLinesToClone = new List<SBQQ__QuoteLine__c>();
      List<SBQQ__QuoteLine__c> lstOfClonedQuoteLines = new List<SBQQ__QuoteLine__c>();
      Map<SBQQ__QuoteLine__c,SBQQ__QuoteLine__c> mapOfParentToChildQuote = new Map<SBQQ__QuoteLine__c,SBQQ__QuoteLine__c>();
      Map<string,string> mapOfBundleQuoteLine = new Map<string,string>();
      Map<string,string> mapOfBundleEntitlementToQuote = new Map<string,string>();
      Map<string,string> mapOfNotBundleQuoteLine = new Map<string,string>();
      List<Contract> lstOfContractsToUpdate = new List<Contract>();
      Map<string,Id> productPricbookEntryMap = new Map<String,Id>();
      Map<string,string> mapOfDateToEntitlmnt = new Map<string,string>();
      if(!lstOfContracts.IsEmpty()){
          lstOfEntitlementRecords = [SELECT Id,DLIP_Id__c,DLI_Id__c,Account__c,Quote__c,Quote__r.SBQQ__PriceBook__c,Total_Contract_Months__c,One_Time_Credit__c,Billing_Frequency__c,DLI_Price__c,
                                  Quantity__c,Quote__r.CurrencyIsoCode,Start_Date__c,End_Date__c,Associated_OSA__c,Quote__r.SBQQ__StartDate__c,Include_in_Select_Bundle__c,Product_Instance__c,DLI_Product__r.Product_Type__c,
                                  Account__r.Name,Associated_OSA__r.ContractNumber,Opportunity__c,Processing_Status__c,DLI_Product__r.SBQQ__SubscriptionPricing__c,Error_Log__c,DLI_Product__r.SBQQ__SubscriptionTerm__c,
                                  DLI_Product__c,DLIP_Product__c,Sale_Price__c,Meter_Type__c,Segment_Index__c,Associated_OSA__r.Migration_Status__c,Support_Level__c,DLI_Product__r.SBQQ__SubscriptionType__c,
                                  Associated_OSA__r.Processing_Status__c,Additional_Discount__c,DLI_Product__r.SBQQ__ChargeType__c,DLI_Product__r.SBQQ__BillingType__c,Software_License_Term__c 
                                  FROM OP4I_Entitlement_View__c WHERE Associated_OSA__c IN: lstOfContracts ORDER BY DLI_Product__c ASC];
        if(!lstOfEntitlementRecords.IsEmpty()){
        for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords){ 
          if(entitlement.Include_in_Select_Bundle__c == true)
          {
            lstOfEntitlementBundle.add(entitlement);
            mapOfBundleQuoteLine.put(entitlement.id,entitlement.Associated_OSA__c);   
            mapOfBundleEntitlementToQuote.put(entitlement.id,entitlement.Quote__c);   
          }
          else
          {
            lstOfEntitlementNotBundle.add(entitlement);   
          }
        }
        
        if(!lstOfEntitlementBundle.IsEmpty()){
          bundleProdId = [Select ID FROM Product2 WHERE Name = 'Intapp Select Bundle' AND IsActive = true LIMIT 1];                             
          setStartAndEndDateForBundle(lstOfEntitlementBundle,productIds,priceBookIds,currencySet,bundlemapOfProductStartDate,bundlemapOfProductEndDate);                   
         }
          
        if(!lstOfEntitlementNotBundle.IsEmpty()){                           
          setStartAndEndDateForNonBundle(lstOfEntitlementNotBundle,productIds,priceBookIds,currencySet,nonBundlemapOfProductStartDate,nonBundlemapOfProductEndDate);                   
         }
        }       
      }

      for(PriceBookEntry priceEntry : [Select Id,Pricebook2Id,Product2Id,Pricebook2.Name,CurrencyIsoCode 
          FROM PriceBookEntry 
         WHERE Product2Id IN: productIds AND Pricebook2Id IN: priceBookIds
      ]){
          productPricbookEntryMap.put(priceEntry.Product2Id + '-' +priceEntry.Pricebook2Id + '-' +priceEntry.CurrencyIsoCode, priceEntry.Id);
      }

      system.debug('currencySet--->'+currencySet);
      system.debug('priceBookIds--->'+priceBookIds);
      system.debug('productIds--->'+productIds);
      Map<string,Id> dimentionMap = new Map<string,Id>();
      for (SBQQ__Dimension__c  dimention : [
          Select id,CurrencyIsoCode, SBQQ__PriceBook__c, SBQQ__Product__c,Name from SBQQ__Dimension__c 
          WHERE CurrencyIsoCode IN :currencySet AND SBQQ__Product__c IN :productIds
      ]) {
          string key = dimention.CurrencyIsoCode + dimention.SBQQ__Product__c;
          system.debug('key--->'+key);
          dimentionMap.put(key, dimention.Id);
      }

     
     if(!lstOfEntitlementBundle.IsEmpty())
     {
            system.debug('in loop1');
            lstOfQuoteLinesToInsert.add(createParentQuoteLine(lstOfEntitlementBundle[0],
                                  productPricbookEntryMap,dimentionMap,bundlemapOfProductStartDate,
                                  bundlemapOfProductEndDate,bundleProdId));
            for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementBundle){
            entitlement.Processing_Status__c = 'Parent Quote Line Created';
            entitlement.Associated_OSA__r.Processing_Status__c = 'Parent Quote Line Created';
            lstOfEntitlementRecordsUpd.add(entitlement);
            if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r))
            {
              lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
            }  
            }           
     }
     
     if(!lstOfEntitlementNotBundle.IsEmpty())
      {
      string key = '';
      for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementNotBundle){
        if(entitlement.DLI_Product__c !=null)
        {
          if(entitlement.Start_Date__c == null && entitlement.End_Date__c == null)
          {
            lstOfQuoteLinesToInsert.add(createParentQuoteLine(entitlement,
                                          productPricbookEntryMap,dimentionMap,
                                          null,null,null));
            mapOfContractToQuoteLineCreate.put(entitlement.Associated_OSA__c,lstOfQuoteLinesToInsert[0]);
            entitlement.Processing_Status__c = 'Parent Quote Line Created';
            entitlement.Associated_OSA__r.Processing_Status__c = 'Parent Quote Line Created';
            lstOfEntitlementRecordsUpd.add(entitlement);
            if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r))
            {
              lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
            }     
          }
          
          else
          {
           key = entitlement.DLI_Product__c + string.valueOf(entitlement.Start_Date__c) + string.valueOf(entitlement.End_Date__c) + string.valueof(entitlement.Product_Instance__c);
           system.debug('@@key info' +key);   
              if(!mapOfDateToEntitlmnt.containskey(key))
              {
                system.debug('in loop');
                mapOfDateToEntitlmnt.put(key,entitlement.Id);  
                system.debug('inside quote loop');
                lstOfQuoteLinesToInsert.add(createParentQuoteLine(entitlement,
                                      productPricbookEntryMap,dimentionMap,
                                      null,null,null));
                mapOfContractToQuoteLineCreate.put(entitlement.Associated_OSA__c,lstOfQuoteLinesToInsert[0]);
                entitlement.Processing_Status__c = 'Parent Quote Line Created';
                entitlement.Associated_OSA__r.Processing_Status__c = 'Parent Quote Line Created';
                lstOfEntitlementRecordsUpd.add(entitlement);
                if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r))
                {
                  lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
                }
             }
         }
        }
       }
     }
     system.debug('@@entitlement date' +lstOfQuoteLinesToInsert);

      if(!lstOfEntitlementRecordsErrorLogUpd.IsEmpty())
      {
        update lstOfEntitlementRecordsErrorLogUpd;    
      }
      
      if(!lstOfQuoteLinesToInsert.IsEmpty())
      { 
         insertQuoteLinesAndEntitlement(lstOfQuoteLinesToInsert,lstOfEntitlementRecordsUpd,mapOfContractToQuoteLineCreate,bundleProdId);
      }
     
      if(!lstOfContractsToUpdate.IsEmpty())
      {
        update lstOfContractsToUpdate;
      }           
  }

  global void finish(Database.BatchableContext bc){

  }
  
  global static SBQQ__QuoteLine__c createParentQuoteLine(OP4I_Entitlement_View__c entitlement ,
                                                   map<string,Id> productPricbookEntryMap,Map<string,Id> dimentionMap,Map<string,date> bundlemapOfProductStartDate ,
                                                   Map<string,date> bundlemapOfProductEndDate , Product2 bundleProdId )
  {
      SBQQ__QuoteLine__c quoteLineMigration = new SBQQ__QuoteLine__c();
      quoteLineMigration.SBQQ__Quote__c = entitlement.Quote__c;
      quoteLineMigration.Bypass_PriceRule__c = true; 
      quoteLineMigration.Original_List_Unit_Price__c = entitlement.Sale_Price__c;  
      quoteLineMigration.SBQQ__ProductSubscriptionType__c = entitlement.DLI_Product__r.SBQQ__SubscriptionType__c;  
      quoteLineMigration.SBQQ__SubscriptionType__c = entitlement.DLI_Product__r.SBQQ__SubscriptionType__c;
      quoteLineMigration.Product_Type__c = entitlement.DLI_Product__r.Product_Type__c;     
      if(entitlement.Include_in_Select_Bundle__c == true)
      {
      quoteLineMigration.SBQQ__Quantity__c = 1;
      quoteLineMigration.SolutionQuantity__c = 1; 
      quoteLineMigration.SBQQ__StartDate__c = bundlemapOfProductStartDate.get(entitlement.DLI_Product__c);
      quoteLineMigration.SBQQ__EndDate__c = bundlemapOfProductEndDate.get(entitlement.DLI_Product__c);
      quoteLineMigration.SBQQ__Product__c = bundleProdId.id;
      quoteLineMigration.Per_Integrations__c = '';      
      quoteLineMigration.One_Time_Credit__c = null;
    //  quoteLineMigration.SBQQ__SegmentIndex__c = 1;
    //  quoteLineMigration.SBQQ__SegmentLabel__c = 'Year  ' + 1;
      }
      else
      {
      quoteLineMigration.SBQQ__Quantity__c = entitlement.Quantity__c;
      quoteLineMigration.SolutionQuantity__c = entitlement.Quantity__c;
      quoteLineMigration.SBQQ__StartDate__c = entitlement.Start_Date__c;
      quoteLineMigration.SBQQ__EndDate__c = entitlement.End_Date__c;
      quoteLineMigration.SBQQ__Product__c = entitlement.DLI_Product__c;   
      quoteLineMigration.Per_Integrations__c = entitlement.Meter_Type__c;       
      quoteLineMigration.One_Time_Credit__c = entitlement.One_Time_Credit__c;
      quoteLineMigration.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c; 
      if(entitlement.Start_Date__c!=null && entitlement.End_Date__c!=null)
      {
      quoteLineMigration.SBQQ__SegmentLabel__c = 'Year  ' + entitlement.Segment_Index__c; 
      }     
      }
      if(entitlement.Include_in_Select_Bundle__c == true)
      {
          quoteLineMigration.SBQQ__ListPrice__c = 0; 
          quoteLineMigration.Parent_of_Bundle__c = true;          
      }
      else if((entitlement.DLIP_Product__c!=null && entitlement.DLI_Product__c != entitlement.DLIP_Product__c) && entitlement.Include_in_Select_Bundle__c == false)
      {
          quoteLineMigration.SBQQ__ListPrice__c = entitlement.DLI_Price__c; 
          quoteLineMigration.Parent_of_Bundle__c = true;          
      }
      else
      {
          quoteLineMigration.DLI_Id__c = entitlement.DLI_Id__c;
          quoteLineMigration.DLIP_Id__c = entitlement.DLIP_Id__c;
          quoteLineMigration.SBQQ__ListPrice__c = entitlement.Sale_Price__c;
          if(entitlement.Additional_Discount__c != null){
              quoteLineMigration.SBQQ__AdditionalDiscountAmount__c = entitlement.Additional_Discount__c;
          }
      }
      
      if(entitlement.Billing_Frequency__c == 'Annually')
      {
        quoteLineMigration.SBQQ__BillingFrequency__c = 'Annual';
      }
      
      else if(entitlement.Billing_Frequency__c == 'Quarterly Y1 Only')
      {
          if(entitlement.Segment_Index__c == 1)
          {
            quoteLineMigration.SBQQ__BillingFrequency__c = 'Quarterly';
          }
          else
          {
            quoteLineMigration.SBQQ__BillingFrequency__c = 'Annual';  
          }
      }
    
      else if(entitlement.Billing_Frequency__c == 'Semi-annual Y1 Only')
      {
          if(entitlement.Segment_Index__c == 1)
          {
            quoteLineMigration.SBQQ__BillingFrequency__c = 'Semiannual';
          }
          else
          {
            quoteLineMigration.SBQQ__BillingFrequency__c = 'Annual';  
          }
      }
      
      else
      {
      quoteLineMigration.SBQQ__BillingFrequency__c = entitlement.Billing_Frequency__c;
      }
      quoteLineMigration.SBQQ__SubscriptionPricing__c = entitlement.DLI_Product__r.SBQQ__SubscriptionPricing__c;  
      if(quoteLineMigration.SBQQ__ChargeType__c == null)
      {
        quoteLineMigration.SBQQ__ChargeType__c = entitlement.DLI_Product__r.SBQQ__ChargeType__c;  
      }
       if(quoteLineMigration.SBQQ__BillingType__c == null)
      {
        quoteLineMigration.SBQQ__BillingType__c = entitlement.DLI_Product__r.SBQQ__BillingType__c;    
      }
       if(quoteLineMigration.SBQQ__DefaultSubscriptionTerm__c == null)
      {
        quoteLineMigration.SBQQ__DefaultSubscriptionTerm__c = entitlement.DLI_Product__r.SBQQ__SubscriptionTerm__c;  
      }
      quoteLineMigration.Price_Book__c = entitlement.Quote__r.SBQQ__PriceBook__c;
      quoteLineMigration.Support_Level__c = entitlement.Support_Level__c;
      quoteLineMigration.CurrencyIsoCode = entitlement.Quote__r.CurrencyIsoCode;
      //quoteLineMigration.SBQQ__SubscriptionPricing__c = 'Fixed Price';
      quoteLineMigration.SBQQ__PricebookEntryId__c = productPricbookEntryMap.get(quoteLineMigration.SBQQ__Product__c + '-' + quoteLineMigration.Price_Book__c + '-' + quoteLineMigration.CurrencyIsoCode);
      system.debug('quoteLineMigration.SBQQ__SegmentIndex__c--->'+quoteLineMigration.SBQQ__SegmentIndex__c);
      if (quoteLineMigration.SBQQ__SegmentIndex__c != null && entitlement.Include_in_Select_Bundle__c == false) {
          string key = quoteLineMigration.CurrencyIsoCode+quoteLineMigration.SBQQ__Product__c;
          system.debug('key 2--->'+key);
          system.debug('dimentionMap.get(key)--->'+dimentionMap.get(key));
          if(entitlement.DLI_Product__r.SBQQ__ChargeType__c!= 'One-Time')
          {
          quoteLineMigration.SBQQ__Dimension__c = dimentionMap.get(key);
          }
          if(entitlement.Start_Date__c!=null && entitlement.End_Date__c!=null)
          {
          quoteLineMigration.SBQQ__SegmentKey__c = quoteLineMigration.SBQQ__Product__c + '|' + string.valueof(entitlement.Product_Instance__c);
          }
      }
      
      return quoteLineMigration;      
  }
  
  
  global static void insertQuoteLinesAndEntitlement(List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsert,List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd,Map<String,SBQQ__QuoteLine__c> mapOfContractToQuoteLineCreate,Product2 bundleProdId)
  {
      List<OP4I_Entitlement_View__c> entitlementListToUpd = new List<OP4I_Entitlement_View__c>();
      set<id> setOfQLEIds = new set<id>();
      List<SBQQ__QuoteLine__c> lstOfQuoteLines = new List<SBQQ__QuoteLine__c>();
      Map<string,string> mapOfDateToQLE = new Map<string,string>();
      Map<String,String> mapOfQliTOProduct = new Map<String,String>();
      Database.SaveResult[] quoteLineInsertResult = Database.insert(lstOfQuoteLinesToInsert, false); 
      //HandleCustomException.logDatabaseErrorsForEntitlements(quoteLineInsertResult,mapOfContractToQuoteLineCreate);
      map<string,string> resultMap = HandleCustomException.logMigrationDatabaseError(
          quoteLineInsertResult,
          mapOfContractToQuoteLineCreate,
          'SBQQ__Product__c,SBQQ__StartDate__c,SBQQ__EndDate__c',
          lstOfQuoteLinesToInsert
      );
      
       for (Database.SaveResult sr : quoteLineInsertResult){
          if(sr.isSuccess()){
                // Operation was successful, so get the ID of the record that was processed
                System.debug('Record Create/Update was Successful' + sr.getId());
                setOfQLEIds.add(sr.getId());
          }
       }
       
       if(setOfQLEIds!=null)
       {
          lstOfQuoteLines = [Select Id,SBQQ__Product__c,SBQQ__StartDate__c,SBQQ__EndDate__c FROM SBQQ__QuoteLine__c WHERE ID IN: setOfQLEIds];
          for(SBQQ__QuoteLine__c qleObj : lstOfQuoteLines)
          {
            mapOfQliTOProduct.put(qleObj.SBQQ__Product__c , qleObj.id);
            string key = qleObj.SBQQ__Product__c + string.valueOf(qleObj.SBQQ__StartDate__c) + string.valueOf(qleObj.SBQQ__EndDate__c);
            mapOfDateToQLE.put(key,qleObj.id);
          }               
       }
       
      string keyFields = 'DLI_Product__c,Start_Date__c,End_Date__c';
      for(OP4I_Entitlement_View__c entitlmnt : lstOfEntitlementRecordsUpd) {
          string keyQLE = entitlmnt.DLI_Product__c + string.valueOf(entitlmnt.Start_Date__c) + string.valueOf(entitlmnt.End_Date__c);
          if(entitlmnt.DLI_Product__c != entitlmnt.DLIP_Product__c && entitlmnt.Include_in_Select_Bundle__c == false){
              entitlmnt.Parent_Quote_Line__c = mapOfDateToQLE.get(keyQLE);
              
          } else if(entitlmnt.Include_in_Select_Bundle__c == true) {
              entitlmnt.Parent_Quote_Line__c = mapOfQliTOProduct.get(bundleProdId.Id);    
          }

          string key = HandleCustomException.getKey(keyFields, entitlmnt);
          if (resultMap.containsKey(key)) {
              entitlmnt.Error_Log__c = resultMap.get(key);
              entitlmnt.Processing_Status__c = 'Parent Quote Line Creation failed';
              entitlmnt.Associated_OSA__r.Processing_Status__c = 'Parent Quote Line Creation failed';
          }
          
          entitlementListToUpd.add(entitlmnt);
      }
      system.debug('@@Entitlmenet Parent Quote line' +quoteLineInsertResult[0].getId());
      system.debug('@@Entitlmenet List' +entitlementListToUpd);
      Database.SaveResult[] entitlementListOpp = Database.update(entitlementListToUpd, false);
      HandleCustomException.logDatabaseErrors(entitlementListOpp);
  }

  global static void setStartAndEndDateForNonBundle(List<OP4I_Entitlement_View__c> lstOfEntitlementNotBundle,Set<id> productIds,
                                                    set<id> priceBookIds,set<string> currencySet,Map<string,date> nonBundlemapOfProductStartDate,
                                                    Map<string,date> nonBundlemapOfProductEndDate){
  if(!lstOfEntitlementNotBundle.IsEmpty()){           
      for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementNotBundle){                 
          priceBookIds.add(entitlement.Quote__r.SBQQ__PriceBook__c);     
          currencySet.add(entitlement.Quote__r.CurrencyIsoCode);
          productIds.add(entitlement.DLI_Product__c); 
          productIds.add(entitlement.DLIP_Product__c);
          if(nonBundlemapOfProductStartDate!=null && nonBundlemapOfProductStartDate.containskey(entitlement.DLI_Product__c))
          {   
            if(nonBundlemapOfProductStartDate.get(entitlement.DLI_Product__c) > entitlement.Start_Date__c)
            {
              nonBundlemapOfProductStartDate.put(entitlement.DLI_Product__c , entitlement.Start_Date__c);
            }
            else
            {
              system.debug('Start date is greater');   
            }
          }
          else
          {
            nonBundlemapOfProductStartDate.put(entitlement.DLI_Product__c , entitlement.Start_Date__c);    
          }
      
          if(nonBundlemapOfProductEndDate!=null && nonBundlemapOfProductEndDate.containskey(entitlement.DLI_Product__c))
          {   
            if(nonBundlemapOfProductEndDate.get(entitlement.DLI_Product__c) < entitlement.End_Date__c)
            {
              nonBundlemapOfProductEndDate.put(entitlement.DLI_Product__c , entitlement.End_Date__c); 
            }
            else
            {
              system.debug('End date is Smaller');     
            }
          }
          else
          {
             nonBundlemapOfProductEndDate.put(entitlement.DLI_Product__c , entitlement.End_Date__c);
          }                   
      }
      system.debug('BunDleStartDate' +nonBundlemapOfProductStartDate);
      system.debug('BunDleEndDate' +nonBundlemapOfProductEndDate);
  }   
} 

global static void setStartAndEndDateForBundle(List<OP4I_Entitlement_View__c> lstOfEntitlementBundle,Set<id> productIds,
                                               set<id> priceBookIds,set<string> currencySet,Map<string,date> bundlemapOfProductStartDate,
                                               Map<string,date> bundlemapOfProductEndDate){
  if(!lstOfEntitlementBundle.IsEmpty()){           
      for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementBundle){                 
          priceBookIds.add(entitlement.Quote__r.SBQQ__PriceBook__c);     
          currencySet.add(entitlement.Quote__r.CurrencyIsoCode);
          productIds.add(entitlement.DLI_Product__c); 
          productIds.add(entitlement.DLIP_Product__c);
          if(bundlemapOfProductStartDate.containskey(entitlement.DLI_Product__c))
          {   
            if(bundlemapOfProductStartDate.get(entitlement.DLI_Product__c) > entitlement.Start_Date__c)
            {
              bundlemapOfProductStartDate.put(entitlement.DLI_Product__c , entitlement.Start_Date__c);
            }
            else
            {
              system.debug('Start date is greater');   
            }
          }
          else
          {
            bundlemapOfProductStartDate.put(entitlement.DLI_Product__c , entitlement.Start_Date__c);    
          }
      
          if(bundlemapOfProductEndDate.containskey(entitlement.DLI_Product__c))
          {   
            if(bundlemapOfProductEndDate.get(entitlement.DLI_Product__c) < entitlement.End_Date__c)
            {
              bundlemapOfProductEndDate.put(entitlement.DLI_Product__c , entitlement.End_Date__c); 
            }
            else
            {
              system.debug('end date is smaller');    
            }
          }
          else
          {
             bundlemapOfProductEndDate.put(entitlement.DLI_Product__c , entitlement.End_Date__c);
          }                   
      }
  }   
}       
}