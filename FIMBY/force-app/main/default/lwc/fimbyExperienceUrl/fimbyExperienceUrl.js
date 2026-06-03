/**
 * Normalize Experience Cloud navigation targets to site-relative paths.
 *
 * Notification Action_URL__c and thread actionUrl values are stored absolute
 * (via FIMBY_URL__mdt for email / push deep links). Inside the site, always
 * navigate with paths like /library-item/{id} so links stay on the current
 * host — production, sandbox, or partial org — without a metadata update.
 */

const KNOWN_EXPERIENCE_HOSTS = new Set([
    'our.fimby.com',
    'app.fimby.com'
]);

const LEGACY_MESSAGES_RE = /^(\/messages\/([a-zA-Z0-9]{15,18}))(?:\/|$|\?|#)/;

function applyLegacyPathRewrites(path) {
    if (!path) {
        return path;
    }
    const match = path.match(LEGACY_MESSAGES_RE);
    if (match) {
        return `/conversation?id=${match[2]}`;
    }
    return path;
}

function pathFromAbsoluteUrl(raw) {
    try {
        const parsed = new URL(raw);
        if (!KNOWN_EXPERIENCE_HOSTS.has(parsed.host)) {
            return null;
        }
        return applyLegacyPathRewrites(parsed.pathname + parsed.search + parsed.hash);
    } catch (e) {
        return null;
    }
}

/**
 * @param {string} url Absolute or relative Experience Cloud URL.
 * @returns {string} Site-relative path when the URL targets a known FIMBY
 *   Experience host; otherwise the original string (external URLs unchanged).
 */
export function toExperiencePath(url) {
    if (url == null) {
        return '';
    }
    const raw = String(url).trim();
    if (!raw) {
        return '';
    }

    if (raw.startsWith('/') && !raw.startsWith('//')) {
        return applyLegacyPathRewrites(raw);
    }

    if (/^https?:\/\//i.test(raw)) {
        const path = pathFromAbsoluteUrl(raw);
        return path != null ? path : raw;
    }

    if (raw.startsWith('//')) {
        const path = pathFromAbsoluteUrl(`https:${raw}`);
        return path != null ? path : raw;
    }

    return applyLegacyPathRewrites(`/${raw.replace(/^\/+/, '')}`);
}

export function isKnownExperienceHost(hostname) {
    return KNOWN_EXPERIENCE_HOSTS.has(hostname);
}
