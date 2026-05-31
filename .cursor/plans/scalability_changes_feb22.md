# FIMBY Scalability Changes — Feb 22, 2026

All changes deployed and all tests passing (161 tests across 11 test classes).

---

## 1. Polling Consolidation (3 LWC components)

### What Changed

| File | Change |
|---|---|
| `fimbyUniversalHeader.js` | Single poll timer at **120s** (was 60s). Broadcasts `fimbybadgecounts` window event with `{ notificationCount, messageCount }`. Listens for `fimbyrequestbadgerefresh` to force an immediate poll. |
| `fimbyBottomNavigation.js` | **Removed** own `setInterval` and `getUnreadMessageCount` import. Now listens for `fimbybadgecounts` event to update its badge. |
| `fimbyMessagesList.js` | **Removed** own `setInterval` and `POLL_INTERVAL_MS`. Now listens for `fimbybadgecounts` event. Dispatches `fimbyrequestbadgerefresh` on mount for an immediate count. |

### What to Test

- [ ] **Notification bell badge** (header) still updates when a new notification arrives — may take up to 2 minutes now instead of 1 minute.
- [ ] **Message badge count** on the bottom nav (mobile) updates when you receive a new message.
- [ ] **Messages list** `totalUnreadCount` at the top of the page updates as you navigate in/out.
- [ ] Sending a message to yourself (or having someone send you one) and waiting — confirm the badge increments within ~2 minutes.
- [ ] **Desktop nav** message badge (in the header) also updates via the same broadcast.
- [ ] If both header and bottom nav are visible during resize, confirm no duplicate polling (only header polls).

### Potential Issues

- **Delayed badge updates**: The interval doubled from 60s to 120s. Users will notice a slightly longer delay before badge counts refresh. If this feels too slow, the constant in `fimbyUniversalHeader.js` line 59 can be reduced back to 60000.
- **Bottom nav badge blank on first load**: The bottom nav no longer fetches its own count — it waits for the header's broadcast. Since the header polls immediately on mount (`_pollBadgeCounts()` in `connectedCallback`), the broadcast should arrive within milliseconds. But if the header renders significantly after the bottom nav, there could be a brief moment with a stale count.
- **fimbyMessagesList initial count**: It calls `refreshUnreadCount()` directly AND listens for the broadcast. The direct call is a safety net for the first render. Subsequent updates come via the broadcast only.

---

## 2. SOQL Query Limits (4 Apex classes)

### What Changed

| File | Method | Change |
|---|---|---|
| `FimbyCommunicationController.cls` | `getUnifiedUnreadCountInternal()` | **DM unread count** now uses two `SELECT SUM()` aggregate queries instead of loading all `Conversation__c` rows. **Response unread** query adds `AND Last_Reply_Contact_Lookup__c != :myContactId` filter (pre-filter instead of in-Apex skip) and `LIMIT 500`. |
| `FimbyMyStuffController.cls` | `getMyLibraryItems()` | Added `LIMIT 200` to the all-items query. |
| `FimbyMyStuffController.cls` | `getMyLibraryItemsArchive()` | Added `LIMIT 500` to the all-items query. |
| `FimbyMyStuffController.cls` | `getMyBorrowedItems()` | Added `LIMIT 100`. |
| `FimbyMyStuffController.cls` | `getContactCards()` (SharedContactHelper) | Added `LIMIT 500` to shared contact info query. |
| `FimbyMessageController.cls` | `searchMessagesInternal()` | Reduced `LIMIT` from 2000 to **500**. |
| `FimbyHomeController.cls` | `getUnifiedFeed()` FeedItem comment counting | Added `LIMIT 2000` to FeedItem query (was unbounded). |

### What to Test

- [ ] **My Library Items** page: if someone owns more than 200 items, only the first 200 appear. This is unlikely but confirm the page still renders normally.
- [ ] **My Library Items Archive**: same, capped at 500.
- [ ] **Message search**: search results may be less comprehensive now (only last 500 messages searched instead of 2000). Test by searching for an old message.
- [ ] **Unread message count in nav bar**: the aggregate SUM approach should return the same number as before. Compare before/after if possible.
- [ ] **Home feed comment counts**: should still display correctly on story cards.
- [ ] **My Contacts**: if someone has 500+ shared contacts, the list will be truncated. Very unlikely at current scale.

### Potential Issues

- **Truncated results**: Users with extreme amounts of data (200+ library items, 500+ shared contacts, 500+ active response threads) will see truncated results. These limits are far above typical usage but should be documented.
- **Aggregate SUM returning null**: The aggregate queries handle null correctly (checking for null before `.intValue()`), but if the `Participant_1_Unread_Count__c` or `Participant_2_Unread_Count__c` fields have unexpected values (negative numbers, etc.), the sum could differ from the old row-by-row count.

