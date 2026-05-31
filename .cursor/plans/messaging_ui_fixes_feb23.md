# Messaging UI Fixes — Feb 23, 2026

**Purpose:** Context for new agents. These messaging-related fixes were implemented in a recent session. Avoid reintroducing the issues below.

---

## 1. Extra Line Above Collapsed Pill

### Problem
When the pill hides conversations in the thread view (e.g. "9" for 9 hidden messages), there was an extra horizontal line above the pill that looked redundant.

### Root Cause
The collapsed first message row (`.msg-collapsed.zone-first`) has `border-bottom: 1px solid`. When the pill appears directly below it, that border created a visible extra line above the pill.

### Fix
Added CSS in **both** `fimbyConversationView` and `fimbyResponseThread`:

```css
.messages-list:has(.collapsed-pill-line) .msg-collapsed.zone-first {
    border-bottom: none;
}
```

### Files
- `fimbyConversationView/fimbyConversationView.css`
- `fimbyResponseThread/fimbyResponseThread.css`

### Don't Reintroduce
- Don't add `border-bottom` to `.msg-collapsed.zone-first` when the pill is shown
- The `:has()` selector removes the border only when `.collapsed-pill-line` exists in the list

---

## 2. Complete Banner Moved to Top of Thread

### Problem
The green "This response is complete" banner was fixed at the bottom of the screen, overlapping the nav bar. It felt disconnected from the thread content.

### Fix
- Moved the banner to the **top** of the messages container (same position as the share-contact prompt)
- Reused the share-contact-prompt format: flex layout, padding, border-radius
- Styled as green: `--fimby-success-tint` background, `--fimby-success` text
- New class: `.complete-clue-prompt` (mirrors `.share-contact-prompt` structure)
- Removed the bottom fixed `.complete-banner` for Completed status

### Files
- `fimbyResponseThread/fimbyResponseThread.html` — added complete-clue-prompt block at top of messages-container
- `fimbyResponseThread/fimbyResponseThread.css` — added `.complete-clue-prompt` styles

### Don't Reintroduce
- Don't put the Completed banner at the bottom as a fixed overlay
- The share-contact prompt and complete-clue-prompt are both "clue" headers at the top; keep that pattern

---

## 3. Reply Button Hidden When Response Is Complete

### Problem
When a response is marked Complete, we didn't want to encourage keeping the thread open. The Reply button should be hidden so users close the thread.

### Fix
- Added `showReplyArea` getter: `canSendMessage && !showTerminalBanner && (!showCompleteBanner || isWithinCompletedGracePeriod)`
- When status is Completed, Reply is hidden **unless** within the 7-day grace period (see #4)

### Files
- `fimbyResponseThread/fimbyResponseThread.js` — `showReplyArea` getter
- `fimbyResponseThread/fimbyResponseThread.html` — Reply area wrapped in `if:true={showReplyArea}`

---

## 4. 7-Day Grace Period for Reply After Completion

### Problem
Users might need to send final messages after marking a response complete (e.g. if they haven't shared contact info yet and can't start a direct message). Hiding Reply immediately was too strict.

### Fix
- **New field:** `Response__c.Completed_Date__c` (DateTime) — stores when status was set to Completed
- **Apex:** `changeStatus` sets `Completed_Date__c = DateTime.now()` when `newStatus == 'Completed'`
- **Thread data:** `buildResponseMap` includes `completedDate`
- **LWC:** `isWithinCompletedGracePeriod` getter — true when status is Completed and `(now - completedDate) <= 7 days`
- **Reply visibility:** When Completed, show Reply only if `isWithinCompletedGracePeriod`

### Files
- `objects/Response__c/fields/Completed_Date__c.field-meta.xml` — new field
- `FimbyResponseThreadController.cls` — set Completed_Date__c in changeStatus; query and return in buildResponseMap
- `fimbyResponseThread/fimbyResponseThread.js` — `isWithinCompletedGracePeriod`, `showReplyArea` logic

### Don't Reintroduce
- Don't hide Reply for Completed responses without the grace period
- Don't remove `Completed_Date__c` — it's needed for the 7-day check
- **Legacy data:** Responses completed before this change have `completedDate = null` → Reply is hidden (strict). Optional: backfill from "Response marked as complete" system message `CreatedDate` if desired.

---

## 5. Extra Divider Above Reply Button / Reply Alignment

### Problem
There was an extra horizontal divider line between the last message and the Reply button. The Reply button was left-aligned with the avatar instead of the message text.

### Fix
- Remove `border-bottom` from the last message card in the list (avoids redundant divider above reply)
- Add `padding-left: 76px` to `.reply-container` so the Reply button aligns with the start of message text (avatar 40px + gap 12px = 52px, plus container padding 24px)

### Files
- `fimbyConversationView/fimbyConversationView.css`
- `fimbyResponseThread/fimbyResponseThread.css`

### Don't Reintroduce
- Don't add a border-bottom to the last message before the reply area
- Keep Reply button aligned with message text, not the avatar

---

## 6. Hide Header Pills When Response Is Complete

### Problem
When a response thread is marked Complete, the status badge ("Completed") and amount pill ("Requesting 1") in the header are redundant — the green "This response is complete" banner already conveys the status.

### Fix
- Added `showHeaderPills` getter: `response.status !== 'Completed'`
- Wrapped status badge and header-amount in `if:true={showHeaderPills}` so both are hidden when Complete

### Files
- `fimbyResponseThread/fimbyResponseThread.js` — `showHeaderPills` getter
- `fimbyResponseThread/fimbyResponseThread.html` — conditional wrapper

### Don't Reintroduce
- Don't show status badge or amount pill when status is Completed

---

## Summary Table

| Issue | Component(s) | Key Change |
|------|--------------|------------|
| Extra line above pill | fimbyConversationView, fimbyResponseThread | CSS: remove border on `.msg-collapsed.zone-first` when pill present |
| Complete banner location | fimbyResponseThread | Moved to top; `.complete-clue-prompt` (green, share-prompt format) |
| Reply hidden when complete | fimbyResponseThread | `showReplyArea` excludes Completed (except grace period) |
| 7-day grace period | Response__c, FimbyResponseThreadController, fimbyResponseThread | `Completed_Date__c` field; Reply visible for 7 days after completion |
| Extra divider above Reply / Reply alignment | fimbyConversationView, fimbyResponseThread | Remove border on last message; `padding-left: 76px` on reply-container |
| Hide header pills when Completed | fimbyResponseThread | `showHeaderPills` getter; status badge + amount pill hidden when status is Completed |

---

## Deployment Note

All changes deployed Feb 23, 2026. Tests: `FimbyResponseThreadControllerTest` (15 passing).
