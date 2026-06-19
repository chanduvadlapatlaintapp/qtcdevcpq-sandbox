trigger AttachmentTrigger on Attachment (before insert, before update, before delete, after insert, after update) {
	if(Trigger.isInsert && Trigger.isBefore){
        //TBD
    }

    if(Trigger.isUpdate && Trigger.isBefore){
        //TBD
    }

    if (Trigger.isDelete && Trigger.isBefore) {
        AttachmentTriggerHandler.attachmentBeforeDelete(Trigger.oldMap);
    }
    
    if(Trigger.isInsert && Trigger.isAfter){
        AttachmentTriggerHandler.attachmentAfterInsert(trigger.newMap);
    }
    
    if(Trigger.isUpdate && Trigger.isAfter){
        //TBD
    }
}