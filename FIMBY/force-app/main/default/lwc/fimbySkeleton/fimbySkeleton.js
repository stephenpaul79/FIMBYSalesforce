import { LightningElement, api } from 'lwc';

/**
 * fimbySkeleton — layout-matched loading placeholders.
 *
 * Shows shaped grey blocks sized like the real content so there's no layout
 * shift when data arrives. Use ONLY for a true cold load (no cached content);
 * a cache hit should paint real content and skip the skeleton entirely.
 *
 * Accessibility: the region carries aria-busy="true" and a polite, visually
 * hidden "Loading…" announcement; the placeholder shapes are aria-hidden so a
 * screen reader doesn't read them as empty boxes. aria-busy is dropped by the
 * parent simply by un-rendering this component once content is ready.
 *
 * Variants:
 *   card        — feed/list cards (default)
 *   list-row    — compact rows (messages, notifications, contacts)
 *   detail      — a single record detail page
 *   profile-hub — avatar + name + stat grid hub pages
 */
const VALID_VARIANTS = ['card', 'list-row', 'detail', 'profile-hub'];

export default class FimbySkeleton extends LightningElement {
    @api variant = 'card';
    @api count = 3;
    @api label = 'Loading…';

    get _variant() {
        return VALID_VARIANTS.includes(this.variant) ? this.variant : 'card';
    }

    /** Repeatable items for list/card variants (detail & hub render once). */
    get items() {
        const repeats = this._variant === 'card' || this._variant === 'list-row'
            ? Math.max(1, Number(this.count) || 1)
            : 1;
        return Array.from({ length: repeats }, (_, i) => ({ key: `sk-${i}` }));
    }

    get isCard() { return this._variant === 'card'; }
    get isListRow() { return this._variant === 'list-row'; }
    get isDetail() { return this._variant === 'detail'; }
    get isProfileHub() { return this._variant === 'profile-hub'; }
}
