/**
 * SyncApplyEngine
 * Writes the resolved field values to the target org.
 *
 * Key responsibility: set SyncInProgress__c = true before update,
 * reset to false after. This suppresses the loop-back CDC event.
 *
 * For cross-org writes (Org A → Org B and vice versa), the engine
 * uses REST API calls via Named Credentials to the partner org.
 * For same-org writes (sandbox → sandbox via Connected App), it
 * uses direct DML.
 */
public with sharing class SyncApplyEngine {

    /**
     * Applies resolved values to the local org.
     * Used when this org IS the target.
     */
    public static ApplyResult applyLocal(String objectApiName,
                                          String recordId,
                                          Map<String, Object> resolvedValues) {
        ApplyResult result = new ApplyResult(recordId);
        if (resolvedValues.isEmpty()) {
            result.status = 'NoChange';
            return result;
        }

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) {
            result.status       = 'Error';
            result.errorMessage = 'Unknown object: ' + objectApiName;
            return result;
        }

        SObject record = objType.newSObject(recordId);

        // Set loop-prevention flag first
        try {
            record.put(SyncConstants.SYNC_IN_PROGRESS_FIELD, true);
        } catch (Exception e) {
            // Field may not exist on this object — proceed without it
        }

        // Apply resolved field values
        for (String field : resolvedValues.keySet()) {
            try {
                record.put(field, resolvedValues.get(field));
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'Could not set field ' + field + ': ' + e.getMessage());
            }
        }

        Database.SaveResult sr = Database.update(record, false);

        if (sr.isSuccess()) {
            // Reset loop-prevention flag
            SObject resetRecord = objType.newSObject(recordId);
            try {
                resetRecord.put(SyncConstants.SYNC_IN_PROGRESS_FIELD, false);
                Database.update(resetRecord, false);
            } catch (Exception e) { /* ignore — best effort */ }

            result.status = 'Applied';
        } else {
            result.status       = 'Error';
            result.errorMessage = sr.getErrors()[0].getMessage();
        }

        return result;
    }

    /**
     * Applies resolved values to a remote org via REST API.
     * Uses Named Credential to authenticate.
     */
    public static ApplyResult applyRemote(String namedCredential,
                                           String objectApiName,
                                           String recordId,
                                           Map<String, Object> resolvedValues) {
        ApplyResult result = new ApplyResult(recordId);
        if (resolvedValues.isEmpty()) {
            result.status = 'NoChange';
            return result;
        }

        // Mark as sync-in-progress in payload
        resolvedValues.put(SyncConstants.SYNC_IN_PROGRESS_FIELD, true);

        String endpoint = 'callout:' + namedCredential
            + '/services/data/v59.0/sobjects/' + objectApiName + '/' + recordId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(resolvedValues));
        req.setTimeout(30000);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 204) {
                result.status = 'Applied';
                // Reset the flag with a second PATCH
                resetRemoteFlag(namedCredential, objectApiName, recordId);
            } else {
                result.status       = 'Error';
                result.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
            }
        } catch (Exception e) {
            result.status       = 'Error';
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    private static void resetRemoteFlag(String namedCredential,
                                         String objectApiName,
                                         String recordId) {
        String endpoint = 'callout:' + namedCredential
            + '/services/data/v59.0/sobjects/' + objectApiName + '/' + recordId;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setBody('{"' + SyncConstants.SYNC_IN_PROGRESS_FIELD + '":false}');
        req.setTimeout(10000);
        try { new Http().send(req); } catch (Exception e) { /* best effort */ }
    }

    public class ApplyResult {
        public String recordId;
        public String status;        // Applied | NoChange | Error
        public String errorMessage;
        public ApplyResult(String id) { this.recordId = id; }
    }
}
