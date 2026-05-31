# FIMBY Scalability — Long-Term Considerations

As FIMBY scales from hundreds to thousands to hundreds of thousands of users,
different Salesforce limits become the binding constraint at each tier. This
document maps the tiers, the limits you'll hit, and the architectural options
to address them.

---

## Current State (Post Feb 22 Changes)

| Optimization | Status | Impact |
|---|---|---|
| Polling consolidated (120s, single timer) | Done | ~4x fewer Apex calls from idle sessions |
| SOQL queries bounded with LIMITs | Done | Eliminates row-limit exceptions |
| DM unread count via aggregate SUM | Done | 2 aggregate queries vs. N rows loaded |
| Push notifications via Queueable (batched) | Done | 50x fewer async invocations for broadcast notifications |
| Platform Cache for hot metadata | Done | Eliminates redundant SOQL for themes/actions/messages |
| Email via User target (not Contact) | Done | Emails no longer count against 5K/day limit |

---

## Tier 1: 1,000–5,000 Users

**You're likely fine.** The changes already deployed handle this tier well.

### Limits to Monitor

| Limit | Current Headroom | How to Check |
|---|---|---|
| Concurrent Apex requests | ~25-50 concurrent | Setup > Apex Flex Queue; monitor for `ConcurrentPerOrgLongTxn` errors in debug logs |
| Daily Queueable jobs | 250,000/day | Setup > Apex Jobs; count daily Queueable executions |
| Org storage (data + file) | Depends on edition | Setup > Storage Usage |
| SOQL queries per transaction (100) | Comfortable | Review debug logs for methods approaching 80+ queries |

### Recommended Actions

- **Set up monitoring**: Create a scheduled report or dashboard tracking daily Apex job counts, storage usage, and any `System.LimitException` errors in logs.
- **Review Notification__c growth**: Every in-app notification creates a record. With 5K users, this table could grow to millions of rows. The existing `FimbyNotificationCleanupJob` purges stale records — verify it's scheduled and the retention window is reasonable (30-90 days).
- **Index custom object fields**: If you haven't already, add custom indexes to frequently queried fields: `Conversation__c.Participant_1__c`, `Conversation__c.Participant_2__c`, `Response__c.Contact__c`, `Notification__c.Contact__c`. Contact Salesforce Support to request these.

---

## Tier 2: 5,000–25,000 Users

**Polling becomes the bottleneck.** Even at 120s intervals, 10K concurrent users generate ~170 Apex transactions per second just from badge polling.

### Limits You'll Hit

| Limit | Threshold | Symptom |
|---|---|---|
| Concurrent Apex (25-50) | ~5K-10K concurrent users | `System.LimitException: Too many concurrent requests` errors; pages time out or show spinners indefinitely |
| API request volume | Depends on edition entitlements | Degraded performance across the org, not just Experience Cloud |
| SOQL row limits on Conversation__c | Users with 500+ conversations | `System.LimitException: Too many query rows` on unread count |

### Recommended Actions

#### Replace Polling with Change Data Capture (CDC) or Streaming

This is the single most impactful change at this tier. Instead of every user polling every 2 minutes, use Salesforce's event-driven architecture:

**Option A: Change Data Capture (CDC)**
- Enable CDC on `Notification__c` and `Conversation__c`
- LWC subscribes to `/data/Notification__cChangeEvent` via `lightning/empApi`
- When a record is created/updated, Salesforce pushes the change to all subscribers
- **Limit**: 2,000 concurrent CometD subscribers per org

**Option B: Custom Platform Events**
- Create `FIMBY_Badge_Update__e` Platform Event with fields: `Contact_Id__c`, `Notification_Count__c`, `Message_Count__c`
- After creating a notification or message, publish the event
- LWC subscribes via `lightning/empApi` and updates badge counts in real-time
- **Limit**: 250,000 event publishes/day; 2,000 concurrent subscribers

