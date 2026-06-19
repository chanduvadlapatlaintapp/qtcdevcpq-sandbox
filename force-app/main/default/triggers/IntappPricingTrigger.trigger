trigger IntappPricingTrigger on Intapp_Pricing__c (After insert, After Update) {
    {
        List<Intapp_Pricing__c> lstOfIntappPrice = new List<Intapp_Pricing__c>();
        if(trigger.isAfter)
        {
            if(trigger.IsInsert)
            {
                IntappPricingHandler.intappPriceAfterInsert(trigger.new);
            }
            if(trigger.isUpdate)
            {
                IntappPricingHandler.intappPriceAfterUpdate(trigger.new,Trigger.oldMap); 
            }
        }
    }
}