/********************************************************************************
*  Name             :  AgenticQTC_CPQController
*  Description      :  Generic LWC-facing controller that bridges to
*                      CPQAmendmentService. Accepts flat, LWC-serialisable
*                      String parameters, constructs the inner-class request
*                      objects that the service expects, and delegates all
*                      CPQ logic there.
*                      Required because Salesforce's @AuraEnabled framework
*                      does not populate inner-class fields when the request
*                      object is deserialized from an LWC imperative Apex call.
*  Change history   :
*  Date          Author        Description
*  29/04/26                    Created
********************************************************************************/
public without sharing class AgenticQTC_CPQController {

    /**
     * @description LWC entry point for creating an amendment quote from a
     *              contract, or applying updates to an existing quote.
     *              Provide ONE of contractId or quoteId.
     */
    @AuraEnabled
    public static Map<String, Object> applyQuoteLineUpdates(String contractId, String quoteId) {
        try {
            CPQAmendmentService.AmendmentRequest request = new CPQAmendmentService.AmendmentRequest();
            request.contractId  = String.isNotBlank(contractId) ? contractId : null;
            request.quoteId     = String.isNotBlank(quoteId)    ? quoteId    : null;
            request.lineUpdates = new List<CPQAmendmentService.LineFieldValues>();
            return CPQAmendmentService.applyQuoteLineUpdates(request);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('AgenticQTC_CPQController.applyQuoteLineUpdates failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_CPQController').addTag('Amendment');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }
}