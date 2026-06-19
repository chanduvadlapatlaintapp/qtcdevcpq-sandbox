global class PriceDimensionBatch implements Database.Batchable<sObject> {
    global Database.QueryLocator start(Database.BatchableContext bc) {
       string prodQuery = 'SELECT Id from product2 where SBQQ__SubscriptionPricing__c = \'Fixed Price\' AND SBQQ__SubscriptionType__c != null';
       return Database.getQueryLocator(prodQuery);  
    }
    
global void execute(Database.BatchableContext bc, List<product2> lstOfProducts){
set<id> setOfProdIds = new set<id>();
List<SBQQ__Dimension__c> listOfPriceDimensionsToAdd = new List<SBQQ__Dimension__c>();
Map<String,SBQQ__Dimension__c> mapOfStringToDimension = new Map<String,SBQQ__Dimension__c>();
for(Product2 prodObj : lstOfProducts)
{
  setOfProdIds.add(prodObj.id);
}

List<SBQQ__Dimension__c> lstOfPriceDimensions = [Select id,CurrencyIsoCode,SBQQ__PriceBook__c,SBQQ__Product__c,Name,SBQQ__Type__c from SBQQ__Dimension__c WHERE SBQQ__Product__c IN: setOfProdIds AND SBQQ__PriceBook__c =: system.label.PricebookIDBatch];
for( SBQQ__Dimension__c dimensn : lstOfPriceDimensions)
{
  mapOfStringToDimension.put(dimensn.SBQQ__Product__c + dimensn.CurrencyIsoCode + dimensn.SBQQ__PriceBook__c , dimensn);    
}

for(Product2 prod : lstOfProducts)
{
  SBQQ__Dimension__c dimenUSD = new SBQQ__Dimension__c(); 
  dimenUSD.SBQQ__Product__c = prod.id;
  dimenUSD.Name = 'FY24 Annual USD';
  dimenUSD.SBQQ__Type__c = 'Year';
  dimenUSD.SBQQ__PriceBook__c = system.label.PricebookIDBatch;
  dimenUSD.CurrencyIsoCode = 'USD';
  if(!mapOfStringToDimension.keyset().contains(dimenUSD.SBQQ__Product__c + dimenUSD.CurrencyIsoCode + dimenUSD.SBQQ__PriceBook__c))
  {
    listOfPriceDimensionsToAdd.add(dimenUSD);  
  }

  SBQQ__Dimension__c dimenEUR = new SBQQ__Dimension__c(); 
  dimenEUR.SBQQ__Product__c = prod.id;
  dimenEUR.Name = 'FY24 Annual EUR';
  dimenEUR.SBQQ__Type__c = 'Year';
  dimenEUR.SBQQ__PriceBook__c = system.label.PricebookIDBatch;
  dimenEUR.CurrencyIsoCode = 'EUR';
  if(!mapOfStringToDimension.keyset().contains(dimenEUR.SBQQ__Product__c + dimenEUR.CurrencyIsoCode + dimenEUR.SBQQ__PriceBook__c))
  {
    listOfPriceDimensionsToAdd.add(dimenEUR);  
  }

  SBQQ__Dimension__c dimenGBP = new SBQQ__Dimension__c(); 
  dimenGBP.SBQQ__Product__c = prod.id;
  dimenGBP.Name = 'FY24 Annual GBP';
  dimenGBP.SBQQ__Type__c = 'Year';
  dimenGBP.SBQQ__PriceBook__c = system.label.PricebookIDBatch;
  dimenGBP.CurrencyIsoCode = 'GBP';
  if(!mapOfStringToDimension.keyset().contains(dimenGBP.SBQQ__Product__c + dimenGBP.CurrencyIsoCode + dimenGBP.SBQQ__PriceBook__c))
  {
    listOfPriceDimensionsToAdd.add(dimenGBP);  
  }

  SBQQ__Dimension__c dimenAUD = new SBQQ__Dimension__c();   
  dimenAUD.SBQQ__Product__c = prod.id;
  dimenAUD.Name = 'FY24 Annual AUD';
  dimenAUD.SBQQ__Type__c = 'Year';
  dimenAUD.SBQQ__PriceBook__c = system.label.PricebookIDBatch;
  dimenAUD.CurrencyIsoCode = 'AUD';
  if(!mapOfStringToDimension.keyset().contains(dimenAUD.SBQQ__Product__c + dimenAUD.CurrencyIsoCode + dimenAUD.SBQQ__PriceBook__c))
  {
    listOfPriceDimensionsToAdd.add(dimenAUD);  
  }  
  
  SBQQ__Dimension__c dimenCAD = new SBQQ__Dimension__c();   
  dimenCAD.SBQQ__Product__c = prod.id;
  dimenCAD.Name = 'FY24 Annual CAD';
  dimenCAD.SBQQ__Type__c = 'Year';
  dimenCAD.SBQQ__PriceBook__c = system.label.PricebookIDBatch;
  dimenCAD.CurrencyIsoCode = 'CAD';
  if(!mapOfStringToDimension.keyset().contains(dimenCAD.SBQQ__Product__c + dimenCAD.CurrencyIsoCode + dimenCAD.SBQQ__PriceBook__c))
  {
    listOfPriceDimensionsToAdd.add(dimenCAD);  
  } 
  
  SBQQ__Dimension__c dimenSGD = new SBQQ__Dimension__c();   
  dimenSGD.SBQQ__Product__c = prod.id;
  dimenSGD.Name = 'FY24 Annual SGD';
  dimenSGD.SBQQ__Type__c = 'Year';
  dimenSGD.SBQQ__PriceBook__c = system.label.PricebookIDBatch;
  dimenSGD.CurrencyIsoCode = 'SGD';
  if(!mapOfStringToDimension.keyset().contains(dimenSGD.SBQQ__Product__c + dimenSGD.CurrencyIsoCode + dimenSGD.SBQQ__PriceBook__c))
  {
    listOfPriceDimensionsToAdd.add(dimenSGD);  
  }  
  
  SBQQ__Dimension__c dimenNZD = new SBQQ__Dimension__c();   
  dimenNZD.SBQQ__Product__c = prod.id;
  dimenNZD.Name = 'FY24 Annual NZD';
  dimenNZD.SBQQ__Type__c = 'Year';
  dimenNZD.SBQQ__PriceBook__c = system.label.PricebookIDBatch;
  dimenNZD.CurrencyIsoCode = 'NZD';
  if(!mapOfStringToDimension.keyset().contains(dimenNZD.SBQQ__Product__c + dimenNZD.CurrencyIsoCode + dimenNZD.SBQQ__PriceBook__c))
  {
    listOfPriceDimensionsToAdd.add(dimenNZD);  
  }   
    
}

    if(listOfPriceDimensionsToAdd.size() > 0)
    {
    system.debug('@@snehal size' +listOfPriceDimensionsToAdd.size());
    insert listOfPriceDimensionsToAdd;
    }
}    
    global void finish(Database.BatchableContext bc){
        // execute any post-processing operations
    }    
}