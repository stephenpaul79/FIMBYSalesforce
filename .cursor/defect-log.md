# FIMBY Defect Log

Tracks browser QA findings, deferred fixes, and sysadmin verification items. Append-only by convention; oldest entries on top, newest at the bottom.

---

## DEF-2026-006 — Legacy lending workflow email alerts (Phase 6 audit)

**Status:** Source-only finding; sysadmin verification required in org.

**Files reviewed**

- `force-app/main/default/workflows/Lending_Request__c.workflow-meta.xml`
- `force-app/main/default/workflows/Loaned_Item__c.workflow-meta.xml`

**Workflow email alert declarations found** (all reference `unfiled$public/...` legacy email templates):

| File | Alert API name |
|---|---|
| `Lending_Request__c` | `Lending_Confirmation`, `Lending_Request_Approval_Request`, `Lending_Request_Approved`, `Lending_Request_Decline`, `Waitlist_Automatic_Decline`, `Waitlist_Confirmation_Email` |
| `Loaned_Item__c` | `Item_Damaged_By_Borrower`, `Item_Damaged_By_Borrower_Owner_Reminder`, `Item_Returned_By_Borrower`, `Item_Returned_By_Borrower_Owner_Reminder`, `Loan_Extension_Approval_Request`, `Loan_Extension_Approved`, `Loan_Extension_Decline`, `Owner_Confirmed_Item_Damaged`, `Owner_Confirmed_Item_Returned` |

**Source audit result**

- No `<rules>` blocks in either workflow file invoke these alerts.
- No flows under `force-app/main/default/flows/` reference any of the alert API names above.
- `FimbyLendingController.cls` contains a stale comment ("Email alert Loaned_Item__c.Loan_Extension_Approved will be triggered by workflow") that suggests at least one of these was historically wired up.

**Sysadmin verification needed**

Confirm in the org (Setup → Process Automation → Workflow Rules, Process Builder, Flows) that no active automation invokes any of the alert API names above. If any are active, **deactivate** them so the consolidated alert pipeline (`FimbyEmailAlertQueueable`) is the single source of email for lending lifecycle events. Leaving the `<alerts>` declarations in source is harmless without callers, but active legacy rules will cause duplicate emails alongside the new pipeline.

Once verified inert, the `<alerts>` blocks can be removed from the workflow XML in a follow-up cleanup PR. Until then, treat both files as legacy declarations only.

---

## Lending Email Fix Plan — implementation summary

All seven planned phases shipped together (see `lending_email_fix_plan_b4b7029a.plan.md`).

### Deployed Apex

- `FimbySettings.cls` (re-deployed; no behavior change, ensures 3-arg `getUrl` overload is live in target org so the new `?action=confirmPickup` URL builds without recompile errors).
- `FimbyEmailAlertQueueable.cls` — Phase 1: single-notification email subjects + wrapper H1 now derive from `Notification__c.Title__c` (truncated at 78 chars) with privacy-generic fallback for DMs and type-map fallback for blank titles. Phase 2: alert emails no longer inject `Email_Intent` whimsy lines.
- `FimbyEmailHtmlBuilder.cls` — Phase 3: card actor sub-line is suppressed when `Title__c` already names the actor (case-insensitive substring match against full name and first name) or when the actor is the FIMBY system. The avatar pill first name is also suppressed for FIMBY system messages.
- `FimbyEmailAlertBatchJob.cls` — Phase 5: per-user Sunday filter now mirrors `FimbyPushBatchJob`. Users with `Include_Sundays__c = true` receive all alert types on Sundays; opt-out users still receive direct-action and DM alerts but broadcast/reminder alerts hold until Monday.
- `FimbyLendingController.cls` — Borrower approval notification now includes `?action=confirmPickup&requestId=...` so the deep link opens the pickup-confirmation modal directly.
- `FimbyEmailAlertQueueableTest.cls` — new subject matrix tests for Title-driven subjects, blank-title fallback, message-type privacy guard, long-title truncation, multi-message batch subject, mixed-type batch subject.

### Deployed LWC

