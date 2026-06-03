import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import MEMES5 from '@salesforce/resourceUrl/Memes5';
import { fireEmojiConfetti } from 'c/fimbyConfettiHelper';

import getUnifiedFeed from '@salesforce/apex/FimbyHomeController.getUnifiedFeed';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getActiveSeasonalTheme from '@salesforce/apex/FimbyProfileController.getActiveSeasonalTheme';
import updateLastAppVisit from '@salesforce/apex/FimbyProfileController.updateLastAppVisit';
import getCelebrationContext from '@salesforce/apex/FimbyProfileController.getCelebrationContext';
import quickEventResponse from '@salesforce/apex/FimbyResponseController.quickEventResponse';
import isVouchedForBorrowing from '@salesforce/apex/FimbyLibraryController.isVouchedForBorrowing';
import { toExperiencePath } from 'c/fimbyExperienceUrl';
import getOnboardingStatus from '@salesforce/apex/FimbyOnboardingController.getOnboardingStatus';

import Id from '@salesforce/user/Id';

/* ---------------------------------------------------------------
 * Icon maps
 * --------------------------------------------------------------- */
const FILTER_ICONS = {
    all:      { active: 'NeighborhoodActive.png',  inactive: 'NeighborhoodInactive.png' },
    story:    { active: 'StoriesActive.png',        inactive: 'StoriesInactive.png' },
    askOffer: { active: 'BulletinBoardActive.png',  inactive: 'BulletinBoardInactive.png' }
};

/* Story sub-type icons (Level 2 pills) */
const STORY_SUB_ICONS = {
    'Thank You': { active: 'ThankYouActive.png',  inactive: 'ThankYouInactive.png' },
    'God Story': { active: 'GodStoryActive.png',  inactive: 'GodStoryInactive.png' },
    'Prayer':    { active: 'PrayActive.png',       inactive: 'PrayInactive.png' },
    'Lament':    { active: 'LamentActive.png',     inactive: 'LamentInactive.png' },
    'Bio':       { active: 'BioActive.png',         inactive: 'BioInactive.png' },
    'Neighbourhood Moment': { active: 'tulips.png', inactive: 'tulipsInactive.png' }
};

/* Story badge CSS-class map */
const BADGE_CLASS_MAP = {
    'God Story': 'card-type-badge godstory-badge',
    'Thank You': 'card-type-badge thankyou-badge',
    'Lament':    'card-type-badge lament-badge',
    'Prayer':    'card-type-badge prayer-badge',
    'Bio':       'card-type-badge bio-badge',
    'Neighbourhood Moment': 'card-type-badge neighbourhood-badge'
};

/* Earth-tone palette — shared by card accent borders AND badge pills */
const ACCENT_COLORS = {
    'God Story': 'rgba(163, 128, 69, 0.9)',
    'Thank You': 'rgba(176, 114, 72, 0.9)',
    'Lament':    'rgba(94, 123, 146, 0.9)',
    'Prayer':    'rgba(126, 116, 149, 0.9)',
    'Bio':       'rgba(107, 125, 84, 0.9)',
    'Neighbourhood Moment': 'rgba(175, 130, 125, 0.9)'
};

const BADGE_BG_COLORS = {
    ...ACCENT_COLORS,
    'Story':     'rgba(163, 128, 69, 0.9)',
    'askOffer':  'rgba(91, 135, 96, 0.9)',
    'Need':      'rgba(91, 135, 96, 0.9)',
    'Offer':     'rgba(91, 135, 96, 0.9)',
    'Event':           'rgba(68, 142, 158, 0.9)',
    'Community_Event': 'rgba(113, 90, 158, 0.9)',
    'Bulk Buy':        'rgba(168, 132, 78, 0.90)',
    'library':         'rgba(141, 123, 106, 0.9)'
};

/* Level-2 sub-filter definitions */
const STORY_SUB_FILTERS = [
    { value: 'All', label: 'All' },
    { value: 'Thank You', label: "Thank You's" },
    { value: 'God Story', label: 'God Stories' },
    { value: 'Prayer', label: 'Prayers' },
    { value: 'Lament', label: 'Laments' },
    { value: 'Bio', label: 'Bios' },
    { value: 'Neighbourhood Moment', label: 'Neighbourhood' }
];

const ASK_OFFER_SUB_FILTERS = [
    { value: 'All', label: 'All' },
    { value: 'Need', label: 'Asks' },
    { value: 'Offer', label: 'Offers' },
    { value: 'Event', label: 'Events' },
    { value: 'Bulk Buy', label: 'Bulk Buys' }
];

const INITIAL_FETCH_SIZE = 100;
const SCROLL_BATCH_SIZE = 50;
const CACHE_KEY = 'fimby-home-feed-state';
const CACHE_MAX_AGE_MS = 15 * 60 * 1000;
const CACHE_MAX_ITEMS = 100;

/** Apex UnifiedFeedItem fields — used to strip UI-only keys when reprocessing cached rows. */
const RAW_FEED_ITEM_KEYS = [
    'recordId', 'name', 'description', 'feedType', 'itemType', 'category', 'createdDate',
    'postedByName', 'postedByImageUrl', 'imageUrl', 'imageRatio', 'hasImage', 'objectApiName',
    'image2Url', 'image2Ratio', 'image3Url', 'image3Ratio', 'image4Url', 'image4Ratio',
    'typeValue', 'engagementCount', 'recordTypeName', 'totalReserved', 'totalQuantity',
    'ownerShares', 'totalAvailable', 'activeReserverIds', 'isOrgContact', 'orgAccountId',
    'eventDetails', 'location', 'eventType', 'eventLinkUrl', 'ownerContactId', 'realAuthorContactId',
    'isUrgent', 'sourceScope'
];

export default class FimbyHomeFeed extends NavigationMixin(LightningElement) {
    @api pageSize = 15;
    @api showMarketplace;
    @api showLibrary;

    currentUserId = Id;
    organizationId = null;
    currentContactId = null;
    actingAsContactId = null;

    @track _userFirstName = '';
    @track _showWelcomeBack = false;
    @track _showBioBanner = false;
    @track _showIntroPostModal = false;
    @track _welcomeBackText = '';
    @track _seasonalTitle = '';
    @track _memesEnabled = false;
    _greetingInitialized = false;

