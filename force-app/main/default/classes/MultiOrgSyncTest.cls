/**
 * MultiOrgSyncTest
 * Full test coverage for the Multi-org Data Sync Engine.
 */
@IsTest
private class MultiOrgSyncTest {

    // ── Helpers ──────────────────────────────────────────────────────
    private static SyncEvent__c makeEvent(String sourceOrg, String recordId,
                                           String objectApiName,
                                           Map<String, Object> payload,
                                           Long commitNum) {
        return new SyncEvent__c(
            SourceOrg__c       = sourceOrg,
            RecordId__c        = recordId,
            ObjectApiName__c   = objectApiName,
            ChangeType__c      = SyncConstants.CHANGE_UPDATE,
            CommitNumber__c    = commitNum,
            CommitTimestamp__c = Datetime.now().addMinutes(-(Integer) commitNum),
            PayloadJSON__c     = JSON.serialize(payload),
            ChangedFields__c   = JSON.serialize(payload.keySet()),
            Status__c          = SyncConstants.EVT_PENDING
        );
    }

    private static SyncedRecordSnapshot__c makeSnapshot(String recordId,
                                                          String objectApiName,
                                                          Map<String, Object> values) {
        return new SyncedRecordSnapshot__c(
            RecordId__c       = recordId,
            ObjectApiName__c  = objectApiName,
            SnapshotJSON__c   = JSON.serialize(values),
            LastSyncedAt__c   = Datetime.now().addHours(-1),
            SnapshotVersion__c = 1
        );
    }

    // ── SyncDeduplicator tests ────────────────────────────────────────
    @IsTest
    static void testDeduplicator_keepsLatestCommit() {
        String recordId = '001000000000001';
        List<SyncEvent__c> events = new List<SyncEvent__c>{
            makeEvent(SyncConstants.ORG_A, recordId, 'Account',
                new Map<String,Object>{'Name'=>'Old'}, 1),
            makeEvent(SyncConstants.ORG_A, recordId, 'Account',
                new Map<String,Object>{'Name'=>'New'}, 5)
        };
        insert events;

        Test.startTest();
        List<SyncEvent__c> deduped = SyncDeduplicator.deduplicate(events);
        Test.stopTest();

        System.assertEquals(1, deduped.size(), 'Should keep only one event');
        Map<String,Object> payload =
            (Map<String,Object>) JSON.deserializeUntyped(deduped[0].PayloadJSON__c);
        System.assertEquals('New', payload.get('Name'), 'Should keep latest value');

        Integer skippedCount = [
            SELECT COUNT() FROM SyncEvent__c WHERE Status__c = :SyncConstants.EVT_SKIPPED
        ];
        System.assertEquals(1, skippedCount, 'Older event should be marked skipped');
    }

    @IsTest
    static void testDeduplicator_differentRecordsNotMerged() {
        List<SyncEvent__c> events = new List<SyncEvent__c>{
            makeEvent(SyncConstants.ORG_A, '001000000000001', 'Account',
                new Map<String,Object>{'Name'=>'A'}, 1),
            makeEvent(SyncConstants.ORG_A, '001000000000002', 'Account',
                new Map<String,Object>{'Name'=>'B'}, 2)
        };
        insert events;

        Test.startTest();
        List<SyncEvent__c> deduped = SyncDeduplicator.deduplicate(events);
        Test.stopTest();

        System.assertEquals(2, deduped.size(), 'Different records should not be merged');
    }

    // ── SyncSnapshotDiffer tests ──────────────────────────────────────
    @IsTest
    static void testDiff_safeToApplyWhenOnlyOneSideChanged() {
        SyncedRecordSnapshot__c snap = makeSnapshot('001xyz', 'Account',
            new Map<String,Object>{'Name'=>'Old Name', 'Phone'=>'111'});
        insert snap;

        Map<String,Object> orgAPayload = new Map<String,Object>{'Name'=>'New Name'};

        Test.startTest();
        SyncSnapshotDiffer.FieldDiff result = SyncSnapshotDiffer.diff(
            '001xyz', 'Account', orgAPayload, null, snap
        );
        Test.stopTest();

        System.assert(!result.hasConflicts, 'Should have no conflicts');
        System.assert(result.safeToApply.containsKey('Name'),
            'Name change should be safe to apply');
        System.assertEquals('New Name', result.safeToApply.get('Name'));
    }

