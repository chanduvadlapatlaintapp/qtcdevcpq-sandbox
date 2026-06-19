public class IntegrationHandler {
    public static void accountEventAfterUpdate(List<Account> newList, Map<Id,Account> oldMap){
        List<Account> listToPublish = new List<Account>(); 
        if(!newList.isEmpty()){
            for(Account acc : newList){
                Boolean isValid = acc.Name!= oldMap.get(acc.Id).name 
                    || acc.VAT_Number__c!=oldMap.get(acc.Id).VAT_Number__c 
                    || acc.Invoicing_Email__c!=oldMap.get(acc.Id).Invoicing_Email__c 
                    || acc.BillingCountry!=oldMap.get(acc.Id).BillingCountry 
                    || acc.billingStreet!=oldMap.get(acc.Id).billingStreet 
                    || acc.billingState!=oldMap.get(acc.Id).billingState
                    || acc.billingPostalCode!=oldMap.get(acc.Id).billingPostalCode 
                    || acc.shippingCountry!=oldMap.get(acc.Id).shippingCountry 
                    || acc.shippingStreet!=oldMap.get(acc.Id).shippingStreet 
                    || acc.shippingCity!=oldMap.get(acc.Id).shippingCity 
                    || acc.shippingState!=oldMap.get(acc.Id).shippingState 
                    || acc.shippingPostalCode!=oldMap.get(acc.Id).shippingPostalCode 
                    || acc.AVA_MAPPER__Business_Identification_Number__c!=oldMap.get(acc.Id).AVA_MAPPER__Business_Identification_Number__c;
                if(acc.Subsidiaries__c != null && acc.Subsidiary__c != null && isValid
                ){
                    listToPublish.add(acc);
                }
            }
            if(!listtoPublish.isEmpty()){
                IntegrationUtility.publishsObjectRecords(listToPublish,'Account');
            }
        }
    }
}