    @track feedItems = [];
    @track filteredFeedItems = [];
    @track isLoading = false;
    @track hasMoreContent = true;
    @track feedOffset = 0;
    @track totalCount = 0;

    @track showLightbox = false;
    @track lightboxImages = [];
    @track lightboxStartIndex = 0;

    /* Sticky header / scroll-direction detection */
    @track filterHidden = false;
    _lastScrollY = 0;
    _scrollTicking = false;

    loadedRecordIds = new Set();

    /* --- Two-level filter state ------------------------------------ */
    @track activeFilter = 'all';     // L1: 'all', 'story', 'askOffer'
    @track activeSubFilter = 'All';  // L2: 'All', 'Thank You', 'Need', etc.

    /* --- State persistence for back-navigation restore ------------- */
    _pendingScrollY = null;
    _restoredFromCache = false;
    _saveThrottleTimer = null;

    defaultAvatarUrl = `${IMPACT_ICONS}/NoProfilePhoto.png`;

    /* ===============================================================
     * L1 Filter pill getters
     * =============================================================== */
    get stickyFilterClass() {
        return this.filterHidden
            ? 'feed-filter-header filter-hidden'
            : 'feed-filter-header';
    }

    get refreshIconUrl()      { return `${IMPACT_ICONS}/refresh.png`; }
    get bioBannerIconUrl()    { return `${IMPACT_ICONS}/Wave.png`; }
    get showBioBanner()       { return this._showBioBanner; }
    get showIntroPostModal()  { return this._showIntroPostModal; }

    handleOpenBioModal() {
        this._showIntroPostModal = true;
        window.requestAnimationFrame(() => {
            const modal = this.template.querySelector('c-fimby-intro-post-modal');
            if (modal && typeof modal.show === 'function') {
                modal.show();
            }
        });
    }

    handleBioPosted() {
        this._showIntroPostModal = false;
        this._showBioBanner = false;
    }

    handleBioSkipped() {
        this._showIntroPostModal = false;
        this._showBioBanner = false;
    }
    get refreshButtonClass()  { return this.isLoading ? 'refresh-button refreshing' : 'refresh-button'; }

    get allFilterClass()      { return this.activeFilter === 'all'      ? 'filter-button active' : 'filter-button'; }
    get storiesFilterClass()  { return this.activeFilter === 'story'    ? 'filter-button active' : 'filter-button'; }
    get askOfferFilterClass() { return this.activeFilter === 'askOffer' ? 'filter-button active' : 'filter-button'; }

    get allFilterIconUrl()      { return `${IMPACT_ICONS}/${FILTER_ICONS.all[this.activeFilter === 'all' ? 'active' : 'inactive']}`; }
    get storiesFilterIconUrl()  { return `${IMPACT_ICONS}/${FILTER_ICONS.story[this.activeFilter === 'story' ? 'active' : 'inactive']}`; }
    get askOfferFilterIconUrl() { return `${IMPACT_ICONS}/${FILTER_ICONS.askOffer[this.activeFilter === 'askOffer' ? 'active' : 'inactive']}`; }

    /* Badge icons (always active/coloured variant) */
    get storyBadgeIconUrl()    { return `${IMPACT_ICONS}/${FILTER_ICONS.story.active}`; }
    get askOfferBadgeIconUrl() { return `${IMPACT_ICONS}/${FILTER_ICONS.askOffer.active}`; }
    get libraryBadgeIconUrl()  { return `${IMPACT_ICONS}/ToolboxActive.png`; }
    get urgentIconUrl()        { return `${IMPACT_ICONS}/exclamation.png`; }
    get borrowIconUrl()        { return `${IMPACT_ICONS}/borrow.png`; }
    get viewPostIconUrl()      { return `${IMPACT_ICONS}/Magnify.png`; }
    get kebabBeigeIconUrl()    { return `${IMPACT_ICONS}/KebabBeige.png`; }
    get libraryBadgeStyle()    { return `background: ${BADGE_BG_COLORS['library']};`; }

    /* ===============================================================
     * L2 Sub-filter logic
     * =============================================================== */
    get showSubFilters() {
        return this.activeFilter === 'story' || this.activeFilter === 'askOffer';
    }

    get subFilterOptions() {
        const definitions = this.activeFilter === 'story' ? STORY_SUB_FILTERS : ASK_OFFER_SUB_FILTERS;
        return definitions.map(opt => {
            const isActive = this.activeSubFilter === opt.value;
            let iconUrl = null;
            if (this.activeFilter === 'story' && STORY_SUB_ICONS[opt.value]) {
                iconUrl = `${IMPACT_ICONS}/${STORY_SUB_ICONS[opt.value][isActive ? 'active' : 'inactive']}`;
            }
            return {
                ...opt,
                iconUrl,
                cssClass: isActive ? 'filter-button sub-filter active' : 'filter-button sub-filter'
            };
        });
    }

    /* ===============================================================
     * L1 Filter handlers
     * =============================================================== */
    handleFilterAll() {
        this.activeFilter = 'all';
        this.activeSubFilter = 'All';
        this.filterAutoLoadCount = 0;
        this._reloadFeed();
    }

    handleFilterStories() {
        this.activeFilter = 'story';
        this.activeSubFilter = 'All';
        this.filterAutoLoadCount = 0;
        this._reloadFeed();
    }

    handleFilterAskOffer() {
        this.activeFilter = 'askOffer';
        this.activeSubFilter = 'All';
        this.filterAutoLoadCount = 0;
        this._reloadFeed();
    }

    /* ===============================================================
     * L2 Sub-filter handler
     * =============================================================== */
    handleSubFilterClick(event) {
        const value = event.currentTarget.dataset.value;
        if (value === this.activeSubFilter) return;
        this.activeSubFilter = value;
        this.filterAutoLoadCount = 0;
        this._reloadFeed();
    }

