/**
 * Shared navigation service for the FIMBY1 LWR Experience Cloud site.
 *
 * Consolidates the route maps that were previously duplicated across the nav
 * shell and ~9 list components (each carried its own `validPages` map, and the
 * two nav components each carried their own `TAB_ROUTES` prefix table).
 *
 * Two navigation styles exist in the codebase and both produce client-side
 * (soft) navigation when invoked through `NavigationMixin.Navigate` — the theme
 * layout (header + bottom nav) stays mounted and only the content region swaps:
 *   - `comm__namedPage` by route API/developer name  (preferred here)
 *   - `standard__namedPage` by url-name              (proven in ~23 shipped calls)
 * `standard__webPage` with a `url:` is deliberately NOT used — it navigates by
 * URL like a hard load and defeats the persistent shell.
 *
 * PAGE-NAME INVENTORY (verified against
 * digitalExperiences/site/FIMBY1/sfdc_cms__route/*):
 *   route API name (folder)  | urlName / url        | bottom tab
 *   -------------------------|----------------------|-----------
 *   Home                     | (home) "/"           | home
 *   Library_List__c          | library-list         | library
 *   messages__c              | messages             | messages
 *   My_Stuff__c              | my-stuff             | mine
 *   profile__c               | profile              | mine
 *   Search__c                | search               | —
 *   Notifications__c         | notifications        | mine
 *   Settings__c              | settings             | mine
 * NOTE: the legacy `name: 'Library__c'` used in fimbyAddLibraryItem does NOT
 * exist as a route — the real library route API name is `Library_List__c`.
 *
 * Components keep ownership of the actual `this[NavigationMixin.Navigate](...)`
 * call (the mixin requires the component instance). This module supplies the
 * page-reference object (`getPageReference`) and the URL fallback (`getUrl`).
 */

/**
 * Route table. Each entry:
 *   url   — location.href fallback (also Stage-1 behaviour, unchanged)
 *   name  — route API/developer name for a `comm__namedPage` soft nav
 *           (omit when there is no clean named-page equivalent)
 *   tab   — which bottom-nav tab this route highlights
 */
const ROUTES = {
    home:                { url: '/',                         name: 'Home',            tab: 'home' },
    library:             { url: '/library-list',             name: 'Library_List__c', tab: 'library' },
    messages:            { url: '/messages',                 name: 'messages__c',     tab: 'messages' },
    mine:                { url: '/my-stuff',                 name: 'My_Stuff__c',     tab: 'mine' },
    myStuff:             { url: '/my-stuff',                 name: 'My_Stuff__c',     tab: 'mine' },
    profile:             { url: '/profile',                  name: 'profile__c',      tab: 'mine' },
    search:              { url: '/search',                   name: 'Search__c',       tab: null },
    notifications:       { url: '/notifications',            name: 'Notifications__c', tab: 'mine' },
    settings:            { url: '/settings',                 name: 'Settings__c',     tab: 'mine' },

    // Secondary destinations — kept on URL fallback (no verified named-page
    // mapping yet); they still route correctly via location.href.
    help:                { url: '/help-support',             tab: 'mine' },
    'help-support':      { url: '/help-support',             tab: 'mine' },
    feedback:            { url: '/feedback',                 tab: 'mine' },
    'create-story':      { url: '/create-story',             tab: 'home' },
    'create-post':       { url: '/ask-or-offer-post',        tab: 'home' },
    'ask-post':          { url: '/ask-or-offer-post?type=Need',  tab: 'home' },
    'offer-post':        { url: '/ask-or-offer-post?type=Offer', tab: 'home' },
    'shared-life-post':  { url: '/shared-life-post',         tab: 'home' },
    'library-item-post': { url: '/library-item-post',        tab: 'library' },
    'add-library-item':  { url: '/library-item-post',        tab: 'library' },
    responses:           { url: '/responses',                tab: 'mine' },
    'loaned-items':      { url: '/loaned-items',             tab: 'mine' },
    'shared-contacts':   { url: '/shared-contacts',          tab: 'mine' },
    stories:             { url: '/?filter=story',            tab: 'home' },
    askOffer:            { url: '/ask-offer-list',           tab: 'home' }
};

/**
 * Bottom-tab detection table (consolidated from the duplicated `TAB_ROUTES`
 * tables in fimbyUniversalHeader and fimbyBottomNavigation). Order matters:
 * the first matching tab wins; falls back to 'home'.
 */
