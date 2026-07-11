import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { fireToast } from 'c/fimbyToastHelper';
import { getPageReference, getUrl, resolveTabFromPath, startNavTiming, endNavTiming, navigate } from 'c/fimbyNavigation';
import { registerTourAnchorProvider } from 'c/fimbyGuidedTourAnchorRegistry';
import { GUIDED_TOUR_REQUEST_EVENT } from 'c/fimbyGuidedTourLauncher';
import getLiveTourState from '@salesforce/apex/FimbyGuidedTourController.getLiveTourState';

const TOUR_PENDING_SESSION_KEY = 'fimby_tour_pending';
import basePath from '@salesforce/community/basePath';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getBadgeCounts from '@salesforce/apex/FimbyCommunicationController.getBadgeCounts';
import recordAppOpen from '@salesforce/apex/FimbyContactController.recordAppOpen';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import switchIdentity from '@salesforce/apex/FimbySupportRelationshipController.switchIdentity';
import switchToSelf from '@salesforce/apex/FimbySupportRelationshipController.switchToSelf';
import endAllSessions from '@salesforce/apex/FimbySessionController.endAllSessions';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import { getModeratorContext } from 'c/fimbyModeratorContext';

const LOGO_FILE = 'FIMBYwGrass.png';
const LOGO_SQUARE = 'FwithGrass.png';
const LOGO_EGG_TAP_COUNT = 3;
const LOGO_EGG_WINDOW_MS = 1000;
const LOGO_HOME_DELAY_MS = 400;
const SYSTEM_PROFILE_PATH = '/system-profile';
const CREATE_ICON = 'add.png';
const BELL_ACTIVE = 'BellActive.png';
const BELL_INACTIVE = 'BellInactive.png';
const SEARCH_ICON = 'Magnify.png';
const MENU_ICON = 'Kebab.png';

const BADGE_COOLDOWN_MS = 30000;
const BADGE_CACHE_KEY = 'fimby-badge-counts';

// Re-record an "app open" (and re-sync quiet hours) only after the session has
// been backgrounded for at least this long, so a quick tab-away doesn't inflate
// the metric. With the persistent shell the header mounts once per session, so
// the resume path is what keeps long-lived sessions registering real opens.
const APP_OPEN_RESUME_THRESHOLD_MS = 1800000; // 30 minutes

const MENU_ICONS = {
    profile:  'ProfileActive.png',
    settings: 'gear.png',
    help:     'lightbulb.png',
    feedback: 'feedback.png',
    logout:   'deactivation.png',
    switch:   'switch.png',
    people:   'people.png'
};

const MAX_KEBAB_IDENTITIES = 3;
const NO_PROFILE_PHOTO = 'NoProfilePhoto.png';
const NO_ORG_PHOTO = 'NoOrgPhoto.png';

/* Tab-prefix → tab mapping now lives in c/fimbyNavigation (resolveTabFromPath). */

/* Icon file-name map (inside the Impact_Icons static resource zip) */
const TAB_ICONS = {
    home:     { active: 'NeighborhoodActive.png',  inactive: 'NeighborhoodInactive.png' },
    library:  { active: 'ToolboxActive.png',        inactive: 'ToolboxInactive.png' },
    messages: { active: 'SpeechBubbleActive.png',   inactive: 'SpeechBubbleInactive.png' },
    mine:     { active: 'ProfileActive.png',        inactive: 'ProfileInactive.png' }
};

export default class FimbyUniversalHeader extends NavigationMixin(LightningElement) {
    @api activeTab = 'home';
    @track _activeTab = 'home';
    @track hasUnread = false;
    @track messageCount = 0;
    @track hasNotifications = false;
    @track notificationCount = 0;
    @track showMenuOverlay = false;
    @track showSearchModal = false;
    @track searchModalTerm = '';

    @track isActingAsSelf = true;
    @track actingAsDisplayName = '';
    @track actingAsAvatarUrl = '';
    @track selfMenuItem = null;
    @track otherIdentityMenuItems = [];
    @track identitiesLoading = false;
    @track _identitySwitching = false;
    _identitiesLoaded = false;
    _actingAsContactId = null;
    @track _isOrgContact = false;
    @track _orgAccountId = null;
    @track _isModerator = false;
    @track _moderatorTaskCount = 0;
    @track showTosModal = false;
    @track hasPriorTosAcceptance = false;
    // Start true so the opaque cover is up from the shell's first paint, before
    // the async TOS check resolves — otherwise the feed flashes for a beat on a
    // cold load. Cleared (fail-open) once getActingAsContact returns or errors.
    @track _tosGatePending = true;
    _savedBodyOverflow = null;

