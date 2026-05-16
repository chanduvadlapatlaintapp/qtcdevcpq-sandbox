/**
* @description Selector class for Renewal Letters
* @author Sahal Mohamed
* @Created Date: Feb 14, 2025
**/
public inherited sharing class RenewalLetterSelector {

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
    public RenewalLetterSelector() {
        baseFieldsToSelect = new Set<String> {
            'Id'
        };
    }

    /**
    * @description Parameterized Contructor for RenewalLetterSelector
    * @param additionalFields
    **/
    public RenewalLetterSelector(Set<String> additionalFields) {
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
    * @description getter for Renewal Letters by Quote Id
    * @param quoteIds
    * @return List<Proforma_Invoice__c>
    **/    
    public List<Proforma_Invoice__c> getRenLetterByQuoteIds(Set<Id> quoteIds) {

        String quoteIdSetString = String.join(quoteIds, '\',\'');
        quoteIdSetString = '(\'' + quoteIdSetString + '\')';
        Set<String> fieldsToSelect = new Set<String>();
        fieldsToSelect.addAll(baseFieldsToSelect);
        if(this.additionalFields != null) {
            fieldsToSelect.addAll(this.additionalFields);
        }
        String query = 'SELECT ' + String.join(new List<String>(fieldsToSelect),',') + ' ' +
                       'FROM Proforma_Invoice__c WHERE Renewal_Quote__c IN ' + quoteIdSetString;
        return Database.Query(query);
    }
}