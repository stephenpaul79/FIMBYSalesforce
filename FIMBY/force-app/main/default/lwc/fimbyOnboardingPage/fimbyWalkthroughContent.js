/**
 * Walkthrough content for fimbyOnboardingPage Phase 2.
 *
 * 5 hard-coded screens (Phase 3 / Screen 6 - the "say hi" intro post -
 * is delegated to the fimbyIntroPostModal LWC and is not in this array).
 *
 * Photos hot-link to fimby.com WordPress media library.
 * Icons reference Impact_Icons static resource via the ${IMPACT_ICONS}
 * base URL substituted at runtime by the page LWC's renderer.
 *
 * Layouts:
 *   hero-text  - single hero image + title + body (Screens 1, 3, 5)
 *   feed-mock  - inline UI mock + title + body (Screen 2)
 *   carousel   - 2 slides, each with its own layout (Screen 4)
 *
 * All visual assets are sourced from existing FIMBY HTML or static
 * resources - nothing invented. See the plan for citation map.
 */

const FIMBY_PHOTO_BASE = 'https://fimby.com/wp-content/uploads';

export const PHOTOS = {
    trellis: `${FIMBY_PHOTO_BASE}/2026/03/Ivy.jpg`,
    tomatoSeedlings: `${FIMBY_PHOTO_BASE}/2026/05/tomatoseedlings.png`,
    pressureWasher: `${FIMBY_PHOTO_BASE}/2026/03/pressurewasher.jpg`,
    kitchenMixer: `${FIMBY_PHOTO_BASE}/2026/03/mixer.jpg`
};

export const SCREEN_IDS = {
    VISION: 'vision',
    FEED: 'feed',
    ASK_OFFER: 'ask-offer',
    SHARED_LIFE_EVENTS: 'shared-life-events',
    LIBRARY: 'library'
};

export const WALKTHROUGH_SCREENS = [
    {
        id: SCREEN_IDS.VISION,
        layout: 'hero-text',
        title: 'Welcome to your neighbourhood.',
        subtitle: 'Not a feed. Not a marketplace. A small, real place.',
        body:
            "FIMBY is the people on your street &mdash; not a city, not the internet. " +
            "You'll see the same neighbours over time. Names become familiar. " +
            "Small acts of care start to build real relationships. That's the whole point.",
        heroPhoto: PHOTOS.trellis,
        heroPhotoAlt: 'A garden trellis with climbing vines - the FIMBY visual metaphor for neighbourhood life growing together.'
    },
    {
        id: SCREEN_IDS.FEED,
        layout: 'feed-mock',
        title: 'Find your way around.',
        body:
            "Your home feed is the bulletin board for the street. Filter by " +
            "<strong>Shared Life</strong> for stories, prayers and thank-yous, or " +
            "<strong>Ask &amp; Offer</strong> for practical needs.<br/><br/>" +
            "You've got your nav &mdash; <strong>Home</strong>, " +
            "<strong>Library</strong>, the big plus to post, <strong>Messages</strong>, " +
            "and <strong>My Stuff</strong> &mdash; alongside Notifications, Search, and Menu.",
        sampleCardPhoto: PHOTOS.tomatoSeedlings,
        sampleCardPhotoAlt: 'Tomato seedlings on a windowsill - sample neighbour offer in the feed mock.'
    },
    {
        id: SCREEN_IDS.ASK_OFFER,
        layout: 'hero-text',
        title: 'Tap the plus. Share what\'s on your mind.',
        body:
            "<strong>Make an Ask</strong> when you need a hand. " +
            "<strong>Make an Offer</strong> when you have something to give. " +
            "<strong>Bulk Buy</strong> to split a Costco run with the block.<br/><br/>" +
            "Asks track responses, offers do too, and bulk buys keep track of who " +
            "reserved which share. Nobody gets lost."
    },
    {
        id: SCREEN_IDS.SHARED_LIFE_EVENTS,
        layout: 'carousel',
        slides: [
            {
                id: 'shared-life',
                title: 'Share more than logistics.',
                body:
                    "Some moments aren't asks or offers &mdash; they're a thank-you, " +
                    "a prayer request, a hard week, a small piece of your story. " +
                    "<strong>Shared Life</strong> holds those.<br/><br/>" +
                    "Post a <strong>Thank You</strong>, a <strong>Prayer</strong>, " +
                    "a <strong>Lament</strong>, or a <strong>Neighbourhood Moment</strong>. " +
                    "Your neighbours can comment."
            },
            {
                id: 'events',
                title: 'Three ways to gather.',
                body:
                    "A <strong>Gathering</strong> is small and hosted &mdash; neighbours RSVP, " +
                    "you control the guest list. An <strong>Open Event</strong> is bigger " +
                    "&mdash; a block party or cleanup day, anyone can tap <em>I'm Going</em>. " +
                    "A <strong>Community Event</strong> is something happening nearby that " +
                    "you want neighbours to know about.<br/><br/>" +
                    "Same plus button. Pick the shape that fits."
            }
        ]
    },
    {
        id: SCREEN_IDS.LIBRARY,
        layout: 'hero-text',
        title: 'Borrow the drill. Skip the hardware store.',
        body:
            "The lending library is tools, kitchen gear, books &mdash; things your " +
            "neighbours already have and are willing to share. Browse by category, " +
            "request a loan, return it when you're done.<br/><br/>" +
            "A borrowed ladder is often how trust starts.",
        footerNote:
            "To start borrowing, a neighbour just needs to vouch that they know you. " +
            "We'll walk you through that on the Library page.",
        navHint: 'Find the library here, anytime.',
        libraryCards: [
            {
                photo: PHOTOS.pressureWasher,
                photoAlt: 'Pressure washer available to borrow from neighbour Huy N.',
                owner: 'Huy N.',
                itemName: 'Pressure washer',
                category: 'Tools',
                badgeToken: 'driftwood'
            },
            {
                photo: PHOTOS.kitchenMixer,
                photoAlt: 'KitchenAid stand mixer available to borrow from neighbour Sarah P.',
                owner: 'Sarah P.',
                itemName: 'KitchenAid Stand mixer',
                category: 'Kitchen',
                badgeToken: 'sage'
            }
        ]
    }
];