    _guidedTourRequestHandler;
    _tourOpenMenuHandler;
    _tourOpenSearchHandler;
    _unregisterTourAnchors;
    _autostartChecked = false;

    /* --- Lifecycle ------------------------------------------------- */

    _lastAppOpenTs = 0;
    _logoTapCount = 0;
    _lastLogoTap = 0;
    _logoHomeTimer = null;

    // Reactive active-tab highlight. Because soft navigation keeps this header
    // mounted, the highlight can no longer be set once in connectedCallback —
    // it must recompute whenever the current page changes. CurrentPageReference
    // fires on every (soft or hard) navigation. Also closes out nav-timing.
    // Guard so the native kettle-handoff signal fires exactly once per shell
    // mount. We want it on first paint of this header — the opaque
    // fimby-tos-modal-backdrop is already covering the DOM by then, so the
    // native shell can safely dissolve the kettle without a flash of unstyled
    // content. The old post-Apex signal added a 500ms–2s network round-trip
    // to the perceived load time. See renderedCallback below.
    _shellReadySent = false;

    @wire(CurrentPageReference)
    wiredPageRef() {
        this._activeTab = this._detectActiveTab();
        endNavTiming();
    }

    renderedCallback() {
        if (this._shellReadySent) return;
        this._shellReadySent = true;
        this._notifyNativeShellReady();
    }

    connectedCallback() {
        this._activeTab = this._detectActiveTab();
        this._hydrateBadgeCountsFromCache();
        this._pollBadgeCounts();
        this._recordAppOpenAndSyncQuietHours();
        this._checkOnboarding();
        this._loadIdentityContext();
        // Lock scroll immediately: _tosGatePending is true until the check above
        // resolves, so the opaque cover is already holding the screen.
        this._applyScrollLock();
        this._loadModeratorContext();

        // Global zoom lock. The header is mounted once in the persistent shell,
        // so this single attach covers every surface. The class drives the
        // touch-action rule (Android + double-tap); the gesture* listeners are
        // iOS WKWebView-only and stay idle on Android. The photo lightbox owns
        // its own contained zoom (touch-action: none + JS transform), unaffected
        // because it reads raw touch points rather than these browser gestures.
        document.documentElement.classList.add('fimby-zoom-locked');
        this._blockPinch = (event) => event.preventDefault();
        document.addEventListener('gesturestart', this._blockPinch, { passive: false });
        document.addEventListener('gesturechange', this._blockPinch, { passive: false });
        document.addEventListener('gestureend', this._blockPinch, { passive: false });

        this._openQuickPostHandler = () => this.handleNewClick();
        window.addEventListener('fimbyopenquickpost', this._openQuickPostHandler);

        this._refreshRequestHandler = () => this._pollBadgeCounts();
        window.addEventListener('fimbyrequestbadgerefresh', this._refreshRequestHandler);

        this._visibilityHandler = () => {
            if (document.visibilityState === 'visible') {
                this._pollBadgeCountsIfStale();
                this._recordAppOpenOnResume();
            }
        };
        document.addEventListener('visibilitychange', this._visibilityHandler);

        // The native app shell dispatches this when it returns to the
        // foreground after an absence. visibilitychange is unreliable in iOS
        // WKWebView after long background, so this bridges that gap. Older app
        // builds never dispatch it, so the listener simply stays idle.
        this._appResumedHandler = () => {
            this._pollBadgeCountsIfStale();
            this._recordAppOpenOnResume();
        };
        window.addEventListener('fimby-app-resumed', this._appResumedHandler);

        this._guidedTourRequestHandler = (event) => {
            this._startGuidedTour({
                replay: !!event?.detail?.replay,
                fromOnboarding: !!event?.detail?.fromOnboarding
            });
        };
        window.addEventListener(GUIDED_TOUR_REQUEST_EVENT, this._guidedTourRequestHandler);

        this._tourOpenMenuHandler = () => this.openMenuOverlay();
        this._tourCloseMenuHandler = () => this.handleMenuClose();
        this._tourOpenSearchHandler = () => this.handleSearchClick();
        window.addEventListener('fimbytouropenmenu', this._tourOpenMenuHandler);
        window.addEventListener('fimbytourclosemenu', this._tourCloseMenuHandler);
        window.addEventListener('fimbytouropensearch', this._tourOpenSearchHandler);

        this._unregisterTourAnchors = registerTourAnchorProvider(this);
        this._maybeAutostartLiveTour();
    }

