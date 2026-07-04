# Bulk Buy QA — needs your help

Updated during autonomous session (you at gym).

## Strathcona onboarding retest (code fix deployed)

- **Fix:** `FimbyOnboardingController` treats `Is_Organization_Contact__c` as onboarding-complete; org contacts backfilled in org where flags were false.
- **Cannot fully UI-retest here:** Approved **Strathcona Vineyard** rep is `stephenpaul79@gmail.com`, not a QA persona (`desktop@` / `mobiletester@` / `sftester@`). `desktop@` has **no** Community Group Rep rows in org.
- **Ask:** Log in as the Strathcona rep (or add an **Approved** `Community_Group_Rep` for `desktop@fimby.com` → Strathcona), switch identity, confirm **Home** loads (not `/onboarding`).

## G-bad (3× Confirm Flag → blocked reserve)

- Needs **sftester@** moderator hat + **mobiletester@** as subject on **three separate** escalation cycles. Long browser run; not finished this session.
- **Ask (optional):** Confirm you want automated confirm flags on R1 in prod QA data, or pre-seed follow-ups in admin.

## Track D3a Clear Flag

- Needs a **new** bulk buy post (escalate → moderator **Clear Flag**, distinct from D′ Confirm Flag). Not finished this session.

## A5 group-chat ordering

- Track A group chat: verify R1/R2 can still post after organiser **Mark Complete**. Deferred; needs two-persona browser pass.

## DLRS rollup

- **Fixed in repo + deployed:** `Total_Reserved_Responses` criteria now includes `Reserved`. May need a one-time **Recalculate All** in DLRS admin on `Total_Reserved_Responses` if B3 SOQL still shows 0 until child rows recalc.

## B2 organiser-cancel notification

- R1 **does** receive `Bulk_Buy_Status` for B5 organiser-cancel path today. B2 row may be stale (pre `notifyAllReservers` ordering). No code change this session.
