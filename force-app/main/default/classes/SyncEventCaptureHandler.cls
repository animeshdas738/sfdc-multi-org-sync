/**
 * SyncEventCaptureHandler
 * Processes CDC (Change Data Capture) events from a trigger and
 * writes them into the SyncEvent__c staging table.
 *
 * How to wire it up — one CDC trigger per synced object:
 *
 *   trigger AccountSyncCapture on AccountChangeEvent (after insert) {
 *       SyncEventCaptureHandler.handle(Trigger.new, 'Account');
 *   }
 *
 * The SyncInProgress__c flag on the record being written by the
 * ApplyEngine suppresses the loop-back event:
 *
 *   if (header.changeOrigin contains 'SyncEngine') return;
 *
 * We use changeOrigin rather than a custom field here because CDC
 * events include the API client name that made the change —
 * the ApplyEngine sets a custom client name on its Named Credential.
 */
public with sharing class SyncEventCaptureHandler {

    private static final String SYNC_ORIGIN_MARKER = 'SyncEngine';

    public static void handle(List<SObject> changeEvents, String objectApiName) {
        List<SyncEvent__c> toInsert = new List<SyncEvent__c>();

        for (SObject event : changeEvents) {
            EventBus.ChangeEventHeader header = getHeader(event);
            if (header == null) continue;

            // Loop prevention: skip events produced by our own apply engine
            if (isOurOwnWrite(header)) continue;

            // One SyncEvent per changed record ID
            for (String recordId : header.getRecordIds()) {
                Datetime commitDt;
                try {
                    commitDt = Datetime.newInstance(header.getCommitTimestamp());
                } catch (Exception e) {
                    commitDt = Datetime.now();
                }

                SyncEvent__c se = new SyncEvent__c(
                    SourceOrg__c        = SyncConstants.ORG_A, // set per deployment
                    ObjectApiName__c    = objectApiName,
                    RecordId__c         = recordId,
                    ChangeType__c       = header.getChangeType(),
                    CommitTimestamp__c  = commitDt,
                    CommitNumber__c     = header.getCommitNumber(),
                    ChangedFields__c    = JSON.serialize(header.getChangedFields()),
                    PayloadJSON__c      = serializePayload(event, header.getChangedFields()),
                    Status__c           = SyncConstants.EVT_PENDING
                );
                toInsert.add(se);
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────

    private static EventBus.ChangeEventHeader getHeader(SObject event) {
        try {
            return (EventBus.ChangeEventHeader) event.get('ChangeEventHeader');
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Could not read ChangeEventHeader: ' + e.getMessage());
            return null;
        }
    }

    private static Boolean isOurOwnWrite(EventBus.ChangeEventHeader header) {
        String origin = header.getChangeOrigin();
        return origin != null && origin.contains(SYNC_ORIGIN_MARKER);
    }

    private static String serializePayload(SObject event, List<String> changedFields) {
        Map<String, Object> payload = new Map<String, Object>();
        for (String field : changedFields) {
            try {
                payload.put(field, event.get(field));
            } catch (Exception e) {
                // Field not accessible — skip
            }
        }
        return JSON.serialize(payload);
    }
}
