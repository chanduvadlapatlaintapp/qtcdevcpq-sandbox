/**
* @description Selector class for Contracts
* @author Sahal Mohamed
* @Created Date: Feb 14, 2025
**/
public inherited sharing class ContractSelector {

    /*****************************************************************************************
    *
    * Props
    *
    ******************************************************************************************/
    public Set<String> baseFieldsToSelect;
    public Set<String> additionalFields;

    /*****************************************************************************************
    *
    * Constructor
    *
    ******************************************************************************************/
    /**
    * @description Contructor for RenewalLetterSelector
    **/
    public contractSelector() {
        baseFieldsToSelect = new Set<String> {
            'Id'
        };
    }

    /**
    * @description Parameterized Contructor for RenewalLetterSelector
    * @param additionalFields
    **/
    public contractSelector(Set<String> additionalFields) {
        baseFieldsToSelect = new Set<String> {
            'Id'
        };
        this.additionalFields = additionalFields;
    }

    /*****************************************************************************************
    *
    * Public Selector methods
    *
    *****************************************************************************************/
    /**
    * @description getter for Contacts by Order Id
    * @param orderIds
    * @return List<Contract>
    **/    
    public List<Contract> getContractsByOrderIds(Set<Id> orderIds) {

        String orderIdSetString = String.join(orderIds, '\',\'');
        orderIdSetString = '(\'' + orderIdSetString + '\')';
        Set<String> fieldsToSelect = new Set<String>();
        fieldsToSelect.addAll(baseFieldsToSelect);
        if(this.additionalFields != null) {
            fieldsToSelect.addAll(this.additionalFields);
        }
        String query = 'SELECT ' + String.join(new List<String>(fieldsToSelect),',') + ' ' +
                       'FROM Contract WHERE SBQQ__Order__c IN ' + orderIdSetString;
        return Database.Query(query);
    }
}