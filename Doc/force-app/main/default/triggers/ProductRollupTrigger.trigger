trigger ProductRollupTrigger on Product_Rollup__c (After insert, After Update) {
    {
        List<Product_Rollup__c> lstOfProductRollup = new List<Product_Rollup__c>();
        if(trigger.isAfter)
        {
            if(trigger.IsInsert)
            {
                ProductRollupHandler.productrollupAfterInsert(trigger.new);
            }
            if(trigger.isUpdate)
            {
                ProductRollupHandler.productrollupAfterUpdate(trigger.new,Trigger.oldMap); 
            }
        }
    }
}