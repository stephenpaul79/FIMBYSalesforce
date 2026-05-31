---
name: Ask / Offer / Event / Bulk Buy — desktop agent QA (runbook)
overview: |
  Executable runbook for Cursor IDE browser QA on FIMBY Ask/Offer flows. Credentials and procedure live only in qa-testing-login.mdc; this file is scenarios, hats, order, and artifacts. Agents: mark todos completed only when outcomes are verified; if blocked, document the blocker and leave todos pending/in_progress—do not bulk-complete to close the session.
  **Build queue:** Product fixes and acceptance live in [ask_offer_event_bulkbuy_fix_backlog.plan.md](./ask_offer_event_bulkbuy_fix_backlog.plan.md) (FIX-BB-*); keep this file for **test** execution and progress only.
  **Verification bar:** Every pass must assess **function** and **UI quality** together—see [UI quality & UX (mandatory with function)](#ui-quality--ux-mandatory-with-function). A flow that “works” but is confusing, off-brand, or hard to navigate is not a clean pass without documented findings. **UX is evaluated per persona** (poster vs responder vs already-responded): [UX by persona](#ux-by-persona-poster-vs-responder--multiple-passes-required)—**one browser walkthrough is not enough** for UX sign-off.
  **Run closed 2026-04-06:** P0 + full P1 (A–D) verified in browser on live org; P2/P3 items were previously waived—re-open and complete with the same **function + UX** bar (see [Runbook completion](#runbook-completion)).
todos:
  - id: p0-preflight
    content: "P0 — Read qa-testing-login.mdc; desktop viewport; note Owner/R1/R2 emails from rule"
    status: completed
  - id: p1-need-anchored
    content: "P1-A — Need (Ask): anchored post; R1+R2 actions; owner thread + notification matrix + artifacts"
    status: completed
  - id: p1-offer-anchored
    content: "P1-B — Offer: R1+R2 + owner checks (see script B: plan quantity before publish); notifications optional"
    status: completed
  - id: p1-event-anchored
    content: "P1-C — Event: RSVP both responders; owner aggregate; RSVP notifications + deep links + artifacts"
    status: completed
  - id: p1-bulkbuy-anchored
    content: "P1-D — Bulk Buy: qty>1; split/edge reserves; reserved state; notifications + artifacts"
    status: completed
  - id: p2-quickpost
    content: "P2 — Quick Post into composer; R1/R2 pair; + UI/UX bar (clarity, nav, CTAs, brand)"
    status: pending
  - id: p2-detail-permissions
    content: "P2 — Detail permissions; owner edit; stale notification titles; + persona-first UX"
    status: pending
  - id: p2-followup-media-pagination
    content: "P2 — Follow-up/accountability; media parity; pagination/refresh; + empty/loading UX"
    status: pending
  - id: p3-polish
    content: "P3 — Empty states; desktop badges; notification copy; + badge vs button + tone"
    status: pending
---

**Summary:** Browser MCP QA (desktop). Secrets and login flow: [qa-testing-login.mdc](../rules/qa-testing-login.mdc) only. **P0 + P1 (A–D) verified** on live org (2026-04-06). **P2/P3** are tracked separately; when executed, they use the same **function + UI/UX** acceptance as P1 — see [UI quality & UX](#ui-quality--ux-mandatory-with-function) and [Runbook completion](#runbook-completion).

**Testing vs build:** Use **this runbook** to **track QA progress** (checklists, per-hat evidence, session notes). Use the separate **[fix backlog / build queue](ask_offer_event_bulkbuy_fix_backlog.plan.md)** for **issues to implement** (FIX-BB-*), priorities, acceptance criteria, and **build** todos—do not mix “what to test next” with “what to ship” in one file.

---

# Ask / Offer / Event / Bulk Buy — desktop agent QA (runbook)

## Do not duplicate the QA rule

**Single source of truth for secrets and global procedure:** [qa-testing-login.mdc](../rules/qa-testing-login.mdc) (repo-relative: `.cursor/rules/qa-testing-login.mdc`).

| In the **rule** only | In **this runbook** only |
|------------------------|------------------------|
| Login URL, passwords, persona table | Post-type scripts (Need / Offer / Event / Bulk Buy) |
| “No URL hacking,” notifications exception, scrolling | Anchored-post model, execution order, P1/P2/P3 |
| Viewport, desktop scope, multi-persona checklist | Per-run artifacts (title, how you re-found the post) |
| Cursor browser MCP (shadow DOM, screenshot+coords, waits) | Role matrix (Owner / R1 / R2), **functional + UI/UX** acceptance (see below) |

**Design / brand context (repo rules, not duplicated here):** [fimby-design-philosophy.mdc](../rules/fimby-design-philosophy.mdc) (tone, identity, clarity) and [fimby-ui-patterns.mdc](../rules/fimby-ui-patterns.mdc) (navigation, persona-first detail pages, badge vs button affordances, empty states, forms).

**Do not paste credentials into this runbook.** When executing, open the rule first, then follow sections below in order.

---

## How to run it

- Use the **todos** in the YAML frontmatter (or the checklist below) **in order**. Complete one P1 post type before the next; each P1 step uses a **new** anchored post and new artifact notes.
- **Todo integrity:** Set a todo to **completed** only after you have **verified** the corresponding checks in the browser (or filed a **blocked** outcome with what you tried). Never mark a batch “all done” because of time limits or stuck UI without saying so.
- **When stuck on the home feed** (post missing, stale cards, search empty): use **Feed reset** in [Automation habits](#automation-habits-see-rule-for-detail) before concluding the post is unreachable.
- **UI quality is not optional:** While exercising each hat and screen, apply [UI quality & UX](#ui-quality--ux-mandatory-with-function). **Poster vs responder UX differ**—see [UX by persona](#ux-by-persona-poster-vs-responder--multiple-passes-required); capture **per-hat** notes in session artifacts, not one generic summary.

### UI quality & UX (mandatory with function)

Use **desktop** viewport; prefer **screenshot + snapshot** so layout, hierarchy, and copy are visible—not only “click succeeded.”

**Thorough page review (required before claiming UX is “good”):**

- **Scroll the full page** as a user would: repeat **`browser_scroll` down** (or scroll the main container) until the tool reports **no further scroll** / scroll boundary. Short pages still get this check; long pages get **multiple viewport screenshots** along the way—not only one `fullPage` capture. Skim **header, body sections, footers, disclaimers, and anything below the fold.**
- **Trust your instincts on duplicates:** two **identical** primary actions (same label, same visual weight) in one flow **should give pause**—users will ask “are these different?” or assume a bug. **Do not** dismiss that because you found two `onclick` handlers in markup; lead with **neighbour impact**, then confirm in code. Flag as **UX defect or design debt** unless product has an explicit, user-visible reason (rare).
- **Order of reasoning:** (1) What would feel wrong or confusing to a low-tech neighbour? (2) What does the full scroll reveal about hierarchy and repetition? (3) Only then, optional code pointers for the team.

### UX by persona (poster vs responder) — multiple passes required

FIMBY detail is **persona-first** (`fimby-ui-patterns`): **poster / organiser** sees management, attention, and responses; a **potential responder** sees what the post is and how to act; someone who **already responded** sees status and next steps—not the same CTAs as a stranger. **The same route can present a legitimately different UI** depending on who is logged in.

- **One UX pass is not sufficient.** Logging in once and scrolling a detail page **does not** validate poster UX if you were a responder (or the reverse). You need **separate judgements** from **each perspective that the product supports** for that post type—at minimum **owner/poster** and **at least one responder** (R1; add **R2** when the UI can differ, e.g. second reservation, waitlist, or thread position).
- **What to do:** For each anchored run, perform **full-page review** (scroll to boundary) and answer the UX table **per hat** after switching accounts per [Persona hats](#persona-hats-fixed-mapping-for-this-runbook). Record **distinct** notes (e.g. “Owner: organiser list + notify pickup clear”; “R1: reservation card + duplicate chat button confusing”)—not one blended paragraph.
- **Sign-off:** Do **not** mark UX as “good” for a scenario if only one persona has been reviewed, unless the runbook explicitly scopes to a single hat (document that scope).

Answer these for **each primary surface** you touch (home feed + filters, composer steps, post detail by persona, response thread, notifications list, messages as needed):

| Question | What “good” looks like (FIMBY-aligned) |
|----------|----------------------------------------|
| **Does it make sense?** | Headings and body copy explain *what this is* and *what happens next* without insider jargon. Bulk Buy / Event / Ask / Offer are distinguishable in **language** and **layout**, not only by a tiny label. |
| **Is it usable?** | Primary action is obvious; destructive or irreversible steps are confirmed in plain language. Errors are **near the action**, empathetic, with a recovery path (see `fimby-ui-patterns`: inline errors, not vague full-page dead ends). |
| **Can the user navigate easily?** | Back / Home / breadcrumbs are obvious; bottom nav and header do not fight each other; fixed chrome does not hide the primary CTA (scroll if needed—see QA rule). Flat flows with clear back affordance per `fimby-ui-patterns`. |
| **Are purpose and actions clear?** | **Persona-first:** poster vs responder vs “already responded” sees the right **header actions** and **one** clear CTA—not generic “Respond” when already responded (see persona-first detail in `fimby-ui-patterns`). User knows **why** a button exists (e.g. reserve vs RSVP vs message). |
| **On brand?** | **Tone:** warm, neighbourly, non-punitive (`fimby-design-philosophy`). **Visual hierarchy:** badges read as **inert** status; buttons read as **tappable** actions—shape/elevation distinguish them, not colour alone (`fimby-ui-patterns` button vs badge). **Identity:** “Posting as” / acting-as is visible where the product promises it. **Tokens:** no rogue hardcoded colours in devtools spot-checks when validating (agents: note obvious off-token clashes). |

**Minimum evidence per run:** At least **one UX note per persona / hat** that saw a **meaningfully different** screen (poster vs responder; add R2 when surfaces differ). A **single** combined “UX pass” without **hat-separated** notes is **not** enough for UX acceptance. File neutral observations or defects when something blocks comprehension.

### Execution checklist

**P0 — Pre-flight**

- [ ] Read [qa-testing-login.mdc](../rules/qa-testing-login.mdc) (login URL, personas, password, navigation, MCP clicks).
- [ ] Browser wide (~1280×800+); use **only** allowed login entry then UI navigation (no pasted app URLs).
- [ ] Confirm Owner / R1 / R2 emails from the rule for hat switches.
- [ ] Skim [fimby-design-philosophy.mdc](../rules/fimby-design-philosophy.mdc) + [fimby-ui-patterns.mdc](../rules/fimby-ui-patterns.mdc) so **brand and UX expectations** are loaded before you judge screens.

**P1-A — Need (script A)** — new unique title; log artifacts

- [ ] **Owner:** Create Need end-to-end; record title + how you reopen post (feed/notification).
- [ ] **R1:** Find post in feed (badge Ask/Need); respond from **feed** and **detail**; thread/reply if present.
- [ ] **R2:** Second response or reply per product rules on **same** post.
- [ ] **Owner:** Thread aggregate; open **Notifications**; verify P1 matrix (appear, copy, deep link, read/unread) for Owner, R1, R2 **as applicable**.
- [ ] **UX:** For each hat above, note whether feed cards, detail, and thread **read as neighbour-clear** (purpose + next step); flag hierarchy or copy issues per [UI quality & UX](#ui-quality--ux-mandatory-with-function).

**P1-B — Offer (script B)** — new anchored post

- [ ] **Owner:** Create Offer; artifacts.
- [ ] **R1 / R2:** Respond paths + offer badges + notification copy; owner outcomes if applicable.
- [ ] **UX:** Offer vs Ask vs badge vs button affordances; confirm **one** obvious primary action on detail for each persona.

**P1-C — Event (script C)** — new anchored post

- [ ] **Owner:** Event with date/time visible.
- [ ] **R1 / R2:** RSVP variants; **Owner:** attendee summary; all: RSVP notifications + detail deep links.
- [ ] **UX:** Date/time and event purpose visible “above the fold”; RSVP states unambiguous; no duplicate or competing CTAs without a clear hierarchy.

**P1-D — Bulk Buy (script D)** — new anchored post, quantity > 1

- [ ] **R1:** Reserve subset; **R2:** remainder or validation edge.
- [ ] **All:** Reserved state on detail; notifications with quantity/item context; owner sees holders.
- [ ] **UX:** Reserve flow and “people who reserved” / pickup / group chat story **read as one narrative**; user can tell **what’s left**, **who holds what**, and **when** chat vs DM applies (see [UI quality & UX](#ui-quality--ux-mandatory-with-function)).

**P2 / P3** (map to `p2-*` / `p3-polish` todos; **function + UX** for each)

- [ ] **Quick Post** → composer preselection + at least one **R1/R2** pair on that post. **UX:** progressive disclosure (one concern per step); chosen post type is obvious before fields; primary/next actions read as brand form nav (`fimby-ui-patterns`).
- [ ] **Detail permissions**; owner **edit**; **stale** notification titles after edit. **UX:** owner vs non-owner surfaces match persona-first rules (correct header actions; no misleading disabled owner controls for strangers).
- [ ] **Follow-up / accountability** by role; **media** visible consistently; **pagination / refresh** resilience (e.g. messages, feed). **UX:** empty states warm/actionable; refresh does not feel like data loss; images consistent in card vs detail.
- [ ] **Polish:** empty states; desktop **badges/icons**; **notification copy** (actor + post type). **UX:** at a glance, rows read as neighbour-to-neighbour, not generic alerts; post type and next step are clear without opening.

**Historical note:** These were **waived** on 2026-04-06 as optional-only; they are **in scope** for any run that promotes P2/P3 to required—still using the same UX bar as P1.

---

## What this runbook is for

- **Agent:** Cursor IDE **browser MCP**, **desktop only** (wide window).
- **Scope:** Routes around ask-offer list/post, respond, response detail/reply, quick-post, asks-offers detail; Event and Bulk Buy as variants.
- **Goal:** Per **post type**, one **anchored** post and **three hats** (owner + two responders), then **notifications** and **deep links** for each hat — plus **qualitative UX per persona** ([UI quality & UX](#ui-quality--ux-mandatory-with-function), [UX by persona](#ux-by-persona-poster-vs-responder--multiple-passes-required)): clarity, navigability, action purpose, and brand/tone **from each perspective that differs**.

---

## Persona hats (fixed mapping for this runbook)

Use the **emails and password from the rule**. Naming here is **role**, not device:

| Hat | Typical email (see rule) | Role in runs |
|-----|--------------------------|--------------|
| **Owner** | Desktop Tester | Creates post; verifies aggregate + notifications |
| **Responder 1 (R1)** | Mobile Tester | Primary respond / RSVP / reserve |
| **Responder 2 (R2)** | SF Tester | Second action on same post (thread, alternate RSVP, second reserve, etc.) |

**Hat switch (every time):** Log out → `https://our.fimby.com/login` → next persona → **confirm redirect** before steps (per rule).

---

## Scenario matrix (P1 — plan before you publish)

Use this table so **post setup**, **who does what**, and **what to verify** are fixed **before** the Owner clicks Publish. Emails/passwords: [qa-testing-login.mdc](../rules/qa-testing-login.mdc).

| ID | Post type | Owner creates (Desktop) | **Pre-publish** (must allow the row’s R1+R2 story) | R1 (Mobile) | R2 (SF) | Everyone verifies |
|----|-----------|---------------------------|---------------------------------------------------|-------------|---------|-------------------|
| **P1-A** | Need / Ask | Need with unique title | Usually none; confirm thread allows **two** responses if product does. | Respond from **feed** and **detail**; use thread/reply if present. | **Second** response or reply on **same** post (per product rules). | Owner: thread aggregate + [P1 notification matrix](#execution-order-systematic). R1/R2: rows for each other’s actions where applicable. |
| **P1-B** | Offer | Offer with unique title | **Quantity (and per-response limits)** so **two** responders can still act after R1 if you need both hats to submit—e.g. qty **≥ 2** and limits not “one claim total.” | Respond / request per Offer flow. | **Second** response or alternate outcome on **same** post **only if** pre-publish allowed it. | Offer badges, owner outcome state, notification copy; [P1 matrix](#execution-order-systematic). |
| **P1-C** | Event | Event; date/time visible in UI | If testing **two** distinct RSVPs, ensure event isn’t single-capacity—set capacity / options per composer. | RSVP (**Interested** or **Going**—pick one). | **Different** RSVP **if the product supports** multiple states per user or alternate choice. | Owner: attendee summary; RSVP notifications + deep link to event detail; [P1 matrix](#execution-order-systematic). |
| **P1-D** | Bulk Buy | Bulk Buy; unique title | **Quantity > 1**; choose total so **R1** can reserve a **subset** and **R2** can take **remainder** or trigger **edge** (e.g. oversell). | Reserve **subset** of units. | Reserve **remainder** or exercise **validation** edge. | Reserved state on detail; notifications with qty/item context; owner sees **who holds what**; **group chat** (see script **D**): user-facing **Open Group Chat** / thread is for when **all shares are reserved** (fully allocated); [P1 matrix](#execution-order-systematic). |

**P2 / P3** are **not** fully scenario’d in the matrix table: use the [Execution checklist](#execution-checklist) bullets; each run still needs a **named goal** in session notes (e.g. “Quick Post → Need → R1+R2 once”) plus **at least one UX observation** per [UI quality & UX](#ui-quality--ux-mandatory-with-function).

---

## Artifacts (required each anchored run)

Record in session notes (or ticket), not in this file:

1. **Post type** (Need / Offer / Event / Bulk Buy).
2. **Unique title** you typed (so filters/search can find it without URL pasting).
3. **Scenario pre-check (before Publish):** For scripts that need **two responders** on the **same** post, the **Owner** must set composer fields so the product allows it—e.g. **Offer:** set **quantity (and per-response limits)** so more than one person can claim/respond; **Bulk Buy:** quantity **> 1** as already required; **Event:** RSVPs not capped at one unless you intentionally test “full.” **Do not** publish with defaults that close the post after R1 and then label “R2 blocked” a product bug—that is **bad test design**, not a defect.
4. After publish: **how you reopened the post** (feed + filter + **View Post**, notification tap, etc.) — **no** pasted detail URLs unless the product exposed them via UI copy.
5. **Time** (rough) if debugging ordering.
6. **UX / brand notes (short), per hat:** For **each** persona that exercised a different screen (owner, R1, R2 as applicable), one or two bullets on **clarity**, **navigation**, **CTA purpose**, and **tone/visual** fit (see [UI quality & UX](#ui-quality--ux-mandatory-with-function) and [UX by persona](#ux-by-persona-poster-vs-responder--multiple-passes-required)). Do not collapse into a single “UX looked fine.”

---

## Automation habits (see rule for detail)

- Prefer **UI paths** from the rule; **header Notifications** to `/notifications` is allowed.
- **`lightning-button` / shadow DOM:** if ref click does nothing, **screenshot → `browser_mouse_click_xy`** per rule; then **wait** and re-snapshot.
- Composer success **View Post** flaky in embedded browser: **Home → feed → filter Ask & Offer → correct card → View Post** (rule).
- **Feed reset (cache / stale list):** If the anchored post does not appear after publish or search looks wrong, do **not** skip straight to failure. In order: **FIMBY home** or **Home** breadcrumb/link → **Ask & Offer** → pick the right sub-filter (**Asks** / **Offers** / **Events** / **Bulk Buys**) → use **Refresh feed** if the control exists → wait 2–5s → re-search by **exact title**. Repeat once. Still missing: try scrolling the feed; **Owner** may use **My Stuff → My Posts → View post** for the card they created (still UI-only). Neighbours rely on feed refresh + filters + search—no pasted detail URLs.
- **Many duplicate “View Post”** on feed: use **title**, **filters**, **scroll** so you open the anchored post only. **Do not rely on “All”** when Event and Offer posts are mixed—set **Ask & Offer** and the right **sub-filter** (e.g. **Offers**) before choosing **View Post**.
- **Click intercepted** on bottom nav: **scroll**, **Escape**, or second **duplicate ref** for same label (rule).

---

## Execution order (systematic)

Complete **Priority 1** for **one post type at a time** using the **anchored post** + **hats** below. Do **not** interleave types on the same post.

### Priority 1 — must pass per post type (same anchored post)

1. **Owner:** Composer end-to-end for that type; identity/acting-as correct.
2. **R1 + R2 (each logged in):** Post visible in feed/list with **correct type badge**; open detail via UI.
3. **R1:** Respond / RSVP / reserve from **feed** and **detail** if both exist.
4. **R2:** Different allowed action on **same** post; no clobbered thread/order.
5. **Owner:** Counts/state match; **Notifications** — for **each** hat, verify:

| Check | Owner | R1 | R2 |
|-------|:-----:|:--:|:--:|
| Row appears when another party acts | ✓ | ✓ | ✓ |
| Copy: correct **actor name** + **post context** | ✓ | ✓ | ✓ |
| Open row → correct **detail / response / reply** | ✓ | ✓ | ✓ |
| Read/unread + badge consistent after open | ✓ | ✓ | ✓ |

**After the matrix:** For each hat, confirm [UI quality & UX](#ui-quality--ux-mandatory-with-function) (sense-making, navigability, action purpose, brand). Log gaps as observations or defects.

6. **Bulk Buy (type D only):** quantity split, reserve remainder or validation; notifications mention **quantity/item** context; **after the last share is reserved**, confirm **group conversation** — detail shows **Open Group Chat** (or equivalent), participants can open the thread and (optional) send a test message; reserver copy should reflect **waiting for all spots to fill** until **Fully Reserved**.
7. **Event (type C only):** aggregate on owner; RSVP notifications name right actor.

### Priority 2 — after P1 stable

- **Quick Post** → composer variant / preselection; then **one** R1/R2 pair on that post.
- Detail **permissions** (owner edit/delete vs non-owner); stale title in notifications after edit.
- Follow-up / accountability visibility by role.
- **Media:** same images all parties.
- Pagination / refresh resilience.
- **UX:** Same [UI quality & UX](#ui-quality--ux-mandatory-with-function) bar—**usability** and **on-brand** checks are not deferred to P3.

### Priority 3 — polish

- Empty states; desktop badge/icon consistency; notification copy distinguishes **Need / Offer / Event / Bulk Buy** and **acting user** with three parties.
- **UX:** Deliberately judge **empty** and **edge** screens (not only happy path): do they feel **warm and actionable** (`fimby-ui-patterns`), and do badges vs buttons remain visually distinct?

---

## Per–post-type scripts (single anchored post, three hats)

Substitute a **unique title** each run. Steps assume **UI-only** navigation per rule.

### A. Need (Ask)

1. **Owner:** Create **Need**; note title.
2. **R1:** Respond from feed + detail; thread/reply if available.
3. **R2:** Second response or reply per product rules.
4. **Owner:** Thread aggregate; **Notifications** matrix (P1 table).

### B. Offer

1. **Owner:** Create **Offer**; note title. **If P1-B requires both R1 and R2 to submit a response:** in the composer, set **quantity** (and **per-response limit** if shown) so **at least two neighbours can still respond** after R1—e.g. quantity **≥ 2** and limits that do not collapse to a single claim for the whole Offer. A single-unit Offer that goes **“all spoken for”** after one response is **expected**; that scenario is for **one-responder** flows, not a two-hat R1+R2 matrix.
2. **R1:** Respond / request per flow.
3. **R2:** Second path or alternate outcome on the **same** post (only valid if step 1 allowed it).
4. **All:** Offer badges + notification copy; owner outcomes if applicable.

### C. Event

1. **Owner:** Create **Event** (date/time visible).
2. **R1:** RSVP **Interested** (or Going).
3. **R2:** Different RSVP if supported.
4. **Owner:** Attendee summary; **all:** RSVP notifications + deep link to event detail.

### D. Bulk Buy

1. **Owner:** **Quantity > 1**; note title.
2. **R1:** Reserve subset.
3. **R2:** Reserve remainder **or** validation edge (oversell / waitlist).
4. **All:** Reserved state on detail; notifications; owner sees who holds what.
5. **Group conversation (new):** The **group chat** is the shared thread for organiser + everyone who reserved. **Product rule:** it **comes into play once all shares are reserved** (nothing left to allocate — status moves toward **Fully Reserved** / pickup handoff). **QA pass:** after the **final** reservation fills the buy, each hat (Owner, R1, R2) opens the bulk buy detail and confirms **Open Group Chat** (or **Open Group Chat** in the body + link in **Messages** if that is how the app surfaces it), navigates in, and verifies they see the same multi-participant conversation. Optionally send one short message as R1 and confirm Owner + R2 see it. **Do not** treat partial reservations as the group-chat milestone—wait until the buy is **fully reserved**.

---

## Runbook completion

**Session:** 2026-04-06 — **Priority 1 (mandatory) complete** on **https://our.fimby.com** with desktop browser MCP and personas from [qa-testing-login.mdc](../rules/qa-testing-login.mdc).

| Tier | Scope | Outcome |
|------|--------|---------|
| **P0** | Pre-flight, viewport, persona table | **Verified** (prior + this run). |
| **P1-A — Need** | Anchored Need; R1/R2; owner notifications | **Verified** (completed in prior runs; artifacts in session history). |
| **P1-B — Offer** | Offer; R1/R2; badges / notifications | **Verified** (prior runs). |
| **P1-C — Event** | Event; RSVPs; owner aggregate; notifications | **Verified** (prior runs). |
| **P1-D — Bulk Buy** | Split reserves; holders; qty in notifications; **group thread** via `/conversation?id=…` | **Verified** live: anchored **`QA Bulk Buy P1D 2026-04-05-RUN`**; group header, members, system + user messages; owner notification rows with share counts + title. |
| **P2 / P3** | Quick post, permissions, follow-up/media/pagination, polish | **Waived on 2026-04-06** as optional-only. **Required when scheduled:** execute with **function + [UI quality & UX](#ui-quality--ux-mandatory-with-function)**; update frontmatter todos and this table with evidence (not waived-by-default). |
| **UX retraced pass** | Home → Create (Ask composer) → Notifications → Bulk Buy detail → Messages; desktop MCP + screenshots | **Recorded 2026-04-05** — see [UX pass log (retraced steps)](#ux-pass-log-retraced-steps). **R1-only** (Mobile); **not** a full UX sign-off per [UX by persona](#ux-by-persona-poster-vs-responder--multiple-passes-required)—repeat as **Desktop owner** (poster) and **SF/R2** when surfaces differ. |

---

## UX pass log (retraced steps)

**When:** 2026-04-05. **Where:** `https://our.fimby.com` (live). **Persona:** **Mobile Tester** (R1) **only** — poster/owner and R2 were **not** part of this session; see [UX by persona](#ux-by-persona-poster-vs-responder--multiple-passes-required). **Method:** Cursor browser MCP: snapshot + viewport screenshots on each surface; judgement against [UI quality & UX](#ui-quality--ux-mandatory-with-function) and `fimby-design-philosophy` / `fimby-ui-patterns`.

**Path retraced:** **Home** (Ask & Offer → Bulk Buys) → **Create new post** → **Make an Ask** (composer only; no publish) → **FIMBY home** → **Notifications** → **Home** → **View post** (anchored Bulk Buy) → **FIMBY home** → **Messages**.

| Surface | Sense-making & hierarchy | Usable & actions | Navigation | On-brand |
|---------|---------------------------|------------------|------------|----------|
| **Home feed** | Cards show poster, **BULK BUY** pill, title, snippet, **1 reserved / 7 available** pills, and a single dominant **Reserve-A-Share** CTA—story is clear for a neighbour scan. | Primary action is obvious; status pills vs CTA read as different tiers (badge-like vs button). | Two-row filter (segment + sub-filter) is easy to learn but **tall**; **Refresh feed** is discoverable. | Warm neutrals + teal CTAs + rounded cards match FIMBY; iconography is friendly. |
| **Create → Ask composer** | **Your Ask** + **Post Settings**; helper copy for Urgent / auto-accept is plain-language. | **Posting as: Mobile Tester** visible (identity). **Next** disabled until required fields—good guardrail. | Breadcrumb **Home > Create a Post**; **Go back to type selection** is explicit. | Tone is neighbourly; form layout matches “one concern per section.” **Check on other viewports:** bottom nav may still show **Home** as selected while user is in composer—confirm whether that matches product intent. |
| **Notifications** | Rows include **actor + post title** (e.g. `Desktop Tester in QA Bulk Buy P1D 2026-04-05-RUN`); **Today / Yesterday** groupings help. | **Mark all as read**, **Clear all**, **Notification settings** are visible power actions. | **Home** crumb + header **Notifications**; standard pattern. | Visual style matches app. **UX concern:** several **consecutive** rows with **identical** primary line (same post) feels noisy—users may want differentiated secondary text or grouping. **Verify** bottom-nav active state matches current page (automation saw ambiguity—confirm visually). |
| **Bulk Buy detail (reserver)** | **Your Reservation**, **3 shares reserved**, and “waiting for all spots to fill” explain state. Payment disclaimer is clear and non-punitive. | **Open Group Chat** sits beside **Cancel Reservation** on one row (y≈509px); a **second** **Open Group Chat** appears below (y≈593px)—same handler, not a mis-click: the template renders chat **twice** when `hasGroupConversation` is true (see [Correction — Open Group Chat](#correction--open-group-chat-implementation)). Destructive action remains visually secondary. | **More actions** in header; scroll shows thermometer → reservation card → separate **Group Chat** section. | Disclaimer tone fits `fimby-design-philosophy`. **Thermometer legend “1 reserved”** vs **“3 shares reserved”** in the card: likely **distinct reservers (1)** vs **share units (3)**—not necessarily inconsistent, but copy should say **shares** vs **people** so neighbours do not read it as a bug. |
| **Messages** | **All / Unread / Archived** filters; rows show peer, **ASK / OFFER** badge, title snippet, time—purpose of screen is clear. | **Compose** available; row **…** menus for thread options. | **Home** crumb; bottom **Messages** active—consistent. | Same earthy palette; badges help scan type. Tree still exposes many **Open conversation** nodes without title in YAML (automation); visually titles appear on rows—aligns with known feed a11y gap. |

**Follow-ups (not necessarily defects):** (1) Deduplicate or differentiate stacked notification rows for the same post. (2) **Open Group Chat:** decide whether reservers need the button in **Your Reservation** *and* in **section-group-chat**, or collapse to one placement / differentiate labels. (3) Thermometer legend: label **shares** vs **neighbours who reserved** if both concepts stay. (4) Repeat pass as **Desktop / owner** for Edit / Delete / organiser CTAs and **stale title** behaviour.

### Correction — Open Group Chat (implementation)

Re-checked live on **`QA Bulk Buy P1D 2026-04-05-RUN`** (Mobile / reserver): bounding boxes show **two** `Open Group Chat` buttons stacked (~84px apart), first **on the same row as** **Cancel Reservation** (not two copies of the same row).

In **`fimbyBulkBuyDetailBody.html`**, the label is rendered in **two** places when `hasGroupConversation` is true:

1. **Inside the “Your Reservation” card** (`hasUserReservation`): primary chat **next to** cancel (`lines 67–72`).
2. **Again in a separate “Group Chat” section** (`section-group-chat`, `lines 204–211`).

Both call the same `handleOpenGroupChat`. So the earlier UX note was right that the screen shows **two identical primary CTAs**, but wrong to imply it was accidental or only “viewport” duplication—it is **structural** in the markup. Product follow-up: keep one surface for reservers, or change the second line to supporting copy (e.g. “Coordinate pickup in the group thread”) so it does not read as two equal buttons.

---

## Tech map (reference)

- Routes: Ask/Offer list & post, Need list/detail, Respond, Response detail/reply, Quick Post (see Experience routes in repo).
- LWCs: `fimbyAskOfferComposer`, `fimbyNeedOfferDetail`, `fimbyQuickPostForm`, `fimbyHomeFeed`, `fimbyResponseThread`.
- Apex (reference): `FimbyAskOfferController`, `FimbyBulkBuyController`, `FimbyBulkBuyReservationController`, `FimbyGroupConversationController`, `FimbyFollowUpController`, `FimbyHomeController`, `FimbyResponseThreadController`, notifications/`getBadgeCounts` alignment.
- Bulk Buy **group chat** UI: `fimbyBulkBuyDetailBody` (`Open Group Chat`, `Group_Conversation__c` on `Needs_Offers__c`); primary route **`/conversation?id=…`** with **`fimbyConversationRouter`** mounting `fimbyGroupConversation` when `Is_Group__c` is true. A separate **`/group-conversation`** page must exist in Experience Builder to use that URL (live org may show **Invalid Page** until published). **Note:** chat entry is wired in **two** template blocks when `hasGroupConversation` (reservation card + `section-group-chat`); see [Correction — Open Group Chat](#correction--open-group-chat-implementation).

---

## Defect logging

- Group by **epic:** composer vs detail vs response thread vs notifications vs **UX / content / brand** (clarity, hierarchy, wrong tone, confusing CTA).
- Each item: **post type**, **hat** (Owner / R1 / R2), **expected vs actual**, **title or id** if captured from UI. For UX-only issues, say **what confused a neighbour** and **what principle** from `fimby-design-philosophy` / `fimby-ui-patterns` is violated.

### Logged (agent / tooling)

| Date | Area | Summary |
|------|------|---------|
| 2026-04-05 | Home feed / a11y | **Card titles not exposed on feed rows in the accessibility snapshot:** controls surface as repeated **View post** / **View Post** (and similar) **without** post title or type in the accessible name. Agents cannot map a `ref` to a specific anchored post from the YAML tree alone—must use **exact-title search + highlight**, **screenshot**, and/or **Ask & Offer sub-filters + scroll** before clicking. **Risk:** wrong card opened; false “post missing” if automation picks the first `View post`. **Product follow-up (optional):** tie each primary action to visible title (e.g. `aria-labelledby` / descriptive `aria-label` including title + post type). |
| 2026-04-05 | Home feed / navigation | **Wrong post opened** when using **All** feed + imprecise click: e.g. `mouse_click_xy` landed on another row and opened an **Event** detail instead of the anchored **Offer**. **Mitigation verified:** **Ask & Offer → Offers** (or correct sub-filter), **Ctrl+F title** / in-app search, then **View Post** on the highlighted card (or `browser_click` on the **View Post** ref paired with **bounding-box** for that row after search scroll). |
| 2026-04-06 | Bulk Buy / conversation | **Live P1-D pass (anchored post `QA Bulk Buy P1D 2026-04-05-RUN`):** `/conversation?id=<group Conversation__c>` loads **group** UI: post title in header, member count, system line (e.g. reservation), thread messages. Owner **Notifications** rows include **quantity + post title** (`Mobile reserved 3 shares…`, `SF Phone reserved 4 shares…`). **`/group-conversation?id=…` on prod returned `Invalid Page`** (Experience route not published); **do not** rely on that URL until the page exists in the site. |
| 2026-04-05 | UX / Bulk Buy detail (R1) | **Open Group Chat** appears **twice** by design in `fimbyBulkBuyDetailBody` (reservation card + `section-group-chat`); same handler—consider one CTA or differentiated copy. Thermometer **“1 reserved”** vs card **“3 shares”** = distinct **people** vs **units**—improve labels. **Notifications:** duplicate row text. See [Correction — Open Group Chat](#correction--open-group-chat-implementation). |

### Runbook mistakes (not product defects)

| Date | What went wrong | Correct approach |
|------|-----------------|------------------|
| 2026-04-05 | P1-B **R2** could not respond after **R1** on the same Offer. | **Owner** had published an Offer with **only one claim/slot** (default quantity). That is **correct product behavior**, not a bug. For any script that needs **R1 and R2** both to respond, **decide in advance** and set **quantity / limits in the composer** before publish—see **Artifacts** pre-check and script **B** step 1. |