- `c/fimbyDateUtils` — new shared module exposing `parseLocalDate`, `formatLocalDate`, `formatShortDate`, `formatLocalDateTime`. Fixes DEF-2026-005 by parsing Salesforce date-only strings as local midnight instead of UTC midnight.
- `fimbyLibraryItemDetail` — banner/history dates and overdue math now go through `fimbyDateUtils`.
- `fimbyLibraryItemAdmin` — current loan, history dates, and `_formatShortDate` delegate to `fimbyDateUtils`.
- `fimbyLibraryItemCard` — formatted due date and overdue check use the local-date parse.
- `fimbyPickupConfirmationModal` — dates use `fimbyDateUtils`. Idempotency UX: when the server reports the request has already moved past the handoff window (and the error is not `wrongStatus`/`notParticipant`), the modal auto-hides and lets the parent refresh the detail banner instead of showing the "Looks like you already took action here" wall.
- `fimbyLendingApprovalModal` — `requestDetails` formatter uses `fimbyDateUtils`. Same idempotency auto-hide pattern as pickup.
- `fimbyLendingConfirmationModal` — same idempotency auto-hide.
- `fimbyLoanExtensionModal` — same idempotency auto-hide.
- `fimbyLoanExtensionApprovalModal` — same idempotency auto-hide.

### Out of source-tracked changes

- Phase 4 (`Notification__c.Email_Subject__c` field) deferred until Phase 1 is field-validated by the QA re-run.
- Phase 6 legacy workflow alert deactivation requires sysadmin verification (see DEF-2026-006 above).

---

## QA re-run checklist — verification of email + lending fixes (P8)

**Setup:** Deploys complete and Experience Cloud `FIMBY` site published. Live URL https://our.fimby.com/login. Personas (per `qa-testing-login.mdc`): Owner = Desktop Tester, Borrower = Mobile Tester, Waitlistee = SF Tester. Anchor item = "My Cat". This checklist exists so the verification pass can be done in one focused session and findings logged here.

### Email content matrix — what to look for

Capture one inbox screenshot per beat. Confirm:

| # | Trigger | Recipient | Expected subject + wrapper H1 | Intent line | Card actor handling |
|---|---|---|---|---|---|
| 1 | Borrower submits borrow request | Owner | `{Borrower} wants to borrow your item` (from Title__c) | none | actor name appears only once (in title or avatar pill) |
| 2 | Owner declines | Borrower | `Your borrow request was declined` | none | no duplicate actor line |
| 3 | Owner approves | Borrower | `Your borrow request was approved` | none | tapping deep link opens pickup confirmation modal |
| 4 | Borrower confirms pickup / handoff | Borrower + Owner | `{Item} is now on loan to you` (borrower) / `{Item} is on loan to {Borrower}` (owner) | none | — |
| 5 | Borrower requests extension | Owner | `{Borrower} requested an extension` | none | — |
| 6 | Owner approves extension | Borrower | `Your extension was approved` | none | — |
| 7 | Borrower submits return | Owner | `{Borrower} says they returned {Item}` | none | — |
| 8 | Owner confirms return | Borrower | `Return confirmed for {Item}` | none | — |
| 9 | Owner confirms return with waitlist active | Waitlistee | `{Item} is now available` | none | tapping deep link opens waitlist confirmation modal |
| 10 | Borrower receives any 2+ alerts in one 15-min batch window | Borrower | `2 new updates in your neighbourhood` | none | per-card titles match scenarios |

### Sunday delivery

- 11. With `User.Include_Sundays__c = false`, fire an `Overdue_Reminder` notification on a Sunday. Confirm `Email_Status__c` stays `Pending` until Monday. Direct-action alerts (lending request, message) should still send the same day.
- 12. With `User.Include_Sundays__c = true`, fire the same `Overdue_Reminder` on a Sunday. Confirm it sends that day.

### In-app lifecycle (DEF-2026-004/005 verification)

- 13. Owner approves with pickup date today + 3 days. Confirm the borrower banner due date matches the picked date exactly (no off-by-one) in both the detail page and admin panel.
- 14. Open the borrower approval email on a Sunday afternoon (UTC midnight crosses zone). Confirm the "Pickup date:" body line matches the wall-clock day, not UTC.
- 15. Lending history list: confirm `displayStartDate` and `displayEndDate` show the calendar day the loan started, not the UTC-shifted day.

### Deep-link auto-open

- 16. From an in-app or email approval notification tap, confirm `fimbyLibraryItemDetail` opens with the pickup-confirmation modal already on screen.
- 17. From a waitlist promotion notification tap, confirm the waitlist confirmation modal opens automatically.
- 18. From an extension-request notification tap, confirm the extension-approval modal opens for the owner.