    /**
     * Reset and reload the feed from scratch whenever the filter changes.
     * The Apex controller now handles filtering server-side.
     */
    _reloadFeed() {
        this.feedOffset = 0;
        this.feedItems = [];
        this.filteredFeedItems = [];
        this.hasMoreContent = true;
        this.loadedRecordIds = new Set();
        this._clearFeedCache();

        window.scrollTo({ top: 0, behavior: 'smooth' });

        const scrollContainer = this.template.querySelector('c-fimby-infinite-scroll');
        if (scrollContainer && scrollContainer.reset) {
            scrollContainer.reset();
        }

        this.loadMoreContent();
    }

    /* ===============================================================
     * Lifecycle
     * =============================================================== */
    async connectedCallback() {
        // Post-login redirect: any user without a completed profile is steered straight
        // to /onboarding. The walkthrough live there too, but only profile completion
        // controls whether the user can see the home feed at all - replay viewers (who
        // already have profileCompleted = true) bypass this and land on home as normal.
        try {
            const onboardingStatus = await getOnboardingStatus();
            if (onboardingStatus && onboardingStatus.profileCompleted === false) {
                window.location.replace('/onboarding');
                return;
            }
            this._showBioBanner = onboardingStatus && onboardingStatus.bioPostCompleted === false;
        } catch (err) {
            // Non-fatal: if onboarding status fails, render the home feed normally rather
            // than blocking on the redirect check. The banner just won't appear.
            console.error('fimbyHomeFeed: onboarding status check failed', err);
        }

        this._applyUrlFilterParam();
        this._initGreeting();
        await this.getOrganizationIdAsync();

        if (!this._restoreFeedState()) {
            this.loadInitialData();
        } else {
            // Session cache must not pin another user's contact ids — that makes isPoster wrong for everyone.
            this.currentContactId = null;
            this.actingAsContactId = null;
            this._hydrateIdentityAndReprocessFeed();
        }

        this._windowScrollHandler = () => {
            if (!this._scrollTicking) {
                requestAnimationFrame(() => {
                    this._handleScrollDirection();
                    this._throttledSaveFeedState();
                    this._scrollTicking = false;
                });
                this._scrollTicking = true;
            }
        };
        window.addEventListener('scroll', this._windowScrollHandler, { passive: true });

        this._pagehideHandler = () => this._saveFeedState();
        window.addEventListener('pagehide', this._pagehideHandler);

        requestAnimationFrame(() => this._measureHeaderHeight());
    }

    _measureHeaderHeight() {
        const header = document.querySelector('header.sticky-header');
        if (header) {
            const height = header.getBoundingClientRect().height;
            this.template.host.style.setProperty('--sticky-top', `${height}px`);
        }
    }

    disconnectedCallback() {
        if (this._windowScrollHandler) {
            window.removeEventListener('scroll', this._windowScrollHandler);
        }
        if (this._pagehideHandler) {
            window.removeEventListener('pagehide', this._pagehideHandler);
        }
    }

    _handleScrollDirection() {
        const currentY = window.scrollY || window.pageYOffset;
        const delta = currentY - this._lastScrollY;
        const isMobile = window.innerWidth < 768;

        if (isMobile) {
            if (delta > 10 && currentY > 80) {
                this.filterHidden = true;
            } else if (delta < -10) {
                this.filterHidden = false;
            }
        } else {
            this.filterHidden = false;
        }

        this._lastScrollY = currentY;
    }

    /**
     * Read ?filter= query param from the URL so that legacy redirect
     * links (e.g. from deprecated fimbyStoriesFeed / fimbyAskOfferFeed)
     * land on the correct L1 filter.
     */
    _applyUrlFilterParam() {
        try {
            const params = new URLSearchParams(window.location.search);
            const filterParam = params.get('filter');
            if (filterParam === 'story' || filterParam === 'askOffer') {
                this.activeFilter = filterParam;
            }
        } catch (e) {
            // Fail silently
        }
    }

    async getOrganizationIdAsync() {
        try {
            this.organizationId = await getOrganizationId();
        } catch (error) {
            console.error('Error fetching Organization ID:', error);
        }
    }

    async loadInitialData() {
        this.isLoading = true;
        this.feedOffset = 0;
        this.feedItems = [];
        this.filteredFeedItems = [];
        this.hasMoreContent = true;
        this.loadedRecordIds = new Set();
        this._clearFeedCache();

        const scrollContainer = this.template.querySelector('c-fimby-infinite-scroll');
        if (scrollContainer && scrollContainer.reset) {
            scrollContainer.reset();
        }

        try {
            await this.loadNextBatch();
        } catch (error) {
            console.error('Error loading initial data:', error);
            this.showErrorToast('Failed to load feed content');
        } finally {
            this.isLoading = false;
            this.updateScrollContainer();
        }
    }

    /* ===============================================================
     * Data loading — sends filter params to Apex
     * =============================================================== */
    async loadNextBatch() {
        const category = this.activeFilter === 'all' ? null : this.activeFilter;
        const subType  = this.activeSubFilter === 'All' ? null : this.activeSubFilter;
        const effectivePageSize = this.feedOffset === 0 ? INITIAL_FETCH_SIZE : SCROLL_BATCH_SIZE;

        const result = await getUnifiedFeed({
            offset: this.feedOffset,
            pageSize: effectivePageSize,
            category: category,
            subType: subType
        });

        if (result?.currentContactId) {
            this.currentContactId = result.currentContactId;
        }
        if (result?.actingAsContactId) {
            this.actingAsContactId = result.actingAsContactId;
        }

        if (result && result.items && result.items.length > 0) {
            const newItems = result.items.filter(item => {
                if (this.loadedRecordIds.has(item.recordId)) return false;
                return true;
            });

            newItems.forEach(item => this.loadedRecordIds.add(item.recordId));

            const processedItems = this.processItems(newItems);
            this.feedItems = [...this.feedItems, ...processedItems];
            this.feedOffset += result.items.length;
            this.hasMoreContent = result.hasMore;
            this.totalCount = result.totalCount;
            this.applyFilter();
        } else {
            this.hasMoreContent = false;
        }
    }