---

## 3. Push Notifications — @future to Queueable (2 Apex classes)

### What Changed

| File | Change |
|---|---|
| `FimbyPushNotificationService.cls` | Replaced `@future(callout=true) sendPushAsync()` with `FimbyPushQueueable` inner class (`Queueable, Database.AllowsCallouts`). `sendPushNotification()` now enqueues a single Queueable. `sendPushNotifications()` batches ALL eligible payloads into one Queueable job instead of firing N separate @future calls. Added `enqueuePayloads()` guard that skips if already in `isQueueable() || isFuture() || isBatch()` context. |
| `FimbyNotificationService.cls` | Updated `sendPushForContact()` guard to also check `System.isQueueable()`. |
| `FimbyPushNotificationServiceTest.cls` | Removed `System.runAs` from callout tests (not needed for Queueable). Added `testQueueableExecutesBatch` and `testSendMultipleNotifications` tests. |

### What to Test

- [ ] **Send a direct message** to another user → they should receive a push notification on their device (if push is set up).
- [ ] **Create a new Need/Offer** → neighbourhood members should get push notifications.
- [ ] **Post a new story** → neighbourhood members should get push notifications.
- [ ] **Library lending actions** (request, approve, return) → relevant parties get push notifications.
- [ ] **In-app notifications** (the bell icon) should still create `Notification__c` records AND trigger push.
- [ ] Check **Apex Jobs** in Setup after triggering push notifications — you should see `FimbyPushQueueable` jobs instead of the old async method entries.

### Potential Issues

- **Queueable limit**: Salesforce allows 50 Queueable jobs per transaction (vs. 50 @future calls). In practice, each user action only enqueues 1 job. But if a Flow/Trigger fires multiple notifications in one transaction, they'd each enqueue a separate Queueable. At very high volumes, consider consolidating into a single enqueue call.
- **No retry on failure**: The old @future had no retry either, but worth noting. If the HTTP callout to the Auth Bridge fails, the notification is lost. The Queueable logs the failure to debug logs. The batch mode (`USE_BATCH_MODE = true`) path is still a placeholder for future implementation.
- **Push notifications silently dropped in async context**: `enqueuePayloads()` returns immediately (no-op) if called from another Queueable, @future, or Batch context. This means push notifications triggered from scheduled jobs (e.g., `FimbyNotificationCleanupJob`) won't fire push. This was already the case with @future — just confirming the behavior is preserved.

---

## 4. Platform Cache (2 new files + 1 modified)

### What Changed

| File | Change |
|---|---|
| `cachePartitions/FIMBY.cachePartition-meta.xml` | **New.** Defines the `FIMBY` org-level cache partition (1MB Org, 1MB Session). |
| `FimbyCacheService.cls` | **New.** Wraps `Cache.Org` with graceful fallback. Provides `getSeasonalTheme()` (1-hour TTL), `getCelebrationActions()` (24-hour TTL), `getLoadingMessages()` (24-hour TTL). If cache partition is unavailable, silently falls back to direct SOQL. |
| `FimbyCacheServiceTest.cls` | **New.** 6 test methods covering get/put/remove and all three convenience methods. |
| `FimbyProfileController.cls` | `getActiveSeasonalTheme()`, `getCelebrationActions()`, `getLoadingMessages()` now delegate to `FimbyCacheService` instead of running SOQL directly. |

### What to Test

- [ ] **Celebration animations** still fire on the correct actions (first post, milestones, etc.).
- [ ] **Seasonal theme** (if one is active today) still shows the emoji rain / confetti.
- [ ] **Loading messages** still rotate while pages load.
- [ ] After confirming the above work, **change a Custom Metadata record** (e.g., add a new loading message) and verify it appears within 1-24 hours (depending on TTL) or after clearing the cache in Setup > Platform Cache.

### Potential Issues

- **Cache partition capacity**: The partition is set to 1MB Org + 1MB Session from the org's free allocation. If your org doesn't have enough free Platform Cache capacity, the partition deployment succeeded but the cache may not store data. Check Setup > Platform Cache to verify the FIMBY partition has allocated capacity.
- **Stale data**: If you update Custom Metadata records, the cached version persists until TTL expires. Seasonal themes refresh hourly; celebration actions and loading messages refresh daily. To force-refresh: Setup > Platform Cache > FIMBY > click "Clear" on the Org partition.
- **Null seasonal theme cached as `{empty: true}`**: When no active theme matches today, a sentinel map is cached to avoid re-querying. The controller returns `null` to the LWC in this case (correct behavior), but the sentinel occupies a tiny amount of cache space.

