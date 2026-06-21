/**
 * fimbyCache — shared stale-while-revalidate cache helper.
 *
 * Generalizes the per-component sessionStorage caching already used by the
 * header badge counts and the home feed so any list/detail surface can paint
 * last-known data instantly on (soft) navigation, then reconcile after a
 * background fetch.
 *
 * PRIVACY (non-negotiable): every entry is keyed by acting-as identity +
 * neighbourhood. A read whose stored scope doesn't match the current scope
 * returns null (and self-evicts) so a user who switched identity never sees the
 * previous identity's cached content flash — this mirrors the trust-boundary
 * rule. On identity switch, callers should also call clearAllScopedCaches().
 *
 * TTL: messages/notifications get a short TTL because a stale unread count or a
 * since-deleted item misleads in a way a slightly stale feed does not.
 *
 * ERROR-VS-CACHE rule (applied by the consumer, not here): when a revalidation
 * fetch fails but readCache() returned content, keep showing that content with
 * a subtle "couldn't refresh" affordance; only fall back to the full error
 * state when there is NO cache (hasCache() === false).
 */

/** Known scoped cache keys. Registered here so clearAllScopedCaches() wipes
 *  every one on identity switch (mirrors the old _clearFeedCaches). */
const SCOPED_KEYS = {
    homeFeed: 'fimby-home-feed-state',
    library: 'fimby-library-state',
    messages: 'fimby-messages-state',
    notifications: 'fimby-notifications-state',
    badgeCounts: 'fimby-badge-counts'
};

const DEFAULT_TTL_MS = 15 * 60 * 1000; // 15 minutes

// Per-key TTL overrides — keep messages/notifications short.
const TTL_OVERRIDES = {
    [SCOPED_KEYS.messages]: 60 * 1000,
    [SCOPED_KEYS.notifications]: 60 * 1000,
    [SCOPED_KEYS.badgeCounts]: 60 * 1000
};

function _scopeId(identityId, neighbourhoodId) {
    return `${identityId || '?'}::${neighbourhoodId || '?'}`;
}

function _ttlFor(key, explicit) {
    if (typeof explicit === 'number') return explicit;
    return TTL_OVERRIDES[key] || DEFAULT_TTL_MS;
}

/**
 * Read a cached value. Returns the stored value, or null when missing, expired,
 * or written under a different identity/neighbourhood scope.
 *
 * @param {string} key
 * @param {object} [opts]
 * @param {string} [opts.identityId]       acting-as contact id
 * @param {string} [opts.neighbourhoodId]  active neighbourhood id
 * @param {number} [opts.ttlMs]            override TTL
 */
function readCache(key, opts = {}) {
    try {
        const raw = sessionStorage.getItem(key);
        if (!raw) return null;
        const entry = JSON.parse(raw);

        // Scope mismatch — never surface another identity's content.
        if (entry.s !== _scopeId(opts.identityId, opts.neighbourhoodId)) {
            sessionStorage.removeItem(key);
            return null;
        }
        // Expired.
        if (Date.now() - entry.t > _ttlFor(key, opts.ttlMs)) {
            return null;
        }
        return entry.v;
    } catch {
        return null;
    }
}

/** True when a non-expired, in-scope cache entry exists (drives the
 *  error-vs-cache decision without consuming the value twice). */
function hasCache(key, opts = {}) {
    return readCache(key, opts) !== null;
}

/**
 * Write a value into the scoped cache.
 *
 * @param {string} key
 * @param {*}      value             JSON-serializable value
 * @param {object} [opts]
 * @param {string} [opts.identityId]
 * @param {string} [opts.neighbourhoodId]
 */
function writeCache(key, value, opts = {}) {
    try {
        const entry = {
            s: _scopeId(opts.identityId, opts.neighbourhoodId),
            t: Date.now(),
            v: value
        };
        sessionStorage.setItem(key, JSON.stringify(entry));
    } catch {
        /* storage unavailable or full — non-fatal */
    }
}

/** Remove a single cache entry. */
function clearCache(key) {
    try {
        sessionStorage.removeItem(key);
    } catch {
        /* ignore */
    }
}

/** Clear every registered scoped cache — call on identity switch. */
function clearAllScopedCaches() {
    Object.values(SCOPED_KEYS).forEach(clearCache);
}

export {
    SCOPED_KEYS,
    readCache,
    writeCache,
    hasCache,
    clearCache,
    clearAllScopedCaches
};
