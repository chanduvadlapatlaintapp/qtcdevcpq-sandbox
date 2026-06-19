public class ProductTriggerHandler
{
    public Static void productAfterInsert(list<Product2> lstOfProduct) { 
        if(!lstOfProduct.isEmpty() && lstOfProduct.size()>0){
            IntegrationUtility.publishEligibleSobjectRecords(lstOfProduct,null,'Product2');
        }         
    }
    
    public Static void productAfterUpdate(list<Product2> lstOfProduct,Map<Id,Product2> oldMapProduct){      
        if(!lstOfProduct.isEmpty() && lstOfProduct.size()>0){
            IntegrationUtility.publishEligibleSobjectRecords(lstOfProduct,oldMapProduct,'Product2');
        } 
    }
}