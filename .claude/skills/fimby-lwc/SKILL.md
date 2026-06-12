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
