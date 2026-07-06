# Multi-Org Data Sync Engine - Salesforce Metadata

This directory contains the complete Salesforce data model for the Multi-Org Data Sync Engine, organized in Salesforce DX format.

## Directory Structure

```
force-app/main/default/
├── objects/
│   ├── SyncEvent__c/                    # Staging table for sync events
│   │   ├── SyncEvent__c.object-meta.xml
│   │   └── fields/
│   │       ├── SourceOrg__c.field-meta.xml
│   │       ├── ObjectApiName__c.field-meta.xml
│   │       ├── RecordId__c.field-meta.xml
│   │       ├── ChangeType__c.field-meta.xml
│   │       ├── CommitTimestamp__c.field-meta.xml
│   │       ├── CommitNumber__c.field-meta.xml
│   │       ├── ChangedFields__c.field-meta.xml
│   │       ├── PayloadJSON__c.field-meta.xml
│   │       ├── Status__c.field-meta.xml
│   │       └── Notes__c.field-meta.xml
│   │
│   ├── SyncedRecordSnapshot__c/         # Baseline state for conflict detection
│   │   ├── SyncedRecordSnapshot__c.object-meta.xml
│   │   └── fields/
│   │       ├── RecordId__c.field-meta.xml (ExternalId)
│   │       ├── ObjectApiName__c.field-meta.xml
│   │       ├── SnapshotJSON__c.field-meta.xml
│   │       ├── LastSyncedAt__c.field-meta.xml
│   │       └── SnapshotVersion__c.field-meta.xml
│   │
│   └── SyncAuditLog__c/                 # Audit trail
│       ├── SyncAuditLog__c.object-meta.xml
│       └── fields/
│           ├── ObjectApiName__c.field-meta.xml
│           ├── RecordId__c.field-meta.xml
│           ├── FieldName__c.field-meta.xml
│           ├── SourceOrg__c.field-meta.xml
│           ├── TargetOrg__c.field-meta.xml
│           ├── Strategy__c.field-meta.xml
│           ├── Outcome__c.field-meta.xml
│           ├── SnapshotValue__c.field-meta.xml
│           ├── OrgAValue__c.field-meta.xml
│           ├── OrgBValue__c.field-meta.xml
│           ├── ResolvedValue__c.field-meta.xml
│           ├── ApplyStatus__c.field-meta.xml
│           ├── ApplyError__c.field-meta.xml
│           ├── SyncedAt__c.field-meta.xml
│           ├── ManualResolutionBy__c.field-meta.xml
│           └── ManualResolutionAt__c.field-meta.xml
│
└── customMetadata/
    ├── SyncFieldPriorityConfig__mdt.object-meta.xml
    ├── SyncFieldPriorityConfig.md        # Sample metadata record
    └── fields/
        ├── ObjectApiName__c.md-meta.xml
        ├── FieldApiName__c.md-meta.xml
        └── WinningOrg__c.md-meta.xml
```

## Deployment

### Option 1: Using Salesforce DX CLI

```bash
# Authenticate to your org
sfdx auth:web:login -a MyOrg

# Deploy to the org
sfdx deploy --sourcepath force-app/main/default --targetusername MyOrg --wait 10

# Or deploy a specific object
sfdx deploy --sourcepath force-app/main/default/objects/SyncEvent__c --targetusername MyOrg
```

### Option 2: Using VS Code Salesforce Extension

1. Right-click on the `force-app` folder
2. Select "Deploy Source to Org"
3. Select your target org

### Option 3: Manual Deployment (Using Setup)

1. In Salesforce, navigate to Setup
2. Create each custom object manually using the field definitions provided
3. Or use the Metadata API with your deployment tool of choice

## Custom Objects Overview

### 1. SyncEvent__c (Staging Table)

**Purpose:** Captures incoming changes from CDC triggers on synced objects.

**Key Fields:**
- `SourceOrg__c` (Text 10) - OrgA or OrgB
- `ObjectApiName__c` (Text 100) - Object type (Account, Contact, etc.)
- `RecordId__c` (Text 18) - Record ID from source org
- `ChangeType__c` (Picklist) - CREATE, UPDATE, DELETE, UNDELETE
- `CommitTimestamp__c` (DateTime) - CDC commit timestamp
- `CommitNumber__c` (Number) - CDC sequence number
- `ChangedFields__c` (Long Text) - Comma-separated field names
- `PayloadJSON__c` (Long Text) - Field → value JSON payload
- `Status__c` (Picklist) - Pending, Processing, Conflict, ManualReview, Applied, Error
- `Notes__c` (Long Text) - Error messages or manual notes

