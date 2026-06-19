public class TriggerDispatcher {
    public static void run(String Objectname){
        Map<Id,Boolean> mapAllowExecution = AutomationPreference.validateExecution(Objectname, Trigger.new != null && Trigger.new.size() > 0 ? Trigger.new : Trigger.old);
        for(Id genericObjectId : mapAllowExecution.keySet()){
            if(!mapAllowExecution.get(genericObjectId)){
                return;
            }
        }
        
        String s = TriggerSettings__mdt.getinstance(Objectname.replaceAll('__','_')).Handler_Name__c;
        Type t = Type.forName(s);
        TriggerFunctionInterface handler = (TriggerFunctionInterface)t.newInstance();        
        if (handler == null)
        {
            throw new TriggerHandlerException('No Trigger Handler found named: ' + t.getName());
        }
        execute(handler);
    }

    private static void execute(TriggerFunctionInterface handler){
        // Before Trigger
        if (Trigger.isBefore)
        { 
            // Iterate through the records to be deleted passing them to the handler.
            if (Trigger.isDelete)
            {
                handler.beforeDelete(Trigger.old, Trigger.oldMap);
            }
            // Iterate through the records to be inserted passing them to the handler.
            else if (Trigger.isInsert)
            {
                handler.beforeInsert(Trigger.new);
            }
            // Iterate through the records to be updated passing them to the handler.
            else if (Trigger.isUpdate)
            {
                handler.beforeUpdate(Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);
            }
        }
        else
        {
             // Iterate through the records deleted passing them to the handler.
            if (Trigger.isDelete)
            {
                handler.afterDelete(Trigger.old, Trigger.oldMap);
            }
            // Passing new colection on insert the handler.
            else if (Trigger.isInsert)
            {
                handler.afterInsert(Trigger.new, Trigger.newMap);
            }
            // Passing new and updated collections to the handler for update event.
            else if (Trigger.isUpdate)
            {
                handler.afterUpdate(Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);
            }
            // Passing new and updated collections to the handler for update event.
            else if (Trigger.isUndelete)
            {
                handler.afterUnDelete(Trigger.new, Trigger.newMap);
            }
        }
        
    }

    public class TriggerHandlerException extends Exception {}
}