    @IsTest
    static void testDiff_conflictWhenBothSidesChanged() {
        SyncedRecordSnapshot__c snap = makeSnapshot('001abc', 'Account',
            new Map<String,Object>{'Name'=>'Original'});
        insert snap;

        Map<String,Object> orgAPayload = new Map<String,Object>{'Name'=>'Org A Name'};
        Map<String,Object> orgBPayload = new Map<String,Object>{'Name'=>'Org B Name'};

        Test.startTest();
        SyncSnapshotDiffer.FieldDiff result = SyncSnapshotDiffer.diff(
            '001abc', 'Account', orgAPayload, orgBPayload, snap
        );
        Test.stopTest();

        System.assert(result.hasConflicts, 'Should detect conflict on Name field');
        System.assert(result.conflicts.containsKey('Name'));
        SyncSnapshotDiffer.ConflictDetail cd = result.conflicts.get('Name');
        System.assertEquals('Original', cd.snapshotValue);
        System.assertEquals('Org A Name', cd.orgAValue);
        System.assertEquals('Org B Name', cd.orgBValue);
    }

    @IsTest
    static void testDiff_noConflictWhenBothChangedToSameValue() {
        SyncedRecordSnapshot__c snap = makeSnapshot('001def', 'Account',
            new Map<String,Object>{'Name'=>'Old'});
        insert snap;

        Map<String,Object> payload = new Map<String,Object>{'Name'=>'Same'};

        Test.startTest();
        SyncSnapshotDiffer.FieldDiff result = SyncSnapshotDiffer.diff(
            '001def', 'Account', payload, payload, snap
        );
        Test.stopTest();

        System.assert(!result.hasConflicts,
            'No conflict when both sides changed to the same value');
    }

    @IsTest
    static void testDiff_noSnapshotTreatsAllAsNew() {
        Map<String,Object> orgAPayload = new Map<String,Object>{'Name'=>'Brand New'};

        Test.startTest();
        SyncSnapshotDiffer.FieldDiff result = SyncSnapshotDiffer.diff(
            '001ghi', 'Account', orgAPayload, null, null
        );
        Test.stopTest();

        System.assert(result.safeToApply.containsKey('Name'),
            'Without snapshot, change should be safe to apply');
    }

    // ── SyncConflictResolver tests ────────────────────────────────────
    @IsTest
    static void testLastWriteWins_orgAWinsOnHigherTimestamp() {
        SyncSnapshotDiffer.FieldDiff diff = new SyncSnapshotDiffer.FieldDiff();
        diff.recordId      = '001xxx';
        diff.objectApiName = 'Account';
        diff.conflicts.put('Name',
            new SyncSnapshotDiffer.ConflictDetail('Old', 'A Name', 'B Name'));

        Test.startTest();
        SyncConflictResolver.ResolutionResult result =
            SyncConflictResolver.resolveLastWriteWins(diff, 1000, 500);
        Test.stopTest();

        System.assertEquals('A Name', result.resolvedValues.get('Name'),
            'Org A should win with higher timestamp');
        System.assertEquals(SyncConstants.OUTCOME_ORG_A_WINS,
            result.auditEntries[0].outcome);
    }

    @IsTest
    static void testLastWriteWins_orgBWinsOnHigherTimestamp() {
        SyncSnapshotDiffer.FieldDiff diff = new SyncSnapshotDiffer.FieldDiff();
        diff.recordId      = '001yyy';
        diff.objectApiName = 'Account';
        diff.conflicts.put('Phone',
            new SyncSnapshotDiffer.ConflictDetail('000', '111', '222'));

        Test.startTest();
        SyncConflictResolver.ResolutionResult result =
            SyncConflictResolver.resolveLastWriteWins(diff, 500, 1000);
        Test.stopTest();

        System.assertEquals('222', result.resolvedValues.get('Phone'),
            'Org B should win with higher timestamp');
    }

    @IsTest
    static void testManualResolution_flagsConflictsForReview() {
        SyncSnapshotDiffer.FieldDiff diff = new SyncSnapshotDiffer.FieldDiff();
        diff.recordId      = '001zzz';
        diff.objectApiName = 'Account';
        diff.safeToApply.put('Phone', '12345');
        diff.conflicts.put('Name',
            new SyncSnapshotDiffer.ConflictDetail('Old', 'A Name', 'B Name'));

        Test.startTest();
        SyncConflictResolver.ResolutionResult result =
            SyncConflictResolver.resolveManual(diff);
        Test.stopTest();

        System.assert(result.requiresManualReview);
        System.assert(result.resolvedValues.containsKey('Phone'),
            'Safe fields should still be in resolved values');
        System.assert(!result.resolvedValues.containsKey('Name'),
            'Conflicted field should not be auto-resolved in manual mode');
    }