### Idempotency

- 19. As Borrower, tap an approval notification you already confirmed pickup for. Confirm the page banner refreshes silently (no "Looks like you already took action here" wall).
- 20. As Waitlistee, confirm waitlist after the request has already been promoted/declined on the backend. Confirm banner refreshes instead of showing a dead-end modal.

### Append findings here

Add a dated subsection (e.g. `### 2026-05-XX run`) for each verification pass with screenshot links/observations, followed by any new DEF-NNNN entries.

---

## 2026-05-24 — My Cat lifecycle QA run (Composer browser)

**Plan:** `lending-lifecycle-qa-composer-run_e7aa75c7.plan.md`  
**Anchor item:** My Cat (`a1JOL000006hiVO2AY`)  
**Personas:** Owner = Desktop Tester, Borrower = Mobile Tester, Waitlistee = SF Tester

### Phase results

| Phase | Status | Outcome |
|---|---|---|
| P0 Pre-flight | Pass | My Cat reset to Available; cleared stale Mobile Tester request |
| P1 Borrow | Pass | Mobile Tester submitted borrow request; banner **Pending Approval** |
| P2 Waitlist | Pass | SF Tester landed **#2 on waitlist**; banner "You're on the waitlist — #2 in line" |
| P3 Approval | Pass | Owner deep-link `?action=reviewRequest&requestId=…` opened approval modal; approved Mobile Tester + contact share |
| P4 Pickup | Pass | Mobile Tester confirmed pickup via notification; active loan banner **due 5/26/2026** |
| P5 Extension | **Skipped** | "Request Extension" → **"Looks like you already took action here"** (stale pending extension from prior session) |
| P6 Return | Pass | Borrower submitted return → Owner verified via `?action=confirmReturn&loanId=…` → item **Available**; Lending History row present |
| P7 Waitlist promote | **Partial** | Auto-promotion fired: SF Tester in-app notification **"My Cat is now available! … confirm you still want to borrow it"**; deep-link URL correct (`?action=confirmWaitlist&requestId=a1KOL00001qjpeD2AQ`). Confirm modal loads then shows **"Looks like you already took action here"** while detail banner still reads **"It's your turn — confirm you still want this item"** (stale client state). |
| P8 Findings | Done | This section |

### Cross-channel beats (user-reported + agent-verified)

| Beat | In-app | Email | Mobile push |
|---|---|---|---|
| P1 borrow → owner | Expected (verified P3 path) | User captured; subject/wrapper mismatch noted pre-fix | N/A (submitter) |
| P3 approval → borrower | Pass | User captured; generic subject vs card title pre-fix | User observed (15-min batch) |
| P4 pickup → owner | Pass | Not re-checked this session | N/A |
| P6 return → owner/borrower | Pass | Not re-checked this session | N/A |
| P7 promote → waitlistee | Pass (notification + URL) | Not re-checked this session | N/A |

**Email content issues (pre-fix, from user screenshots):** wrapper subject/H1 used coarse `Type__c` map while card had scenario-specific `Title__c`; digest-style intent lines appeared on transactional alerts. Fixes deployed same day — see **Lending Email Fix Plan** section above.

### New / confirmed defects

#### DEF-2026-007 — Waitlist confirm idempotency: banner stale after server advance

**Area:** `fimbyLendingConfirmationModal` + `fimbyLibraryItemDetail` user context  
**Steps:** P6 return completes → SF Tester promoted → tap promotion notification or Confirm banner → modal shows "already took action" → dismiss → banner still says "It's your turn".  
**Expected:** Modal auto-closes and banner refreshes to **Pending Approval** (or next phase).  
**Actual:** Dead-end modal message; banner unchanged until hard reload (and even after reload banner may still show Requesting Confirmation if userContext stale).  
**Note:** Idempotency auto-hide fix was deployed in `fimbyLendingConfirmationModal` same session; re-verify after publish propagates.

#### DEF-2026-008 — P5 extension blocked by stale pending extension

**Area:** `fimbyLoanExtensionModal`  
**Steps:** Open extension on active loan when prior session left `Requested_Due_Date_Extension__c` populated.  
**Expected:** Fresh extension form or clear message to cancel pending request.  
**Actual:** "Looks like you already took action here" with no path forward.

