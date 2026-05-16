public with sharing class ContractSubscriptionController {
    
    /**
     * Get subscriptions for a given contract, or all subscriptions if contractId is null
     * Uses CPQ Subscription object (SBQQ__Subscription__c) with CPQ field names
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getSubscriptions(Id contractId) {
        try {
            // Using CPQ Subscription object and fields
            String objectName = 'SBQQ__Subscription__c';
            String monthlyCostField = 'SBQQ__NetPrice__c'; // Using NetPrice as monthly cost
            String quantityField = 'SBQQ__Quantity__c';
            String startDateField = 'SBQQ__StartDate__c';
            String endDateField = 'SBQQ__EndDate__c';
            String contractField = 'SBQQ__Contract__c';
            
            String query = 'SELECT Id, Name, SBQQ__Product__c, ' + 
                          monthlyCostField + ', ' + 
                          quantityField + ', ' + 
                          startDateField + ', ' + 
                          endDateField + ', ' + 
                          contractField + ', ' + 
                          contractField.replace('__c', '__r.Name') + 
                          ' FROM ' + objectName;
            
            if (!String.isBlank(contractId)) {
                query += ' WHERE ' + contractField + ' = :contractId';
            }
            
            query += ' ORDER BY ' + startDateField + ' DESC NULLS LAST LIMIT 1000';
            
            return Database.query(query);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching subscriptions: ' + e.getMessage());
        }
    }
    
    /**
     * Get subscriptions by contract number/name
     * Searches for contracts matching the number/name and returns their subscriptions
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getSubscriptionsByContractNumber(String contractNumber) {
        try {
            if (String.isBlank(contractNumber)) {
                return getSubscriptions(null);
            }
            
            // Search for contracts by ContractNumber or Name
            List<Contract> contracts = [
                SELECT Id 
                FROM Contract 
                WHERE ContractNumber LIKE :('%' + contractNumber + '%')
                   OR Name LIKE :('%' + contractNumber + '%')
                LIMIT 10
            ];
            
            if (contracts.isEmpty()) {
                return new List<SObject>();
            }
            
            Set<Id> contractIds = new Set<Id>();
            for (Contract c : contracts) {
                contractIds.add(c.Id);
            }
            
            // Using CPQ Subscription object and fields
            String objectName = 'SBQQ__Subscription__c';
            String monthlyCostField = 'SBQQ__NetPrice__c';
            String quantityField = 'SBQQ__Quantity__c';
            String startDateField = 'SBQQ__StartDate__c';
            String endDateField = 'SBQQ__EndDate__c';
            String contractField = 'SBQQ__Contract__c';
            
            String query = 'SELECT Id, Name, SBQQ__Product__c, ' + 
                          monthlyCostField + ', ' + 
                          quantityField + ', ' + 
                          startDateField + ', ' + 
                          endDateField + ', ' + 
                          contractField + ', ' + 
                          contractField.replace('__c', '__r.Name') + 
                          ' FROM ' + objectName +
                          ' WHERE ' + contractField + ' IN :contractIds' +
                          ' ORDER BY ' + startDateField + ' DESC NULLS LAST LIMIT 1000';
            
            return Database.query(query);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching subscriptions by contract number: ' + e.getMessage());
        }
    }
}