# FIMBY — Project Guide for Claude

FIMBY (Family In My Backyard) is a neighbourhood mutual-aid platform on Salesforce Experience Cloud, served through a React Native / Expo WebView mobile app. This file holds the **always-on** guardrails and the project map. Detailed, file-type-specific conventions live in skills (see *Skill routing* at the bottom) — load the matching skill **before** your first edit of that file type each session.

> Cursor and Claude work against the same codebase. These guidelines mirror the Cursor rules in `.cursor/rules/` so both agents apply the same guardrails. If you change a convention, update both surfaces.

---

## 1. Confirm Before Implement (unconditional)

Default to **discuss first**. Do **not** edit/create/delete files, run deploys, or create commits/PRs until the user has **explicitly approved** the proposed approach in the conversation.

First share: (1) **what you found** — root cause / feasibility / best hypothesis with evidence; (2) **what you would change** — options, tradeoffs, files, scope, and a recommendation; (3) **a clear ask** ("Want me to implement option B?") — then **stop**.

Treat these as discuss-only until approved: "can you…", "is it possible…", "how would we…", "make it on brand", "fix this", "improve X" — when said **without** an explicit go-ahead in the same message.

**You may implement when one is true:**
1. Same message: user clearly approves ("go ahead", "implement", "do it", "yes, option B", "deploy it").
2. Prior turn: you proposed a **specific** plan (files + approach) and the user's next reply approves it.
3. Trivial typo: one obvious single-line correction the user pointed at.

**In-process (relaxed) mode:** once a specific plan is approved and work is underway, follow-ups on the *same task* (refinement, "also…", "that failed…") may be implemented without re-pitching — but still briefly state what you're changing. **Cold start / new topic →** use the cautious default even if the wording sounds like "fix this". Still pause for messages that introduce new tradeoffs, expand scope, or touch guarded areas (network/site metadata).

When unsure, **ask once**. This rule **overrides** the proactive-deploy default and any inference that a question means "do it now".

> Note: the user's request to *generate these guideline files* was itself an explicit instruction — that approval does not extend to later code changes.

---

## 2. Efficient Responses

- Concise, structured output: bullets, short paragraphs, tables. Skip preamble ("Sure!", "Great question!"). Don't restate the user's question.
- Explain code changes in 1–2 sentences (what changed + why), not a line-by-line walkthrough.
- Plan before building; implement one step at a time. Don't generate an entire feature in one response unless asked.
- Don't re-read files already in context unless they may have changed. Reference rules by name instead of restating them.
- When a task is complete, **stop** — no unsolicited "next steps" unless there's a clear gap.
- No narration comments in code; comments only explain non-obvious intent.
- **Load the matching skill before editing a new file type** (see *Skill routing*). The skills carry mandatory conventions (tokens, icon names, patterns) that prevent rework.

---

## 3. Experience Cloud — Network & Site Guardrails

**Do not edit, deploy, or change** `networks/*.network-meta.xml`, `sites/*.site-meta.xml`, custom domains, publish/preview/status, page-override wiring (`networkPageOverrides`, `changePasswordPage`), or `sf community publish` for the purpose of changing site config — **unless the user explicitly asks for that exact change in the current message.**

When asked to brand or fix a Visualforce page / email / CMS view / CSS, change **only those files**. Do not hook up VF via network/site metadata.

> Network/site mistakes have previously deactivated the domain and forced org-wide password resets. Leave network settings alone by default.

(The post-LWC-deploy `sf community publish` in §8 is the **one** sanctioned publish — it pushes already-approved LWC changes live, it does not alter site config.)

---

## 4. Project Architecture

| Layer | Technology | Location |
|-------|-----------|----------|
| Mobile app | React Native / Expo 54, expo-router, WebView | `fimby-mobile-app/` |
| Auth bridge | Node.js serverless on Vercel, Redis (Upstash) | `fimby-auth-bridge/` |
| Backend + UI | Salesforce Experience Cloud (LWR), Apex, LWC | `FIMBY/force-app/` |

Auth: Mobile → OAuth PKCE → auth bridge exchanges for app JWTs (15min access / 30-day refresh) → JWT Bearer + `/singleaccess` → frontdoor URL → WebView. Salesforce tokens never reach the device.

### Change cost: simple publish vs. full app rebuild

