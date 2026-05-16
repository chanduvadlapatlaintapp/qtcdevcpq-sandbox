global class QuoteLinesChildMigrationBatch implements Database.Batchable<sObject>{
  List<string> lstOfContractAssignment;
  global QuoteLinesChildMigrationBatch() {}

  global QuoteLinesChildMigrationBatch(List<string> lstOfContractNumbers){
      lstOfContractAssignment = lstOfContractNumbers ;
  }

  global Database.QueryLocator start(Database.BatchableContext bc){
      string endCondition;
      if (lstOfContractAssignment != null && !lstOfContractAssignment.isempty()) {
          for (string endDigit : lstOfContractAssignment) {
              endCondition = endCondition != null? (endCondition +  ' OR ContractNumber like \'%' + endDigit + '\'') :' ContractNumber like \'%' + endDigit + '\'';
          }
      } 
      String query = 'SELECT Id,Processing_Status__c FROM Contract WHERE Processing_Status__c = \'Parent Quote Line Created\'';
      query = endCondition != null? query + ' AND (' + endCondition + ')' : query;
      system.debug('Start Query' +query);   
      return Database.getQueryLocator(query);        
  }

global void execute(Database.BatchableContext bc, List<Contract> lstOfContracts){
    List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsertChild = new List<SBQQ__QuoteLine__c>();
    List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsertChildBundle = new List<SBQQ__QuoteLine__c>();
    List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsertChildUpd = new List<SBQQ__QuoteLine__c>();
    Map<String,SBQQ__QuoteLine__c> mapOfContractToQuoteLineCreate = new Map<String,SBQQ__QuoteLine__c>();
    Map<SBQQ__QuoteLine__c,String> mapOfQliToRequiredByToProduct = new Map<SBQQ__QuoteLine__c,String>();
    List<OP4I_Entitlement_View__c> lstOfEntitlementRecords = new List<OP4I_Entitlement_View__c>();
    List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsert = new List<SBQQ__QuoteLine__c>();
    List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd = new List<OP4I_Entitlement_View__c>(); 
    List<OP4I_Entitlement_View__c> lstOfEntitlementBundle = new List<OP4I_Entitlement_View__c>();
    List<OP4I_Entitlement_View__c> lstOfEntitlementNotBundle = new List<OP4I_Entitlement_View__c>();
    List<SBQQ__QuoteLine__c> lstOfQuoteLinesToClone = new List<SBQQ__QuoteLine__c>();
    Map<string,string> mapOfBundleQuoteLine = new Map<string,string>();
    Map<string,string> mapOfBundleEntitlementToQuote = new Map<string,string>();
    Map<string,string> mapOfDateToEntitlmnt = new Map<string,string>();
    Map<string,string> mapOfStartEndDateToQLi = new Map<string,string>();
    Map<String,String> mapOfDateToQleId = new Map<String,String>();
    List<Contract> lstOfContractsToUpdate = new List<Contract>();
    Map<string,Id> productPricbookEntryMap = new Map<String,Id>();
    Set<id> productIds = new set<id>();
    set<id> priceBookIds = new set<id>(); 
    set<string> currencySet = new set<string>();
    set<id> setOfQuoteIds = new set<id>();
    if(!lstOfContracts.IsEmpty()){
        lstOfEntitlementRecords = [SELECT Id,DLIP_Id__c,DLI_Id__c,Account__c,Quote__c,Quote__r.SBQQ__PriceBook__c,One_Time_Credit__c,Include_in_Select_Bundle__c,DLIP_Product__r.SBQQ__ChargeType__c,DLIP_Product__r.SBQQ__SubscriptionType__c,
                                Quantity__c,Quote__r.CurrencyIsoCode,Start_Date__c,End_Date__c,Associated_OSA__c,Parent_Quote_Line__c,Billing_Frequency__c,DLIP_Product__r.SBQQ__SubscriptionTerm__c,
                                Account__r.Name,Associated_OSA__r.ContractNumber,Opportunity__c,Processing_Status__c,DLIP_Product__r.SBQQ__SubscriptionPricing__c,Product_Instance__c,
                                DLI_Product__c,DLIP_Product__c,Sale_Price__c,Meter_Type__c,Segment_Index__c,Associated_OSA__r.Migration_Status__c,Support_Level__c,DLIP_Product__r.Product_Type__c,
                                Associated_OSA__r.Processing_Status__c,Additional_Discount__c,DLI_Product__r.SBQQ__ChargeType__c,DLIP_Product__r.SBQQ__BillingType__c,Software_License_Term__c 
                                FROM OP4I_Entitlement_View__c WHERE Associated_OSA__c IN: lstOfContracts];
      if(!lstOfEntitlementRecords.IsEmpty()){         
        for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords){ 
            priceBookIds.add(entitlement.Quote__r.SBQQ__PriceBook__c);     
            currencySet.add(entitlement.Quote__r.CurrencyIsoCode);
            productIds.add(entitlement.DLI_Product__c); 
            productIds.add(entitlement.DLIP_Product__c);
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
        Select id,CurrencyIsoCode, SBQQ__PriceBook__c, SBQQ__Product__c from SBQQ__Dimension__c 
        WHERE CurrencyIsoCode IN :currencySet AND SBQQ__Product__c IN :productIds
    ]) {
        string key = dimention.CurrencyIsoCode + dimention.SBQQ__Product__c;
        system.debug('key--->'+key);
        dimentionMap.put(key, dimention.Id);
    }
    
    if(!lstOfEntitlementRecords.IsEmpty())
    {
       string key = '';
       for(OP4I_Entitlement_View__c entitlement : lstOfEntitlementRecords){
        if(entitlement.DLIP_Product__c!=null && entitlement.DLI_Product__c != entitlement.DLIP_Product__c)
        {
          key = entitlement.DLIP_Product__c + string.valueOf(entitlement.Start_Date__c) + string.valueOf(entitlement.End_Date__c) + string.valueof(entitlement.Product_Instance__c);
          system.debug('@@key info' +key);   
          if(!mapOfDateToEntitlmnt.containskey(key))
          {
          system.debug('in loop');
          mapOfDateToEntitlmnt.put(key,entitlement.Id); 
            
            system.debug('@@inside loop');               
            SBQQ__QuoteLine__c qliObj = createChildQuoteLine(entitlement,
                                             productPricbookEntryMap,dimentionMap);
             system.debug('@@quote entitlemnt' +entitlement.Start_Date__c); 
             system.debug('@@quote entitlemnt' +entitlement.End_Date__c); 
             system.debug('@@quote info start date' +qliObj.SBQQ__StartDate__c); 
             system.debug('@@quote info end date' +qliObj.SBQQ__EndDate__c);                 
            if(entitlement.Parent_Quote_Line__c == null)
            {
              system.debug('@@in null loop'); 
              setOfQuoteIds.add(qliObj.SBQQ__Quote__c);
              mapOfQliToRequiredByToProduct.put(qliObj, entitlement.DLI_Product__c);
            }
            else
            {
              lstOfQuoteLinesToInsertChildBundle.add(qliObj);   
            }
            lstOfQuoteLinesToInsertChild.add(qliObj);
            entitlement.Processing_Status__c = 'Child Quote Line Created';
            entitlement.Associated_OSA__r.Processing_Status__c = 'Child Quote Line Created';
            lstOfEntitlementRecordsUpd.add(entitlement);
            if(!lstOfContractsToUpdate.contains(entitlement.Associated_OSA__r))
            {
            lstOfContractsToUpdate.add(entitlement.Associated_OSA__r);
            }
          }             
        }
        if(!lstOfQuoteLinesToInsertChild.IsEmpty())
        mapOfContractToQuoteLineCreate.put(entitlement.Associated_OSA__c,lstOfQuoteLinesToInsertChild[0]);
     }
    }

    if(setOfQuoteIds!=null && !setOfQuoteIds.isEmpty())
    {
      system.debug('@@quote not null');
      List<SBQQ__QuoteLine__c> lstOfQuoteLinesRequiredByNull = [Select Id,SBQQ__Quote__c,SBQQ__Product__c,SBQQ__StartDate__c,SBQQ__EndDate__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c IN: setOfQuoteIds];
      if(lstOfQuoteLinesRequiredByNull.size()>0)
      {
        for(SBQQ__QuoteLine__c qleReq : lstOfQuoteLinesRequiredByNull)
        {
          MapOfDateToQleId.put(qleReq.SBQQ__Product__c + String.ValueOf(qleReq.SBQQ__StartDate__c) + String.ValueOf(qleReq.SBQQ__EndDate__c) , qleReq.id);
        }               
      }
      if(!lstOfQuoteLinesToInsertChild.IsEmpty())
      {
        for(SBQQ__QuoteLine__c qle : lstOfQuoteLinesToInsertChild) 
        {
          if(qle.SBQQ__RequiredBy__c == null)
          {
            qle.SBQQ__RequiredBy__c = MapOfDateToQleId.get(MapOfQliToRequiredByToProduct.get(qle) + String.ValueOf(qle.SBQQ__StartDate__c) + String.ValueOf(qle.SBQQ__EndDate__c));         
          }
          lstOfQuoteLinesToInsertChildUpd.add(qle); 
        }               
      }
    }
    
    if(lstOfQuoteLinesToInsertChildUpd!=null && !lstOfQuoteLinesToInsertChildUpd.IsEmpty())
    { 
     system.debug('@@first loop');
     insertChildQuoteLinesAndEntitlement(lstOfQuoteLinesToInsertChildUpd,lstOfEntitlementRecordsUpd,mapOfContractToQuoteLineCreate);
    }
    if(lstOfQuoteLinesToInsertChildBundle!=null && !lstOfQuoteLinesToInsertChildBundle.IsEmpty())
    {
     system.debug('@@second loop');
     insertChildQuoteLinesAndEntitlement(lstOfQuoteLinesToInsertChildBundle,lstOfEntitlementRecordsUpd,mapOfContractToQuoteLineCreate);   
    }
        
    if(!lstOfContractsToUpdate.IsEmpty())
    {
      update lstOfContractsToUpdate;
    } 
}

global void finish(Database.BatchableContext bc){

}

global static SBQQ__QuoteLine__c createChildQuoteLine(OP4I_Entitlement_View__c entitlement ,
                                                 map<string,Id> productPricbookEntryMap,Map<string,Id> dimentionMap)
{
    SBQQ__QuoteLine__c quoteLineMigration = new SBQQ__QuoteLine__c();
    quoteLineMigration.SBQQ__Quote__c = entitlement.Quote__c;
    quoteLineMigration.Bypass_PriceRule__c = true;
    quoteLineMigration.SBQQ__Quantity__c = entitlement.Quantity__c;
    quoteLineMigration.SolutionQuantity__c = entitlement.Quantity__c;
    quoteLineMigration.Support_Level__c = entitlement.Support_Level__c;
    quoteLineMigration.SBQQ__ListPrice__c = entitlement.Sale_Price__c;
    quoteLineMigration.Original_List_Unit_Price__c = entitlement.Sale_Price__c;
    quoteLineMigration.Per_Integrations__c = entitlement.Meter_Type__c;
    quoteLineMigration.SBQQ__StartDate__c = entitlement.Start_Date__c;
    quoteLineMigration.SBQQ__EndDate__c = entitlement.End_Date__c;
    quoteLineMigration.SBQQ__Product__c = entitlement.DLIP_Product__c;
    quoteLineMigration.DLI_Id__c = entitlement.DLI_Id__c;
    quoteLineMigration.DLIP_Id__c = entitlement.DLIP_Id__c;
    quoteLineMigration.SBQQ__RequiredBy__c = entitlement.Parent_Quote_Line__c;
    quoteLineMigration.One_Time_Credit__c = entitlement.One_Time_Credit__c;
    quoteLineMigration.SBQQ__ProductSubscriptionType__c = entitlement.DLIP_Product__r.SBQQ__SubscriptionType__c;
    quoteLineMigration.SBQQ__SubscriptionType__c = entitlement.DLIP_Product__r.SBQQ__SubscriptionType__c;
    quoteLineMigration.Product_Type__c = entitlement.DLIP_Product__r.Product_Type__c;
    if (entitlement.Additional_Discount__c != null) {
        quoteLineMigration.SBQQ__AdditionalDiscountAmount__c = entitlement.Additional_Discount__c;
    }
    
    if(quoteLineMigration.SBQQ__SubscriptionPricing__c == null)
    {
      quoteLineMigration.SBQQ__SubscriptionPricing__c = entitlement.DLIP_Product__r.SBQQ__SubscriptionPricing__c;  
    }
    if(quoteLineMigration.SBQQ__ChargeType__c == null)
    {
      quoteLineMigration.SBQQ__ChargeType__c = entitlement.DLIP_Product__r.SBQQ__ChargeType__c;  
    }
     if(quoteLineMigration.SBQQ__BillingType__c == null)
    {
      quoteLineMigration.SBQQ__BillingType__c = entitlement.DLIP_Product__r.SBQQ__BillingType__c;    
    }
    quoteLineMigration.Price_Book__c = entitlement.Quote__r.SBQQ__PriceBook__c;
    quoteLineMigration.SBQQ__SegmentIndex__c = entitlement.Segment_Index__c;
    quoteLineMigration.SBQQ__SegmentLabel__c = 'Year  ' + entitlement.Segment_Index__c;
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
     if(quoteLineMigration.SBQQ__DefaultSubscriptionTerm__c == null)
    {
      quoteLineMigration.SBQQ__DefaultSubscriptionTerm__c = entitlement.DLIP_Product__r.SBQQ__SubscriptionTerm__c;  
    }
    quoteLineMigration.CurrencyIsoCode = entitlement.Quote__r.CurrencyIsoCode;
    //quoteLineMigration.SBQQ__SubscriptionPricing__c = 'Fixed Price';
    quoteLineMigration.SBQQ__PricebookEntryId__c = productPricbookEntryMap.get(quoteLineMigration.SBQQ__Product__c + '-' + quoteLineMigration.Price_Book__c + '-' + quoteLineMigration.CurrencyIsoCode);
    system.debug('quoteLineMigration.SBQQ__SegmentIndex__c--->'+quoteLineMigration.SBQQ__SegmentIndex__c);
    if (quoteLineMigration.SBQQ__SegmentIndex__c != null) {
        string key = quoteLineMigration.CurrencyIsoCode+quoteLineMigration.SBQQ__Product__c;
        system.debug('key 2--->'+key);
        system.debug('dimentionMap.get(key)--->'+dimentionMap.get(key));
        if(entitlement.DLIP_Product__r.SBQQ__ChargeType__c!= 'One-Time')
        {
        quoteLineMigration.SBQQ__Dimension__c = dimentionMap.get(key);
        }
        quoteLineMigration.SBQQ__SegmentKey__c = quoteLineMigration.SBQQ__Product__c + '|' + string.valueof(entitlement.Product_Instance__c);
    }
    
    return quoteLineMigration;  
}

global static void insertChildQuoteLinesAndEntitlement(
    List<SBQQ__QuoteLine__c> lstOfQuoteLinesToInsertChild,
    List<OP4I_Entitlement_View__c> lstOfEntitlementRecordsUpd,
    Map<String,SBQQ__QuoteLine__c> mapOfContractToQuoteLineCreate
){
    Database.SaveResult[] quoteLinesInsertResult = Database.insert(lstOfQuoteLinesToInsertChild, false); 
    //HandleCustomException.logDatabaseErrorsForEntitlements(quoteLinesToInsert,mapOfContractToQuoteLineCreate);
    map<string,string> resultMap = HandleCustomException.logMigrationDatabaseError(
        quoteLinesInsertResult,
        mapOfContractToQuoteLineCreate,
        'SBQQ__Product__c,SBQQ__StartDate__c,SBQQ__EndDate__c',
        lstOfQuoteLinesToInsertChild
    );

    string keyFields = 'DLIP_Product__c,Start_Date__c,End_Date__c';
    for (OP4I_Entitlement_View__c entitlementView : lstOfEntitlementRecordsUpd) {
        string key = HandleCustomException.getKey(keyFields, entitlementView);
        if (resultMap.containsKey(key)) {
            entitlementView.Error_Log__c = resultMap.get(key);
            entitlementView.Processing_Status__c = 'Child Quote Line Creation failed';
        }
    }
    
    Database.SaveResult[] entitlementListOpp = Database.update(lstOfEntitlementRecordsUpd, false);
    HandleCustomException.logDatabaseErrors(entitlementListOpp);
}
 
}