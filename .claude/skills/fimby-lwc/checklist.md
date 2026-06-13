# FIMBY LWC Quick Checklist

Review before finishing or deploying any LWC change. Consider each item if it affects your change.

## Navigation & loading
- [ ] In-app navigation uses `navigate(this, url)` / `navigateToRoute(this, key)` from `c/fimbyNavigation` — never `location.href`/`window.location.href`/`location.assign` to an internal path, and no internal `<a href="/...">`. Component extends `NavigationMixin(LightningElement)`. (External links, `/secur/` auth, and deliberate `location.replace` flow-resets stay hard nav.)
- [ ] Detail pages reveal fully-formed: single `_detailReady` gate over all critical loads + `detailFadeIn`; no incremental section pop-in. Reduced-motion disables the fade.
- [ ] Feeds use `fimbyInfiniteScroll` (curtain reveal); user images fade in on load (cached sweep); cached back-restore hides the scroll jump.

## Templates & structure
- [ ] Conditional templates use `lwc:if`/`lwc:elseif`/`lwc:else` — never deprecated `if:true`/`if:false`. For `!condition`, add an inverse getter.
- [ ] All pages use `c-fimby-page-header` — never a custom header `<div>` with back buttons.
- [ ] Detail page actions use `fimbyPageHeader`'s `menuItems` API — never body-level pills or custom header markup.
- [ ] `menuItems` three-tier: `inline` (primary CTAs), `responsive` (management), `kebab` (safety).
- [ ] Never `slot="actions"`, `showCustomAction`, or `showMenu` (deprecated).

## Layout
- [ ] Page-level components use `var(--fimby-surface-page)` for both `:host` and outer wrapper.
- [ ] `min-height` uses `calc(100vh - var(--fimby-header-height,78px))` + `calc(100dvh - …)` — never bare `100vh`.
- [ ] Bottom padding `80px` reduced to `24px` at `@media (min-width: 892px)`.
- [ ] Desktop `max-width: 800px` at `@media (min-width: 1024px)` (standard) or `640px` (narrow forms).
- [ ] Horizontal spacing via `padding` on outer wrapper — never `margin` on child cards/sections.
- [ ] Outer wrapper uses `box-sizing: border-box`.
- [ ] Page header and body share width — no independent `max-width` on `c-fimby-page-header`.
- [ ] Full-viewport components subtract header + bottom-nav on mobile, header-only on desktop (≥892px).
- [ ] Desktop modal backdrop uses `--fimby-modal-inset-top` (not bare `inset: 0` centering).

## Icons
- [ ] Brand/nav/content icons from `Impact_Icons`; `lightning-icon` only for generic UI (arrows, close, chevrons).
- [ ] `utility:image` / `utility:delete` never used — `photo.png` / `trash.png` instead.
- [ ] `utility:edit` only for subtle inline pencils; pill buttons use `edit.png`.
- [ ] Impact Icons on primary (teal) buttons render naturally — no `filter: brightness(0) invert(1)`.

## Buttons & shapes
- [ ] Icon+label action buttons use pill shape (`9999px`) with `<img>` icons (body-level CTAs).
- [ ] Header action buttons are Tier 1 rounded rectangle — never pill.
- [ ] Primary button text uses `color: #ffffff`, not `var(--fimby-text-on-teal)`.
- [ ] Button resets don't override component styles — compound selectors after resets.

## CSS / Safari
- [ ] Every `background: var(--fimby-surface-card)` also has `box-shadow: var(--fimby-shadow-card)` (unless nested).
- [ ] Sticky footers use shadow + radius — not flat strips.
- [ ] Solid-colour backgrounds use `background-color:` not `background:` (Safari).
- [ ] `backdrop-filter` paired with `-webkit-backdrop-filter`.
- [ ] New colour tokens have `@property` registration in `fimby-tokens.css`.
- [ ] Zero hardcoded colours — all `var(--fimby-*)`.
- [ ] Rounded corners on all cards, headers, panels, containers.
- [ ] Base styles work at 320px; desktop via `min-width` queries.

## Accessibility
- [ ] Tap targets ≥ 44px.
- [ ] `prefers-reduced-motion` respected.
- [ ] Focus ring visible via `--fimby-focus-ring`.
- [ ] Every `<img>` has `alt`; icon-only buttons have `aria-label`.
- [ ] No clickable `<div>`/`<span>` — semantic `<button>`/`<a>`.
- [ ] `onclick` on non-buttons paired with `onkeydown` (Enter/Space).
- [ ] Heading hierarchy sequential — no skipped levels.
- [ ] Colour never the sole state indicator — paired with icon/text.
- [ ] Form inputs have visible labels; errors linked via `aria-describedby`.

## Forms
- [ ] Multi-page forms use `.form-navigation` footer — "< Back" left, primary CTA right.
- [ ] Form nav uses custom `nav-btn` — never `lightning-button`.
- [ ] "Next" has `utility:chevronright`; final submit has no icon.
- [ ] Both "Next" and Submit use `.nav-next` (teal, `#ffffff`); "Back" uses `.nav-back` (neutral).
- [ ] Character counters: `maxlength` matches the field length exactly, counter turns red at the limit (`>=`).

## User feedback (toasts & banners)
- [ ] **Never** `ShowToastEvent` / `lightning/platformShowToastEvent` — it silently no-ops in our LWR site. Removed from any file you touch.
- [ ] Operation failures (server/FLS/network: "Couldn't save") → `fireToast`/`fireErrorToast` from `c/fimbyToastHelper` (shell-mounted `c-fimby-toast`, assertive/global).
- [ ] In-form validation errors ("Name is required", "Pick a date") → inline next to the action via `c-fimby-inline-banner variant="error"` — **not** a toast.
- [ ] Success → `c-fimby-inline-banner variant="success"` only when the user stays on the surface; **nothing** when the action navigates away or removes the item from a list (the surface change is the confirmation).
- [ ] No bespoke `errorMessage`/`_error`/`this.error` banner markup — render through `c-fimby-inline-banner` so roles/`aria-live`/styling are uniform.

## Experience Builder
- [ ] If exposing `<property>` entries: flag enum fields, icon refs, or 5+ props for a CPE.
