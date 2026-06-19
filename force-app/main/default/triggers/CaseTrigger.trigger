/********************************************************************************     
 *  Name             :  CaseTrigger
 *  Author           :  Hiforte Technologies
 *  Description      :  1. Identifies if an Account has Active projects, for Cases
 *                                  
 *  Change history   :
 *  Date                Author                          Description
 *  02/24/14        Vasu Pulipati                   Created
 ********************************************************************************/
trigger CaseTrigger on Case (before insert, before update,after Insert, after update, after delete, after undelete) {

    if(Trigger.isBefore) 
    {
          if(Trigger.isInsert)
          {   
              CaseTriggerHandler.BeforeInsert(Trigger.new);
          }
          
          if(Trigger.isUpdate)
          { 
              CaseTriggerHandler.BeforeUpdate(Trigger.new, Trigger.NewMap, Trigger.old, Trigger.oldMap);
          }
      
   }
    
    if(Trigger.isAfter)
    {
         if(Trigger.isInsert)
         {
           CaseTriggerHandler.AfterInsert(Trigger.new, Trigger.newMap);

         }

         if(Trigger.isUpdate)
         {
           CaseTriggerHandler.AfterUpdate(Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);

         }

         if(Trigger.isDelete)
         {
           CaseTriggerHandler.AfterDelete(Trigger.old, Trigger.oldMap);

         }

         if(Trigger.isUnDelete)
         {
           CaseTriggerHandler.AfterUnDelete(Trigger.new, Trigger.newMap);

         }       

    }       
    
}