    disconnectedCallback() {
        if (this._blockPinch) {
            document.removeEventListener('gesturestart', this._blockPinch, { passive: false });
            document.removeEventListener('gesturechange', this._blockPinch, { passive: false });
            document.removeEventListener('gestureend', this._blockPinch, { passive: false });
            document.documentElement.classList.remove('fimby-zoom-locked');
            this._blockPinch = null;
        }
        if (this._openQuickPostHandler) {
            window.removeEventListener('fimbyopenquickpost', this._openQuickPostHandler);
        }
        if (this._refreshRequestHandler) {
            window.removeEventListener('fimbyrequestbadgerefresh', this._refreshRequestHandler);
        }
        if (this._visibilityHandler) {
            document.removeEventListener('visibilitychange', this._visibilityHandler);
        }
        if (this._appResumedHandler) {
            window.removeEventListener('fimby-app-resumed', this._appResumedHandler);
        }
        if (this._guidedTourRequestHandler) {
            window.removeEventListener(GUIDED_TOUR_REQUEST_EVENT, this._guidedTourRequestHandler);
        }
        if (this._tourOpenMenuHandler) {
            window.removeEventListener('fimbytouropenmenu', this._tourOpenMenuHandler);
        }
        if (this._tourCloseMenuHandler) {
            window.removeEventListener('fimbytourclosemenu', this._tourCloseMenuHandler);
        }
        if (this._tourOpenSearchHandler) {
            window.removeEventListener('fimbytouropensearch', this._tourOpenSearchHandler);
        }
        if (this._unregisterTourAnchors) {
            this._unregisterTourAnchors();
        }
        if (this._logoHomeTimer) {
            clearTimeout(this._logoHomeTimer);
            this._logoHomeTimer = null;
        }
        if (this._savedBodyOverflow !== null) {
            document.body.style.overflow = this._savedBodyOverflow;
            this._savedBodyOverflow = null;
        }
    }

    @api
    getTourAnchorRect(name) {
        if (name === 'search-modal' && !this.showSearchModal) {
            return null;
        }
        const el = this.template.querySelector(`[data-tour="${name}"]`);
        if (!el) {
            return null;
        }
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 ? rect : null;
    }

    @api
    openMenuOverlay() {
        this.showMenuOverlay = true;
        this._loadAvailableIdentitiesIfNeeded();
    }

    async _maybeAutostartLiveTour() {
        if (this._autostartChecked) {
            return;
        }
        this._autostartChecked = true;
        if (this._activeTab !== 'home') {
            return;
        }
        try {
            const state = await getLiveTourState();
            const tourPending = this._hasTourPendingFlag();
            if (state?.autostartEligible && tourPending) {
                this._startGuidedTour({ replay: false, fromOnboarding: true });
            }
        } catch (err) {
            console.error('fimbyUniversalHeader autostart live tour', err);
        }
    }

    _hasTourPendingFlag() {
        try {
            return sessionStorage.getItem(TOUR_PENDING_SESSION_KEY) === '1';
        } catch {
            return false;
        }
    }

    _startGuidedTour(options) {
        const tour = this.template.querySelector('c-fimby-guided-tour');
        if (tour?.startTour) {
            tour.startTour(options);
        }
    }

    /**
     * Tab navigation triggers a full page reload (location.href), which tears
     * down and rebuilds this header. Without a primed value the bell renders
     * BellInactive first, then swaps to BellActive once the async badge fetch
     * returns — a visible flash on every navigation. Reading the last-known
     * counts synchronously on mount lets the bell render in its correct state
     * immediately; the background poll then reconciles any change.
     */
    _hydrateBadgeCountsFromCache() {
        try {
            const cached = sessionStorage.getItem(BADGE_CACHE_KEY);
            if (!cached) return;
            const counts = JSON.parse(cached);
            this.notificationCount = counts.notifications || 0;
            this.hasNotifications = this.notificationCount > 0;
            this.messageCount = counts.messages || 0;
            this.hasUnread = this.messageCount > 0;
        } catch { /* ignore corrupt/unavailable cache */ }
    }

    _writeBadgeCountsToCache() {
        try {
            sessionStorage.setItem(BADGE_CACHE_KEY, JSON.stringify({
                notifications: this.notificationCount,
                messages: this.messageCount
            }));
        } catch { /* ignore unavailable storage */ }
    }

    _pollBadgeCounts() {
        this._lastBadgeFetch = Date.now();
        getBadgeCounts()
            .then(result => {
                this.notificationCount = result.notifications || 0;
                this.hasNotifications = this.notificationCount > 0;
                this.messageCount = result.messages || 0;
                this.hasUnread = this.messageCount > 0;
                this._writeBadgeCountsToCache();
                this._broadcastCounts();
            })
            .catch(err => {
                console.error('Error fetching badge counts:', err);
            });
    }

