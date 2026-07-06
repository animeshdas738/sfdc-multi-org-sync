# Multi-Org Data Sync Engine

**Solution Design Document**

Bi-directional Salesforce org sync with snapshot-based conflict detection, three resolution strategies, full audit trail, and manual review UI.

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Problem Statement](#problem-statement)
- [Solution Overview](#solution-overview)
- [Architecture & Data Flow](#architecture--data-flow)
- [Data Model](#data-model)
- [Components & Modules](#components--modules)
- [Conflict Resolution Strategies](#conflict-resolution-strategies)
- [Implementation & Setup](#implementation--setup)
- [Demo & Validation Scenario](#demo--validation-scenario)
- [Business Value & Monetization](#business-value--monetization)

---

## Executive Summary

The Multi-Org Data Sync Engine is a production-grade solution for maintaining data consistency across two or more Salesforce organizations. It enables organizations to:

- Synchronize critical data in real-time using Salesforce Change Data Capture (CDC)
- Automatically detect and resolve field-level conflicts with three configurable strategies
- Maintain a complete audit trail of all synchronization events and resolutions
- Provide a manual review interface for complex or contentious changes
- Prevent infinite sync loops through intelligent flag management

The system handles post-acquisition org mergers, partner data synchronization, and multi-region consistency scenarios with minimal manual intervention.

---

## Problem Statement

Organizations managing multiple Salesforce instances face critical challenges:

### Data Divergence
Without synchronization, data in separate orgs diverges over time, creating a single source of truth problem and causing operational friction.

### Conflict Handling
When the same record is edited simultaneously in both orgs, there's no clear mechanism to decide which change should win.

### Sync Loop Risk
Naive two-way sync implementations create infinite loops where applying a change triggers a change event that syncs back.

### Audit & Compliance
Without comprehensive logging, organizations cannot track what was synced, when, by what logic, or who intervened.

---

## Solution Overview

The Multi-Org Data Sync Engine provides a declarative, event-driven synchronization platform built on Salesforce native technologies.

### Key Capabilities

- **Change Data Capture Integration:** CDC triggers on both orgs capture mutations in real-time
- **Deduplication:** Rapid-fire edits to the same record are collapsed to a single sync event
- **Snapshot-Based Diffing:** Changes are compared against the last synced state to detect conflicts at the field level
- **Pluggable Resolution Strategies:** Three out-of-the-box strategies (LastWriteWins, FieldPriority, Manual) with extensibility
- **Safe Application:** The SyncInProgress flag prevents CDC-triggered loop-back events
- **Complete Audit Trail:** Every sync decision is logged with before/after values and resolution rationale
- **Manual Review UI:** Contested changes surface in a Lightning Web Component for human judgment

> **✓ Built on Salesforce Standards**
>
> The solution uses only native Salesforce features (CDC, batch jobs, custom objects, LWC). No third-party middleware or external dependencies required.

---

## Architecture & Data Flow

### High-Level Workflow

```
CDC Trigger (both orgs)
      │
      ▼
SyncEvent__c staging table      ← Source org · record ID · payload · timestamp
      │
SyncDeduplicator                ← Collapses rapid-fire edits to same record
      │
SyncSnapshotDiffer              ← Field-level diff vs last synced state
      │
      ├── No conflict → safeToApply
      └── Conflict detected →
              ├── LastWriteWins   (timestamp decides)
              ├── FieldPriority   (Custom Metadata config per field)
              └── Manual          (queued for human review)
      │
SyncApplyEngine                 ← PATCH to target org; sets SyncInProgress__c
      │                           flag to suppress loop-back CDC event
SyncAuditTrailWriter            ← Before/after/winner/strategy per field
      │
SyncedRecordSnapshot__c updated ← New baseline for next diff cycle
```

### Process Flow Details

#### 1. Change Capture
A CDC trigger fires on a record change in either org. The trigger handler creates a `SyncEvent__c` record containing the source org, object name, record ID, change type (CREATE/UPDATE/DELETE/UNDELETE), field names, and full payload JSON.

#### 2. Deduplication
The `SyncDeduplicator` batch scans `SyncEvent__c` records in Pending status. Multiple events for the same record within a time window are merged into a single event with the union of changed fields.

#### 3. Snapshot Diff
The `SyncSnapshotDiffer` compares the current payload against the last `SyncedRecordSnapshot__c`. For each field, it checks: was this field synced before, and if so, has the other org changed it independently?

#### 4. Conflict Detection & Resolution
If no conflicts are found, the sync is marked `safeToApply`. If a conflict is detected on a field, the configured strategy for that field (or object) is applied to decide the winner.

#### 5. Safe Application
The `SyncApplyEngine` sets `SyncInProgress__c = true` on the target record, applies the PATCH via REST API, and resets the flag to `false`. This prevents the update from triggering a CDC event that cycles back.

#### 6. Audit Logging
The `SyncAuditTrailWriter` creates a `SyncAuditLog__c` record for every field that was part of the sync, capturing before/after values, the resolution strategy applied, and the outcome.

#### 7. Snapshot Update
Finally, the `SyncedRecordSnapshot__c` is updated with the new field values and the sync timestamp, establishing the baseline for the next cycle.

---

## Data Model

The solution defines four custom objects and one custom metadata type to manage the sync state and audit trail.

### SyncEvent__c (Staging Table)

Captures incoming changes from CDC triggers.

| Field | Type | Purpose |
|-------|------|---------|
| `SourceOrg__c` | Text(10) | OrgA or OrgB identifier |
| `ObjectApiName__c` | Text(100) | Synced object (e.g., Account, Contact) |
| `RecordId__c` | Text(18) | Record ID from source org |
| `ChangeType__c` | Picklist | CREATE, UPDATE, DELETE, UNDELETE |
| `CommitTimestamp__c` | DateTime | CDC commit timestamp for ordering |
| `CommitNumber__c` | Number(18,0) | CDC ChangeEventHeader sequence |
| `ChangedFields__c` | Long Text Area | Comma-separated field names |
| `PayloadJSON__c` | Long Text Area | Field → new value mapping (JSON) |
| `Status__c` | Picklist | Pending, Processing, Applied, Conflict, ManualReview, Error |
| `Notes__c` | Long Text Area | Error messages or manual notes |

### SyncedRecordSnapshot__c (Baseline State)

Stores the last known good state of synced records to detect conflicts.

| Field | Type | Purpose |
|-------|------|---------|
| `RecordId__c` | Text(18) ExternalId | Unique identifier for upsert |
| `ObjectApiName__c` | Text(100) | SObject type |
| `SnapshotJSON__c` | Long Text Area | Field → value state (JSON) |
| `LastSyncedAt__c` | DateTime | Timestamp of last successful sync |
| `SnapshotVersion__c` | Number(18,0) | Monotonic counter for versioning |

### SyncAuditLog__c (Audit Trail)

Immutable record of every sync decision and outcome.

| Field | Type | Purpose |
|-------|------|---------|
| `ObjectApiName__c` | Text(100) | Synced object type |
| `RecordId__c` | Text(18) | Record identifier |
| `FieldName__c` | Text(100) | Field being synced |
| `SourceOrg__c` | Text(10) | Origin of change |
| `TargetOrg__c` | Text(100) | Destination org |
| `Strategy__c` | Text(50) | LastWriteWins, FieldPriority, Manual |
| `Outcome__c` | Text(50) | Applied, Rejected, ManualReview |
| `SnapshotValue__c` | Text(255) | Baseline value before sync |
| `OrgAValue__c` | Text(255) | Org A's current value |
| `OrgBValue__c` | Text(255) | Org B's current value |
| `ResolvedValue__c` | Text(255) | Value chosen by resolution strategy |
| `ApplyStatus__c` | Text(20) | Success, Error |
| `ApplyError__c` | Long Text Area | API error message if applicable |
| `SyncedAt__c` | DateTime | When sync was executed |
| `ManualResolutionBy__c` | Lookup(User) | User who resolved a manual conflict |
| `ManualResolutionAt__c` | DateTime | When manual resolution occurred |

### SyncFieldPriorityConfig__mdt (Configuration)

Custom Metadata Type defining per-field resolution rules.

| Field | Type | Purpose |
|-------|------|---------|
| `ObjectApiName__c` | Text | Target object (e.g., Account) |
| `FieldApiName__c` | Text | Field name (e.g., AnnualRevenue) |
| `WinningOrg__c` | Picklist | OrgA or OrgB — which org's value always wins |

### SyncInProgress__c Flag (Required on All Synced Objects)

A Boolean field (default `false`) must be added to every object being synced. It is set to `true` before applying changes and reset to `false` after. The CDC trigger checks this flag and skips creating a `SyncEvent__c` if it is true, preventing loop-back cycles.

> **ℹ Field Creation Requirement**
>
> Adding `SyncInProgress__c` requires a deployment to the target org. It is a one-time setup cost but is critical to system stability.

---

## Components & Modules

### Apex Components

#### Trigger Handler: SyncEventCaptureHandler

**Responsibility:** Listens to CDC triggers on synced objects and creates `SyncEvent__c` records.

**Key Logic:**
- Check `SyncInProgress__c` flag; if true, abort (prevent loop-back)
- Extract field changes from CDC ChangeEventHeader
- Serialize changed fields to JSON payload
- Create `SyncEvent__c` with status Pending

#### Batch Job: SyncDeduplicator

**Responsibility:** Consolidates rapid-fire edits to the same record into a single sync event.

**Key Logic:**
- Query `SyncEvent__c` with status Pending, ordered by CommitNumber
- Group by (SourceOrg, ObjectApiName, RecordId)
- Merge PayloadJSON of all events in the group
- Update first event with merged payload and deduplicated fields
- Delete duplicate events

#### Batch Job: SyncSnapshotDiffer

**Responsibility:** Detects field-level conflicts by comparing incoming changes against the last synced snapshot.

**Key Logic:**
- For each `SyncEvent__c` (Pending → Processing)
- Look up `SyncedRecordSnapshot__c` by RecordId + ObjectApiName
- For each changed field in the payload:
  - If no snapshot exists → no conflict (first sync)
  - If snapshot value matches source org value → no conflict
  - If snapshot value differs from source org value → conflict (other org changed it)
- Mark event status: safeToApply or Conflict

#### Batch Job: SyncResolutionEngine

**Responsibility:** Applies conflict resolution strategies and routes unresolved conflicts to manual review.

**Key Logic:**
- For each event with status Conflict:
  - Look up `SyncFieldPriorityConfig__mdt` for the field
  - If WinningOrg is set → apply FieldPriority strategy
  - Otherwise → apply default LastWriteWins strategy
- If resolution is Manual → set status ManualReview
- Otherwise → set status safeToApply with resolved payload

#### Batch Job: SyncApplyEngine

**Responsibility:** Pushes resolved changes to the target org via REST API and updates the SyncInProgress flag.

**Key Logic:**
- For each event with status safeToApply (Processing):
  - Retrieve the target org's Named Credential
  - Set `SyncInProgress__c = true` on the target record
  - PATCH the resolved fields to the target org
  - Set `SyncInProgress__c = false`
- Handle API errors (network timeout, record locked, etc.) with retry logic
- Update event status to Applied or Error

#### Batch Job: SyncAuditTrailWriter

**Responsibility:** Creates immutable audit log records for every field change.

**Key Logic:**
- For each Applied or Error event:
  - Retrieve the corresponding `SyncedRecordSnapshot__c`
  - For each field in the payload:
    - Extract SnapshotValue (from snapshot) and OrgAValue, OrgBValue (from audit context)
    - Create `SyncAuditLog__c` entry

#### Batch Job: SyncSnapshotUpdater

**Responsibility:** Updates the snapshot baseline after a successful sync.

**Key Logic:**
- For each Applied event:
  - Upsert `SyncedRecordSnapshot__c` using RecordId as external ID
  - Set SnapshotJSON to the applied payload
  - Update LastSyncedAt and increment SnapshotVersion

### LWC Components

#### SyncConflictDashboard

**Purpose:** Displays `SyncEvent__c` records with status ManualReview, allowing users to inspect and resolve conflicts.

**Features:**
- List view of pending conflicts with record name, object, source org, and timestamp
- Click to open detail panel showing before/after comparison
- Field-by-field display of OrgA value, OrgB value, and snapshot baseline
- Action buttons: "Accept Org A", "Accept Org B", "Custom Value"
- After selection, update the event status and trigger immediate sync

### Scheduler

#### SyncOrchestratorScheduler

**Responsibility:** Orchestrates the batch job sequence at a configurable interval (default: every 10 minutes).

**Execution Order:**
1. SyncDeduplicator
2. SyncSnapshotDiffer
3. SyncResolutionEngine
4. SyncApplyEngine
5. SyncAuditTrailWriter
6. SyncSnapshotUpdater

**Configuration:** Accepts a strategy parameter (e.g., 'FieldPriority') that influences conflict resolution defaults.

---

## Conflict Resolution Strategies

When the same field is changed in both orgs since the last sync, a conflict is detected. The system offers three resolution strategies:

### Strategy 1: LastWriteWins

**Decision Logic:** The value with the later `CommitTimestamp__c` is applied to both orgs.

**Use Case:** Default for fields without explicit ownership (e.g., generic metadata fields).

**Strengths:** Simple, deterministic, avoids manual review.

**Weaknesses:** May not reflect business priority; "last to edit wins" can feel arbitrary.

### Strategy 2: FieldPriority

**Decision Logic:** Configured via `SyncFieldPriorityConfig__mdt`. If a field has a `WinningOrg__c` setting, that org's value always wins.

**Use Case:** Fields with clear business ownership (e.g., Finance owns Annual Revenue, Partner team owns Description).

**Configuration Example:**
```
Account.AnnualRevenue → WinningOrg = OrgA
Account.Description   → WinningOrg = OrgB
```

**Strengths:** Reflects business logic; declarative and easy to update without code changes.

**Weaknesses:** Requires upfront configuration; doesn't handle truly contentious conflicts.

### Strategy 3: Manual

**Decision Logic:** The conflict is flagged for human review in the LWC dashboard. A user inspects both values and OrgA value, OrgB value, and the snapshot baseline, then selects which to apply.

**Use Case:** Critical fields or contentious conflicts where business judgment is needed.

**UI Workflow:**
- Dashboard shows record name and the conflicted field
- Side-by-side display: Snapshot | OrgA | OrgB
- User clicks "Accept Org A" or "Accept Org B"
- System updates the event payload and applies immediately
- Audit log records who resolved it and when

**Strengths:** Prevents automatic loss of data; allows informed decisions.

**Weaknesses:** Introduces latency; requires user attention.

### Strategy Selection Logic

The `SyncResolutionEngine` determines which strategy to apply in this order:

1. Check if `SyncFieldPriorityConfig__mdt` has a record for (ObjectApiName, FieldApiName). If yes, use FieldPriority.
2. Check if the scheduler was invoked with strategy parameter 'Manual'. If yes, route to manual review.
3. Otherwise, apply LastWriteWins (default).

> **⚠ Extensibility Note**
>
> The resolution engine is designed to be extended. Additional strategies can be plugged in by implementing an interface and registering in the strategy factory. Examples: Average (for numeric fields), Merge (concatenate both values), Custom (invoke an external API for business logic).

---

## Implementation & Setup

### 1. Enable Change Data Capture on Both Orgs

Navigate to Setup → Change Data Capture and move target objects (e.g., Account, Contact) to the Selected Entities list. This enables CDC triggers to fire on insert/update/delete/undelete.

### 2. Create Named Credentials (Mutual Trust)

Each org must have outbound connectivity to the other:

- **In Org A:** Create Named Credential `SyncEngine_OrgB` pointing to Org B's instance domain with OAuth + REST authentication.
- **In Org B:** Create Named Credential `SyncEngine_OrgA` pointing to Org A's instance domain with OAuth + REST authentication.

Both must be authorized with a user account that has API access and permission to modify synced objects.

### 3. Deploy Custom Objects & Fields

Deploy to both orgs:
- `SyncEvent__c` (staging table)
- `SyncedRecordSnapshot__c` (baseline state)
- `SyncAuditLog__c` (audit trail)
- `SyncFieldPriorityConfig__mdt` (configuration)
- `SyncInProgress__c` boolean field on all synced objects (Account, Contact, etc.)

### 4. Create CDC Triggers

For each synced object, create a trigger:

```apex
trigger AccountSyncCapture on AccountChangeEvent (after insert) {
    SyncEventCaptureHandler.handle(Trigger.new, 'Account');
}

trigger ContactSyncCapture on ContactChangeEvent (after insert) {
    SyncEventCaptureHandler.handle(Trigger.new, 'Contact');
}
```

### 5. Configure Field Priority (Optional)

Create `SyncFieldPriorityConfig__mdt` records to declare field ownership:

| Object | Field | Winning Org | Rationale |
|--------|-------|-------------|-----------|
| Account | AnnualRevenue | OrgA | Finance team owns pricing |
| Account | Description | OrgB | Partner team owns narratives |
| Contact | Phone | OrgA | Customer support owns contact info |

### 6. Deploy Apex Classes & Scheduler

Deploy all Apex components (handlers, batch jobs, scheduler, LWC). Configure the scheduler to run at the desired interval:

```apex
String cron = '0 0/10 * * * ?';  // Every 10 minutes
System.schedule('Multi-Org Sync', cron, new SyncOrchestratorScheduler('FieldPriority'));
```

### 7. Deploy LWC Dashboard

Deploy the `SyncConflictDashboard` LWC to both orgs and add it to the desired app or home page for visibility.

### 8. Initial Data Sync (Bootstrap)

For the first sync, seed `SyncedRecordSnapshot__c` with the current state of all records that should be managed. This establishes the baseline and prevents false conflict detection on the first cycle.

> **✓ Bootstrap Strategy**
>
> Query all existing records from Org A, snapshot them into `SyncedRecordSnapshot__c` on both orgs, and set their SyncInProgress flag. This prevents the first sync event from treating all records as new.

---

## Demo & Validation Scenario

A compelling demo showcases the real-time conflict detection and resolution flow.

### Demo Script

#### 1. Edit Same Record in Both Orgs

In Org A, edit the Account Name to "Acme Corp - Updated A" and save. Within seconds, in Org B, change it to "Acme Corp - Updated B" and save. Both edits happen before the next sync cycle.

#### 2. Staging Table Captures Changes

Refresh the `SyncEvent__c` list. Show two records: one from Org A (source) and one from Org B (source). Both have Status = Pending, with their respective payloads.

#### 3. Sync Cycle Runs

The scheduler runs (or manually trigger the SyncOrchestratorScheduler). Watch the batch jobs execute in sequence. Refresh the list to see Status changes: Pending → Processing → Conflict → ManualReview.

#### 4. Conflict Appears in Dashboard

Open the `SyncConflictDashboard` LWC. The conflicted account appears with a red flag. Click to expand and see a side-by-side comparison:
- Snapshot Value: "Acme Corp" (last synced baseline)
- Org A Value: "Acme Corp - Updated A"
- Org B Value: "Acme Corp - Updated B"

#### 5. Resolve Manually

Click "Accept Org A". The system immediately applies "Acme Corp - Updated A" to Org B. The `SyncEvent__c` status updates to Applied.

#### 6. Audit Trail Confirms Decision

Open the `SyncAuditLog__c` for this record. Show the entry with:
- FieldName: "Name"
- SourceOrg: "OrgA"
- Strategy: "Manual"
- OrgAValue: "Acme Corp - Updated A"
- OrgBValue: "Acme Corp - Updated B"
- ResolvedValue: "Acme Corp - Updated A"
- ManualResolutionBy: (current user)
- ManualResolutionAt: (timestamp)

#### 7. Orgs Converge

Verify that both Org A and Org B now have the same Account Name. Show the side-by-side comparison in Org B to confirm the sync.

### Key Talking Points

- **Real-time Detection:** CDC triggers captured changes within seconds; no polling or scheduled imports required.
- **Field-Level Conflict Awareness:** The system knows which field changed in which org and compared against the baseline.
- **Flexible Resolution:** Three strategies (LastWriteWins, FieldPriority, Manual) cater to different business scenarios.
- **Complete Audit:** Every decision is logged with before/after values and who made the call.
- **No Infinite Loops:** The SyncInProgress flag ensures that applying a change doesn't trigger a loop-back event.

---

## Business Value & Monetization

The Multi-Org Data Sync Engine addresses several high-value use cases:

### Post-Acquisition Org Merge
**Price:** $10K – $30K

When two companies merge and must consolidate their Salesforce orgs, this solution provides a controlled way to unify data, detect conflicts, and maintain audit trails during the transition.

### Ongoing Partner Data Sync
**Price:** $5K setup + $500/month

MSPs, resellers, and partners often need to maintain synced data between their org and the customer's org. This solution makes it operationally feasible.

### Multi-Region Org Consistency
**Price:** $8K – $20K

Large enterprises with regional Salesforce instances can use this engine to maintain consistent master data across regions while respecting local overrides.

### Data Migration & Validation
**Price:** Variable

Syncing data from a legacy system to Salesforce and validating convergence is a common engagement. This solution provides visibility into what was synced and why.

### Operational Benefits

- **Reduces Manual Data Reconciliation:** Automated sync means fewer spreadsheets and manual corrections.
- **Speeds Time-to-Value in M&A:** Post-acquisition integration is faster and more transparent.
- **Enables Partner Ecosystem:** Makes it easier to onboard and support partners who need bidirectional data flow.
- **Compliance & Auditability:** Complete audit trail satisfies compliance requirements and internal audits.

### Revenue Model

- **One-Time Implementation:** Charged based on scope (number of objects, complexity of conflict resolution logic).
- **Ongoing Support & Monitoring:** Monthly fee for monitoring sync health, handling edge cases, and supporting the dashboard.
- **Consulting Hours:** Configuration (field priority rules), custom strategies, integration with other systems.

---

## Summary

The Multi-Org Data Sync Engine is a production-ready, event-driven solution for keeping multiple Salesforce organizations in sync. It combines CDC technology, snapshot-based diffing, pluggable conflict resolution, and comprehensive audit logging to deliver a reliable, transparent data synchronization platform.

Built entirely on Salesforce native features, it requires no middleware or external dependencies. The solution is deployable, maintainable, and extensible for real-world scenarios ranging from post-acquisition integration to ongoing partner data management.

### Next Steps

- Identify target use case(s) and scope (objects, fields, orgs)
- Review and customize `SyncFieldPriorityConfig__mdt` records for your business logic
- Execute the demo scenario to validate architecture and get stakeholder buy-in
- Plan implementation timeline and resource allocation

---

**Multi-Org Data Sync Engine — Solution Design Document**

© 2026. All rights reserved. For implementation inquiries, contact your Salesforce specialist.