**Option C: Hybrid — Streaming for Active, Polling for Idle**
- Use Platform Events when the user is actively on the site
- Fall back to polling (at a much longer interval, e.g., 5 minutes) only when the streaming connection drops
- This is the most robust pattern and handles the CometD subscriber limit gracefully

**The 2,000 concurrent CometD subscriber limit** is the hard ceiling for both CDC and Platform Events. Beyond that, you need Option D below.

#### Add Platform Cache for Unread Counts

Instead of querying `Conversation__c` and `Response__c` on every poll, write unread counts to `Cache.Session` when messages are sent/read:

```
// When a message is sent:
Cache.Session.put('UnreadCount_' + recipientUserId, newCount, 300);

// When badge is polled:
Integer cached = (Integer) Cache.Session.get('UnreadCount_' + userId);
if (cached != null) return cached;  // Skip SOQL
return computeFromSOQL();           // Fallback
```

This eliminates the 2 most expensive SOQL queries (aggregate SUM + response scan) for the vast majority of polls.

#### Implement the Queueable Batch Push Mode

The `FimbyPushNotificationService.USE_BATCH_MODE` flag is still `false` (placeholder). At this tier, implement the batch mode:

1. Create `Push_Notification_Queue__c` custom object (User, Payload JSON, Status, CreatedDate)
2. Notifications insert queue records instead of enqueuing Queueable jobs
3. A scheduled job runs every 1-5 minutes, groups queued records by neighbourhood, and sends them to the Auth Bridge in bulk HTTP callouts
4. This reduces Queueable job count from N-per-notification to 1-per-interval

---

## Tier 3: 25,000–100,000 Users

**Salesforce becomes the bottleneck.** At this scale, the fundamental architecture of "every user action = Apex transaction = SOQL queries" doesn't scale linearly.

### Limits You'll Hit

| Limit | Threshold | Symptom |
|---|---|---|
| CometD concurrent subscribers (2,000) | ~2,000+ active users | Streaming connections refused; fall back to polling which compounds the Apex problem |
| Platform Event publishes (250K/day) | ~25K users with moderate activity | Events dropped or delayed |
| Queueable jobs/day (250K) | High message volume | Push notifications silently dropped |
| Org CPU time / Apex execution time | Aggregate across all users | Slow page loads, timeout errors |
| Data storage | Millions of Notification__c, Message__c, Conversation__c records | Storage limit exceeded |

### Architectural Changes Required

#### External Real-Time Service

Move badge counts and presence indicators to an external real-time service:

- **Firebase Realtime Database / Firestore**: LWC connects via WebSocket (from a custom Aura component or post-message bridge). Badge counts written to Firebase from a Salesforce Queueable/Platform Event subscriber.
- **Pusher / Ably / Socket.io**: Commercial real-time messaging services. Your Auth Bridge (already running externally) could host this.
- **Your existing Auth Bridge**: Extend it to maintain WebSocket connections for badge counts. Salesforce publishes a Platform Event; the Auth Bridge subscribes via CometD and re-broadcasts to connected clients via WebSocket.

**Architecture:**
```
User Browser ←WebSocket→ Auth Bridge ←CometD→ Salesforce Platform Events
```

This removes the 2,000 CometD subscriber limit entirely — the Auth Bridge is 1 CometD subscriber, and it fans out to unlimited WebSocket clients.

#### Read Replicas / External Search

Move read-heavy operations off Salesforce:

- **Message search**: Index messages in Algolia, Elasticsearch, or Typesense. Write messages to Salesforce (source of truth) and sync to the search index via Platform Events.
- **Home feed**: Pre-compute the feed in an external service (e.g., Heroku Postgres) and serve it via API. Salesforce writes to both its own objects and the external feed service.
- **Contact lookup / search**: Move the SOSL search to an external search index.

#### Tiered Storage

- **Hot data** (last 30 days): Keep in Salesforce objects
- **Warm data** (30-365 days): Move to Big Objects or external database
- **Cold data** (365+ days): Archive to Salesforce Big Objects or S3

Implement data archival jobs that move old `Message__c`, `Notification__c`, and `FeedItem` records out of standard objects.

