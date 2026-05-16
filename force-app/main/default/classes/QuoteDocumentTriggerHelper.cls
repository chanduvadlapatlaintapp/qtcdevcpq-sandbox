/**
* @description This class is a Helper class for QuoteDocumentTrigger.
**/
public class QuoteDocumentTriggerHelper {

    /***********************************************************************************************
    *
    * public methods
    *
    ***********************************************************************************************/
    
    /**
    * @description This method is to publish Approved Quote Documents.
    * @param lstQuoteDocuments A list of newly updated 'SBQQ__QuoteDocument__c' records.
    * @param mapOldQuoteDocuments A map of old values of the 'SBQQ__QuoteDocument__c' records.
    **/
    public static void publishApprovedOSA(List<SBQQ__QuoteDocument__c> lstQuoteDocuments, Map<Id, SBQQ__QuoteDocument__c> mapOldQuoteDocuments) {
        List<SBQQ__QuoteDocument__c> lstDocumentsToPublish = new List<SBQQ__QuoteDocument__c>();
        for(SBQQ__QuoteDocument__c document : lstQuoteDocuments) {
            if(document.Quote_ApprovalStatus__c != mapOldQuoteDocuments.get(document.Id).Quote_ApprovalStatus__c
               && document.Quote_ApprovalStatus__c == QuoteConstants.STATUS_APPROVED) {
            	lstDocumentsToPublish.add(document);
        	}
        }
        
        if(!lstDocumentsToPublish.IsEmpty()) {
            IntegrationUtility.publishEligibleSobjectRecords(lstDocumentsToPublish, mapOldQuoteDocuments, 'SBQQ__QuoteDocument__c');
        }
    }
    
    /**
     * @description Validates that quote document names do not exceed the maximum character limit
     * @param newQuoteDocuments List of new quote document records
     */
    public static void validateQuoteDocumentNameLength(List<SBQQ__QuoteDocument__c> newQuoteDocuments) {
        // Get the maximum character limit from custom label
        Integer maxLength = Integer.valueOf(Label.Quote_Document_Name_Max_Length);
        
        for (SBQQ__QuoteDocument__c quoteDoc : newQuoteDocuments) {
            // Check if document name field exists and has value
            if (String.isNotBlank(quoteDoc.Name)) {
                // Validate length does not exceed the maximum limit
                if (quoteDoc.Name.length() > maxLength) {
                    quoteDoc.Name.addError(
                        String.format(Label.Quote_Document_Name_Length_Error, 
                            new List<String>{
                                String.valueOf(maxLength), 
                                String.valueOf(quoteDoc.Name.length())
                            })
                    );
                }
            }
        }
    }
}