export const SHARED_LIFE_PILLS = [
    { type: 'Thank You', label: 'Thank You', iconFile: 'ThankYouActive.png' },
    { type: 'Prayer', label: 'Prayer', iconFile: 'PrayActive.png' },
    { type: 'Lament', label: 'Lament', iconFile: 'LamentActive.png' },
    { type: 'Neighbourhood Moment', label: 'Neighbourhood', iconFile: 'tulips.png' }
];

// Sample posts shown inside the phone-frame for Slide 4a (Shared Life).
// Card colours mirror FIMBY_CONFIG.STORY_TYPE_COLORS in fimbyHomeFeed.js.
// Body text adapted from the FIMBY website's home.html preview shell.
export const SHARED_LIFE_PHONE_POSTS = [
    {
        id: 'thankyou-rosa',
        initials: 'RL',
        name: 'Rosa L.',
        time: '2 days ago',
        badgeLabel: 'THANK YOU',
        badgeEmoji: '\u{1F64C}', // raising hands
        badgeColor: 'rgba(176, 114, 72, 0.9)', // Thank You copper
        accentColor: 'var(--fimby-earth-ochre, #7D6234)',
        body: "Kids were sick all week and Huy watched them so I could run errands. I almost cried in the grocery store."
    },
    {
        id: 'prayer-kim',
        initials: 'KW',
        name: 'Kim W.',
        time: 'Yesterday',
        badgeLabel: 'PRAYER',
        badgeEmoji: '\u{1F64F}', // praying hands
        badgeColor: 'rgba(126, 116, 149, 0.9)', // Prayer lavender
        accentColor: 'var(--fimby-earth-ochre, #7D6234)',
        title: 'Big week ahead',
        body: "Surgery on Thursday. If you've got a quiet moment, please think of us."
    }
];

export const EVENT_TIERS = [
    {
        id: 'gathering',
        title: 'Gathering',
        description: 'A dinner party, game night, or small get-together. Neighbours RSVP and you control the guest list.',
        tierTag: 'RSVP \u00B7 Capacity',
        iconFile: 'dining-table.png'
    },
    {
        id: 'open-event',
        title: 'Open Event',
        description: "A block party or cleanup day. Anyone can tap I'm Going - no capacity cap, no guest list.",
        tierTag: 'Casual \u00B7 Open',
        iconFile: 'people.png'
    },
    {
        id: 'community-event',
        title: 'Community Event',
        description: "Something happening nearby that you want neighbours to know about. Read-only interest list.",
        tierTag: 'Share \u00B7 Interest',
        iconFile: 'cityscape.png'
    }
];

export const QUICK_POST_TILES = [
    { type: 'Ask', label: 'Make an Ask', iconFile: 'needsm.png' },
    { type: 'Offer', label: 'Make an Offer', iconFile: 'giftsm.png' },
    { type: 'Event', label: 'Post an Event', iconFile: 'plannersm.png' },
    { type: 'BulkBuy', label: 'Bulk Buy', iconFile: 'bulkbuy.png' },
    { type: 'Story', label: 'Share in Shared Life', iconFile: 'StoriesActive.png' },
    { type: 'Lend', label: 'Lend an Item', iconFile: 'ToolboxActive.png' }
];

export const NAV_ITEMS = [
    { id: 'home', label: 'Home', iconFile: 'NeighborhoodActive.png', isActive: true },
    { id: 'library', label: 'Library', iconFile: 'ToolboxInactive.png' },
    { id: 'create', label: 'Create', iconFile: 'add.png', isCreateButton: true },
    { id: 'messages', label: 'Messages', iconFile: 'SpeechBubbleInactive.png' },
    { id: 'mine', label: 'My Stuff', iconFile: 'ProfileInactive.png' }
];

export const HEADER_ACTIONS = [
    // Bell intentionally uses the active variant so the phone-frame mockup
    // reads as a live app with something waiting in notifications.
    { id: 'bell', label: 'Notifications', iconFile: 'BellActive.png' },
    { id: 'search', label: 'Search', iconFile: 'Magnify.png' },
    { id: 'menu', label: 'Menu', iconFile: 'Kebab.png' }
];

export const FEED_FILTER_PILLS = [
    { id: 'all', label: 'All', iconFile: 'NeighborhoodActive.png', isActive: true },
    { id: 'shared-life', label: 'Shared Life', iconFile: 'StoriesInactive.png' },
    { id: 'ask-offer', label: 'Ask & Offer', iconFile: 'BulletinBoardInactive.png' }
];