**Record Lifecycle:**
1. Created by CDC trigger handler (Status = Pending)
2. Deduplicated if multiple edits to same record
3. Diffed against snapshot to detect conflicts
4. Resolved using appropriate strategy
5. Applied to target org
6. Audit trail recorded

### 2. SyncedRecordSnapshot__c (Baseline State)

**Purpose:** Stores the last known good state of synced records for conflict detection.

**Key Fields:**
- `RecordId__c` (Text 18, ExternalId) - Unique identifier for upsert
- `ObjectApiName__c` (Text 100) - SObject type
- `SnapshotJSON__c` (Long Text) - Field → value state in JSON format
- `LastSyncedAt__c` (DateTime) - Timestamp of last successful sync
- `SnapshotVersion__c` (Number) - Monotonic counter for versioning

**Usage:**
- Updated after every successful sync
- Used to detect conflicts by comparing incoming changes
- Supports upsert by RecordId external ID

### 3. SyncAuditLog__c (Audit Trail)

**Purpose:** Immutable record of every sync decision and outcome.

**Key Fields:**
- `ObjectApiName__c` (Text 100) - Synced object type
- `RecordId__c` (Text 18) - Record identifier
- `FieldName__c` (Text 100) - Field being synced
- `SourceOrg__c` (Text 10) - Origin of change
- `TargetOrg__c` (Text 100) - Destination org
- `Strategy__c` (Text 50) - Resolution strategy used
- `Outcome__c` (Text 50) - Applied, Rejected, ManualReview
- `SnapshotValue__c` (Text 255) - Baseline value
- `OrgAValue__c` (Text 255) - Org A's value
- `OrgBValue__c` (Text 255) - Org B's value
- `ResolvedValue__c` (Text 255) - Value that won
- `ApplyStatus__c` (Text 20) - Success or Error
- `ApplyError__c` (Long Text) - API error if failed
- `SyncedAt__c` (DateTime) - Execution timestamp
- `ManualResolutionBy__c` (Lookup User) - User who resolved conflict
- `ManualResolutionAt__c` (DateTime) - Timestamp of manual resolution

**Audit Trail Usage:**
- One record per field that was synced
- Supports compliance and troubleshooting
- Tracks who made manual resolutions

### 4. SyncFieldPriorityConfig__mdt (Custom Metadata Type)

**Purpose:** Declarative configuration for per-field resolution priority.

**Key Fields:**
- `ObjectApiName__c` (Text) - Target object (e.g., Account)
- `FieldApiName__c` (Text) - Field name (e.g., AnnualRevenue)
- `WinningOrg__c` (Picklist) - OrgA or OrgB

**Sample Records:**
```
Account.AnnualRevenue   → OrgA  (Finance owns pricing)
Account.Description     → OrgB  (Partners own descriptions)
Contact.Phone           → OrgA  (Support owns contact info)
```

**Update Without Deployment:**
- Add/edit records directly in Setup → Custom Metadata Types
- No code deployment required
- Changes take effect immediately in the sync engine

## Additional Required Setup

### 1. SyncInProgress__c Flag

Add a Boolean field to every synced object (Account, Contact, Opportunity, etc.):

**Field Definition:**
- API Name: `SyncInProgress__c`
- Type: Boolean
- Default Value: `false`
- Description: Flag to prevent CDC loop-back events

**Purpose:** Prevents infinite sync loops by indicating when system is applying a change.

### 2. CDC Triggers

Create change event triggers for each synced object:

```apex
trigger AccountSyncCapture on AccountChangeEvent (after insert) {
    SyncEventCaptureHandler.handle(Trigger.new, 'Account');
}
```

### 3. Named Credentials

Set up mutual trust between orgs:

- `SyncEngine_OrgA` - In Org B, pointing to Org A
- `SyncEngine_OrgB` - In Org A, pointing to Org B
- Authentication: OAuth with API user account

## Deployment Checklist

- [ ] Deploy custom objects and fields to both orgs
- [ ] Add `SyncInProgress__c` Boolean field to all synced objects
- [ ] Enable Change Data Capture on synced objects
- [ ] Create Named Credentials for inter-org communication
- [ ] Deploy Apex trigger handlers
- [ ] Deploy batch jobs and scheduler
- [ ] Deploy LWC conflict resolution dashboard
- [ ] Create `SyncFieldPriorityConfig__mdt` records for field ownership
- [ ] Bootstrap `SyncedRecordSnapshot__c` with existing records
- [ ] Schedule the `SyncOrchestratorScheduler` (e.g., every 10 minutes)
- [ ] Test demo scenario (edit same record in both orgs)

## Related Documentation

See `/docs/SOLUTION_DESIGN.md` for:
- Complete architecture overview
- Process flow details
- Conflict resolution strategies
- Implementation guide
- Demo scenario
- Business value and use cases