const TAB_ROUTES = [
    { tab: 'library',  prefixes: ['/library-list', '/library-item', '/library-item-post', '/add-library-item', '/borrow-item', '/skill-offer'] },
    { tab: 'messages', prefixes: ['/messages', '/conversation', '/new-message'] },
    { tab: 'mine',     prefixes: ['/mine', '/my-stuff', '/my-stuff/my-contacts', '/my-stuff/my-posts', '/my-stuff/my-shared-life', '/my-stuff/my-library-items', '/my-stuff/my-skills', '/my-stuff/my-borrowing', '/my-items', '/post-archive', '/story-archive', '/borrowing-history', '/profile', '/edit-profile', '/responses', '/loaned-items', '/settings', '/notifications', '/moderator-dashboard', '/moderator-task-archive', '/help-and-support', '/help-support', '/community-guidelines', '/feedback', '/shared-contacts'] },
    { tab: 'home',     prefixes: ['/shared-life-list', '/stories', '/story', '/create-story', '/shared-life-post', '/ask-offer-list', '/ask-or-offer-post', '/asks-offers', '/needs-offers', '/quick-post', '/respond', '/response-detail', '/response-reply'] }
];

const DEFAULT_TAB = 'home';

/** Resolve the location.href URL for a logical route key. */
function getUrl(key) {
    const entry = ROUTES[key];
    return entry ? entry.url : '/';
}

/**
 * Build a page reference for a soft (`NavigationMixin.Navigate`) navigation.
 * Returns null when the route has no named-page equivalent — callers should
 * fall back to `location.href = getUrl(key)` in that case.
 *
 * @param {string} key   logical route key (e.g. 'home', 'library')
 * @param {object} [opts]
 * @param {object} [opts.state]  optional page-reference state object
 */
function getPageReference(key, opts = {}) {
    const entry = ROUTES[key];
    if (!entry || !entry.name) {
        return null;
    }
    const ref = {
        type: 'comm__namedPage',
        attributes: { name: entry.name }
    };
    if (opts.state) {
        ref.state = opts.state;
    }
    return ref;
}

/**
 * Build a page reference for a record-detail (object) soft navigation.
 * LWR resolves `standard__recordPage` to the object's configured detail route
 * (e.g. Needs_Offers__c → /asks-offers/{id}, Story__c → /sharedlife/{id},
 * Library_Item__c → /library-item/{id}, Skill_Offer__c → /skill-offer/{id}),
 * keeping the persistent shell mounted. This is NOT standard__webPage by url.
 *
 * Returns null when inputs are missing so callers can fall back to location.href.
 *
 * @param {string} objectApiName  e.g. 'Needs_Offers__c', 'Story__c'
 * @param {string} recordId
 */
function getRecordPageReference(objectApiName, recordId) {
    if (!objectApiName || !recordId) {
        return null;
    }
    return {
        type: 'standard__recordPage',
        attributes: {
            recordId,
            objectApiName,
            actionName: 'view'
        }
    };
}

/** Which bottom tab does a given URL path belong to? */
function resolveTabFromPath(path) {
    try {
        const pagePath = (path || '').split('?')[0].replace(/\/$/, '') || '/';
        if (pagePath === '/' || pagePath === '') {
            return 'home';
        }
        for (const route of TAB_ROUTES) {
            for (const prefix of route.prefixes) {
                if (pagePath === prefix || pagePath.startsWith(prefix + '/')) {
                    return route.tab;
                }
            }
        }
        return DEFAULT_TAB;
    } catch (e) {
        return DEFAULT_TAB;
    }
}

/** Map a route key directly to its bottom tab (for reactive highlight on nav). */
function tabForKey(key) {
    const entry = ROUTES[key];
    return entry && entry.tab ? entry.tab : DEFAULT_TAB;
}

/* ---------------------------------------------------------------------------
 * Lightweight nav-timing instrumentation.
 * startNavTiming() is called the instant a navigation is requested; the
 * destination calls endNavTiming() on mount to log the perceived tab-switch
 * time. Gives a concrete before/after number for the soft-nav pilot.
 * ------------------------------------------------------------------------- */
const NAV_TIMING_KEY = 'fimby-nav-timing';

function startNavTiming(key) {
    try {
        const payload = { key, t: Date.now() };
        sessionStorage.setItem(NAV_TIMING_KEY, JSON.stringify(payload));
        if (typeof performance !== 'undefined' && performance.mark) {
            performance.mark(`fimby-nav-start:${key}`);
        }
    } catch (e) {
        /* instrumentation must never break navigation */
    }
}

function endNavTiming() {
    try {
        const raw = sessionStorage.getItem(NAV_TIMING_KEY);
        if (!raw) return null;
        sessionStorage.removeItem(NAV_TIMING_KEY);
        const { key, t } = JSON.parse(raw);
        const delta = Date.now() - t;
        if (typeof performance !== 'undefined' && performance.mark) {
            performance.mark(`fimby-nav-end:${key}`);
        }
        // eslint-disable-next-line no-console
        console.log(`[fimby-nav] ${key} time-to-mount: ${delta}ms`);
        return { key, delta };
    } catch (e) {
        return null;
    }
}

export {
    ROUTES,
    TAB_ROUTES,
    getUrl,
    getPageReference,
    getRecordPageReference,
    resolveTabFromPath,
    tabForKey,
    startNavTiming,
    endNavTiming
};
