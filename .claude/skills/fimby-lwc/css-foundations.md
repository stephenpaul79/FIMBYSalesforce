# FIMBY LWC — CSS Foundations

Load before editing `**/lwc/**/*.css`. FIMBY is served via WKWebView (Safari engine) on iOS — Safari handles CSS custom properties in shorthand more strictly than Chrome.

## Safari / WebKit
- **`background-color:` not `background:`** for solid-colour custom-property backgrounds — Safari can drop `background: var(--token)` entirely. Keep `background:` shorthand only for multiple sub-properties (gradients, image+position) or `!important` SLDS overrides.
- **`@property` registrations:** all `--fimby-*` colour tokens are registered via `@property` at the top of `fimby-tokens.css` (`syntax: '<color>'`, `initial-value` = fallback; needs Safari 16.4+). When adding a colour token: (1) add `@property` registration, (2) add `:root` light default, (3) add dark override in both `@media (prefers-color-scheme: dark)` and `:root[data-theme="dark"]`.
  ```css
  @property --fimby-my-new-token { syntax: '<color>'; inherits: true; initial-value: #F0EBE3; }
  ```
- **`-webkit-backdrop-filter`** always paired with `backdrop-filter`.
- **Inline hex fallbacks** on above-the-fold components (`fimbyUniversalHeader`, `fimbyHomeFeed`, `fimbyCard`, `fimbyBottomNavigation`): `background-color: var(--fimby-surface-card, #FAF7F2);`. New components don't need them if they use `background-color:` + a registered token.

## Brand tokens are mandatory
Every LWC uses `--fimby-*` from `FIMBY_Brand/fimby-tokens.css`. Never hardcode colours, shadows, radii.

| Purpose | Tokens |
|---------|--------|
| Backgrounds | `--fimby-surface-page`, `-card`, `-input` |
| Text | `--fimby-text-strong`, `-primary`, `-secondary`, `-muted` |
| Borders | `--fimby-border-subtle`, `-default`, `--fimby-divider-default` |
| Brand accent | `--fimby-brand-teal`, `-hover`, `--fimby-text-on-teal` |
| Interaction | `--fimby-hover-bg`, `-pressed-bg`, `-selected-bg` |
| Focus | `--fimby-focus-ring`, `-focus-glow` |
| Radii | `--fimby-radius-sm` (8) / `-md` (12) / `-lg` (16) / `-xl` (20) / `-full` |
| Shadows | `--fimby-shadow-card`, `-card-hover`, `-modal` |
| Status | `--fimby-success`/`-warning`/`-error`/`-info` + `-tint`/`-border` |
| Layout | `--fimby-header-height` (70), `-modal-inset-top` (86), `-bottom-nav-height` (70) |

## Button token system (`--fimby-btn-*`)
CTA buttons use `--fimby-btn-*` for WCAG AA fills. **Do not** use brand tokens (`--fimby-brand-teal`, `--fimby-success`, `--fimby-error`) for button backgrounds — those are for links, focus rings, tints, borders.

