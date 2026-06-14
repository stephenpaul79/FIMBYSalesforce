---
name: fimby-lwc
description: FIMBY Lightning Web Component conventions — reusable primitives, header menuItems API, image URL resolution, event-type config, quick-response modal, character counters, persona-first detail pages. Load before editing any file under **/lwc/** in the FIMBY repo. Pulls in reference docs for CSS foundations, UI/UX patterns, the Impact Icon index, mobile gesture pitfalls, and a pre-deploy checklist.
---

# FIMBY LWC Patterns

Read this before writing or changing any LWC. All components are prefixed `fimby*` and support dual-mode (page vs modal via `isModalMode`). Design philosophy and identity/banner rules are in CLAUDE.md §5. Reference files extend this skill — open the relevant one before you write:

- **[css-foundations.md](css-foundations.md)** — Safari/WebKit compat, `--fimby-*` tokens, button/badge shape hierarchy, light/dark, responsive layout, modal positioning, native date inputs. Load before editing `**/lwc/**/*.css`.
- **[ui-patterns.md](ui-patterns.md)** — accessibility (WCAG), forms, navigation, persona-first detail pages, event-type UX, mobile-native patterns. Load for UX/markup decisions.
- **[component-patterns.md](component-patterns.md)** — card type badges, pill action buttons, accessibility guardrails, multi-page form navigation, character-counter label rows, bold labels. Load before editing `**/lwc/**/*.html` or `*.css`.
- **[icons-resources.md](icons-resources.md)** — full Impact Icon index, import patterns, utility-vs-Impact rules, Custom Property Editor guidance. Load before editing `**/lwc/**/*.js`.
- **[mobile-gestures.md](mobile-gestures.md)** — swipe/menu touch-handler pitfalls. Load when touching gesture or dropdown code.
- **[checklist.md](checklist.md)** — review against this before finishing/deploying any LWC change.

## Reusable Primitives — build on these first
| Component | Purpose |
|-----------|---------|
| `fimbyCard` | Universal feed card — images, tags, social actions, Read More/Less, desktop horizontal layout |
| `fimbyInfiniteScroll` | Paginated lists, pull-to-refresh, empty/error/end states |
| `fimbyResponsiveList` | Table ↔ card responsive (768px) with sort + search |
| `fimbyImageUploader` | Client-side compression (1200px max, JPEG 0.8), tap + drag-drop |
| `fimbyRecordEditModal` / `fimbyRecordDetailCard` | Dynamic record forms via field sets |
| `fimbyLoadingMessage` | Rotating messages from `FIMBY_Loading_Message__mdt` |
| `fimbyCelebration` | Emoji confetti + GIFs, occasion-scaled, reduced-motion aware |
| `fimbyPageHeader` | Breadcrumb + `menuItems` three-tier actions + search + notifications |
| `fimbyUniversalHeader` / `fimbyBottomNavigation` | Site nav: 4 tabs + Create + identity switcher + acting-as chip |
| `fimbyManageIdentities`, `fimbyRelationshipSetupModal`, `fimbyOrganizationProfile` | Identity/relationship/org UIs |

## Navigation — soft nav only (no `location.href`, no internal `<a href>`)
FIMBY is a persistent-shell SPA on LWR. **All in-app navigation MUST be client-side (soft) navigation** so the header/footer shell stays mounted and only the content region swaps. A full reload remounts the shell and causes the empty → spinner → content flash we are eliminating. Route every in-app navigation through `c/fimbyNavigation`:

```javascript
import { NavigationMixin } from 'lightning/navigation';
import { navigate, navigateToRoute } from 'c/fimbyNavigation';

