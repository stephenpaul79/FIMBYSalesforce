/**
 * Live guided tour step definitions — Essentials, Extended, Finale.
 * Copy: universal warmth tone; vision woven per step.
 */

export const TRACK_ESSENTIALS = 'essentials';
export const TRACK_EXTENDED = 'extended';
export const TRACK_FINALE = 'finale';

export const TOUR_STEPS = [
    {
        id: 'welcome',
        track: TRACK_ESSENTIALS,
        advance: 'next',
        placement: 'center',
        hideVine: true,
        hideProgressLabel: true,
        title: 'Welcome to your neighbourhood',
        body:
            'What if your street felt a little more like family — people who know your name, ' +
            'notice when you are carrying too much, make room at the table? ' +
            'This is the few streets around you, small on purpose. ' +
            'FIMBY is just the trellis; you and your neighbours are what grows.',
        heroImage: 'trellisbefore.png',
        heroAlt: 'A garden trellis with a young vine just starting to climb.',
        iconFile: null
    },
    {
        id: 'feed-filters',
        track: TRACK_ESSENTIALS,
        progressIndex: 1,
        advance: 'clickTarget',
        anchor: 'feed-filter-bar',
        placement: 'bottom',
        title: 'Your home feed',
        body:
            'Need and gift sit side by side here. Shared Life holds gratitude, stories, prayer — ' +
            'offered, never required. Ask & Offer holds the practical. ' +
            'Quiet here for now? You could be the first to post something your neighbours see.',
        mobileBody:
            'Need and gift sit side by side here. Shared Life holds gratitude, stories, and prayer. ' +
            'Ask & Offer holds the practical.',
        actionLabel: 'Try a filter',
        iconFile: 'StoriesInactive.png',
        clickAdvanceOn: ['story', 'askOffer']
    },
    {
        id: 'create',
        track: TRACK_ESSENTIALS,
        progressIndex: 2,
        advance: 'modalDismiss',
        anchor: 'nav-create',
        placement: 'top',
        title: 'One button to share',
        body:
            'One button to ask, offer, lend, gather, or share. ' +
            'Asking is not failure here — it is where trust starts.',
        actionLabel: 'Open Create',
        modalAnchor: 'quick-post-modal',
        modalActionLabel: 'Browse sharing options',
        modalActionSublabel: 'Select one or close to continue',
        hideModalCoach: true,
        modalCalloutOnly: true,
        modalCalloutFixedTop: true,
        revealTitle: 'You found the sharing menu',
        revealBody:
            'Those six options are always here when you tap Create. ' +
            'Tap Next when you are ready to keep touring.',
        revealNavigateTitle: 'Off to a good start',
        revealNavigateBody:
            'You opened a sharing path — finish when you like, then tap Next here to continue the tour.',
        iconFile: 'add.png',
        modalEvent: 'fimbyopenquickpost'
    },
    {
        id: 'library',
        track: TRACK_ESSENTIALS,
        progressIndex: 3,
        advance: 'clickTarget',
        anchor: 'nav-library',
        waitAnchor: 'library-filter-bar',
        route: '/library-list',
        placement: 'top',
        title: 'Borrow the drill',
        body:
            'Abundance circulates — the drill down the block instead of the store. ' +
            'Remember the vouch you asked for in setup? That is what opens the library.',
        mobileBody:
            'Abundance circulates — the drill down the block instead of the store.',
        actionLabel: 'Open Library',
        iconFile: 'ToolboxActive.png'
    },
    {
        id: 'messages',
        track: TRACK_ESSENTIALS,
        progressIndex: 4,
        advance: 'clickTarget',
        anchor: 'nav-messages',
        route: '/messages',
        placement: 'top',
        title: 'Care close enough to walk over',
        body:
            'This is where a borrowed ladder becomes a conversation. ' +
            'Quiet inbox? That is normal in a new neighbourhood — your first hello may start here.',
        mobileBody: 'This is where a borrowed ladder becomes a conversation.',
        actionLabel: 'Open Messages',
        iconFile: 'SpeechBubbleActive.png'
    },
    {
        id: 'different-by-design',
        track: TRACK_ESSENTIALS,
        progressIndex: 5,
        advance: 'next',
        placement: 'center',
        title: 'Different by design',
        body:
            'No ads, no likes, no followers. Here you are never the product — your data is never sold. ' +
            'No public broadcast, no city-wide reach. A brief check-in, not a slot machine. ' +
            'A doorbell, not an endless feed.',
        iconFile: 'NeighborhoodActive.png'
    },
    {
        id: 'off-ramp',
        track: TRACK_ESSENTIALS,
        advance: 'offRampChoice',
        placement: 'center',
        hideVine: true,
        title: 'You are ready to explore',
        body: 'You know the daily loop. Want a quick look at notifications, search, and your account?',
        iconFile: null
    },
    {
        id: 'notifications',
        track: TRACK_EXTENDED,
        progressIndex: 1,
        advance: 'clickTarget',
        anchor: 'nav-notifications',
        route: '/notifications',
        placement: 'bottom',
        title: 'Gentle nudges',
        body: 'A gentle nudge when a neighbour reaches out — not a feed to scroll.',
        actionLabel: 'Open Notifications',
        iconFile: 'BellActive.png'
    },
    {
        id: 'search',
        track: TRACK_EXTENDED,
        progressIndex: 2,
        advance: 'modalDismiss',
        anchor: 'nav-search',
        placement: 'bottom',
        title: 'Find nearby',
        body: 'Find a neighbour, an offer, or a skill nearby.',
        actionLabel: 'Open Search',
        modalAnchor: 'search-modal',
        modalActionLabel: 'Try a search',
        modalActionSublabel: 'Search or tap outside when you are done',
        hideModalCoach: true,
        modalCalloutOnly: true,
        revealTitle: 'Search is right there',
        revealBody:
            'Find neighbours, offers, or skills anytime. Tap Next when you are ready to continue.',
        revealNavigateTitle: 'Nice — you searched',
        revealNavigateBody:
            'Results open on their own page. Come back here and tap Next when you are ready.',
        iconFile: 'Magnify.png',
        opensSearch: true
    },
    {
        id: 'menu',
        track: TRACK_EXTENDED,
        progressIndex: 3,
        advance: 'clickTarget',
        anchor: 'nav-menu',
        placement: 'bottom',
        title: 'Everything else',
        body: 'Everything else lives here.',
        actionLabel: 'Open Menu',
        iconFile: 'Kebab.png'
    },
    {
        id: 'profile',
        track: TRACK_EXTENDED,
        progressIndex: 4,
        advance: 'next',
        anchor: 'menu-profile',
        placement: 'bottom',
        menuGuided: true,
        title: 'Be a little more known',
        body: 'Be a little less anonymous, a little more known.',
        actionLabel: 'Profile',
        iconFile: 'ProfileActive.png',
        mobileBubbleTop: true,
        route: '/profile'
    },
    {
        id: 'settings',
        track: TRACK_EXTENDED,
        progressIndex: 5,
        advance: 'next',
        anchor: 'menu-settings',
        placement: 'bottom',
        menuGuided: true,
        title: 'You are in control',
        body: 'You control how close people get — quiet hours, what you share, who can reach you.',
        actionLabel: 'Settings',
        iconFile: 'gear.png',
        mobileBubbleTop: true,
        route: '/settings'
    },
    {
        id: 'manage-identities',
        track: TRACK_EXTENDED,
        progressIndex: 6,
        advance: 'next',
        anchor: 'menu-manage-identities',
        placement: 'bottom',
        menuGuided: true,
        skipWhenSingleIdentity: true,
        title: 'No one left out',
        body:
            'No one is left out. A neighbour who cannot tap a screen — an elder, a kid — ' +
            'can have someone act for them here. The person you would normally pass on the street ' +
            'can become the one who checks in after surgery.',
        actionLabel: 'Manage Identities',
        iconFile: 'people.png',
        menuCalloutAbove: true,
        route: '/manage-identities'
    },
    {
        id: 'my-stuff',
        track: TRACK_EXTENDED,
        progressIndex: 7,
        advance: 'clickTarget',
        anchor: 'nav-mine',
        route: '/my-stuff',
        placement: 'top',
        title: 'Your corner of FIMBY',
        body: 'Your posts, items, and history, all in one place.',
        actionLabel: 'Open My Stuff',
        iconFile: 'ProfileActive.png',
        navigateHomeOnNext: true
    },
    {
        id: 'extended-complete',
        track: TRACK_EXTENDED,
        advance: 'next',
        placement: 'center',
        hideVine: true,
        hideProgressLabel: true,
        title: 'The backyard is yours',
        body:
            'You have the lay of the land now — feed, library, messages, settings, the lot. ' +
            'What grows next is ordinary neighbour stuff: show up, lend a hand, ask when you are stuck. ' +
            'No audience. Just the people on your few streets.',
        heroImage: 'trellisafter.png',
        heroAlt: 'The same trellis now covered in a thriving, fruiting vine.',
        iconFile: null
    },
    {
        id: 'say-hi',
        track: TRACK_FINALE,
        progressIndex: 1,
        advance: 'introPost',
        placement: 'center',
        hideVine: true,
        hideProgressLabel: true,
        title: 'Say hi to your street',
        body:
            'Here is the first small thing: say hi to your street. ' +
            'You do not have to arrive with something to give — asking for help is where trust starts too. ' +
            'Trust is not installed; it grows, one ordinary act at a time.',
        iconFile: 'BioActive.png'
    }
];

export function getFilteredSteps(options = {}) {
    const { includeExtended = false, includeFinale = true, hasMultipleIdentities = true } = options;
    return TOUR_STEPS.filter((step) => {
        if (step.track === TRACK_EXTENDED && !includeExtended) {
            return false;
        }
        if (step.track === TRACK_FINALE && !includeFinale) {
            return false;
        }
        if (step.skipWhenSingleIdentity && !hasMultipleIdentities) {
            return false;
        }
        return true;
    });
}

export function getProgressLabel(step, stepIndex, steps, trackPhase) {
    if (step.hideProgressLabel) {
        return '';
    }
    if (step.track === TRACK_EXTENDED) {
        const extendedSteps = steps.filter((s) => s.track === TRACK_EXTENDED);
        const idx = extendedSteps.findIndex((s) => s.id === step.id) + 1;
        return `${idx} / ${extendedSteps.length}`;
    }
    if (step.progressIndex) {
        return `${step.progressIndex} / 5`;
    }
    return '';
}

export function getVineStage(step, trackPhase) {
    if (step?.hideVine || !step?.progressIndex) {
        return null;
    }
    return Math.min(5, Math.max(1, step.progressIndex));
}
