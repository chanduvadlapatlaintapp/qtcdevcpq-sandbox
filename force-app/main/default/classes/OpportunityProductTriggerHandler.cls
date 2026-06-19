/**
* @description Trigger Handler class for OpportunityProductTrigger 
* @author Pooja Hemrajani
* @jira BIZ-66418
**/
public without sharing class OpportunityProductTriggerHandler implements TriggerFunctionInterface {

    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/

    /**
    * @description : This method will handle before insert event of Order object. 
    * @param lstNewObject 
    **/
    public void beforeInsert(List<SObject> lstNewObject){
        OpportunityProductTriggerHelper.updateOLIFromGhostQL((List<OpportunityLineItem>)lstNewObject);
    }

    /**
    * @description : This method will handle before update event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle before delete event of Order object.
    * @param lstNewObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after insert event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
        OpportunityProductTriggerHelper.updateSegmentedBundleId(lstNewObject);
        OpportunityProductTriggerHelper.opportunityProductEventafterInsert(lstNewObject, false);
        if(OpportunityProductTriggerHelper.isfirstRun){
            OpportunityProductTriggerHelper.isfirstRun = false;
            OpportunityProductTriggerHelper.updateRenewalSegmentedBundleId(lstNewObject);
        }
        
        // Track field history for new OpportunityLineItem records
        FieldHistoryHandler.trackFieldChangesOnInsert((List<OpportunityLineItem>) lstNewObject, 'OpportunityLineItem');
    }

    /**
    * @description : This method will handle after update event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        List<OpportunityLineItem> opportunityProductNewList = (List<OpportunityLineItem>)lstNewObject;
        Map<Id,OpportunityLineItem> opportunityProductOldMap = (Map<Id,OpportunityLineItem>)mapOldObject;

        // Track field history FIRST, before any logic that may re-trigger updates on the same records
        FieldHistoryHandler.trackFieldChanges(opportunityProductNewList, (Map<Id, SObject>)mapOldObject, 'OpportunityLineItem');

        OpportunityProductTriggerHelper.checkSegmentBundleForRetrigger(opportunityProductNewList, opportunityProductOldMap); //BIZ-77103
        OpportunityProductTriggerHelper.opportunityProductEventafterUpdate(opportunityProductNewList, opportunityProductOldMap);
    }

    /**
    * @description : This method will handle after delete event of Order object.
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        List<OpportunityLineItem> opportunityProductOldList = (List<OpportunityLineItem>)lstOldObject;
        OpportunityProductTriggerHelper.opportunityProductEventafterDelete(opportunityProductOldList);
    }

    /**
    * @description : This method will handle after undelete event of Order object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
    }
}