import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';

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

    // Record-scoped custom routes reached with state:{id} (→ ?id= query param).
    neighbour:           { url: '/neighbour',                name: 'Neighbour__c',    tab: null },
    conversation:        { url: '/conversation',             name: 'Conversation__c', tab: 'messages' },

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

/* ---------------------------------------------------------------------------
 * Path → page-reference resolution for the universal `navigate()` helper.
 *
 * Verified against digitalExperiences/site/FIMBY1/sfdc_cms__route/* (every
 * route's urlPrefix/urlName). `comm__namedPage` resolves by ROUTE API NAME, so
 * the canonical URL is correct regardless of the legacy path string a caller
 * passes (e.g. '/my-stuff/my-skills' and '/my-skills' both → 'My_Skills__c').
 * ------------------------------------------------------------------------- */

/**
 * First-path-segment → object API name for record-detail pages. These resolve
 * via `standard__recordPage` (LWR picks the object's detail route), which is
 * how the list+detail prefix collisions (asks-offers, sharedlife, library-item,
 * skill-offer all carry list + detail + related routes) are disambiguated.
 */
const RECORD_DETAIL_OBJECTS = {
    'asks-offers': 'Needs_Offers__c',
    'needs-offers': 'Needs_Offers__c',
    'sharedlife': 'Story__c',
    'story': 'Story__c',
    'library-item': 'Library_Item__c',
    'skill-offer': 'Skill_Offer__c'
};

/**
 * Internal path → route API name for `comm__namedPage` soft nav. Keys are the
 * path tail without the leading slash; nested `my-stuff/*` aliases are included
 * because legacy code hard-codes `/my-stuff/my-skills` etc.
 */
const NAMED_ROUTES_BY_PATH = {
    '': 'Home',
    'library-list': 'Library_List__c',
    'messages': 'messages__c',
    'my-stuff': 'My_Stuff__c',
    'profile': 'profile__c',
    'search': 'Search__c',
    'notifications': 'Notifications__c',
    'settings': 'Settings__c',
    'neighbour': 'Neighbour__c',
    'conversation': 'Conversation__c',
    'response-reply': 'Response_Reply__c',
    'response-detail': 'Response_Detail__c',
    'moderator-dashboard': 'Moderator_Dashboard__c',
    'moderator-task': 'Moderator_Task__c',
    'moderator-task-archive': 'Moderator_Task_Archive__c',
    'help-support': 'Help_and_Support__c',
    'help-and-support': 'Help_and_Support__c',
    'organization-profile': 'Organization_Profile__c',
    'manage-identities': 'Manage_Identities__c',
    'new-message': 'New_Message__c',
    'quick-post': 'Quick_Post__c',
    'ask-or-offer-post': 'Ask_or_Offer_Post__c',
    'library-item-post': 'Library_Item_Post__c',
    'shared-life-post': 'Stories__c',
    'shared-life-list': 'Shared_Life_List__c',
    'share-contact': 'Share_Contact__c',
    'feedback': 'Feedback__c',
    'post-archive': 'Post_Archive__c',
    'story-archive': 'Story_Archive__c',
    'borrowing-history': 'Borrowing_History__c',
    'my-items': 'My_Items__c',
    'my-contacts': 'My_Contacts__c',
    'my-posts': 'My_Posts__c',
    'my-shared-life': 'My_Shared_Life__c',
    'my-skills': 'My_Skills__c',
    'my-library-items': 'My_Library_Items__c',
    'my-borrowing': 'My_Borrowing__c',
    'my-bulk-buys': 'My_Bulk_Buys__c',
    'my-stuff/my-contacts': 'My_Contacts__c',
    'my-stuff/my-posts': 'My_Posts__c',
    'my-stuff/my-shared-life': 'My_Shared_Life__c',
    'my-stuff/my-skills': 'My_Skills__c',
    'my-stuff/my-library-items': 'My_Library_Items__c',
    'my-stuff/my-borrowing': 'My_Borrowing__c',
    'my-stuff/my-bulk-buys': 'My_Bulk_Buys__c',
    'system-profile': 'System_Profile__c'
};

/** Schemes / paths that must always perform a full (hard) load. */
const HARD_NAV_PATTERN = /^(https?:|mailto:|tel:|sms:|fimby:|javascript:|data:)/i;

function parseQueryToState(rawQuery) {
    const state = {};
    if (!rawQuery) return state;
    for (const pair of rawQuery.split('&')) {
        if (!pair) continue;
        const idx = pair.indexOf('=');
        const key = idx === -1 ? pair : pair.slice(0, idx);
        const val = idx === -1 ? '' : pair.slice(idx + 1);
        if (!key) continue;
        try {
            state[decodeURIComponent(key)] = decodeURIComponent(val.replace(/\+/g, ' '));
        } catch {
            state[key] = val;
        }
    }
    return state;
}

/**
 * Resolve an internal app path (e.g. '/asks-offers/abc?x=1') to a soft-nav page
 * reference, or null when the path has no known mapping (caller hard-navigates).
 */