#### DEF-2026-005 (confirmed) — Borrowing history dates off-by-one

**Area:** `fimbyLibraryItemDetail` borrower history  
**Observed:** Loan to Desktop Tester displayed as **4/4/2026** then **4/5/2026** after reload (action was May 24). `fimbyDateUtils` deploy may still be propagating or history endpoint returns datetime not date-only.

#### DEF-2026-009 — Deep-link auto-open inconsistent for confirmWaitlist

**Area:** `fimbyLibraryItemDetail._tryAutoOpenActionModal`  
**Observed:** Notification tap lands on correct URL with query params; URL params cleaned from address bar before modal opens; user must click Confirm banner manually. Auto-open did not fire on notification-driven navigation in this session.

### Residual tech debt (unchanged)

- `fimbyLoanedItemReturn` bundle + orphan routes `confirmLendingRequest`, `lendingExtensionRequest` — see lifecycle plan.

### Post-run cleanup suggestion

As Owner (Desktop Tester), approve or decline SF Tester's confirmed request so My Cat ends Available with no pending rows.

---

## Lending Lifecycle QA — fresh full run (2026-05-24)

**Scope:** P0–P8 on anchor item **My Cat** (`a1JOL000006hiVO2AY`) after email-fix deploy.

### Phase results

| Phase | Result | Notes |
|---|---|---|
| P0 Preflight | Pass | Cleared stale SF Tester row via owner Remove from waitlist |
| P1 Borrow | Pass | Owner in-app + email (user screenshot: subject/H1 = Title__c) |
| P2 Waitlist | Pass | SF Tester #2; **no owner notification** for waitlist join |
| P3 Approval | Pass | `reviewRequest` deep-link; borrower approval in-app |
| P4 Pickup | Pass | `confirmPickup` deep-link auto-opened modal |
| P5 Extension | Skipped | Blocked by design when waitlist exists |
| P6 Return | Pass | Borrower return + owner verify; history → 4 rows; item Available |
| P7 Waitlist promote | Pass (after fix) | SF Tester promoted → Confirm modal works post-deploy |
| P8 Findings | Complete | See cross-channel table + defects below |

### Cross-channel notification matrix

| Beat | In-app | Email | Push |
|---|---|---|---|
| P1 owner borrow | Pass | Pass (user screenshot) | Not verified |
| P2 waitlist join (owner) | No notification observed | — | — |
| P3 borrower approval | Pass | Not verified this run | Not verified |
| P4 owner pickup | Pass | Not verified this run | Not verified |
| P6 owner return verify | Pass | Not verified this run | Not verified |
| P7 waitlist promote | Pass | Not verified this run | Not verified |

**Email fix validations:** Title-driven subject/H1 confirmed on owner borrow email. Dates May 26 / 28 / 29 / 24 — no off-by-one on admin/request UI this run.

### DEF-2026-010 — Waitlist Confirm button dead (FIXED)

**Status:** Fixed and verified by user (2026-05-24).

**Area:** `FimbyLendingController.getLendingRequestForConfirmation`, `confirmRequestInternal`, `fimbyLendingConfirmationModal`

**Root cause:** After return, waitlist promotion sets request status to **`Requesting Confirmation`**, but `getLendingRequestForConfirmation` only accepted **`Waitlisted`**. Clicking Confirm opened the modal, Apex returned `success=false`, and the modal called `hide()` with no user-visible feedback — button appeared dead.

**Fix shipped:**
- Apex accepts **`Requesting Confirmation`** (position 1) or **`Waitlisted`** (position 1) for load + confirm.
- `confirmRequestInternal` validates requester dual-check and confirmable status before update.
- `getLendingRequestForConfirmation` changed from `cacheable=true` to non-cacheable (status is mutable).
- Modal shows `alreadyHandled` / error state instead of silent `hide()` on load failure.
- Tests: `testGetLendingRequestForConfirmation_RequestingConfirmation`, `testConfirmLendingRequest_RequestingConfirmation`.

**Deploy:** `FimbyLendingController`, `FimbyLendingControllerTest`, `fimbyLendingConfirmationModal`; Experience Cloud published.

### Other findings (open / partial)

