/**
 * SyncSnapshotDiffer
 * Compares an incoming change payload against the last known synced
 * state (SyncedRecordSnapshot__c) to produce a field-level diff.
 */
public with sharing class SyncSnapshotDiffer {

    public class FieldDiff {
        public String recordId;
        public String objectApiName;
        public Map<String, Object> safeToApply   = new Map<String, Object>();
        public Map<String, ConflictDetail> conflicts = new Map<String, ConflictDetail>();
        public Boolean hasConflicts { get { return !conflicts.isEmpty(); } }
    }

    public class ConflictDetail {
        public Object snapshotValue;
        public Object orgAValue;
        public Object orgBValue;
        public ConflictDetail(Object snap, Object a, Object b) {
            snapshotValue = snap;
            orgAValue     = a;
            orgBValue     = b;
        }
    }

    public static FieldDiff diff(String recordId, String objectApiName,
                                  Map<String, Object> orgAPayload,
                                  Map<String, Object> orgBPayload,
                                  SyncedRecordSnapshot__c snapshot) {

        FieldDiff result       = new FieldDiff();
        result.recordId        = recordId;
        result.objectApiName   = objectApiName;

        Map<String, Object> snapshotValues = snapshot != null
            ? (Map<String, Object>) JSON.deserializeUntyped(snapshot.SnapshotJSON__c)
            : new Map<String, Object>();

        Set<String> allChangedFields = new Set<String>();
        if (orgAPayload != null) allChangedFields.addAll(orgAPayload.keySet());
        if (orgBPayload != null) allChangedFields.addAll(orgBPayload.keySet());

        for (String field : allChangedFields) {
            Object snapVal = snapshotValues.get(field);
            Object aVal    = orgAPayload != null ? orgAPayload.get(field) : null;
            Object bVal    = orgBPayload != null ? orgBPayload.get(field) : null;

            Boolean aChanged = orgAPayload != null && orgAPayload.containsKey(field)
                && !valuesEqual(aVal, snapVal);
            Boolean bChanged = orgBPayload != null && orgBPayload.containsKey(field)
                && !valuesEqual(bVal, snapVal);

            if (aChanged && bChanged && !valuesEqual(aVal, bVal)) {
                result.conflicts.put(field, new ConflictDetail(snapVal, aVal, bVal));
            } else if (aChanged && !bChanged) {
                result.safeToApply.put(field, aVal);
            } else if (bChanged && !aChanged) {
                result.safeToApply.put(field, bVal);
            }
        }

        return result;
    }

    private static Boolean valuesEqual(Object a, Object b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        return String.valueOf(a) == String.valueOf(b);
    }

    public static Map<String, SyncedRecordSnapshot__c> loadSnapshots(
            List<String> recordIds, String objectApiName) {
        Map<String, SyncedRecordSnapshot__c> result = new Map<String, SyncedRecordSnapshot__c>();
        for (SyncedRecordSnapshot__c snap : [
            SELECT RecordId__c, SnapshotJSON__c, LastSyncedAt__c
            FROM SyncedRecordSnapshot__c
            WHERE RecordId__c IN :recordIds
              AND ObjectApiName__c = :objectApiName
        ]) {
            result.put(snap.RecordId__c, snap);
        }
        return result;
    }

    public static void upsertSnapshots(List<String> recordIds,
                                        String objectApiName,
                                        List<Map<String, Object>> resolvedPayloads) {
        List<SyncedRecordSnapshot__c> toUpsert = new List<SyncedRecordSnapshot__c>();
        for (Integer i = 0; i < recordIds.size(); i++) {
            toUpsert.add(new SyncedRecordSnapshot__c(
                RecordId__c       = recordIds[i],
                ObjectApiName__c  = objectApiName,
                SnapshotJSON__c   = JSON.serialize(resolvedPayloads[i]),
                LastSyncedAt__c   = Datetime.now(),
                SnapshotVersion__c = System.currentTimeMillis()
            ));
        }
        upsert toUpsert RecordId__c;
    }
}
