/**
 * Live guided tour step definitions — Essentials and Extended.
 * Copy: universal warmth tone; vision woven per step.
 */

export const TRACK_ESSENTIALS = 'essentials';
export const TRACK_EXTENDED = 'extended';

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
        fromOnboardingTitle: 'Welcome in',
        fromOnboardingBodyPrefix:
            'Your profile is ready — neighbours can get to know you now. ',
        heroImage: 'trellisbefore.png',
        heroAlt: 'A garden trellis with a young vine just starting to climb.',
        iconFile: null
    },
    {
        id: 'feed-filters',
        track: TRACK_ESSENTIALS,
        progressIndex: 1,
        vineStage: 1,
        advance: 'clickTarget',
        anchor: 'feed-filter-bar',
        placement: 'bottom',
        title: 'Your home feed',
        body:
            'Our lives sit side by side here. Shared Life is for thanks, prayer, ' +
            'and small updates. Ask & Offer is for practical neighbour help.',
        mobileBody:
            'Our lives sit side by side here. Shared Life is for thanks, prayer, ' +
            'and small updates. Ask & Offer is for practical neighbour help.',
        actionLabel: 'Try a filter',
        iconFile: 'StoriesInactive.png',
        clickAdvanceOn: ['story', 'askOffer']
    },
    {
        id: 'create',
        track: TRACK_ESSENTIALS,
        progressIndex: 2,
        vineStage: 2,
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
        revealBody: 'Tap Next when you are ready to keep going.',
        iconFile: 'add.png',
        modalEvent: 'fimbyopenquickpost'
    },
    {
        id: 'library',
        track: TRACK_ESSENTIALS,
        progressIndex: 3,
        vineStage: 3,
        advance: 'clickTarget',
        anchor: 'nav-library',
        waitAnchor: 'library-filter-bar',
        route: '/library-list',
        placement: 'top',
        title: 'Borrow the drill',
        body:
            'The library helps abundance circulate — the drill down the block before another trip to the store. ' +
            'Browse what neighbours list anytime. When you are ready to borrow, someone who knows you vouches first; ' +
            'that is how we keep this a trusted local circle, not a free-for-all.',
        mobileBody:
            'The library helps abundance circulate — browse anytime. When you are ready to borrow, ' +
            'a neighbour vouches that they know you.',
        actionLabel: 'Open Library',
        iconFile: 'ToolboxActive.png'
    },
    {
        id: 'messages',
        track: TRACK_ESSENTIALS,
        progressIndex: 4,
        vineStage: 3,
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
        vineStage: 4,
        advance: 'next',
        placement: 'center',
        title: 'Different by design',
        body:
            'No ads, no likes, no followers. You are never the product, and your data is never sold. ' +
            'FIMBY is local by design: a doorbell, not an endless feed.',
        iconFile: 'NeighborhoodActive.png'
    },
    {
        id: 'everyday-trust',
        track: TRACK_ESSENTIALS,
        advance: 'offRampChoice',
        placement: 'center',
        vineStage: 5,
        hideProgressLabel: true,
        title: 'That is the whole thing',
        body:
            'A tool shared. A message answered. A name remembered. ' +
            'Nothing fancy — just neighbours showing up for each other.',
        iconFile: null
    },
    {
        id: 'open-menu',
        track: TRACK_EXTENDED,
        vineStage: 2,
        advance: 'clickTarget',
        anchor: 'nav-menu',
        placement: 'bottom',
        title: 'Everything else',
        body:
            'Profile, settings, and a few useful corners live here — less-daily stuff, always nearby.',
        actionLabel: 'Open Menu',
        iconFile: 'Kebab.png'
    },
    {
        id: 'account-controls',
        track: TRACK_EXTENDED,
        vineStage: 3,
        advance: 'next',
        anchor: 'menu-account',
        placement: 'bottom',
        menuGuided: true,
        title: 'You and your settings',
        body:
            'Profile is where neighbours get to know you. Settings is where you choose quiet hours, ' +
            'sharing, and who can reach you. Both live here in the menu.',
        actionLabel: 'Profile & Settings',
        iconFile: 'ProfileActive.png',
        mobileBubbleTop: true
    },
    {
        id: 'manage-identities',
        track: TRACK_EXTENDED,
        vineStage: 4,
        advance: 'next',
        anchor: 'menu-manage-identities',
        placement: 'bottom',
        menuGuided: true,
        title: 'No one left out',
        body:
            'Some neighbours need help using an app: kids, elders, or anyone who needs support. ' +
            'Manage Identities lets a trusted person act with them or for them, so no one is left out.',
        actionLabel: 'Manage Identities',
        iconFile: 'people.png',
        menuCalloutAbove: true,
        route: '/manage-identities'
    },
    {
        id: 'your-corner',
        track: TRACK_EXTENDED,
        vineStage: 5,
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
            'Small things, close to home, building a neighbourhood with room to hold us all.',
        heroImage: 'trellisafter.png',
        heroAlt: 'The same trellis now covered in a thriving, fruiting vine.',
        iconFile: null
    }
];

export function getFilteredSteps(options = {}) {
    const { includeExtended = false, hasMultipleIdentities = true } = options;
    return TOUR_STEPS.filter((step) => {
        if (step.track === TRACK_EXTENDED && !includeExtended) {
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
        return `${step.progressIndex} / 4`;
    }
    return '';
}

export function getVineStage(step) {
    if (!step || step.hideVine || step.id === 'welcome' || !step.vineStage) {
        return null;
    }
    return step.vineStage;
}