- **P2:** No owner in-app notification when second waitlistee joins (may be by design — only first borrow notifies).
- **P5:** Extension blocked when waitlist exists — intentional; modal still silent-hides on other failures (see extension modal pattern).
- **P6:** `confirmReturn` deep-link did not auto-open verify modal; owner clicked **Verify Return & Condition** manually (DEF-2026-009 pattern).
- **DEF-2026-005:** Borrower history still shows **4/5/2026** for a May 24 action — re-check after full publish propagation.

---

## Gap-fill QA — lending lifecycle gaps (2026-05-24)

**Run:** Foreground browser QA on https://our.fimby.com/login after main P0–P8 run. Anchor item My Cat (`a1JOL000006hiVO2AY`). Personas: Owner = Desktop Tester, Borrower = Mobile Tester.

| Gap | Scenario | Result | Notes |
|---|---|---|---|
| G5 | Library browse smoke | **Partial pass** | List loads; category filter works (Pet Supplies). Desktop Tester sees vouch gate on browse → card **View Item** opens vouch modal instead of detail. Expected for unvouched owner persona. |
| G3 | Extension (no waitlist) | **Pass** | Borrower requested extension to 6/12/2026; owner approved via notification deep-link (`?action=approveExtension&loanId=…`); modal auto-opened; borrower banner updated to due **6/12/2026**. |
| G6 | Lending messaging + badge | **Pass** | Owner **Message Borrower** from detail → `/conversation?id=…`; context header shows **My Cat ›**; test message sent; Messages list shows **LENDING** badge on My Cat threads. |
| G1 | `confirmReturn` deep-link (post-fix) | **Pass** | After borrower submitted return, owner tapped *"Mobile says they've returned My Cat"* notification → landed on `?action=confirmReturn&loanId=a1LOL000007HTZR2A4` and **Verify Return modal auto-opened** (no manual button). |
| G4 | Decline + cancel paths | **Not run** | Item was on active loan at gap-fill start; deferred until post-return cleanup and fresh borrow. |
| G2 | `confirmWaitlist` deep-link | **Not run** | Requires waitlist-on-return setup (SF Tester); deferred. |
| G7 | Findings log | **Complete** | This section. |

### New / updated findings

- **DEF-2026-011 — My Borrowing card links to loan Id (Invalid Page):** Mobile Tester → My Stuff → My Borrowing → **View borrowed item** navigates to `/library-item/a1LOL000007HTZR2A4` (Loaned_Item__c Id) → **Invalid Page**. Workaround: open item from Library list or Messages lending thread link.
- **G1 fix confirmed:** `fimbyLibraryItemDetail` `confirmReturn` alias resolves prior P6 failure (DEF-2026-009 pattern for return only).
- **Owner verify return (gap-fill):** After G1 auto-open, first **Confirm Return** attempt showed **Try Again** in modal — may be transient or validation edge; re-test on next return cycle.
- **Stale detail after return (fixed):** `fimbyItemReturnModal` only fired `returncomplete` on **Done**, not on submit success — detail page kept showing Return Pending / Verify Return behind the celebration screen. Aligned with other lending modals: notify parent on success; `handleReturnComplete` now clears cached context/admin data before reload.

---

## Gap-fill QA — session 2 (2026-05-24, browser automation)

**Run:** G4 → G3 → G1 → G2 → G5/G6 on https://our.fimby.com/login. Anchor **My Cat** (`a1JOL000006hiVO2AY`). Personas: Owner = Desktop Tester, Borrower = Mobile Tester, Waitlistee = SF Tester.

| Gap | Result | Notes |
|---|---|---|
| **G4** Decline / cancel | **Pass** | Owner declined with reason "G4 QA decline test" (modal auto-opened from notification). Borrower saw declined notification with reason. Second borrow cancelled via **Cancel Request** before approval. Item clean: 0 pending requests, Available. |
| **G3** Extension (no waitlist) | **Pass** | Borrow → approve (May 28 pickup) → confirm pickup → extension to **2026-06-05** → owner approved via notification (Extension Request modal auto-opened). Borrower notification: extension approved, new due **2026-06-05**. |
| **G1** `confirmReturn` deep-link | **Pass** | Owner tapped fresh *"Mobile says they've returned My Cat"* notification → **Verify Return modal auto-opened** without manual **Verify Return & Condition** click. Return verified → item Available. URL params stripped after open (`_cleanUpUrlParams` — expected). |
| **G2** `confirmWaitlist` deep-link | **Fail / blocked** | Stale promotion notification (43m): landed on item detail with **Borrow** only — **Your Turn modal did not auto-open**. Fresh cycle (borrow → approve → pickup → return → verify) completed; **no new SF promotion** — SF Tester is **#2 on waitlist**, not #1. Promotion goes to waitlist position 1 per `FimbyLendingController` return handler. |
| **G5** Browse smoke | **Partial pass** | `library-list` loads; vouch banner for Desktop (pre-existing). |
| **G6** Messaging | **Partial / not formal** | Mobile inbox shows *"Desktop Tester sent you a message — Gap-fill QA test message from owner"* (parallel activity). Formal G6 steps (Message Owner from detail during loan, Messages **Lending** badge) not re-run this session. |

