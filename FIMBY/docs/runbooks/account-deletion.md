# Account Deletion — Setup Runbook (sys admin)

This is the operational follow-up to the Salesforce-Native Account Deletion Flow build. The Apex, fields, two Case record types (`Support` and `Account_Deletion`), two Case business processes (`Case_Support_Process` and `FIMBY_Account_Deletion_Process`), two queues (`Account_Deletion`, `FIMBY_Support`), the active Case assignment rule (`FIMBY Case Routing`), and triggers were deployed via `sf project deploy` and are validated by `FimbyDeletionControllerTest` (15 tests, 100% pass). Three things still need to be done by hand in Setup, in this order.

### What the deploy already did

- ✅ Created the two queues. **Members are empty in source** — admin must add themselves and any reviewers (see step 0 below).
- ✅ Activated the `FIMBY Case Routing` assignment rule with two entries: deletion-RT Cases route to `Account_Deletion` queue, support-RT Cases route to `FIMBY_Support` queue.
- ✅ Stamps `Account_Deletion` RecordType automatically on inbound Email-to-Case Cases whose subject contains `delete my account`, `delete account`, or `close my account` (handled by `FimbyDeletionIntakeService.handleBeforeInsert`). The assignment rule then routes by RecordType — no subject-string config needed in Setup.

### Note for future Apex that creates Cases

Salesforce assignment rules only fire when the DML opts in. Plain `insert myCase` skips them. To route a programmatically-created Case through `FIMBY Case Routing`:

```apex
Database.DMLOptions dml = new Database.DMLOptions();
dml.assignmentRuleHeader.useDefaultRule = true;
Database.insert(myCase, dml);
```

Tests deliberately skip this to keep owner assignment predictable.

---

## 0. Profile defaults + queue membership

### Make `Support` the default Case record type on every profile

Adding the first Case record type means every profile must now pick a default; otherwise general inbound Cases would all default to `Account_Deletion`, which is wrong.

1. **Setup → Object Manager → Case → Record Types**: confirm both `Support` and `Account_Deletion` are present and active
2. For every profile that can create Cases (System Administrator, plus any custom support profiles), open the profile and:
   - **Record Type Settings → Cases → Edit**
   - Available Record Types: both `Support` and `Account_Deletion` (or just `Support` for profiles that should never manually create deletion Cases)
   - **Default**: `Support`
3. The `Account_Deletion` record type stays available so `FimbyDeletionIntakeService.handleBeforeInsert` can stamp deletion-keyword inbound emails with it and the assignment rule can route them.

> Why: with multiple record types, Salesforce no longer auto-assigns the master record type. If `Support` is not set as the default, users get a record-type picker every time they create a Case, and any code that creates a Case without specifying a record type ends up on `Account_Deletion` — which would route every general support email through the deletion flow.

### Add yourself to both queues

The deploy created `Account_Deletion` and `FIMBY_Support` queues as objects, but member User IDs are org-specific so source ships them empty.

1. **Setup → Users → Queues → Account Deletion → Edit → Queue Members**
   - Add yourself (sole member during the first 30 days — see Monitoring section)
   - Set the **Queue Email** to your address so deletion notifications hit your inbox immediately
   - **Send Email to Members**: ✓
