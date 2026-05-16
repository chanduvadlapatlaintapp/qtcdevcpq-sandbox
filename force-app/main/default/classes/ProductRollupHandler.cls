public class ProductRollupHandler {
    public Static void productrollupAfterInsert(list<Product_Rollup__c> lstOfProductRollups){
        if(!lstOfProductRollups.isEmpty() && lstOfProductRollups.size()>0){
            IntegrationUtility.publishEligibleSobjectRecords(lstOfProductRollups,null,'Product_Rollup__c');
        }        
    }
    
    public Static void productrollupAfterUpdate(list<Product_Rollup__c> lstOfProductRollups,Map<Id,Product_Rollup__c> oldMapProductRollup){      
        if(!lstOfProductRollups.isEmpty() && lstOfProductRollups.size()>0){
            IntegrationUtility.publishEligibleSobjectRecords(lstOfProductRollups,oldMapProductRollup,'Product_Rollup__c');
        } 
    }   
}