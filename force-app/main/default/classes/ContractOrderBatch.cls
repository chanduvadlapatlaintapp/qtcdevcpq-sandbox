/**
* @description Batch class for contracting activated orders
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public without sharing class ContractOrderBatch implements Database.Batchable<sObject>, Schedulable, Database.Stateful {
    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    public Set<Order> ordersContractedSet;
    private Set<Id> orderIds;
    private String query;

    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Constructor
    * @param orderIds
    **/
    public contractOrderBatch(Set<Id> orderIds) {
        this.orderIds = orderIds;
        this.query = getDefaultQuery();
        this.ordersContractedSet = new Set<Order>();
    }

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/

    /**
    * @description Method that can be used to override the order ids
    * @param orderIds
    **/
    public void executeBatch(Set<Id> orderIds) {
        ContractOrderBatch obj = new ContractOrderBatch(orderIds);
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
    * @param ordersToContract
    **/
    public void execute(Database.BatchableContext bc, List<Order> ordersToContract) {
        List<Order> ordersContracted = new List<Order>();
        Set<Id> quoteIds = Pluck.ids(Order.SBQQ__Quote__c, ordersToContract);

        // track the current state on Renewal letter
        RenewalLetterSelector selector = new RenewalLetterSelector();
        List<Proforma_Invoice__c> renewalLetters = selector.getRenLetterByQuoteIds(quoteIds);
        renewalLetters = RenewalLetterUtil.updateRenewalLetterState(renewalLetters, 'Order Contracting Started');
        List<Database.SaveResult> results = Database.update(renewalLetters, false);
        ResultHandler.logErrors('ContractOrderBatch Renewal Letter State Tracking', renewalLetters, results);

        // contract order
        for (Order order : ordersToContract) {
            order.SBQQ__Contracted__c = true;
        }

        List<Database.SaveResult> orderResults = Database.update(ordersToContract, false);
        Set<Id> orderIdsNotContracted = ResultHandler.logErrors('ContractOrderBatch contract orders', ordersToContract, orderResults);
       
        List<Order> failedOrders = new List<Order>();
        for (Integer i = 0; i < orderResults.size(); i++) {
            if (!orderResults[i].isSuccess() && orderResults[i].getErrors()[0].getStatusCode() == StatusCode.UNABLE_TO_LOCK_ROW) {   
                failedOrders.add(ordersToContract[i]);
            }
        }
        
        if (!failedOrders.isEmpty()) {
            System.enqueueJob(new RetryDmlQueueable(failedOrders, 1, 'ContractOrderBatch'));
        }
        
        // Get orders successfully contracted
        ordersContracted = CollectionUtil.getRecordsNotInSet(ordersToContract, orderIdsNotContracted);

        for(Order order : ordersContracted) {
            ordersContractedSet.add(order);
        }

    }

    /**
    * @description finish method
    * @param bc
    **/
    public void finish(Database.BatchableContext bc) {

        // Abort the job scheduled by previous day's run

        CronTrigger jobRecord = BatchUtil.getCronTrigger('Contract Orders - ');
        if(jobRecord != null) {
            System.abortJob(jobRecord.Id);
        }

        // Verify if contracts are created and update renewal letters
        if(ordersContractedSet.size() > 0) {
            List<Order> ordersContractedList = new List<Order>(ordersContractedSet);
            System.enqueueJob(new ContractCreationTrackerQueueable(ordersContractedList), 10);
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
        executeBatch(this.orderIds);
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
        String orderIdSetString = String.join(this.orderIds, '\',\'');
        orderIdSetString = '(\'' + orderIdSetString + '\')';
        String defaultQuery = 'SELECT Id, SBQQ__Quote__c ' + 
                                'FROM Order ' +
                                'WHERE Id IN ' + orderIdSetString;
        return defaultQuery;
    }

}