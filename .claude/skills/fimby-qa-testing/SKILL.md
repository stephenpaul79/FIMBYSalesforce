---
name: fimby-qa-testing
description: FIMBY QA — test credentials, personas, login flow, navigation discipline, and multi-persona validation for browser-driven testing of the FIMBY Experience Cloud site (desktop + emulated mobile). Load when asked to run, test, or QA a FIMBY flow as a persona, or to verify a change in the live app.
---

# FIMBY QA & Login

> **Tooling note.** The Cursor rules drive QA through Cursor's `cursor-ide-browser` MCP. Claude does **not** have that tool. Use whatever browser-automation surface is connected to this session (a browser MCP if available, or the `verify` / `run` skills). If no automation surface can reach a step, **do not declare it out of scope** — hand off to the human tester (see *Human–agent handoff*). There is no separate persistent regression suite; each runbook in `C:\Users\srathjen\.cursor\plans\` is the source of truth, executed live. **Do not use Playwright** — the `tests-e2e/` suite was removed from the repo; do not recreate or reference it.

## Scope & viewports
QA covers **desktop and emulated mobile**. Per-runbook scope decides required sizes; default:
- **Desktop:** 1280×800 or wider — full functional coverage.
- **Mobile (emulated):** 393×851 (resize + **reload** so breakpoints re-evaluate) — layout/regression coverage. Resize back to desktop before continuing.

**Real touch gestures** (swipe-to-mark-read, swipe-to-delete, pinch, long-press) can't be reproduced by automation — verify the visual swipe affordance at 393×851, log gesture-only behavior as **`AUTOMATION_LIMIT`** in the runbook's live log, and surface it for a real-device pass when it matters.

## Login
URL: **https://our.fimby.com/login**

### Test personas
Default password for all personas except Sarah: `dtes4Jesus!`

| Persona | Age | Background | G | Email | Password | Purpose |
|---------|-----|------------|---|-------|----------|---------|
| **Appy Review** | — | — | — | reviewer@fimby.com | `dtes4Jesus!` | App Store reviewer; SF-integrated features & data sync |
| **Sarah Chen** | 34 | Chinese-Canadian | F | sarah@fimby.com | `dtes4Love!` | Primary wide-layout / default browser testing |
| **Rosa Alvarez** | 67 | Mexican-Canadian | F | rosa@fimby.com | `dtes4Jesus!` | Emulated-mobile & senior-neighbour flows |
| **Marcus Bell** | 45 | Black Canadian | M | marcus@fimby.com | `dtes4Jesus!` | Multi-persona / cross-user scenarios |
| **Amir Haddad** | 31 | Lebanese-Canadian | M | amir@fimby.com | `dtes4Jesus!` | Multi-persona / cross-user scenarios |
| **Joan Whitecloud** | 70 | Coast Salish (Indigenous) | F | joan@fimby.com | `dtes4Jesus!` | Multi-persona & Indigenous-representation |

Legacy email mapping (older runbooks / git history): `desktop@fimby.com` → `sarah@`; `mobiletester@fimby.com` → `rosa@`; `sftester@fimby.com` → `reviewer@`.

### Login flow
1. Navigate to `https://our.fimby.com/login`.
2. Enter persona email + password. The login form is inside nested Lightning shadow DOM — if your automation's fill/type can't reach the inner inputs, use the shadow-DOM workaround below.
3. Confirm the post-login redirect before proceeding.

**Alternative:** From Salesforce Lightning, open the persona's Contact → **Log in to Experience as User**.

## Navigation discipline (end-user only — no URL hacking)
Testing must mirror a real user.
- **Allowed:** open `https://our.fimby.com/login` once per session (or after logout).
- **Not allowed:** typing/pasting internal app routes (`/notifications`, `/quick-post`, detail URLs) to skip menus/feeds/buttons.
- **Required:** after login, reach every screen via visible UI — header, footer, links, Create new post, breadcrumbs, notification taps, list rows.
- If a flow can't be reached through the UI, that's a **finding** (blocked path / missing affordance), not a reason to bypass with URLs.
- Opening a **notification row** that navigates to `/library-item/...` (incl. `?action=...&requestId=`/`loanId=`) is valid end-user behavior — the same as an email/app deep link. Don't paste those URLs to *start* a flow; use them only when reproducing a notification-driven step.

