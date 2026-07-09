# Multi-Org Sync Engine - Complete Setup Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Phase 1: Pre-Deployment Setup](#phase-1-pre-deployment-setup)
3. [Phase 2: Deploy the Package](#phase-2-deploy-the-package)
4. [Phase 3: Post-Deployment Configuration](#phase-3-post-deployment-configuration)
5. [Phase 4: Enable Change Data Capture](#phase-4-enable-change-data-capture)
6. [Phase 5: Set Up Named Credentials](#phase-5-set-up-named-credentials)
7. [Phase 6: Add SyncInProgress Field](#phase-6-add-syncinprogress-field)
8. [Phase 7: Create CDC Triggers](#phase-7-create-cdc-triggers)
9. [Phase 8: Configure Field Priorities](#phase-8-configure-field-priorities)
10. [Phase 9: Schedule Orchestrator](#phase-9-schedule-orchestrator)
11. [Phase 10: Add Dashboard](#phase-10-add-dashboard)
12. [Phase 11: Initial Data Sync](#phase-11-initial-data-sync)
13. [Phase 12: Testing & Validation](#phase-12-testing--validation)

---

## Prerequisites

### Requirements
- **2 Salesforce organizations** (Org A and Org B) to sync
- **Production or Sandbox orgs** - Change Data Capture requires Production or Sandbox
- **System Administrator** access in both orgs
- **API Enabled** - Ensure API access is enabled for users making changes
- **Sufficient API Limits** - Multiple API calls per sync operation

### Check Your Edition
CDC is available on:
- Production orgs (all editions)
- Full Sandbox
- Partial Copy Sandbox
- Developer orgs

**Note:** CDC is NOT available on free trials or metadata-only sandboxes

---

## Phase 1: Pre-Deployment Setup

### Step 1.1: Identify Synced Objects

Decide which objects should be synchronized:

**Common choices:**
- Account
- Contact
- Opportunity
- Lead
- Custom objects

**Example for this guide:** Account

### Step 1.2: Grant Deployment Permissions

In **both orgs**, ensure your deployment user has:
- "Deploy Metadata" permission
- API access enabled
- "Create Scratch Orgs" or equivalent

### Step 1.3: Prepare Org Connection

```bash
# Log in to Org A
sfdx auth:web:login --alias OrgA --instance-url https://login.salesforce.com

# Log in to Org B
sfdx auth:web:login --alias OrgB --instance-url https://login.salesforce.com

# Verify connections
sfdx org:list
```

---

## Phase 2: Deploy the Package

### Step 2.1: Deploy Using CLI

```bash
# Navigate to project directory
cd /path/to/sfdc-multi-org-sync

# Deploy to Org A
sfdx project deploy start --source-dir force-app/main/default --target-org OrgA

# Deploy to Org B
sfdx project deploy start --source-dir force-app/main/default --target-org OrgB
```

### Step 2.2: Verify Deployment

Check deployment succeeded:

```bash
sfdx project deploy report --job-id <deployment-id> --target-org OrgA
```

**Expected deployed metadata:**
- ✓ 3 Custom Objects (SyncEvent__c, SyncAuditLog__c, SyncedRecordSnapshot__c)
- ✓ 10+ Apex Classes
- ✓ 1 LWC Component (syncDashboard)
- ✓ Constants and Utilities

---

## Phase 3: Post-Deployment Configuration

### Step 3.1: Create Permission Set (Optional)

In **both orgs**, create a Permission Set for sync users:

1. Go to **Setup → Permission Sets**
2. Click **New**
3. Name: `SyncUser`
4. Grant permissions:
   - Object Permissions
     - SyncEvent__c: Create, Read, Update
     - SyncAuditLog__c: Create, Read
     - SyncedRecordSnapshot__c: Create, Read, Update, Upsert
     - Account: Read, Update (or your synced objects)
   - Apex: 
     - SyncDashboardController
     - SyncApplyEngine
     - SyncDeduplicator
     - SyncSnapshotDiffer
     - SyncConflictResolver
     - SyncOrchestratorBatch
     - SyncEventCaptureHandler
5. Click **Save**
6. Assign permission set to sync users

### Step 3.2: Verify Custom Objects

In **both orgs**, verify custom objects were created:

1. Go to **Setup → Custom Objects**
2. Verify these exist:
   - SyncEvent__c
   - SyncAuditLog__c
   - SyncedRecordSnapshot__c

---

## Phase 4: Enable Change Data Capture

**In BOTH Orgs**, enable CDC on Account (or your synced object):

### Step 4.1: Enable CDC on Objects

1. Go to **Setup → Change Data Capture**
2. Under "Change Data Capture", click **Edit**
3. In left column "Available Entities", find **Account**
4. Click arrow to move to "Selected Entities"
5. Click **Save**

**Note:** CDC changes take effect within 15 minutes

### Step 4.2: Verify CDC is Active

```bash
# Query CDC status
sfdx data:query --query "SELECT Id, Name FROM EntityDefinition WHERE QualifiedApiName = 'Account'" --target-org OrgA
```

---

## Phase 5: Set Up Named Credentials

Named Credentials allow cross-org communication via OAuth.

### Step 5.1: In Org A (to call Org B)

1. Go to **Setup → Named Credentials**
2. Click **New Named Credential**
3. Configure:
   - **Label:** `SyncEngine_OrgB`
   - **URL:** `https://yourorgbinstance.salesforce.com`
   - **Authentication Protocol:** OAuth 2.0
   - **Authentication Provider:** (Create new - see Step 5.3)
   - **Scope:** `api full refresh_token`
   - **Allow Refresh:** Checked
   - **Generate Authorization Header:** Checked
4. Click **Save**

### Step 5.2: In Org B (to call Org A)

1. Go to **Setup → Named Credentials**
2. Click **New Named Credential**
3. Configure:
   - **Label:** `SyncEngine_OrgA`
   - **URL:** `https://yourorgainstance.salesforce.com`
   - **Authentication Protocol:** OAuth 2.0
   - **Authentication Provider:** (Create new - see Step 5.3)
   - **Scope:** `api full refresh_token`
4. Click **Save**

### Step 5.3: Create Authentication Provider

**In Org A** (create provider to authenticate Org B):

1. Go to **Setup → Auth Providers**
2. Click **New**
3. Configure:
   - **Provider Type:** Salesforce
   - **Name:** `OrgB_Auth`
   - **Client Id:** Get from Org B's Connected App (Step 5.4)
   - **Client Secret:** Get from Org B's Connected App
   - **Authorize Endpoint:** `https://yourorgbinstance.salesforce.com/services/oauth2/authorize`
   - **Token Endpoint:** `https://yourorgbinstance.salesforce.com/services/oauth2/token`
4. Click **Save**

**Repeat in Org B** for Org A's auth provider

### Step 5.4: Create Connected App in Org B

1. Go to **Setup → App Manager**
2. Click **New Connected App**
3. Configure:
   - **Connected App Name:** `SyncEngine_OrgA`
   - **API Name:** `SyncEngine_OrgA`
   - **Contact Email:** Your email
   - **Enable OAuth Settings:** Checked
   - **Callback URL:** `https://login.salesforce.com/services/oauth2/callback`
   - **Selected OAuth Scopes:**
     - Full access (full)
     - Refresh token validity (refresh_token)
     - Access your basic information (id)
     - Access your profile information (profile)
     - Perform requests on your behalf (api)
4. Click **Save**
5. Copy Client ID and Client Secret to Org A's Auth Provider

**Repeat for Org A's Connected App**

### Step 5.5: Test Named Credentials

```bash
# Test connection from Org A to Org B
sfdx data:query --query "SELECT COUNT() FROM Account" --target-org OrgB
```

---

## Phase 6: Add SyncInProgress Field

Add a boolean field to Account (and any other synced objects) to prevent sync loops.

### Step 6.1: Create Custom Field in Org A

1. Go to **Setup → Objects and Fields → Object Manager**
2. Select **Account**
3. Click **Fields & Relationships**
4. Click **New**
5. Configure:
   - **Data Type:** Checkbox
   - **Field Label:** `Sync In Progress`
   - **Field Name:** `SyncInProgress__c`
   - **Default Value:** Unchecked
   - **Description:** `Set to true during sync to prevent CDC loop-back`
6. Click **Save**

### Step 6.2: Create in Org B

Repeat the same steps in Org B

### Step 6.3: Deploy to Both Orgs

```bash
# Deploy Account with new field
sfdx project deploy start --source-dir force-app/main/default/objects/Account --target-org OrgA
sfdx project deploy start --source-dir force-app/main/default/objects/Account --target-org OrgB
```

---

## Phase 7: Create CDC Triggers

Create a CDC trigger on Account to capture changes.

### Step 7.1: Create Trigger in Org A

In Org A, create a new Apex trigger:

1. Go to **Setup → Apex Trigger**
2. Click **New**
3. Name: `AccountSyncCapture`
4. Object: Account (select from dropdown)
5. Copy this code:

```apex
trigger AccountSyncCapture on AccountChangeEvent (after insert) {
    SyncEventCaptureHandler.handle(Trigger.new, 'Account');
}
```

6. Click **Save**

### Step 7.2: Create Trigger in Org B

Repeat the same trigger in Org B

### Step 7.3: Deploy Triggers

```bash
sfdx project deploy start --source-dir force-app/main/default/triggers --target-org OrgA
sfdx project deploy start --source-dir force-app/main/default/triggers --target-org OrgB
```

---

## Phase 8: Configure Field Priorities

Create custom metadata records to define field ownership during conflicts.

### Step 8.1: In Org A, Create Metadata Records

1. Go to **Setup → Custom Metadata Types**
2. Find **Sync Field Priority Config**
3. Click **Manage Records**
4. Click **New**
5. Create record:
   - **Label:** Account Annual Revenue
   - **Object API Name:** Account
   - **Field API Name:** AnnualRevenue
   - **Winning Org:** OrgA
   - **Description:** Finance team owns pricing in Org A
6. Click **Save**

7. Click **New** again for second record:
   - **Label:** Account Description
   - **Object API Name:** Account
   - **Field API Name:** Description
   - **Winning Org:** OrgB
   - **Description:** Partner team owns content in Org B
8. Click **Save**

### Step 8.2: Replicate in Org B

Create the same metadata records in Org B

### Step 8.3: Deploy Metadata

```bash
sfdx project deploy start --source-dir force-app/main/default/customMetadata --target-org OrgA
sfdx project deploy start --source-dir force-app/main/default/customMetadata --target-org OrgB
```

---

## Phase 9: Schedule Orchestrator

Schedule the batch job to run periodically.

### Step 9.1: In Org A, Schedule the Batch

1. Go to **Setup → Scheduled Actions** (or search "Scheduled Apex")
2. Click **Schedule Apex**
3. Configure:
   - **Job Name:** `Multi_Org_Sync_Orchestrator`
   - **Apex Class:** `SyncOrchestratorScheduler`
   - **Frequency:** Weekly (or your preferred interval)
   - **Start Date:** Today
   - **End Date:** Leave blank
   - **Preferred Start Time:** Off-peak time (e.g., 2:00 AM)
4. Click **Schedule**

### Step 9.2: In Org B, Schedule the Batch

Repeat the same scheduling in Org B

### Step 9.3: Or Use CRON Schedule (via Execute Anonymous)

```apex
// Execute as Anonymous in Org A
String cron = '0 0 2 * * ?'; // 2:00 AM every day
System.schedule('Multi-Org Sync', cron, new SyncOrchestratorScheduler('FieldPriority'));
```

---

## Phase 10: Add Dashboard

Add the sync monitoring dashboard to your home page or app.

### Step 10.1: Add to Home Page

1. Go to **Home**
2. Click **Edit Page** (pencil icon)
3. In left sidebar, click **+**
4. Search for **Sync Dashboard**
5. Drag component onto page
6. Click **Save**

### Step 10.2: Add to Custom Tab

1. Go to **Setup → Tabs**
2. Click **New** in Lightning Component Tabs
3. Configure:
   - **Lightning Component:** syncDashboard
   - **Tab Label:** Sync Dashboard
   - **Tab Name:** Sync_Dashboard
4. Click **Save**
5. Add to your app navigation

---

## Phase 11: Initial Data Sync

Bootstrap the system with existing data to prevent false conflicts.

### Step 11.1: Create Initial Snapshots

In Org A, execute this Anonymous Apex:

```apex
// Query all existing records and create snapshots
List<Account> accounts = [SELECT Id, Name, AnnualRevenue, Description FROM Account LIMIT 10000];
List<SyncedRecordSnapshot__c> snapshots = new List<SyncedRecordSnapshot__c>();

for (Account acc : accounts) {
    Map<String, Object> payload = new Map<String, Object>{
        'Name' => acc.Name,
        'AnnualRevenue' => acc.AnnualRevenue,
        'Description' => acc.Description
    };
    
    snapshots.add(new SyncedRecordSnapshot__c(
        RecordId__c = acc.Id,
        ObjectApiName__c = 'Account',
        SnapshotJSON__c = JSON.serialize(payload),
        LastSyncedAt__c = Datetime.now(),
        SnapshotVersion__c = System.currentTimeMillis()
    ));
}

upsert snapshots RecordId__c;
System.debug('Created ' + snapshots.size() + ' initial snapshots');
```

### Step 11.2: Replicate in Org B

Run the same code in Org B

### Step 11.3: Verify Snapshots

Query to verify:

```sql
SELECT COUNT() FROM SyncedRecordSnapshot__c
```

Expected result: Same number of records as Account count

---

## Phase 12: Testing & Validation

### Test 12.1: Single Field Change

1. In **Org A**, edit an Account:
   - Change Name to "Test Account A"
   - Save

2. Wait 30 seconds (for scheduler or trigger)

3. Check **Org B**:
   - Name should now be "Test Account A"

4. Check **SyncEvent__c** in Org A:
   - Should have new record with Status = 'Applied'

### Test 12.2: Simultaneous Changes (Conflict)

1. In **Org A**, edit Account Description to "From Org A"
2. **IMMEDIATELY** (within 1 minute), in **Org B**, edit same Account Description to "From Org B"
3. Wait for sync to run
4. Check **SyncAuditLog__c**:
   - Should have entry with Outcome = 'ManualReview'
5. Go to **Sync Dashboard**
   - Conflict should appear in "Pending Conflicts"
6. Click "Accept Org A"
   - Value should resolve to "From Org A" in both orgs

### Test 12.3: Dashboard Functionality

1. Navigate to **Sync Dashboard**
2. Verify:
   - ✓ Stats display correctly
   - ✓ Pending conflicts show
   - ✓ Audit log displays recent changes
   - ✓ "Trigger Sync Now" button works
   - ✓ "Refresh Stats" updates data

### Test 12.4: Error Handling

1. Simulate error by making Account read-only in Org B
2. Trigger sync from Org A
3. Verify error is logged in **SyncAuditLog__c** with ApplyStatus = 'Error'

---

## Troubleshooting

### Issue: No SyncEvent__c records created

**Cause:** CDC not enabled or trigger not firing

**Solution:**
1. Verify CDC is enabled: Setup → Change Data Capture
2. Verify trigger exists: Setup → Apex Triggers
3. Check trigger is active: Dev Console → Logs
4. Make a test change to Account and check logs

### Issue: Conflicts not resolving

**Cause:** SyncInProgress__c field missing or conflict doesn't exist

**Solution:**
1. Verify SyncInProgress__c field exists: Setup → Object Manager → Account
2. Check Named Credentials are configured
3. Verify API permissions for sync user
4. Check SyncApplyEngine logs

### Issue: Dashboard shows no data

**Cause:** User lacks permissions or no sync has run

**Solution:**
1. Assign SyncUser permission set
2. Run sync manually: `Database.executeBatch(new SyncOrchestratorBatch('FieldPriority'), 50)`
3. Check for Apex errors: Setup → Debug Logs
4. Verify custom object permissions

### Issue: Infinite sync loop

**Cause:** SyncInProgress__c not being set/reset properly

**Solution:**
1. Check SyncApplyEngine.applyLocal() is being called
2. Verify CDC trigger is checking SyncInProgress flag
3. Clear SyncInProgress__c: `UPDATE Account SET SyncInProgress__c = false WHERE SyncInProgress__c = true`
4. Restart sync

---

## Configuration Checklist

Use this checklist to verify complete setup:

- [ ] Phase 1: Prerequisites verified
- [ ] Phase 2: Package deployed to both orgs
- [ ] Phase 3: Permission sets created and assigned
- [ ] Phase 4: CDC enabled on Account (and other objects)
- [ ] Phase 5: Named Credentials configured both ways
- [ ] Phase 6: SyncInProgress__c field added to Account
- [ ] Phase 7: CDC triggers created and deployed
- [ ] Phase 8: Field priority metadata records created
- [ ] Phase 9: Scheduler configured
- [ ] Phase 10: Dashboard added to home page
- [ ] Phase 11: Initial snapshots created
- [ ] Phase 12: All tests passed

---

## Next Steps

1. **Monitor:** Watch Sync Dashboard for anomalies
2. **Extend:** Add more objects to sync
3. **Optimize:** Adjust scheduler frequency based on volume
4. **Integrate:** Connect to external systems via Webhooks
5. **Scale:** Add additional orgs

---

**Setup Complete!** Your Multi-Org Sync Engine is ready to synchronize data between your organizations.

For support, refer to:
- `docs/SOLUTION_DESIGN.md` - Architecture details
- `docs/CUSTOM_METADATA_SETUP.md` - Metadata configuration
- `docs/DASHBOARD_GUIDE.md` - Dashboard usage
