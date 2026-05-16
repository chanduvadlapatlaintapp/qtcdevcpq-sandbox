public with sharing class DisableCPQtriggers {
    @InvocableMethod(label='Disable CPQ Triggers' description='Disables CPQ triggers for DML operations')
    public static void disableCPQTriggerExecutions() {
        try {
            SBQQ.TriggerControl.disable();
            System.debug('CPQ Triggers Disabled Successfully');
        } catch (Exception e) {
            System.debug('Error disabling CPQ triggers: ' + e.getMessage());
        }
    }
}