/** 
  @description Trigger handler for Opportunity object
  **/
public class OpportunityTriggerHandler  implements TriggerFunctionInterface {
    /***********************************************************************************************
    *
    * Trigger Handler Methods
    *
    ***********************************************************************************************/
    /**
    * @description : This method will handle before insert event of Quote object. 
    * @param lstNewObject 
    **/
    public void beforeInsert(List<SObject> lstNewObject){
      OpportunityTriggerHelper.setRenewalStageToQualify((List<Opportunity>)lstNewObject); // BIZ-80539
      OpportunityTriggerHelper.markProjectOutOfSync((List<Opportunity>)lstNewObject);
    }

    /**
    * @description : This method will handle before update event of Quote object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/ 
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
      OpportunityTriggerHelper.updateOpportunityFieldsOnStageChange((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject);
      OpportunityTriggerHelper.setCloseDate((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject); // BIZ-71731
      OpportunityTriggerHelper.blockRenewalHoldClosedWon((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject); // BIZ-82935
    }

    /**
    * @description : This method will handle before delete event of Quote object.
    * @param lstNewObject 
    * @param mapOldObject 
    **/
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject){
    }

    /**
    * @description : This method will handle after insert event of Quote object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
      OpportunityTriggerHelper.setCloseDateAfterInsert((List<Opportunity>)lstNewObject);

      //Added via BIZ-76798
      OpportunityTriggerHelper.setNYMYCloseDateAfterInsert((List<Opportunity>)lstNewObject, null);

      OpportunityTriggerHelper.publishNonMigrationOpportunities((List<Opportunity>)lstNewObject);

      // BIZ-82935: Custom field history tracking for Renewal Hold fields (Salesforce standard
      // history tracking limit of 20 fields already reached on Opportunity)
      FieldHistoryHandler.trackFieldChangesOnInsert(lstNewObject, 'Opportunity');
    }

    /**
    * @description : This method will handle after update event of Quote object.
    * @param lstNewObject 
    * @param mapNewObject 
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject){
        
        // BIZ-68167 - Cancel Contract and Accounts based different scenarios
        OpportunityTriggerHelper.cancelContractAndAccounts((List<Opportunity>)lstNewObject);
        
        // BIZ-68167 - Update Account Type to Client When Stage moved to Closed Won
        OpportunityTriggerHelper.updateAccountType((List<Opportunity>)lstNewObject);

        OpportunityTriggerHelper.processOpportunities((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject);

      	//Added via BIZ-76798
      	OpportunityTriggerHelper.setNYMYCloseDateAfterInsert((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject);

        // BIZ-82773 - Cancel Initiated Renewal Letters when Renewal Opp moves to a closed stage
        OpportunityTriggerHelper.cancelRenewalLettersOnOppClose((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject);

        // BIZ-82935: When Renewal Hold is checked, update related Renewal Letter status
        OpportunityTriggerHelper.updateRenewalLetterOnHold((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject);

        // BIZ-79329: Sync Renewal Hold / Reason from Opportunity back to parent Contract
        OpportunityTriggerHelper.syncHoldToContract((List<Opportunity>)lstNewObject, (Map<Id, Opportunity>)mapOldObject);

        // BIZ-82935: Custom field history tracking for Renewal Hold fields
        // Two-step cast: Map<Id,Object> → Map<Id,Opportunity> → Map<Id,SObject> (direct cast throws TypeException)
        FieldHistoryHandler.trackFieldChanges(lstNewObject, (Map<Id, SObject>)(Map<Id, Opportunity>)mapOldObject, 'Opportunity');
    }

    /**
    * @description : This method will handle after delete event of Quote object.
    * @param lstOldObject 
    * @param mapOldObject 
    **/
    public void afterDelete(List<Object> lstNewObject, Map<Id, Object> mapOldObject){
      OpportunityTriggerHelper.sendOpportunityDeletionNotification((List<Opportunity>)lstNewObject);
    }

    /**
    * @description : This method will handle after undelete event of Quote object.
    * @param lstNewObject 
    * @param mapNewObject 
    **/
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject){
    }

}