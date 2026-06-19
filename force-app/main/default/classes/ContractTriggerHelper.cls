/********************************************************************************     
*  Name             :  ContractTriggerHelper
*  Author           :  Hiforte Technologies
*  Description      :  Helper class for Contract trigger operations: populates Billing Account, 
						identifies and publishes eligible sObjects (Account, Opportunity, Contract, Subscription),
*              			and builds dynamic SOQL queries used by the trigger framework.          
*  Change history   :  
*  Date             Author                          Description
*  06/01/14         Vasu Pulipati, Ratan Paul        Created
*  21/03/25         Ratan Paul                      Updated as part of BIZ-66427 and implemented trigger framework and
                                                    moved all logic from ContractTriggerHandler to contractTriggerHelper class. and optimise the code
*  27/04/26         Manisha S                       BIZ-75817 Added populateMasterTermsContractNumber to auto-populate
                                                    Intapp Master Terms: Contract Number on Account
*  28/04/26         Manisha S                       BIZ-75817 (AC update) Simplified populateMasterTermsContractNumber:
                                                    removed Account.Type, Opportunity.StageName, and QT-0002 QuoteTerm
                                                    checks; added Quote.SBQQ__Type__c != 'Amendment' check
*  18/05/26         BIZ-82935                       Removed updateRenewalOpps() — Contract→Opportunity sync retired; Opportunity is now the source of truth for Renewal Hold
********************************************************************************/
public without sharing class ContractTriggerHelper {

    /**
     * @description Populates the Billing Account field on Contracts.
     * If the Billing Account is not already set, it uses the Account's Bill To Entity or defaults to the Account itself.
     * @param newContracts The list of Contract records to update.
     */
    public static void populateBillingAccount(List<Contract> newContracts){
        Map<Id, Id> mapAcct2ParentId = new Map<Id, Id>();
        for(Contract con: newContracts){
            if(con.AccountId != null && con.Billing_Account__c == null){
                mapAcct2ParentId.put(con.AccountId, null);
            }
        }
        for(Account a: [select Id, Bill_To_Entity__c from Account where Id in :mapAcct2ParentId.keySet()]){
            mapAcct2ParentId.put(a.Id, a.Bill_To_Entity__c);
        }
        for(Contract con: newContracts){
            if(con.AccountId != null && con.Billing_Account__c == null){
                con.Billing_Account__c = (mapAcct2ParentId.get(con.AccountId) != null)? mapAcct2ParentId.get(con.AccountId) : con.AccountId;
            }
        }    
    }
    
    /**
     * @description Processes and publishes eligible records for Contracts, Opportunities, Accounts, and Subscriptions.  
     * This method identifies records that have undergone significant changes and need to be synchronized 
     * with external systems by querying and publishing them accordingly.
     * @param contractNewList The list of newly inserted or updated Contract records.
     * @param contractOldMap A map of old Contract records, keyed by their IDs, to track field changes.
     */
    public static void publishEligibleSobjectRecords(list<Contract> contractNewList, Map<Id,Contract> contractOldMap) {
        List<Account> eligibleAccountList = new List<Account>();
        List<Opportunity> eligibleOpportunityList = new List<Opportunity>();
        List<Contract> lstOfContractsToSend = new List<Contract>();
        List<SBQQ__Subscription__c> eligibleSubscriptionList = new List<SBQQ__Subscription__c>();
        Set<id> setOfAccountId = new Set<id>();
        Set<id> setOfOpportunityId = new Set<id>();
        Set<id> setOfContractId = new Set<id>();
        
        /* BIZ-55114 Start */
        for(Contract contractObj : contractNewList){
            if(contractObj.OP4I_Contract_Id__c != null || contractObj.OP4I_Error__c !=null){
                lstOfContractsToSend.add(contractObj);  
            }
            if(contractObj.SBQQ__Opportunity__c != null && contractObj.OP4I_Contract_Id__c != contractOldMap.get(contractObj.id).OP4I_Contract_Id__c){
                setOfOpportunityId.add(contractObj.SBQQ__Opportunity__c);    
                setOfContractId.add(contractObj.Id);                    
            }               
            
            if(contractObj.Status == 'In Force' && contractObj.Subsidiary__c != null && contractObj.Subsidiary__c != contractOldMap.get(contractObj.id).Subsidiary__c){
                setOfAccountId.add(contractObj.AccountId);
            } 
        }
        
        if(!lstOfContractsToSend.IsEmpty() && lstOfContractsToSend.size() > 0){
            IntegrationUtility.publishEligibleSobjectRecords(lstOfContractsToSend,contractOldMap,'Contract');    
        }
        /* BIZ-55114 End */
        
        if(!setOfAccountId.isEmpty()){
            String strQuery = createQuery('Account',setOfAccountId);
            String strQueryUpd = strQuery.replace('setOfsObjectIds' , 'setOfAccountId');
            eligibleAccountList = Database.query(strQueryUpd);
        }
        
        if(!setOfOpportunityId.isEmpty()){
            List<Opportunity> lstOfOpportunities = [Select id from Opportunity where Related_Opportunity__c IN: setOfOpportunityId];
            if(lstOfOpportunities != null && !lstOfOpportunities.IsEmpty()){
                for(Opportunity opp : lstOfOpportunities){
                    setOfOpportunityId.add(opp.id);
                }                     
            }
            String strQuery = createQuery('Opportunity',setOfOpportunityId);
            String strQueryUpd = strQuery.replace('setOfsObjectIds' , 'setOfOpportunityId');
            eligibleOpportunityList = Database.query(strQueryUpd);
        }
        if(!setOfContractId.isEmpty()){                
            String strQuery = createQuerySubscription('SBQQ__Subscription__c',setOfContractId);
            String strQueryUpd = strQuery.replace('setOfsObjectIds' , 'setOfContractId');
            eligibleSubscriptionList = Database.query(strQueryUpd);
        }
        
        if(!eligibleAccountList.isEmpty()){
            IntegrationUtility.publishsObjectRecords(eligibleAccountList,'Account');
        }
        
        /* published Opportunities as part of BIZ-54487 */
        if(!eligibleOpportunityList.isEmpty()){
            IntegrationUtility.publishsObjectRecords(eligibleOpportunityList,'Opportunity');
        }
        if(!eligibleSubscriptionList.isEmpty()){
            IntegrationUtility.publishsObjectRecords(eligibleSubscriptionList,'SBQQ__Subscription__c');
        }
    }

    /**
     * @description Invocable method to publish an event after a Contract record is inserted.
     * This method is designed to be called from a Flow.
     * @param contractNewList The list of newly inserted Contract records.
     */
    @InvocableMethod(label='Send Updated Payload')
    public static void publishAfterInsertEventFromFlow(list<Contract> contractNewList) {  
        IntegrationUtility.publishsObjectRecords(contractNewList,'Contract');
    }

    /**
     * @description Constructs a dynamic SOQL query to fetch all fields for a given SObject.
     * @param sObjName The API name of the SObject (e.g., 'Account', 'Opportunity').
     * @param setOfsObjectIds The set of record IDs to be queried.
     * @return A string containing the dynamically generated SOQL query.
     */
    public static string createQuery(String sObjName , Set<Id> setOfsObjectIds) {
        Set<String> fieldNames = new Set<String>();
        Schema.SObjectType targetObjType = ((SObject)Type.forName(sObjName).newInstance()).getSObjectType();
        Map<String, Schema.SObjectField> fieldMap = targetObjType.getDescribe().fields.getMap();
        fieldNames = fieldMap.keyset();
        List<String> fields = new List<String>(fieldNames);
        String query =  ' SELECT ' +
            String.join( fields, ',' ) +
            ' FROM ' +
            sObjName +
            ' WHERE ' +
            ' Id IN: setOfsObjectIds';
        
        String strQuery1 = query.remove('{');
        String strQuery2 = strQuery1.remove('}');
        
        return strQuery2;
    } 
    
    /**
     * @description Constructs a dynamic SOQL query to fetch Subscription records linked to a given Contract.
     * @param sObjName The API name of the SObject (e.g., 'SBQQ__Subscription__c').
     * @param setOfsObjectIds The set of Contract IDs used to fetch related Subscriptions.
     * @return A string containing the dynamically generated SOQL query.
     */
    public static string createQuerySubscription(String sObjName , Set<Id> setOfsObjectIds) {
        Set<String> fieldNames = new Set<String>();
        Schema.SObjectType targetObjType = ((SObject)Type.forName(sObjName).newInstance()).getSObjectType();
        Map<String, Schema.SObjectField> fieldMap = targetObjType.getDescribe().fields.getMap();
        fieldNames = fieldMap.keyset();
        List<String> fields = new List<String>(fieldNames);
        String query =  ' SELECT ' +
            String.join( fields, ',' ) +
            ' FROM ' +
            sObjName +
            ' WHERE ' +
            ' SBQQ__Contract__c IN: setOfsObjectIds AND ' +
            ' OP4I_Entitlement_Id__c != null ';

        String strQuery1 = query.remove('{');
        String strQuery2 = strQuery1.remove('}');

        return strQuery2;
    }

    /**
     * @description Populates Master_Terms_Contract_Number__c on Account when a new Contract
     * is created and all qualifying conditions are met (BIZ-75817).
     * Conditions:
     *   - Account.Master_Terms_Contract_Number__c is blank
     *   - Quote.Contract_Master_Terms__c = 'URL Terms'
     *   - Quote.SBQQ__Type__c != 'Amendment'
     *   - Quote.Deal_Type__c != 'Services_Only'
     * @param newContracts List of newly inserted Contract records.
     */
    public static void populateMasterTermsContractNumber(List<Contract> newContracts) {
        // Guard: null/empty input
        if (newContracts == null || newContracts.isEmpty()) {
            return;
        }

        try {
            // Step 1: Filter contracts that have required lookups populated
            Set<Id> contractIds = new Set<Id>();
            for (Contract con : newContracts) {
                if (con != null
                    && con.Id != null
                    && con.AccountId != null
                    && con.SBQQ__Quote__c != null) {
                    contractIds.add(con.Id);
                }
            }
            if (contractIds.isEmpty()) {
                return;
            }

            // Step 2: Fetch Contracts with related Account and Quote in a single query
            List<Contract> contractsWithRelations = [
                SELECT Id, AccountId, SBQQ__Quote__c,
                       Account.Master_Terms_Contract_Number__c,
                       SBQQ__Quote__r.Contract_Master_Terms__c,
                       SBQQ__Quote__r.Deal_Type__c,
                       SBQQ__Quote__r.SBQQ__Type__c
                FROM Contract
                WHERE Id IN :contractIds
            ];
            if (contractsWithRelations.isEmpty()) {
                return;
            }

            // Step 3: Build the Account update map (first-wins for duplicate AccountIds)
            Map<Id, Account> accountsToUpdate = new Map<Id, Account>();
            for (Contract con : contractsWithRelations) {
                // Null-safe checks on relationship fields
                if (con.Account == null || con.SBQQ__Quote__r == null) {
                    continue;
                }
                // Account: lookup must be blank
                if (con.Account.Master_Terms_Contract_Number__c != null) {
                    continue;
                }
                // Quote: URL Terms AND not Amendment AND not Services_Only
                if (con.SBQQ__Quote__r.Contract_Master_Terms__c != QuoteConstants.CONTRACT_MASTER_TERMS_URL
                    || con.SBQQ__Quote__r.SBQQ__Type__c == QuoteConstants.TYPE_AMENDMENT
                    || con.SBQQ__Quote__r.Deal_Type__c == QuoteConstants.DEAL_TYPE_SERVICES_ONLY) {
                    continue;
                }
                // first-wins: skip if AccountId already mapped
                if (accountsToUpdate.containsKey(con.AccountId)) {
                    continue;
                }
                accountsToUpdate.put(con.AccountId, new Account(
                    Id = con.AccountId,
                    Master_Terms_Contract_Number__c = con.Id
                ));
            }

            // Step 4: Bulk update Accounts with partial success enabled
            if (!accountsToUpdate.isEmpty()) {
                List<Account> accountsList = accountsToUpdate.values();
                Database.SaveResult[] saveResults = Database.update(accountsList, false);
                for (Integer i = 0; i < saveResults.size(); i++) {
                    if (!saveResults[i].isSuccess()) {
                        String errorMsg = '';
                        for (Database.Error err : saveResults[i].getErrors()) {
                            errorMsg += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                        }
                        Nebula.Logger.error(
                            'BIZ-75817 Account update failed for Id=' + accountsList[i].Id + ' - ' + errorMsg
                        ).addTag('BIZ-75817');
                    }
                }
                Nebula.Logger.saveLog();
            }
        } catch (Exception e) {
            // Catch-all to prevent trigger failure
            Nebula.Logger.error(
                'BIZ-75817 ContractTriggerHelper.populateMasterTermsContractNumber failed: '
                + e.getMessage() + '\n' + e.getStackTraceString(), e
            ).addTag('BIZ-75817');
            Nebula.Logger.saveLog();
        }
    }
}