    /**
     * Pull server identity after restoring cached rows, then re-run processItems so
     * isPoster / RSVP labels match the current viewer (not a previous session user).
     */
    async _hydrateIdentityAndReprocessFeed() {
        try {
            const category = this.activeFilter === 'all' ? null : this.activeFilter;
            const subType = this.activeSubFilter === 'All' ? null : this.activeSubFilter;
            const result = await getUnifiedFeed({
                offset: 0,
                pageSize: 1,
                category,
                subType
            });
            if (result?.currentContactId) {
                this.currentContactId = result.currentContactId;
            }
            if (result?.actingAsContactId) {
                this.actingAsContactId = result.actingAsContactId;
            }
        } catch (e) {
            // Non-fatal; next loadNextBatch will hydrate.
        }
        if (this.feedItems?.length) {
            this.feedItems = this.processItems(this.feedItems.map((fi) => this._toRawFeedItem(fi)));
            this.applyFilter();
        }
    }

    /** Fields that come from Apex UnifiedFeedItem (strip client-only UI keys before reprocessing). */
    _toRawFeedItem(fi) {
        const raw = {};
        RAW_FEED_ITEM_KEYS.forEach((k) => {
            if (Object.prototype.hasOwnProperty.call(fi, k)) {
                raw[k] = fi[k];
            }
        });
        return raw;
    }

    /* ===============================================================
     * Item processing — adds UI flags, badge data, accent colours
     * =============================================================== */
    processItems(items) {
        return items.map(item => {
            const processedImageUrl = this.getCompleteImageUrl(item.imageUrl);
            const aspectRatioStyle = this.calculateAspectRatioStyle(item.imageRatio);
            const isStory = item.feedType === 'story';
            const isAskOffer = item.feedType === 'askOffer';
            const isEvent = isAskOffer && item.typeValue === 'Event';
            const isBulkBuy = isAskOffer && item.recordTypeName === 'Bulk Buy';

            // Build images array for the new multi-image card API
            const images = this._buildImagesArray(item, processedImageUrl);

            // Badge logic (type badge in top-right corner)
            let badgeClass, badgeIconUrl, badgeLabel, badgeBg;
            const STORY_BADGE_LABELS = {
                'Neighbourhood Moment': 'Neighbourhood'
            };
            if (isStory) {
                badgeClass = BADGE_CLASS_MAP[item.itemType] || 'card-type-badge story-badge';
                badgeIconUrl = this._storyBadgeIconUrl(item.itemType);
                badgeLabel = STORY_BADGE_LABELS[item.itemType] || item.itemType || 'Shared Life';
                badgeBg = BADGE_BG_COLORS[item.itemType] || BADGE_BG_COLORS['Story'];
            } else if (isBulkBuy) {
                badgeClass = 'card-type-badge bulk-buy-badge';
                badgeIconUrl = `${IMPACT_ICONS}/bulkbuy.png`;
                badgeLabel = 'BULK BUY';
                badgeBg = BADGE_BG_COLORS['Bulk Buy'];
            } else if (isEvent) {
                const evtType = item.eventType;
                if (evtType === 'Community_Event') {
                    badgeClass = 'card-type-badge community-event-badge';
                    badgeIconUrl = `${IMPACT_ICONS}/cityscape.png`;
                    badgeLabel = 'COMMUNITY EVENT';
                    badgeBg = BADGE_BG_COLORS['Community_Event'] || BADGE_BG_COLORS['Event'];
                } else if (evtType === 'Open_Event') {
                    badgeClass = 'card-type-badge event-badge';
                    badgeIconUrl = `${IMPACT_ICONS}/people.png`;
                    badgeLabel = 'EVENT';
                    badgeBg = BADGE_BG_COLORS['Event'];
                } else if (evtType === 'Gathering') {
                    badgeClass = 'card-type-badge event-badge';
                    badgeIconUrl = `${IMPACT_ICONS}/dining-table.png`;
                    badgeLabel = 'GATHERING';
                    badgeBg = BADGE_BG_COLORS['Event'];
                } else {
                    badgeClass = 'card-type-badge event-badge';
                    badgeIconUrl = `${IMPACT_ICONS}/dining-table.png`;
                    badgeLabel = 'EVENT';
                    badgeBg = BADGE_BG_COLORS['Event'];
                }
            } else if (isAskOffer) {
                badgeClass = 'card-type-badge ask-offer-badge';
                badgeIconUrl = this.askOfferBadgeIconUrl;
                badgeLabel = item.itemType === 'Need' ? 'Ask' : (item.itemType || 'Ask & Offer');
                badgeBg = BADGE_BG_COLORS[item.itemType] || BADGE_BG_COLORS['askOffer'];
            } else if (item.feedType === 'library') {
                badgeBg = BADGE_BG_COLORS['library'];
            }

            // Response pill (footer action)
            let responseLabel, responseIconUrl, engagementLabel;
            if (isStory) {
                responseLabel = 'Comment';
                responseIconUrl = `${IMPACT_ICONS}/comment.png`;
                engagementLabel = 'Comments';
            } else if (isBulkBuy) {
                const isBulkBuyPoster =
                    item.ownerContactId === this.actingAsContactId ||
                    item.realAuthorContactId === this.currentContactId;
                const hasReserved = item.activeReserverIds &&
                    item.activeReserverIds.includes(this.currentContactId);
                if (isBulkBuyPoster) {
                    responseLabel = 'View Post';
                    responseIconUrl = `${IMPACT_ICONS}/Magnify.png`;
                } else if (hasReserved) {
                    responseLabel = 'Reserved - View Details';
                    responseIconUrl = `${IMPACT_ICONS}/complete.png`;
                } else {
                    responseLabel = 'Reserve-A-Share';
                    responseIconUrl = `${IMPACT_ICONS}/buy.png`;
                }
                engagementLabel = null;
            } else if (isEvent) {
                const evtType = item.eventType;
                const alreadyResponded = this.currentContactId && item.activeReserverIds &&
                    item.activeReserverIds.includes(this.currentContactId);
                if (evtType === 'Open_Event') {
                    responseIconUrl = `${IMPACT_ICONS}/people.png`;
                    responseLabel = alreadyResponded ? 'Going' : "I'm Going";
                    engagementLabel = 'going';
                } else if (evtType === 'Community_Event') {
                    responseIconUrl = `${IMPACT_ICONS}/cityscape.png`;
                    responseLabel = alreadyResponded ? 'Interested' : "I'm Interested";
                    engagementLabel = 'interested';
                } else {
                    responseIconUrl = `${IMPACT_ICONS}/dining-table.png`;
                    responseLabel = alreadyResponded ? "RSVP'd" : 'RSVP';
                    engagementLabel = 'RSVPs';
                }
            } else if (isAskOffer) {
                const alreadyResponded = this.currentContactId && item.activeReserverIds &&
                    item.activeReserverIds.includes(this.currentContactId);
                responseLabel = alreadyResponded ? 'Responded' : 'Respond';
                responseIconUrl = `${IMPACT_ICONS}/reply.png`;
                engagementLabel = 'Responses';
            }

            const isOrg = item.isOrgContact === true;

            const hasVisibleImage = item.hasImage === true && !!processedImageUrl && processedImageUrl.trim() !== '';
            const libraryWrapperClass = 'feed-card-wrapper library-announcement'
                + (hasVisibleImage ? ' library-has-image' : ' library-no-image');
            const libraryAvatarClass = isOrg
                ? 'library-listed-avatar-wrap clickable-avatar'
                : 'library-listed-avatar-wrap';

            let responsePillClass = '';
            const userHasResponded = isAskOffer && item.activeReserverIds &&
                item.activeReserverIds.includes(this.currentContactId);
            if (isBulkBuy && userHasResponded) {
                responsePillClass = 'response-pill-reserved';
            } else if (userHasResponded) {
                responsePillClass = 'response-pill-responded';
            }

            let allocationPills = null;
            if (isBulkBuy) {
                const ownerVal = Number(item.ownerShares) || 0;
                const reservedVal = Number(item.totalReserved) || 0;
                const availVal = Number(item.totalAvailable) || 0;
                const taken = ownerVal + reservedVal;
                allocationPills = [
                    { key: 'reserved', label: `${taken} reserved`, cssClass: taken > 0 ? 'alloc-pill-compact alloc-pill-reserved' : 'alloc-pill-compact alloc-pill-reserved alloc-pill-zero' },
                    { key: 'available', label: `${availVal} available`, cssClass: availVal > 0 ? 'alloc-pill-compact alloc-pill-available' : 'alloc-pill-compact alloc-pill-available alloc-pill-zero' }
                ];
            }
            const orgAvatarFallback = `${IMPACT_ICONS}/NoOrgPhoto.png`;
            const avatarUrl = item.postedByImageUrl
                ? this.getCompleteImageUrl(item.postedByImageUrl)
                : (isOrg ? orgAvatarFallback : this.defaultAvatarUrl);
            const orgProfileUrl = isOrg && item.orgAccountId
                ? `/organization/${item.orgAccountId}` : '';

            let eventDateTime = '';
            let eventLocation = '';
            let eventLinkUrl = '';
            if (isEvent && item.eventDetails) {
                const atIdx = item.eventDetails.indexOf(' @ ');
                eventDateTime = atIdx > -1 ? item.eventDetails.substring(0, atIdx) : item.eventDetails;
                eventLocation = item.location || '';
            }
            if (isEvent && item.eventType === 'Community_Event' && item.eventLinkUrl) {
                eventLinkUrl = item.eventLinkUrl;
            }

            const isPoster =
                item.ownerContactId === this.actingAsContactId ||
                item.realAuthorContactId === this.currentContactId;

            if (isPoster) {
                responseLabel = 'View Post';
                responseIconUrl = `${IMPACT_ICONS}/Magnify.png`;
                responsePillClass = 'response-pill-responded';
            }

            return {
                ...item,
                isStory,
                isAskOffer,
                isEvent,
                isBulkBuy,
                isUrgent: isAskOffer && item.isUrgent === true,
                isPoster,
                isNotPoster: !isPoster,
                showCardMenu: !isPoster,
                isLibrary: item.feedType === 'library',
                isOrgPoster: isOrg,
                orgProfileUrl,
                showImage: hasVisibleImage,
                libraryWrapperClass,
                libraryAvatarClass,
                imageUrl: processedImageUrl,
                imageAspectRatio: aspectRatioStyle,
                images: images,
                avatarUrl,
                formattedType: this.formatItemType(item),
                engagementCount: item.engagementCount || 0,
                responseLabel,
                responseIconUrl,
                responsePillClass,
                engagementLabel,
                allocationPills,
                eventDateTime,
                eventLocation,
                eventLinkUrl,
                accentColor: badgeBg || null,
                libraryCardStyle: badgeBg ? `border-left-color: ${badgeBg};` : '',
                badgeClass,
                badgeIconUrl,
                badgeLabel,
                badgeStyle: badgeBg ? `background: ${badgeBg};` : ''
            };
        });
    }