function resolvePageReference(url) {
    try {
        let [rawPath, rawQuery] = String(url).split('?');
        const state = parseQueryToState(rawQuery);
        // Strip the community basePath (e.g. '/fimby') when the URL was already
        // run through toExperiencePath, so server-built / notification action
        // URLs still resolve to a soft-nav route.
        if (basePath && rawPath.startsWith(basePath)) {
            rawPath = rawPath.slice(basePath.length);
        }
        const segments = rawPath.split('/').filter(s => s && s !== 's');

        // Home (optionally with ?filter=).
        if (segments.length === 0) {
            const ref = { type: 'comm__namedPage', attributes: { name: 'Home' } };
            if (Object.keys(state).length) ref.state = state;
            return ref;
        }

        // Record-detail page: <prefix>/<recordId>.
        const first = segments[0];
        if (RECORD_DETAIL_OBJECTS[first] && segments.length >= 2) {
            const ref = getRecordPageReference(RECORD_DETAIL_OBJECTS[first], segments[1]);
            if (ref && Object.keys(state).length) ref.state = state;
            return ref;
        }

        // Named route: try the full path tail first (for nested my-stuff/*),
        // then the leading segment.
        const fullPath = segments.join('/');
        const name = NAMED_ROUTES_BY_PATH[fullPath] || NAMED_ROUTES_BY_PATH[first];
        if (name) {
            const ref = { type: 'comm__namedPage', attributes: { name } };
            if (Object.keys(state).length) ref.state = state;
            return ref;
        }
        return null;
    } catch {
        return null;
    }
}

/**
 * Universal soft-navigation entry point. Converts an internal app URL into a
 * client-side (`NavigationMixin.Navigate`) navigation that keeps the persistent
 * shell mounted. External links, auth/session paths, and any unmapped internal
 * path fall back to a full `location.href` load so nothing ever breaks.
 *
 * Replaces every `location.href = '/...'` / `window.location.href = '/...'` and
 * internal `<a href>` in the app. The calling component MUST extend
 * `NavigationMixin(LightningElement)`; if it does not, this degrades to a hard
 * load automatically.
 *
 * @param {object} cmp  the component instance (`this`)
 * @param {string} url  an internal app path or absolute/external URL
 */
/**
 * Page-level back affordance (< chevron): prefer browser history.
 * Soft-nav SPA moves do not update document.referrer, so never gate on referrer.
 * Optional fallback only when history.length <= 1 (direct link / new tab).
 */
function navigateBack(cmp, fallbackUrl) {
    if (window.history.length > 1) {
        window.history.back();
        return;
    }
    if (fallbackUrl) {
        navigate(cmp, fallbackUrl);
    }
}

function navigate(cmp, url) {
    if (!url || typeof url !== 'string') return;
    const target = url.trim();
    if (!target || target === '#') return;

    // External / scheme / Salesforce auth endpoints → full load.
    if (HARD_NAV_PATTERN.test(target) || target.startsWith('/secur/')) {
        window.location.href = target;
        return;
    }

    const ref = resolvePageReference(target);
    if (ref && cmp && typeof cmp[NavigationMixin.Navigate] === 'function') {
        startNavTiming(resolveTabFromPath(target));
        cmp[NavigationMixin.Navigate](ref);
        return;
    }
    window.location.href = target;
}

/**
 * Soft-navigate to a known logical route key (e.g. tab handlers that already
 * have 'home' / 'library' / 'messages'), with optional page-reference state.
 * Falls back through `navigate()` (URL) when the key has no named-page mapping.
 */
function navigateToRoute(cmp, key, opts = {}) {
    const ref = getPageReference(key, opts);
    if (ref && cmp && typeof cmp[NavigationMixin.Navigate] === 'function') {
        startNavTiming(tabForKey(key));
        cmp[NavigationMixin.Navigate](ref);
        return;
    }
    navigate(cmp, getUrl(key));
}

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
    } catch {
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
    } catch {
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
         
        console.log(`[fimby-nav] ${key} time-to-mount: ${delta}ms`);
        return { key, delta };
    } catch {
        return null;
    }
}

/**
 * Resolve a profile URL for a contact avatar tap.
 * Mirrors fimbyUniversalHeader.handleProfileClick for self-routing.
 */
function profilePathForContact({ contactId, isOrgContact, orgAccountId, currentContactId }) {
    if (!contactId) return '';
    const isSelf = currentContactId && contactId === currentContactId;
    if (isSelf || isOrgContact) {
        if (orgAccountId) {
            return `/organization-profile?id=${orgAccountId}`;
        }
        if (isSelf) {
            return '/profile';
        }
    }
    return `/neighbour?id=${contactId}`;
}

export {
    ROUTES,
    TAB_ROUTES,
    getUrl,
    getPageReference,
    getRecordPageReference,
    resolvePageReference,
    navigate,
    navigateBack,
    navigateToRoute,
    resolveTabFromPath,
    tabForKey,
    startNavTiming,
    endNavTiming,
    profilePathForContact
};