    get notificationBadgeLabel() {
        if (this.notificationCount <= 0) return '';
        return this.notificationCount > 9 ? '9+' : String(this.notificationCount);
    }

    get notificationAriaLabel() {
        const count = this.notificationCount;
        if (count <= 0) return 'Notifications';
        return `Notifications — ${count} unread`;
    }

    get messageBadgeLabel() {
        if (this.messageCount <= 0) return '';
        return this.messageCount > 9 ? '9+' : String(this.messageCount);
    }

    get messagesAriaLabel() {
        const count = this.messageCount;
        if (count <= 0) return 'Messages';
        return `Messages — ${count} unread`;
    }

    _pollBadgeCountsIfStale() {
        if (this._lastBadgeFetch && (Date.now() - this._lastBadgeFetch) < BADGE_COOLDOWN_MS) {
            return;
        }
        this._pollBadgeCounts();
    }

    _broadcastCounts() {
        window.dispatchEvent(new CustomEvent('fimbybadgecounts', {
            detail: {
                hasNotifications: this.hasNotifications,
                notificationCount: this.notificationCount,
                hasUnread: this.hasUnread,
                messageCount: this.messageCount
            }
        }));
    }

    /* --- Logo & Create icon ---------------------------------------- */

    get logoUrl() {
        return this.isActingAsSelf
            ? `${IMPACT_ICONS}/${LOGO_FILE}`
            : `${IMPACT_ICONS}/${LOGO_SQUARE}`;
    }

    get logoImgClass() {
        return this.isActingAsSelf ? 'fimby-logo-img' : 'fimby-logo-img fimby-logo-img-compact';
    }

    get createIconUrl() {
        return `${IMPACT_ICONS}/${CREATE_ICON}`;
    }

    get bellIconUrl() {
        return this.hasNotifications
            ? `${IMPACT_ICONS}/${BELL_ACTIVE}`
            : `${IMPACT_ICONS}/${BELL_INACTIVE}`;
    }

    get searchIconUrl() {
        return `${IMPACT_ICONS}/${SEARCH_ICON}`;
    }

    get menuIconUrl() {
        return `${IMPACT_ICONS}/${MENU_ICON}`;
    }

    get profileMenuIconUrl()  { return `${IMPACT_ICONS}/${MENU_ICONS.profile}`; }
    get settingsMenuIconUrl() { return `${IMPACT_ICONS}/${MENU_ICONS.settings}`; }
    get helpMenuIconUrl()     { return `${IMPACT_ICONS}/${MENU_ICONS.help}`; }
    get feedbackMenuIconUrl() { return `${IMPACT_ICONS}/${MENU_ICONS.feedback}`; }
    get logoutMenuIconUrl()   { return `${IMPACT_ICONS}/${MENU_ICONS.logout}`; }
    get switchIconUrl()       { return `${IMPACT_ICONS}/${MENU_ICONS.switch}`; }
    get peopleIconUrl()       { return `${IMPACT_ICONS}/${MENU_ICONS.people}`; }
    get defaultAvatarUrl()    { return `${IMPACT_ICONS}/${NO_PROFILE_PHOTO}`; }

    get showActingAsChip() { return !this.isActingAsSelf; }
    get hasAvailableIdentities() { return this.otherIdentityMenuItems.length > 0; }
    get actingAsAriaLabel() { return `Acting as ${this.actingAsDisplayName}. Click to switch back.`; }
    get selfIsActive() { return this.selfMenuItem?.isActive ?? true; }
    get switchBackAriaLabel() { return this.selfMenuItem ? `Switch back to ${this.selfMenuItem.name}` : 'Switch back to self'; }

    _loadIdentityContext() {
        getActingAsContact()
            .then((actingResult) => this._applyActingAsContext(actingResult))
            .catch(() => {
                // Fail open: never strand the user behind the pre-decision veil
                // if the identity check fails. Option C (server-side) is the
                // real data gate; this cover is only visual.
                this._tosGatePending = false;
                this._applyScrollLock();
                this._notifyNativeShellReady();
            });
    }

