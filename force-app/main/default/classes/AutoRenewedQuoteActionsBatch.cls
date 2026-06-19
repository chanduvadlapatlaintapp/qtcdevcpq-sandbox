/**
* @description Batch class for triggering actions on autorenewed quote which are within 30 days for renewal and renewal status is Initiated
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public without sharing class AutoRenewedQuoteActionsBatch implements Database.Batchable<sObject>, Schedulable, Database.Stateful {

    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    public Set<Id> quotesOrdered;
    public Set<Id> quoteIdsToOrder;
    private String query;
    private Integer scopeSize;
    private Set<String> taxMessagesToConsider = new Set<String>{
        'UNABLE_TO_LOCK_ROW', 
        'CANNOT_EXECUTE_FLOW_TRIGGER'
    };

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Default Constructor
    **/
    public autoRenewedQuoteActionsBatch() {
        this.quotesOrdered = new Set<Id>();
        this.query = getDefaultQuery();
        this.scopeSize = 1;
        this.quoteIdsToOrder = new Set<Id>();

    }

    /**
    * @description parameterized Constructor
    * @param query
    * @param scopeSize
    **/
    public autoRenewedQuoteActionsBatch(String query, Integer scopeSize) {
        // Set the query and scope size
        this.quotesOrdered = new Set<Id>();
        this.query = query ?? getDefaultQuery();
        this.scopeSize = scopeSize ?? 1;
        this.quoteIdsToOrder = new Set<Id>();
    }

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description Method that can be used to override the query and scope size
    * @param query
    * @param scopeSize
    **/
    public void executeBatch(String query, Integer scopeSize) {
        AutoRenewedQuoteActionsBatch obj = new AutoRenewedQuoteActionsBatch(query, scopeSize);
        Database.executeBatch(obj, scopeSize);
    }

    /***********************************************************************************************
    *
    * Batch Methods
    *
    ***********************************************************************************************/
    /**
    * @description start method
    * @param bc
    * @return Database.QueryLocator
    */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query renewal letters that need to be processed
        String query = this.query;
        return Database.getQueryLocator(query);
    }

    /**
    * @description execute method
    * @param bc
    * @param renewalLetters
    **/
    public void execute(Database.BatchableContext bc, List<Proforma_Invoice__c> renewalLetters) {
        Nebula.Logger.info('AutoRenewedQuoteActionsBatch execute started with ' + renewalLetters.size() + ' renewal letters');
        
        BatchProcessingResult result = processRenewalLetters(renewalLetters);
        updateRecords(result);
        
        Nebula.Logger.info('AutoRenewedQuoteActionsBatch execute completed. Quotes to order: ' + quoteIdsToOrder.size());
        Nebula.Logger.saveLog();
    }

    /**
    * @description Processes renewal letters and returns the results
    * @param renewalLetters
    * @return BatchProcessingResult
    **/
    private BatchProcessingResult processRenewalLetters(List<Proforma_Invoice__c> renewalLetters) {
        BatchProcessingResult result = new BatchProcessingResult();
        
        for (Proforma_Invoice__c renLetter : renewalLetters) {
            processIndividualRenewalLetter(renLetter, result);
        }
        
        return result;
    }

    /**
    * @description Processes an individual renewal letter
    * @param renLetter
    * @param result
    **/
    private void processIndividualRenewalLetter(Proforma_Invoice__c renLetter, BatchProcessingResult result) {
        Nebula.Logger.info('Processing Renewal Letter: ' + renLetter.Id + ', Days Remaining: ' + renLetter.Days_remaining_for_Renewal__c + ', Status: ' + renLetter.Status__c + ', Activity Status: ' + renLetter.Activity_Status__c);
        
        SBQQ__Quote__c quote = new SBQQ__Quote__c(Id = renLetter.Renewal_Quote__c);
        
        updateTaxCalculationIfNeeded(renLetter, quote);
        updateActivityStatusIfNeeded(renLetter);
        result.renLettersToUpdate.add(renLetter);
        
        if (shouldOrderQuote(renLetter)) {
            prepareQuoteForOrdering(renLetter, quote, result);
        }
    }

    /**
    * @description Updates tax calculation if needed
    * @param renLetter
    * @param quote
    **/
    private void updateTaxCalculationIfNeeded(Proforma_Invoice__c renLetter, SBQQ__Quote__c quote) {
        Nebula.Logger.info('Checking tax calculation - AvaTax Message: ' + renLetter.Renewal_Quote__r.AVA_SFCPQ__AvaTaxMessage__c);
        
        if (renLetter.Renewal_Quote__r.AVA_SFCPQ__AvaTaxMessage__c != QuoteConstants.AVA_TAX_MSG_UPTO_DATE && 
            taxMessagesToConsider.contains(renLetter.Renewal_Quote__r.AVA_SFCPQ__AvaTaxMessage__c)) {
            Nebula.Logger.info('Tax calculation needs update - setting AutomateTaxCalculation to true');
            quote.AVA_SFCPQ__Quote_AutomateTaxCalculation__c = true;
            quote.AVA_SFCPQ__AvaTaxMessage__c = QuoteConstants.AVA_TAX_MSG_REFRESH;
        }
    }

    /**
    * @description Updates activity status if needed
    * @param renLetter
    **/
    private void updateActivityStatusIfNeeded(Proforma_Invoice__c renLetter) {
        Decimal renewalBeforeDays = renLetter.Renewal_Quote__r.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Renewal_to_be_created_Before_Days__c;
        Nebula.Logger.info('Checking activity status update - Days remaining: ' + renLetter.Days_remaining_for_Renewal__c + ', Renewal before days: ' + renewalBeforeDays);
        
        if (renLetter.Days_remaining_for_Renewal__c <= renewalBeforeDays &&
            renLetter.Activity_Status__c != RenewalLetterConstants.ACTIVITY_STATUS_SEND_DOC_TO_CONTACT &&
            renLetter.Status__c == RenewalLetterConstants.STATUS_INITIATED) {
            
            Nebula.Logger.info('Updating Activity Status to Send Document to Contact');
            renLetter.Activity_Status__c = RenewalLetterConstants.ACTIVITY_STATUS_SEND_DOC_TO_CONTACT;
            renLetter.State__c = 'Activity Status updated to ' + renLetter.Activity_Status__c;
        }
    }

    /**
    * @description Checks if quote should be ordered
    * @param renLetter
    * @return Boolean
    **/
    private Boolean shouldOrderQuote(Proforma_Invoice__c renLetter) {
        Nebula.Logger.info('Checking quote ordering criteria - 30 day check');
        
        return renLetter.Days_remaining_for_Renewal__c <= 30 &&
               renLetter.Status__c == RenewalLetterConstants.STATUS_INITIATED &&
               renLetter.Renewal_Quote__r.SBQQ__Opportunity2__r.StageName != OpportunityConstants.STAGE_CLOSED_WON &&
               (renLetter.Activity_Status__c == RenewalLetterConstants.ACTIVITY_STATUS_SEND_DOC_TO_CONTACT || String.isBlank(renLetter.Activity_Status__c));
    }

    /**
    * @description Prepares quote for ordering
    * @param renLetter
    * @param quote
    * @param result
    **/
    private void prepareQuoteForOrdering(Proforma_Invoice__c renLetter, SBQQ__Quote__c quote, BatchProcessingResult result) {
        Date proposedCloseDate = (renLetter.Renewal_Quote__r.SBQQ__Opportunity2__r.Renewal_Start_Date__c != null)
            ? renLetter.Renewal_Quote__r.SBQQ__Opportunity2__r.Renewal_Start_Date__c.addDays(-30)
            : null;
        Nebula.Logger.info('30-day criteria met - preparing quote for ordering. Quote ID: ' + quote.Id + ', Proposed Close Date: ' + proposedCloseDate);
        
        quote.Quote_Stage__c = QuoteConstants.STATUS_CONTRACT_EXECUTED;
        quote.SBQQ__Primary__C = true;
        result.quotesToUpdate.add(quote);
        
        result.oppsToClose.add(new Opportunity(
            Id = renLetter.Renewal_Quote__r.SBQQ__Opportunity2__c,
            StageName = OpportunityConstants.STAGE_CLOSED_WON,
            CloseDate = proposedCloseDate
        ));
    }

    /**
    * @description Updates records in database
    * @param result
    **/
    private void updateRecords(BatchProcessingResult result) {
        updateRenewalLetters(result.renLettersToUpdate);
        updateQuotes(result.quotesToUpdate);
        updateOpportunities(result.oppsToClose);
        
        for (SBQQ__Quote__c quote : result.quotesToUpdate) {
            quoteIdsToOrder.add(quote.Id);
        }
    }

    /**
    * @description Updates renewal letters
    * @param renLettersToUpdate
    **/
    private void updateRenewalLetters(List<Proforma_Invoice__c> renLettersToUpdate) {
        Nebula.Logger.info('Updating ' + renLettersToUpdate.size() + ' renewal letters');
        try {
            update renLettersToUpdate;
            Nebula.Logger.info('Successfully updated ' + renLettersToUpdate.size() + ' renewal letters');
            
            // Update state tracking
            renLettersToUpdate = RenewalLetterUtil.updateRenewalLetterState(renLettersToUpdate, 'Renewal Letter state updated');
            update renLettersToUpdate;
            Nebula.Logger.info('Successfully updated renewal letter state tracking for ' + renLettersToUpdate.size() + ' records');
        } catch (Exception e) {
            Nebula.Logger.error('AutoRenewedQuoteActionsBatch Update Renewal Letters', renLettersToUpdate, e);
            Nebula.Logger.saveLog();
        }
    }

    /**
    * @description Updates quotes
    * @param quotesToUpdate
    **/
    private void updateQuotes(List<SBQQ__Quote__c> quotesToUpdate) {
        if (quotesToUpdate.isEmpty()) {
            return;
        }
        
        Nebula.Logger.info('Updating ' + quotesToUpdate.size() + ' quotes to Contract Executed status');
        try {
            update quotesToUpdate;
            Nebula.Logger.info('Successfully updated ' + quotesToUpdate.size() + ' quotes to Contract Executed status');
        } catch (Exception e) {
            Nebula.Logger.error('AutoRenewedQuoteActionsBatch Update Quotes', quotesToUpdate, e);
            Nebula.Logger.saveLog();
        }
    }

    /**
    * @description Updates opportunities
    * @param oppsToClose
    **/
    private void updateOpportunities(List<Opportunity> oppsToClose) {
        if (oppsToClose.isEmpty()) {
            return;
        }
        
        Nebula.Logger.info('Closing ' + oppsToClose.size() + ' opportunities');
        try {
            update oppsToClose;
            Nebula.Logger.info('Successfully closed ' + oppsToClose.size() + ' opportunities');
        } catch (Exception e) {
            Nebula.Logger.error('AutoRenewedQuoteActionsBatch Close Opps', oppsToClose, e);
        }
    }

    /**
    * @description Inner class to hold batch processing results
    **/
    private class BatchProcessingResult {
        public List<Opportunity> oppsToClose = new List<Opportunity>();
        public List<Proforma_Invoice__c> renLettersToUpdate = new List<Proforma_Invoice__c>();
        public List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c>();
    }

    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {
        Nebula.Logger.info('AutoRenewedQuoteActionsBatch finish method started');
        
        if(quoteIdsToOrder.size() > 0) {
            Nebula.Logger.info('Executing OrderQuoteBatch for ' + quoteIdsToOrder.size() + ' quotes: ' + quoteIdsToOrder);
            OrderQuoteBatch obj = new OrderQuoteBatch(quoteIdsToOrder);
            Database.executeBatch(obj, 1);
        } else {
            Nebula.Logger.info('No quotes to order - OrderQuoteBatch will not be executed');
        }
        
        Nebula.Logger.saveLog();
    }

    /***********************************************************************************************
    *
    * Schedulable Methods
    *
    ***********************************************************************************************/
    /**
    * @description execute method
    * @param sc
    **/
    public void execute(SchedulableContext sc) {
        // Execute the batch job
        executeBatch(this.query, this.scopeSize);
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /**
    * @description set the default query
    * @return String
    **/
    private String getDefaultQuery() {
        
        // Set the default query based on the business logic
        String defaultQuery = 'SELECT Id, Activity_Status__c, Days_Remaining_for_Renewal__c , Renewal_Quote__r.AVA_SFCPQ__AvaTaxMessage__c, ' + 
                                    'Renewal_Quote__r.AVA_SFCPQ__Tax_Calculation_Status__c, Status__c, Renewal_Quote__r.SBQQ__Opportunity2__r.Quote_Start_Date__c, ' +
                                    'Renewal_Quote__r.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Renewal_to_be_created_Before_Days__c, ' +
            						'Renewal_Quote__r.SBQQ__Opportunity2__r.IsClosed, Renewal_Quote__r.SBQQ__Opportunity2__r.StageName, Renewal_Quote__r.SBQQ__Opportunity2__r.Renewal_Start_Date__c ' +
                                'FROM Proforma_Invoice__c ' +
                                'WHERE Days_remaining_for_Renewal__c <= 90 AND Status__c = \''+RenewalLetterConstants.STATUS_INITIATED+ '\' ' +
                                'AND Renewal_Quote__r.SBQQ__Primary__c = TRUE ' +
                                'AND Renewal_Quote__r.SBQQ__Opportunity2__r.IsClosed = FALSE ' +
                                'AND Renewal_Quote__r.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Status != \'' + ContractConstants.STATUS_CANCELLED_LAPSED + '\' ' +
                                'AND Renewal_Quote__r.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Status != \'' + ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT + '\' ' +
                                'AND (Renewal_Quote__r.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Consolidated_Quote__c = null ' +
                                'OR Renewal_Quote__r.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Consolidated_Quote__r.SBQQ__Opportunity2__r.StageName != \'' + OpportunityConstants.STAGE_CLOSED_WON + '\')';

        return defaultQuery;
    }

}