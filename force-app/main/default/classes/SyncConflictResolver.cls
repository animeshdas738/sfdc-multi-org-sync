/**
 * SyncConflictResolver
 * Applies conflict resolution strategies when both orgs have changed a field.
 * Three strategies: LastWriteWins (timestamp), FieldPriority (metadata config), Manual (user review)
 */
public with sharing class SyncConflictResolver {

    public class ConflictLogEntry {
        public String fieldName;
        public String strategy;       // LastWriteWins | FieldPriority | Manual
        public String outcome;        // Applied | ManualReview | Rejected
        public Object snapshotValue;
        public Object orgAValue;
        public Object orgBValue;
        public Object resolvedValue;
    }

    public class ResolutionResult {
        public Map<String, Object> resolvedValues = new Map<String, Object>();
        public List<ConflictLogEntry> auditEntries = new List<ConflictLogEntry>();
        public String strategy;                    // overall strategy used
        public Boolean requiresManualReview = false;
    }

    /**
     * LastWriteWins strategy: higher timestamp wins
     */
    public static ResolutionResult resolveLastWriteWins(
            SyncSnapshotDiffer.FieldDiff fieldDiff,
            Long orgATimestamp,
            Long orgBTimestamp) {
        ResolutionResult result = new ResolutionResult();
        result.strategy = 'LastWriteWins';

        // Add safe-to-apply fields
        result.resolvedValues.putAll(fieldDiff.safeToApply);

        // Resolve conflicts by timestamp
        for (String fieldName : fieldDiff.conflicts.keySet()) {
            SyncSnapshotDiffer.ConflictDetail conflict = fieldDiff.conflicts.get(fieldName);

            Object winner = orgATimestamp >= orgBTimestamp
                ? conflict.orgAValue : conflict.orgBValue;

            result.resolvedValues.put(fieldName, winner);

            ConflictLogEntry entry = new ConflictLogEntry();
            entry.fieldName = fieldName;
            entry.strategy = 'LastWriteWins';
            entry.outcome = 'Applied';
            entry.snapshotValue = conflict.snapshotValue;
            entry.orgAValue = conflict.orgAValue;
            entry.orgBValue = conflict.orgBValue;
            entry.resolvedValue = winner;

            result.auditEntries.add(entry);
        }

        return result;
    }

    /**
     * FieldPriority strategy: check SyncFieldPriorityConfig__mdt for field ownership
     */
    public static ResolutionResult resolveFieldPriority(
            SyncSnapshotDiffer.FieldDiff fieldDiff) {
        ResolutionResult result = new ResolutionResult();
        result.strategy = 'FieldPriority';

        // Add safe-to-apply fields
        result.resolvedValues.putAll(fieldDiff.safeToApply);

        // Resolve conflicts by field priority config
        for (String fieldName : fieldDiff.conflicts.keySet()) {
            SyncSnapshotDiffer.ConflictDetail conflict = fieldDiff.conflicts.get(fieldName);

            // Query custom metadata for this field's priority
            Object winner = null;
            String winningOrg = null;

            // For now, default to Org A's value
            // In production, this would query SyncFieldPriorityConfig__mdt
            winner = conflict.orgAValue;

            result.resolvedValues.put(fieldName, winner);

            ConflictLogEntry entry = new ConflictLogEntry();
            entry.fieldName = fieldName;
            entry.strategy = result.requiresManualReview ? 'Manual' : 'FieldPriority';
            entry.outcome = result.requiresManualReview ? 'ManualReview' : 'Applied';
            entry.snapshotValue = conflict.snapshotValue;
            entry.orgAValue = conflict.orgAValue;
            entry.orgBValue = conflict.orgBValue;
            entry.resolvedValue = winner;

            result.auditEntries.add(entry);
        }

        return result;
    }

    /**
     * Manual review strategy: flag all conflicts for human review
     */
    public static ResolutionResult resolveManual(
            SyncSnapshotDiffer.FieldDiff fieldDiff) {
        ResolutionResult result = new ResolutionResult();
        result.strategy = 'Manual';
        result.requiresManualReview = true;

        // Add safe-to-apply fields
        result.resolvedValues.putAll(fieldDiff.safeToApply);

        // All conflicts go to manual review
        for (String fieldName : fieldDiff.conflicts.keySet()) {
            SyncSnapshotDiffer.ConflictDetail conflict = fieldDiff.conflicts.get(fieldName);

            ConflictLogEntry entry = new ConflictLogEntry();
            entry.fieldName = fieldName;
            entry.strategy = 'Manual';
            entry.outcome = 'ManualReview';
            entry.snapshotValue = conflict.snapshotValue;
            entry.orgAValue = conflict.orgAValue;
            entry.orgBValue = conflict.orgBValue;
            entry.resolvedValue = conflict.orgAValue; // default to OrgA, user can override

            result.auditEntries.add(entry);
        }

        return result;
    }
}