### New / updated findings (session 2)

- **G2 blocked by waitlist position:** SF Tester is #2 on My Cat waitlist; return promotion notifies #1 only. Need sole waitlistee or admin cleanup before G2 can pass with SF persona.
- **G2 stale notification:** Tapping aged *"My Cat is now available"* notification navigates to item but does not open confirmation modal when request status is no longer `Requesting Confirmation` (see `_isActionStillValid` in `fimbyLibraryItemDetail.js`).
- **Library card stale waitlist badge:** Mobile library list showed **On Waitlist** for My Cat while item was Available with 0 requests — possible stale card state after prior runs.
- **Login `[object Object]` error:** Red error text on login page after failed/repeated shadow-DOM login attempts (transient; CDP fill succeeded).
- **Session ec=302 redirects:** Mid-session navigation to Library occasionally redirected to login (`?ec=302&startURL=...`).

---

## Gap-fill QA — session 3 (2026-05-24, foreground browser)

**Run:** G2 retest + bug fixes. Same anchor/personas.

| Gap | Result | Notes |
|---|---|---|
| **G1** (retest) | **Pass** | Verify Return modal auto-opened from fresh return notification; background refreshed to Available behind success modal (stale-UI fix confirmed). |
| **G2** | **Fail → fix deployed, retest pending** | Sole waitlistee (SF) joined while item on loan; after return verify **no fresh promotion notification**. Root cause: `createLendingRequest` set position-1 to **Pending Approval** even when item on loan; return handler only promoted `Status__c = Waitlisted`. **Fixed** in `FimbyLibraryController` + `FimbyLendingController` (deployed). Need one more borrow→waitlist→return cycle to confirm G2 pass. |
| **G5** | **Not re-run** | — |
| **G6** | **Not re-run** | Owner **Message Borrower** visible during return-pending loan; formal thread + Lending badge not completed. |

### Bugs fixed (session 3)

- **DEF-2026-011 — My Borrowing → Invalid Page:** `fimbyMyStuffPage` used `Loaned_Item__c` Id in `/library-item/` link; fixed to `loan.itemId` (`Library_Item__c`). Deployed + published.
- **Waitlist promotion miss (G2):** On-loan position-1 requests now get **Waitlisted** status; return handler promotes position-1 **Waitlisted** or **Pending Approval**. Apex deployed with `FimbyLibraryControllerTest` + `FimbyLendingControllerTest`.
- **Stale detail after return (prior session):** `fimbyItemReturnModal` + `handleReturnComplete` refresh — confirmed on owner verify-return.

---

## Gap-fill QA — session 4 (2026-05-24, foreground browser)

**Run:** G2 retest after waitlist-promotion fix; G5/G6 formal pass; full return cycle. Anchor **My Cat** (`a1JOL000006hiVO2AY`). Personas: Owner = Desktop Tester, Borrower = Mobile Tester, Waitlistee = SF Tester.

