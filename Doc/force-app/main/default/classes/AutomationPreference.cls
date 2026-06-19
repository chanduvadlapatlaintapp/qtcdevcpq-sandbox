/**
* @description       : Utility class that controls the execution of automation (triggers/flows) based on custom settings and metadata.
*                      This class provides functionality to selectively bypass automation execution for specific objects or records
*                      through the Automation_Controls__c custom setting. It checks if automation bypass is enabled for a given
*                      object type and validates whether specific record IDs should be excluded from automation execution.
*                      The class is used by the trigger framework (TriggerDispatcher) to conditionally allow or prevent
*                      trigger execution based on configuration.
* @author            : 
* Created Date       : 
**/
public with sharing class AutomationPreference {
    
    /**
    * @description Validates whether automation (triggers/flows) should execute for a given list of records based on
    *              Automation_Controls__c custom setting configuration. This method checks if automation bypass is enabled
    *              for the specified object type and determines execution permission for each record.
    *              The method supports two bypass modes:
    *              1. Global bypass: When Data_Id__c is blank, all records of the specified object type are bypassed if enabled.
    *              2. Selective bypass: When Data_Id__c contains comma-separated record IDs, only those specific records are bypassed.
    *              If automation controls are not active, bypass is disabled, or metadata is missing, execution is allowed by default.
    * @param sObjectName The API name of the sObject type to validate (e.g., 'Account', 'SBQQ__Quote__c').
    *                    Note: Double underscores (__) are replaced with single underscores (_) when looking up metadata.
    * @param lstGenericObject List of sObject records to validate for automation execution.
    * @return Map<Id,Boolean> Map where each key is a record Id and the value indicates whether automation should execute
    *                        (true = allow execution, false = bypass execution).
    * @example
    * List<Account> accounts = [SELECT Id FROM Account LIMIT 10];
    * Map<Id,Boolean> executionMap = AutomationPreference.validateExecution('Account', accounts);
    * // Returns map with Id => true/false for each account based on automation controls
    **/
    public static Map<Id,Boolean> validateExecution(String sObjectName, List<sObject> lstGenericObject) {
        Map<Id,Boolean> mapIdandAllowExecution = new Map<Id,Boolean>();
        Boolean bObjectBypass = false;

        Automation_Controls__c oAutomationControl = Automation_Controls__c.getInstance();
        Generic_Key_Value_Setting__mdt keyValueSetting = Generic_Key_Value_Setting__mdt.getInstance(sObjectName.replaceAll('__','_'));
        if(keyValueSetting != null && keyValueSetting.Value__c != null && oAutomationControl != null) {
            try {
                bObjectBypass = (Boolean)oAutomationControl.get(keyValueSetting.Value__c);
                // Handle null values - treat as false
                if(bObjectBypass == null) {
                    bObjectBypass = false;
                }
            } catch(SObjectException e) {
                // Field doesn't exist on Automation_Controls__c, default to false
                bObjectBypass = false;
            }
        }
        if(oAutomationControl != null && oAutomationControl.Active__c && bObjectBypass == true && oAutomationControl.Bypass_Triggers__c && String.isBlank(oAutomationControl.Data_Id__c) && lstGenericObject != null && lstGenericObject.size() > 0){
            for(sObject oGenericSObject : lstGenericObject){
                mapIdandAllowExecution.put((Id)oGenericSObject.get('Id'), false);               
            }                     
        } 
        else if(oAutomationControl != null && oAutomationControl.Active__c && bObjectBypass == true && oAutomationControl.Bypass_Triggers__c && String.isNotBlank(oAutomationControl.Data_Id__c) && lstGenericObject != null && lstGenericObject.size() > 0){
            for(sObject oGenericSObject : lstGenericObject){
                mapIdandAllowExecution.put((Id)oGenericSObject.get('Id'), validateDataExecutionUtil(oAutomationControl, oGenericSObject));
            }
        }   
        else{
            if(lstGenericObject != null && lstGenericObject.size() > 0){
                for(sObject oGenericSObject : lstGenericObject){
                    mapIdandAllowExecution.put((Id)oGenericSObject.get('Id'), true);
                }
            }
        }
        return mapIdandAllowExecution;       
    }    
    
    /**
    * @description Private utility method that determines whether a specific record should be bypassed from automation execution
    *              based on the Data_Id__c field in Automation_Controls__c. This method checks if the record's Id is included
    *              in the comma-separated list of bypass record IDs. If the record Id is found in the list, execution is bypassed (returns false).
    *              If Data_Id__c is blank or the record Id is not in the list, execution is allowed (returns true).
    *              Records without an Id are always allowed to execute (true).
    * @param oAutomationControl The Automation_Controls__c custom setting instance containing bypass configuration.
    * @param oGenericObject The sObject record to check for bypass eligibility.
    * @return Boolean Returns true if automation execution should be allowed, false if the record should be bypassed.
    *                - Returns true if record has no Id
    *                - Returns false if record Id is found in Data_Id__c comma-separated list
    *                - Returns true if Data_Id__c is blank or record Id is not in the list
    **/
    private static Boolean validateDataExecutionUtil(Automation_Controls__c oAutomationControl, sObject oGenericObject){        
        String sDataId = oGenericObject.get('Id')!=null ? oGenericObject.get('Id').toString() : null;
        Boolean bAllowRecordExecution = false;
        
        if(String.isBlank(sDataId)){
            bAllowRecordExecution = true;
        }
        else if(oAutomationControl != null){
            bAllowRecordExecution = String.isNotBlank(oAutomationControl.Data_Id__c) ? !oAutomationControl.Data_Id__c.split(',').contains(sDataId) : true;
        }

        return bAllowRecordExecution;
    }    

}