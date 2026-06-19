trigger ApprovalTrigger on SBAA__Approval__c (
    before insert, before update,
    after insert, after update
) {
    TriggerDispatcher.run('sbaa__Approval__c');
}