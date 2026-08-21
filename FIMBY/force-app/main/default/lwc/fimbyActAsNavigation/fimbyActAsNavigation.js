import switchIdentityToContact from '@salesforce/apex/FimbySupportRelationshipController.switchIdentityToContact';
import { resetProxiedIdentityCache } from 'c/fimbyProxiedIdentity';

const ACT_AS_ID_PATTERN = /^[a-zA-Z0-9]{15,18}$/;

/**
 * Parse a Salesforce Id from ?actAs= on an internal path or absolute URL.
 * @param {string} url
 * @returns {string|null}
 */
export function parseActAsFromUrl(url) {
    if (!url || typeof url !== 'string') {
        return null;
    }
    try {
        const queryStart = url.indexOf('?');
        if (queryStart === -1) {
            return null;
        }
        const hashStart = url.indexOf('#', queryStart);
        const query = hashStart === -1
            ? url.slice(queryStart + 1)
            : url.slice(queryStart + 1, hashStart);
        const actAs = new URLSearchParams(query).get('actAs');
        return ACT_AS_ID_PATTERN.test(actAs) ? actAs : null;
    } catch {
        return null;
    }
}

/**
 * Remove ?actAs= (and &actAs=) while preserving other query params and hash.
 * @param {string} url site-relative path or absolute URL
 * @returns {string}
 */
export function stripActAsFromUrl(url) {
    if (!url || typeof url !== 'string') {
        return url;
    }
    try {
        if (/^https?:\/\//i.test(url)) {
            const parsed = new URL(url);
            parsed.searchParams.delete('actAs');
            return parsed.pathname + parsed.search + parsed.hash;
        }
        const hashIndex = url.indexOf('#');
        const hash = hashIndex === -1 ? '' : url.slice(hashIndex);
        const pathAndQuery = hashIndex === -1 ? url : url.slice(0, hashIndex);
        const queryIndex = pathAndQuery.indexOf('?');
        if (queryIndex === -1) {
            return url;
        }
        const path = pathAndQuery.slice(0, queryIndex);
        const params = new URLSearchParams(pathAndQuery.slice(queryIndex + 1));
        params.delete('actAs');
        const query = params.toString();
        return path + (query ? `?${query}` : '') + hash;
    } catch {
        return url;
    }
}

/** Clear client caches that key off the acting identity. */
export function clearIdentitySwitchCaches() {
    try {
        sessionStorage.removeItem('fimby-home-feed-state');
        sessionStorage.removeItem('fimby-library-browser-v3');
        sessionStorage.removeItem('fimby-badge-counts');
    } catch {
        /* ignore */
    }
    resetProxiedIdentityCache();
}

/**
 * Switch to the supported identity, then hard-navigate so every surface loads
 * in the right voice. Used by notification taps, ?actAs= deep links, and any
 * navigate() call that carries actAs in the URL.
 *
 * @param {string} url destination (may include ?actAs=)
 * @param {object} [opts]
 * @param {string} [opts.actAsContactId] explicit inbox Contact Id (overrides URL param)
 * @param {function} [opts.onError] called with the Apex error before navigating anyway
 * @returns {Promise<boolean>} true when identity switched before navigation
 */
export async function honourActAsThenNavigate(url, opts = {}) {
    const actAs = (opts.actAsContactId && ACT_AS_ID_PATTERN.test(opts.actAsContactId))
        ? opts.actAsContactId
        : parseActAsFromUrl(url);
    const destination = stripActAsFromUrl(url);

    if (!actAs) {
        window.location.href = destination;
        return false;
    }

    try {
        const switched = await switchIdentityToContact({ actAsContactId: actAs });
        clearIdentitySwitchCaches();
        window.location.replace(destination);
        return switched === true;
    } catch (error) {
        if (typeof opts.onError === 'function') {
            opts.onError(error);
        }
        window.location.replace(destination);
        return false;
    }
}
