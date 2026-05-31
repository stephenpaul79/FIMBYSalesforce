# FIMBY Operations Playbook

> **Audience:** the small team that operates FIMBY day-to-day — system admin, support email triagers, neighbourhood moderators with admin support, anyone called on for a privacy/breach/safety/legal incident.
>
> **Posture:** lean. Most days you will not open this file. When you do, you should be able to find the right procedure in under a minute, follow it without guessing, and know what to write back to the neighbour. Wherever the system already does the work, the playbook just points at it. Wherever the system can't, the playbook is the source of truth.
>
> **Companion runbooks** in [`./runbooks/`](./runbooks/) cover the two long-form procedures (account deletion setup, paper-form supportee verification) that pre-existed this playbook.

---

## Section status legend

| Marker | Meaning |
|---|---|
| `Ready` | Documented and backed by an existing system or manual procedure that has been run end-to-end. |
| `Manual v1` | No automation yet, but the manual procedure is sufficient to honour the public commitment for v1. |
| `Needs build follow-up — <ref>` | The public commitment cannot be honestly supported without additional implementation. The reference points at the plan slice or ticket that will deliver it. A bare "needs build follow-up" without a reference is not acceptable here — it just becomes a forgotten obligation. |
| `Needs operator approval` | Wording, threshold, or policy choice still requires owner sign-off before the section is considered live. Until approval, follow the *Recommended default* the playbook lists; flag the section in the operator's monthly review. |

---

## Currently `Needs operator approval`

These sections of the playbook ship with a **recommended default** but require a one-time owner decision before they're treated as canonical. Until each is decided, follow the recommended default and re-visit at the next monthly self-audit.