    // ── SyncApplyEngine tests ─────────────────────────────────────────
    @IsTest
    static void testApplyLocal_success() {
        Account a = new Account(Name = 'Before Sync');
        insert a;

        Test.startTest();
        SyncApplyEngine.ApplyResult result = SyncApplyEngine.applyLocal(
            'Account',
            String.valueOf(a.Id),
            new Map<String,Object>{'Name' => 'After Sync'}
        );
        Test.stopTest();

        System.assertEquals('Applied', result.status);
        Account updated = [SELECT Name FROM Account WHERE Id = :a.Id];
        System.assertEquals('After Sync', updated.Name);
    }

    @IsTest
    static void testApplyLocal_noChangeWhenEmpty() {
        Account a = new Account(Name = 'Unchanged');
        insert a;

        Test.startTest();
        SyncApplyEngine.ApplyResult result = SyncApplyEngine.applyLocal(
            'Account', String.valueOf(a.Id), new Map<String,Object>()
        );
        Test.stopTest();

        System.assertEquals('NoChange', result.status);
    }

    @IsTest
    static void testApplyLocal_unknownObject() {
        Test.startTest();
        SyncApplyEngine.ApplyResult result = SyncApplyEngine.applyLocal(
            'NonExistentObject__z', '001000000000001',
            new Map<String,Object>{'Name' => 'X'}
        );
        Test.stopTest();

        System.assertEquals('Error', result.status);
    }

    // ── SyncSnapshotDiffer.upsertSnapshots test ───────────────────────
    @IsTest
    static void testUpsertSnapshots_createsAndUpdates() {
        List<String> ids      = new List<String>{'001snap001'};
        List<Map<String,Object>> payloads = new List<Map<String,Object>>{
            new Map<String,Object>{'Name'=>'Synced Value'}
        };

        Test.startTest();
        SyncSnapshotDiffer.upsertSnapshots(ids, 'Account', payloads);
        // Upsert again to test update path
        payloads[0].put('Name', 'Updated Value');
        SyncSnapshotDiffer.upsertSnapshots(ids, 'Account', payloads);
        Test.stopTest();

        List<SyncedRecordSnapshot__c> snaps = [
            SELECT SnapshotJSON__c FROM SyncedRecordSnapshot__c
            WHERE RecordId__c = '001snap001'
        ];
        System.assertEquals(1, snaps.size(), 'Should upsert to single record');
        Map<String,Object> stored =
            (Map<String,Object>) JSON.deserializeUntyped(snaps[0].SnapshotJSON__c);
        System.assertEquals('Updated Value', stored.get('Name'));
    }

    // ── Audit trail test ──────────────────────────────────────────────
    @IsTest
    static void testAuditTrailWriter() {
        List<SyncConflictResolver.ConflictLogEntry> entries =
            new List<SyncConflictResolver.ConflictLogEntry>();
        SyncConflictResolver.ConflictLogEntry e =
            new SyncConflictResolver.ConflictLogEntry();
        e.fieldName     = 'Name';
        e.snapshotValue = 'Old';
        e.orgAValue     = 'A';
        e.orgBValue     = 'B';
        e.resolvedValue = 'A';
        e.strategy      = SyncConstants.STRATEGY_LAST_WRITE;
        e.outcome       = SyncConstants.OUTCOME_ORG_A_WINS;
        entries.add(e);

        Test.startTest();
        SyncAuditTrailWriter.write('Account', '001test', SyncConstants.ORG_A,
            SyncConstants.ORG_B, SyncConstants.STRATEGY_LAST_WRITE,
            entries, 'Applied', null);
        Test.stopTest();

        List<SyncAuditLog__c> logs = [
            SELECT FieldName__c, Outcome__c FROM SyncAuditLog__c
            WHERE RecordId__c = '001test'
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Name', logs[0].FieldName__c);
        System.assertEquals(SyncConstants.OUTCOME_ORG_A_WINS, logs[0].Outcome__c);
    }

    // ── Constants test ────────────────────────────────────────────────
    @IsTest
    static void testConstantsNotNull() {
        System.assertNotEquals(null, SyncConstants.ORG_A);
        System.assertNotEquals(null, SyncConstants.STRATEGY_LAST_WRITE);
        System.assertNotEquals(null, SyncConstants.SYNC_IN_PROGRESS_FIELD);
    }
}
