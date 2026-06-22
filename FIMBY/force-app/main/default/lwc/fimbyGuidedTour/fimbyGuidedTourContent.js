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
            'What if your street felt a little more like family: people who know your name, ' +
            'notice when life is heavy, and make room at the table? FIMBY is small on purpose: ' +
            'just the few streets around you. It is the trellis; you and your neighbours are what grows.',
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
            'Need and gift sit side by side here. Shared Life is for stories, thanks, prayer, ' +
            'and small updates. Ask & Offer is for practical neighbour help. ' +
            'Quiet for now? Someone gets to be first.',
        mobileBody:
            'Need and gift sit side by side here. Shared Life is for stories, thanks, prayer, ' +
            'and small updates. Ask & Offer is for practical neighbour help.',
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
            'Asking is not failure here; it is where trust starts.',
        actionLabel: 'Open Create',
        modalAnchor: 'quick-post-modal',
        modalActionLabel: 'Browse sharing options',
        modalActionSublabel: 'Select one or close to continue',
        hideModalCoach: true,
        modalCalloutOnly: true,
        modalCalloutFixedTop: true,
        revealTitle: 'You found the sharing menu',
        revealBody:
            'These six options are always here when you tap Create. ' +
            'Tap Next when you are ready to keep going.',
        revealNavigateTitle: 'Off to a good start',
        revealNavigateBody:
            'You opened a sharing path. Finish when you like, then tap Next here to continue.',
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
            'The library helps abundance circulate: the drill down the block before another trip to the store. ' +
            'Borrowing works because this is a trusted local circle. ' +
            'That is what your setup vouch helps protect.',
        mobileBody:
            'The library helps abundance circulate: the drill down the block before another trip to the store.',
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
            'Quiet inbox? Normal at first. Your first hello may start here.',
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
            'No ads, no likes, no followers. You are never the product, and your data is never sold. ' +
            'FIMBY is local by design: a doorbell, not an endless feed.',
        iconFile: 'NeighborhoodActive.png'
    },
    {
        id: 'off-ramp',
        track: TRACK_ESSENTIALS,
        advance: 'offRampChoice',
        placement: 'center',
        hideVine: true,
        title: 'You are ready to explore',
        body: 'You know the daily loop now. Want a quick look at notifications, search, and your account?',
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
        body: 'A gentle nudge when a neighbour reaches out. Not a feed begging to be scrolled.',
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
            'Search is always nearby when you need it. Find neighbours, offers, or skills anytime. ' +
            'Tap Next when you are ready to continue.',
        revealNavigateTitle: 'Nice — you searched',
        revealNavigateBody:
            'Search results open on their own page. Come back here and tap Next when you are ready.',
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
        body:
            'The less-daily stuff lives here: profile, settings, your posts, and a few useful corners.',
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
        body: 'Add enough of yourself that neighbours know who they are talking to. No performance needed.',
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
        body: 'You control how close people get: quiet hours, what you share, and who can reach you.',
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
            'Some neighbours need help using an app: kids, elders, or anyone who needs support. ' +
            'Manage Identities lets a trusted person act with them or for them, so the circle stays open.',
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
        body: 'Your posts, items, offers, and history, all in one place.',
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
        showFinishOnly: true,
        title: 'The backyard is yours',
        body:
            'You have the lay of the land now: feed, library, messages, settings, the lot. ' +
            'What grows next is ordinary neighbour stuff: show up, lend a hand, ask when you are stuck. ' +
            'No audience. Just your few streets.',
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
            'Start small: say hi to your street. You do not have to arrive with something impressive. ' +
            'Ask for help, offer something simple, or just introduce yourself. ' +
            'Trust grows one ordinary act at a time.',
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
