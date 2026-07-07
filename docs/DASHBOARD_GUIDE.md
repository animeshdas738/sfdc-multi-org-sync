# Sync Dashboard Guide

## Overview

The **syncDashboard** Lightning Web Component provides a real-time monitoring and management interface for the Multi-Org Sync Engine. It displays sync health metrics, pending conflicts requiring manual review, and a complete audit trail of all sync operations.

## Component Location

**LWC:** `syncDashboard`  
**Controller:** `SyncDashboardController`  
**Available on:** App Pages, Home Pages, Record Pages

## Features

### 1. Sync Health Metrics

Dashboard displays four key metrics updated in real-time:

| Metric | Description |
|--------|-------------|
| **Pending Events** | Number of SyncEvent__c records awaiting processing |
| **Applied Today** | Count of events successfully synced in the last 24 hours |
| **Open Conflicts** | Number of field-level conflicts waiting for manual review |
| **Errors Today** | Count of sync failures in the last 24 hours |
| **Last Sync Run** | Timestamp of the most recent batch job completion |

### 2. Pending Conflicts Table

Displays conflicts requiring manual intervention with:

- **Object** - The SObject type (Account, Contact, etc.)
- **Record ID** - Unique identifier of the conflicted record
- **Field** - The specific field with conflicting values
- **Org A Value** - Current value in Org A
- **Org B Value** - Current value in Org B
- **Snapshot** - Last known good baseline value
- **Action** - Menu to resolve the conflict

#### Resolving Conflicts

Click the action menu for a conflict and choose:

- **Accept Org A** - Apply Org A's value to both orgs
- **Accept Org B** - Apply Org B's value to both orgs
- **View Details** - See detailed conflict information

The resolution is automatically applied and logged in the audit trail.

### 3. Recent Sync Activity (Audit Trail)

Shows the 50 most recent sync operations with:

| Column | Purpose |
|--------|---------|
| **Object** | SObject type that was synced |
| **Record ID** | Record identifier |
| **Field** | Specific field that was synced |
| **Strategy** | Resolution method used (LastWriteWins, FieldPriority, Manual) |
| **Outcome** | Result (Applied, ManualReview, Rejected) |
| **Resolved Value** | The value that was applied |
| **Synced At** | Timestamp of the operation |

## Actions

### Trigger Sync Now

Click the **"Trigger Sync Now"** button to execute an immediate sync cycle instead of waiting for the scheduled batch job.

- Useful when you want to push changes urgently
- Creates a new batch job with "FieldPriority" strategy
- Returns the batch job ID for monitoring

### Refresh Stats

Click **"Refresh Stats"** to manually reload all dashboard data without waiting for the automatic 30-second refresh interval.

## Auto-Refresh

The dashboard automatically refreshes sync data every 30 seconds, keeping metrics current without manual intervention.

## Adding to Your Org

### Method 1: Lightning App Builder

1. Navigate to any App Page or Home Page
2. Click **Edit** (Edit Page icon)
3. Click the **+** button in the left sidebar
4. Search for **"Sync Dashboard"**
5. Drag it onto your page
6. Click **Save**

### Method 2: Record Page

1. Open a record (Account, Contact, etc.)
2. Click the **Setup** icon (gear)
3. Select **Edit Page**
4. Add the **Sync Dashboard** component
5. Save the page

### Method 3: Programmatic

Add to your Lightning App in `app.app`:

```xml
<aura:component>
  <c:syncDashboard />
</aura:component>
```

## Permissions Required

Users viewing this dashboard need:

- **Read** access to `SyncEvent__c`, `SyncAuditLog__c`, `SyncedRecordSnapshot__c`
- **Update** access to `SyncAuditLog__c` (for manual conflict resolution)
- Permission to execute `SyncDashboardController` Apex methods

## Troubleshooting

### Component Not Loading

**Issue:** "Lightning component not found"  
**Solution:** Ensure `syncDashboard` LWC has been deployed to your org

### No Data Displayed

**Issue:** Dashboard shows empty tables  
**Solution:**
1. Ensure CDC triggers are set up on your objects
2. Check that SyncEvent__c records exist in your org
3. Verify user has read permissions on custom objects
4. Run a sync to generate data

### Conflicts Won't Resolve

**Issue:** "Error resolving conflict"  
**Solution:**
1. Verify the record still exists in the org
2. Check user has update permission on the target object
3. Ensure `SyncInProgress__c` field exists on synced objects
4. Check Named Credentials are configured for cross-org access

### Stale Data

**Issue:** Dashboard metrics don't match actual database state  
**Solution:**
1. Click **"Refresh Stats"** button
2. If still stale, the automatic refresh (30 seconds) should catch up
3. Or manually trigger sync to generate fresh events

## Data Model Integration

The dashboard queries three core tables:

```
SyncEvent__c
├─ Status__c (Pending, Applied, Failed, etc.)
├─ CommitTimestamp__c
└─ CreatedDate

SyncAuditLog__c
├─ ObjectApiName__c
├─ RecordId__c
├─ FieldName__c
├─ OrgAValue__c, OrgBValue__c, ResolvedValue__c
├─ Strategy__c
├─ Outcome__c
├─ ManualResolutionAt__c, ManualResolutionBy__c
└─ SyncedAt__c

AsyncApexJob
└─ (for determining last sync timestamp)
```

## Performance Notes

- Dashboard loads up to 50 pending conflicts and 50 audit log entries
- Suitable for orgs with hundreds of sync operations per day
- For very high-volume deployments, consider filtering by date range

## Future Enhancements

Potential improvements:

- Filter conflicts by object type or time range
- Drill-down into record details with field history
- Batch resolution of conflicts
- Custom sync strategy selection from dashboard
- Webhooks to notify external systems of conflicts
- Performance analytics and trend analysis

---

**Last Updated:** July 2026  
**Component Version:** 1.0  
**API Version:** 67.0