    _applyActingAsContext(actingResult) {
        const selfAvatarUrl = avatarImageUrl(actingResult.realContactAvatarUrl)
            || this.defaultAvatarUrl;
        this.selfMenuItem = {
            name: actingResult.realContactName,
            avatarUrl: selfAvatarUrl,
            isActive: actingResult.isActingAsSelf
        };
        this.isActingAsSelf = actingResult.isActingAsSelf;
        this._tosGatePending = false;
        this._setTosModalVisibility(
            actingResult.tosReacceptanceRequired === true
            && actingResult.isActingAsSelf === true
        );
        this.hasPriorTosAcceptance = actingResult.hasPriorTosAcceptance === true;
        if (!actingResult.isActingAsSelf) {
            this.actingAsDisplayName = actingResult.actingAsContactName;
            this.actingAsAvatarUrl = avatarImageUrl(actingResult.actingAsAvatarUrl)
                || (actingResult.isOrganizationContact
                    ? `${IMPACT_ICONS}/${NO_ORG_PHOTO}`
                    : this.defaultAvatarUrl);
            this._isOrgContact = actingResult.isOrganizationContact === true;
            this._orgAccountId = actingResult.organizationAccountId || null;
        }
        this._actingAsContactId = actingResult.actingAsContactId;
        this._notifyNativeShellReady();
    }

    _loadAvailableIdentitiesIfNeeded() {
        if (this._identitiesLoaded || this.identitiesLoading) {
            return;
        }
        this.identitiesLoading = true;
        getAvailableIdentities()
            .then((identitiesResult) => {
                this._applyAvailableIdentities(identitiesResult);
                this._identitiesLoaded = true;
            })
            .catch(() => { /* silent */ })
            .finally(() => {
                this.identitiesLoading = false;
            });
    }

    _applyAvailableIdentities(identitiesResult) {
        const raw = (identitiesResult || []).map(id => ({
            ...id,
            avatarUrl: avatarImageUrl(id.avatarUrl)
                || (id.type === 'Support_Person'
                    ? `${IMPACT_ICONS}/${NO_PROFILE_PHOTO}`
                    : `${IMPACT_ICONS}/${NO_ORG_PHOTO}`)
        }));

        const actingAsContactId = this._actingAsContactId;
        const activeIdx = this.isActingAsSelf ? -1 : raw.findIndex(id =>
            String(id.targetContactId) === String(actingAsContactId));

        let activeRow = null;
        let others = raw;
        if (activeIdx >= 0) {
            activeRow = { ...raw[activeIdx], isActive: true };
            others = raw.filter((_, i) => i !== activeIdx);
        }

        const seen = new Set();
        const deduped = others.filter(id => {
            const key = id.relationshipId;
            if (seen.has(key)) return false;
            seen.add(key);
            return true;
        });

        this.otherIdentityMenuItems = [];
        if (activeRow) this.otherIdentityMenuItems.push(activeRow);
        const remaining = deduped.slice(0, Math.max(0, MAX_KEBAB_IDENTITIES - this.otherIdentityMenuItems.length));
        remaining.forEach(id => this.otherIdentityMenuItems.push({
            ...id,
            isActive: false,
            switchAriaLabel: `Switch to ${id.name}`
        }));
    }

    handleTosComplete() {
        this._setTosModalVisibility(false);
    }

    // The gate must fully take over the screen: a first-time user must not be
    // able to see or scroll the feed (which renders in the content region behind
    // the shell). showTosCover is true both during the pre-decision hold and
    // while the live modal is shown; the opaque backdrop hides the feed either way.
    get showTosCover() {
        return this._tosGatePending || this.showTosModal;
    }

    _setTosModalVisibility(show) {
        this.showTosModal = show;
        this._applyScrollLock();
    }

    // Lock background scroll whenever the gate covers the screen so the
    // wheel/touch can't move the page underneath. Save/restore the prior value
    // rather than blindly clearing, matching the other FIMBY modals.
    _applyScrollLock() {
        const shouldLock = this._tosGatePending || this.showTosModal;
        if (shouldLock) {
            if (this._savedBodyOverflow === null) {
                this._savedBodyOverflow = document.body.style.overflow;
            }
            document.body.style.overflow = 'hidden';
        } else if (this._savedBodyOverflow !== null) {
            document.body.style.overflow = this._savedBodyOverflow;
            this._savedBodyOverflow = null;
        }
    }

    get tosModalTitle() {
        return this.hasPriorTosAcceptance
            ? 'A quick check-in before you continue'
            : 'Welcome — one step before you join in';
    }

    get tosModalIntro() {
        return this.hasPriorTosAcceptance
            ? 'Our Terms of Service have changed since you last agreed. Please read the current version and confirm you\'re 19 or older to continue.'
            : 'To be part of your neighbourhood on FIMBY, please read our Terms of Service and confirm you\'re 19 or older.';
    }