2. **Setup → Users → Queues → FIMBY Support → Edit → Queue Members**
   - Add yourself + anyone else who should triage general support emails
   - Set the **Queue Email** to a shared inbox (or your address if it's just you)

---

## 1. Configure Email-to-Case on `help@fimby.com`

Email-to-Case routing addresses are not deployable as metadata (org-config), so this stays a Setup task. The queue, assignment rule, and subject-keyword detection are already wired by the deploy — this step is just exposing `help@fimby.com` to Email-to-Case.

1. **Setup → Service → Email-to-Case → Edit Settings**
   - Enable Email-to-Case
   - Enable **On-Demand Service** (no email-to-case agent JAR — works with no infrastructure)
   - Enable **Thread Email Headers** (so user replies thread back to the same Case via In-Reply-To / References, which is what the `FimbyDeletionEmailMessageTrigger` fires on)
2. **Setup → Service → Email-to-Case → Routing Addresses → New**
   - Routing Name: `FIMBY Help Inbox`
   - Email Address: `help@fimby.com`
   - Save Email Headers: ✓
   - Default Case Owner: `FIMBY Support` queue (deletion-keyword Cases get re-routed to the `Account Deletion` queue automatically by the assignment rule + before-insert trigger)
   - Default Case Origin: `Email`
   - Default Case Record Type: **Support**
   - **Save**, then verify the address by clicking the verification link in the email Salesforce sends to `help@fimby.com`
3. **No assignment rule configuration needed.** The `FIMBY Case Routing` rule is already active in the org from the deploy. It routes by RecordType:
   - `Support` RT → `FIMBY Support` queue
   - `Account_Deletion` RT → `Account Deletion` queue
   The before-insert trigger (`FimbyDeletionIntakeService.handleBeforeInsert`) flips the RT to `Account_Deletion` for inbound emails whose subject contains the deletion keywords, so subject-string matching lives in code, not in the assignment rule.
4. **Smoke test**: send an email to `help@fimby.com` from a personal address with subject "Delete my account". Confirm:
   - A Case appears with RecordType = Account Deletion, owned by the Account Deletion queue
   - The deletion trigger fires: `Deletion_Stage__c = Awaiting Confirmation`, `Confirmation_Sent_Date__c` populated
   - You (the recipient via the User on file) receive the verification email
5. Reply with `CONFIRM DELETE` and confirm the Case advances to `Confirmed` with `Safeguard_Enqueue_After__c` 24 hours out
6. Send a second test email with subject "Help with my profile" — confirm it lands as a `Support` RT Case in the `FIMBY Support` queue, not the deletion queue.

If subject-keyword detection ever needs to evolve (more languages, fuzzy matching, etc.), update the `DELETION_SUBJECT_KEYWORDS` set in `FimbyDeletionIntakeService.cls` and redeploy — no Setup change required.

### Org-Wide Email Address

`FimbyDeletionEmailService` looks up an OrgWideEmailAddress with DisplayName `FIMBY` and falls back to the running user's address if none is found. Confirm one exists:

- **Setup → Email → Organization-Wide Addresses**: ensure `FIMBY <help@fimby.com>` is verified and Available for Use by All Profiles

---

## 2. Schedule the three retention batches

None of these are scheduled in the org today. Without scheduling them, the deletion flow stops after `CONFIRM DELETE` — login is revoked but no data is scrubbed and no expiry/safeguard ever fires.

Run **Setup → Custom Code → Apex → Anonymous Apex** with each block (one job at a time, paste, Execute, verify under **Setup → Apex Jobs → Scheduled Jobs**):

```apex
// 1. Deletion expiry + 24h safeguard + rate-limit backstop
//    Daily at 01:00 org time
System.schedule(
    'FIMBY Deletion Expiry',
    '0 0 1 * * ?',
    new FimbyDeletionExpiryBatch()
);
```

```apex
// 2. Grace-window expiry (in-app delete-with-grace -> flag for scrub on day 30)
//    Daily at 00:30 org time. Runs BEFORE the account-deactivation batch so
//    any contact whose grace window elapsed today gets picked up the same night.
System.schedule(
    'FIMBY Grace Expiry',
    '0 30 0 * * ?',
    new FimbyGraceExpiryBatch()
);
```

```apex
// 3. Account deactivation (anonymize Contact, delete content, active-loan hold)
//    Daily at 02:00 org time
System.schedule(
    'FIMBY Account Deactivation',
    '0 0 2 * * ?',
    new FimbyAccountDeactivationBatch()
);
```

```apex
// 4. Feedback anonymization (90-day delayed scrub of submitter references)
//    Daily at 02:30 org time
System.schedule(
    'FIMBY Feedback Anonymization',
    '0 30 2 * * ?',
    new FimbyFeedbackAnonymizationBatch()
);
```

Stagger times so the deactivation batch finishes flagging before the feedback batch starts looking; the grace-expiry batch runs first so any contact whose 30-day window elapsed today gets `Deactivation_Requested__c = true` before the deactivation batch starts its query at 02:00.

To remove a job: **Setup → Apex Jobs → Scheduled Jobs → Del** next to the matching name.

---

## 3. First-30-days monitoring playbook

Until the flow has been observed handling real traffic, every deletion Case gets a human review before the 24-hour safeguard lets `FimbyDeletionController.enqueue` fire.

### Daily review (10–15 min)

1. **Setup → Cases → List Views → New** (one-time):
   - Filter: `Record Type = Account Deletion AND Created Date = LAST 7 DAYS`
   - Pin to your home tab as "Account Deletion — Last 7 Days"
2. Each morning, open the list. For every Case in `Awaiting Confirmation`:
   - Confirm the inbound email body looks like a real, intentional request
   - Confirm `SuppliedEmail` matches the matched `Contact.Email`
   - If anything looks like spoofing (mismatched casing, suspicious domain, multiple in-burst), flip `Deletion_Rate_Limit_Flagged__c = true` to pause it until you've messaged the user directly
3. For Cases in `Confirmed` with `Safeguard_Enqueue_After__c` in the next 12 hours:
   - This is the last window to intervene. Re-read the original email and the CONFIRM DELETE reply.
   - If the reply looks coerced, came from a forwarded thread, or arrived suspiciously fast (<60 seconds after the verification email), flip `Deletion_Rate_Limit_Flagged__c = true` and reply asking for a follow-up confirmation
4. For Cases in `Completed`:
   - Audit the next-day batch run — confirm the matching Contact's `Deactivation_Requested__c = true` and that `FimbyAccountDeactivationBatch` picked them up that night

### Weekly review (5 min)

- **Apex Jobs**: confirm all three scheduled jobs ran in the last 24h. If a run was missed, re-schedule.
- **Setup → Logs → Debug Logs**: search for `FimbyDeletionController` / `FimbyDeletionIntakeService` / `FimbyDeletionConfirmationService` warnings. The classes log via `FimbyLogger`, so warnings also land in `Error_Log__c`.
- Spot-check anonymized Contacts: pick one Completed Case from > 24 hours ago and confirm the Contact is `FirstName = "A former"`, `LastName = "neighbour"`, all PII fields nulled.

### When to stop monitoring

Once you've seen the flow handle (a) at least 5 real deletion requests, (b) at least one CANCEL reply, and (c) at least one 7-day expiry — and none surfaced a problem — you can:

1. Switch the `Account Deletion` queue's primary email recipient from a single human owner to a shared inbox or distribution list
2. Stop the daily Case-by-Case review; rely on the weekly batch-job audit instead
3. Continue the monthly Apex log audit indefinitely

### Things to flag for follow-up code work

- If the rate-limit-flagged path fires more than once a quarter, consider raising `RATE_LIMIT_MAX_PER_24H` (currently 3) or adding IP-based detection at the auth-bridge layer
- If users frequently misspell `CONFIRM DELETE` (e.g. "confirm deletion", "yes delete it"), consider expanding the parser to recognize fuzzy matches — but only after seeing real traffic, not pre-emptively

---

## In-app delete with 30-day grace (Apple 5.1.1(v) path)

Distinct from the email-to-Case flow above. Triggered when a neighbour taps **Settings → Delete my account** in the mobile app:

- **Default (graceful)**: `FimbyProfileController.requestAccountDeletion(skipGrace=false)` stamps `Contact.Grace_Started_At__c = now`, enqueues `FimbyDeactivateUserQueueable` (flips `User.IsActive = false` immediately), and sends a delete-with-grace confirmation email via `FimbyReactivationEmailService.sendDeleteWithGraceConfirmation` containing a 30-day restore magic link. `Deactivation_Requested__c` stays `false` until day 30.
- **Skip-grace (opt-in checkbox)**: same controller with `skipGrace=true` sets `Deactivation_Requested__c = true` immediately, same queueable, no restore email — picked up by tonight's `FimbyAccountDeactivationBatch`.
- **Grace expiry**: `FimbyGraceExpiryBatch` runs daily at 00:30. For each Contact whose `Grace_Started_At__c` is older than `Grace_Window_Days__c` (default 30 via `FIMBY_App_Settings__mdt.Default_Grace_Window_Days__c`), it flips `Deactivation_Requested__c = true`. The existing 02:00 scrub batch picks them up that night.

### Safeguard guard on the scrub batch

`FimbyAccountDeactivationBatch.start()` query is now `WHERE Deactivation_Requested__c = true AND (Grace_Started_At__c = NULL OR Grace_Started_At__c <= :graceCutoff)`. A Contact in the middle of its grace window can't be scrubbed even if `Deactivation_Requested__c` is somehow co-flagged (Flow, manual edit). Email-Case deletions never set `Grace_Started_At__c`, so they continue scrubbing immediately as before.

### Self-serve reactivation (no admin work)

During the 30-day grace, neighbours have two restore paths:

1. **Restore link in confirmation email** — magic link valid for the full grace window. Lands on `/reactivate?token=...` which hits `FimbyReactivationController.consumeReactivationToken`. On success: clears `Contact.Grace_Started_At__c`, enqueues `FimbyReactivateUserQueueable` to flip `User.IsActive = true`, and sends a welcome-back email.
2. **`/account-paused` page** (linked from the public footer) — guest neighbour enters their **username** (User.Username, the email-shaped login string; we lookup by username because Contact.Email is not unique in Salesforce); `FimbyReactivationController.requestReactivationLink` publishes a `Reactivation_Request_Event__e` platform event. The `ReactivationRequestEventTrigger` subscriber runs as the sys admin (via `PlatformEventSubscriberConfig` — required because the default Automated Process user cannot send email, and the guest profile cannot read User/Contact) and calls `FimbyReactivationRequestEventHandler.handle`, which mints a fresh 24h-TTL token via `FimbyReactivationTokenService.issueOnDemandToken` (rate-limited 3/24h per Contact) and emails the magic link to the linked Contact. Anti-enumeration: the page always responds "If a restorable account exists for that username, we've sent a link" regardless of match status, so neither a missed username, a not-in-grace contact, a past-grace contact, nor a rate-limit hit reveals itself to the caller.

### Tokens

`Reactivation_Token__c` is master-detail to `Contact`, so tokens cascade-delete when the Contact is anonymized at end-of-grace. Tokens are 36-char hex (192 bits of entropy via `Crypto.generateAesKey`), single-use, and stamped `Used_At__c` on consume.

### Monitoring

- **Daily**: spot-check `Reactivation_Token__c` for unusual volume from a single Contact (rate-limit cap = 3/24h; anything at the cap is logged via `FimbyLogger.warn`).
- **Weekly**: confirm `FimbyGraceExpiryBatch` ran (`Setup → Apex Jobs`). Sample a Contact past day-30 and confirm it landed on the next scrub batch run.
- **Quarterly**: if a different grace window is needed, update `FIMBY_App_Settings__mdt.Default_Grace_Window_Days__c` — no code change.

### Support plays

**"I'm not getting the restore email" — neighbour hit the rate limit.**

The on-demand throttle is 3 tokens per Contact per 24h. After the 4th request, `FimbyReactivationTokenService.issueOnDemandToken` logs `Rate limit hit for Contact <id> (4 tokens in last 24h)` to `Error_Log__c` (severity WARN) and the handler silently no-ops. The public `/account-paused` "Check your inbox" copy hints at this and points the neighbour to `help@fimby.com`, but deliberately does not name the exact number (so attackers can't tune behaviour to it).

To unblock a support request, find the Contact and clear today's tokens:

```apex
// Run in Setup -> Custom Code -> Apex -> Anonymous Apex.
// Use the Contact Id from the log entry, or look it up by Email/Name.
Id contactId = '003XXXXXXXXXXXXXXX';
delete [
    SELECT Id FROM Reactivation_Token__c
    WHERE Contact__c = :contactId
      AND CreatedDate >= :System.now().addHours(-24)
];
System.debug('Cleared tokens; rate limit reset.');
```

After this the neighbour can submit `/account-paused` again and a fresh link will fire. If the email still doesn't arrive, the failure has moved past the rate limit and is something else (Contact.Email actually wrong on file, OWEA "FIMBY" not verified, sandbox Email Deliverability set to System Only, etc.).

**Where to look first when troubleshooting:**

1. `Error_Log__c` filtered to `Class_Name__c = 'FimbyReactivationController' OR 'FimbyReactivationRequestEventHandler' OR 'FimbyReactivationTokenService' OR 'FimbyReactivationEmailService'` — covers every failure mode (publish gate, perms gate, rate limit, email send).
2. **Setup → Email Logs** filtered to the Contact.Email value — confirms delivery / bounce / deferred.
3. **Setup → Platform Events → Reactivation Request Event → Subscriptions** — confirms the trigger is subscribed and the running user is set correctly (must be the sys admin, NOT Automated Process, or `Messaging.sendEmail` silently fails).

---

## Profile permissions to apply

The deployment created new components. The sys admin should add these to the relevant profiles:

**Apex Classes:**
- FimbyDeletionEmailService
- FimbyDeletionIntakeService
- FimbyDeletionController
- FimbyDeletionConfirmationService
- FimbyDeletionExpiryBatch
- FimbyReactivationController (Apex Class access on **Experience Cloud guest user profile** so `/account-paused` and `/reactivate` work without login)
- FimbyReactivationEmailService
- FimbyReactivationTokenService
- FimbyReactivationRequestEventHandler (no profile assignment needed — invoked only by `ReactivationRequestEventTrigger` running as the configured subscriber user)
- FimbyGraceExpiryBatch
- FimbyReactivateUserQueueable

**Apex Triggers:** (no profile permission needed — they fire on DML / event regardless)

**Platform Events:**
- `Reactivation_Request_Event__e` — grant **Create** to the **Experience Cloud guest user profile** so `FimbyReactivationController.requestReactivationLink` can publish from `/account-paused`. Without this perm, `EventBus.publish` returns `isSuccess()=false` silently (now caught and logged to `Error_Log__c` as WARN).
- `Error_Log_Event__e` — grant **Create** to the **Experience Cloud guest user profile** as well, otherwise the guest can't surface its own failures into the error log.

**Platform Event Subscriber Config:**
- `ReactivationRequestEventTriggerConfig` (deployed) points the trigger at `fimby@strathconavineyard.com`. This is **required** — the default Automated Process user cannot send transactional email, so without this config the handler reaches `Messaging.sendEmail` and silently fails. If the running user is ever changed, suspend + resume the subscription in **Setup → Platform Events → Reactivation Request Event → Subscriptions → Manage** for the new user to take effect immediately (otherwise caching can delay it).

**Custom Fields on Case** (if FLS matters for owner-facing list views):
- Case.Deletion_Stage__c
- Case.Confirmation_Sent_Date__c
- Case.Confirmation_Received_Date__c
- Case.Contact_User_Id__c
- Case.Deletion_Enqueued_Date__c
- Case.Safeguard_Enqueue_After__c
- Case.Deletion_Rate_Limit_Flagged__c

**Custom Fields on Contact** (read+edit on **Experience Cloud guest user profile** for the reactivation flow):
- Contact.Grace_Started_At__c
- Contact.Grace_Window_Days__c

**New Object — Reactivation_Token__c** (CRUD on **Experience Cloud guest user profile** plus FLS on all fields so `FimbyReactivationController` can mint, look up, and mark tokens used). Fields:
- Reactivation_Token__c.Contact__c
- Reactivation_Token__c.Token__c
- Reactivation_Token__c.Expires_At__c
- Reactivation_Token__c.Used_At__c
- Reactivation_Token__c.Request_Count_24h__c

**Custom Metadata on FIMBY_App_Settings__mdt** (new fields, default record updated):
- Default_Grace_Window_Days__c (default 30)
- Reactivation_Token_TTL_Hours__c (default 24)

**Record Types:**
- `Case.Support` → assign to **every** profile that can create Cases, set as the **default** Case record type. This is the standard general-support record type.
- `Case.Account_Deletion` → assign to System Administrator and any profile that owns the Account Deletion queue. Do not set as default.

**Business Processes:** Both are auto-applied through the record types above; no separate profile permission needed.

**Queues (membership):**
- `Account_Deletion` → add yourself as the sole member during the first-30-days monitoring window
- `FIMBY_Support` → add yourself plus anyone else triaging general inbound mail

**Assignment Rule:** `FIMBY Case Routing` is active by default from the deploy — no profile permission needed.

> Critical: skipping the `Support` record type assignment means every Case (general support, future custom intake, etc.) will land on `Account_Deletion` and trigger the deletion flow. See section 0 above.
