/**
 * @description Two-phase Queueable that cycles SBQQ__Primary__c false -> true on an
 *              amendment quote across SEPARATE transactions, forcing Salesforce CPQ to
 *              (re)generate the Opportunity Products + Amount for the primary quote.
 *
 *              CPQ runs that sync on a primary-flag transition. An agentic amendment
 *              quote is created already-primary (via ContractAmender), so a normal save
 *              never fires the transition, and a same-transaction false->true toggle is
 *              suppressed by CPQ's in-transaction recursion guard. The two updates
 *              therefore have to commit in two transactions: phase 1 sets the flag false
 *              and chains phase 2, which sets it back to true — reproducing the manual
 *              two-save UI fix that is known to sync the products.
 *
 *              Runs fully in the background (enqueued from the async calculator
 *              callback), so it adds nothing to the user's Save & Calculate wait.
 *              Enqueued from AgenticQTC_CPQAmendmentService.resyncOpportunityProducts.
 */
public class AgenticQTC_PrimaryToggleQueueable implements Queueable {

    private final Id quoteId;
    /** false = phase 1 (set primary false, then chain phase 2); true = phase 2 (set primary true). */
    private final Boolean setPrimary;

    public AgenticQTC_PrimaryToggleQueueable(Id quoteId, Boolean setPrimary) {
        this.quoteId = quoteId;
        this.setPrimary = setPrimary;
    }

    public void execute(QueueableContext context) {
        if (quoteId == null) {
            return;
        }
        try {
            update new SBQQ__Quote__c(Id = quoteId, SBQQ__Primary__c = setPrimary);
        } catch (Exception e) {
            Nebula.Logger.warn('AgenticQTC_PrimaryToggleQueueable: update failed (setPrimary=' + setPrimary + ') for ' + quoteId + ': ' + e.getMessage())
                .addTag('AgenticQTC_PrimaryToggleQueueable');
            Nebula.Logger.saveLog();
            return;
        }
        // After committing the "false" phase, chain the "true" phase so CPQ sees a
        // false -> true transition across two transactions and regenerates products.
        if (setPrimary == false && !Test.isRunningTest()) {
            try {
                System.enqueueJob(new AgenticQTC_PrimaryToggleQueueable(quoteId, true));
            } catch (Exception e) {
                Nebula.Logger.warn('AgenticQTC_PrimaryToggleQueueable: could not chain phase 2 for ' + quoteId + ': ' + e.getMessage())
                    .addTag('AgenticQTC_PrimaryToggleQueueable');
                Nebula.Logger.saveLog();
            }
        }
    }
}