    handleIdentitySwitch(event) {
        if (this._identitySwitching) return;
        this._identitySwitching = true;
        const relId = event.currentTarget.dataset.id;
        if (!relId) {
            console.error('Identity switch: no relationship ID found on element');
            this._identitySwitching = false;
            return;
        }
        switchIdentity({ relationshipId: relId })
            .then(() => {
                this._clearFeedCaches();
                this.showMenuOverlay = false;
                window.location.href = '/';
            })
            .catch(error => {
                console.error('Identity switch failed:', JSON.stringify(error));
                this._identitySwitching = false;
                fireToast({
                    title: 'Unable to switch',
                    message: error?.body?.message || 'Something went wrong. Please try again.',
                    variant: 'error'
                });
            });
    }

    handleSwitchBack() {
        if (this._identitySwitching) return;
        this._identitySwitching = true;
        switchToSelf()
            .then(() => {
                this._clearFeedCaches();
                this.showMenuOverlay = false;
                window.location.href = '/';
            })
            .catch(error => {
                console.error('Switch back failed:', JSON.stringify(error));
                this._identitySwitching = false;
                fireToast({
                    title: 'Unable to switch back',
                    message: error?.body?.message || 'Something went wrong. Please try again.',
                    variant: 'error'
                });
            });
    }

    handleManageIdentitiesClick() {
        this.showMenuOverlay = false;
        navigate(this, '/manage-identities');
    }

    /* --- Moderator context ----------------------------------------- */

    _loadModeratorContext() {
        getModeratorContext()
            .then(ctx => {
                this._isModerator = ctx.isModerator;
                this._moderatorTaskCount = ctx.taskCount;
            })
            .catch(() => { /* silent — non-moderators see nothing */ });
    }

    get moderatorIconUrl() {
        return this._moderatorTaskCount > 0
            ? `${IMPACT_ICONS}/moderatoractive.png`
            : `${IMPACT_ICONS}/moderatorinactive.png`;
    }

    get hasModeratorTasks() { return this._moderatorTaskCount > 0; }

    get moderatorAriaLabel() {
        const count = this._moderatorTaskCount;
        return count > 0
            ? `Moderator Dashboard — ${count} open task${count !== 1 ? 's' : ''}`
            : 'Moderator Dashboard';
    }

    handleModeratorClick() {
        navigate(this, '/moderator-dashboard');
    }

    _clearFeedCaches() {
        try {
            sessionStorage.removeItem('fimby-home-feed-state');
            sessionStorage.removeItem('fimby-library-state');
        } catch { /* ignore */ }
    }

    /* ---------------------------------------------------------------
     * URL-based active-tab detection
     * --------------------------------------------------------------- */
    _detectActiveTab() {
        try {
            const fullPath = window.location.pathname;
            let pagePath = fullPath;
            if (basePath && fullPath.startsWith(basePath)) {
                pagePath = fullPath.substring(basePath.length);
            }
            if (!pagePath.startsWith('/')) {
                pagePath = '/' + pagePath;
            }
            pagePath = pagePath.split('?')[0].split('#')[0];

            if (pagePath === '/' || pagePath === '' || pagePath === '/home') {
                return 'home';
            }

            return resolveTabFromPath(pagePath);
        } catch {
            return 'home';
        }
    }

    /* ---------------------------------------------------------------
     * Icon URL getters
     * --------------------------------------------------------------- */
    _iconUrl(tab) {
        const icons = TAB_ICONS[tab];
        const file = this._activeTab === tab ? icons.active : icons.inactive;
        return `${IMPACT_ICONS}/${file}`;
    }

    get homeIconUrl()     { return this._iconUrl('home'); }
    get libraryIconUrl()  { return this._iconUrl('library'); }
    get messagesIconUrl() { return this._iconUrl('messages'); }
    get mineIconUrl()     { return this._iconUrl('mine'); }

    /* --- Active-state indicator classes ----------------------------- */

    get homeIndicator()     { return this._activeTab === 'home'     ? 'desktop-indicator active' : 'desktop-indicator'; }
    get libraryIndicator()  { return this._activeTab === 'library'  ? 'desktop-indicator active' : 'desktop-indicator'; }
    get messagesIndicator() { return this._activeTab === 'messages' ? 'desktop-indicator active' : 'desktop-indicator'; }
    get mineIndicator()     { return this._activeTab === 'mine'     ? 'desktop-indicator active' : 'desktop-indicator'; }

    /* --- Active CSS class on desktop nav items ---------------------- */

    get homeDesktopClass()     { return this._activeTab === 'home'     ? 'desktop-nav-item active' : 'desktop-nav-item'; }
    get libraryDesktopClass()  { return this._activeTab === 'library'  ? 'desktop-nav-item active' : 'desktop-nav-item'; }
    get messagesDesktopClass() { return this._activeTab === 'messages' ? 'desktop-nav-item active' : 'desktop-nav-item'; }
    get mineDesktopClass()     { return this._activeTab === 'mine'     ? 'desktop-nav-item active' : 'desktop-nav-item'; }

