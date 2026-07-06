/**
 * SyncOrchestratorBatch
 * Main batch job for processing sync events
 */
public with sharing class SyncOrchestratorBatch
        implements Database.Batchable<SObject>,
                   Database.AllowsCallouts,
                   Database.Stateful {

    private String  strategy;
    private Integer processedCount = 0;
    private Integer conflictCount  = 0;
    private Integer errorCount     = 0;

    public SyncOrchestratorBatch(String strategy) {
        this.strategy = strategy != null ? strategy : 'FieldPriority';
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, SourceOrg__c, ObjectApiName__c, RecordId__c,
                   ChangeType__c, CommitTimestamp__c, CommitNumber__c,
                   ChangedFields__c, PayloadJSON__c, Status__c
            FROM SyncEvent__c
            WHERE Status__c = 'Pending'
            ORDER BY CommitNumber__c ASC
            LIMIT 1000
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<SObject> scope) {
        List<SyncEvent__c> events = (List<SyncEvent__c>) scope;

        // Step 1: Deduplicate
        List<SyncEvent__c> deduped = SyncDeduplicator.deduplicate(events);

        // Step 2: Process remaining events
        List<SyncEvent__c> toUpdate = new List<SyncEvent__c>();
        for (SyncEvent__c evt : deduped) {
            processedCount++;
            toUpdate.add(new SyncEvent__c(Id = evt.Id, Status__c = 'Applied'));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug(LoggingLevel.INFO,
            'SyncOrchestratorBatch complete. Processed: ' + processedCount);
    }
}
