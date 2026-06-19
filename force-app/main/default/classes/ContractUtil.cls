/**
 * @description       : Util class for contracts
**/
public inherited sharing class ContractUtil {

    /**
     * @description Returns the open NYMY Opportunities and Renewal Opportunities from the contracts
     * @param contractIds
     * @return List<Opportunity>
     */
    public static List<Opportunity> getNymyAndRenewalOpportunitiesFromContracts(Set<Id> contractIds){
        List<Opportunity> renewalAndNymyOpporty = [
            SELECT Id, 
                Deal_Type__c,
                Associated_Contract_OSA__c,
                SBQQ__RenewedContract__c, 
                StageName
            FROM Opportunity
            WHERE  
                (
                    (Associated_Contract_OSA__c IN :contractIds AND Deal_Type__c = :OpportunityConstants.DEAL_TYPE_NYMY) 
                    OR 
                    (SBQQ__RenewedContract__c IN :contractIds AND Type = :OpportunityConstants.TYPE_RENEWAL)
                )
                AND (NOT StageName LIKE '%closed%')
        ];
        

        return renewalAndNymyOpporty;
    }

    /**
     * @description Returns the active contract count on the account.
     * @param accountIds
     * @return Map<Id, Integer> 
     */
    public static Map<Id, Integer> getActiveContractCountOnAccount(Set<Id> accountIds) {
        Map<Id, Integer> accountIdToContractCountMap = new Map<Id, Integer>();
    
        if (accountIds == null || accountIds.isEmpty()) {
            return accountIdToContractCountMap;
        }
    
        for (AggregateResult ar : [
            SELECT AccountId, COUNT(Id) contractCount
            FROM Contract
            WHERE AccountId IN :accountIds
              AND Status = :ContractConstants.STATUS_INFORCE
            GROUP BY AccountId
        ]) {
            accountIdToContractCountMap.put(
                (Id) ar.get('AccountId'),
                (Integer) ar.get('contractCount')
            );
        }
    
        return accountIdToContractCountMap;
    }
}