    /**
     * Build a normalised images array from a feed item.
     * AskOffer items can have up to 4 images; stories and library items have 1.
     */
    _buildImagesArray(item, primaryImageUrl) {
        const images = [];
        const altText = item.name || '';

        if (item.feedType === 'askOffer') {
            if (primaryImageUrl) {
                images.push({ url: primaryImageUrl, ratio: item.imageRatio || null, alt: altText });
            }
            if (item.image2Url) {
                const url2 = this.getCompleteImageUrl(item.image2Url);
                if (url2) images.push({ url: url2, ratio: item.image2Ratio || null, alt: altText });
            }
            if (item.image3Url) {
                const url3 = this.getCompleteImageUrl(item.image3Url);
                if (url3) images.push({ url: url3, ratio: item.image3Ratio || null, alt: altText });
            }
            if (item.image4Url) {
                const url4 = this.getCompleteImageUrl(item.image4Url);
                if (url4) images.push({ url: url4, ratio: item.image4Ratio || null, alt: altText });
            }
        } else {
            if (primaryImageUrl) {
                images.push({ url: primaryImageUrl, ratio: item.imageRatio || null, alt: altText });
            }
        }

        return images;
    }

    _storyBadgeIconUrl(storyType) {
        if (STORY_SUB_ICONS[storyType]) {
            return `${IMPACT_ICONS}/${STORY_SUB_ICONS[storyType].active}`;
        }
        return `${IMPACT_ICONS}/${FILTER_ICONS.story.active}`;
    }

