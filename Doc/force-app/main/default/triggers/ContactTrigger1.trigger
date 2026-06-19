/********************************************************************************     
 *  Name             :  ProjectTrigger
 *  Author           :  Intapp
 *  Description      :  1. Notifies users when an contact is deleted
 *                                  
 *  Change history   :
 *  Date                Author                          Description
 *  11/28/2016          Mitali Machra                   Created
 
 ********************************************************************************/
trigger ContactTrigger1 on Contact (before insert,before update,after delete,after insert,after update)  
{
    if(trigger.isAfter){
      if(trigger.isDelete)
      {
        System.debug('#### Contact trigger- contacts deleted: '+ trigger.old.size());
        ContactTriggerHandler.sendContactDeletedNotification(trigger.old);
      }
      if(trigger.isinsert)
      {
        ContactTriggerHandler.contactAfterInsert(trigger.new);
      }     
      if(trigger.isupdate)
      {
        ContactTriggerHandler.contactAfterUpdate(trigger.new,trigger.oldmap);
      }
    }
    if (trigger.isBefore){
        ContactTriggerHandler.disablePortalUserCheck(trigger.New);
    }

 }