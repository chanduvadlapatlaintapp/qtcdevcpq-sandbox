/**
 * @description : BIZ-74649 - Invocable class triggered from Quote After Insert Flow. 
 *                Sends Quotes (with valid Ids) to OP4i and flips the Pause Quote Payload checkbox.
 * @author      : Manisha Sharma
 * @createdDate : Oct-10-2025
 */
public class QuotePayloadFlowClass {

    @InvocableMethod(label='SendQuotePayloadOP4I' description='Method to send Quote Payload to OP4i')
    public static void sendQuotePayload(List<Id> quoteIds){
        Set<Id> quoteIdSet = new Set<Id>(quoteIds);
        List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c>();
        List<SBQQ__Quote__c> finalQuotesToPublish = new List<SBQQ__Quote__c>();

        try {
            finalQuotesToPublish = [
                SELECT Id, Pause_Quote_Payload__c, SBQQ__Type__c, SBQQ__Opportunity2__c
                FROM SBQQ__Quote__c
                WHERE Id IN :quoteIdSet
            ];

            for (SBQQ__Quote__c q : finalQuotesToPublish) {
                if (q.Pause_Quote_Payload__c == true) {
                    q.Pause_Quote_Payload__c = false;
                    quotesToUpdate.add(q);
                }
            }

            if (!quotesToUpdate.isEmpty()) {
                update quotesToUpdate;
            }

            IntegrationUtility.publishEligibleSobjectRecords(finalQuotesToPublish, null, 'SBQQ__Quote__c');

        } catch (Exception e) {
            Nebula.Logger.error('QuotePayloadFlowClass.sendQuotePayload', finalQuotesToPublish, e);
        } finally {
            Nebula.Logger.saveLog();
        }
    }
}