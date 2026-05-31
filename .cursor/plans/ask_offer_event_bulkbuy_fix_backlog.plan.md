---
name: Ask / Offer / Event / Bulk Buy — fix backlog (build queue)
overview: |
  Actionable issues distilled from browser QA + UX review ([ask_offer_event_bulkbuy_qa.plan.md](./ask_offer_event_bulkbuy_qa.plan.md)). Use **this file** to track what to **build** (status, priority, acceptance). Use the **QA runbook** to track **testing progress** (P0–P3, personas, evidence)—not implementation tasks.
todos:
  - id: fix-bb-chat-dup
    content: "FIX-BB-01 — Bulk Buy: remove or differentiate duplicate Open Group Chat (reserver)"
    status: pending
  - id: fix-bb-thermometer-copy
    content: "FIX-BB-02 — Bulk Buy: clarify thermometer vs “Your Reservation” counts (people vs shares)"
    status: pending
  - id: fix-notif-dedupe
    content: "FIX-BB-03 — Notifications: reduce noise when many rows share same primary line"
    status: pending
  - id: fix-feed-a11y-titles
    content: "FIX-BB-04 — Home feed: expose post title/type in accessible names for card actions"
    status: pending
  - id: fix-exp-group-conversation-route
    content: "FIX-BB-05 — Experience: publish or align /group-conversation (Invalid Page on prod)"
    status: pending
  - id: fix-nav-active-composer
    content: "FIX-BB-06 — Nav: bottom-tab active state vs Create/composer route (if unintended)"
    status: pending
  - id: fix-messages-a11y-rows
    content: "FIX-BB-07 — Messages inbox: richer accessible names on conversation rows (parity with visuals)"
    status: pending
---

**Paired doc:** [Ask / Offer / Event / Bulk Buy — desktop agent QA (runbook)](./ask_offer_event_bulkbuy_qa.plan.md) — execution order, personas, **test** todos, UX methodology, defect *log* (historical). **This file** is the **fix queue** you run builds against.

---

# Fix backlog — Ask / Offer / Event / Bulk Buy

## How to use

| Doc | Purpose |
|-----|---------|
| **QA runbook** | What to test, how, per hat; mark **testing** todos complete when verified; paste session artifacts. |
| **This backlog** | What to **change in product**; move todos to **completed** when shipped + re-tested (link PR or work item). |

When an issue ships: confirm on **live** or scratch org per [qa-testing-login.mdc](../rules/qa-testing-login.mdc), then check the row and the YAML todo.

---

## Issues (build queue)

### FIX-BB-01 — Duplicate **Open Group Chat** on Bulk Buy detail (reserver)

| Field | Detail |
|-------|--------|
| **Priority** | P1 — UX / trust |
| **Area** | Bulk Buy detail · `fimbyBulkBuyDetailBody` |
| **Problem** | Two identical primary buttons (`Open Group Chat`) when `hasGroupConversation`: one in **Your Reservation** (with Cancel), one in **`section-group-chat`**. Same handler; reads as mistake or double-tap confusion. |
| **Direction** | Prefer **one** primary entry for **reservers** (keep in reservation card **or** standalone section, not both). If organiser/non-reserver still needs the lower block, gate `section-group-chat` so reservers do not see a duplicate. Optionally second line = supporting text (“Pickup coordination happens in the group thread”) with single button above. |
| **Hint** | Template: `FIMBY/force-app/main/default/lwc/fimbyBulkBuyDetailBody/fimbyBulkBuyDetailBody.html` (~lines 67–72 vs 204–211). |
| **Acceptance** | Logged-in reserver sees **at most one** `Open Group Chat` primary in the body **or** two controls with **clearly distinct** labels/roles; manual pass R1 + spot-check owner. |

---

### FIX-BB-02 — Thermometer legend vs “Your Reservation” numbers (wording)