---

## 5. Email Sending — User Target (3 Apex classes)

### What Changed

All three email-sending methods switched from `setToAddresses(contactEmail)` to `setTargetObjectId(userId)` + `setTreatTargetObjectAsRecipient(true)`. This sends to the User record, which does **not** count against the 5,000/day single email limit.

| File | Method | Change |
|---|---|---|
| `FimbyThanksController.cls` | `sendThankYouEmail()` | Resolves recipient Contact → User via SOQL. Uses `setTargetObjectId(userId)`. Skips email if no active User found. |
| `FimbyLendingController.cls` | `sendShareContactEmail()` | Same pattern. Also adds `setSaveAsActivity(false)`. |
| `FimbyResponseController.cls` | `shareContactInfoInternal()` | Same pattern. Replaced `setToAddresses` with `setTargetObjectId`. |
| `FimbyThanksControllerTest.cls` | Test setup | Switched to `createCompleteTestSetup()` so the recipient Contact has an associated community User for email coverage. |
| `FimbyResponseControllerTest.cls` | Added `testShareContactInfo_EmailSentToUser` | New test where recipient is the poster (who has a User), covering the email code path. |

### What to Test

- [ ] **Send a thank-you** to someone who responded to your Need/Offer → they should receive an email.
- [ ] **Share contact info** during a lending request → the other party should receive an email with the shared details.
- [ ] **Share contact info** on a response → the other party should receive an email.
- [ ] Check the email **From address** — it may now show differently since `setTargetObjectId` changes how Salesforce resolves the sender. Verify it still looks correct.
- [ ] **Deactivated user test**: if a Contact's User has been deactivated, the email should silently skip (no error).

### Potential Issues

- **Email "From" address change**: When using `setTargetObjectId`, Salesforce may use the org's default "From" address or the current user's address differently than when using `setToAddresses`. The `FimbyLendingController` previously used `setReplyTo(sender.Email)` and `setSenderDisplayName(sender.FirstName)` — these are preserved, but verify the received email looks correct.
- **No email for Contacts without Users**: The old code sent email to any Contact with an Email field. The new code requires the Contact to have an active User record. For FIMBY this is correct (all community members have Users), but if there are Contacts who receive emails but aren't community users, they will stop getting emails.
- **`setTreatTargetObjectAsRecipient(true)`**: This flag is required for the email to actually be delivered to the User's email address when no template is used. Without it, `setTargetObjectId` only resolves merge fields but doesn't set the recipient. We've included it in all three methods.

---

## Complete File Change Summary

### New Files (4)
- `force-app/main/default/cachePartitions/FIMBY.cachePartition-meta.xml`
- `force-app/main/default/classes/FimbyCacheService.cls` + `.cls-meta.xml`
- `force-app/main/default/classes/FimbyCacheServiceTest.cls` + `.cls-meta.xml`

### Modified LWC (3)
- `lwc/fimbyUniversalHeader/fimbyUniversalHeader.js`
- `lwc/fimbyBottomNavigation/fimbyBottomNavigation.js`
- `lwc/fimbyMessagesList/fimbyMessagesList.js`

### Modified Apex Classes (8)
- `FimbyCommunicationController.cls`
- `FimbyMyStuffController.cls`
- `FimbyMessageController.cls`
- `FimbyHomeController.cls`
- `FimbyPushNotificationService.cls`
- `FimbyNotificationService.cls`
- `FimbyProfileController.cls`
- `FimbyThanksController.cls`
- `FimbyLendingController.cls`
- `FimbyResponseController.cls`

### Modified Test Classes (3)
- `FimbyPushNotificationServiceTest.cls`
- `FimbyThanksControllerTest.cls`
- `FimbyResponseControllerTest.cls`

---

## Quick Smoke Test Checklist

If you only have 10 minutes to test, prioritize these:

1. [ ] Load the app — confirm the home feed renders with comment counts on stories.
2. [ ] Check the notification bell — tap it, see notifications, confirm badge count matches.
3. [ ] Go to Messages — confirm threads load and unread counts display.
4. [ ] Send a message — confirm it sends and the other user's badge updates within ~2 min.
5. [ ] Go to My Stuff > My Library Items — confirm items display.
6. [ ] Share contact info with someone — confirm the email arrives.
7. [ ] If push notifications are set up: trigger one and confirm it arrives on the device.
