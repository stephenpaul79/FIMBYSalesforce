# FIMBY UI / UX Patterns

Accessibility, forms, navigation, persona-first detail pages, event-type UX. Pairs with css-foundations.md (tokens/layout) and component-patterns.md (markup/CSS snippets).

## Accessibility (WCAG)
- **Colour contrast:** `--fimby-*` tokens only; never hardcode.
- **Touch targets:** ≥ 44×44px.
- **ARIA:** modals → `role="dialog"` + `aria-modal` + `aria-labelledby`; progress → `role="progressbar"` + value attrs; alerts → `role="alert"`; icon-only buttons → `aria-label`.
- **Focus:** move focus into modals on open, return on close.
- **Keyboard:** Enter submits, Escape closes, arrows for carousels.
- **Images:** decorative → `alt=""`; meaningful → descriptive alt; spinners → `alternative-text`.

## Button vs badge affordances
Actions and decorative badges must be distinct at a glance (low-tech / low-vision users). **Action buttons (Tier 1):** rounded rectangle, elevated (shadow), hover/active states, ≥44px, `--fimby-btn-*`. **Toggle controls (Tier 2):** pill, always grouped with clear selected state. **Decorative badges (Tier 3):** pill, flat, small, non-interactive, `--fimby-badge-*`. When a badge and button share a row, shape difference alone must distinguish them — never rely on colour.

## Navigation
- Four tabs: Home, Library, Messages, My Stuff + context-sensitive Create.
- Mobile-first: bottom tab bar fixed; desktop tabs in header.
- Keep it flat — most flows one level deep; clear back affordance when deeper.
- Menus: labels over icons, no jargon, group related items.

## Forms & interaction
- **Progressive disclosure:** one concern per step; only required steps block; conditional fields reveal when relevant; Read More/Show Less for long content.
- **Multi-page navigation:** `.form-navigation` footer on every page — "< Back" bottom-left (neutral outlined + left chevron), primary bottom-right (teal + white). "Next >" has right chevron; final submit has no chevron. Nav buttons always inside the form area, never the header. (Markup/CSS in component-patterns.md.)
- **Empty states:** warm, actionable ("You're all caught up!" not "No results").
- **Error handling:** inline near the failed action, empathetic language, recovery path; auto-clear on context change; never full-page error screens.
- **Success feedback:** 1.5–2s timed confirmation, then auto-navigate/close.
- **Destructive actions:** confirmation modals explaining what happens + reassurance.
- **Inline validation:** `role="alert"` on errors.
- **Character counters:** same row as label via `.field-label-row` flex; for `lightning-input`/`-textarea` use `variant="label-hidden"` + custom label row; counter `0.75rem`, `var(--fimby-text-secondary)`.

## Persona-first detail pages
Structure around the viewer's relationship to content, not generic record-detail:

| Persona | Detection | Priority |
|---------|-----------|----------|
| Poster/author | Owns the record | Responses, attention, management |
| Potential responder | No existing response | What is it? Available? How to respond? |
| Already responded | Has response/reservation | Status, continuation |

Layout: **Poster** → header (Edit/Photo/Delete as `responsive`) → summary card → attention strip → response inbox → collapsible details. **Potential responder** → header (Flag as `kebab`) → summary card → action context + CTA → collapsible details. **Already responded** → header (Flag `kebab`) → summary card → "Your Response" card → collapsible details.

Principles: decision page not record page (top card answers "what is this, should I act?"); persona-specific CTAs (never generic Respond to someone who already responded); header actions via `menuItems` only; max 2 meta facts above the fold on mobile; collapsible secondary details (mobile collapsed, desktop primary expanded); warm empty states for posters with no responses; attention strips = summary pills (unread, new, accepted, available). Reference: `fimbyNeedOfferDetail`, `fimbyBulkBuyDetailBody`.

## Event-type UX
Use `EVENT_TYPE_CONFIG` (see fimby-lwc SKILL), never nested if/else.
- **Gathering** (intimate, capped): poster is host; hard cap via `Total_Quantity__c`; full RSVP form, response threads, accept/decline. "Hosted by". Feed: "X spots left".
- **Open Event** (everyone welcome): poster is organizer; no cap; 1-click "I'm Going", auto-accept, attendee list with moderation (remove/block), optional guest stepper; on-demand group chat (poster opt-in, not automatic). "Hosted by". Feed: "X going" + avatars.
- **Community Event** (sharing someone else's): poster is NOT host; no capacity/management; 1-click "I'm Interested" (not a commitment); read-only interest list, no moderation, no group chat; prominent `Event_Link__c` "check for latest details". "Shared by". Feed: "X interested" + COMMUNITY EVENT badge.

**Never happens:** Open/Community entering capacity exhaustion ("Event Full", disabled CTA); group chat auto-created on event creation; `Conversation__c` for event DMs (use `Response__c`); Community Event poster shown moderation or "Hosted by"; response threads for Open/Community (Gathering only).

## Mobile-native
Pull-to-refresh via `fimbyInfiniteScroll`; client-side compression via `fimbyImageUploader`; table↔card via `fimbyResponsiveList`; tap + drag-drop file inputs.

## Community reciprocity
Surface neighbourhood stats with weekly deltas; thank-yous as direct actions tied to responses; engagement counts on cards.

## Onboarding
Registration and profile setup are separate phases; only name required (rest optional/editable later); care prefs in onboarding but never gate progress; walkthrough CMS-driven with dismiss option.
