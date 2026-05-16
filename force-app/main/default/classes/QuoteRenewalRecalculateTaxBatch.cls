/**
* @description Batch class for Recalculating tax on Renewal Quotes.
* @author Suresh Somu
* @jira BIZ-65680
**/
public without sharing class QuoteRenewalRecalculateTaxBatch implements Database.Batchable<sObject>, Schedulable, Database.Stateful {

    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    private String query;
    private Integer scopeSize;

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Default Constructor
    **/
    public quoteRenewalRecalculateTaxBatch() {
        this.query = getDefaultQuery();
        this.scopeSize = 1;
    }

    /**
    * @description parameterized Constructor
    * @param query
    * @param scopeSize
    **/
    public quoteRenewalRecalculateTaxBatch(String query, Integer scopeSize) {
        // Set the query and scope size
        this.query = query ?? getDefaultQuery();
        this.scopeSize = scopeSize ?? 1;
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
        QuoteRenewalRecalculateTaxBatch obj = new QuoteRenewalRecalculateTaxBatch(query, scopeSize);
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
        // Query Quotes that need to be processed
        String query = this.query;
        return Database.getQueryLocator(query);
    }

    /**
    * @description execute method
    * @param bc
    * @param renewalQuotes
    **/
    public void execute(Database.BatchableContext bc, List<SBQQ__Quote__c> renewalQuotes) {
        List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c>();

        // Process each renewal Quote
        for (SBQQ__Quote__c renewalQuote : renewalQuotes) {
            SBQQ__Quote__c quote = new SBQQ__Quote__c(
                Id = renewalQuote.id,
                AVA_SFCPQ__Quote_AutomateTaxCalculation__c = true,
                AVA_SFCPQ__AvaTaxMessage__c = QuoteConstants.AVA_TAX_MSG_REFRESH
            );
            if(renewalQuote.SBQQ__StartDate__c != null && Date.today().daysBetween(renewalQuote.SBQQ__StartDate__c) <= renewalQuote.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Renewal_to_be_created_Before_Days__c){
                quotesToUpdate.add(quote);
            }                        
        }

        System.enqueueJob(new UpdateQuoteQueueable(quotesToUpdate));

    }
    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {   

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
        DateTime limitDate = System.today().addDays(90);
        String formattedDate = limitDate.format('yyyy-MM-dd');
        String defaultQuery = 'SELECT Id, Renewal_Quote_Type__c, SBQQ__Type__c, AVA_SFCPQ__AvaTaxMessage__c, ' + 
                                      'SBQQ__StartDate__c, AVA_SFCPQ__Quote_AutomateTaxCalculation__c, SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Renewal_to_be_created_Before_Days__c ' + 
                                      'FROM SBQQ__Quote__c ' +
                                      'WHERE SBQQ__Type__c = \''+QuoteConstants.TYPE_RENEWAL+'\'' + 
                                      ' AND OP4I_Auto_Number_Deal_ID__c != null' +
                                      ' AND Renewal_Quote_Type__c = \'' + QuoteConstants.RENEWAL_QUOTE_TYPE_AUTO_RENEWAL + '\'' +
                                      ' AND SBQQ__StartDate__c <= ' + formattedDate +
                                      ' AND SBQQ__Opportunity2__r.StageName != \''+ OpportunityConstants.STAGE_CLOSED_WON + '\'' +
                                      ' AND (Id NOT IN (SELECT Renewal_Quote__c FROM Proforma_Invoice__c))' +
                                      ' AND Id IN (SELECT SBQQ__Quote__c FROM SBQQ__QuoteLine__c)';
        return defaultQuery;
    }
    
}