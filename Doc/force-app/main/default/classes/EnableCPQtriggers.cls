public with sharing class EnableCPQtriggers {
    @InvocableMethod(label='Enable CPQ Triggers' description='Enables CPQ triggers after bulk operations')
    public static void enableCPQTriggerExecutions() {
        try {
            SBQQ.TriggerControl.enable();
            System.debug('CPQ Triggers Enabled Successfully');
        } catch (Exception e) {
            System.debug('Error enabling CPQ triggers: ' + e.getMessage());
        }
    } 
}