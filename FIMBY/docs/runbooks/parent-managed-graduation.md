# Graduating a parent-managed profile at 19 — admin runbook

## Purpose

A parent-managed profile is a Contact with a visible neighbourhood presence and no
User. A guardian logs in as themselves and switches into the profile, so every action
carries both identities. FIMBY is an adults-only platform for **Users**; the moment
the young person turns 19 they are entitled to speak for themselves.

v1 graduation is **administrator-run on purpose**. There is no scheduled job, no
invite flow, and no automatic User provisioning. The consequential step — linking a
login to a Contact — happens only after the now-adult has personally attested and
accepted the current Terms, and no batch job can witness that.

This runbook is for admins working the **Parent-Managed Profiles Approaching 19**
report (Reports → FIMBY Neighbourhood Health).

---

## The report

| Column | Why it's there |
|---|---|
| Contact name | Who the profile is |
| `Age_Years__c` | Formula on `Birthdate`; **advisory only** — see the leap-day note below |
| `Birthdate` | The authoritative value. Never rendered on any Experience Cloud surface |
| Account | Their neighbourhood |
| `Proxied_By_Contact__c` | The guardian who set the profile up and is the person to contact |

Filtered to `Is_Parent_Proxied__c = true` and `Age_Years__c >= 18`, so profiles appear
roughly a year ahead of the decision rather than on the day it lands.

> **Leap-day caveat.** Salesforce date formulas mishandle 29 February birthdays — the
> formula can return null and the row will not appear. When a household tells you a
> birthday is 29 February, work the row from `Birthdate` directly.

---

## Working a row

Contact the **guardian** first. This is a household conversation, not an enforcement
action, and the young person may not know the profile exists in this form. Two
outcomes are available; either is fine.

### Outcome A — close the profile

Use when the household does not want a FIMBY presence to continue, or nobody
responds.

1. Confirm with the guardian (or record that no response was received after a
   reasonable window — the same non-punitive language used elsewhere).
2. Ask the guardian to use **Manage Identities → Remove profile**. This is the
   ordinary, tested erasure path and is preferable to an admin doing it by hand.
3. If the guardian cannot or will not act, set `Deactivation_Requested__c = true` on
   the child Contact. `FimbyAccountDeactivationBatch` handles the rest: it defers
   while any loan is still out, deletes owned content, deletes shared-contact
   episodes (locking and explaining the threads they authorized), closes support
   relationships, and anonymizes the Contact to "A former neighbour" while clearing
   `Birthdate`, `Is_Parent_Proxied__c`, and `Proxied_By_Contact__c`.

### Outcome B — graduate to an adult account

Use when the now-adult wants to keep their neighbourhood presence.

The whole point of graduating rather than re-registering is that **history persists**:
posts, offers, threads, lending history, and vouches all stay attached because they
stay attached to the same Contact.

1. **The now-adult personally attests.** They confirm they are 19 or older and accept
   the current Terms **themselves**. A guardian may not do this on their behalf — that
   is the one thing this entire flow exists to prevent. Record the attestation the
   same way an adult supportee's is recorded.
2. **Provision the User against the existing Contact.** Never create a replacement
   Contact. A new Contact silently discards every relationship the young person built.
3. **Clear `Is_Parent_Proxied__c`** and `Proxied_By_Contact__c` on the Contact.
4. **Close every `Parent_Guardian` relationship** on that Contact (set `Status__c` to
   an ended value). Leaving one Approved would let a parent keep switching into an
   adult neighbour's account.
5. **Leave `AccountId` unchanged.** They stay on the family household unless they
   later ask to split; that is a separate request.

**Order matters.** No User may be linked before step 1 is done and recorded. If you
have provisioned a login and only then discovered the attestation is missing,
deactivate the User until it is.

---

## Verifying afterwards

| Check | Expected |
|---|---|
| Contact | `Is_Parent_Proxied__c = false`, `Proxied_By_Contact__c` empty |
| `Support_Relationship__c` where `Related_Contact__c` = the Contact, type `Parent_Guardian` | No rows in `Approved` |
| Manage Identities, as each former guardian | The profile no longer appears as switchable |
| Their own login | Lands on their own identity; the parent-managed badge is gone from their profile, feed cards, and search rows |

If a former guardian still sees the profile in their switcher, an Approved
`Parent_Guardian` row was missed in step 4.

---

## What is deliberately not automated

Automated lifecycle enforcement, self-service graduation, and an invite flow are a
later plan. Do not build `FimbyProxiedGraduationJob` against this runbook — the
manual step is the control, not a gap.
