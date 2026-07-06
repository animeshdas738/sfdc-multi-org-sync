/**
 * SyncConstants
 * Central registry for the Multi-org Data Sync Engine.
 * Import everywhere — never hardcode these strings.
 */
public class SyncConstants {

    // ── Org identifiers (set these per-deployment) ────────────────────
    public static final String ORG_A = 'OrgA';
    public static final String ORG_B = 'OrgB';

    // ── Event statuses ───────────────────────────────────────────────
    public static final String EVT_PENDING    = 'Pending';
    public static final String EVT_PROCESSING = 'Processing';
    public static final String EVT_APPLIED    = 'Applied';
    public static final String EVT_CONFLICTED = 'Conflicted';
    public static final String EVT_SKIPPED    = 'Skipped';
    public static final String EVT_FAILED     = 'Failed';

    // ── Conflict resolution strategies ──────────────────────────────
    public static final String STRATEGY_LAST_WRITE   = 'LastWriteWins';
    public static final String STRATEGY_FIELD_PRIORITY = 'FieldPriority';
    public static final String STRATEGY_MANUAL       = 'Manual';

    // ── Conflict outcomes ────────────────────────────────────────────
    public static final String OUTCOME_ORG_A_WINS    = 'OrgAWins';
    public static final String OUTCOME_ORG_B_WINS    = 'OrgBWins';
    public static final String OUTCOME_MERGED        = 'Merged';
    public static final String OUTCOME_MANUAL        = 'PendingManualReview';

    // ── Change types (mirrors CDC ChangeEventHeader.changeType) ──────
    public static final String CHANGE_CREATE = 'CREATE';
    public static final String CHANGE_UPDATE = 'UPDATE';
    public static final String CHANGE_DELETE = 'DELETE';
    public static final String CHANGE_UNDELETE = 'UNDELETE';

    // ── Loop-prevention custom field (add this to every synced object) ──
    // Boolean field: SyncInProgress__c
    // When true, the CDC trigger skips creating a SyncEvent__c
    public static final String SYNC_IN_PROGRESS_FIELD = 'SyncInProgress__c';

    // ── Named credential for the partner/remote org REST API ─────────
    public static final String NAMED_CREDENTIAL_ORG_A = 'SyncEngine_OrgA';
    public static final String NAMED_CREDENTIAL_ORG_B = 'SyncEngine_OrgB';

    // ── Deduplication window: collapse events within N minutes ───────
    public static final Integer DEDUP_WINDOW_MINUTES = 5;

    // ── Max fields stored in snapshot JSON ──────────────────────────
    public static final Integer MAX_SNAPSHOT_FIELDS = 200;

    public class SyncException extends Exception {}
}
