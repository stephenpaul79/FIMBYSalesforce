# Verifying a paper support relationship — admin runbook

## Purpose

A FIMBY supporter can set up a relationship for a neighbour who will never log in
(e.g. an elder, low-tech, or housebound supportee). Because the supportee never
clicks "I agree" themselves, we use a multi-layered verification process to make
sure the consent on the paper form is real and not coerced.

This runbook is for admins working `Pending Paper Review` and `Pending Verification`
queue tasks on `Support_Relationship__c`.

---

## Lifecycle states (Support_Relationship__c.Status__c)

| Status                  | What it means                                                                |
|-------------------------|------------------------------------------------------------------------------|
| `Draft`                 | Supporter started the request; no signed form uploaded yet                    |
| `Pending Paper Review`  | Signed form is uploaded; an admin needs to review legibility, identifiers     |
| `Pending Verification`  | Form looks good; admin is contacting the supportee to confirm consent         |
| `Approved`              | Verified — supporter can now act on behalf                                    |
| `Rejected`              | Couldn't verify; relationship is closed (see `Rejection_Reason__c`)            |
| `Expired`               | 90 days passed since Day-0 email and no upload; auto-set by reminder batch    |

The `FimbySupportRelationshipTrigger` fires on status changes and auto-creates
admin tasks, sends supporter emails, and stamps acceptance fields. The admin's
job is to **work the tasks** — the trigger does the rest.

---

## 1. Working a `Pending Paper Review` task

The task title is **"Verify supportee — `<supportee name>`"** and is auto-created
in the `FIMBY_Support` queue when the supporter uploads a signed form.

Steps:

1. Open the `Support_Relationship__c` record from the task's "Related to" link.
2. Open the attached signed form (in the Files related list).
3. Confirm:
   - All three blocks (Designation / Data sharing / Terms of Service) are initialled.
   - The supportee signed (or marked X with a witness signature + phone).
   - The supporter also signed.
   - The supportee identifiers on the form match the Contact record fields
     (full name, mailing address, DOB, phone, email).
   - **Block C references a TOS version that is still current.** If the form
     references a stale version, ask the supporter to re-print and re-collect.
4. If the form is **not** valid:
   - Set `Rejection_Reason__c` (e.g. `Form invalid`) and a short
     `Rejection_Reason_Detail__c` (e.g. "Block B not initialled, page 2 missing").
   - Set `Status__c` to `Rejected`. The trigger will email the supporter.
5. If the form **is** valid:
   - Set `Status__c` to `Pending Verification` and proceed to step 2 below.

---

## 2. Working a `Pending Verification` task

The task title is **"Contact supportee — `<supportee name>`"**. This is the
anti-fraud / anti-coercion gate. **Always contact the supportee directly — never
the supporter.**

### Tier 1 — Phone call (preferred)

1. Call the phone number on the Contact record (or on the form, if different —
   record the discrepancy in `Verification_Notes__c`).
2. **Talk to the supportee, not whoever picks up.** If a third party answers,
   politely insist on speaking to the supportee privately. If you can't, hang up
   and try again at a different time of day.
3. Confirm in plain language:
   - "Did you sign a paper form asking `<supporter name>` to use FIMBY for you?"
   - "Do you understand that `<supporter name>` will be able to post things and
     reply to neighbours on your behalf?"
   - "Did anyone pressure you to sign? Are you doing this freely?"
   - "Is there anything you want to ask us?"
4. Record the outcome:
   - If confirmed: `Verification_Method__c = Phone Call`,
     `Verification_Date__c = today`, brief `Verification_Notes__c`,
     `Status__c = Approved`. The trigger handles the rest (stamp TOS acceptance,
     email the supporter, create the activation-letter task).
   - If declined / pressured / confused:
     `Verification_Method__c = Phone Call`,
     `Rejection_Reason__c = Supportee declined`, detail in
     `Rejection_Reason_Detail__c`, `Status__c = Rejected`.

### Tier 2 — Postal letter fallback

Use this if you cannot reach the supportee by phone after 3 attempts on
different days.