---

## Tier 4: 100,000+ Users

**Salesforce is the system of record, not the runtime.** At this scale, Salesforce handles admin workflows, reporting, and data management. The user-facing Experience Cloud app is backed by external services for all real-time operations.

### Architecture Pattern: Headless Salesforce

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Mobile App    │────→│  Auth Bridge /   │────→│   Salesforce    │
│   (React Native │     │  API Gateway     │     │   (System of    │
│    or LWC)      │←────│  (Node.js)       │←────│    Record)      │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                       │
        │                ┌──────┴──────┐
        │                │ External DB │
        │                │ (Postgres / │
        └───WebSocket───→│  Firebase)  │
                         └─────────────┘
```

- **Salesforce** handles: user provisioning, Contact/Account management, reporting, admin workflows, data governance
- **External API** handles: message send/receive, feed generation, search, real-time badge counts, push notifications
- **Sync**: Salesforce Platform Events or Change Data Capture → External API → External DB

At this tier, you may also consider whether Experience Cloud is still the right UI layer, or whether a fully custom frontend (React, Next.js) backed by the API Gateway provides better performance and cost efficiency.

---

## Salesforce Edition Considerations

The specific numeric limits depend on your Salesforce edition:

| Limit | Professional | Enterprise | Unlimited |
|---|---|---|---|
| API requests/day | 1,000/user | 1,000/user | 5,000/user |
| Platform Event publishes/day | 25,000 | 250,000 | 250,000 |
| Platform Cache (free) | 0 MB | 10 MB | 30 MB |
| Concurrent Apex | 10 | 25 | 50 |
| Community user licenses | Per-login or per-member pricing | Same | Same |

Community (Experience Cloud) user licenses have **reduced API entitlements** compared to full Salesforce licenses. Specifically:
- **Customer Community**: 10 API calls/user/day
- **Customer Community Plus**: 200 API calls/user/day

LWC @AuraEnabled calls from Experience Cloud do NOT count against API limits (they're Apex transactions, not REST API calls). But any external integrations, mobile API calls, or Composite API usage do count.

---

## Cost Considerations

As you scale, the cost model shifts:

| Scale | Primary Cost | Approx. Range |
|---|---|---|
| 1K users | Salesforce licenses | $2-10K/year |
| 10K users | Salesforce licenses + storage add-ons | $20-100K/year |
| 100K users | Licenses + Platform Event capacity + external infra | $100K-500K/year |
| 1M users | Custom architecture mandatory; Salesforce as back-office only | Varies widely |

**Platform Event capacity packs** are available from Salesforce for additional publishes beyond the included allocation.

**Storage add-ons** may be needed as `Message__c`, `Notification__c`, and `Loaned_Item__c` records accumulate.

---

## Recommended Monitoring Checklist

Set these up now so you have baseline data before scaling:

- [ ] **Weekly**: Check Setup > Apex Jobs for Queueable job counts
- [ ] **Weekly**: Check Setup > Storage Usage for data growth trends
- [ ] **Monthly**: Review debug logs for any `System.LimitException` occurrences
- [ ] **Monthly**: Check Setup > Platform Cache > FIMBY partition hit/miss ratio
- [ ] **Quarterly**: Run a load test simulating 2x current user count
- [ ] **Before any launch**: Verify Experience Cloud page view limits in your contract (some licenses cap monthly page views)

---

## Decision Points — When to Act

| Signal | Action |
|---|---|
| Concurrent Apex errors in logs | Move to Tier 2 changes (streaming/CDC) |
| Queueable jobs approaching 200K/day | Implement batch push mode |
| Storage usage > 60% of allocation | Implement data archival |
| Page load times > 3s (p95) | Add Platform Cache for hot queries; consider external read layer |
| CometD subscriber limit hit | Build Auth Bridge WebSocket fan-out |
| 50K+ monthly active users | Begin Tier 3 planning; evaluate external DB |
| Salesforce license costs exceed external infra costs | Evaluate headless architecture |
