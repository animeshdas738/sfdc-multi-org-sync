/**
 * SyncDashboardController
 * AuraEnabled controller for the LWC sync dashboard and
 * the manual conflict review interface.
 */
public with sharing class SyncDashboardController {

    // ── Dashboard stats ──────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static SyncStats getSyncStats() {
        SyncStats stats = new SyncStats();
        stats.pendingEvents   = [SELECT COUNT() FROM SyncEvent__c
                                  WHERE Status__c = :SyncConstants.EVT_PENDING];
        stats.appliedToday    = [SELECT COUNT() FROM SyncEvent__c
                                  WHERE Status__c = :SyncConstants.EVT_APPLIED
                                    AND CreatedDate = TODAY];
        stats.conflictsOpen   = [SELECT COUNT() FROM SyncEvent__c
                                  WHERE Status__c = :SyncConstants.EVT_CONFLICTED];
        stats.errorsToday     = [SELECT COUNT() FROM SyncEvent__c
                                  WHERE Status__c = :SyncConstants.EVT_FAILED
                                    AND CreatedDate = TODAY];
        stats.lastSyncRun     = getLastSyncRun();
        return stats;
    }

    // ── Pending conflicts for manual review ──────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<ConflictReviewItem> getPendingConflicts(Integer limitRows) {
        if (limitRows == null) limitRows = 50;
        List<ConflictReviewItem> items = new List<ConflictReviewItem>();

        for (SyncAuditLog__c log : [
            SELECT Id, ObjectApiName__c, RecordId__c, FieldName__c,
                   OrgAValue__c, OrgBValue__c, SnapshotValue__c,
                   SourceOrg__c, SyncedAt__c
            FROM SyncAuditLog__c
            WHERE Outcome__c = :SyncConstants.OUTCOME_MANUAL
              AND ManualResolutionAt__c = null
            ORDER BY SyncedAt__c ASC
            LIMIT :limitRows
        ]) {
            items.add(new ConflictReviewItem(log));
        }
        return items;
    }

    // ── Resolve a manual conflict ────────────────────────────────────
    @AuraEnabled
    public static String resolveConflict(Id auditLogId, String winningOrg) {
        SyncAuditLog__c log = [
            SELECT Id, ObjectApiName__c, RecordId__c, FieldName__c,
                   OrgAValue__c, OrgBValue__c
            FROM SyncAuditLog__c WHERE Id = :auditLogId
        ];

        String resolvedValue = winningOrg == SyncConstants.ORG_A
            ? log.OrgAValue__c : log.OrgBValue__c;

        // Apply the chosen value to both orgs
        Map<String, Object> payload = new Map<String, Object>{
            log.FieldName__c => resolvedValue
        };

        SyncApplyEngine.ApplyResult localResult =
            SyncApplyEngine.applyLocal(log.ObjectApiName__c, log.RecordId__c, payload);

        // Mark the audit log as resolved
        update new SyncAuditLog__c(
            Id                     = auditLogId,
            Outcome__c             = winningOrg == SyncConstants.ORG_A
                                         ? SyncConstants.OUTCOME_ORG_A_WINS
                                         : SyncConstants.OUTCOME_ORG_B_WINS,
            ResolvedValue__c       = resolvedValue,
            ManualResolutionBy__c  = UserInfo.getUserId(),
            ManualResolutionAt__c  = Datetime.now()
        );

        return localResult.status;
    }

    // ── Trigger an immediate sync run ────────────────────────────────
    @AuraEnabled
    public static Id triggerSync(String strategy) {
        return Database.executeBatch(
            new SyncOrchestratorBatch(strategy), 50
        );
    }

    // ── Recent audit log entries ─────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<SyncAuditLog__c> getRecentAuditLog(Integer limitRows) {
        if (limitRows == null) limitRows = 100;
        return [
            SELECT ObjectApiName__c, RecordId__c, FieldName__c,
                   SourceOrg__c, TargetOrg__c, Strategy__c, Outcome__c,
                   OrgAValue__c, OrgBValue__c, ResolvedValue__c,
                   ApplyStatus__c, SyncedAt__c
            FROM SyncAuditLog__c
            ORDER BY SyncedAt__c DESC
            LIMIT :limitRows
        ];
    }

    // ── Helpers ──────────────────────────────────────────────────────
    private static Datetime getLastSyncRun() {
        List<AsyncApexJob> jobs = [
            SELECT CompletedDate FROM AsyncApexJob
            WHERE ApexClass.Name = 'SyncOrchestratorBatch'
              AND Status = 'Completed'
            ORDER BY CompletedDate DESC
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0].CompletedDate;
    }

    // ── DTOs ─────────────────────────────────────────────────────────
    public class SyncStats {
        @AuraEnabled public Integer  pendingEvents;
        @AuraEnabled public Integer  appliedToday;
        @AuraEnabled public Integer  conflictsOpen;
        @AuraEnabled public Integer  errorsToday;
        @AuraEnabled public Datetime lastSyncRun;
    }

    public class ConflictReviewItem {
        @AuraEnabled public Id      auditLogId;
        @AuraEnabled public String  objectApiName;
        @AuraEnabled public String  recordId;
        @AuraEnabled public String  fieldName;
        @AuraEnabled public String  orgAValue;
        @AuraEnabled public String  orgBValue;
        @AuraEnabled public String  snapshotValue;
        @AuraEnabled public String  sourceOrg;
        @AuraEnabled public Datetime syncedAt;

        public ConflictReviewItem(SyncAuditLog__c log) {
            this.auditLogId    = log.Id;
            this.objectApiName = log.ObjectApiName__c;
            this.recordId      = log.RecordId__c;
            this.fieldName     = log.FieldName__c;
            this.orgAValue     = log.OrgAValue__c;
            this.orgBValue     = log.OrgBValue__c;
            this.snapshotValue = log.SnapshotValue__c;
            this.sourceOrg     = log.SourceOrg__c;
            this.syncedAt      = log.SyncedAt__c;
        }
    }
}
