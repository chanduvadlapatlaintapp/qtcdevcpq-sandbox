trigger ProductTrigger on Product2 (After insert, After Update)
{
    List<Product2> lstOfProducts = new List<Product2>();
    if(trigger.isAfter)
    {
        if(trigger.IsInsert)
        {
            ProductTriggerHandler.productAfterInsert(trigger.new);
        }
        
        if(trigger.isUpdate)
        {
            ProductTriggerHandler.productAfterUpdate(trigger.new,Trigger.oldMap); 
        }
    }
}