| Field | Detail |
|-------|--------|
| **Priority** | P1 — comprehension |
| **Area** | Bulk Buy · thermometer + reservation card |
| **Problem** | Legend can read **“N reserved”** (often **distinct reservers**) while **Your Reservation** says **“M shares reserved”** (units). Neighbours may think the UI contradicts itself. |
| **Direction** | Label legend and card so **units (shares)** vs **people (who reserved)** are explicit (copy + optional tooltip). Align with data model in Apex/component getters. |
| **Hint** | `fimbyBulkBuyDetailBody` thermometer / `legendReservedCount` / `reservedPillText` and reservation strings. |
| **Acceptance** | With multi-share reserver + partial fill, a tester can explain both numbers without support. |

---

### FIX-BB-03 — Notifications list: repeated primary line for same post

| Field | Detail |
|-------|--------|
| **Priority** | P2 — noise / scanability |
| **Area** | Notifications UI / notification payload or list template |
| **Problem** | Multiple consecutive rows with **identical** primary text (same actor + post title) — hard to scan; feels like spam. |
| **Direction** | Group/coalesce, **differentiated secondary line** (event type, action: reserved vs message), or collapse burst from same post. Product call. |
| **Acceptance** | Same scenario produces distinguishable rows **or** grouped entry; R1 manual pass. |

---

### FIX-BB-04 — Home feed: card actions missing title in accessible name

| Field | Detail |
|-------|--------|
| **Priority** | P2 — accessibility + safer automation |
| **Area** | Home feed cards · `fimbyHomeFeed` (or card child) |
| **Problem** | Primary controls expose as **View post** / **View Post** without post title or type in the accessible name — screen readers and MCP snapshots cannot disambiguate. |
| **Direction** | `aria-labelledby` / descriptive `aria-label` including **title + post type** (or equivalent). |
| **Acceptance** | Snapshot or AT shows unique names per card; QA agent can target correct post without title search workaround. |

---

### FIX-BB-05 — Experience route **`/group-conversation`** returns Invalid Page on prod

| Field | Detail |
|-------|--------|
| **Priority** | P1 — routing / parity (if product still references URL) |
| **Area** | Experience Builder · site map |
| **Problem** | Live QA: `/group-conversation?id=…` → **Invalid Page**; primary path may be `/conversation?id=…` instead. Any code or copy still pointing at old URL breaks. |
| **Direction** | Publish missing page, **or** redirect, **or** remove references from product/docs. |
| **Hint** | See QA runbook [Tech map](./ask_offer_event_bulkbuy_qa.plan.md#tech-map-reference) + defect log 2026-04-06. |
| **Acceptance** | No dead link from in-app navigation; documented canonical URL for group chat. |

---

### FIX-BB-06 — Bottom navigation active state vs **Create** / composer

| Field | Detail |
|-------|--------|
| **Priority** | P3 — polish (confirm intent first) |
| **Area** | App shell / bottom nav · Experience theme |
| **Problem** | UX pass noted **Home** (or another tab) may appear selected while user is on **Create a Post** / composer — may confuse “where am I?” |
| **Direction** | If unintended: highlight **Create** or neutral state during composer. If intended: document. |
| **Acceptance** | Design agrees; behaviour matches. |

---

### FIX-BB-07 — Messages list: generic **Open conversation** in accessibility tree

| Field | Detail |
|-------|--------|
| **Priority** | P2 — a11y parity with visuals |
| **Area** | Messages inbox list |
| **Problem** | Rows show titles visually; a11y tree exposes repeated **Open conversation** without thread title/participant context. |
| **Direction** | Richer `aria-label` / listbox row pattern including peer + subject snippet. |
| **Acceptance** | Screen reader or snapshot distinguishes threads without visual-only scan. |

---

## Out of scope here (process / test design)

- **Wrong post opened** due to **All** feed + fuzzy click — mitigated by filters + search; not a code fix unless tightening feed hit targets.
- **P2/P3 QA execution** (Quick Post, permissions, pagination) — tracked in **QA runbook** todos until tested; new product issues discovered there get **new rows** in this backlog.

---

## Changelog

| Date | Change |
|------|--------|
| 2026-04-05 | Initial backlog from QA + UX pass notes. |
