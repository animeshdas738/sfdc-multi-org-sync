# Multi-Org Sync Engine - Deployment Guide

## Overview

The **package.xml** file provides a declarative way to deploy all components of the Multi-Org Sync Engine using Salesforce CLI.

**File Location:** `/manifest/package.xml`

**Total Components:** 14
- 10 Apex Classes
- 3 Custom Objects
- 1 Lightning Web Component
- 1 Custom Metadata Type (definition)

---

## Quick Deploy

### Deploy to Org A
```bash
sfdx project deploy start --manifest manifest/package.xml --target-org OrgA
```

### Deploy to Org B
```bash
sfdx project deploy start --manifest manifest/package.xml --target-org OrgB
```

### Deploy with Validation Only (No Deployment)
```bash
sfdx project deploy start --manifest manifest/package.xml --target-org OrgA --test-level NoTestRun --validation-only
```

### Deploy with Full Test Run
```bash
sfdx project deploy start --manifest manifest/package.xml --target-org OrgA --test-level RunAllTests
```

---

## Package Contents

### Apex Classes (10 total)

| Class Name | Purpose | Dependencies |
|------------|---------|--------------|
| **MultiOrgSyncTest** | Unit tests for sync engine | Uses mocking frameworks |
| **SyncApplyEngine** | Applies resolved changes to target org | REST API via Named Credentials |
| **SyncAuditTrailWriter** | Logs sync decisions to audit trail | SyncConflictResolver |
| **SyncConflictResolver** | Resolves field-level conflicts | SyncSnapshotDiffer |
| **SyncConstants** | Configuration constants | None |
| **SyncDashboardController** | Backend for dashboard LWC | SyncApplyEngine, SyncOrchestratorBatch |
| **SyncDeduplicator** | Consolidates duplicate events | SyncConstants |
| **SyncEventCaptureHandler** | CDC trigger handler | SyncConstants |
| **SyncOrchestratorBatch** | Main batch orchestrator | All other classes |
| **SyncSnapshotDiffer** | Detects conflicts via snapshots | SyncConstants |

### Custom Objects (3 total)

| Object | Purpose | Key Fields |
|--------|---------|-----------|
| **SyncEvent__c** | Staging table for sync events | SourceOrg__c, ObjectApiName__c, Status__c, PayloadJSON__c |
| **SyncAuditLog__c** | Immutable audit trail | RecordId__c, FieldName__c, Strategy__c, Outcome__c |
| **SyncedRecordSnapshot__c** | Last known state baseline | RecordId__c, ObjectApiName__c, SnapshotJSON__c |

### Lightning Web Components (1 total)

| Component | Purpose | APIs |
|-----------|---------|------|
| **syncDashboard** | Monitoring & conflict resolution UI | SyncDashboardController |

### Custom Metadata Type (1 total)

| Metadata Type | Purpose | Records |
|---------------|---------|---------|
| **SyncFieldPriorityConfig__mdt** | Field ownership configuration | User-created (see CUSTOM_METADATA_SETUP.md) |

---

## Deployment Methods

### Method 1: Using SFDX CLI (Recommended)

**Prerequisites:**
```bash
# Install SFDX CLI
npm install -g @salesforce/cli

# Authenticate to your org
sfdx auth:web:login --alias OrgA
sfdx auth:web:login --alias OrgB

# Verify authentication
sfdx org:list
```

**Deploy:**
```bash
# Standard deployment
sfdx project deploy start --manifest manifest/package.xml --target-org OrgA

# With options
sfdx project deploy start \
  --manifest manifest/package.xml \
  --target-org OrgA \
  --test-level RunAllTests \
  --wait 60
```

### Method 2: Salesforce UI (Setup → Deploy)

1. Go to **Setup → Deploy → Deployment Status**
2. Click **Deploy from Scratch Org**
3. Upload the `manifest/package.xml` file
4. Follow the UI prompts

### Method 3: VSCode with Salesforce Extensions

1. Install **Salesforce Extension Pack** for VSCode
2. Right-click `manifest/package.xml`
3. Select **Deploy Source to Org**
4. Choose target org

---

## Deployment Options

### Standard Deployment
```bash
sfdx project deploy start --manifest manifest/package.xml --target-org OrgA
```

**Test Level:** NoTestRun (default)  
**Rollback:** Automatic on failure  
**Duration:** ~2-5 minutes

### Validate Only (No Deployment)
```bash
sfdx project deploy start \
  --manifest manifest/package.xml \
  --target-org OrgA \
  --validation-only
```

**Purpose:** Verify deployment will succeed without actually deploying  
**Use Case:** Pre-deployment checking

### Run All Tests
```bash
sfdx project deploy start \
  --manifest manifest/package.xml \
  --target-org OrgA \
  --test-level RunAllTests
```

**Recommended:** Yes (ensures no regressions)  
**Duration:** ~5-10 minutes  
**Coverage Required:** 75% for managed packages

### Run Specified Tests
```bash
sfdx project deploy start \
  --manifest manifest/package.xml \
  --target-org OrgA \
  --test-level RunSpecifiedTests \
  --tests MultiOrgSyncTest
```

---

## Monitoring Deployment

### Watch Progress
```bash
# Real-time progress
sfdx project deploy start --manifest manifest/package.xml --target-org OrgA --wait 60

# Check status
sfdx project deploy report --job-id 0Afg500000BADbzCAH --target-org OrgA
```

### Retrieve Results
```bash
# Show deployment details
sfdx project deploy report --job-id <deployment-id> --target-org OrgA --verbose
```

