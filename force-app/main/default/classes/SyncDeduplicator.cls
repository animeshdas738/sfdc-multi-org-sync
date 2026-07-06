/**
 * SyncDeduplicator
 * Collapses multiple SyncEvent__c records for the same record ID
 * that arrived within the deduplication window into a single event.
 */
public with sharing class SyncDeduplicator {

    public static List<SyncEvent__c> deduplicate(List<SyncEvent__c> events) {
        Map<String, SyncEvent__c> latest = new Map<String, SyncEvent__c>();
        Map<String, List<SyncEvent__c>> duplicates = new Map<String, List<SyncEvent__c>>();

        for (SyncEvent__c evt : events) {
            String key = evt.SourceOrg__c + '|' + evt.ObjectApiName__c + '|' + evt.RecordId__c;

            if (!latest.containsKey(key)) {
                latest.put(key, evt);
                duplicates.put(key, new List<SyncEvent__c>());
            } else {
                SyncEvent__c existing = latest.get(key);
                if (evt.CommitNumber__c > existing.CommitNumber__c) {
                    duplicates.get(key).add(existing);
                    latest.put(key, evt);
                } else {
                    duplicates.get(key).add(evt);
                }
            }
        }

        List<SyncEvent__c> toSkip = new List<SyncEvent__c>();
        for (String key : duplicates.keySet()) {
            for (SyncEvent__c dup : duplicates.get(key)) {
                toSkip.add(new SyncEvent__c(
                    Id        = dup.Id,
                    Status__c = SyncConstants.EVT_SKIPPED,
                    Notes__c  = 'Superseded by event with higher commit number'
                ));
            }
        }
        if (!toSkip.isEmpty()) update toSkip;

        return latest.values();
    }
}