1. Set `Verification_Method__c = Phone - Could Not Reach` and add notes about
   the attempts.
2. Generate the verification letter from the `Support_Relationship__c` record
   ("Mail verification letter" Visualforce action — separate from the activation
   letter; uses the same address block but asks for a phone call back).
3. Mail it. Set `Verification_Method__c = Postal Letter` and
   `Verification_Date__c = today`.
4. If the supportee calls back and confirms, follow Tier 1 step 4 (Approved).
5. If 30 days pass with no callback: `Rejection_Reason__c = Could not reach supportee`,
   `Status__c = Rejected`.

### Tier 3 — Activation letter (always, on Approval)

This is automatic — when you set `Status__c = Approved`, the trigger creates a
**"Mail FIMBY activation letter"** task. Generate the
`FimbySupporteeActivationLetter.page` PDF from the record, print it, and mail
it to the supportee's address. Then mark the task complete and stamp
`Activation_Letter_Sent_Date__c`.

The activation letter is the supportee's "you are now in the system, and here's
how to revoke if you change your mind" notice. Even when phone verification is
clean, this letter goes out — a third independent signal that we know who they
are and where they live.

---

## 3. Re-runs and edge cases

- **Supporter re-uploads after a rejection**: create a new
  `Support_Relationship__c` record (the rejected one stays as audit trail).
- **Supportee revokes**: any FIMBY admin can revoke at any time from the
  Support_Relationship__c record by setting `Status__c` to a closed state and
  filling `Ended_Date__c` + `Ended_By__c`. No paperwork needed — the supportee's
  word is enough.
- **Form is signed with X plus a witness**: that's allowed; treat it the same
  as a signature, but also call the witness during phone verification to
  confirm they actually saw the supportee mark the form.
- **Supportee speaks a language we don't**: pause verification, get a translator,
  document in `Verification_Notes__c`. Don't approve until you've talked to the
  supportee in their language.
- **Reminder cadence**: the supporter gets reminder emails on day 14 / 30 / 60
  if their `Status__c` is still `Draft`. After 90 days the
  `FimbySupportRelationshipReminderBatch` auto-sets `Status__c = Expired`.
  No admin action needed.

---

## 4. What gets stamped where

When you set `Status__c = Approved`, the `FimbySupportRelationshipTriggerHandler`:

- Calls `FimbyTosController.recordPaperAcceptance` which writes the Contact's
  `Tos_Accepted_Date__c`, `Tos_Version_Accepted__c`,
  `Tos_Acceptance_Source__c = Support Relationship Paper Form`, and
  `Tos_Acceptance_Form_Id__c = <ContentDocumentId of the signed form>`.
- Calls `FimbySupportRelationshipEmailService.sendApprovalNotification` — emails
  the supporter that the relationship is live.
- Creates the **"Mail FIMBY activation letter"** task.

When you set `Status__c = Rejected`, the same handler:

- Calls `FimbySupportRelationshipEmailService.sendRejectionNotification` —
  emails the supporter using the wording from `Rejection_Reason__c`.

You should not stamp these fields manually. If something is wrong with what got
stamped, fix the `Support_Relationship__c` record and the trigger will reconcile
on the next save.

---

## 5. Reports / monitoring

Useful saved views on `Support_Relationship__c`:

- **Pending Paper Review** (open paper-review tasks)
- **Pending Verification > 7 days** (verification calls that have stalled)
- **Drafts > 60 days** (supporters who never uploaded — reminder batch handles
  most of these, but human review can spot patterns)
- **Activation letters not yet sent** (`Status__c = Approved` AND
  `Activation_Letter_Sent_Date__c = null` for > 3 days)
- **Rejected — Supportee declined** (rare; review for any pattern of one
  supporter repeatedly being declined, which is a coercion red flag)

---

*Companion docs: [`account_deletion_setup_runbook.md`](./account_deletion_setup_runbook.md), [`terms_acceptance_implementation_b5bc2bef.plan.md`](./terms_acceptance_implementation_b5bc2bef.plan.md).*
