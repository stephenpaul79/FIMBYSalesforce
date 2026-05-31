# Data Retention Admin Guide

## Overview

The FIMBY Data Retention batch cleans up old, terminal records and their linked files to manage storage costs. It ships **dormant** — no records are deleted until an admin schedules it.

## What Each Phase Deletes

The batch runs three phases sequentially (A → B → C):

### Phase A: Post Cleanup

Deletes `Needs_Offers__c` records where:
- `CreatedDate` is older than the retention period
- `Status__c` is terminal (Completed, Expired, Cancelled, Closed)

Also deletes child records: `Response__c`, `Response_Message__c`, and linked Salesforce Files (`ContentDocument`).

**NOT deleted:** Active/posted posts (regardless of age), `Story__c` records (preserved indefinitely).

### Phase B: Conversation Message Trimming

For conversations where `Last_Message_Date__c` is older than the retention period:
- Trims messages to keep only the most recent N messages (configurable)
- Conversations with activity within the retention window are untouched

### Phase C: Library Item Cleanup

Deletes `Library_Item__c` records where:
- `CreatedDate` is older than the retention period
- `Status__c` is "Removed from Library"

Also deletes child records: `Lending_Request__c`, `Loaned_Item__c`, `Lending_History__c`, and linked files.

**NOT deleted:** Active/available library items (regardless of age).

## What Is Preserved

- **Stories + comments** — kept indefinitely
- **Active library listings** — kept regardless of age
- **Active/posted needs & offers** — kept regardless of age
- **Contact/Account counters** — reflect lifetime activity and are never decremented by retention

## Configuration

All settings are in **FIMBY_App_Settings__mdt** (Setup > Custom Metadata Types > FIMBY App Settings > Default):

| Setting | Default | Description |
|---------|---------|-------------|
| `Data_Retention_Months__c` | 6 | Months before terminal records become eligible for cleanup |
| `Conversation_Trim_Keep_Count__c` | 50 | Most recent messages to keep per dormant conversation |
| `Data_Retention_Batch_Size__c` | 200 | Records per batch execution chunk |

## Dry Run (Preview What Would Be Deleted)

Run a dry run first to see what the batch would delete without actually deleting anything:

```apex
Database.executeBatch(new FimbyDataRetentionBatch('A', true), 50);
```

Check the results in `Error_Log__c` with source `FimbyDataRetentionBatch` — it logs the count of records that would be deleted.

## Scheduling the Batch

### Option 1: Schedule via Anonymous Apex

Run this in the Developer Console (Setup > Developer Console > Debug > Execute Anonymous):

```apex
// Schedule weekly on Sundays at 2 AM
System.schedule(
    'FIMBY Data Retention',
    '0 0 2 ? * SUN',
    new FimbyDataRetentionScheduler()
);
```

### Option 2: Schedule via Setup

1. Go to **Setup > Apex Classes**
2. Click **Schedule Apex**
3. Job Name: `FIMBY Data Retention`
4. Apex Class: `FimbyDataRetentionScheduler`
5. Set the schedule (recommended: weekly, off-peak hours)

### One-Time Run

To run the batch once without scheduling:

```apex
Database.executeBatch(new FimbyDataRetentionBatch('A'), 200);
```

## Pausing / Unscheduling

To stop the scheduled job:

```apex
for (CronTrigger ct : [
    SELECT Id FROM CronTrigger
    WHERE CronJobDetail.Name = 'FIMBY Data Retention'
]) {
    System.abortJob(ct.Id);
}
```

Or go to **Setup > Scheduled Jobs** and delete the "FIMBY Data Retention" entry.

## Expected Runtime

| Data Volume | Approximate Runtime |
|-------------|-------------------|
| < 10K records | Under 5 minutes |
| 10K–50K records | 5–15 minutes |
| 50K–200K records | 15–45 minutes |
| 200K+ records | 45+ minutes (runs in batches of 200) |

The batch chains automatically (A → B → C). If any phase hits governor limits, only that batch scope fails — the rest continues.

## Governor Considerations

- Each batch scope processes up to `Data_Retention_Batch_Size__c` parent records
- Child record queries (responses, messages, files) run within each scope
- `Database.delete` uses partial success (`false`) — individual failures don't halt the batch
- File deletion respects Salesforce's multi-link protection: files linked to multiple records are not deleted until all links are removed