The app is **live and approved on both stores** ([App Store](https://apps.apple.com/us/app/fimby/id6776707632), [Google Play](https://play.google.com/store/apps/details?id=com.fimby.app)). Because the app is a **WebView shell**, the two layers have very different change costs — weigh this on every design choice.

| Change location | Path | Cost to ship |
|--------|--------|--------|
| **Experience Cloud** (Apex, LWC, objects, CMS) | `FIMBY/force-app/` | Targeted deploy + `sf community publish` — **live in minutes** |
| **Mobile app shell** | `fimby-mobile-app/` | **Full store re-submission** to App Store **and** Google Play — review cycle, approval wait, users must update |

**The vast majority of UX/feature work lives in Experience Cloud and ships instantly.** Only changes to the native shell trigger a store re-publish: `app.json` / Expo config, native dependencies, the WebView / auth-bridge wiring, push-notification registration, deep-link / universal-link handling, splash screen, app icons, OS permissions, and expo-router *native* routes.

**Be thoughtful before proposing app-rebuild work.** Prefer an Experience Cloud solution that ships the same day. When a request genuinely needs a native shell change, **say so explicitly and flag the re-publish cost** (two store reviews, approval wait, user update) so the tradeoff is a conscious decision — not a surprise.

### Core data model

| Object | Purpose | Record Types |
|--------|---------|--------------|
| `Needs_Offers__c` | Asks, offers, bulk buys, events | Need, Offer, Bulk_Buy |
| `Response__c` / `Response_Message__c` | Replies + thread messages (MD → Response) | — |
| `Bulk_Buy_Follow_Up__c` | Accountability check-ins | Follow_Up, Restoration |
| `Story__c` / `Story_Comment__c` | Community stories + comments (MD → Story) | — |
| `Library_Item__c` | Lending library items | Personal, FIMBY |
| `Lending_Request__c` / `Loaned_Item__c` / `Lending_History__c` | Borrow lifecycle | — |
| `Conversation__c` / `Message__c` / `Conversation_Member__c` | DM & group messaging | — |
| `Notification__c` | In-app notifications (MD → Contact) | — |
| `Shared_Contact_Info__c` / `Blocked_Contact__c` | Consent-gated sharing / bidirectional blocks | — |
| `Feedback__c` | Reports & feedback (content reports via `Type__c='Content Report'`) | — |
| `Support_Relationship__c` | Support-person & community-group-rep links (MD → Contact) | — |
| `Community_Group_Neighbourhood__c` | Org ↔ neighbourhood junction (MD → Account) | — |
| `Error_Log__c` / `Error_Log_Event__e` | Error logging | — |

Account record types: **HH_Account**, **Neighbourhood_Account**, **Organization** (Community Groups via `Type`), **Boundary_Account**. Contact belongs to Account; most custom objects relate to Contact.

### Identity & acting-as

`FimbyIdentityRepository` caches identity per transaction. Two Contact lookups drive switching: `Logged_In_As_Contact__c` (overrides acting identity — requires Approved `Support_Relationship__c`) and `Logged_In_As_Neighbourhood__c` (overrides neighbourhood context). Key concepts: `realContactId` (who clicked) vs `actingAsContactId` (who it's for). `FimbyContactController.getActingAsContact()` returns both + `isActingAsSelf`. Single active identity per user globally.

**Dual-stamp every action** — record both who clicked (`realContactId`) and who it's for (`actingAsContactId`). Per-object field mapping (**Post Owner** = represented identity shown on feed cards; **Submitted By** = real author at keyboard):

| Object | Post Owner | Submitted By |
|--------|-----------|--------------|
| `Needs_Offers__c` | `Contact__c` | `Posted_By__c` |
| `Story__c` / `Story_Comment__c` | `Posted_By__c` | `Contact__c` |
| `Library_Item__c` | `Owner_Contact__c` | `Listed_By__c` |
| `Message__c` / `Response_Message__c` | `On_Behalf_Of__c` | `Sender__c` |
| `Response__c` | `On_Behalf_Of_Contact__c` | `Contact__c` |
| `Feedback__c` (Content Reports) | `Posted_By__c` | `Contact__c` |
| `Lending_Request__c` | `Requested_By__c` | `Requested_By_Real_Contact__c` |
| `Loaned_Item__c` | `Loaned_To__c` | `Loaned_To_Real_Contact__c` |

⚠️ `Posted_By__c` means "real author" on `Needs_Offers__c` but "represented identity" on `Story__c` — **opposite semantics, same API name**. Always check the per-object mapping.

**Authorization dual-check** — ownership/edit/delete must accept access via **either** path, or users acting as another identity get false-denies:
```
post.Posted_By__c == realContactId  OR  post.Contact__c == actingAsContactId
```
**Vouching is personal** — all vouch actions require the user be acting as their **own** identity; `FimbyVouchController.enforceOwnIdentityForVouching()` is the canonical guard (call it first in every vouch `@AuraEnabled` method).

### Neighbourhood scoping (the trust boundary)
All queries filter by `FimbyIdentityRepository.getNeighbourhoodId()`. New records must be stamped with `Neighbourhood__c`. Users never see content outside their active neighbourhood.

### Event type model
Events are `Needs_Offers__c` with `Type__c='Event'`; `Event_Type__c` (`Gathering` / `Open_Event` / `Community_Event`) drives behaviour. **Critical:** only Gathering uses hard capacity — Open/Community Events must **never** enter capacity-exhaustion paths ("Event Full", disabled CTA). Gate all capacity logic behind `isGathering`, not `isEventType`. Event-scoped DMs reuse `Response__c` + `/response-reply?recordId=...`, never `Conversation__c`.

### Experience Cloud site
Single site **FIMBY1** (`sldsFlexibleLayout`). Theming via `--fimby-*` CSS custom properties with light/dark (`data-theme`). Static resources: `FIMBY_Brand` (tokens, login CSS, theme-init JS), `Impact_Icons` (custom colour icons).

**URLs are owned by Experience Builder** — `sf project deploy` ships LWCs but does **not** create or update pages or routes. New pages require manual Builder setup (flag them — see §8). Path sources: Apex `FimbySettings.getUrl(devName)` (`FIMBY_URL__mdt`); LWC hardcoded paths relative to `basePath`; tab highlighting via `TAB_ROUTES` in `fimbyUniversalHeader`.

### Custom metadata
`FIMBY_App_Settings__mdt` (TTLs, page sizes, rate limits, quiet hours), `FIMBY_URL__mdt` (route paths), `FIMBY_Public_Website_URL__mdt` (public site links), `FIMBY_Celebration_Action__mdt`, `FIMBY_Loading_Message__mdt`, `FIMBY_Seasonal_Theme__mdt`.

### Naming
- Apex: `Fimby` + Domain + Suffix (`Controller`, `Service`, `Job`, `Batch`, `Queueable`, `Action`)
- LWC: `fimby` + camelCase (`fimbyBulkBuyForm`)
- Tests: `[ClassUnderTest]Test`; Inner helpers: `[Domain]Helper` / `[Domain]Updater`

---

## 5. Design Philosophy

FIMBY serves neighbours who may be vulnerable, low-tech, or new to digital community. Every decision favours **belonging over performance, dignity over efficiency, clarity over cleverness.**

- **Always show identity** (multi-identity users): forms call `getActingAsContact()` and display "Posting as: / Responding as: / Messaging as:". The green banner is gated on `hasMultipleIdentities` (`getAvailableIdentities()`); single-identity users never see it. Canonical markup: `fimbyAskOfferComposer` (`.posting-as`, green `--fimby-success-tint`, `border-left: 4px solid var(--fimby-success)`).
- **Privacy as consent:** care prefs optional/editable; contact sharing granular + revocable; blocking bidirectional; deactivation = right to be forgotten; push has quiet hours + per-category prefs.
- **Language & tone:** non-punitive, warm, grounded — "a neighbour over a fence, not a platform issuing instructions." Use *Check-in* not *Report/Flag*, *Ask for Help* not *Escalate*, "Were you able to sort things out?" not "You failed to…", "No response was received" not "No-show". Empathetic error states; neighbourhood-metaphor loading messages.
- **Whimsy with purpose:** celebrations scale by occasion; always respect `prefers-reduced-motion`; offer opt-out in Settings.
- **Build on what exists:** check reusable primitives (`fimbyCard`, `fimbyInfiniteScroll`, `fimbyResponsiveList`, `fimbyImageUploader`, `fimbyRecordEditModal`, …) before creating new components — see the **fimby-lwc** skill.

---

## 6. Salesforce Deployment Rules

**Proactive deploy (default):** when an *approved* task changes Salesforce metadata (incl. LWC bundles), run the targeted deploy before wrapping up the same turn. Never deploy exploratory/unapproved changes. Skip/defer if the user said keep it local/draft, or no CLI org is available.

⚠️ **The Bash shell's cwd is the repo root `c:/Users/srathjen/FIMBY`, which is NOT the Salesforce project — `sfdx-project.json` lives one level down in `c:/Users/srathjen/FIMBY/FIMBY`.** The Bash tool has **no `working_directory` parameter**, and `cd`/`&&` are banned in deploy commands, so a *relative* `--source-dir` resolves against the wrong folder and fails with "File or folder not found." **Always pass an ABSOLUTE `--source-dir` rooted at `c:/Users/srathjen/FIMBY/FIMBY/force-app/...`** — copy-paste the example below and swap only the bundle/metadata tail. Use targeted `--source-dir` (or `--metadata`) — **never** the whole `force-app`. For LWCs, point `--source-dir` at the bundle folder; deploy each changed bundle as its own `--source-dir`.

```bash
sf project deploy start --source-dir "c:/Users/srathjen/FIMBY/FIMBY/force-app/main/default/lwc/<bundleName>" --wait 10 2>&1 | tail -n 20
```
Do not use `cd` / `&&` inside the command; do not include `--target-org`. (Cursor's rule pipes to PowerShell `Select-Object -Last 20`; on bash use `tail -n 20`.)

**MANDATORY pre-deploy checklist — every deploy:**
1. Does `--source-dir` include **any** `.cls`/`.trigger`? **YES →** you MUST add `--tests TestClassName` for each relevant test class (omitting it runs ~600 org tests, 20+ wasted minutes). **NO** (LWC/objects/layouts/flows only) → do **not** add `--tests`/`--test-level`.
2. Never `--test-level RunAllTestsInOrg` / `RunLocalTests` — always name specific tests.
3. Confirm each test class still covers the change (target 80%+, 75% only in a pinch).
4. **Coverage is enforced PER CHANGED CLASS (≥75%), not org-wide.** Every `.cls` in the `--source-dir` set must individually clear 75% from the tests you name — a single class at 74% fails the *entire* atomic deploy even when all named tests pass. So name **each changed class's own test** (changing `FimbySettings.cls` → add `FimbySettingsTest`), not just the test for the behaviour you touched. A `Test coverage of selected Apex Class is NN%` failure is fixed by adding that class's test to `--tests`, never by editing product code.

If deploy output ends with `Error (MetadataTransferError): Metadata API request failed: Missing message metadata.transfer:Finalizing for locale en_US.` the **deploy succeeded** — known CLI locale bug; pass/fail counts shown are display artifacts. Don't re-run `sf project deploy report`.

**Atomic rollback:** a deploy is atomic per call — a failed test rolls back **everything**, including new fields/objects. Deploy schema-only changes (fields, picklist values, new CMDT types) in a separate call **without** `--tests`, then the dependent Apex in a second call **with** `--tests`.

**CMDT records:** `force-app/main/default/customMetadata/*.md-meta.xml` deploy fine **without** `--tests`. New CMDT *types* (`objects/*__mdt/`) must deploy **before** their records. The community profile needs **View Setup and Configuration** to call `CustomMetadataType.getAll()`/`getInstance()` — if `FimbySettings.getUrl()` returns blank in test runs but works for admins, that's the cause.

**Post-deploy publish:** after a successful **LWC** deploy, publish so changes go live (this is the one sanctioned publish — see §3):
```bash
sf community publish --name "FIMBY" 2>&1 | tail -n 20
```
Skip only if the user says not to publish.

**Post-deploy commit (mandatory — no prompt):** after **each successful** org deploy (and after publish when LWC was included), commit immediately. Do not ask whether to commit. One commit per deploy call; stage only paths from that deploy plus related session wiring; brief why-focused message (`Deploy: …`); never push unless asked; never secrets. Skip only on deploy failure or explicit user opt-out (keep local / deploy only / no commit). Empty commit → skip.

**Experience Cloud Setup Required:** CLI deploys LWC bundles but not pages/routes. If you created new page-level LWCs needing routes (e.g. `fimbyManageIdentities` → `/manage-identities`), changed route paths, or components needing page config, add an **Experience Cloud Setup Required** section to the session summary listing them for manual Builder setup.

---

## 7. Salesforce Profile Permissions

**Never deploy Profile metadata** — it overwrites the sys admin's manual customizations.

As the **final step** after any successful deployment, list all **net-new** items that need manual profile updates (modified items already have permissions). Group by type:

```
## Manual Profile Updates Required
The following net new items were deployed. A sys admin should add them to profile permissions as needed:

**Apex Classes:** MyNewController, MyService
**Custom Objects:** My_Custom_Object__c
**Custom Fields:** Account.My_Field__c (if FLS needed)
**Custom Metadata:** My_Setting__mdt.MyRecord
**Pages / Tabs / Flows / VF / Named Credentials:** …
```

When you create any new component (even if not deployed this session), document it for this list so the sys admin knows what to configure.

---

## 8. Skill Routing — load before editing

Before your **first edit of a given file type this session**, invoke the matching skill (it carries mandatory tokens/patterns). These mirror the Cursor `globs` rules.

| Editing… | Load skill |
|----------|-----------|
| `**/*.cls`, `**/*.trigger` | **fimby-apex** (Apex patterns, best practices, notification contract) |
| `**/lwc/**` (any LWC file) | **fimby-lwc** (component patterns, CSS foundations, UI/UX, icons, mobile gestures, checklist) |
| CMS content import packages (zip/JSON for Salesforce CMS) | **salesforce-cms-import** |
| `FIMBY Website/**` going **live to fimby.com** via Respira MCP | **respira-inject** |
| Running browser/QA test scenarios as a persona | **fimby-qa-testing** |

When work spans an LWC and notifications, or Apex and the notification contract, load both relevant skills/reference docs.
