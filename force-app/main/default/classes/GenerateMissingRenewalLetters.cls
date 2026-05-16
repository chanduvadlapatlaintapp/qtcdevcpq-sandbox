/**
 * @description Batch class to insert renewal letters for quotes with start dates within the next 90 days.
 * This class also updates quotes to trigger tax calculations if the renewal letter is not applicable.
 * Handles batch processing with error logging for failed DML operations.
 * 
 * @author Pooja Hemrajani
 * @jira BIZ-68060
 */

 public without sharing class GenerateMissingRenewalLetters implements Database.Batchable<sObject>, Schedulable  {
    
    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    public Set<Id> quotesForRL;
    private String query;
    private Integer scopeSize;
    private Date startDate = Date.today();
    private Date endDate = Date.today().addDays(90);

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Default Constructor
    **/
    public generateMissingRenewalLetters() {

        this.quotesForRL = new Set<Id>();
        this.query = getDefaultQuery();
        this.scopeSize = 1;
    }

    /**
    * @description parameterized Constructor
    * @param query
    * @param scopeSize
    **/
    public generateMissingRenewalLetters(String query, Integer scopeSize) {
        // Set the query and scope size

        this.quotesForRL = new Set<Id>();
        this.query = (query != null) ? query : getDefaultQuery();
        this.scopeSize = 1;
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
        GenerateMissingRenewalLetters obj = new GenerateMissingRenewalLetters(query, scopeSize);
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
    * @param quotesData
    **/
    public void execute(Database.BatchableContext bc, List<SBQQ__Quote__c> quotesData) {

        List<Proforma_Invoice__c> renewalLettersToInsert = new List<Proforma_Invoice__c>();
        List<SBQQ__Quote__c> quotesToUpdate = new List<SBQQ__Quote__c>();

        for(SBQQ__Quote__c quote: quotesData){
            if (QuoteConstants.AVA_TAX_MSG_UPTO_DATE.equals(quote.AVA_SFCPQ__AvaTaxMessage__c) && quote.SBQQ__StartDate__c != null) {
                // Create a new Renewal Letter
                renewalLettersToInsert.add(new Proforma_Invoice__c(
                    Renewal_Quote__c = quote.Id,
                    Renewal_Start_Date__c = quote.SBQQ__StartDate__c,
                    Status__c = RenewalLetterConstants.STATUS_INITIATED,
                    CurrencyISOCode = quote.CurrencyISOCode
                ));
            } else {
                // Update the quote to trigger tax calculation
                quote.AVA_SFCPQ__Quote_AutomateTaxCalculation__c = true;
                quotesToUpdate.add(quote);
            }
        }

        if (!renewalLettersToInsert.isEmpty()) {
            List<Database.SaveResult> renewalLettersToInsertResults = Database.insert(renewalLettersToInsert, false);
            ResultHandler.logErrors('GenerateMissingRenewalLetters Insert Renewal Letters', renewalLettersToInsert, renewalLettersToInsertResults);
        }
        
        if (!quotesToUpdate.isEmpty()) {
            System.enqueueJob(new UpdateQuoteQueueable(quotesToUpdate));
        }
    }

    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {
        
        System.debug('Batch process completed successfully.');
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
        Date startDate = Date.today();
        Date endDate = Date.today().addDays(90);
        
        String defaultQuery = 'SELECT Id, AVA_SFCPQ__AvaTaxMessage__c, SBQQ__StartDate__c, AVA_SFCPQ__Quote_AutomateTaxCalculation__c, ' +
                            'Renewal_Letter__c, Renewal_Quote_Type__c, Opportunity_Stage__c, CurrencyISOCode, ' +
                            'SBQQ__Primary__c, SBQQ__Ordered__c ' +
                            'FROM SBQQ__Quote__c ' +
                            'WHERE Renewal_Letter__c = NULL ' +
                            'AND SBQQ__StartDate__c >= :startDate ' +  // Bind variable
                            'AND SBQQ__StartDate__c <= :endDate ' +    // Bind variable
                            'AND Renewal_Quote_Type__c = \'Auto-Renewal\' ' +
                            'AND Opportunity_Stage__c != \'Closed Lost\' ' +
                            'AND SBQQ__Primary__c = TRUE ' +
                            'AND SBQQ__Ordered__c = FALSE ' +
                            'AND (SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Status = \'' + ContractConstants.STATUS_INFORCE + '\' ' +
                            '     OR SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Status = \'' + ContractConstants.STATUS_PARTIALLY_SUPERSEDED + '\') ' +
            				'AND SBQQ__Opportunity2__r.IsClosed = FALSE';
                            
        return defaultQuery;
    }
}