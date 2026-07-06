# SyncFieldPriorityConfig__mdt Setup Guide

The `SyncFieldPriorityConfig__mdt` custom metadata type is used to configure per-field conflict resolution priorities during sync operations.

## Overview

**Type Name:** `SyncFieldPriorityConfig__mdt`  
**Plural Label:** Sync Field Priority Configs  
**Visibility:** Public

## Fields

### ObjectApiName__c (Text, 100 chars)
- **Label:** Object API Name
- **Description:** Target object API name (e.g., Account, Contact)
- **Required:** Yes
- **Unique:** No

### FieldApiName__c (Text, 100 chars)
- **Label:** Field API Name
- **Description:** Target field API name (e.g., AnnualRevenue, Description)
- **Required:** Yes
- **Unique:** No

### WinningOrg__c (Picklist)
- **Label:** Winning Org
- **Description:** Which org's value wins in case of conflict (OrgA or OrgB)
- **Required:** Yes
- **Picklist Values:**
  - OrgA
  - OrgB

## Sample Configuration Records

Create the following custom metadata records based on your business requirements:

### Record 1: Account Annual Revenue
| Field | Value |
|-------|-------|
| Label | Account Annual Revenue |
| ObjectApiName__c | Account |
| FieldApiName__c | AnnualRevenue |
| WinningOrg__c | OrgA |

**Rationale:** Finance team owns pricing data in Org A

### Record 2: Account Description
| Field | Value |
|-------|-------|
| Label | Account Description |
| ObjectApiName__c | Account |
| FieldApiName__c | Description |
| WinningOrg__c | OrgB |

**Rationale:** Partner team owns narrative content in Org B

### Record 3: Contact Phone
| Field | Value |
|-------|-------|
| Label | Contact Phone |
| ObjectApiName__c | Contact |
| FieldApiName__c | Phone |
| WinningOrg__c | OrgA |

**Rationale:** Customer support team owns contact info in Org A

## Manual Creation Steps

1. In Salesforce, go to **Setup → Custom Metadata Types**
2. Click **New Custom Metadata Type**
3. Fill in:
   - **Label:** Sync Field Priority Config
   - **Plural Label:** Sync Field Priority Configs
   - **Object Name:** SyncFieldPriorityConfig__mdt (auto-fills)
   - **Visibility:** Public
4. Click **Save**
5. Click **New** in the Fields section to add three fields with configurations above
6. Once the type is created, click **Manage Records** and add the sample records

## Resolution Strategy Logic

The `SyncResolutionEngine` uses this metadata to determine conflict resolution:

1. **Check Field Priority:** If a `SyncFieldPriorityConfig__mdt` record exists for (ObjectApiName, FieldApiName), the WinningOrg's value is applied
2. **Check Manual Strategy:** If no field priority rule exists and the sync is marked for manual review, queue for human review
3. **Default to LastWriteWins:** If neither above applies, use timestamp-based resolution

## Example Usage in Apex

```apex
// Query for a specific field's winning org
SyncFieldPriorityConfig__mdt config = [
    SELECT WinningOrg__c 
    FROM SyncFieldPriorityConfig__mdt 
    WHERE ObjectApiName__c = 'Account' 
    AND FieldApiName__c = 'AnnualRevenue'
    LIMIT 1
];

if (config != null && config.WinningOrg__c == 'OrgA') {
    // Use Org A's value
    resolvedValue = orgAValue;
} else {
    // Use Org B's value or apply default strategy
    resolvedValue = orgBValue;
}
```

## Notes

- Custom metadata records are deployed as part of your metadata package
- Records can be updated without code deployments
- Queries on custom metadata are cached, so allow 15 minutes for changes to propagate
- Use the `@isTest(seeAllData=true)` annotation in tests to access custom metadata
