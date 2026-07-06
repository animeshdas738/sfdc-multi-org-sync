public class SyncAuditTrailWriter {
    public static void write(String objectApiName,
                              String recordId,
                              String sourceOrg,
                              String targetOrg,
                              String strategy,
                              List<SyncConflictResolver.ConflictLogEntry> entries,
                              String applyStatus,
                              String applyError) {
        List<SyncAuditLog__c> logs = new List<SyncAuditLog__c>();

        for (SyncConflictResolver.ConflictLogEntry entry : entries) {
            logs.add(new SyncAuditLog__c(
                ObjectApiName__c  = objectApiName,
                RecordId__c       = recordId,
                FieldName__c      = entry.fieldName,
                SourceOrg__c      = sourceOrg,
                TargetOrg__c      = targetOrg,
                Strategy__c       = entry.strategy,
                Outcome__c        = entry.outcome,
                SnapshotValue__c  = truncate(String.valueOf(entry.snapshotValue)),
                OrgAValue__c      = truncate(String.valueOf(entry.orgAValue)),
                OrgBValue__c      = truncate(String.valueOf(entry.orgBValue)),
                ResolvedValue__c  = truncate(String.valueOf(entry.resolvedValue)),
                ApplyStatus__c    = applyStatus,
                ApplyError__c     = applyError,
                SyncedAt__c       = Datetime.now()
            ));
        }

        if (!logs.isEmpty()) insert logs;
    }

    private static String truncate(String val) {
        if (val == null || val == 'null') return null;
        return val.length() > 255 ? val.left(252) + '…' : val;
    }
}

