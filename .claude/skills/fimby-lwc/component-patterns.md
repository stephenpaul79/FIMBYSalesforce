# FIMBY Component Patterns (HTML/CSS)

Card badges, pill action buttons, accessibility guardrails, multi-page form navigation, character counters, form labels. After LWC/metadata edits, deploy per CLAUDE.md §6 (after approval).

## Card type badge colours (pill badges)
Every feed card shows a type badge (pill) top-right. Primary badges = white text on `--fimby-badge-*` backgrounds; secondary (Reserved, Available) may use tint if WCAG contrast holds.

| Badge | Token | Class | Icon |
|-------|-------|-------|------|
| Story | `--fimby-badge-story` | `.story-badge` | `StoriesActive.png` |
| God Story | `--fimby-badge-god-story` | `.godstory-badge` | `GodStoryActive.png` |
| Thank You | `--fimby-badge-thank-you` | `.thankyou-badge` | `ThankYouActive.png` |
| Lament | `--fimby-badge-lament` | `.lament-badge` | `LamentActive.png` |
| Prayer | `--fimby-badge-prayer` | `.prayer-badge` | `PrayActive.png` |
| Bio | `--fimby-badge-bio` | `.bio-badge` | `BioActive.png` |
| Ask & Offer | `--fimby-badge-ask-offer` | `.ask-offer-badge` | `BulletinBoardActive.png` |
| Event | `--fimby-badge-event` | `.event-badge` | `plannersm.png` |
| Library | per-category inline style | per-category | per-category (see icons-resources.md) |

Library badges use per-category icons/colors from `c/fimbyLibraryCategoryConfig` (`getCategoryIconUrl`, `getCategoryStyle`, `CATEGORY_COLORS`) on library pages; the **home feed** keeps one generic "Library" badge.

```css
.type-badge {
    display: inline-flex; align-items: center; gap: 5px;
    padding: var(--fimby-badge-padding, 2px 10px);
    border-radius: var(--fimby-badge-radius, 9999px);
    font-size: var(--fimby-badge-font-size, .75rem);
    font-weight: var(--fimby-badge-font-weight, 600);
    text-transform: uppercase; letter-spacing: .03em; color: #fff;
    -webkit-backdrop-filter: blur(4px); backdrop-filter: blur(4px);
}
.badge-icon { width: 18px; height: 18px; object-fit: contain; }
.story-badge { background-color: var(--fimby-badge-story); }
```
Badge label = content type, never status. Always icon + label. ≤480px: padding `3px 8px`, font `0.65rem`.

## Pill action buttons (icon + label)
Body-level CTAs pairing an Impact Icon with text use pill shape (`border-radius: 9999px`). Header actions (Edit, Photo, Delete, Flag, Block) belong in `fimbyPageHeader` via `menuItems` — body pills are for primary CTAs (Borrow, Respond, Message).

```html
<button class="action-btn" onclick={handleEdit}>
    <img src={editIconUrl} alt="" class="action-btn-icon"><span>Edit</span>
</button>
<button class="action-btn danger" onclick={handleDeleteClick}>
    <img src={trashIconUrl} alt="" class="action-btn-icon"><span>Delete</span>
</button>
```
```css
.action-btn {
    display: inline-flex; align-items: center; gap: 6px; padding: 8px 16px;
    background-color: var(--fimby-surface-card); border: 1px solid var(--fimby-border-default);
    border-radius: 9999px; cursor: pointer; font-size: .85rem; font-weight: 500;
    color: var(--fimby-text-secondary); min-height: 44px; transition: all .2s ease;
}
.action-btn:hover { background-color: var(--fimby-hover-bg); border-color: var(--fimby-border-strong); }
.action-btn-icon { width: 18px; height: 18px; object-fit: contain; flex-shrink: 0; }
.action-btn.primary { background-color: var(--fimby-btn-primary-bg); color: #fff; border-color: var(--fimby-btn-primary-bg); font-weight: 700; }
.action-btn.danger:hover { background-color: var(--fimby-error-tint); }
```
Rules: pill shape mandatory for icon+label buttons; always `<img>` Impact Icons for edit/photo/delete; **do NOT apply `filter: brightness(0) invert(1)`** to Impact Icons on primary buttons (multi-colour artwork); primary text `color: #ffffff` (not `var(--fimby-text-on-teal)`); ≥44px tap target.