    calculateAspectRatioStyle(ratioString) {
        if (!ratioString) return '16 / 9';
        try {
            const parts = ratioString.toUpperCase().split('X');
            const w = parseInt(parts[0], 10);
            const h = parseInt(parts[1], 10);
            if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) return '16 / 9';
            const ratio = w / h;
            let cw = w, ch = h;
            if (ratio > 1.91) { cw = Math.round(h * 1.91); }
            else if (ratio < 0.8) { ch = Math.round(w / 0.8); }
            return `${cw} / ${ch}`;
        } catch (e) {
            return '16 / 9';
        }
    }

    formatItemType(item) {
        if (item.feedType === 'story') {
            const typeMap = {
                'Thank You': '💝 Thank You',
                'God Story': '✨ God Story',
                'Prayer': '🙏 Prayer Request',
                'Bio': '👋 Introduction',
                'Lament': '💙 Support Needed',
                'Neighbourhood Moment': '🌷 Neighbourhood'
            };
            return typeMap[item.itemType] || item.itemType || 'Shared Life';
        } else if (item.feedType === 'askOffer') {
            return item.itemType === 'Need' ? 'Ask' : (item.itemType || 'Post');
        } else if (item.feedType === 'library') {
            return item.category || 'Item';
        }
        return item.itemType || '';
    }

    getCompleteImageUrl(imageUrl) {
        if (!imageUrl) return null;
        if (this.organizationId && imageUrl.includes(this.organizationId)) return imageUrl;
        if (this.organizationId) return imageUrl + this.organizationId;
        return imageUrl;
    }

    getAvatarUrl(imageUrl) {
        if (imageUrl) return this.getCompleteImageUrl(imageUrl);
        return this.defaultAvatarUrl;
    }

    /* ===============================================================
     * Client-side filter application (for the "all" feed view)
     * Server-side filtering is the primary mechanism now.
     * =============================================================== */
    minFilteredItems = 5;
    maxFilterAutoLoadBatches = 3;
    filterAutoLoadCount = 0;

    applyFilter() {
        this.filteredFeedItems = [...this.feedItems];
    }

    get displayFeedItems() {
        return this.feedItems;
    }

    get hasFeedItems() {
        return this.feedItems && this.feedItems.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && this.feedItems.length === 0;
    }

    get emptyStateGifUrl() {
        return this._memesEnabled ? `${MEMES5}/still-waiting.gif` : null;
    }

    get displayHasMoreContent() {
        if (this.feedItems.length === 0 && !this.isLoading) return false;
        return this.hasMoreContent;
    }

    /* ===============================================================
     * Scroll / load handlers
     * =============================================================== */
    handleLoadMore() {
        if (!this.hasMoreContent || this.isLoading) return;
        this.loadMoreContent();
    }

    async loadMoreContent() {
        if (this.isLoading) return;
        this.isLoading = true;
        try {
            await this.loadNextBatch();
        } catch (error) {
            console.error('Error loading more content:', error);
            this.showErrorToast('Failed to load more content');
        } finally {
            this.isLoading = false;
            this.updateScrollContainer();
        }
    }

    handleRefresh() {
        this.loadInitialData();
    }

    handleGetStarted() {
        window.dispatchEvent(new CustomEvent('fimbyopenquickpost'));
    }

    /* ===============================================================
     * Card interactions
     * =============================================================== */
    handleCardClick(event) {
        const cardWrapper = event.currentTarget;
        const recordId = cardWrapper.dataset.recordId;
        const item = this.feedItems.find(i => i.recordId === recordId);
        if (item) this.navigateToDetailPage(item);
    }

    handleCardKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleCardClick(event);
        }
    }

    navigateToDetailPage(item) {
        const detailPages = {
            'story': '/sharedlife',
            'askOffer': '/asks-offers',
            'library': '/library-item'
        };
        const page = detailPages[item.feedType];
        if (page) location.href = `${page}/${item.recordId}`;
    }

    handleStoryComment(event) {
        const cardWrapper = event.target.closest('.feed-card-wrapper');
        const recordId = cardWrapper?.dataset.recordId;
        if (recordId) this._openQuickResponseModal(recordId, 'story');
    }

    handleStoryShare(event) {
        const cardWrapper = event.target.closest('.feed-card-wrapper');
        const recordId = cardWrapper?.dataset.recordId;
        const item = this.feedItems.find(i => i.recordId === recordId);
        if (item) this.shareContent(item);
    }

    handleAskOfferRespond(event) {
        event.stopPropagation();
        const cardWrapper = event.target.closest('.feed-card-wrapper');
        const recordId = cardWrapper?.dataset.recordId;
        if (recordId) this._openQuickResponseModal(recordId, 'askOffer');
    }

    handleAvatarNavigation(event) {
        event.stopPropagation();
        const url = toExperiencePath(event.detail?.url);
        if (url) location.href = url;
    }

    handleCardRespond(event) {
        event.stopPropagation();
        const cardWrapper = event.target.closest('.feed-card-wrapper');
        const recordId = cardWrapper?.dataset.recordId;
        const item = this.feedItems.find(i => i.recordId === recordId);
        if (!item || !recordId) return;

        if (item.isPoster) {
            this.navigateToDetailPage(item);
            return;
        }

        if (item.isStory) {
            this._openQuickResponseModal(recordId, 'story');
        } else if (item.isBulkBuy) {
            if (item.responsePillClass === 'response-pill-reserved') {
                location.href = `/asks-offers/${recordId}`;
            } else {
                this._openQuickResponseModal(recordId, 'bulkBuy');
            }
        } else if (item.isEvent && item.eventType === 'Open_Event') {
            this._openQuickResponseModal(recordId, 'openEvent');
        } else if (item.isEvent && item.eventType === 'Community_Event') {
            this._handleCommunityEventInline(recordId, item);
        } else if (item.isEvent && item.eventType === 'Gathering') {
            this._openQuickResponseModal(recordId, 'gathering');
        } else {
            this._openQuickResponseModal(recordId, 'askOffer');
        }
    }

    handleCardReport(event) {
        event.stopPropagation();
        const cardWrapper = event.target.closest('.feed-card-wrapper');
        const recordId = cardWrapper?.dataset?.recordId;
        if (!recordId) return;
        const item = this.feedItems.find(i => i.recordId === recordId);
        if (!item) return;
        this._openContentReport(recordId, item);
    }

    handleLibraryCardReport(event) {
        event.stopPropagation();
        const recordId = event.currentTarget?.dataset?.recordId;
        if (recordId) {
            this._openContentReport(recordId, { feedType: 'library' });
        }
    }

    _openContentReport(recordId, item) {
        const contentTypeByFeed = {
            story: 'Story',
            askOffer: 'Need_Offer',
            library: 'Library_Item'
        };
        const contentType = contentTypeByFeed[item.feedType];
        if (!contentType) return;
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) {
            modal.show(recordId, contentType);
        }
    }

    handleLibraryAvatarClick(event) {
        const url = toExperiencePath(event.currentTarget.dataset.url);
        if (!url) return;
        event.stopPropagation();
        location.href = url;
    }

    async handleLibraryBorrow(event) {
        event.stopPropagation();
        const cardWrapper = event.target.closest('.feed-card-wrapper');
        const recordId = cardWrapper?.dataset.recordId;
        if (!recordId) return;

        // Vouching gate: settling-in members cannot borrow.
        try {
            const vouched = await isVouchedForBorrowing();
            if (vouched !== true) {
                const gateModal = this.template.querySelector('c-fimby-vouching-required-modal');
                if (gateModal) gateModal.show();
                return;
            }
        } catch (e) {
            console.error('Vouching check error', e);
            return;
        }
        this._openQuickResponseModal(recordId, 'library');
    }

    /* ===============================================================
     * Quick Response Modal
     * =============================================================== */

    _openQuickResponseModal(recordId, responseType) {
        const modal = this.template.querySelector('c-fimby-quick-response-modal');
        if (modal) modal.show(recordId, responseType);
    }

    _communityEventProcessingIds = new Set();

    async _handleCommunityEventInline(recordId, item) {
        if (item.responsePillClass === 'response-pill-responded') {
            location.href = `/asks-offers/${recordId}`;
            return;
        }
        if (this._communityEventProcessingIds.has(recordId)) return;
        this._communityEventProcessingIds.add(recordId);

        const prevLabel = item.responseLabel;
        const prevClass = item.responsePillClass;
        const prevCount = item.engagementCount || 0;

        this.feedItems = this.feedItems.map(fi => {
            if (fi.recordId !== recordId) return fi;
            return {
                ...fi,
                responsePillClass: 'response-pill-responded',
                responseLabel: 'Interested',
                engagementCount: prevCount + 1
            };
        });

        try {
            await quickEventResponse({ eventId: recordId, action: 'respond', guestCount: 1 });
        } catch (error) {
            this.feedItems = this.feedItems.map(fi => {
                if (fi.recordId !== recordId) return fi;
                return {
                    ...fi,
                    responsePillClass: prevClass,
                    responseLabel: prevLabel,
                    engagementCount: prevCount
                };
            });
            this.showErrorToast(error.body?.message || 'Something went wrong.');
        } finally {
            this._communityEventProcessingIds.delete(recordId);
        }
    }

    handleResponseSaved(event) {
        const { recordId, responseType } = event.detail;
        const updateMap = {
            story: (fi) => ({ ...fi, engagementCount: (fi.engagementCount || 0) + 1 }),
            askOffer: (fi) => ({ ...fi, responsePillClass: 'response-pill-responded', responseLabel: 'Responded' }),
            gathering: (fi) => ({ ...fi, responsePillClass: 'response-pill-responded', responseLabel: "RSVP'd" }),
            openEvent: (fi) => ({ ...fi, responsePillClass: 'response-pill-responded', responseLabel: 'Going' }),
            bulkBuy: (fi) => ({ ...fi, responsePillClass: 'response-pill-reserved', responseLabel: 'Reserved' }),
            library: (fi) => ({ ...fi, responsePillClass: 'response-pill-responded', responseLabel: 'Requested' })
        };
        const updater = updateMap[responseType];
        if (!updater) return;

        this.feedItems = this.feedItems.map(fi => {
            if (fi.recordId !== recordId) return fi;
            return updater(fi);
        });
    }

    /* ===============================================================
     * Lightbox (image viewer)
     * =============================================================== */
    handleImageClick(event) {
        const detail = event.detail;
        if (detail && detail.images && detail.images.length > 0) {
            this.lightboxImages = detail.images;
            this.lightboxStartIndex = detail.index || 0;
            this.showLightbox = true;

            // Open the lightbox component after render
            requestAnimationFrame(() => {
                const lb = this.template.querySelector('c-fimby-lightbox');
                if (lb) lb.open(this.lightboxStartIndex);
            });
        }
    }

    handleLightboxClose() {
        this.showLightbox = false;
        this.lightboxImages = [];
        this.lightboxStartIndex = 0;
    }

    shareContent(item) {
        const shareUrl = `${window.location.origin}/${item.feedType}/${item.recordId}`;
        if (navigator.share) {
            navigator.share({ title: item.name, text: item.description, url: shareUrl });
        } else {
            const text = `${item.name}\n\n${item.description || ''}\n\n${shareUrl}`;
            navigator.clipboard.writeText(text).then(() => {
                this.showSuccessToast('Link copied to clipboard!');
            });
        }
    }

    /* ===============================================================
     * Utilities
     * =============================================================== */
    updateScrollContainer() {
        const scrollContainer = this.template.querySelector('c-fimby-infinite-scroll');
        if (scrollContainer) scrollContainer.finishLoading(this.hasMoreContent);
    }

    showSuccessToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success', mode: 'pester' }));
    }

    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error', mode: 'pester' }));
    }

    /* ===============================================================
     * Feed state persistence (sessionStorage)
     * =============================================================== */
    _saveFeedState() {
        if (!this.feedItems || this.feedItems.length === 0) return;
        try {
            const state = {
                feedItems: this.feedItems.slice(0, CACHE_MAX_ITEMS),
                feedOffset: this.feedOffset,
                loadedRecordIds: [...this.loadedRecordIds],
                activeFilter: this.activeFilter,
                activeSubFilter: this.activeSubFilter,
                hasMoreContent: this.hasMoreContent,
                totalCount: this.totalCount,
                scrollY: window.scrollY,
                timestamp: Date.now()
            };
            sessionStorage.setItem(CACHE_KEY, JSON.stringify(state));
        } catch (e) { /* storage unavailable or full */ }
    }

    _throttledSaveFeedState() {
        if (this._saveThrottleTimer) return;
        this._saveThrottleTimer = setTimeout(() => {
            this._saveThrottleTimer = null;
            this._saveFeedState();
        }, 2000);
    }

    _restoreFeedState() {
        try {
            const raw = sessionStorage.getItem(CACHE_KEY);
            if (!raw) return false;

            const state = JSON.parse(raw);
            if (Date.now() - state.timestamp > CACHE_MAX_AGE_MS) {
                sessionStorage.removeItem(CACHE_KEY);
                return false;
            }

            this.feedItems = state.feedItems;
            this.filteredFeedItems = [...state.feedItems];
            this.feedOffset = state.feedOffset;
            this.loadedRecordIds = new Set(state.loadedRecordIds);
            this.activeFilter = state.activeFilter;
            this.activeSubFilter = state.activeSubFilter === 'Services' ? 'All' : state.activeSubFilter;
            this.hasMoreContent = state.hasMoreContent;
            this.totalCount = state.totalCount || 0;

            this._pendingScrollY = state.scrollY;
            this._restoredFromCache = true;
            return true;
        } catch (e) {
            return false;
        }
    }

    _clearFeedCache() {
        try { sessionStorage.removeItem(CACHE_KEY); } catch (e) { /* ignore */ }
    }

    renderedCallback() {
        if (this._pendingScrollY != null && this._restoredFromCache) {
            const scrollContainer = this.template.querySelector('c-fimby-infinite-scroll');
            if (scrollContainer && scrollContainer.restoreState) {
                scrollContainer.restoreState(this.hasMoreContent);
            }

            const savedY = this._pendingScrollY;
            this._pendingScrollY = null;
            this._restoredFromCache = false;
            requestAnimationFrame(() => {
                window.scrollTo(0, savedY);
            });
        }
    }

    /* ===============================================================
     * Greeting + Welcome-Back
     * =============================================================== */
    get greetingText() {
        if (!this._userFirstName) return '';
        const hour = new Date().getHours();
        if (hour >= 5 && hour < 12) return `Good morning, ${this._userFirstName}`;
        if (hour >= 12 && hour < 17) return `Good afternoon, ${this._userFirstName}`;
        if (hour >= 17 && hour < 21) return `Good evening, ${this._userFirstName}`;
        return `Burning the midnight oil, ${this._userFirstName}?`;
    }

    get greetingSubtext() {
        if (this._seasonalTitle) return this._seasonalTitle;
        return '';
    }

    get showWelcomeBack() {
        return this._showWelcomeBack;
    }

    get welcomeBackText() {
        return this._welcomeBackText;
    }

    dismissWelcomeBack() {
        this._showWelcomeBack = false;
    }

    async _initGreeting() {
        if (this._greetingInitialized) return;
        this._greetingInitialized = true;

        try {
            const [actingAs, seasonalTheme, celebCtx] = await Promise.all([
                getActingAsContact(),
                getActiveSeasonalTheme(),
                getCelebrationContext()
            ]);

            if (actingAs?.firstName) {
                this._userFirstName = actingAs.firstName;
            } else if (actingAs?.contactName) {
                this._userFirstName = actingAs.contactName.split(' ')[0];
            }

            if (seasonalTheme?.title) {
                this._seasonalTitle = seasonalTheme.title;
            }

            this._memesEnabled = celebCtx?.memesEnabled !== false;

            const lastVisitStr = localStorage.getItem('fimby-last-visit');
            if (lastVisitStr) {
                const lastVisit = new Date(lastVisitStr);
                const now = new Date();
                const daysSince = Math.floor((now - lastVisit) / (1000 * 60 * 60 * 24));
                if (daysSince >= 3) {
                    this._showWelcomeBack = true;
                    this._welcomeBackText = `Welcome back! Your neighbours have been busy since you were last here.`;
                }
            }

            try { localStorage.setItem('fimby-last-visit', new Date().toISOString()); } catch (_) { /* storage unavailable */ }
            this._throttledUpdateLastAppVisit();

            if (seasonalTheme?.fireOnLogin && celebCtx?.confettiEnabled !== false) {
                this._fireSeasonalConfetti(seasonalTheme);
            }
        } catch (e) {
            // Non-critical
        }
    }

    _throttledUpdateLastAppVisit() {
        const THROTTLE_KEY = 'fimby-last-visit-apex';
        const THROTTLE_MS = 300000; // 5 minutes
        try {
            const last = sessionStorage.getItem(THROTTLE_KEY);
            if (last && (Date.now() - Number(last)) < THROTTLE_MS) {
                return;
            }
            sessionStorage.setItem(THROTTLE_KEY, String(Date.now()));
        } catch (_) { /* storage unavailable -- proceed with the call */ }
        updateLastAppVisit().catch(() => {});
    }

    _fireSeasonalConfetti(theme) {
        const sessionKey = `fimby-seasonal-confetti-${theme.name}`;
        try {
            if (sessionStorage.getItem(sessionKey)) return;
        } catch (_) { /* storage unavailable */ }

        if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

        try {
            let emojis = ['🎉', '🥳', '✨', '💛'];
            if (theme.emojiList) {
                const parsed = theme.emojiList.split(',').map(e => e.trim()).filter(Boolean);
                if (parsed.length > 0) emojis = parsed;
            }

            fireEmojiConfetti({
                emojis,
                style: theme.animationStyle || 'Cannon',
                intensity: 'normal'
            });

            try { sessionStorage.setItem(sessionKey, '1'); } catch (_) { /* storage unavailable */ }
        } catch (e) {
            console.error('Seasonal confetti error', e);
        }
    }
}