/**
 * @description Service class for Contract Subscription validation logic
 * @author Sahal Mohamed
 * @jira BIZ-69730
 */
public with sharing class ContractSubscriptionService {
    
    /**
     * @description Get all recurring subscriptions for given contracts
     * @param contractIds Set of contract IDs
     * @return Map of Contract ID to List of Subscriptions
     */
    public static Map<Id, List<SBQQ__Subscription__c>> getRecurringSubscriptions(Set<Id> contractIds) {
        Map<Id, List<SBQQ__Subscription__c>> contractToSubscriptions = new Map<Id, List<SBQQ__Subscription__c>>();
        
        if (contractIds == null || contractIds.isEmpty()) {
            return contractToSubscriptions;
        }
        
        // Initialize map with empty lists
        for (Id contractId : contractIds) {
            contractToSubscriptions.put(contractId, new List<SBQQ__Subscription__c>());
        }
        
        // Query recurring subscriptions (exclude One-time and Evergreen)
        // Note: Subscription object uses 'One-Time' (capital T), different from Product 'One-time'
        for (SBQQ__Subscription__c sub : [
            SELECT Id, SBQQ__Contract__c, SBQQ__TerminatedDate__c, SBQQ__SubscriptionType__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__c IN :contractIds
              AND SBQQ__SubscriptionType__c NOT IN ('One-time', 'One-Time', 'Evergreen')
        ]) {
            contractToSubscriptions.get(sub.SBQQ__Contract__c).add(sub);
        }
        
        return contractToSubscriptions;
    }
    
    /**
     * @description Check if all recurring subscriptions for a contract are terminated
     * @param contractId The contract ID
     * @param subscriptionsMap Map of contract ID to subscriptions (pre-queried)
     * @return true if all recurring subscriptions are terminated, false otherwise
     */
    public static Boolean areAllSubscriptionsTerminated(Id contractId, Map<Id, List<SBQQ__Subscription__c>> subscriptionsMap) {
        List<SBQQ__Subscription__c> subscriptions = subscriptionsMap.get(contractId);
        
        // If no recurring subscriptions exist, consider it as "all terminated" (nothing to block)
        if (subscriptions == null || subscriptions.isEmpty()) {
            return true;
        }
        
        // Check if any subscription is NOT terminated (SBQQ__TerminatedDate__c is null)
        for (SBQQ__Subscription__c sub : subscriptions) {
            if (sub.SBQQ__TerminatedDate__c == null) {
                return false; // At least one active subscription remains
            }
        }
        
        return true; // All subscriptions are terminated
    }
    
    /**
     * @description Filter contracts to only those with all subscriptions terminated
     * @param contractIds Set of contract IDs to check
     * @return Set of contract IDs that have all subscriptions terminated
     */
    public static Set<Id> getContractsWithAllSubscriptionsTerminated(Set<Id> contractIds) {
        Set<Id> eligibleContractIds = new Set<Id>();
        
        if (contractIds == null || contractIds.isEmpty()) {
            return eligibleContractIds;
        }
        
        Map<Id, List<SBQQ__Subscription__c>> subscriptionsMap = getRecurringSubscriptions(contractIds);
        
        for (Id contractId : contractIds) {
            if (areAllSubscriptionsTerminated(contractId, subscriptionsMap)) {
                eligibleContractIds.add(contractId);
            } else {
                Nebula.Logger.info('Contract ' + contractId + ' has active recurring subscriptions - skipping status update');
            }
        }
        
        return eligibleContractIds;
    }
}