    get hasUnreadMessages() { return this.messageCount > 0; }

    /* --- Desktop nav click handler --------------------------------- */

    handleNavClick(event) {
        const selectedTab = event.currentTarget.dataset.tab;
        this._activeTab = selectedTab;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { tab: selectedTab } }));
        this.navigateToPage(selectedTab);
    }

    /* --- Header action handlers ------------------------------------ */

    handleLogoClick() {
        const now = Date.now();
        if (now - this._lastLogoTap > LOGO_EGG_WINDOW_MS) {
            this._logoTapCount = 0;
        }
        this._lastLogoTap = now;
        this._logoTapCount += 1;

        if (this._logoHomeTimer) {
            clearTimeout(this._logoHomeTimer);
            this._logoHomeTimer = null;
        }

        if (this._logoTapCount >= LOGO_EGG_TAP_COUNT) {
            this._logoTapCount = 0;
            navigate(this, SYSTEM_PROFILE_PATH);
            return;
        }

        // Defer single-tap home so a quick triple-tap can finish first.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._logoHomeTimer = setTimeout(() => {
            if (this._logoTapCount === 1) {
                this.navigateToPage('home');
            }
            this._logoTapCount = 0;
            this._logoHomeTimer = null;
        }, LOGO_HOME_DELAY_MS);
    }

    handleNewClick() {
        const quickPostForm = this.template.querySelector('c-fimby-quick-post-form');
        if (quickPostForm) {
            quickPostForm.show();
        }
    }

    handleQuickPostClose() {
        // fimbyquickpostclosed is dispatched from fimbyQuickPostForm.hide()
    }

    get searchOverlayClass() {
        return this.showSearchModal
            ? 'search-overlay search-overlay-visible'
            : 'search-overlay search-overlay-hidden';
    }

    handleSearchClick() {
        this.searchModalTerm = '';
        this.showSearchModal = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const input = this.template.querySelector('[data-id="search-modal-input"]');
            if (input) {
                input.focus();
            }
            window.dispatchEvent(new CustomEvent('fimbysearchopened'));
        });
    }

    handleSearchModalInput(event) {
        this.searchModalTerm = event.target.value;
    }

    handleSearchModalKeydown(event) {
        if (event.key === 'Enter' && this.searchModalTerm.trim().length > 0) {
            this._navigateToSearchResults();
        }
        if (event.key === 'Escape') {
            this.showSearchModal = false;
            window.dispatchEvent(
                new CustomEvent('fimbysearchclosed', { detail: { navigatedAway: false } })
            );
        }
    }

    handleSearchModalSubmit() {
        if (this.searchModalTerm.trim().length > 0) {
            this._navigateToSearchResults();
        }
    }

    handleSearchModalClear() {
        this.searchModalTerm = '';
        const input = this.template.querySelector('[data-id="search-modal-input"]');
        if (input) input.focus();
    }

    handleSearchOverlayClick() {
        this.showSearchModal = false;
        window.dispatchEvent(
            new CustomEvent('fimbysearchclosed', { detail: { navigatedAway: false } })
        );
    }

    handleSearchModalClick(event) {
        event.stopPropagation();
    }

    _navigateToSearchResults() {
        const term = encodeURIComponent(this.searchModalTerm.trim());
        this.showSearchModal = false;
        window.dispatchEvent(
            new CustomEvent('fimbysearchclosed', { detail: { navigatedAway: true } })
        );
        navigate(this, '/search?q=' + term);
    }

    handleMenuClick() {
        this.showMenuOverlay = true;
        this._loadAvailableIdentitiesIfNeeded();
    }

    handleMenuClose() {
        this.showMenuOverlay = false;
    }

    handleOverlayClick() {
        this.showMenuOverlay = false;
    }

    handleMenuContentClick(event) {
        event.stopPropagation();
    }

    /* --- Menu item handlers ------------------------------------------ */

    handleProfileClick() {
        this.showMenuOverlay = false;
        if (this._isOrgContact && this._orgAccountId) {
            navigate(this, `/organization-profile?id=${this._orgAccountId}`);
        } else {
            this.navigateToPage('profile');
        }
    }

    handleNotificationsClick() {
        this.showMenuOverlay = false;
        this.navigateToPage('notifications');
    }

    handleSettingsClick() {
        this.showMenuOverlay = false;
        this.navigateToPage('settings');
    }

    handleHelpClick() {
        this.showMenuOverlay = false;
        this.navigateToPage('help-support');
    }

    handleFeedbackClick() {
        this.showMenuOverlay = false;
        this.navigateToPage('feedback');
    }

    async handleLogoutClick() {
        this.showMenuOverlay = false;
        // End every server-side session first so re-entry requires real
        // re-authentication. /secur/logout.jsp only clears the WebView's cookie;
        // the OAuth browser keeps a live session that lets Salesforce silently
        // re-issue an auth code. Deleting the AuthSession records kills the
        // session regardless of which cookie jar holds it. Best-effort — never
        // block the logout redirect on it.
        try {
            await endAllSessions();
        } catch {
            // Swallow: the redirect below still tears down the WebView session.
        }
        const sitePrefix = basePath.replace(/\/s$/i, '');
        const logoutUrl = sitePrefix + '/secur/logout.jsp';
        // In the native app, hand logout to the native shell so it can revoke the
        // app session token and tear down deterministically. This makes a real
        // logout explicit, so the native side never confuses it with a session
        // timeout (which silently re-authenticates). Web falls back to the redirect.
        if (window.ReactNativeWebView) {
            window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'logout' }));
            return;
        }
        window.location.href = logoutUrl;
    }

    /* --- Shared navigation helper ---------------------------------- */

    navigateToPage(tab) {
        startNavTiming(tab);
        // Soft navigation (NavigationMixin) keeps the theme layout mounted and
        // only swaps the content region. Routes with no clean named-page
        // equivalent fall back to location.href through the same chokepoint.
        const pageRef = getPageReference(tab);
        if (pageRef) {
            this[NavigationMixin.Navigate](pageRef);
        } else {
            window.location.href = getUrl(tab);
        }
    }

    /* --- Public API ------------------------------------------------ */

    @api
    updateUnreadCount(count) {
        this.messageCount = count || 0;
        this.hasUnread = this.messageCount > 0;
        this._writeBadgeCountsToCache();
    }

    @api
    updateNotificationCount(count) {
        this.notificationCount = count || 0;
        this.hasNotifications = this.notificationCount > 0;
        this._writeBadgeCountsToCache();
    }

    @api
    setActiveTab(tab) {
        this._activeTab = tab;
    }

    /* --- App-open tracking + quiet hours sync ----------------------- */

    _quietHoursPreference = '10PM_6AM';

    /** Sync quiet-hours pref to the native shell (also signals shell-ready for
     *  the kettle handoff when the WebView bridge is present). */
    _syncQuietHoursToNative() {
        try {
            if (window.ReactNativeWebView) {
                window.ReactNativeWebView.postMessage(
                    JSON.stringify({
                        type: 'quietHours',
                        window: this._quietHoursPreference || '10PM_6AM'
                    })
                );
            }
        } catch {
            // native bridge unavailable (desktop web)
        }
    }

    /** Fired once identity/TOS veil resolves — native keeps the kettle up until
     *  this message so the themed shell paints before the overlay lifts. */
    _notifyNativeShellReady() {
        this._syncQuietHoursToNative();
    }

    _recordAppOpenAndSyncQuietHours() {
        this._lastAppOpenTs = Date.now();
        try {
            const count = parseInt(sessionStorage.getItem('fimby_app_visit_count') || '0', 10) + 1;
            sessionStorage.setItem('fimby_app_visit_count', String(count));
        } catch {
            // ignore
        }
        recordAppOpen()
            .then(result => {
                if (result?.quietHoursPreference) {
                    this._quietHoursPreference = result.quietHoursPreference;
                }
                // Identity may have already posted with the default; refresh storage
                // when the server pref arrives without blocking on recordAppOpen first.
                if (!this._tosGatePending) {
                    this._syncQuietHoursToNative();
                }
            })
            .catch(err => {
                console.error('Error recording app open:', err);
            });
    }

    /**
     * Under the persistent shell the header mounts once per session, so
     * connectedCallback fires recordAppOpen only once. Re-fire it (and re-sync
     * quiet hours) when the WebView returns to the foreground after being
     * backgrounded long enough to count as a genuine new "app open" — this also
     * picks up a mid-session quiet-hours preference change.
     */
    _recordAppOpenOnResume() {
        if (Date.now() - this._lastAppOpenTs >= APP_OPEN_RESUME_THRESHOLD_MS) {
            this._recordAppOpenAndSyncQuietHours();
        }
    }

    /* --- Onboarding ------------------------------------------------ */

    _checkOnboarding() {
        // Auto-show was previously handled by an embedded onboarding modal.
        // Onboarding now lives at /onboarding, and fimbyHomeFeed.connectedCallback
        // redirects users without a completed profile straight there. The header
        // no longer needs to nudge.
    }

    @api
    launchWalkthrough() {
        this._startGuidedTour({ replay: true });
    }
}