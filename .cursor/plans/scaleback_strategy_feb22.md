# FIMBY Scale-Back Strategy

**Date:** Feb 22, 2026  
**Last Updated:** Feb 22, 2026 (post-implementation)  
**Purpose:** Simplify the system now to avoid scalability problems later. Each item is ranked by impact and includes a concrete implementation plan plus any decisions you need to make.

## Implementation Status Summary

| # | Item | Status | Notes |
|---|------|--------|-------|
| 0 | FIMBY App Settings CMT | DEPLOYED | 33 fields on `FIMBY_App_Settings__mdt`, `FimbySettings` helper, all controllers refactored |
| 1 | Replace timer polling | DEPLOYED | `visibilitychange` listener replaces `setInterval` in `fimbyUniversalHeader` |
| 2 | Dots instead of counts | DEPLOYED | Dot indicators on header bell, desktop badge, bottom nav, and inbox thread list |
| 3 | Delete message search | DEPLOYED | `searchMessages()`, `searchMessagesInternal()`, `MessageSearchResult` removed. Test updated. |
| 4 | Remove typing indicators | DEPLOYED | `@api enableTypingIndicators` kept as deprecated no-op (can't remove from meta XML while published pages reference it) |
| 5 | Constrain DMs / Email-style UI | DEPLOYED | All messaging UIs (DMs, Responses, Lending) redesigned: card-style messages, collapsible Reply compose, no Enter-to-send, no optimistic send. Backend unchanged. Inbox renamed, Compose button. 90-day auto-delete job created (`FimbyConversationCleanupJob`). |
| 6 | Notification batching | DEPLOYED | Batch-until-read with `Aggregate_Count__c` and `Last_Push_Sent__c`. Re-push only if user logged in since last push. |
| 7 | Story expiration | DEPLOYED | 90-day soft TTL via `LAST_N_DAYS` in `getUnifiedFeed()` and `getStories()`. Configurable via CMT. |
| 8 | Broadcast push removal | DEPLOYED | `notifyNewNeedOrOffer()` and `notifyNewStory()` deleted from `FimbyPushNotificationService`. Tests removed. |
| 9 | Comment counts removal | DEPLOYED | FeedItem query removed from `getUnifiedFeed()`. Comment count display removed from `fimbyStoryCard` and `fimbyCard`. |

### Deviations from Original Plan

- **Phase 0 (CMT) added**: All hardcoded settings were extracted into `FIMBY_App_Settings__mdt` with `FimbySettings` helper class. This was not in the original strategy but was implemented as a prerequisite.
- **Item 4 (typing indicators)**: `@api enableTypingIndicators` could not be fully removed because Salesforce blocks property removal from meta XML when published Experience Cloud pages reference it. The property is retained as a deprecated default-false no-op.
- **Item 5 (DMs)**: Original plan suggested constraining DM creation. Instead, the decision was to keep the DM backend as-is but redesign the UI to "email-style" to lower real-time expectations. DM creation remains restricted to shared contacts (existing behavior).
- **Item 9 (comment counts)**: Original plan suggested denormalizing counts onto `Story__c`. Instead, comment counts were removed entirely from the UI ("let's be humble"). This was simpler and eliminated the FeedItem query without adding a new field or trigger.

### Post-Deploy Checklist

- [ ] **Schedule `FimbyConversationCleanupJob`**: Run `System.schedule('FIMBY Conversation Cleanup', '0 0 3 * * ?', new FimbyConversationCleanupJob());` in Execute Anonymous to activate the 90-day conversation auto-delete.
- [ ] **Schedule `FimbyNotificationCleanupJob`**: Verify this job is already scheduled (it existed before). If not: `System.schedule('FIMBY Notification Cleanup', '0 0 2 * * ?', new FimbyNotificationCleanupJob());`
- [ ] **Set CMT defaults in production**: Verify the `FIMBY_App_Settings.Default` record deployed with correct values. Navigate to Setup > Custom Metadata Types > FIMBY App Settings > Manage Records.
- [ ] **Test messaging UI**: Open DMs, Response threads, and Lending conversations. Verify card-style messages render correctly, Reply button expands compose area, Send button works.
- [ ] **Test badge dots**: Verify red dots appear on header bell and messages icons when there are unread items.
- [ ] **Test home feed**: Verify stories older than 90 days no longer appear. Verify comment counts are gone from story cards.
- [ ] **Test notification batching**: Create two responses to the same post. Verify the recipient sees one aggregated notification (not two).

---

## 1. Replace Timer Polling with Navigation-Triggered Refresh

**Impact:** HIGH — eliminates the single largest source of background Apex transactions  
**Effort:** Small (2 files changed)  
**Risk:** Low  

### What exists today

`fimbyUniversalHeader` runs `setInterval(() => _pollBadgeCounts(), 120000)` — every 2 minutes, it fires 2 Apex calls (notification count + message count) and broadcasts via `fimbybadgecounts` window event. This happens regardless of whether the user is actively using the app.

### The problem at scale

At 10K concurrent users, that's **10,000 Apex transactions/minute** from idle tabs alone. These are the most wasteful calls in the system because the user isn't even looking.

### Strategy: Refresh on navigation + visibility change

Replace the `setInterval` with:

1. **`visibilitychange` event** — refresh when the user returns to the tab (covers switching back from another app/tab)
2. **Navigation events** — refresh when the user clicks a tab (home, library, messages, mine) since `location.href` already reloads the page and the header runs `connectedCallback`
3. **Explicit refresh** — keep the `fimbyrequestbadgerefresh` event so pages like Messages can trigger a refresh on load

**What gets removed:** The 120-second `setInterval` and `clearInterval` logic.

**What happens:** Badges update when the user navigates to a new page (which they already do — `location.href` triggers a full page load) and when they come back to the tab. The only scenario where badges would be stale is if the user stares at one page for 10+ minutes without navigating. In that case, badges update the next time they tap anything.

### Decision needed

> **None** — this is a strict improvement. The current polling is invisible to users because page navigation already triggers `connectedCallback` (which calls `_pollBadgeCounts`). The `setInterval` only helps users who never navigate, which is a negligible scenario.

---

## 2. Show Dots Instead of Exact Counts on Badges

**Impact:** MEDIUM — reduces Apex query complexity from aggregate COUNT/SUM to a simple `LIMIT 1` existence check  
**Effort:** Small (2 Apex methods + 4 HTML template changes)  
**Risk:** Low  

### What exists today

- Header shows `{notificationCount}` (exact number) on the bell icon
- Header and bottom nav show `{unreadCount}` (exact number) on the messages tab
- Apex runs `COUNT()` on Notification__c and `SUM(Unread_Count_1__c)` + a 500-row Response query to calculate these

### Strategy: Boolean "has unread" check

Change the Apex methods to return `true`/`false` (or `1`/`0`) instead of exact counts:

```apex
// Instead of: SELECT COUNT() FROM Notification__c WHERE ...
// Do:         SELECT Id FROM Notification__c WHERE ... LIMIT 1
// Return:     !result.isEmpty()
```

Change the UI from `<div class="bell-badge">{notificationCount}</div>` to a simple dot indicator when `hasNotifications` is true.

The exact counts are still available on the Notifications page and Messages page themselves (where they're loaded as part of the page content, not via polling).

### Decision needed

> **Question: Do you want to keep exact counts on the bell icon and messages tab, or switch to dots?**
>
> - **Option A: Dots everywhere** — Simplest. Bell shows a red dot, messages tab shows a red dot. Exact counts only visible when you open those pages. This is what Instagram, LinkedIn, and most mobile apps do.
> - **Option B: Dot on messages, count on bell** — Compromise. Notification count is cheap (single COUNT query). Message unread count is expensive (aggregate + Response scan). Show count on bell, dot on messages.
> - **Option C: Keep counts but make them cheaper** — Keep the UI as-is, but cap the displayed count at "9+" to avoid needing exact totals. This still needs the aggregate queries though, so the savings are minimal.
>
> **My recommendation: Option A.** The counts add very little user value on the nav bar — they just tell you "go look at that page." A dot does the same job.

---

## 3. Remove Message Body Search (It's Already Dead Code)

**Impact:** HIGH — prevents a future landmine  
**Effort:** Tiny (delete unused Apex method)  
**Risk:** None  

### What exists today

`FimbyMessageController.searchMessages()` loads 500 `Message__c` records and runs `.contains()` in Apex — brute-force string matching on a LongTextArea field. **This method is not called from any LWC.** The search bar on the Messages page (`fimbyPageHeader`) sends `searchTerm` to `getThreads()`, which filters conversation names/participants — not message bodies.

### Strategy: Delete the dead code

Remove `searchMessagesInternal()` and the `MessageSearchResult` wrapper class from `FimbyMessageController.cls`. This ensures nobody accidentally wires it up later, because it's a scalability trap.

### Decision needed

> **None** — the code is unused. Removing it prevents someone from accidentally enabling the most expensive per-invocation operation in the app.

---

## 4. Never Build Typing Indicators, Read Receipts, or Online Status

**Impact:** EXTREME — prevents the three most expensive features from ever entering the codebase  
**Effort:** Tiny (remove the unused API property)  
**Risk:** None  

### What exists today

- `fimbyMessagesList` has `@api enableTypingIndicators = false;` — a property with no implementation behind it
- `fimbyConversationView` has read status tracking (`getReadStatusClass` returns 'sent', 'delivered', 'read', 'failed') and displays read indicators in the UI
- No online/offline presence system exists

### Strategy

1. **Remove `enableTypingIndicators`** — Delete the `@api` property. This removes the temptation to implement it. Typing indicators on Salesforce would require polling every 1-3 seconds per open conversation. At 1K users in conversations simultaneously, that's 300-1000 Apex calls/second. Salesforce caps concurrent long-running requests at 25-50. The math doesn't work.

2. **Simplify read status to "Sent" only** — The conversation view currently tracks Sent/Delivered/Read/Failed states. The read status is updated by marking messages as read when the recipient opens the conversation (DML on every message view). Consider simplifying to just show "Sent" and "Failed" (remove the Delivered/Read visual states). The DML still happens (it resets the unread count), but you stop setting user expectations of "they've seen my message."

3. **Never build online/offline status** — This would require either polling ("who's online right now?") or a presence service. Neither is viable on Salesforce.

### Decision needed

> **Question: Do you want to keep the read receipt indicators in the conversation view?**
>
> - **Option A: Remove read indicators** — Messages show as "Sent" or "Failed" only. No blue checkmarks, no "Read" status. The backend still marks messages as read (for unread count tracking), but the UI doesn't surface it to the sender. This prevents the "I can see you read my message, why haven't you replied?" dynamic that creates pressure for real-time responsiveness.
> - **Option B: Keep read indicators as-is** — They're already built and working. The DML cost is already paid (unread count reset). The visual indicator is just a CSS class change.
>
> **My recommendation: Option A** for a neighbourhood app. Read receipts create social pressure and set chat-app expectations. But this is a UX/community decision, not purely technical. If your users have already gotten used to seeing read receipts, removing them might cause confusion.

---

## 5. Constrain Direct Messages to Contextual Conversations

**Impact:** EXTREME — this is the single biggest architectural decision for scalability  
**Effort:** Medium (UI changes to remove free-form DM creation, redirect New Message flow)  
**Risk:** MEDIUM — this is a user-facing feature removal that needs careful messaging  

### What exists today

The Messages tab has a "New Message" button that opens a contact picker modal. Users can search for any contact in their neighbourhood and start a free-form conversation. There's no requirement for the conversation to be related to a need, offer, lending, or story.

The Messages tab also shows three thread types in a unified inbox:
- **Direct** — Free-form DMs (`Conversation__c` + `Message__c`)
- **Ask/Offer** — Response threads tied to a `Needs_Offers__c` post (`Response__c`)
- **Lending** — Lending conversations tied to a `Loaned_Item__c` record

### The problem

Free-form DMs are the most expensive feature in the app:
- 7 SOQL queries per message sent
- 5 SOQL + 2 DML per conversation opened
- 1 Queueable callout per message for push
- Unbounded conversation history (no TTL, no archiving)
- Creates user expectation of "real-time chat"

The Response Threads and Lending conversations are naturally bounded — they have a purpose, a lifecycle, and a natural conclusion. DMs are open-ended.

### Strategy options

> **Question: How important is free-form DM to your community?**
>
> - **Option A: Remove the "New Message" button entirely** — Users can only communicate through Response Threads (respond to a need/offer) and Lending conversations (request to borrow). If they want to contact someone directly, they share contact info through those flows (which already exists — the contact sharing feature sends an email with phone/email). The Messages tab becomes a pure inbox of contextual conversations.
>
>   *Pros:* Eliminates the entire `Conversation__c`/`Message__c` write path for new conversations. Dramatically reduces message volume. Sets clear expectation that FIMBY is for sharing, not chatting.  
>   *Cons:* Users lose the ability to reach out to neighbours without a specific need/offer. Some communities value the social connection of being able to say "hey, welcome to the neighbourhood."
>
> - **Option B: Keep DMs but make them invitation-only** — Remove the contact search picker. Users can only start a DM with someone they've already interacted with (responded to their post, borrowed their item, etc.). The "New Message" button is replaced with a "Message" action on existing thread cards or profile pages of people you've had transactions with.
>
>   *Pros:* Reduces new conversation creation to people who already have a reason to talk. Preserves the ability to follow up after a transaction.  
>   *Cons:* Still maintains the full DM infrastructure. Volume is lower but the architecture remains.
>
> - **Option C: Keep DMs as-is but add conversation limits** — Cap conversations per user (e.g., 50 active conversations max). Auto-archive conversations with no activity for 30 days. Add a message limit per conversation (e.g., 200 messages, then the oldest are pruned).
>
>   *Pros:* Keeps full functionality. Bounds the data growth.  
>   *Cons:* Doesn't address the fundamental issue of setting chat-app expectations. Adds complexity (archiving, pruning jobs).
>
> - **Option D: Keep DMs but add a "cool down" pattern** — When a user sends a message, hide the input for 30 seconds with a message like "Give your neighbour time to respond." This is a UX nudge that positions the tool as "neighbourhood mail" rather than "chat." It naturally limits message volume without hard caps.
>
>   *Pros:* Creative UX solution. Keeps functionality while naturally slowing velocity.  
>   *Cons:* Might feel patronizing to some users. Doesn't address data growth.
>
> **My recommendation: Option B.** It preserves the ability to have DM conversations but removes the most dangerous pattern (cold-messaging strangers), naturally reduces conversation volume, and positions DMs as a follow-up tool rather than a chat platform.

---

## 6. Aggregate Notifications for Popular Posts

**Impact:** MEDIUM-HIGH — linear reduction in Notification__c records and push callouts  
**Effort:** Medium (modify `FimbyNotificationService`, add debouncing logic)  
**Risk:** Low  

### What exists today

Every user action creates exactly 1 `Notification__c` record + 1 push notification:
- Sarah responds to your need → 1 notification + 1 push
- Mike responds to your need → 1 notification + 1 push  
- Jane responds to your need → 1 notification + 1 push

If your post gets 15 responses, you get 15 individual notifications.

### Strategy: Time-windowed notification batching

Instead of creating a notification immediately, buffer them:

1. When a notification is about to be created, check: "Does the recipient already have an unread notification of the same type for the same record in the last 15 minutes?"
2. If yes: update the existing notification's title to "Sarah and 2 others responded to your need" and skip the push (or send one aggregated push)
3. If no: create a new notification as normal

This requires adding a query to `createNotification()`:

```apex
List<Notification__c> existing = [
    SELECT Id, Title__c, Actor_Name__c 
    FROM Notification__c
    WHERE Contact__c = :recipientContactId
      AND Type__c = :type
      AND Related_Record_Id__c = :relatedRecordIdStr
      AND Read_Date__c = null
      AND CreatedDate >= :fifteenMinutesAgo
    LIMIT 1
];
```

If found, update the title and increment a counter field. If not, insert new.

### Decision needed

> **Question: Do you want to implement notification batching now, or defer it?**
>
> - **Option A: Implement now** — Adds 1 SOQL per notification creation (to check for existing), but saves N-1 inserts and N-1 push callouts for popular posts. Net positive at scale. Requires a new `Aggregate_Count__c` number field on `Notification__c`.
> - **Option B: Defer** — Current 1:1 pattern is fine for early user counts. Revisit when you see posts regularly getting 10+ responses. The notification cleanup job already handles old records.
>
> **My recommendation: Option B (defer).** At your current user count, posts probably get 1-5 responses. The batching logic adds complexity for marginal benefit right now. But **do add it to your monitoring checklist** — when you see posts consistently getting 10+ responses, implement it.

---

## 7. Set Content Expiration / Auto-Archive

**Impact:** HIGH (long-term) — keeps your active dataset bounded as the org grows  
**Effort:** Small-Medium  
**Risk:** Low  

### What exists today

- **Needs/Offers:** Already have `End_Date__c`, `Expired_Yesterday__c` formula, and `Expired` status in the picklist. The home feed already filters to active statuses (`Posted`, `Reply Received`, `Reply Accepted`). However, I don't see an automation that actually sets `Status__c = 'Expired'` when `End_Date__c` passes.
- **Stories:** No expiration mechanism at all. Stories live forever.
- **Library Items:** Status-based (`Available`, etc.), no TTL.
- **Conversations:** No auto-archive. Conversations persist indefinitely.
- **Notifications:** Cleanup job deletes read notifications older than 30 days (good).

### Strategy

> **Question: Does a flow/process builder already exist to auto-expire Needs/Offers when End_Date__c passes?**
>
> If not, here's what to add:
>
> **a) Needs/Offers auto-expiration** — Scheduled flow or batch job that runs daily and sets `Status__c = 'Expired'` where `End_Date__c < TODAY() AND Status__c IN ('Posted', 'Reply Received')`. The `Expired_Yesterday__c` formula suggests this might already exist in some form — but it only flags records, it doesn't update the status.
>
> **b) Story archiving** — This is the decision point:
>
> - **Option A: Auto-archive stories after 90 days** — Add an `Archived__c` checkbox to `Story__c`. Scheduled batch sets `Archived__c = true` for stories older than 90 days. Home feed filters exclude archived stories. Users can still see their own archived stories in "My Stuff."
> - **Option B: Never auto-archive stories** — Stories are low-volume (1-3 per user) and read-heavy. Even at 100K users, you'd have ~300K stories — well within SOQL limits. The Neighbourhood filter already scopes queries to the user's community.
> - **Option C: Soft TTL** — Stories older than 90 days don't appear in the main feed but remain accessible via direct link or "My Stuff." No status change needed — just add `AND CreatedDate >= LAST_N_DAYS:90` to the feed query.
>
> **My recommendation: Option C for stories** (add to the feed query, no schema change needed). **Option A is already partially built for Needs/Offers** — just needs the automation to actually flip the status.
>
> **c) Conversation archiving** — Add a daily batch that sets `Status__c = 'Archived'` on Conversations with no new messages in 60 days. The Messages tab already filters by status, so archived conversations would simply drop off the list.