export default class FimbyThing extends NavigationMixin(LightningElement) {
    goToItem(id)  { navigate(this, `/asks-offers/${id}`); }      // any internal path
    goToConvo(id) { navigate(this, `/conversation?id=${id}`); }   // query → state preserved
    goToTab()     { navigateToRoute(this, 'library'); }           // known route key
}
```
- `navigate(this, url)` resolves any internal path: record-detail (`/asks-offers|sharedlife|story|library-item|skill-offer/{id}`) → `standard__recordPage`; custom routes with query (`/conversation`, `/neighbour`, `/response-reply`, `/search`, `/organization-profile`, `/moderator-task`, …) → `comm__namedPage` + `state`; named pages (`/messages`, `/settings`, `/my-stuff/*`) → `comm__namedPage`. Unknown paths fall back to a hard load — it never breaks.
- `navigateToRoute(this, key, opts)` for logical route keys (e.g. tab handlers: `navigateToRoute(this, selectedTab)`).
- Component **must** `extend NavigationMixin(LightningElement)`, or the helper degrades to a hard load.

**FORBIDDEN for in-app nav:** ❌ `location.href = '/...'`, `window.location.href = '/...'`, `location.assign('/...')`; ❌ internal anchors `<a href="/messages">`. For internal links in markup use `<button onclick={…}>` → `navigate(this, …)`, or `<a href={url} onclick={handleNav}>` with `event.preventDefault()` then `navigate(this, url)`.

**ALLOWED hard nav** (`navigate()` passes these through): external (`http(s):`, `mailto:`, `tel:`, `sms:`), auth/session (`/secur/logout.jsp`, login), and deliberate full-reset reloads at a flow boundary (`window.location.replace('/onboarding')` post-signup, `'/'` after onboarding). Reading `window.location` (e.g. `new URL(window.location.href)` for a record id) is not navigation — fine.

## Loading choreography — smooth, fully-formed reveals (no chunky pop-in)
Hide intermediate loading states; reveal each surface fully formed, once, with a gentle fade. Four codified patterns:
1. **Hide-until-loaded reveal (detail pages):** gate the entire body behind a single `_detailReady` flag set only when **all** critical layout-defining loads resolve (call `_maybeMarkReady()` from each load's success **and** error). Spinner until ready, then render + `detailFadeIn` 220ms opacity fade; reduced-motion disables it. Refs: `fimbyNeedOfferDetail`, `fimbyStoryDetail`, `fimbyLibraryItemDetail`, `fimbySkillOfferDetail`. Never reveal sections incrementally.
2. **Feed curtain (lists):** use `fimbyInfiniteScroll` for every feed (Home, Notifications, Messages, Library) — it lays content out at `opacity:0` behind a curtain and reveals in one fade (≥350ms min, reserves `--fimby-feed-curtain-min-height`). Don't roll your own list shell.
3. **Image fade-in:** user images start `opacity:0` → `1` on `load`; `renderedCallback` sweep marks already-`complete` (cached) images loaded so they don't flash; reduced-motion instant. Ref: `fimbyImageGrid`.
4. **Silent scroll restore:** on cached back-restore, hold the list invisible from first paint, `scrollTo` while hidden (nested rAF), then fade in at position. Flush cached scroll state in `disconnectedCallback` (soft nav doesn't fire `pagehide`). Refs: `fimbyHomeFeed`, `fimbyLibraryBrowser`.

## Conditional templates
Use `lwc:if` / `lwc:elseif` / `lwc:else` — **never** the deprecated `if:true` / `if:false` (removed at API 58.0). For `!condition`, add an inverse getter in JS.

## Header `menuItems` API (three-tier)
`fimbyPageHeader` accepts `menu-items`, emits `menuaction`. Each item declares `display`:
- **`inline`** — always-visible button (primary CTAs: Compose, Set Up).
- **`responsive`** — button on desktop (≥768px), kebab on mobile (management: Edit, Photo, Delete).
- **`kebab`** — always in dropdown (safety: Flag, Block).

Item shape: `{ key, label, icon, display, variant }`. `icon` = `Impact_Icons` filename (`'edit.png'`). `variant`: `'primary'` (teal) or `'danger'`. Header action buttons are **Tier 1 (rounded rectangle)** — never pill (`9999px`).

```javascript
get headerMenuItems() {
    if (this.isPosterPersona) {
        return [
            { key: 'edit', label: 'Edit', icon: 'edit.png', display: 'responsive' },
            { key: 'photo', label: 'Photo', icon: 'photo.png', display: 'responsive' },
            { key: 'delete', label: 'Delete', icon: 'trash.png', display: 'responsive', variant: 'danger' }
        ];
    }
    return [{ key: 'flag', label: 'Report', icon: 'warning.png', display: 'kebab' }];
}
handleHeaderMenuAction(event) {
    const actions = { edit: () => this.handleEdit(), photo: () => this.handleUploadPhoto(),
                      delete: () => this.handleDeleteClick(), flag: () => this.handleFlag() };
    actions[event.detail.key]?.();
}
```
**Never** use `slot="actions"`, `showCustomAction`, or `showMenu` (deprecated). All header actions via `menuItems`; always use `c-fimby-page-header` — never custom header markup.

## Image URL resolution (Org ID suffix)
CMS images need the Org ID suffix. Every LWC showing user-uploaded images:
1. `import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';`
2. `this._organizationId = await getOrganizationId();` in `connectedCallback` (cacheable).
3. ```javascript
   _completeImageUrl(url) {
       if (!url) return '';
       if (this._organizationId && !url.includes(this._organizationId)) return url + this._organizationId;
       return url;
   }
   ```
Apply to all Apex/record image URLs. **Not** to static resources (`IMPACT_ICONS`, `MEMES*`, `FIMBY_Brand`).

## Event-type config (CONFIG-driven getters)
`fimbyNeedOfferDetail` uses `EVENT_TYPE_CONFIG` keyed by `Event_Type__c` (`Gathering`, `Open_Event`, `Community_Event`). All event getters resolve via `this.eventTypeConfig.property` — when adding event behaviour, **add a property to the config**, never ad-hoc if/else. Flags: `usesCapacity`, `usesQuickResponse`, `usesResponseThreads`, `usesOnDemandEventChat`, `usesAttendeeList`, `showMessagePoster`, `showGuestStepper`, `showModeration`, `showEventLink`. **Critical:** `usesCapacity` is `true` only for Gathering — gate all capacity logic behind `isGathering`; Open/Community Events must never enter exhaustion paths.

## Quick-Response Modal (`fimbyQuickResponseModal`)
All feed response interactions use this single reusable modal with type-switching variants. **Do not** navigate to deprecated `/respond`, `/reserve-share`, `/borrow-item`. Community Event = inline 1-click (no modal); Open Event = modal w/ guest stepper from feed, inline from detail; Gathering/Ask/Offer/Bulk Buy/Library = form modal; Story = comment modal (feed) or `fimbyCommentComposer` (detail). After close/inline action, cards/detail update in-place (no reload, scroll preserved).

## User feedback — toasts & inline banners (NO `ShowToastEvent`)
`ShowToastEvent` / `lightning/platformShowToastEvent` **does not render** in our LWR Experience Cloud site — it silently no-ops. Never import or dispatch it. Two mechanisms, each with one job:

| Outcome | Mechanism | Why |
|---------|-----------|-----|
| **Operation failure** (server/FLS/network: "Couldn't save — try again") | **`fireToast` / `fireErrorToast`** from `c/fimbyToastHelper` → shell-mounted `c-fimby-toast` | Must interrupt and be seen regardless of scroll. Global, assertive, auto-dismiss. |
| **In-form validation** ("Name is required", "Pick a date") | **`c-fimby-inline-banner`** `variant="error"`, next to the field | Validation belongs in context. Toasting it is an anti-pattern. |
| **Success** | **`c-fimby-inline-banner`** `variant="success"` if the user **stays**; **nothing** if the action navigates away / removes the item from a list | Success is contextual and quiet. The surface change is its own confirmation. |

```javascript
import { fireToast, fireErrorToast } from 'c/fimbyToastHelper';
// operation failure:
catch (error) { fireErrorToast(error); }            // pulls AuraHandledException message
// or explicit: fireToast({ message: 'Couldn’t reach the server.', variant: 'error' });
```
```html
<!-- success kept on-page -->
<c-fimby-inline-banner variant="success" message={successMessage}></c-fimby-inline-banner>
<!-- in-form validation -->
<c-fimby-inline-banner variant="error" message={fieldError}></c-fimby-inline-banner>
```
- `c-fimby-toast` is mounted **once** in the shell (`fimbyUniversalHeader`) so it survives soft nav — don't add it per page. `fireToast` variants: `error` (default) / `warning` / `info` (no `success` — success is never a toast).
- `c-fimby-inline-banner` handles `role`/`aria-live` itself (error/warning = `alert`/assertive, success/info = `status`/polite) and renders nothing when `message` is empty. Icon + text always (colour never the sole signal).
- **Don't** hand-roll `errorMessage`/`_error`/`this.error` banner markup — route through `c-fimby-inline-banner` for uniform roles/styling. Reference implementation: `fimbyModeratorTaskPage` (success banner + toast on failure) and `fimbyModeratorDashboard` (toast on failure, no success banner because actions clear the task from the queue).

## Confetti — DOM-based only
Use `fireEmojiConfetti({ emojis, style, intensity })` from `fimbyConfettiHelper` (pure-DOM `element.animate()`). **Do not** import `loadScript(CONFETTI)`, `buildEmojiShapes`, or canvas confetti — deprecated (WebView emoji failures). The `Confetti` static resource is rollback insurance only.

## Character-limited text fields
1. `maxlength` matches the Salesforce field length **exactly** — never higher.
2. Always show a counter in `.field-label-row`: `<span class={countClass}>{length}/{max}</span>`.
3. Dynamic colour via getter (red **at** limit `>=`, not above):
   ```javascript
   get fieldCountClass() {
       const len = this.fieldValue.length;
       if (len >= MAX) return 'character-count at-limit';
       if (len >= Math.floor(MAX * 0.9)) return 'character-count near-limit';
       return 'character-count';
   }
   ```
4. CSS `.near-limit` (`--fimby-warning`) / `.at-limit` (`--fimby-error`). Match existing base class (`character-count` or `char-count`).
5. Hard limits — `maxlength` enforces the cap, don't allow overage + block submit.
6. Prefer native `<input>`/`<textarea>` over `lightning-input`/`lightning-textarea` in modals/compact forms (Lightning reserves padding for unused help/error slots).

## Persona-first detail pages
Three client-side persona getters: `isPosterPersona`, `isResponderPersona`, `isRespondedPersona` (no new Apex). Single-column at all viewports. Poster actions via `headerMenuItems` (`responsive`); viewer safety via `headerMenuItems` (`kebab`). Reference: `fimbyNeedOfferDetail`, `fimbyBulkBuyDetailBody`. Full UX detail in [ui-patterns.md](ui-patterns.md).

## Collapsible sections
Tracked boolean + chevron `<button>` + `slideDown` CSS. Mobile: collapsed; desktop: expanded (`window.matchMedia('(min-width: 768px)')` in `connectedCallback`). Respect `prefers-reduced-motion`. Inline per consumer — no shared component.

## Onboarding
- **Signup** (pre-account): `FIMBY_Public_Signup_Page` flow at `/sign-up`; standard self-register at `/register`. No LWC.
- **Profile setup** (`fimbyOnboardingPage` at `/onboarding`): Phase 1 — name required; photo/about/care/vouch optional.
- **Walkthrough**: Phase 2, content in `fimbyWalkthroughContent.js`; dismissible per-session or permanently.

## After LWC edits
Deploy per CLAUDE.md §6 (targeted `--source-dir` on the bundle folder, no `--tests` for LWC-only, then `sf community publish`) — only after approval. Flag any new pages/routes for Experience Builder setup.