| Variant | Background | Contrast |
|---|---|---|
| Primary teal | `--fimby-btn-primary-bg` (#3A7D8C) → `-hover` | ~4.7:1 |
| Success green | `--fimby-btn-success-bg` (#1A7B40) → `-hover` | ~4.9:1 |
| Danger red | `--fimby-btn-danger-bg` (#C0392B) → `-hover` | ~5.4:1 |
| Info blue | `--fimby-btn-info-bg` (#0166BA) | ~5.4:1 |

Non-color: `--fimby-btn-shadow`, `-shadow-active`, `-border-bottom`, `-font-size` (0.9375rem), `-radius` (`var(--fimby-radius-md)` / 12px — rounded rectangle, **not** pill).

```css
.btn-primary {
    background-color: var(--fimby-btn-primary-bg);
    color: #ffffff; border: none;
    border-radius: var(--fimby-btn-radius);
    box-shadow: var(--fimby-btn-shadow), var(--fimby-btn-border-bottom);
    font-size: var(--fimby-btn-font-size); font-weight: 700;
    padding: 10px 20px; min-height: 44px; cursor: pointer;
    transition: background-color .15s, box-shadow .15s, transform .1s;
}
.btn-primary:hover  { background-color: var(--fimby-btn-primary-bg-hover); }
.btn-primary:active { background-color: var(--fimby-btn-primary-bg-active); box-shadow: var(--fimby-btn-shadow-active); transform: scale(.97); }
```

## Button vs badge shape hierarchy
Shape alone must distinguish actions from labels.

| Tier | Element | Shape | Radius | Required | Forbidden |
|------|---------|-------|--------|----------|-----------|
| 1 — Action Button | CTAs, page/modal/card/row/header actions | Rounded rectangle | `--fimby-btn-radius` (12px) | shadow, hover, active, `cursor:pointer`, `min-height:44px`, bold | — |
| 2 — Toggle Control | filter chips, segmented controls, radio/selection pills | Pill | `--fimby-radius-full` | grouped, clear selected state | looking like a standalone CTA |
| 3 — Decorative Badge | status/type/category/count labels | Pill, flat | `--fimby-badge-radius` | small text, compact padding, flat fill | shadow, hover, `cursor:pointer`, transition, `min-height:44px` |

**Never `border-radius: 9999px` on an action button.** Only Tier 2 toggle controls keep pill shape.

```css
.status-badge {
    display: inline-flex; align-items: center; gap: 4px;
    border-radius: var(--fimby-badge-radius);
    font-size: var(--fimby-badge-font-size); font-weight: var(--fimby-badge-font-weight);
    padding: var(--fimby-badge-padding); line-height: 1; white-space: nowrap;
    pointer-events: none; user-select: none;
}
```

## Button reset specificity
Place component-specific overrides **after** generic resets and use a compound selector to win the cascade:
```css
button.post-image-container { padding: 0; background: none; border: none; cursor: pointer; width: 100%; }
button.post-image-container.bulk-buy-image-container { padding: 16px; background: var(--fimby-surface-input, #f5f2ec); display: flex; align-items: center; justify-content: center; }
```

## Card surfaces & box shadow
Every card-level container uses `box-shadow: var(--fimby-shadow-card)`. Feed/detail cards → `--fimby-shadow-card`; hover → `-card-hover`; modals → `-modal`; inline → `-sm` or `-card`. Every `background: var(--fimby-surface-card)` element should also have a `box-shadow` unless it's a child of an already-shadowed parent. Sticky footers use shadow + radius, not flat strips; stacked sections use `border-top` dividers.

## Light/dark mode
Tokens swap in `fimby-tokens.css` via `:root` (light), `@media (prefers-color-scheme: dark)` on `:root:not([data-theme="light"])`, and `:root[data-theme="dark"]`. **Do not** add `@media (prefers-color-scheme)` in component CSS. Dark-only overrides:
```css
:host-context([data-theme="dark"]) .my-element,
:host-context(:root:not([data-theme="light"])) .my-element { /* override */ }
```

## Mobile-first responsive
Base ≤480px, then `min-width` breakpoints: 480 (large phones), 768 (tablet/small desktop — two-column), 1024 (desktop — multi-column, max-width).
```css
:host { display: block; background-color: var(--fimby-surface-page); }
.page-container { width: 100%; padding: 0 16px; box-sizing: border-box; }
@media (min-width: 768px)  { .page-container { padding: 0 24px; } }
@media (min-width: 1024px) { .page-container { max-width: 800px; margin: 0 auto; padding: 0 32px; } }

.card-grid { display: grid; grid-template-columns: 1fr; gap: 16px; }
@media (min-width: 768px)  { .card-grid { grid-template-columns: repeat(2,1fr); gap: 20px; } }
@media (min-width: 1024px) { .card-grid { grid-template-columns: repeat(3,1fr); gap: 24px; } }
```

## `:host` background on page-level components
Every page-level LWC sets `display: block` + `background` on `:host` (else the EC theme background bleeds at the sides). The site-wide `fimby-tokens.css` overrides the EC section overlay:
```css
:root { --dxp-c-section-image-overlay-color: transparent; --dxp-c-section-background-color: var(--fimby-surface-page); }
html, body { background: var(--fimby-surface-page) !important; }
```
`background` shorthand is required here because SLDS ships `html { background: #eef4ff }`. **Never change these overrides** without checking page backgrounds. The Experience Builder stylesheet `digitalExperiences/site/FIMBY1/sfdc_cms__styles/styles_css/styles.css` must never set `html { background: white }` — keep it aligned with token overrides.

```css
:host { display: block; background-color: var(--fimby-surface-page); }  /* always the first rule */
.my-page { background-color: var(--fimby-surface-page); }
```
No `min-height`/`max-width`/`padding` on `:host`. Surface mapping: inner wrapper `--fimby-surface-page` → `:host` same (default); `-surface-section`/`-input` → match; gradient → solid fallback.

## Page layout conventions
- **Standard desktop width 800px:** `max-width: 800px; margin: 0 auto;` at `@media (min-width: 1024px)` on the **outer wrapper**. Width tiers: Standard 600/800 (feeds, detail, lists, search); Narrow 640 all viewports (settings, profile, composer, forms); Very narrow 400–500 (registration, signup).
- **Header-body width matching:** never set `max-width` on `c-fimby-page-header` independently — set it on the outer wrapper containing both.
- **Container padding, not child margins:** horizontal padding on the outer wrapper (mobile `0 16px <bottom>`, 768px+ `0 24px <bottom>`); `<bottom>` typically `80px`, reduced to `24px` at ≥892px. `box-sizing: border-box`; children use only vertical margins.
- `fimbyPageHeader` has built-in `margin-bottom: 12px` — don't add extra.

```css
:host { display: block; background-color: var(--fimby-surface-page); }
.my-page {
    min-height: calc(100vh - var(--fimby-header-height, 78px));
    min-height: calc(100dvh - var(--fimby-header-height, 78px));
    background-color: var(--fimby-surface-page);
    padding: 0 16px 80px; box-sizing: border-box;
}
@media (min-width: 768px)  { .my-page { padding: 0 24px 80px; } }
@media (min-width: 892px)  { .my-page { padding-bottom: 24px; } }
@media (min-width: 1024px) { .my-page { max-width: 800px; margin: 0 auto; } }
```
Narrow form pages: same, plus `max-width: 640px; margin: 0 auto;`.

## Modal positioning (desktop)
`fimbyUniversalHeader` is sticky at `--fimby-header-height: 70px`. Modals use `position: fixed`, z-index 9999+, and must **not** vertically center in the full viewport. Layout tokens: `--fimby-header-height: 70px`, `--fimby-modal-top-gap: 16px`, `--fimby-modal-inset-top: calc(var(--fimby-header-height) + var(--fimby-modal-top-gap))` (86px). Layout tokens don't need `@property`.

```css
.modal-backdrop { position: fixed; top: var(--fimby-modal-inset-top, 86px); left: 0; right: 0; bottom: 0; display: flex; align-items: center; justify-content: center; padding: 16px; z-index: 9999; }
.modal-container { max-height: calc(100dvh - var(--fimby-modal-inset-top, 86px) - 32px); }
```
Full-viewport scrim variant (delete/cancel, SLDS sections): `padding: var(--fimby-modal-inset-top, 86px) 24px 24px;` + flex center. Mobile bottom sheets (≤480px): reset `top: 0`, `align-items: flex-end`, `padding-top: var(--fimby-header-height, 70px)` when it must not cover the header. **Anti-patterns:** `inset: 0` + `align-items: center` without `--fimby-modal-inset-top`; `top: 50%; transform: translate(-50%,-50%)`; SLDS `.slds-modal` without `padding-top: var(--fimby-modal-inset-top)`.

## Full-viewport height
```css
.my-full-page {
    height: calc(100vh - var(--fimby-header-height,78px) - var(--fimby-bottom-nav-height,70px));
    height: calc(100dvh - var(--fimby-header-height,78px) - var(--fimby-bottom-nav-height,70px));
    display: flex; flex-direction: column; overflow: hidden;
}
@media (min-width: 892px) {
    .my-full-page { height: calc(100vh - var(--fimby-header-height,78px)); height: calc(100dvh - var(--fimby-header-height,78px)); }
}
```
Always use `100dvh` as progressive enhancement; `overflow: hidden` on outer, inner scroll region scrolls.

## Rounded corners
Every distinct section uses `--fimby-radius-md` (12px) or `-lg` (16px). `overflow: hidden` when children might bleed. Stacked sections → single rounded parent. No square corners unless intentionally full-bleed at ≤320px.

## Native date / datetime-local inputs
`lightning-input` doesn't support `type="datetime-local"` — use native `<input type="datetime-local">`. For date-only fields where `lightning-input type="date"` mis-aligns on iOS, use `<input type="date">`. Native inputs are **not** styled by SLDS automatically; DXP block-spacing tokens resolve to `0` outside shadow DOM, so explicit padding/min-height is required.

```css
.date-input, .datetime-input {
    -webkit-appearance: none; appearance: none;
    width: 100%; min-width: 0; max-width: 100%; margin: 0;
    padding: 3px 12px 2px; min-height: 1.75rem;
    font-size: var(--dxp-c-input-text-font-size, var(--dxp-s-form-element-text-font-size, var(--dxp-s-body-font-size, .875rem)));
    line-height: 1.5;
    font-family: var(--dxp-s-form-element-text-font-family, var(--dxp-s-body-font-family, inherit));
    background-color: var(--dxp-s-form-element-color-background, var(--dxp-g-root));
    color: var(--dxp-s-form-element-text-color, var(--dxp-g-root-contrast));
    border: var(--dxp-s-form-element-width-border, 1px) solid var(--dxp-s-form-element-color-border, var(--dxp-g-neutral-3));
    border-radius: var(--dxp-s-form-element-radius-border, 4px);
    box-shadow: var(--dxp-s-form-element-shadow);
    box-sizing: border-box; text-align: left; transition: border-color .2s;
}
.date-input::-webkit-date-and-time-value, .datetime-input::-webkit-date-and-time-value { text-align: left; }
.date-input:focus, .datetime-input:focus {
    outline: none;
    background-color: var(--dxp-s-form-element-color-background-active, var(--dxp-s-form-element-color-background, var(--dxp-g-root)));
    border-color: var(--dxp-s-form-element-color-border-focus, var(--dxp-g-brand));
    box-shadow: var(--dxp-s-form-element-shadow-focus, 0 0 3px var(--dxp-g-brand-1));
}
```
Why: `-webkit-appearance: none` strips iOS chrome; explicit asymmetric padding (DXP tokens = 0 outside shadow DOM); `min-height` prevents iOS collapse; `::-webkit-date-and-time-value` is the only way to left-align on iOS; DXP `--dxp-s-form-element-color-*` tokens keep it in sync with the EC theme (incl. dark). **Pitfalls:** don't use `--fimby-surface-input`/`-border-default` (different colours → mismatch); don't put `overflow: hidden` on a parent containing date inputs (clips the right border on mobile); never omit `min-height`.

## Desktop optimisations
Cap content to 800/640px; horizontal card/form layouts above 768px; put conflicting `:hover`/`:focus-visible` inside `@media (hover: hover)`; `scrollbar-width: thin` for desktop scroll areas.
