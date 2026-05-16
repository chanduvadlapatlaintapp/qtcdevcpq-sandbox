@isTest
public class PriceDimensionBatchTest {
    @isTest
    public static void testmethod1(){  
        
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account'
            ), 'AccountDefaults'
        );
        
        Item_Master_Product__c imp = new Item_Master_Product__c(Name = 'test12', Create_Revenue_Plans_On__c='Revenue Arrangement Creation',Income_Account__c='4200',Deferred_Revenue_Account__c = '2355',
                            Item_Revenue_Category__c = 'Intapp Cloud Renewal',Rev_Rec_Forecast_Rule__c='POB 2 - Cloud / SaaS',Revenue_Allocation_Group__c='Bundle_Item_Testing',TaxCode__c='SW053003',Revenue_Recognition_Rule__c='POB 2 - Cloud / SaaS');

        insert imp;
        
        Product2 prodObj = (Product2)TestFactory.createSObject(
            new Product2(
            	Name = 'Testproduct',
        		IsActive = true,
                ProductCode = '123462',
                SBQQ__SubscriptionPricing__c = 'Fixed Price',
                SBQQ__SubscriptionTerm__c = 12,
                SBQQ__SubscriptionType__c = 'Renewable',
                SBQQ__ChargeType__c = 'Recurring',
                SBQQ__BillingFrequency__c = 'Annual',
                SBQQ__BillingType__c = 'Arrears',
                Item_Master_Product__c = imp.Id
            ), 'ProductDefaults');

        
       prodObj.SBQQ__SubscriptionTerm__c = 13;
       update prodObj;
       
       System.assertEquals('Annual', prodObj.SBQQ__BillingFrequency__c); 
       Database.executebatch(new PriceDimensionBatch() , 2); 
   }
}