### Check Logs
```bash
# View debug logs
sfdx apex:log:list --target-org OrgA
sfdx apex:log:get --log-id <log-id> --target-org OrgA
```

---

## Post-Deployment Verification

After deployment completes, verify:

### 1. Check Custom Objects
```bash
sfdx data:query --query "SELECT COUNT() FROM SyncEvent__c" --target-org OrgA
sfdx data:query --query "SELECT COUNT() FROM SyncAuditLog__c" --target-org OrgA
sfdx data:query --query "SELECT COUNT() FROM SyncedRecordSnapshot__c" --target-org OrgA
```

### 2. Verify Apex Classes
```bash
# List deployed classes
sfdx force:apex:class:list --target-org OrgA
```

### 3. Check LWC Component
```bash
# Component should be available in App Builder
# Setup → Lightning Components
```

### 4. Validate Metadata
```bash
# Retrieve and inspect
sfdx force:mdapi:retrieve \
  --apiversion 67.0 \
  --unpackaged manifest/package.xml \
  --targetdir ./retrieved \
  --username <org-username>
```

---

## Deployment Issues & Solutions

### Issue: "Invalid Component" Error

**Cause:** Component referenced in package.xml doesn't exist

**Solution:**
1. Verify component names are correct
2. Ensure spelling matches exactly
3. Run validation-only first: `--validation-only`

### Issue: "Insufficient Privileges" Error

**Cause:** User lacks deployment permissions

**Solution:**
1. Verify user has "Deploy Metadata" permission
2. Check API access is enabled
3. Use admin account for deployment

### Issue: "Compilation Error" After Deployment

**Cause:** Missing dependencies or syntax errors

**Solution:**
1. Check recent code changes
2. Review test logs: `sfdx apex:log:get`
3. Validate package locally before deploying
4. Deploy in order: Classes first, then Objects, then LWC

### Issue: "Deployment Timeout"

**Cause:** Large deployment or slow org

**Solution:**
```bash
# Increase wait time
sfdx project deploy start \
  --manifest manifest/package.xml \
  --target-org OrgA \
  --wait 120  # 2 minutes
```

---

## Partial Deployments

Deploy only specific components:

### Deploy Only Apex Classes
```xml
<!-- manifest/package-classes.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>*</members>
        <name>ApexClass</name>
    </types>
    <version>67.0</version>
</Package>
```

### Deploy Only Custom Objects
```xml
<!-- manifest/package-objects.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>*</members>
        <name>CustomObject</name>
    </types>
    <version>67.0</version>
</Package>
```

### Deploy Only LWC
```xml
<!-- manifest/package-lwc.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>syncDashboard</members>
        <name>LightningComponentBundle</name>
    </types>
    <version>67.0</version>
</Package>
```

---

## Rollback Strategy

If deployment fails or has issues:

### Automatic Rollback
SFDX automatically rolls back on validation failure (if deployment hasn't completed).

### Manual Rollback
If partial deployment succeeded:

```bash
# Get previous version from git
git checkout HEAD~1 -- force-app/

# Deploy previous version
sfdx project deploy start --source-dir force-app --target-org OrgA
```

### Reset Custom Objects
```apex
// Execute Anonymous to clear data
DELETE [SELECT Id FROM SyncEvent__c];
DELETE [SELECT Id FROM SyncAuditLog__c];
DELETE [SELECT Id FROM SyncedRecordSnapshot__c];
System.debug('Data cleared');
```

---

## Deployment Checklist

- [ ] Authenticated to target org: `sfdx auth:web:login --alias OrgA`
- [ ] Verified package.xml syntax: `xmllint manifest/package.xml`
- [ ] Run validation: `--validation-only` flag
- [ ] Check for conflicts: `sfdx force:source:status --target-org OrgA`
- [ ] Deploy: `sfdx project deploy start --manifest manifest/package.xml --target-org OrgA`
- [ ] Monitor: `sfdx project deploy report --job-id <id> --target-org OrgA`
- [ ] Verify custom objects created
- [ ] Verify Apex classes deployed
- [ ] Verify LWC component available
- [ ] Run post-deployment tests

---

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Deploy to Salesforce

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Authenticate to Salesforce
        uses: salesforcecli/github-workflows@main
        with:
          sfdx-auth-url: ${{ secrets.SFDX_AUTH_URL }}
      
      - name: Deploy Package
        run: |
          sfdx project deploy start \
            --manifest manifest/package.xml \
            --target-org production \
            --test-level RunAllTests
```

---

## Performance Tips

1. **Deploy in stages:**
   - Classes first
   - Objects second
   - LWC last

2. **Parallel deployments to multiple orgs:**
   ```bash
   sfdx project deploy start --manifest manifest/package.xml --target-org OrgA &
   sfdx project deploy start --manifest manifest/package.xml --target-org OrgB &
   wait
   ```

3. **Pre-validate before deployment:**
   ```bash
   sfdx project deploy start \
     --manifest manifest/package.xml \
     --target-org OrgA \
     --validation-only
   ```

4. **Use appropriate test level:**
   - `NoTestRun` - Fast, for non-production
   - `RunAllTests` - Required for production
   - `RunSpecifiedTests` - Focused testing

---

## Support & Documentation

- **Setup Guide:** `docs/SETUP_GUIDE.md`
- **Quick Start:** `docs/QUICK_START.md`
- **Dashboard Guide:** `docs/DASHBOARD_GUIDE.md`
- **Solution Design:** `docs/SOLUTION_DESIGN.md`

---

**Last Updated:** July 2026  
**Package Version:** 1.0  
**API Version:** 67.0  
**Total Components:** 14
