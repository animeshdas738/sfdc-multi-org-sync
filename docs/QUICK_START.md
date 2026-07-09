# Multi-Org Sync - Quick Start Reference

## 🚀 5-Minute Setup Summary

### 1. Deploy Package (2 min)
```bash
sfdx project deploy start --source-dir force-app --target-org OrgA
sfdx project deploy start --source-dir force-app --target-org OrgB
```

### 2. Enable CDC (1 min)
- **In both orgs:** Setup → Change Data Capture
- Select **Account** (your synced object)
- Click **Save**

### 3. Create SyncInProgress Field (1 min)
- **In both orgs:** Setup → Objects → Account → Fields
- **New Field:** 
  - Type: Checkbox
  - Name: `SyncInProgress__c`
  - Default: Unchecked

### 4. Create CDC Trigger (1 min)
- **In both orgs:** Setup → Apex Triggers
- **New Trigger:**
```apex
trigger AccountSyncCapture on AccountChangeEvent (after insert) {
    SyncEventCaptureHandler.handle(Trigger.new, 'Account');
}
```

---

## 🔧 Essential Configuration

### Named Credentials (Org A → Org B)
```
Setup → Named Credentials → New
Label: SyncEngine_OrgB
URL: https://orgb.salesforce.com
Auth: OAuth 2.0
```

### Schedule Sync (Both Orgs)
```apex
// Execute Anonymous
String cron = '0 0 2 * * ?'; // 2 AM daily
System.schedule('Sync', cron, new SyncOrchestratorScheduler('FieldPriority'));
```

### Field Priorities (Both Orgs)
```
Setup → Custom Metadata Types → Sync Field Priority Config
Manage Records → New
Object: Account, Field: AnnualRevenue, Winning Org: OrgA
Object: Account, Field: Description, Winning Org: OrgB
```

---

## 📊 Key Objects

| Object | Purpose |
|--------|---------|
| **SyncEvent__c** | Staging table for captured changes |
| **SyncAuditLog__c** | Immutable audit trail |
| **SyncedRecordSnapshot__c** | Last known state (for conflict detection) |

---

## 🎯 Dashboard Access

1. Home Page → Edit Page → Add "Sync Dashboard" component
2. View sync health, resolve conflicts, see audit trail
3. Auto-refreshes every 30 seconds

---

## ✅ Test It

### Test 1: Simple Sync
1. Edit Account in Org A (change Name)
2. Wait 30 sec
3. Check Org B - Name should update

### Test 2: Conflict Resolution
1. Change Description in Org A to "From A"
2. Change Description in Org B to "From B" (same 1-minute window)
3. Dashboard shows conflict
4. Click "Accept Org A"
5. Both orgs now have "From A"

---

## 🚨 Troubleshooting

| Issue | Fix |
|-------|-----|
| No changes syncing | ✓ Check CDC enabled ✓ Check trigger exists |
| Infinite loop | ✓ Verify SyncInProgress__c field ✓ Check ApplyEngine |
| Dashboard empty | ✓ Assign SyncUser permission set ✓ Run sync manually |
| Conflicts won't resolve | ✓ Check record exists ✓ Verify API permissions |

---

## 📋 Full Setup Checklist

- [ ] Deploy to both orgs
- [ ] Enable CDC on Account
- [ ] Add SyncInProgress__c field
- [ ] Create CDC triggers
- [ ] Set up Named Credentials
- [ ] Schedule sync job
- [ ] Create field priority records
- [ ] Add dashboard to home page
- [ ] Test simple change
- [ ] Test conflict resolution
- [ ] Monitor dashboard

---

## 📖 Detailed Docs

- **SETUP_GUIDE.md** - Complete 12-phase setup (this is the master guide)
- **SOLUTION_DESIGN.md** - Architecture and design decisions
- **DASHBOARD_GUIDE.md** - Dashboard features and usage
- **CUSTOM_METADATA_SETUP.md** - Field priority configuration

---

## 🔑 Key Commands

```bash
# Deploy
sfdx project deploy start --source-dir force-app --target-org OrgA

# Execute anonymous
sfdx apex:run --file setup.apex --target-org OrgA

# Query
sfdx data:query --query "SELECT COUNT() FROM SyncEvent__c" --target-org OrgA

# Check deployment
sfdx project:deploy:report --job-id <id> --target-org OrgA
```

---

## 📞 Support

**Need help?** Check these docs in order:
1. QUICK_START.md (this file)
2. SETUP_GUIDE.md (detailed phases)
3. Troubleshooting section above

---

**Last Updated:** July 2026  
**Time to Setup:** ~30 minutes with both orgs open  
**Complexity:** Medium (requires CDC, Named Credentials, CDC triggers)