---

## 8. Don't Wire Up Broadcast Push Notifications

**Impact:** EXTREME — prevents a category of problems that could single-handedly exhaust your daily limits  
**Effort:** None (just don't do it)  
**Risk:** None  

### What exists today

`FimbyPushNotificationService` has four convenience methods that are **defined but not called anywhere**:

- `notifyNewMessage()` — push to a single user
- `notifyNewNeedOrOffer()` — push to ALL users in a neighbourhood  
- `notifyNewStory()` — push to ALL users in a neighbourhood
- `notifyLibraryActivity()` — push to a single user

### The problem

`notifyNewNeedOrOffer()` and `notifyNewStory()` are **1:N broadcast patterns**. If a neighbourhood has 500 members and someone posts a new need, that's 500 push notification Queueable jobs. If 20 posts happen per day across the platform, that's 10,000 push jobs/day — and that's at modest scale.

### Strategy: Delete the broadcast methods, keep the single-user ones

Remove `notifyNewNeedOrOffer()` and `notifyNewStory()` from the codebase entirely. These should never be triggered as real-time pushes.

If you ever want "new post in your neighbourhood" notifications, implement them as:
- A **daily digest** scheduled batch: "Here's what happened in your neighbourhood today"
- Or an **in-app only** notification (no push) that's created when the user next opens the app

Keep `notifyNewMessage()` and `notifyLibraryActivity()` — these are 1:1 patterns that are fine.

### Decision needed

> **Question: Do you ever plan to send "new post" push notifications to entire neighbourhoods?**
>
> - If **no**: Delete the broadcast methods now. Simple.
> - If **yes, as real-time push**: Don't. At 10K users in a neighbourhood, one post = 10K callouts. Your daily Queueable limit would be exhausted by 25 posts.
> - If **yes, as daily digest**: Keep the methods but rename them to clearly indicate they're for batch use only (e.g., `buildDigestPayloadsForNeighbourhood()`), and only call them from a scheduled batch class.
>
> **My recommendation: Delete them.** If you want digests later, you'll build that as a separate scheduled batch with its own design.

---

## 9. Denormalize Comment Counts onto Story__c

**Impact:** MEDIUM — eliminates a 2,000-row FeedItem query on every home feed load  
**Effort:** Medium (new field, trigger or flow to maintain it, backfill job)  
**Risk:** Low  

### What exists today

`FimbyHomeController.getUnifiedFeed()` queries up to 2,000 `FeedItem` records every time the home feed loads, then counts them in memory per story. There is no `Comment_Count__c` field on `Story__c`.

The count is displayed on story cards in the feed (via `engagementCount` in the `UnifiedFeedItem` wrapper).

### Strategy: Add Comment_Count__c to Story__c

1. Add a `Comment_Count__c` (Number) field to `Story__c`, default 0
2. In `FimbyStoryCommentController.postStoryComment()`, after inserting the FeedItem, increment the count:
   ```apex
   update new Story__c(Id = storyId, Comment_Count__c = story.Comment_Count__c + 1);
   ```
3. In `FimbyStoryCommentController.deleteStoryComment()` (if it exists), decrement
4. Run a one-time backfill batch to set counts for existing stories
5. Remove the FeedItem query from `getUnifiedFeed()` and read `Comment_Count__c` from the Story query (which already runs)

### Decision needed

> **Question: Is comment count accuracy critical, or is "close enough" acceptable?**
>
> - **Option A: Maintained via Apex trigger/code** — Accurate count, updated on every comment post/delete. Requires changes to `FimbyStoryCommentController` + a backfill job.
> - **Option B: Remove comment counts from the feed entirely** — Show a "comments" icon without a number. Users tap into the story to see comments. Eliminates the FeedItem query completely with zero new code.
> - **Option C: Lazy-load counts client-side** — Remove the count from `getUnifiedFeed`. Add a separate lightweight method that takes a list of story IDs and returns counts. Call it after the feed renders, so the feed loads fast and counts fill in asynchronously.
>
> **My recommendation: Option A.** It's the most complete solution and the implementation is straightforward. The FeedItem query in `getUnifiedFeed` is one of the two heaviest operations on every page load. Eliminating it is worth the effort.

---

## Implementation Priority

If you want to do these now, here's the order I'd recommend:

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| 1 | **Remove timer polling** (#1) | 30 min | Immediate: eliminates biggest background load |
| 2 | **Delete message search dead code** (#3) | 10 min | Immediate: removes a landmine |
| 3 | **Delete broadcast push methods** (#8) | 10 min | Immediate: removes another landmine |
| 4 | **Remove typing indicators property** (#4) | 5 min | Immediate: closes the door on a bad feature |
| 5 | **Dots instead of counts** (#2) | 1-2 hrs | Medium-term: simplifies badge queries |
| 6 | **Denormalize comment counts** (#9) | 2-3 hrs | Medium-term: speeds up home feed |
| 7 | **Content auto-expiration** (#7) | 2-3 hrs | Long-term: keeps dataset bounded |
| 8 | **Constrain DMs** (#5) | Half day | Strategic: biggest architectural simplification |
| 9 | **Notification batching** (#6) | Half day | Defer: implement when posts get 10+ responses |

Items 1-4 can be done in under an hour with almost zero risk. Items 5-7 are worth doing soon. Item 8 is the strategic decision that has the biggest long-term impact but also affects the user experience most.

---

## Questions Summary

Decisions I need from you before implementing:

1. **Dots vs counts (#2):** Option A (dots everywhere), B (dot on messages, count on bell), or C (keep counts)?
2. **Read receipts (#4):** Option A (remove read indicators) or B (keep as-is)?
3. **DM scope (#5):** Option A (remove free-form DMs), B (interaction-only DMs), C (keep + limits), or D (keep + cooldown)?
4. **Notification batching (#6):** Option A (implement now) or B (defer)?
5. **Story expiration (#7):** Option A (archive flag), B (never expire), or C (soft TTL in feed query)?
6. **Needs/Offers expiration (#7):** Is there already an automation that sets Status to Expired? Or do we need to build it?
7. **Broadcast push (#8):** Delete the methods, or rename for future batch use?
8. **Comment counts (#9):** Option A (denormalize), B (remove from feed), or C (lazy-load)?