| Gap | Result | Notes |
|---|---|---|
| **G2** `confirmWaitlist` deep-link | **Pass** | SF joined waitlist (#1 in line) while item on loan to Mobile. After borrower return + owner verify, Desktop showed SF **Awaiting Confirmation**. SF tapped fresh *"My Cat is now available — You're next on the waitlist"* notification → **Your Turn! modal auto-opened** on item detail (`Confirming as: Sales Force`). |
| **G1** (regression) | **Pass** | Owner return notification auto-opened **Verify Return** modal (same cycle as G2). |
| **G5** Browse smoke (Mobile) | **Pass** | Library list → My Cat detail with on-loan/waitlist state; browse path works for vouched Mobile persona. |
| **G6** Messaging + LENDING badge | **Pass** | Owner **Message Borrower** → conversation with **My Cat ›** header; Messages inbox shows **LENDING** badge on My Cat threads. |
| **G4** Decline/cancel | **Pass** (session 2) | Not re-run. |
| **G3** Extension | **Pass** (session 2) | Not re-run. |
| **G7** Findings log | **Complete** | This section. |

### Session 4 setup notes

- Cleared stale SF pending request on My Cat before cycle (Desktop declined prior SF borrow).
- Waitlist join: SF **Join Waitlist** → borrow modal (May 28 pickup, 3 days) → **Request submitted**; detail banner **#1 in line**.
- Return cycle: Mobile **Return Item** (Unchanged, 2026-05-24) → Desktop verify from notification → SF promotion notification delivered within ~1 min.

### Open / minor (unchanged)

- **DEF-2026-011:** Fix deployed session 3; My Borrowing card not re-verified this session (Mobile used My Borrowing → detail successfully during return flow).
- **Library card badge drift:** SF list card briefly showed **Join Waitlist** before detail refreshed to **Cancel Request** / waitlist banner — possible stale card after submit (cosmetic).

---

## AOE QA — session 2026-05-27 (Ask/Offer/Event runbook)

### DEF-2026-AOE-D5 — Open Event chat button vs `Group_Conversation__c`

**Status:** RESOLVED (2026-05-27).

**Fix:** `getGroupConversationIdForPost` (imperative, non-cacheable) + `_resolvedEventGroupConversationId` / `_hasEventGroupChat` use Apex value with uiRecordApi fallback. Reverted mistaken `cacheable=false` on `getNeedOfferVisibility` (broke `@wire`, caused all detail pages to show "no longer available").

**Retest:** PASS — poster header **Event Chat** + inline card on `a0yOL000005ZaIfYAK`; navigates to `/conversation?id=a1ROL000002d6Fh2AI`.

### DEF-2026-AOE-G3 — Delete post redirect lands on Invalid Page

**Status:** RESOLVED (2026-05-27).

**Fix:** `handleDeleteConfirm` redirect changed from `/ask-offer-list` to `/` (home).

### DEF-2026-AOE-O1 — `/needs-offers/` URL alias shows Invalid Page

**Status:** OPEN (2026-05-27).

**Symptom:** Deep link `https://our.fimby.com/needs-offers/a0yOL000005ZaIfYAK/qaaoed20260527openevent` renders **Invalid Page**; same record via `/asks-offers/...` loads normally.

**Impact:** Legacy flows and `FIMBY_URL.Needs_Offers` CMDT still emit `/needs-offers/` paths (e.g. Share Contact Info flows). Notification/email deep links using that prefix will fail until Experience Builder exposes an alias route or redirect.

**Fix path:** Experience Cloud Setup Required — duplicate Need/Offer object page route for `/needs-offers/*` or add redirect to `/asks-offers/*`. LWC already parses both prefixes in `fimbyNeedOfferDetail` and `TAB_ROUTES`.

### DEF-2026-AOE-O2 — Event group chat absent from Messages inbox

**Status:** OPEN / BY DESIGN? (2026-05-27).

**Symptom:** Mobile Tester is `Conversation_Member__c` on Open Event group chat `a1ROL000002d6Fh2AI` but `/messages` lists Response threads only; no row for the event chat.

**Notes:** Access works via event detail **Event Chat** header/card → `/conversation?id=...`. `fimbyMessagesList` uses `FimbyCommunicationController.getThreads` (response-scoped). Confirm product intent: should on-demand event group chats appear in unified inbox?

### DEF-2026-AOE-O3 — Event chat notification deep link Invalid Page

**Status:** RESOLVED (2026-05-27).

**Symptom:** Tapping **Event chat started** notification routed to `/messages/{conversationId}` → **Invalid Page**. Working path is `/conversation?id={id}`.

**Root cause:** Legacy `Action_URL__c` values stored as `/messages/{id}` (predates `/conversation?id=` route). Org CMDT `FIMBY_URL.Conversation` already correct in source.

**Fix:** `fimbyNotificationsList._normalizeLegacyActionUrl()` rewrites `/messages/{id}` → `/conversation?id={id}` on tap. Deployed + published.

