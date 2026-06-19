public class OpportunityProductFlowClass {
	@InvocableMethod(label='SendOppLineItemPayloadOP4I' description='Method to send Opportunity LineItems Payload to OP4i')
    public static void createOP4IOliPayload(List<Id> recordId){
        system.debug('Payload class entered');
        set<Id> OliSetIds = new set<Id> (recordId);
        List<OpportunityLineItem> oppProductsToUpdate = new List<OpportunityLineItem>();
        Map<Id, String> oppErrors = new Map<Id, String>();
        List < OpportunityLineItem > finalOliListToPublish = new List < OpportunityLineItem > ();
        //Updated via BIZ-66418
    	String strQuery = OpportunityProductTriggerHelper.createQuery(OliSetIds);
        system.debug('query:..'+strQuery);
        system.debug('Ids:..'+OliSetIds);
        String strQueryUpd = strQuery.replace('setOfOli', 'OliSetIds');
        system.debug('query1:..'+strQueryUpd.substring(strQueryUpd.length()-200));
        finalOliListToPublish = Database.query(strQueryUpd);
        system.debug('Query Result:..'+finalOliListToPublish);
        
        // Update OpportunityLineItem fields and prepare for updates
        for (OpportunityLineItem oppProd : finalOliListToPublish) {
            if(oppProd.Opportunity_Prod_Updated__c == true){
                oppProd.Opportunity_Prod_Updated__c = false;
                oppProd.Last_Sync_to_OP4I_Time__c = System.now();
                oppProductsToUpdate.add(oppProd);
            }
        }
        // Attempt to update OpportunityLineItems
        if (!oppProductsToUpdate.isEmpty()) {
            Database.SaveResult[] srList = Database.update(oppProductsToUpdate, false);
        }
        
        IntegrationUtility.publishsObjectRecords(finalOliListToPublish, 'OpportunityLineItem');
        system.debug('Payload class completed');
    }
}