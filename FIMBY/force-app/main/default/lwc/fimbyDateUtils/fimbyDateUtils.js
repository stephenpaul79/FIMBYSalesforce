/**
 * Shared date helpers for FIMBY LWCs.
 *
 * The core problem (DEF-2026-005): Salesforce Date fields serialize as ISO date-only
 * strings ("YYYY-MM-DD"). `new Date("2026-04-06")` parses as UTC midnight, which renders
 * as Apr 5 in US Pacific. We normalize to local-midnight so the day matches the wall
 * clock of the FIMBY user.
 *
 * Use formatLocalDate for any UI surface that displays a date-only field (due dates,
 * pickup dates, waitlist requested-on, loan history bookends). Use formatLocalDateTime
 * for true datetime fields (CreatedDate, LastModifiedDate, etc.) where preserving the
 * instant matters.
 */

const DATE_ONLY_RE = /^\d{4}-\d{2}-\d{2}$/;

export function parseLocalDate(value) {
    if (value == null || value === '') return null;
    if (value instanceof Date) return isNaN(value.getTime()) ? null : value;
    const s = typeof value === 'string' ? value.trim() : String(value);
    if (DATE_ONLY_RE.test(s)) {
        const [y, mo, d] = s.split('-').map((n) => parseInt(n, 10));
        return new Date(y, mo - 1, d);
    }
    const parsed = new Date(s);
    return isNaN(parsed.getTime()) ? null : parsed;
}

export function formatLocalDate(value, options) {
    const d = parseLocalDate(value);
    if (!d) return '';
    return d.toLocaleDateString(undefined, options);
}

export function formatShortDate(value) {
    return formatLocalDate(value, { month: 'short', day: 'numeric' });
}

export function formatLocalDateTime(value, options) {
    if (value == null || value === '') return '';
    const d = value instanceof Date ? value : new Date(value);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleString(undefined, options);
}
