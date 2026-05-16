/**
* @description Queueable class to update the Quotes
**/
public class UpdateQuoteQueueable implements Queueable {
    private List<SBQQ__Quote__c> quotes;

    /**
    * @description constructor which has the quotes to be updated as param
    * @param quotes
    **/
    public updateQuoteQueueable(List<SBQQ__Quote__c> quotes) {
        this.quotes = quotes;
    }

    /**
    * @description queueable execute method
    * @param context
    **/
    public void execute(QueueableContext context) {
        List<Database.SaveResult> updateQuoteResults = Database.update(quotes, false);
        ResultHandler.logErrors('QuoteRenewalRecalculateTaxBatch Update Quotes', quotes, updateQuoteResults);
    }
}