## Accessibility guardrails
- Every `<img>` has `alt` (decorative: `alt=""`); icon-only buttons have `aria-label` / visually-hidden text.
  ```html
  <button class="icon-btn" aria-label="Close modal" onclick={handleClose}><img src={closeIcon} alt=""></button>
  ```
- `<button>` for actions, `<a>` for navigation — never clickable `<div>`/`<span>`. If a custom element must act as a button: `role="button"` + `tabindex="0"`.
- Every `onclick` on a non-button needs matching `onkeydown` (Enter/Space). Modals trap focus + return on close.
- Focus visibility: `:focus-visible` using `--fimby-focus-ring`; never `outline: none` without alternative.
  ```css
  .interactive:focus-visible { outline: 2px solid var(--fimby-focus-ring); outline-offset: 2px; box-shadow: 0 0 0 4px var(--fimby-focus-glow); }
  ```
- Colour & contrast: `--fimby-*` tokens (AA pre-validated); never colour as sole state indicator; warn on hardcoded colours.
- Headings: sequential, no skipped levels; one `<h1>` per page; landmark regions where appropriate.
- Forms: every input has a visible `<label>` or `aria-label` (placeholder ≠ label); errors via `aria-describedby`; group related fields with `<fieldset>`+`<legend>`.
- Motion: `@media (prefers-reduced-motion: reduce) { .animated-element { transition: none; animation: none; } }`

## Multi-page form navigation
`.form-navigation` footer on every page: "< Back" bottom-left (neutral outlined), primary bottom-right (teal).

| Position | Element | Style | Icon |
|---|---|---|---|
| Left | "< Back" | neutral outlined | left chevron before label |
| Right (intermediate) | "Next >" | teal fill | right chevron after label |
| Right (final) | submit | teal fill | **no icon** |

```html
<div class="form-navigation">
    <button class="nav-btn nav-back" onclick={handleBack} type="button" aria-label="Go back">
        <lightning-icon icon-name="utility:chevronleft" size="xx-small"></lightning-icon><span>Back</span>
    </button>
    <button class="nav-btn nav-next" onclick={handleNext} disabled={isNextDisabled} type="button">
        <span>Next</span><lightning-icon icon-name="utility:chevronright" size="xx-small"></lightning-icon>
    </button>
</div>
<!-- final page: nav-next calls handleSubmit, label {submitLabel}, NO chevron -->
```
```css
.form-navigation { display: flex; align-items: center; justify-content: space-between; margin-top: 24px; padding-top: 20px; border-top: 1px solid var(--fimby-border-subtle); }
.nav-btn { display: inline-flex; align-items: center; gap: 6px; padding: 10px 20px; border: 1px solid var(--fimby-border-default); border-radius: var(--fimby-radius-sm); background-color: var(--fimby-surface-card); color: var(--fimby-text-secondary); font-size: 14px; font-weight: 600; cursor: pointer; min-height: 44px; transition: all .2s ease; font-family: inherit; }
.nav-btn:hover { background-color: var(--fimby-hover-bg); border-color: var(--fimby-border-strong); }
.nav-btn:focus-visible { outline: 2px solid var(--fimby-focus-ring); outline-offset: 2px; box-shadow: 0 0 0 4px var(--fimby-focus-glow); }
.nav-next { background-color: var(--fimby-btn-primary-bg); color: #fff; border-color: var(--fimby-btn-primary-bg); }
.nav-next:hover { background-color: var(--fimby-btn-primary-bg-hover); border-color: var(--fimby-btn-primary-bg-hover); }
.nav-next:disabled { opacity: .5; cursor: not-allowed; }
.nav-next lightning-icon { --lwc-colorTextIconDefault: #ffffff; }
```
Rules: same place every page; no `lightning-button` in form nav (use `nav-btn`); chevron = more pages ahead, final submit no icon; header is for breadcrumbs/actions not nav; single-page forms skip this.

## Character counter label row
```html
<div class="field-label-row">
    <label for="my-input" class="field-label">Title</label>
    <span class="field-counter">{current}/{max}</span>
</div>
<lightning-input variant="label-hidden" ...></lightning-input>
```
```css
.field-label-row { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 4px; }
.field-label-row .field-label, .field-label-row label { margin-bottom: 0; }
.field-counter { font-size: .75rem; color: var(--fimby-text-secondary); padding: 0; }
```

## Form input labels — always bold
All input labels bold (`font-weight: 600`/`700`). Since `lightning-input`/`-textarea`/`-combobox` render labels in shadow DOM, use `variant="label-hidden"` + a custom `.field-label` above the component.
