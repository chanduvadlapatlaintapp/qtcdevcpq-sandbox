/********************************************************************************     
*  Name             :  ContractTriggerHandler
*  Author           :  Hiforte Technologies, 
*  Description      :  1. Populate Billing Account on contracts               
*  Change history   : 
*  Date                     Author              Description
*  06/01/14,21/03/2025      Vasu Pulipati       implemeted trigger framework 
*  21/03/25                 Ratan Paul          Updated as part of BIZ-66427 and implemented trigger framework and moved all logic to contractTriggerHelper class
*  7/11/25					Manisha S			BIZ-75580 for Renewal pause field assignments
*  27/04/26                 Manisha S           BIZ-75817 Auto-populate Intapp Master Terms: Contract Number on Account
*  18/05/26                 BIZ-82935           Removed updateRenewalOpps call — Opportunity is now source of truth for Renewal Hold
********************************************************************************/
public without sharing class ContractTriggerHandler  implements TriggerFunctionInterface{
    public static Boolean firstCallUpdate = false;
    
    /**
     * @description Before insert handler
     * @param lstNewObject List<SObject> new Contract records.
     */
    public void beforeInsert(List<SObject> lstNewObject){
        ContractTriggerHelper.populateBillingAccount((List<Contract>)lstNewObject);
        ContractOsaStatusService.setCpqContractStatus((List<Contract>)lstNewObject, null);
    }
    
    /**
     * @description Before update handler
     * @param lstNewObject List<SObject> new Contract records.
     * @param mapNewObject Map<Id,Object> map of new Contract records.
     * @param lstOldObject List<Object> old Contract records.
     * @param mapOldObject Map<Id,Object> map of old Contract records.
     */
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        ContractOsaStatusService.setCpqContractStatus((List<Contract>)lstNewObject, (Map<Id, Contract>)mapOldObject);
    }

    /**
     * @description Before delete handler
     * @param lstOldObject List<SObject> old Contract records to delete.
     * @param mapOldObject Map<Id,Object> old Contract records map.
     */
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
     * @description After insert handler
     * @param lstNewObject List<SObject> inserted Contract records.
     * @param mapNewObject Map<Id,Object> inserted Contract records map.
     */
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        ContractTriggerHelper.populateMasterTermsContractNumber((List<Contract>) lstNewObject);
    }

    /**
     * @description After update handler
     * @param lstNewObject List<SObject> updated Contract records.
     * @param mapNewObject Map<Id,Object> updated Contract records map.
     * @param lstOldObject List<Object> old Contract records.
     * @param mapOldObject Map<Id,Object> old Contract records map.
     */
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        if(!firstCallUpdate) {
            firstCallUpdate = true;
            ContractTriggerHelper.publishEligibleSobjectRecords((List<Contract>)lstNewObject, (Map<Id, Contract>)mapOldObject);

            // BIZ-82935: updateRenewalOpps removed — Opportunity is now source of truth for Renewal Hold
            ContractOsaStatusService.syncOsaSiblings((List<Contract>)lstNewObject, (Map<Id, Contract>)mapOldObject);
        }
    }

    /**
     * @description After delete handler
     * @param lstOldObject List<Object> deleted Contract records.
     * @param mapOldObject Map<Id,Object> deleted Contract records map.
     */
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
     * @description After undelete handler
     * @param lstNewObject List<SObject> restored Contract records.
     * @param mapNewObject Map<Id,Object> restored Contract records map.
     */
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
    }
    
}