/**
* @description Queueable class for tracking contract creation
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public without sharing class ContractCreationTrackerQueueable implements Queueable {
    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    public final static Set<String> CONTRACT_FIELDS_TO_QUERY = new Set<String>{
        'SBQQ__Order__c'
    };
    private List<Order> orders;


    /***********************************************************************************************
    *
    * Constructors
    *
    ***********************************************************************************************/
    /**
    * @description Constructor
    * @param orders
    **/
    public contractCreationTrackerQueueable(List<Order> orders) {
        this.orders = orders;
    }

    /***********************************************************************************************
    *
    * Queueable Methods
    *
    ***********************************************************************************************/
    /**
    * @description execute method
    * @param context 
    */
    public void execute(QueueableContext context) {
        Set<Id> orderIds = Pluck.ids(this.orders);
        List<Contract> contracts = new ContractSelector(CONTRACT_FIELDS_TO_QUERY).getContractsByOrderIds(orderIds);
        Set<Id> orderIdsWithContract =  Pluck.ids(Contract.SBQQ__Order__c, contracts);
        // Get Orders without contract
        List<Order> ordersWithoutContract = (List<Order>)CollectionUtil.getRecordsNotInSet(this.orders, orderIdsWithContract);

        Set<Id> orderIdsWithoutContract = Pluck.ids(ordersWithoutContract);
        // Get Orders with contract
        List<Order> ordersWithContract = (List<Order>)CollectionUtil.getRecordsNotInSet(this.orders, orderIdsWithoutContract);

        RenewalLetterSelector selector = new RenewalLetterSelector();
        // Update Activity Status on Renewal Letter to Order Activated
        Set<Id> renewalQuoteIds = Pluck.ids(Order.SBQQ__Quote__c, ordersWithContract);
        List<Proforma_Invoice__c> renewalLettersWithContract = new List<Proforma_Invoice__c>();
        for(Proforma_Invoice__c renLetter : selector.getRenLetterByQuoteIds(renewalQuoteIds)) {
            renLetter.Activity_Status__c = RenewalLetterConstants.ACTIVITY_STATUS_ORDER_ACTIVATED;
            renewalLettersWithContract.add(renLetter);
        }

        List<Database.SaveResult> finalResults = Database.update(renewalLettersWithContract, false);
        ResultHandler.logErrors('ContractCreationTrackerQueueable update renewal letters', renewalLettersWithContract, finalResults);

        // If there are no orders without contract, exit
        if(ordersWithoutContract.size() == 0) {
            return;
        }

        // track the current state on Renewal letter of orders without contract contract
        Set<Id> quoteIdsWithoutContract = Pluck.ids(Order.SBQQ__Quote__c, ordersWithoutContract);
        List<Proforma_Invoice__c> renewalLettersWithoutContract = selector.getRenLetterByQuoteIds(quoteIdsWithoutContract);
        renewalLettersWithoutContract = RenewalLetterUtil.updateRenewalLetterState(renewalLettersWithoutContract, 'Order Contracting Failed');
        List<Database.SaveResult> results = Database.update(renewalLettersWithoutContract, false);
        ResultHandler.logErrors('ContractCreationTrackerQueueable Renewal Letter State Tracking', renewalLettersWithoutContract, results);

    }

}