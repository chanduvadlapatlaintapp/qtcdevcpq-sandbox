public without sharing class NebulaLogCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {

    public enum Target { LOG_ENTRY_TAG, LOG_ENTRY, LOG }

    private static final Integer SCOPE_SIZE = 200;

    private final Datetime cutoff;
    private final Target target;
    private Integer deletedCount = 0;
    private Integer errorCount = 0;

    public NebulaLogCleanupBatch(Datetime cutoff, Target target) {
        this.cutoff = cutoff;
        this.target = target;
    }

    public static Id run(Datetime cutoff) {
        return Database.executeBatch(new NebulaLogCleanupBatch(cutoff, Target.LOG_ENTRY_TAG), SCOPE_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String soql;
        switch on target {
            when LOG_ENTRY_TAG {
                soql = 'SELECT Id FROM Nebula__LogEntryTag__c WHERE CreatedDate < :cutoff';
            }
            when LOG_ENTRY {
                soql = 'SELECT Id FROM Nebula__LogEntry__c WHERE CreatedDate < :cutoff';
            }
            when LOG {
                soql = 'SELECT Id FROM Nebula__Log__c WHERE CreatedDate < :cutoff';
            }
        }
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope.isEmpty()) return;

        Database.DeleteResult[] delResults = Database.delete(scope, false);
        List<SObject> deleted = new List<SObject>();
        for (Integer i = 0; i < delResults.size(); i++) {
            if (delResults[i].isSuccess()) {
                deleted.add(scope[i]);
            } else {
                errorCount++;
            }
        }
        deletedCount += deleted.size();
        if (!deleted.isEmpty()) {
            Database.emptyRecycleBin(deleted);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'NebulaLogCleanupBatch[' + target + '] deleted=' + deletedCount + ' errors=' + errorCount);
        Target next = nextTarget(target);
        if (next != null) {
            Database.executeBatch(new NebulaLogCleanupBatch(cutoff, next), SCOPE_SIZE);
        }
    }

    private static Target nextTarget(Target current) {
        switch on current {
            when LOG_ENTRY_TAG { return Target.LOG_ENTRY; }
            when LOG_ENTRY { return Target.LOG; }
            when else { return null; }
        }
    }
}