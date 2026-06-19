public class IntappPricingHandler
{
    public Static void intappPriceAfterInsert(list<Intapp_Pricing__c> lstOfIntappPrices){
        if(!lstOfIntappPrices.isEmpty() && lstOfIntappPrices.size()>0){
            IntegrationUtility.publishEligibleSobjectRecords(lstOfIntappPrices,null,'Intapp_Pricing__c');
        }        
    }
    
    public Static void intappPriceAfterUpdate(list<Intapp_Pricing__c> lstOfIntappPrices,Map<Id,Intapp_Pricing__c> oldMapIntappPrice){      
        if(!lstOfIntappPrices.isEmpty() && lstOfIntappPrices.size()>0){
            IntegrationUtility.publishEligibleSobjectRecords(lstOfIntappPrices,oldMapIntappPrice,'Intapp_Pricing__c');
        }  
    }
}