| # | Decision | Recommended default | Lives in |
|---|---|---|---|
| 1 | Privacy export format and target turnaround | PDF cover letter + CSV per object; **30 business days** target | [Section 4 — Privacy Access Requests](#4-privacy-access-requests--data-export) |
| 2 | Succession/shutdown notice window | **90 days** where practical; shorter only for urgent shutdown | [Section 9 — Succession / Shutdown](#9-succession--shutdown) |
| 3 | Breach-decision owner | Operator (sysadmin) decides notification thresholds; backup is the church operations lead | [Section 5 — Breach Response](#5-breach--incident-response) |
| 4 | Supportee verification retry policy | **3 attempts across at least 10 business days** using all available contact paths | [Section 7 — Supportee Verification](#7-supportee-verification) |
| 5 | CASL recurring audit home | Both: this playbook's monthly checklist **and** a future `.cursor/rules/` rule for new email/push templates | [Section 6 — CASL Log](#6-casl-log-and-message-content-audit) |
| 6 | Intake routing for `privacy@fimby.com` | Manual forward into Email-to-Case during v1 (see Section 1) until a dedicated routing address is configured | [Section 1 — Intake](#1-intake-and-triage) |

When a decision lands, replace the relevant *Recommended default* in the section body with the approved wording, drop the row from this table, and note the change in the monthly self-audit log.

---

## How to use this playbook

1. **Identify the trigger** — an inbound email, an in-app report, a moderator task overdue, a system alert. The triage matrix in [Section 1](#1-intake-and-triage) maps every trigger to a section number.
2. **Open the section.** Each section follows a consistent shape:
   - **Status** — one of the markers above.
   - **Public commitment** — what the user-facing legal/help page promises. Quotes the canonical wording so drift is detectable.
   - **System anchors** — exact Salesforce objects, classes, LWCs, and fields that back the procedure.
   - **Operator owner** — who is on point.
   - **When to use this** — trigger events.
   - **Procedure** — numbered steps.
   - **Templates** — anchored canned-reply text in [Section 11](#11-shared-response-templates).
   - **Audit trail** — where the action is logged.
   - **Escalation** — when to involve admin/legal/leadership.
3. **Use the templates** — every operator-sent reply has a canned starting point in Section 11. Edit names, dates, and links, but do not re-author tone from scratch — the templates are aligned to the [`fimby-design-philosophy`](../../.cursor/rules/fimby-design-philosophy.mdc) language rules.
4. **Log it.** Whatever section you used, the audit-trail line tells you what to record. The monthly self-audit ([Section 12](#12-monthly-self-audit-checklist)) keys off these logs.

---

## Table of contents

1. [Intake and Triage](#1-intake-and-triage)
2. [Deletion](#2-deletion)
3. [Safety Reports](#3-safety-reports)
4. [Privacy Access Requests / Data Export](#4-privacy-access-requests--data-export)
5. [Breach / Incident Response](#5-breach--incident-response)
6. [CASL Log and Message Content Audit](#6-casl-log-and-message-content-audit)
7. [Supportee Verification](#7-supportee-verification)
8. [Moderation Day-One Operations](#8-moderation-day-one-operations)
9. [Succession / Shutdown](#9-succession--shutdown)
10. [IP Complaint Intake Template](#10-ip-complaint-intake-template)
11. [Shared Response Templates](#11-shared-response-templates)
12. [Monthly Self-Audit Checklist](#12-monthly-self-audit-checklist)

---

## 1. Intake and Triage

**Status:** `Manual v1` (intake routing decision pending — see *Currently `Needs operator approval`*)
**Public commitment:** Help / contact pages list `help@fimby.com` for support, `privacy@fimby.com` for privacy access requests, and `safety@fimby.com` for urgent safety concerns.
**System anchors:** Email-to-Case routing on `help@fimby.com`, Case record types `Support` and `Account_Deletion`, queues `FIMBY_Support` and `Account_Deletion`, assignment rule `FIMBY Case Routing`, before-insert trigger `FimbyDeletionIntakeService.handleBeforeInsert`. See [`runbooks/account-deletion.md`](./runbooks/account-deletion.md) Section 1 for the deployed configuration.
**Operator owner:** sysadmin (queue member during the first-30-days monitoring window described in the deletion runbook; thereafter shared inbox).
**When to use this:** every inbound request — email, in-app feedback, system-created moderator task, regulator inquiry — runs through this triage first.

**Neighbourhood scope reminder.** When you query the org to respond to a user request, scope to the requester's neighbourhood (`FimbyIdentityRepository.getNeighbourhoodId()`-equivalent in admin context). The exception is operator/legal work — breach response, succession, IP complaints — which can cross neighbourhoods. Do not silently broaden visibility beyond what the in-app system enforces; if you need a broader query for a legitimate operator reason, log the reason in the Case.

### Triage matrix

| Trigger | Goes to | Section |
|---|---|---|
| Inbound email subject contains `delete my account`, `delete account`, `close my account` | Auto-flipped to `Account_Deletion` Case RT, routed to `Account_Deletion` queue | [§2 Deletion](#2-deletion) |
| Inbound email asks for "a copy of my information", "my data", "data export", "subject access request" | Manual creation of a `Support` Case, tagged in subject `[Privacy Access]` | [§4 Privacy Access](#4-privacy-access-requests--data-export) |
| Email or system alert indicates **suspected unauthorised access** to data, or a system outage that may have exposed data | Manual creation of a `Support` Case, tagged in subject `[Incident]`, immediate breach-log entry (Section 5) | [§5 Breach](#5-breach--incident-response) |
| In-app **report** submitted via `fimbyReportContent` (or a content surface kebab) | Auto-creates `Moderator_Task__c` via `FimbyContentReportController.submitContentReport` -> `FimbyModeratorTaskService.createOrUpdateTask` | [§3 Safety reports](#3-safety-reports), [§8 Moderation ops](#8-moderation-day-one-operations) |
| Inbound email about **copyright / IP infringement** | Manual creation of a `Support` Case, reply with the IP intake template | [§10 IP complaint intake](#10-ip-complaint-intake-template) |
| Inbound email or admin task about a **paper-form supportee verification** | Existing `Support_Relationship__c.Status__c` workflow + `Pending Paper Review` / `Pending Verification` queue | [§7 Supportee verification](#7-supportee-verification) |
| User asks to **opt out of a fundraising email** ("Updates about FIMBY itself") or general unsubscribe complaint | Update `User.FIMBY_Operating_Updates_Enabled__c = false` on the requesting user; log Case note | [§6 CASL log](#6-casl-log-and-message-content-audit) |
| Notice of operator change (church transfer, dissolution, shutdown) | Activate succession procedure | [§9 Succession](#9-succession--shutdown) |

### Routing for `privacy@fimby.com` (operator decision pending)

**Recommended default for v1:** `privacy@fimby.com` is monitored manually by the same operator who triages `help@fimby.com`. Privacy requests are forwarded into Email-to-Case by hand: open the request, forward to `help@fimby.com` with subject `[Privacy Access] <original subject>`, then reply to the original sender from the now-tracked Case. This avoids configuring a second Email-to-Case routing address before there is real volume to justify it.

**Operator decision needed:** confirm the manual-forward posture, or schedule a ticket to add `privacy@fimby.com` as a second Email-to-Case routing address. Either choice is fine for v1; the manual posture is the lighter setup.

### Response-time language by category

The numbers below are **target windows the operator commits to internally**, not promises in the public legal pages. Public pages are deliberately hedged ("we aim to", "as soon as practicable") so silence about a missed window does not become a breach of contract.

| Category | Target window | Hedge wording in any reply |
|---|---|---|
| Safety report | **24 hours** (matches `/community-guidelines` public commitment) | "Reviewed within 24 hours by a moderator." |
| Account deletion email confirmation | Auto-replied within minutes by `FimbyDeletionIntakeService` | n/a — system-generated |
| Privacy access request | **30 business days** (recommended default; see Section 4) | "We aim to fulfill within 30 business days; we will let you know if more time is needed." |
| Breach individual notification | "as soon as practicable, where required by law" — drives Section 5's decision tree, not a fixed clock | Section 5 templates |
| IP complaint intake reply | 5 business days for the first acknowledgement; longer to resolve | Section 10 template |
| Supportee verification | Up to 10 business days for the verification window itself; see Section 7 | Section 7 script |

### Audit trail

| Action | Logged in |
|---|---|
| Any operator-replied request | The Case (Email-to-Case threads automatically) |
| Safety report outcome | The associated `Moderator_Task__c` (`Decision_Reason_Code__c`, `Decision_Statement__c`, `Notes__c`) |
| Feedback submitted via in-app form | `Feedback__c` |
| Breach response action | The breach log + the Case |
| Manual unsubscribe | Case note + `User.FIMBY_Operating_Updates_Enabled__c` change is captured by Field Audit Trail if enabled |

### Escalation

- **Anything legal-shaped** (subpoena, regulator letter, lawyer demand letter, name-and-image complaint with legal claim language) — operator stops, does not reply, hands to the Strathcona Vineyard Church operations lead within one business day.
- **Suspected breach** — operator opens Section 5 immediately, even before deciding whether the threshold is met.
- **Repeat moderator-task abuse** (the same Contact appearing as `Subject_Contact__c` on multiple `Moderator_Task__c` records within a short window) — escalate inside the moderator dashboard via `escalateTask` (sets `Status__c = 'Escalated'` and pages the admin via `FimbyModeratorAlertService.alertAdmin`).

---

## 2. Deletion

**Status:** `Ready` (system shipped; manual setup required from the runbook before scheduled batches run)
**Public commitment:** [`delete-account.html`](../FIMBY%20Website/delete-account.html) and the Privacy Policy "right to be forgotten" clause.
**System anchors:** `fimbySettingsView` (in-app deletion), `FimbyProfileController.requestAccountDeactivation`, `FimbyDeactivateUserQueueable`, the Email-to-Case deletion pipeline (`FimbyDeletionIntakeService`, `FimbyDeletionConfirmationService`, `FimbyDeletionExpiryBatch`, `FimbyDeletionController`, `FimbyDeletionEmailService`), retention cleanup (`FimbyAccountDeactivationBatch`, `FimbyFeedbackAnonymizationBatch`), Case record type `Account_Deletion`, `Contact.Deactivation_Requested__c`.
**Operator owner:** sysadmin (sole `Account_Deletion` queue member during the first-30-days monitoring window).

> **The full procedure lives in [`runbooks/account-deletion.md`](./runbooks/account-deletion.md).** That runbook covers profile defaults, queue membership, Email-to-Case configuration, scheduling the three retention batches, the first-30-days monitoring loop, and the profile-permissions list. Read it once before going live; refer back during incidents.

This playbook section adds **what the runbook does not** — the public-facing cross-reference, the supporter-side identity edge case, and the manual recovery procedures.

### Public-commitment cross-reference

| Public page promise | Deployed mechanism | Notes |
|---|---|---|
| "Login is revoked immediately on confirmation" | `FimbyDeactivateUserQueueable` flips `User.IsActive = false` on enqueue (after the 24-hour safeguard) | Runbook §1 verifies this on smoke test |
| "We do this so no one else can delete your account" (email path requires reply from the FIMBY-account address) | `FimbyDeletionIntakeService.resolveActiveUsers` matches `Case.ContactId` from the inbound sender; verification email goes to `User.Email` only | Sender spoofing falls into the rate-limit guard |
| "Reply CONFIRM DELETE within 7 days" | `FimbyDeletionExpiryBatch.processExpiry` flips stale Cases to `Expired` after 7 days; cancellation email fires | Runbook §2 schedules the batch |
| "Reply CANCEL or ignore this email to keep your account" | `FimbyDeletionConfirmationService` parses both tokens; ignore = expiry path above | Confirmed by tests |
| "Your Contact stays — anonymized to 'A former neighbour'" | `FimbyAccountDeactivationBatch.anonymizeContacts` sets `FirstName = 'A former'`, `LastName = 'neighbour'`, nulls all PII fields | Falls back to delete on update failure |
| "Your posts, stories, library listings, and group-chat messages are hard-deleted within 24 hours of the nightly retention batch" | `FimbyAccountDeactivationBatch.deleteOwnedContent` covers `Notification__c`, `Story__c`, `Needs_Offers__c`, `Library_Item__c`, `Shared_Contact_Info__c`, `Support_Relationship__c`, `Conversation_Member__c`, `Message__c` | Runs nightly per the schedule in runbook §2 |
| "Active loans pause your data deletion" | `findContactsWithActiveLending` defers data scrub for any Contact with open `Lending_Request__c` (status ∈ Waitlisted, Requesting Confirmation, Pending Approval, Approved) or unreturned `Loaned_Item__c`. Login lockout still happens immediately. | The deferred Contact is picked up on the next nightly run once loans resolve |
| "Reports/feedback you filed are kept for 90 days, then anonymized" | `FimbyAccountDeactivationBatch.markFeedbackForDelayedAnonymization` stamps `Feedback__c.Anonymize_After__c = +90 days`; `FimbyFeedbackAnonymizationBatch` performs the scrub when the date elapses | Both batches must be scheduled per runbook §2 |

If any of these claims drift between the public page and the deployed code, the public page is the contract — the deployed code must catch up, not the other way around.

### Edge case — supporter is acting as the deleted Contact

When a Contact is deactivated, any other user whose `Logged_In_As_Contact__c` points at that Contact would have a stale identity reference. The deletion batch handles this **by side-effect**, not by an explicit invalidation call:

1. `FimbyAccountDeactivationBatch.deleteOwnedContent` deletes every `Support_Relationship__c` where the deleted Contact is involved (`Contact__c IN :contactIds OR Related_Contact__c IN :contactIds OR Approved_By__c IN :contactIds OR Ended_By__c IN :contactIds`).
2. `FimbyIdentityRepository`'s identity resolution rule requires an *Approved* `Support_Relationship__c` to honour `Logged_In_As_Contact__c`. With the underlying relationship gone, the next request from the supporter falls back to their own identity automatically.
3. The supporter does not see an error — they just notice they are no longer "acting as" anyone. If they had a stale browser tab open with the represented identity cached, a single refresh resolves it.

**No explicit `FimbyIdentityRepository.clearCache()` call is needed in this path** because the identity cache is per-transaction. The next transaction sees the deleted relationship and resolves the supporter to themselves.

If you are doing a manual deletion outside the batch (rare — usually only for incident recovery), do clear the supporter's `Logged_In_As_Contact__c` directly. Use the same pattern as `FimbySupportRelationshipController.deactivateRelationship`:

```apex
Contact supporter = new Contact(
    Id = supporterContactId,
    Logged_In_As_Contact__c = null,
    Logged_In_As_Neighbourhood__c = null
);
update supporter;
```

### Manual recovery procedures

If a scheduled job is missed (a paused org, an admin disabling the schedule by accident, a rare exception that aborted a batch run), the following anonymous Apex restores the missed run. Do these from **Setup → Custom Code → Apex → Anonymous Apex** — they are idempotent over a 24-hour window so re-running is safe.

```apex
// Re-run deletion expiry + safeguard + rate-limit backstop (catches missed daily run)
FimbyDeletionExpiryBatch.run();
```

```apex
// Re-run nightly account deactivation (catches Contacts with Deactivation_Requested__c = true)
Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
```

If you need to enqueue user deactivation directly for a single Contact (rare — only when the Email-to-Case path failed and the user explicitly asked you to proceed), find the related User Id and:

```apex
Id userIdToDeactivate = '005...';  // resolve via [SELECT Id FROM User WHERE ContactId = :targetContactId AND IsActive = true]
System.enqueueJob(new FimbyDeactivateUserQueueable(userIdToDeactivate));
```

Document the manual intervention in the relevant Case so the audit trail explains why a User was deactivated outside the normal flow.

### What not to write

Do **not** describe deletion as "we delete all your data". The system intentionally retains:

- An anonymized Contact stub so foreign keys on lending history, blocks, and other-neighbour-owned records still resolve a name (without exposing PII).
- `Blocked_Contact__c` rows from both directions — the bidirectional shield must survive even after one party deletes their account.
- `Lending_History__c` references the deleted Contact via the anonymized stub.
- Aggregated/de-identified analytics counters (none currently shipped, but reserve the language).

### Templates

| Trigger | Template |
|---|---|
| User asks "did you actually delete me" after the fact | [§11 — *Deletion confirmed* template](#deletion-confirmed) |
| Active-loan-deferred deletion needs explanation | [§11 — *Deletion deferred for active loans* template](#deletion-deferred-for-active-loans) |
| Manual recovery / email-to-case path failed | [§11 — *Manual deletion completed* template](#manual-deletion-completed) |

### Audit trail

- The originating Case (Email-to-Case path) carries the full request → confirmation → completion email thread.
- `Contact.Deactivation_Requested__c = true` on the deleted Contact (held until anonymization completes).
- `User.IsActive = false` on the deleted User (immediate after safeguard).
- `FimbyLogger` warnings/errors land in `Error_Log__c` — search for `FimbyDeletionController`, `FimbyDeletionIntakeService`, `FimbyDeletionConfirmationService`, `FimbyAccountDeactivationBatch` when investigating.

### Escalation

- A user disputes a completed deletion — restoration is **not possible** (the data is gone or anonymized). Reply with the canned *Deletion confirmed* template and acknowledge there is no undo.
- A user reports they did not request deletion but received a verification email — treat as a possible spoofing or account-takeover incident; open Section 5 (Breach) before doing anything to their account.
- The rate-limit-flagged path fires more than once a quarter — flag for follow-up code work per runbook §3.

---

## 3. Safety Reports

**Status:** `Ready`
**Public commitment:** From [`community-standards.html`](../FIMBY%20Website/community-standards.html) and `/community-guidelines`: *"We review every report within 24 hours."* Reports go to the neighbourhood moderator first, FIMBY team as backup. The moderation ladder is content removal → warning → temporary restriction → permanent removal.
**System anchors:** `fimbyReportContent` LWC (modal embedded across feed cards, detail pages, and the response-thread/reply kebabs), `FimbyContentReportController.submitContentReport`, `FimbyModeratorTaskService.createOrUpdateTask`, `Moderator_Task__c`, `Moderator_Task_Evidence__c`. Outcomes apply via `FimbyModeratorActionService` (see Section 8).
**Operator owner:** neighbourhood moderator (Contact with `Site_Moderator__c = true`); admin backup.

### How a report becomes a moderator task

1. Neighbour taps **Report** on the surface (or **Block & report** on a thread/reply kebab).
2. `fimbyReportContent` collects reason + optional details, posts to `FimbyContentReportController.submitContentReport`.
3. The controller builds a `FimbyModeratorTaskService.TaskRequest` and calls `createOrUpdateTask`.
4. `createOrUpdateTask` builds a dedup key — `<neighbourhoodId>:<category>:<relatedRecordType>:<relatedRecordId>` for content reports, falling back to `<neighbourhoodId>:<category>:<subjectContactId>` when the report is about a person not a record.
5. **If an open task with that dedup key exists** (`Status__c IN ('New', 'In_Progress', 'Awaiting_Info')`): `appendEvidence` increments `Report_Count__c`, stamps `Latest_Reported_Date__c`, escalates `Priority__c` upward if the new report is higher-priority, flips `Awaiting_Info` back to `In_Progress`, and inserts a new `Moderator_Task_Evidence__c`. **No second task is created.**
6. **If a recently-resolved task exists** (`Resolved_Date__c` within the last 24 hours): `reopenWithEvidence` brings it back to `New`, attaches the new evidence, and re-alerts moderators.
7. **Otherwise**: a brand-new `Moderator_Task__c` is inserted, the first `Moderator_Task_Evidence__c` is attached, and `FimbyModeratorAlertService.alertModerators` notifies the neighbourhood's moderator pool.

The neighbour who filed the report sees the [§11 *Report received* template](#report-received) confirmation in the modal — no separate operator action required.

### Evidence handling and confidentiality

Each report inserts a separate `Moderator_Task_Evidence__c` row with:

- `Reporter__c` — the reporting Contact (kept confidential by default; see public commitment in `community-standards.html`).
- `Reason_Code__c` — one of the reasons defined in `fimbyReportContent.reportReasons` (`inappropriate`, `spam`, `harassment`, `privacy`, `safety`, `other`).
- `Details__c` — the reporter's free-text optional context.
- `Source_Type__c` — usually `Content_Report`; `Block_Report` for the combined Block + report path; `Lifecycle_Request` for community-group close/delete.

**Reporter identity is confidential.** Do not include the reporter's name when contacting the subject of the report. The public commitment is: "We may disclose a reporter's identity only where required by law, by court order, or where necessary to prevent imminent harm to a person's safety." That is the only authority to break confidentiality.

### Priority and target response time

`Moderator_Task__c.Priority__c` is a restricted picklist: `Urgent`, `Standard` (default), `Low`. The per-priority target windows:

| Priority | Target | Notes |
|---|---|---|
| `Urgent` | within 1 hour during operator hours; within 4 hours overnight | Use for safety-of-life, sexualized minors, doxxing-with-real-time-risk |
| `Standard` | **within 24 hours** (matches the public commitment) | Default for most reports |
| `Low` | within 5 business days | Use for spam-only, low-grade nuisance |

`Moderator_Task__c.Hours_Open__c` (formula) and `Is_Overdue__c` (formula `Hours_Open__c > 24`) drive the dashboard's overdue badge — the moderator dashboard sorts and highlights overdue tasks automatically.

### Claim / handoff procedure

| Action | Field write | UI hook |
|---|---|---|
| Claim a task | `Claimed_Date__c = now()`, `OwnerId = <moderator user>`, `Status__c` flips `New` → `In_Progress` | `FimbyModeratorActionService.claimTask` |
| Hand off to another moderator | `OwnerId = <new owner user>` | `FimbyModeratorActionService.reassignTask` |
| Release back to the queue (cannot continue) | `Claimed_Date__c = null` | `FimbyModeratorActionService.releaseTask` |
| Park awaiting more info from the reporter or subject | `Status__c = 'Awaiting_Info'` (the next inbound report flips it back to `In_Progress`) | `FimbyModeratorActionService.requestMoreInfo` |
| Escalate to admin | `Status__c = 'Escalated'`, `Escalated_To__c = <admin>`, `Escalation_Reason__c = <text>` | `FimbyModeratorActionService.escalateTask` (also pages admin via `FimbyModeratorAlertService.alertAdmin`) |
| Resolve | `Status__c = 'Resolved'`, `Resolved_Date__c = now()`, `Resolved_By__c = <moderator>`, `Notes__c = <text>` | `FimbyModeratorActionService.resolveTask` |
| Re-open after a re-review request | `Re_Review_Requested__c = true`; if previously `Resolved`/`Dismissed`, `Status__c` flips back to `New` | `FimbyModeratorActionService.requestReReview` |

**Stale-task safety net:** `FimbyModeratorTaskStalenessJob` runs on a schedule and re-pages moderators on tasks that have been claimed but untouched for too long. Confirm it is scheduled in the org (Setup → Apex Jobs → Scheduled Jobs); if not, schedule it from anonymous Apex with `System.schedule('FIMBY Moderator Task Staleness', '<cron>', new FimbyModeratorTaskStalenessJob());`.

### Templates (neighbour-facing)

| Trigger | Template |
|---|---|
| Acknowledge the report (auto-shown in modal) | [§11 — *Report received* template](#report-received) |
| Need more context from the reporter | [§11 — *Safety report — more info needed* template](#safety-report--more-info-needed) |
| Action taken (content removed, warning issued, etc.) | [§11 — *Safety report — action taken* template](#safety-report--action-taken) |
| No action taken (report did not meet the standards) | [§11 — *Safety report — no action* template](#safety-report--no-action) |

### Audit trail

- Every action is on the `Moderator_Task__c` itself — `Decision_Reason_Code__c`, `Decision_Statement__c`, `Notes__c`, plus the timeline of `Claimed_Date__c`, `Resolved_Date__c`, etc.
- Every report (including duplicates) is preserved as a separate `Moderator_Task_Evidence__c` row.
- Content actions (hide / republish) are logged on the underlying record via `Hidden_By_Moderator__c`, `Hidden_Date__c`, `Hidden_Reason_Code__c` (Section 8 covers the hide/republish procedure).

### Escalation

- **Self-conflict-of-interest:** a moderator is named in a report (subject or reporter). They must release the task and let another moderator pick it up. The dashboard shows this clearly — do not work tasks where you are involved.
- **Cross-neighbourhood concerns** (someone reports content outside their neighbourhood) — escalate to admin; the moderator queue is neighbourhood-scoped by `FimbyModeratorQueryService` so a moderator may not even see the task.
- **Imminent safety risk** — page admin immediately AND advise the reporter (template) to call 911 or local emergency services. FIMBY is not an emergency service; this is a hard rule from `community-standards.html`.

---

## 4. Privacy Access Requests / Data Export

**Status:** `Manual v1` + `Needs operator approval` (target turnaround pending — see *Currently `Needs operator approval`*)
**Public commitment:** Privacy Policy "copy of your information on request" / data portability language.
**System anchors:** Manual export — no dedicated Apex service ships in v1. Salesforce Reports + workbench exports cover the object list below. If volume justifies it later, build `FimbyDataExportService` as a separate ticket.
**Operator owner:** sysadmin.

### Verification before fulfilling

A privacy access request must come **from the email address on the requesting account**, or be verified by one of:

- A reply to a verification email sent to `User.Email` (same pattern as deletion).
- A signed support relationship paper form on file (rare — the Privacy Policy notes that supportee-side requests can be made by the supportee directly through the supporter).
- For someone whose account has already been deleted: respond that the data they're asking for has been anonymized per the deletion procedure and cannot be reconstituted.

### Format and turnaround

- **Format (recommended default):** PDF cover letter + CSV per object that holds the requester's data. The cover letter explains what each CSV contains, what is excluded and why, and where to follow up.
- **Turnaround (recommended default):** **30 business days** target. Hedge in the reply with "we aim to fulfill within 30 business days; we will let you know if more time is needed". This is consistent with PIPA (BC) and PIPEDA expectations.
- **Operator decision needed:** confirm or override both choices. If the operator wants PDF-only, drop the CSVs and prepare the cover letter as a single document.

### Object coverage (everything the requester owns or authored, plus consent-gated records they are party to)

| Object | What to include | Notes |
|---|---|---|
| `Contact` | All PII fields, care preferences, "about" fields, identity flags, `Pronouns__c` | The requester's own row only |
| `User` profile/preferences | Notification toggles (`Push_*`, `Email_Alert_*`, `FIMBY_Operating_Updates_Enabled__c`), `Theme_Preference__c`, `TimeZoneSidKey`, `LocaleSidKey`, `LanguageLocaleKey`, `FIMBY_Summary_Emails__c`, `Include_Sundays__c`, `Quiet_Hours_Preference__c`, celebration flags | The requester's own User row |
| `Needs_Offers__c` | Asks, offers, bulk buys, events the requester posted (or had stamped on their behalf via `Posted_By__c` / `Contact__c`) | |
| `Response__c`, `Response_Message__c` | Responses the requester filed; messages they sent inside response threads | |
| `Story__c` | Shared Life posts the requester authored | |
| `Library_Item__c` | Library items the requester listed (`Owner_Contact__c` or `Listed_By__c`) | |
| `Lending_Request__c`, `Loaned_Item__c`, `Lending_History__c` | Both directions where the requester is involved (`Requested_By__c`, `Item_Owner__c`, `Owned_By__c`, `Loaned_To__c`) | History rows already store the relationship even after anonymization, so include them |
| `Conversation__c`, `Conversation_Member__c`, `Message__c` | Threads where the requester is a participant; messages they sent | Do not include other neighbours' private messages they were not party to |
| `Notification__c` | The requester's own notifications | |
| `Support_Relationship__c` | Both sides — relationships where the requester is the helper (`Contact__c`) or the supportee (`Related_Contact__c`) | |
| `Shared_Contact_Info__c` | Records the requester shared, and records shared with them | Both directions |
| `Blocked_Contact__c` | Both directions involving the requester | They are entitled to know who blocked them and who they blocked |
| `Feedback__c` | Records the requester filed | The targets of those reports stay confidential per Section 3 |
| `Bulk_Buy_Follow_Up__c` | Follow-ups filed by or about the requester | |
| `Giving_Receiving__c` | Gratitude tracking entries involving the requester | |
| `Thank_You_Badges__c` | Badges earned by the requester | |

### Excluded from export (and why)

| Object | Why excluded |
|---|---|
| `Error_Log__c` / `Error_Log_Event__e` | System telemetry, may contain other neighbours' references; not personal-data scope |
| `Moderator_Task__c` / `Moderator_Task_Evidence__c` | Confidential moderator workspace; tell the requester only the outcome that affected them, not the queue contents or the reporter identity |
| Salesforce `LoginHistory`, `SetupAuditTrail`, etc. | Standard system-audit tables; not personal-data export scope under PIPA/PIPEDA in this app's posture |
| Other neighbours' private data even when joined to the requester's records | E.g. another neighbour's full Contact record is **not** disclosed even if the requester has lent them an item; show only the lending-history row, not the other neighbour's profile data |

### Procedure

1. Verify the requester's identity (see above).
2. Reply with the [§11 — *Privacy access — request received* template](#privacy-access--request-received) acknowledging the request and stating the 30-business-day window.
3. Run Salesforce Reports for each object in the list above, filtered to the requester's Contact / User Id. Export each as CSV.
4. Compose a PDF cover letter using the [§11 — *Privacy access — export ready* template](#privacy-access--export-ready) — describe what each CSV contains, the exclusions, the redaction rule, and where to follow up.
5. Bundle the CSVs + PDF in a zip; deliver via the same Case thread (or via a secure channel if the requester prefers — confirm before sending).
6. Close the Case once delivery is confirmed.
7. Log the fulfillment in the monthly self-audit (Section 12).

### Templates

| Trigger | Template |
|---|---|
| Request received, acknowledging | [§11 — *Privacy access — request received*](#privacy-access--request-received) |
| Identity verification needed before fulfilment | [§11 — *Identity verification needed*](#identity-verification-needed) |
| Export ready and delivered | [§11 — *Privacy access — export ready*](#privacy-access--export-ready) |

### Audit trail

- The originating Case (with the verification + delivery thread).
- Monthly self-audit log entry (Section 12).

### Escalation

- The requester is a regulator or lawyer acting on behalf of someone — operator stops, hands to leadership before responding (per Section 1 escalation rule).
- The requester wants raw Salesforce object data the operator does not understand or cannot extract — escalate to admin for help; do not estimate.
- The 30-business-day window is going to slip — proactively reply before day 25 with an honest update and a new estimate.

---

## 5. Breach / Incident Response

**Status:** `Needs operator approval` (decision owner + threshold wording pending — see *Currently `Needs operator approval`*)
**Public commitment:** Privacy Policy "as soon as practicable, where required by law" wording.
**System anchors:** Monitoring sources — `Error_Log__c` (queryable history), `Error_Log_Event__e` (Platform Event stream), Salesforce SetupAuditTrail and LoginHistory.
**Operator owner (recommended default):** sysadmin makes the threshold call; church operations lead is the backup decision-maker. **Requires operator confirmation.**

> This section is an operations aid, not legal advice. The notification thresholds below are based on a plain reading of PIPA (BC) and PIPEDA. Final wording for thresholds and regulator notification timing should be reviewed by an operator with legal counsel before being relied on for a real incident.

### Monitoring sources and what triggers a check

| Source | What to look for | Cadence |
|---|---|---|
| `Error_Log__c` | Spikes in errors from `FimbyAuthService`, deletion-flow classes, `FimbyConversationController`, anything indicating data leaking across neighbourhoods | Weekly review minimum; spot-check on every operator login |
| `Error_Log_Event__e` (Platform Event) | Real-time stream — connect a dashboard widget or email subscription if volume warrants | Live |
| Salesforce SetupAuditTrail | Unexpected profile changes, sharing rule changes, new Connected Apps, new admins | Weekly review |
| Salesforce LoginHistory | Unusual login patterns for the operator account, failed login bursts | Weekly review |
| User reports | Inbound emails or in-app reports describing unexpected data visibility | Immediate response |

If anything triggers a check, open Section 5 even if the threshold is not yet known. **It is cheaper to open a breach log entry that turns out to be nothing than to discover a breach that should have been logged days earlier.**

### Breach log fields

Maintain a single internal breach log (recommended location: a dedicated tab on the operator's runbook spreadsheet, or a `Feedback__c` record with `Type__c = 'Incident'` if you prefer to keep it inside Salesforce). Each entry captures:

- Incident date — when the incident occurred (or earliest known occurrence)
- Discovered date — when FIMBY became aware
- Systems affected — which classes, queries, or Connected Apps
- Data categories affected — which object types and fields
- People affected — Contact Ids (or rough count if Ids not yet established)
- Containment — what was done to stop further exposure
- Root cause — once known
- Notification decision — see threshold matrix below
- Notification dates — regulator and individuals separately
- Post-incident review notes

### Severity triage

| Severity | Description | Response posture |
|---|---|---|
| `low operational issue` | A handful of records had a temporary visibility issue (e.g. caching bug); no PII exposed; contained inside the operator's neighbourhood | Document, fix, monitor — no notification |
| `suspected unauthorized access` | Logs suggest someone may have viewed or pulled data they should not have | Investigate immediately; assume notification will be required until proven otherwise |
| `confirmed personal information exposure` | Verified that PII left FIMBY's intended boundary (e.g. one neighbour saw another's address, a list export went to the wrong inbox) | Trigger notification thresholds below |
| `real risk of significant harm` | Confirmed exposure of high-sensitivity data (care preferences, identity flags, support relationships, contact info paired with location) **or** small-scale exposure with realistic harm (e.g. a stalker scenario) | Notify individuals + regulator on the short clock |

### Notification thresholds (PIPA BC + PIPEDA — operator/legal sign-off required)

This is a plain-reading summary; the actual statutory text governs.

- **PIPA (BC) — `Personal Information Protection Act`:** organizations must notify the BC Office of the Information and Privacy Commissioner (OIPC BC) and affected individuals "without unreasonable delay" if the breach could reasonably be expected to cause significant harm. "Significant harm" generally includes bodily harm, humiliation, damage to reputation, financial loss, identity theft, negative effects on credit record, or damage to property.
- **PIPEDA (federal) — `Personal Information Protection and Electronic Documents Act`:** organizations must notify the Office of the Privacy Commissioner of Canada (OPC) and affected individuals if it is reasonable in the circumstances to believe the breach creates "real risk of significant harm". The same significant-harm factors apply, plus consideration of the sensitivity of the data and probability of misuse.
- **In practice for FIMBY:** if the severity assessment lands on `confirmed personal information exposure` or higher, notify both regulators and the affected individuals. If it lands on `suspected unauthorized access` and investigation cannot rule out exposure within a reasonable time, default to notifying.

The operator/legal-approved version of these thresholds replaces the wording above when finalized.

### Templates

| Trigger | Template |
|---|---|
| Notify an affected individual | [§11 — *Breach — individual notification*](#breach--individual-notification) |
| Notify OIPC BC | [§11 — *Breach — OIPC BC notification*](#breach--oipc-bc-notification) |
| Notify OPC Canada | [§11 — *Breach — OPC Canada notification*](#breach--opc-canada-notification) |

### Post-incident review checklist

Within 30 days of containment:

- Root cause documented
- Code or configuration fix deployed
- New tests or monitoring rules added (if applicable)
- Breach log entry updated with notification dates and outcomes
- Operator-facing post-mortem (one page) circulated to leadership
- Public-page wording reviewed — does any commitment need updating?

### Audit trail

- Breach log itself.
- All Cases related to the incident.
- Apex/setup audit trail extracts attached to the breach log entry.
- Notification confirmations (regulator portal receipt + individual delivery records).

### Escalation

- Anything involving children, financial data, or identity theft — leadership immediately, before any further action.
- Anything that requires deactivating other accounts (e.g. the breach was caused by an insider) — leadership immediately.
- Regulator follow-up correspondence — operator stops, hands to leadership before responding.

---

## 6. CASL Log and Message Content Audit

**Status:** `Ready` (Plan A item A4 has shipped `User.FIMBY_Operating_Updates_Enabled__c`; CASL recurring rule as a `.cursor/rules/` is still pending — see *Currently `Needs operator approval`* row 5)
**Public commitment:** Privacy Policy notification/email sections; Help page settings references; the in-app Settings line on `fimbySettingsView` that reads "Occasional updates about FIMBY itself, including operating-cost requests from Strathcona Vineyard Church. Opting out doesn't affect your access to the app."
**System anchors:** `FimbyTransactionalEmailService`, `FimbyEmailAlertService`, `FimbyDigestEmailSendQueueable`, `Digest_Email_Log__c`, `FIMBY_Email_Template__mdt`, `User.FIMBY_Operating_Updates_Enabled__c` (default `true` under the CASL registered-charity exemption — see field description).
**Operator owner:** sysadmin.

### One-time pre-publication audit (run before any operating-update sends)

Walk every existing email and push template the FIMBY app sends and confirm:

- [ ] **Transactional messages contain no fundraising / growth / referral copy.** Reservation confirmations, loan approvals, response notifications, etc. are operational only — they describe the action and link the user back into the app.
- [ ] **Community digest contains no fundraising.** `FimbyDigestEmailSendQueueable` builds neighbourhood-level digests; verify the rendered HTML body has no donate links, fundraising copy, or operating-cost requests.
- [ ] **Sender identity is clear.** Every email footer must identify FIMBY as operated by Strathcona Vineyard Church and include a contact path (`help@fimby.com`).
- [ ] **"Updates about FIMBY itself" is its own message.** Operating-update emails must NOT be embedded in transactional or digest templates. Separate subject line, separate body, separate template.
- [ ] **Opt-out is honored.** Any code that sends an operating-update email must check `User.FIMBY_Operating_Updates_Enabled__c = true` before delivering. Until a dedicated send path exists, no operating-update emails should be sent at all.

Record completion of this audit in the monthly self-audit log; re-run after every batch of new templates.

### Recurring content rule

| Rule | Mechanism (today) | Future improvement |
|---|---|---|
| Every new email/push template must be reviewed against the CASL checklist before release | Manual checklist in this section | A `.cursor/rules/` rule with a glob on `**/email/**` and `**/push/**` that nudges the agent to surface this checklist (recommended default; pending operator approval) |
| Every new transactional notification type must wire push + email gates | `fimby-apex-patterns` rule already documents the four-step wiring checklist | Adequate today |
| Every operating-update send must check the opt-out field | Manual inspection of the sending code path | Future: a small `FimbyOperatingUpdatesService` class that all operating-update senders go through, with the opt-out filter built in |

### Audit trail

- **Digest emails:** `Digest_Email_Log__c` records one row per neighbourhood-build per cadence per window date (the row is keyed by `Idempotency_Key__c = {NeighbourhoodId}_{Cadence}_{WindowDate}` — there is no per-user component). Each row carries the rendered preview in `Email_Body_Preview__c`, a delimited list of successful recipients in `Recipients__c`, the failed recipients in `Failed_Recipients__c`, and a `Status__c` of `Sent`, `Partial`, `Failed`, or `Skipped`. Search `Status__c IN ('Failed', 'Partial')` weekly. A `Skipped` row is written even when the build had no feed-card content or no eligible recipients — the presence of one row per active neighbourhood per cadence per day is the proof of life. The deprecated `User__c` field on this object is no longer populated by new builds and will be removed once historical data has aged out of retention.
- **Transactional one-off emails:** `FimbyTransactionalEmailService` does not write a per-send log row. For v1, the audit trail is the originating Case note (when an email is sent in response to a request) plus the Apex log if there was a send error.
- **Operating-update sends (future):** when this channel is built, it must write a per-send log to either `Digest_Email_Log__c` (extend the schema) or a new `Operating_Update_Log__c` object so unsubscribe complaints can be reconstructed.
- **Unsubscribe events:** today, an operator manually flipping `User.FIMBY_Operating_Updates_Enabled__c = false` is captured by Field Audit Trail if enabled. If not enabled, log a Case note with the date and the user's request.

### Escalation

- A user complains they received a fundraising email after opting out — confirm via Field Audit Trail that their flag was off at the time of send. If yes, treat as a CASL breach: pause the operating-update channel, notify leadership, log to the breach section.
- Multiple users complain of unwanted emails in a short window — pause the channel and audit the most recent send batch before resuming.
- Counsel reverses the registered-charity exemption assumption — change the field default to `false`, push out an in-app prompt asking existing users for express opt-in consent, and document the change in the breach log even if no breach occurred (so the change history is preserved).

---

## 7. Supportee Verification

**Status:** `Ready` + `Needs operator approval` (retry policy pending — see *Currently `Needs operator approval`* row 4)
**Public commitment:** Privacy Policy supportee clauses; [`help.html`](../FIMBY%20Website/help.html) paper-form section.
**System anchors:** `Support_Relationship__c`, `FimbySupportRelationshipController`, `FimbySupportRelationshipReminderBatch`, `FimbySupportRelationshipEmailService`, paper-form classes (`FimbyAuthorizedSupporterFormController`, `FimbySupportRelationshipPaperFlowTest`, `FimbySupporteeActivationLetterController`).
**Operator owner:** sysadmin (queue member during `Pending Paper Review` and `Pending Verification` workflows).

> **The full procedure lives in [`runbooks/supportee-verification.md`](./runbooks/supportee-verification.md).** That runbook covers the lifecycle (`Draft` → `Pending Paper Review` → `Pending Verification` → `Approved` / `Rejected` / `Expired`), the three-tier verification (Phone Call → Postal Letter → Activation Letter), edge cases, and the trigger-driven side effects.

This playbook section adds **what the runbook does not** — the public-commitment cross-reference, the recommended retry policy, and the at-a-glance decision-tree summary.

### Public-commitment cross-reference

| Public page promise | Deployed mechanism |
|---|---|
| "If you're helping a neighbour who can't use the app themselves, they can still consent to these Terms by signing a printable form" | Paper-form path; runbook §1 |
| "Your supporter cannot consent on your behalf — only you can" | Block C of `FimbyAuthorizedSupporterForm.page` requires the supportee's initials; trigger requires `Status__c = 'Approved'` from a human admin before TOS is stamped |
| "We may verify consent directly with you where contact details allow it before activating the relationship" | Three-tier verification process (runbook §2) |
| **Plan A A1 (now shipped) addition: also stamps age attestation on approval** | `FimbyTosController.recordPaperAcceptance` writes both TOS and age fields per A1 — see updated note below |

### Plan A coordination — runbook update needed

After Plan A item A1 shipped, `FimbyTosController.recordPaperAcceptance` now stamps both TOS *and* age attestation fields when the paper-form path approves a supportee. The runbook's `## 4. What gets stamped where` section needs a one-line update:

> **When you set `Status__c = Approved`, the `FimbySupportRelationshipTriggerHandler`:**
>
> - Calls `FimbyTosController.recordPaperAcceptance` which writes the Contact's `Tos_Accepted_Date__c`, `Tos_Version_Accepted__c`, `Tos_Acceptance_Source__c = Support Relationship Paper Form`, `Tos_Acceptance_Form_Id__c`, **`Age_Attestation_Confirmed__c = true`, `Age_Attestation_Date__c` (matching the TOS stamp), and `Age_Attestation_Source__c = Support Relationship Paper Form`**.

When the runbook is next edited, fold this in. The functional behavior already matches what's deployed; the runbook is the only piece that needs the wording update.

### Retry policy (recommended default)

When supportee verification cannot reach the supportee on the first try:

- **Phone (Tier 1):** **3 attempts across at least 10 business days**, varying time of day. After the third no-answer, fall through to Tier 2.
- **Postal letter (Tier 2):** one letter, 14-day cooling-off window for response. Silence after 14 days = consent (passive verification).
- **Activation letter (Tier 3):** sent regardless of how Tiers 1/2 resolved, immediately on `Status__c = Approved`.

Operator decision needed to confirm or override. Until confirmed, follow the recommended default and surface in monthly self-audit.

### Decision tree summary (quick reference)

```
                       ┌─────────────────────────────────┐
                       │ Pending Verification work item  │
                       └────────────┬────────────────────┘
                                    │
                  Try Tier 1 phone — 3 attempts / 10 days
                                    │
                ┌───────────────────┼───────────────────┐
                │                   │                   │
        Supportee confirms     Supportee declines     No answer
                │                   │                   │
   Set Subject_Confirmed__c   Set Status__c          Tier 2 letter
   = true; Subject_Confirmed_  = Rejected;             │
   Date__c = now();            Rejection_Reason__c    14 days silence
   Consent_Method__c =         + detail               │
   Phone Call;                 Trigger notifies        Status__c = Approved
   Status__c = Approved        supporter               (passive)
   Trigger stamps TOS + age                            Trigger stamps TOS + age
   fields, sends approval                              fields, sends approval
   email, creates activation                           email, creates activation
   letter task                                         letter task
```

If the supportee cannot consent at all (cognitive impairment, non-English speaker without translator, no contact path that works) — do not approve. Route to human support with the `Supportee cannot consent — route to human support` reason code on `Rejection_Reason__c`. Per `terms-of-service.html` section 10: FIMBY does not currently support legal representatives or BC Representation Agreements. A future version may.

### Templates

| Trigger | Template |
|---|---|
| Phone verification opening script | [§11 — *Supportee verification — phone script*](#supportee-verification--phone-script) |
| Postal verification letter | [§11 — *Supportee verification — postal letter*](#supportee-verification--postal-letter) |
| Activation letter (Tier 3, always sent on approval) | Generated from `FimbySupporteeActivationLetter.page` (Visualforce); see runbook §2 |

### Audit trail

- `Support_Relationship__c` fields: `Subject_Confirmed__c`, `Subject_Confirmed_Date__c`, `Consent_Method__c`, `Verification_Method__c`, `Verification_Date__c`, `Verification_Notes__c`, `Activation_Letter_Sent_Date__c`, `Approved_By__c`, `Approved_Date__c`, `Ended_By__c`, `Ended_Date__c`, `Rejection_Reason__c`, `Rejection_Reason_Detail__c`.
- Trigger-fired emails are sent via `FimbySupportRelationshipEmailService`.
- Manual operator notes: write into `Verification_Notes__c` on the relationship record itself, not in a separate Case.

### Escalation

- A pattern of one supporter repeatedly being declined by different supportees — flag to admin. May be a coercion or fraud signal.
- Witness signature on the paper form looks suspicious (signature mismatch, witness has same family name) — do a Tier 1 phone check on the witness as well.
- Anything involving suspected elder abuse, financial coercion, or emotional manipulation — pause the verification, document, escalate to leadership immediately.

---

## 8. Moderation Day-One Operations

**Status:** `Ready`
**Moderator dashboard URL:** https://our.fimby.com/moderator-dashboard
**Public commitment:** [`community-standards.html`](../FIMBY%20Website/community-standards.html) moderation ladder; `/community-guidelines` 24h commitment.
**System anchors:** `Contact.Site_Moderator__c` (Boolean), `Moderator_Assignment__c` (per-neighbourhood moderator linkage), `Moderator_Task__c` (the work queue), `FimbyModeratorActionService` (claim/release/resolve/escalate/hide/republish actions), `FimbyModeratorTaskStalenessJob` (re-pages stuck claimed tasks), `fimbyModeratorDashboard` (LWC).
**Operator owner:** neighbourhood moderator(s) per neighbourhood; admin oversight.

### Neighbourhood scope reminder

Moderator queries are neighbourhood-scoped via `FimbyModeratorQueryService`. Do not document workarounds that bypass that scope. If a moderator legitimately needs to see a task outside their neighbourhood (e.g. cross-neighbourhood pattern investigation), the admin handles it — moderators stay inside their neighbourhood.

### Dashboard route note

The moderator dashboard lives at https://our.fimby.com/moderator-dashboard (Experience Builder page hosting the `fimbyModeratorDashboard` LWC). The route does not currently appear in the [`fimby-architecture`](../../.cursor/rules/fimby-architecture.mdc) `TAB_ROUTES` map — that map is used for the bottom-nav tab-highlighting logic in `fimbyUniversalHeader`, and the moderator dashboard intentionally does not appear in the bottom nav (moderators bookmark the URL directly). If a future change adds the dashboard to the bottom nav, add the prefix to `TAB_ROUTES` at the same time.

### Who can moderate

- A Contact with `Site_Moderator__c = true` is eligible to be assigned moderator tasks.
- `Moderator_Assignment__c` (per-neighbourhood linkage) records which moderator owns which neighbourhood. The active assignments drive `FimbyModeratorQueryService`'s scoping.
- **Operator decision:** confirm during discovery whether `Site_Moderator__c = true` alone is sufficient, or whether a Permission Set is also required to grant access to the dashboard. As of the current org state, `Site_Moderator__c` is the only Apex-side check; Permission Set requirements (if any) live in profile-level CRUD on `Moderator_Task__c` and may need separate setup.

### Daily queue review

1. Open the moderator dashboard (URL confirmed above).
2. Sort by `Is_Overdue__c = true`, then by `Priority__c` (Urgent → Standard → Low), then by `Latest_Reported_Date__c` ascending (oldest first).
3. Claim a task: `FimbyModeratorActionService.claimTask` (or the dashboard button equivalent). Stamps `Claimed_Date__c`, sets `OwnerId`, flips `New` → `In_Progress`.
4. Open the related record (the dashboard's "View" deep-link uses `Related_Record_Id__c` + `Related_Record_Type__c`).
5. Apply an enforcement decision (see below).
6. Resolve the task with `Decision_Reason_Code__c`, `Decision_Statement__c`, and brief `Notes__c`.

### Enforcement-level guidance (`Moderator_Task__c.Enforcement_Level__c`)

Use the API names exactly — they drive downstream automation and cross-neighbourhood reporting.

| Level | When to use | Effect |
|---|---|---|
| `None` | The report did not surface a Standards issue (false positive, misunderstanding, content already removed by author) | Resolve the task; no enforcement |
| `Check_In` | The post crossed a line but the author likely did not intend harm; a warm conversation will fix it | Issued by `FimbyModeratorActionService.issueCheckIn`; stamps `Decision_Reason_Code__c`, `Decision_Statement__c` |
| `Recorded_Concern` | The pattern is concerning but does not yet warrant restriction; logged so escalation history exists if it repeats | `FimbyModeratorActionService.recordConcern`; same fields |
| `Admin_Review` | The matter exceeds moderator authority — restriction, ban, or appeal handling needed | Escalate via `FimbyModeratorActionService.escalateTask`; admin takes over |

Account-level ban is a separate path — `Contact.Status__c = 'Banned User'` triggers automatic `User.IsActive = false` (per the UGC publish-readiness flow). Banning is admin-only, never a moderator action.

### Content hide / republish

- Hide a piece of content: `FimbyModeratorActionService.flagContent(recordId, recordType, flagValue, moderatorContactId)` — sets `Moderation_Status__c = 'Hidden_By_Moderator'` and stamps `Hidden_By_Moderator__c`, `Hidden_Date__c`, `Hidden_Reason_Code__c` on the underlying record (`Needs_Offers__c`, `Response__c`, `Story__c`, or `Library_Item__c`).
- Republish: `FimbyModeratorActionService.republishContent(recordId, recordType, taskId)` — sets `Moderation_Status__c = 'Visible'`, clears the `Hidden_*` fields, optionally resolves the task in the same call.
- Keep content hidden after review: `FimbyModeratorActionService.keepContentHidden(taskId, reasonCode, statement, notes, moderatorContactId)` — flags the content via the same path AND records the decision on the task.

### Appeal / re-review

- A user appeals a moderation decision via email to `help@fimby.com` — operator records the appeal on the original `Moderator_Task__c` and calls `FimbyModeratorActionService.requestReReview(taskId)`. This sets `Re_Review_Requested__c = true` and (if the task was already `Resolved` or `Dismissed`) flips `Status__c` back to `New`.
- A different moderator picks it up — the original moderator does not re-handle their own decision. The dashboard makes this routing visible.

### Training and confidentiality expectations

- New moderators read this section + Section 3 + the [`fimby-design-philosophy`](../../.cursor/rules/fimby-design-philosophy.mdc) language rules before claiming their first task.
- Reporter identity is confidential by default. The only authority to break confidentiality is the public-commitment rule from Section 3: legal requirement, court order, or imminent harm.
- Moderator-task content is not for casual sharing — even with other moderators outside the neighbourhood the report originated in.
- Conflict of interest: a moderator named in a report (subject or reporter) must release the task and let another moderator pick it up.

### Templates

The neighbour-facing templates moderators use are in Section 11 — see [Section 3 templates](#3-safety-reports). This section's day-one ops do not introduce new templates.

### Audit trail

- All decisions land on `Moderator_Task__c` itself.
- Content actions are mirrored on the underlying record (`Hidden_*` fields).
- Account-level enforcement (ban) is mirrored on `Contact.Status__c` and the related `User.IsActive`.
- `FimbyModeratorTaskStalenessJob` log entries surface in `Error_Log__c` if scheduled and runs encounter exceptions.

### Escalation

- Conflict of interest — release and rotate.
- Moderator decision is contested by the subject AND the reporter (rare) — escalate to admin; let admin do the re-review.
- Pattern of bad-faith reports from a single Contact — escalate to admin; admin may ban the bad-faith reporter under the Standards.

---

## 9. Succession / Shutdown

**Status:** `Manual v1` + `Needs operator approval` (notice window pending — see *Currently `Needs operator approval`* row 2)
**Public commitment:** [`terms-of-service.html`](../FIMBY%20Website/terms-of-service.html) section 20 (Assignment) + section 16 (Ending your account). Strathcona Vineyard Church may assign FIMBY to a successor organization; users may delete their accounts before any transfer; no transfer of personal data to a successor without fresh consent where required.
**System anchors:** None code-side. This is a manual operator + leadership procedure; the playbook IS the source of truth.
**Operator owner:** Strathcona Vineyard Church operations lead, with sysadmin executing the technical steps.

### Trigger events

Open this section when any of:

- Strathcona Vineyard Church is dissolving, merging, or transferring FIMBY to another operator.
- The decision is made to shut FIMBY down (planned wind-down).
- A material change in operator obligations (e.g. the church's charitable status changes in a way that affects CASL exemption handling — see Section 6).
- An emergency forces an unplanned shutdown (security incident, infrastructure loss, regulator order). Use the same procedure on a compressed clock.

### Notice window (recommended default)

- **Planned succession or shutdown:** **90 days** notice from the announcement date. Users get 90 days to read the notice, export their data (Section 4), and delete their account (Section 2) before any transfer takes effect.
- **Urgent shutdown:** as much notice as practical, with the reason explained honestly. Even a 7-day notice is preferable to going dark.
- **Operator decision needed:** confirm or override the 90-day default. Until confirmed, follow the recommended default.

### Notice channels (use all three for planned events)

| Channel | What to do | Timing |
|---|---|---|
| In-app banner | Add a persistent banner across the FIMBY1 site explaining the change, the date, and what users can do. Use the [§11 — *Succession — in-app banner*](#succession--in-app-banner) template. | Day 0 of the notice window |
| Email blast | Send to every active user. Use the [§11 — *Succession — email blast*](#succession--email-blast) template. | Day 0 of the notice window, and again at day -30 + day -7 |
| Public posting on `www.fimby.com` | Replace the relevant section of the public site with the [§11 — *Succession — public posting*](#succession--public-posting) template, plus a stable contact path for questions. | Day 0 of the notice window |

For urgent shutdown: same channels, compressed timing, honest hedge in the language ("we are turning off FIMBY on <date> because <reason>; we know this is short notice").

### Deletion / export window before shutdown or transfer

The notice window is also the user's **export-and-delete window**:

- The Privacy Access Request flow (Section 4) remains open; reduce the target turnaround to match the notice window if needed.
- The Account Deletion flow (Section 2) remains open. Encourage users to use it explicitly in the notice templates.
- After the deletion/export window closes:
  - For **shutdown:** the data deletion path runs to completion. `FimbyAccountDeactivationBatch` processes any remaining `Deactivation_Requested__c = true` Contacts; admin then runs a final pass to anonymize/delete the rest per the agreed retention policy.
  - For **transfer:** see fresh-consent protocol below.

### Fresh consent protocol (transfers only)

> No transfer of personal data to a successor operator without separate, explicit consent for that successor, where required.

For each user in the org at the end of the notice window:

1. Send a separate consent request email — not bundled with the succession notice. Use the [§11 — *Succession — fresh consent request*](#succession--fresh-consent-request) template.
2. Require an affirmative reply (or click-through in the app) confirming the user agrees to their data moving to `<successor name>` under `<successor's terms link>`.
3. Users who do not affirmatively consent within the response window have their data deleted/anonymized per the deletion procedure before the transfer happens — the successor never receives that data.
4. Users who did not interact at all during the notice window (truly inactive accounts) are treated as "did not consent" — delete their data before the transfer.

The successor receives only the data of users who affirmatively consented. The legal advice is: this avoids the trap of assuming PIPA/PIPEDA's exception for transferring personal information as part of a corporate transaction applies in the church-charity context. When in doubt, default to delete-before-transfer rather than transfer-then-ask.

### Templates

| Trigger | Template |
|---|---|
| In-app banner copy | [§11 — *Succession — in-app banner*](#succession--in-app-banner) |
| Email blast to all users | [§11 — *Succession — email blast*](#succession--email-blast) |
| Public posting on `www.fimby.com` | [§11 — *Succession — public posting*](#succession--public-posting) |
| Fresh-consent request (transfers only) | [§11 — *Succession — fresh consent request*](#succession--fresh-consent-request) |

### Audit trail

- Decision to trigger this section: leadership-level minutes/notes, attached to a master succession Case.
- All notice sends: in the master Case (banner, emails, public posting URL).
- Per-user fresh-consent responses: log in a dedicated CSV attached to the master Case (`Contact Id, response date, response: consent | deny | no response`).
- Final deletion pass: `FimbyAccountDeactivationBatch` results.
- Any remaining data after transfer: the successor must receive an explicit hand-off list with consent evidence per user.

### Escalation

- Anything legal-shaped about the transfer (the successor's compliance posture, regulator inquiries, unhappy users with legal counsel) — operator stops, leadership and counsel handle.
- Insufficient notice window forced by external events — leadership signs off on the compressed timeline before the notices go out, and the breach log captures the deviation from the agreed default.
- Successor wants to skip fresh-consent — refuse; this is a hard rule from `terms-of-service.html` section 20.

---

## 10. IP Complaint Intake Template

**Status:** `Ready`
**Public commitment:** [`terms-of-service.html`](../FIMBY%20Website/terms-of-service.html) section 9 (Copyright and intellectual property complaints) and the parallel section in [`community-standards.html`](../FIMBY%20Website/community-standards.html). Notice-and-takedown posture, not a formal DMCA program.
**System anchors:** Manual; uses the standard `Support` Case record type and a canned reply.
**Operator owner:** sysadmin (admin escalation for actual takedown decisions if disputed).

### When to use this

A neighbour or third party emails `help@fimby.com` claiming content on FIMBY infringes their copyright or other IP rights.

### What the public page promises (the contract you're working from)

> If you believe content on FIMBY infringes your copyright or other intellectual property rights, please email **help@fimby.com** with:
> - the URL or in-app location of the content;
> - a description of the work you say is being infringed;
> - your contact information; and
> - a statement that you have a good-faith basis to believe the content is infringing.
>
> We may remove or restrict access to allegedly infringing content while we review the complaint. Repeat infringers and accounts with repeated violations may have features limited or accounts terminated.

### Procedure

1. **Acknowledge within 5 business days** using the [§11 — *IP complaint — intake reply*](#ip-complaint--intake-reply) template. The template asks for the four required pieces of information (URL/location, work description, contact, good-faith statement) plus authority to act if the complainant is acting for someone else.
2. **Tag the Case** subject with `[IP Complaint]` so it surfaces separately in the operator's view.
3. **Optionally hide the content while reviewing** — if the content is high-risk (commercially valuable IP, named individuals, identifiable trademark), the moderator can hide it via `FimbyModeratorActionService.flagContent` (Section 8) pending review. Document this on the Case so the takedown decision and the temporary hide are not conflated.
4. **Review the complaint:**
   - Does it identify specific content (URL/in-app location)?
   - Does the complainant claim a specific right (copyright, trademark, name-and-image)?
   - Is the good-faith statement included?
   - If the complainant is acting for someone else, is there explicit authorization?
   - If any of these is missing, reply asking for the missing piece(s) before proceeding.
5. **Decide:** if the complaint looks valid, remove or restrict the content (Section 8 hide procedure). Notify the content's author with a neutral message explaining the takedown and pointing them at `help@fimby.com` for counter-notice.
6. **Repeat-infringer tracking:** if the same content author appears in a third valid IP complaint, escalate to admin for restriction or account termination.
7. **Counter-notice handling:** if the author disputes the takedown, reply asking for their basis for believing the content is non-infringing. Forward to admin / leadership for the final call. Restoration is admin-only.
8. **Close the Case** when the takedown / non-takedown is recorded.

### Template

| Trigger | Template |
|---|---|
| Acknowledge an IP complaint and request the four required pieces of information | [§11 — *IP complaint — intake reply*](#ip-complaint--intake-reply) |

### Audit trail

- The `Support` Case with the `[IP Complaint]` subject tag.
- If content was hidden: the underlying record's `Hidden_*` fields (Section 8).
- A repeat-infringer note appended to the offending author's `Contact.Notes` or a dedicated audit field if you create one.

### Escalation

- The complainant is a lawyer — operator acknowledges receipt only, hands to leadership before any substantive reply.
- The content is the subject of an active legal proceeding — leadership immediately.
- Counter-notices, in general — admin handles restoration calls.

---

## 11. Shared Response Templates

> **Tone is governed by the [`fimby-design-philosophy`](../../.cursor/rules/fimby-design-philosophy.mdc) rule.** Quoting the rule's "Language & Tone" section verbatim:
>
> | Instead of | Use |
> |---|---|
> | Report / Flag / Violation | Check-in / Follow-up |
> | Escalate | Ask for Help |
> | Penalty / Consequence | Recorded in Bulk Buy History |
> | "You failed to..." | "Were you able to sort things out?" |
> | No-show | "No response was received" |
>
> **Forbidden words in templates** unless quoting required legal text: `violation`, `penalty`, `failed`, `no-show`, `escalate`. If a template needs one of these (e.g. the breach notification's reference to a regulatory threshold), the legal language is wrapped in clearly-marked quote blocks and signed off by the operator/legal owner.
>
> **Always Show Identity (from the design philosophy rule):** any operator-sent message that touches the represented-identity model (e.g. supportee verification, group-rep notifications) must name both the helper and the supportee/group, not just one.

Each template is a starting point. Edit names, dates, links, and any neighbour-specific context — but keep the structure and tone intact. Sign-off: the operator's first name + role.

---

### Deletion confirmed

**Subject:** Your FIMBY account is now closed
**Body:**

> Hi <first name>,
>
> This is to confirm that your FIMBY account is closed. You won't receive any more emails or notifications from us, and you can't sign back in with this address.
>
> A few things you might want to know:
>
> - **Your posts, stories, library listings, and direct messages have been removed** within the last 24 hours.
> - **Your Contact record stays as an anonymized stub** — "A former neighbour" with all your personal details cleared. This is so blocks you put in place stay in place, and so neighbours you lent things to still see a name on the loan history (they don't see yours).
> - **Reports you filed are kept for 90 days, then anonymized** — that gives our team a window to act on them, then your connection to those reports ends.
>
> If you change your mind in the next few hours and didn't actually mean to do this, reply right away and we'll see if there's anything we can do. After 24 hours, the deletion is final and we can't restore the account.
>
> Take care,
> <Operator first name> — FIMBY support

---

### Deletion deferred for active loans

**Subject:** Your FIMBY account is closed — one note about your library activity
**Body:**

> Hi <first name>,
>
> Your account is closed and you can't sign back in. The data deletion piece is paused for one specific reason: you have <N> active borrow/lend item(s) on the go. We hold off on removing your records until those items are returned, so the other neighbour involved isn't left with a half-finished history.
>
> Once the loans wrap up, our nightly process picks you up and finishes the data scrub described at our /delete-account page.
>
> While you're waiting, the other neighbour sees "A former neighbour" instead of your name on the loan record.
>
> If you'd like to follow up about a specific loan, reply here and I'll help.
>
> <Operator first name> — FIMBY support

---

### Manual deletion completed

**Subject:** Your FIMBY account is now closed (handled directly)
**Body:**

> Hi <first name>,
>
> I've gone ahead and processed your account closure directly. You won't be able to sign in, and your data is being scrubbed per our normal deletion procedure described at our /delete-account page.
>
> The reason I handled this manually instead of through the email confirmation flow: <one-line context — e.g. "the verification email bounced", "you confirmed by phone last Tuesday">.
>
> Take care,
> <Operator first name> — FIMBY support

---

### Privacy access — request received

**Subject:** Your FIMBY data request — we're on it
**Body:**

> Hi <first name>,
>
> Thanks for reaching out. We received your request for a copy of the information FIMBY holds about you.
>
> A few things to set expectations:
>
> - **We aim to fulfill within 30 business days.** If we need more time, I'll let you know before the window runs out — we won't go silent.
> - **Format:** I'll send a PDF cover letter explaining what's included, plus CSV files for each kind of data (your posts, your messages, your library activity, etc.). If you'd prefer a different format, let me know.
> - **Identity check first:** I need to be sure the request is coming from the account holder, so I'll usually send a verification email to your account address before pulling the data. If you got that email already, just reply to confirm.
>
> Talk soon,
> <Operator first name> — FIMBY support

---

### Identity verification needed

**Subject:** A quick check before I send your FIMBY data
**Body:**

> Hi <first name>,
>
> To make sure I'm sending your data to you and not to someone pretending to be you, I need a quick confirmation:
>
> Please reply to this email from the address on your FIMBY account. That's the same address you use to sign in, and it's our way of being sure the request is genuinely from you.
>
> Once I have that confirmation, I'll get to work on your export and aim to have it back to you within 30 business days.
>
> Talk soon,
> <Operator first name> — FIMBY support

---

### Privacy access — export ready

**Subject:** Your FIMBY data export is ready
**Body:**

> Hi <first name>,
>
> Your data export is attached as a zip file. Here's what's inside:
>
> - **`README.pdf`** — a plain-language guide to the rest of the files.
> - **One CSV per kind of data** — your Contact profile, your posts, your responses, your messages, your library activity, your support relationships, your blocks, your shared contact info, your feedback, your bulk buys, your gratitude entries, your badges.
>
> What's not included, and why:
>
> - **Other neighbours' private information.** Even when you and another neighbour are on the same record, we only share your side of it. Their full Contact details, their messages with other people, and similar are kept private.
> - **Internal moderator records.** If you reported something or were the subject of a report, you'll see the outcome that affected you, but not the moderator queue contents or the identities of other people involved.
> - **System telemetry** (error logs, login history, etc.). Those aren't personal data in the sense the privacy laws intend; they're operational records.
>
> Have a look at the README first — it points you at the right file for whatever you're trying to find. If anything's missing or you have questions, reply here.
>
> Take care,
> <Operator first name> — FIMBY support

---

### Report received

> *(This is the in-app confirmation shown by `fimbyReportContent` when a report submits successfully — already deployed. No operator action required. Included here for reference so the wording stays in sync.)*
>
> **Title:** Thanks for the heads-up
>
> **Body:**
>
> > We'll take a look. A moderator will review this within 24 hours and follow up if needed.
> >
> > Your report is private — the person you reported is not told who flagged the content.
> >
> > [Read the Community Guidelines](/community-guidelines)
> > [Need help? Contact your neighbourhood moderator](/help-and-support)
> > [Urgent safety concern? Email safety@fimby.ca](mailto:safety@fimby.ca)

---

### Safety report — more info needed

**Subject:** Quick question about the report you filed
**Body:**

> Hi <first name>,
>
> Thanks for letting us know about <thing they reported, in plain language — e.g. "the comment on the bulk buy">. Before I can do much with it, I'd like a little more context:
>
> - <Specific question 1 — e.g. "Was this the first time you noticed this kind of comment from this neighbour, or has it happened before?">
> - <Specific question 2 — e.g. "Is there anything in particular you'd like the outcome to be — content removed, a quiet word with the person, or something else?">
>
> No rush — reply when it suits you. I'll keep the report open in the meantime, and we won't share your name with the person involved.
>
> <Operator first name> — FIMBY moderator team

---

### Safety report — action taken

**Subject:** A note about the report you filed
**Body:**

> Hi <first name>,
>
> Thanks again for telling us about <thing they reported>. After taking a look, here's what we did:
>
> - <Specific action — e.g. "We removed the comment.", "We had a check-in with the person about how they were speaking to neighbours.", "We've recorded the concern so we can act faster if anything similar comes up.">
>
> Your name was not shared with the person involved.
>
> If you notice anything else along these lines, the report tools on every post, story, library item, and message thread are still there. And you can always email me directly.
>
> <Operator first name> — FIMBY moderator team

---

### Safety report — no action

**Subject:** A note about the report you filed
**Body:**

> Hi <first name>,
>
> Thanks for letting us know about <thing they reported>. After looking at it, this is one we're not going to act on — here's why:
>
> <One-paragraph plain-language explanation. Avoid "violation" or "did not breach" language. Try: "What you described is the kind of thing neighbours can disagree about without it crossing a line into the standards we apply.", or "The post you flagged is from outside FIMBY, so it isn't something we can remove from here.">
>
> If you'd rather not see this neighbour's posts or messages, the **block** option in their profile or in your message thread with them is the quickest way. They aren't told you blocked them.
>
> If something else comes up that does need our attention, please report again — we'd rather get an extra report than miss something.
>
> <Operator first name> — FIMBY moderator team

---

### Supportee verification — phone script

> **Use this on Tier 1 phone verification per Section 7.** The goal is a 2-3 minute warm conversation that confirms the supportee actually wants the help relationship to be set up. Stay in the supportee's language and pace; if you're not getting clear answers, slow down or call back another time.

> *Hello, is this <Supportee First Name>?*
>
> *My name is <Operator first name>. I'm calling from FIMBY — that's the neighbourhood app that <Supporter Full Name> uses, and they've asked us to set up a way for them to help you on the app. Before we do anything, I just wanted to talk to you for a minute to make sure that's something you're actually wanting.*
>
> *Is now a good time, or should I call back?*
>
> [If yes:]
>
> *A few things I want to check with you, just so I know we're doing this right:*
>
> 1. *Do you remember signing a paper form recently — it had three sections you initialled, with <Supporter First Name>'s name on it?*
> 2. *Was the idea to let <Supporter First Name> use FIMBY on your behalf — to help with things like asking neighbours for a hand, sharing news, that kind of thing?*
> 3. *Did anyone tell you that you had to sign it, or pressure you in any way?*
> 4. *Are you doing this freely, because it's something that would actually help you?*
> 5. *Is there anything you want to ask me before we go ahead?*
>
> [If they confirm: ] *That's great. I'll get the relationship set up today, and we'll mail you a letter at <address> with a phone number you can call any time if you want to end it. You don't need to give a reason — just call. Take care.*
>
> [If they decline or sound coerced: ] *That's okay — we won't set anything up. I'll let <Supporter First Name> know we couldn't get this confirmed, but I won't share what you said. If anything changes, you or anyone helping you can reach me at <number/email>. Take care.*

After the call, write the conversation summary into `Support_Relationship__c.Verification_Notes__c` and set `Verification_Method__c = 'Phone Call'`, `Verification_Date__c = today`. Then set `Status__c = 'Approved'` (the trigger handles the rest) or set `Status__c = 'Rejected'` with `Rejection_Reason__c = 'Supportee declined'` and detail.

---

### Supportee verification — postal letter

> **Mail this on Tier 2 fallback per Section 7** when phone verification doesn't reach the supportee after 3 attempts across 10 business days. Print on plain letterhead, sign by hand.

> Dear <Supportee Full Name>,
>
> My name is <Operator full name> and I'm writing from FIMBY — a neighbourhood app that <Supporter Full Name> uses.
>
> <Supporter Full Name> recently signed a form with you, designating themselves as your authorized supporter on FIMBY. Before we activate that relationship, I'd like to confirm with you directly that this is something you want to set up.
>
> If yes — there's nothing more for you to do. We'll go ahead 14 days from the date of this letter.
>
> **If no, or if you'd like to ask me anything first**, please call or text me at <phone number> or email <email>. There's no deadline if you'd just like to talk.
>
> If at any point in the future you change your mind, you can also call or text the same number to end the relationship. You don't need to give a reason.
>
> Thank you,
> <Operator full name> — FIMBY support
>
> <Date>
> <Address block>

After mailing, set `Verification_Method__c = 'Postal Letter'`, `Verification_Date__c = today`, write a note in `Verification_Notes__c`. Wait 14 days. Silence after 14 days = consent (passive verification); set `Status__c = 'Approved'`. If they call back to decline, set `Status__c = 'Rejected'` with the appropriate reason.

---

### Breach — individual notification

> **Use this template after the operator decision-owner has confirmed the breach meets the notification threshold** (see Section 5). Adjust language to the specific incident; the structure is fixed so notifications are recognizable across regulator/individual recipients.

**Subject:** Important: a security incident affecting your FIMBY account
**Body:**

> Hi <first name>,
>
> I'm writing to let you know that we discovered a security incident on FIMBY on <date> that may have involved information related to your account. I want to be straightforward about what happened, what data was involved, what we've done about it, and what you can do.
>
> **What happened:** <plain-language description of the incident — e.g. "A bug in our messaging code allowed a small group of users to see message previews from people they weren't actually in conversation with. We caught it on <date> and pushed a fix the same day.">
>
> **What information was involved:** <specific data categories — e.g. "Message preview text (first 100 characters of the message body) for messages between <date1> and <date2>. No phone numbers, addresses, or login credentials were involved.">
>
> **What we've done:** <plain-language remediation — e.g. "We deployed a code fix on <date>. We reviewed our logs and identified the affected accounts. We've notified the BC Office of the Information and Privacy Commissioner.">
>
> **What this means for you:** <plain-language risk + recommended steps — e.g. "Because no contact information or credentials were exposed, we don't think you need to change anything. If you'd prefer to delete your account or any of the affected messages, the steps are at our /delete-account page.">
>
> **Where to ask follow-up questions:** Reply to this email or contact me at help@fimby.com.
>
> I'm sorry this happened. We take this seriously and we're committed to being upfront with you about it.
>
> <Operator first name> — FIMBY support
> Strathcona Vineyard Church (operator of FIMBY)

---

### Breach — OIPC BC notification

> **Use the OIPC BC PIPA breach reporting form** (currently at https://www.oipc.bc.ca/ — confirm the current URL when filing). This template summarizes the content the form expects; transcribe into the form, do not send the template directly.

> **Reporting organization:** Strathcona Vineyard Church, operating FIMBY (a neighbourhood mutual-aid app).
> **Contact for this report:** <Operator name>, <email>, <phone>.
>
> **Date of incident:** <date>
> **Date discovered:** <date>
> **Date contained:** <date>
>
> **Nature of incident:** <plain-language description matching the individual-notification template>
>
> **Personal information involved:** <data categories>
>
> **Number of individuals affected:** <count, or estimate with basis>
>
> **Risk assessment:** <our determination that this meets the "real risk of significant harm" threshold under PIPA, with the factors considered>
>
> **Containment and remediation:** <what we did>
>
> **Notification of affected individuals:** <date(s) sent, channel, sample template attached>
>
> **Steps to prevent recurrence:** <what we changed in code, configuration, monitoring>

Attach the individual-notification template you used and the breach-log entry as supporting documents.

---

### Breach — OPC Canada notification

> **Use the OPC Canada PIPEDA breach reporting form** (currently at https://www.priv.gc.ca/ — confirm the current URL when filing). Same content shape as OIPC BC; PIPEDA expects "real risk of significant harm" framing.

(Same template content as OIPC BC, retitled for OPC Canada. The two regulators expect substantively the same information; file with both when both jurisdictions apply.)

---

### IP complaint — intake reply

**Subject:** We've received your IP complaint — a few things we need to act on it
**Body:**

> Hi <complainant first name>,
>
> Thanks for reaching out about content on FIMBY that you believe infringes your rights. I want to act on this quickly, and to do that, I need a few specific pieces of information:
>
> 1. **The URL or in-app location of the specific content.** A screenshot or a link is fine.
> 2. **A description of the work you say is being infringed** — what is the original work, and how does it relate to the FIMBY content?
> 3. **Your contact information** (you've given me an email; if there's a different address you'd like us to use, let me know).
> 4. **A good-faith statement that you believe the content is infringing.** A short sentence is enough — for example, "I have a good-faith basis to believe the FIMBY content at the URL above is infringing my copyright."
> 5. **If you're acting on behalf of someone else** (an organization, a client, an artist), please confirm you have the authority to do so.
>
> Once I have those five pieces, I'll review and get back to you within 5 business days. Depending on the situation, we may temporarily remove the content while we look at it.
>
> Talk soon,
> <Operator first name> — FIMBY support

---

### Succession — in-app banner

> **Banner copy** (shows persistently across the FIMBY1 site for the notice window). Keep under 2 sentences in the banner; link to the public posting for full detail.

> *Important: FIMBY is changing operators on <date>. [Read what this means and how to export or delete your data](https://www.fimby.com/transition).*

For shutdown (not transfer), substitute "shutting down" for "changing operators".

---

### Succession — email blast

**Subject:** Important: changes coming to FIMBY on <date>
**Body:**

> Hi <first name>,
>
> I'm writing to let you know that FIMBY is <changing operators / shutting down> on <date>.
>
> **What's happening:** <one paragraph of plain-language context — e.g. "Strathcona Vineyard Church has decided to transfer FIMBY to <new operator name>, who will run it under their own privacy policy and terms of service. The app you use day-to-day stays the same, but the organization behind it changes.">
>
> **What this means for you:**
>
> - **You have <N> days from today to decide what you want to do.**
> - **You can keep using FIMBY normally** during that time.
> - **You can export your data** at any time — reply to this email and ask, and I'll send you a copy of everything FIMBY holds about you within 30 business days.
> - **You can delete your account** at any time — go to Settings, scroll to Account Deactivation, and follow the prompts. You can also email help@fimby.com if you'd rather we handle it.
> - **For the transfer specifically:** we will not move your data to the new operator unless you tell us yes. Closer to <date>, you'll get a separate email asking for that consent. If you don't respond, we delete your data before the transfer.
>
> If you have any questions at all, please reply to this email. I'll do my best to answer.
>
> Take care,
> <Operator first name>
> Strathcona Vineyard Church (current operator of FIMBY)

For shutdown: drop the consent paragraph and add "After <date>, FIMBY will no longer be available to sign in to. We'll keep your data accessible for export until <date + 30 days>; after that, it's deleted permanently."

---

### Succession — public posting

> **Replace the relevant section of `www.fimby.com`** with this for the duration of the notice window. Keep the contact path and the dates current.

**Title:** FIMBY is changing — what neighbours need to know
**Body (similar tone to the email blast):**

> FIMBY is <changing operators / shutting down> on <date>.
>
> <Two-paragraph context, repeating the email blast.>
>
> **What you can do, by when:**
>
> | What | How | By |
> |---|---|---|
> | Export your data | Email help@fimby.com | <date - 14 days>, so we have time to fulfill within 30 business days |
> | Delete your account | Settings → Account Deactivation, or email help@fimby.com | <date - 7 days>, to be sure it processes before the change |
> | Decide whether your data moves to <new operator> (transfers only) | Look for a separate consent email closer to <date> | <date> |
>
> **Where to ask questions:** help@fimby.com.
>
> Strathcona Vineyard Church (current operator of FIMBY)

---

### Succession — fresh consent request

**Subject:** One question before FIMBY moves to its new operator
**Body:**

> Hi <first name>,
>
> As I mentioned in my earlier note, FIMBY is moving to a new operator — <new operator name> — on <date>.
>
> Before that happens, I want to ask you directly: **do you want your FIMBY data to move with you?**
>
> The data we'd hand to <new operator name> includes the same things you'd see in a data export — your profile, your posts, your messages, your library activity, your support relationships, your blocks, and so on. <New operator name>'s privacy policy is at <link>; their terms of service are at <link>.
>
> **Two ways to answer:**
>
> - **Reply YES MOVE MY DATA** (those exact words) to this email by <date>. We'll move your data to <new operator name> on <date>.
> - **Reply NO DELETE MY DATA** (those exact words), or just don't reply. We'll delete your data before the transfer happens, and your account will not move to <new operator name>.
>
> If you have any questions, reply with anything other than the two phrases above and I'll get back to you before the deadline.
>
> Take care,
> <Operator first name>
> Strathcona Vineyard Church (current operator of FIMBY)

---

## 12. Monthly Self-Audit Checklist

> Run this once a month. Estimated time: 30 minutes if everything is healthy, longer if items surface. Record the run in a dated entry — anywhere stable (a Google Doc, a `Feedback__c` row with `Type__c = 'Monthly Audit'`, the operator's runbook spreadsheet) — so a missed month is visible.

### Health checks (object/system queries the operator runs)

- [ ] **Deletion Cases past SLA reviewed.** List view: `Account_Deletion` Cases where `Deletion_Stage__c = 'Awaiting Confirmation' AND Confirmation_Sent_Date__c < TODAY - 7`. Should be empty if `FimbyDeletionExpiryBatch` is running. If anything is here, the batch has stalled.
- [ ] **Confirmed deletion Cases past safeguard processed.** List view: Cases where `Deletion_Stage__c = 'Confirmed' AND Safeguard_Enqueue_After__c < NOW`. Should be empty.
- [ ] **Account deactivation batch errors reviewed.** Search `Error_Log__c` for `Source = 'FimbyAccountDeactivationBatch'` in the last 30 days. Investigate any.
- [ ] **`Moderator_Task__c.Is_Overdue__c = true` tasks reviewed.** Should be < 5; investigate any cluster.
- [ ] **Privacy access Cases near target turnaround reviewed.** Cases tagged `[Privacy Access]` where `CreatedDate < TODAY - 25 business days` and not yet closed. Each gets a proactive update before day 30.
- [ ] **Breach log reviewed.** Any new entries in the last month? Are open entries past their post-incident-review deadline? Any pattern across the last 6 months?
- [ ] **CASL / email template changes reviewed.** Any new `EmailTemplate` records or changes to `FimbyTransactionalEmailService` / `FimbyDigestEmailSendQueueable` deployed since last audit? Each gets the Section 6 audit checklist re-run.
- [ ] **Supportee verification pending/expired reviewed.** `Support_Relationship__c.Status__c IN ('Pending Paper Review', 'Pending Verification', 'Draft', 'Expired')` rows older than 60 days. Anything still pending after 60 days needs a check-in.
- [ ] **Digest/email logs checked for failures.** `Digest_Email_Log__c.Status__c = 'Failed'` in the last 30 days. Sample the error messages; if a pattern, file a follow-up.
- [ ] **Succession/shutdown status — has anything changed?** Any decisions from leadership, operator-team transitions, charity-status changes that should trigger Section 9?

### Operator decisions still pending

- [ ] Walk the *Currently `Needs operator approval`* table at the top of this playbook. Has anything resolved? If so, update the relevant section, drop the row from the table, and note here.

### Build follow-ups

- [ ] Walk the playbook for any section marked `Needs build follow-up — <ref>`. Has the referenced ticket / plan slice closed? If so, flip the section to `Ready` and update the body.

### Anything new

- [ ] **New legal page wording deployed?** Walk Section 1's triage matrix and confirm none of the section-by-section public commitments have drifted from the deployed code.
- [ ] **New Cursor rules** added to `.cursor/rules/` that affect operator-facing wording or process? Update the playbook references.
- [ ] **Public-page deployments** to the FIMBY Website repo — note any since the last audit.

### Sign-off

> **Audit completed by:** <Operator name>
> **Date:** <YYYY-MM-DD>
> **Issues surfaced:** <bullet list, or "none">
> **Follow-ups created:** <bullet list, or "none">

---

## Appendix A — Vouching System Setup & Operation

> **Status:** Manual v1 — set up by the system admin once after the vouching system deploys, then operated by moderators ongoing.

### A.1 — One-time DLRS rollup setup

The vouching system uses **Declarative Lookup Rollup Summaries (DLRS)** to maintain trust counts on `Contact` from `Vouch_Record__c` children. The build ships the target fields and helper logic but **does not create DLRS config records** — those live in the org and must be configured manually in Setup.

Sign in as a sys admin, then in **Setup → App Launcher → Manage Lookup Rollup Summaries**, create the following four rollup records. Each one is realtime-triggered; the rolling-window rollup also needs scheduled full recalculation nightly.

#### Rollup 1 — `Vouches_Given_Count`
- Parent Object: `Contact`
- Aggregate Result Field: `Vouches_Given_Count__c`
- Child Object: `Vouch_Record__c`
- Relationship Field: `Reference_Contact__c`
- Aggregate Operation: `Count`
- Relationship Criteria: `Status__c = 'Approved'`
- Active: checked
- Calculation Mode: **Realtime**

#### Rollup 2 — `Vouches_Revoked_Count`
- Parent: `Contact`
- Aggregate Result Field: `Vouches_Revoked_Count__c`
- Child: `Vouch_Record__c`
- Relationship Field: `Reference_Contact__c`
- Aggregate Operation: `Count`
- Relationship Criteria: `Status__c = 'Revoked' AND Counts_Toward_Voucher_Pause__c = TRUE`
- Active: checked
- Calculation Mode: **Realtime**

#### Rollup 3 — `Vouches_Revoked_Last_12_Months`
- Parent: `Contact`
- Aggregate Result Field: `Vouches_Revoked_Last_12_Months__c`
- Child: `Vouch_Record__c`
- Relationship Field: `Reference_Contact__c`
- Aggregate Operation: `Count`
- Relationship Criteria: `Status__c = 'Revoked' AND Counts_Toward_Voucher_Pause__c = TRUE AND Revoked_Date__c = LAST_N_DAYS:365`
- Active: checked
- Calculation Mode: **Realtime**
- **Also schedule full recalculation nightly** (DLRS UI → Schedule Calculate Job → daily 2:00 AM). This is essential because records aging out of the 365-day window do not fire triggers.

#### Rollup 4 — `Vouch_Decline_Count`
- Parent: `Contact`
- Aggregate Result Field: `Vouch_Decline_Count__c`
- Child: `Vouch_Record__c`
- Relationship Field: `Requester_Contact__c`
- Aggregate Operation: `Count`
- Relationship Criteria: `Status__c = 'Declined'`
- Active: checked
- Calculation Mode: **Realtime**

After creating each rollup, click **Manage Child Trigger** and **Manage Child Triggers Test** to deploy the auto-generated trigger and test class. Click **Calculate** once to backfill existing data.

### A.2 — Launch cohort runbook (moderator-vouched bulk approval)

When a brand-new neighbourhood goes live, no one yet has been vouched, so peer vouching cannot bootstrap. Moderators must directly vouch the first 5–10 members of the cohort.

For each launch member:
1. From the **Moderator Dashboard → Routine Review → Signups** tab, open their welcome panel.
2. Click **Override-vouch** in the Vouching section.
3. Confirm. The system sets `Contact.Vouched_Status__c = 'Vouched'`, `Vouched_By_Moderator__c = true`, `Vouch_Source__c = 'Moderator_Override'`, and creates a `Vouch_Record__c` with `Source__c = 'Moderator_Override'` for audit.

After the first cohort is vouched, normal peer vouching takes over.

### A.3 — Revocation categories — for-cause vs administrative

Only **for-cause** revocations count against a voucher (`Counts_Toward_Voucher_Pause__c = true`). Administrative removals preserve the audit trail but do not count.

**Counts against voucher (for-cause):**
- `Safety_Trust_Concern`, `Theft_Or_Misuse`, `Repeated_No_Return`, `Serious_Conduct_Issue`, `Identity_Misrepresentation`, `Other_For_Cause`

**Does not count against voucher (administrative):**
- `Admin_Correction`, `Wrong_Contact_Selected`, `Duplicate_Or_Test_Record`, `Neighbourhood_Move`, `Support_Relationship_Ended`, `Organization_Rep_Link_Corrected`

When in doubt, lean toward administrative; voucher accountability should only kick in for genuine trust failures.

### A.4 — Voucher pause review

When a voucher's `Vouches_Revoked_Last_12_Months__c` crosses the threshold (default 2, configurable via `FIMBY_App_Settings__mdt.Vouching_Disable_Threshold__c`), the system auto-sets `Vouching_Disabled__c = true` and creates a moderator task in the **Needs Attention → Vouchers** tab.

Procedure:
1. Open the task. Review the voucher's `Vouches_Revoked_Last_12_Months__c` related list to see which revocations triggered the pause.
2. If the pattern looks like coincidence (e.g. two unrelated revocations for different reasons), click **Re-enable** in the CTA row to restore the voucher's ability to vouch.
3. If the pattern looks concerning (e.g. multiple vouchees revoked for the same kind of conduct issue), leave the pause in place. The voucher's profile already shows the paused state privately; they have been notified.
4. Document the decision in the related `Moderator_Task__c` notes.

### A.5 — Cross-neighbourhood moves

When a member moves between FIMBY neighbourhoods, their Contact.AccountId changes. The vouching trust they earned is local to their previous neighbourhood — neighbours in the new neighbourhood do not know them.

**Procedure:**
1. When a moderator processes an admin-driven neighbourhood transfer (Contact.AccountId change), reset `Vouched_Status__c` to `New`, clear `Vouched_By_Contact__c`, `Vouched_By_Organization__c`, and `Vouched_Date__c`.
2. Add a note to the Contact (or to the moderator dashboard) that this person was previously vouched in `{Previous Neighbourhood}` so the new neighbourhood's moderator has context.
3. The member will see the "Settling in" banner in the library and can request a vouch from someone in their new neighbourhood.

This is intentional: trust is local. A person who was vouched in V6A is not automatically trusted by neighbours in V6B who have never met them. The new-neighbourhood moderators can override-vouch if they have personal knowledge of the move (e.g. a known supportee or community member relocating with their support network).

### A.6 — Block-then-decline edge case

If a vouch recipient blocks the requester (via the standard FIMBY block flow) instead of using the decline modal:
- The conversation is automatically marked `Status__c = 'Blocked'`.
- The Vouch_Record__c remains in `Pending` status until cleaned up.
- Moderators should periodically sweep `Pending` Vouch_Records older than the expiry window (default 30 days) and mark them `Expired`.

A future build phase may automate this via a scheduled job. For v1, the moderator dashboard's "Settling-in members who have NOT requested a vouch yet" cohort surfaces these stuck requesters.

### A.7 — Privacy-conscious voucher communications

When a vouchee is revoked for cause, the system sends the voucher a notification + email via the `Voucher_Pause_Notice` standard Email Template. **The default copy does not name the revoked vouchee.** This is intentional — moderators may discuss case-specific detail when appropriate, but the system never auto-discloses identities.

If a voucher reaches out asking for specifics, moderators can:
- Share the revocation category (e.g. "we revoked someone for a safety concern") without names, OR
- Share names case-by-case if there's a legitimate operational need (e.g. the voucher needs to know to recover their own borrowed item).

Default toward less disclosure; document any name-sharing in the moderator notes.
