/**
* @description Batch class for activating orders
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public without sharing class ActivateOrderBatch implements Database.Batchable<sObject>, Schedulable, Database.Stateful {
    /***********************************************************************************************
    *
    * Private props
    *
    ***********************************************************************************************/
    public Set<Id> orderIdsToContract;
    private Set<Id> quoteIdsToActivate;
    private String query;

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Constructor
    * @param quoteIdsToActivate
    **/
    public activateOrderBatch(Set<Id> quoteIdsToActivate) {
        this.quoteIdsToActivate = quoteIdsToActivate;
        this.query = getDefaultQuery();
        this.orderIdsToContract = new Set<Id>();

    }

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description Method that can be used to override the quote ids
    * @param quoteIdsToActivate
    **/
    public void executeBatch(Set<Id> quoteIdsToActivate) {
        ActivateOrderBatch obj = new ActivateOrderBatch(quoteIdsToActivate);
        Database.executeBatch(obj, 1);
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
    * @param ordersToActivate
    **/
    public void execute(Database.BatchableContext bc, List<Order> ordersToActivate) {
        for (Order order : ordersToActivate) {
            order.Status = OrderConstants.STATUS_ACTIVATED;
            order.Included_In_Batch__c = true;
        }

        // track the current state on renewal letters
        if(ordersToActivate.size() > 0) {
            List<Proforma_Invoice__c> renewalLetters = new RenewalLetterSelector().getRenLetterByQuoteIds(this.quoteIdsToActivate);
            renewalLetters = RenewalLetterUtil.updateRenewalLetterState(renewalLetters, 'Order Activation Started');
            List<Database.SaveResult> results = Database.update(renewalLetters, false);
            ResultHandler.logErrors('ActivateOrderQueueable Renewal Letter State Tracking', renewalLetters, results);
        }
        List<Database.SaveResult> orderResults = Database.update(ordersToActivate, false);
        Set<Id> failedOrderIds = ResultHandler.logErrors('ActivateOrderQueueable execute', ordersToActivate, orderResults);

        // Get orders which did not fail activation
        for(Id orderId : CollectionUtil.getIdsNotInSet(ordersToActivate, failedOrderIds)) {
            orderIdsToContract.add(orderId);
        }

    }

    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {
        // Abort the job scheduled by previous day's run
        CronTrigger jobRecord = BatchUtil.getCronTrigger('Activate Orders - ');
        if(jobRecord != null) {
            System.abortJob(jobRecord.Id);
        }

        // Contract orders after 10 mins
        if(orderIdsToContract.size() > 0) {
            String nextFireTime = BatchUtil.getNextFireTime(0, 10, 0);
            System.schedule('Contract Orders - ' + System.now().format(), nextFireTime, new ContractOrderBatch(orderIdsToContract));
        }
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
        executeBatch(this.quoteIdsToActivate);
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
        String quoteIdSetString = String.join(this.quoteIdsToActivate, '\',\'');
        quoteIdSetString = '(\'' + quoteIdSetString + '\')';
        String defaultQuery = 'SELECT Id, SBQQ__Quote__c, OpportunityId ' + 
                                'FROM Order ' +
                                'WHERE SBQQ__Quote__c IN ' + quoteIdSetString;
        return defaultQuery;
    }
}