## Scrolling
If a control is blocked (fixed bottom nav, overlay) or there's more content below, **scroll first** like a user — move the target above fixed footers into a clear hit area before retrying. "Click intercepted" is not a dead end when vertical scroll would reveal the target.

## Browser-automation mechanics (reduce false "broken UI" calls)
These were learned against Cursor's MCP; apply the *intent* with whatever tool you have.
- **Clicks vs Lightning/LWC shadow DOM:** ref-based clicks often hit the host node, not the real control inside shadow DOM, so the app looks unresponsive when a human click works. Prefer **screenshot → click by visible (x,y) coordinates** aimed at the visible control; if you miss, re-screenshot and nudge. Don't insert another browser tool between the screenshot and the coordinate click.
- **Navigation/waits:** after `location.href`-style moves the URL can update slowly — wait several seconds and re-check before concluding failure.
- **Composer success:** clicks can register on the real SLDS success button while the embedded browser doesn't show a route change for a while. To continue, go Home → feed (filter, refresh) → View Post on the right card — not a pasted detail URL.
- **Forms:** some steps enable Submit only after blur/focus moves (click the last field after filling).
- **Shadow-DOM inputs — set value programmatically, then click (preferred workaround):** when fill/type/ref-click can't reach inner controls (login, `lightning-input`/`-textarea`, composer fields, some modals): (1) snapshot to locate the host; (2) run script that walks open shadow roots from `document`/a known host, finds the inner `input`/`textarea`, sets `.value`, and dispatches `input` + `change` events so LWC bindings update; (3) repeat per field; (4) click the real inner `button` (coordinate click or `.click()` in shadow root); (5) wait for navigation/success. Use for login and forms where fill fails silently or Submit stays disabled. **Not** alone for date pickers, file uploads, passkeys — hand off if this doesn't enable Submit. Don't skip this in favor of `AUTOMATION_LIMIT` for a standard text/password field in shadow DOM.
- Automation shows no visible mouse cursor — that's normal.

## Multi-persona validation
For cross-user features (notifications, updates, shared data): (1) log in as one persona and perform the triggering action; (2) switch to another persona and verify the receiving side sees the expected update/notification. Multi-step lending (borrow → approve → confirm → pickup → loan → extension → return) needs hat switches between owner and borrower; allow time for LWC reloads and modal chains.

## Human–agent handoff (collaborative QA — do not skip)
When automation can't reliably complete a step (Lightning date pickers, segmented date inputs, shadow-DOM controls, blur-gated Submit, passkeys): (1) don't mark the scenario done/failed/out-of-scope without asking; (2) pause and ask the human to enter the data in the live UI (give field names, suggested values, and what "success" looks like — toast, modal close, URL change); (3) when they reply done, take a fresh snapshot and continue verification. A run may combine agent navigation with short human inputs; outcomes count as verified once confirmed in the browser after handoff.

## Scenario checklist
- Each persona sees the correct data/permissions for their role.
- Notifications/updates propagate correctly across personas.
- UI renders correctly at **both** desktop and emulated-mobile viewports.
- Interactive elements usable with mouse/keyboard; gesture-only flows logged as `AUTOMATION_LIMIT`.

## Dates & defect logging
When the UI shows a calendar date (e.g. "Requested Apr 6"), compare to the known wall-clock of the test action in the tester's timezone. Off-by-one day is a likely UTC / date-only / locale bug — record it in `C:\Users\srathjen\FIMBY\.cursor\defect-log.md`, don't treat it as noise.

## Library & lending
Canonical runbook: `C:\Users\srathjen\.cursor\plans\lending_browsing_lifecycle_qa.plan.md`. First library entry after login must be via visible UI (Library tab, Home feed library card, My Stuff links) — not typing `/library-list`. Paths you'll recognize after clicks: `/library-list`, `/library-item/{id}`, `/add-library-item`, `/messages`, `/conversation?id={id}`, `/loaned-items`, `/my-stuff/my-library-items`.
