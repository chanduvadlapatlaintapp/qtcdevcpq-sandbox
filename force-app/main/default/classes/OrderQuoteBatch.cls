/**
* @description Batch class for ordering quotes which are within 30 days for renewal and renewal status is Initiated
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public without sharing class OrderQuoteBatch implements Database.Batchable<sObject>, Database.Stateful {

    /***********************************************************************************************
    *
    * Private props
    *
    ***********************************************************************************************/
    private Set<Id> quoteIdsToOrder;
    private Set<Id> quoteIdsToActivate;
    private String query;

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Constructor
    * @param quoteIdsToOrder
    **/
    public orderQuoteBatch(Set<Id> quoteIdsToOrder) {
        this.quoteIdsToOrder = quoteIdsToOrder;
        this.quoteIdsToActivate = new Set<Id>();
        this.query = getDefaultQuery();
    }

    /**
    * @description Constructor
    * @param query
    **/
    public orderQuoteBatch(String query) {
        this.query = query;
        this.quoteIdsToActivate = new Set<Id>();
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
    * @param quotes
    **/
    public void execute(Database.BatchableContext bc, List<SBQQ__Quote__c> quotes) {
        // Track initial state
        List<Proforma_Invoice__c> renewalLetters = new RenewalLetterSelector().getRenLetterByQuoteIds(this.quoteIdsToOrder);
        renewalLetters = RenewalLetterUtil.updateRenewalLetterState(renewalLetters, 'Order Creation Started');
        List<Database.SaveResult> results = Database.update(renewalLetters, false);
        ResultHandler.logErrors('OrderQuoteBatch Renewal Letter State Tracking', renewalLetters, results);

        // order quotes
        for(SBQQ__Quote__c quote : quotes) { 
            quote.SBQQ__Ordered__c = true;
        }
        List<Database.SaveResult> orderQuoteResults = Database.update(quotes, false);
        Set<Id> quotesNotOrdered = ResultHandler.logErrors('OrderQuoteBatch Order Quotes', quotes, orderQuoteResults);
        Set<Id> quotesOrdered = CollectionUtil.getIdsNotInSet(quotes, quotesNotOrdered);
        for(Id quoteId : quotesOrdered) {
            quoteIdsToActivate.add(quoteId);
        }
    }

    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {
        
        // Activate orders after 10 mins
        if(quoteIdsToActivate.size() > 0) {
            String nextFireTime = BatchUtil.getNextFireTime(0, 10, 0);
            System.schedule('Activate Orders - ' + System.now().format(), nextFireTime, new ActivateOrderBatch(quoteIdsToActivate));
        }
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
        String quoteIdSetString = String.join(this.quoteIdsToOrder, '\',\'');
        quoteIdSetString = '(\'' + quoteIdSetString + '\')';
        String defaultQuery = 'SELECT Id ' +
                                'FROM SBQQ__Quote__c ' +
                                'WHERE Id IN ' + quoteIdSetString +
                                ' AND SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Status != \'' + ContractConstants.STATUS_CANCELLED_LAPSED + '\' ' +
                                'AND SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Status != \'' + ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT + '\' ' +
                                'AND (SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Consolidated_Quote__c = null ' +
                                'OR SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Consolidated_Quote__r.SBQQ__Opportunity2__r.StageName != \'' + OpportunityConstants.STAGE_CLOSED_WON + '\')';
        return defaultQuery;
    }

}