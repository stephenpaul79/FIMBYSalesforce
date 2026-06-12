import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPageReference, getUrl, resolveTabFromPath, startNavTiming, endNavTiming } from 'c/fimbyNavigation';
import basePath from '@salesforce/community/basePath';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getBadgeCounts from '@salesforce/apex/FimbyCommunicationController.getBadgeCounts';
import recordAppOpen from '@salesforce/apex/FimbyContactController.recordAppOpen';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import switchIdentity from '@salesforce/apex/FimbySupportRelationshipController.switchIdentity';
import switchToSelf from '@salesforce/apex/FimbySupportRelationshipController.switchToSelf';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import { getModeratorContext } from 'c/fimbyModeratorContext';

const LOGO_FILE = 'FIMBYwGrass.png';
const LOGO_SQUARE = 'FwithGrass.png';
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

    /* --- Lifecycle ------------------------------------------------- */

    _lastAppOpenTs = 0;

    // Reactive active-tab highlight. Because soft navigation keeps this header
    // mounted, the highlight can no longer be set once in connectedCallback —
    // it must recompute whenever the current page changes. CurrentPageReference
    // fires on every (soft or hard) navigation. Also closes out nav-timing.
    @wire(CurrentPageReference)
    wiredPageRef() {
        this.activeTab = this._detectActiveTab();
        endNavTiming();
    }

    connectedCallback() {
        this.activeTab = this._detectActiveTab();
        this._hydrateBadgeCountsFromCache();
        this._pollBadgeCounts();
        this._recordAppOpenAndSyncQuietHours();
        this._checkOnboarding();
        this._loadIdentityContext();
        this._loadModeratorContext();

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
    }

    disconnectedCallback() {
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
        } catch (e) { /* ignore corrupt/unavailable cache */ }
    }

    _writeBadgeCountsToCache() {
        try {
            sessionStorage.setItem(BADGE_CACHE_KEY, JSON.stringify({
                notifications: this.notificationCount,
                messages: this.messageCount
            }));
        } catch (e) { /* ignore unavailable storage */ }
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
            .catch(() => { /* silent */ });
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
        this.showTosModal = actingResult.tosReacceptanceRequired === true
            && actingResult.isActingAsSelf === true;
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
        this.showTosModal = false;
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
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Unable to switch',
                    message: error?.body?.message || 'Something went wrong. Please try again.',
                    variant: 'error',
                    mode: 'pester'
                }));
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
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Unable to switch back',
                    message: error?.body?.message || 'Something went wrong. Please try again.',
                    variant: 'error',
                    mode: 'pester'
                }));
            });
    }

    handleManageIdentitiesClick() {
        this.showMenuOverlay = false;
        location.href = '/manage-identities';
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
        location.href = '/moderator-dashboard';
    }

    _clearFeedCaches() {
        try {
            sessionStorage.removeItem('fimby-home-feed-state');
            sessionStorage.removeItem('fimby-library-state');
        } catch (e) { /* ignore */ }
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
        } catch (e) {
            return 'home';
        }
    }

    /* ---------------------------------------------------------------
     * Icon URL getters
     * --------------------------------------------------------------- */
    _iconUrl(tab) {
        const icons = TAB_ICONS[tab];
        const file = this.activeTab === tab ? icons.active : icons.inactive;
        return `${IMPACT_ICONS}/${file}`;
    }

    get homeIconUrl()     { return this._iconUrl('home'); }
    get libraryIconUrl()  { return this._iconUrl('library'); }
    get messagesIconUrl() { return this._iconUrl('messages'); }
    get mineIconUrl()     { return this._iconUrl('mine'); }

    /* --- Active-state indicator classes ----------------------------- */

    get homeIndicator()     { return this.activeTab === 'home'     ? 'desktop-indicator active' : 'desktop-indicator'; }
    get libraryIndicator()  { return this.activeTab === 'library'  ? 'desktop-indicator active' : 'desktop-indicator'; }
    get messagesIndicator() { return this.activeTab === 'messages' ? 'desktop-indicator active' : 'desktop-indicator'; }
    get mineIndicator()     { return this.activeTab === 'mine'     ? 'desktop-indicator active' : 'desktop-indicator'; }

    /* --- Active CSS class on desktop nav items ---------------------- */

    get homeDesktopClass()     { return this.activeTab === 'home'     ? 'desktop-nav-item active' : 'desktop-nav-item'; }
    get libraryDesktopClass()  { return this.activeTab === 'library'  ? 'desktop-nav-item active' : 'desktop-nav-item'; }
    get messagesDesktopClass() { return this.activeTab === 'messages' ? 'desktop-nav-item active' : 'desktop-nav-item'; }
    get mineDesktopClass()     { return this.activeTab === 'mine'     ? 'desktop-nav-item active' : 'desktop-nav-item'; }

    get hasUnreadMessages() { return this.messageCount > 0; }

    /* --- Desktop nav click handler --------------------------------- */

    handleNavClick(event) {
        const selectedTab = event.currentTarget.dataset.tab;
        this.activeTab = selectedTab;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { tab: selectedTab } }));
        this.navigateToPage(selectedTab);
    }

    /* --- Header action handlers ------------------------------------ */

    handleLogoClick() {
        this.navigateToPage('home');
    }

    handleNewClick() {
        const quickPostForm = this.template.querySelector('c-fimby-quick-post-form');
        if (quickPostForm) {
            quickPostForm.show();
        }
    }

    handleQuickPostClose() {
        // Modal closed
    }

    get searchOverlayClass() {
        return this.showSearchModal
            ? 'search-overlay search-overlay-visible'
            : 'search-overlay search-overlay-hidden';
    }

    handleSearchClick() {
        this.searchModalTerm = '';
        this.showSearchModal = true;
        const input = this.template.querySelector('[data-id="search-modal-input"]');
        if (input) input.focus();
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
    }

    handleSearchModalClick(event) {
        event.stopPropagation();
    }

    _navigateToSearchResults() {
        const term = encodeURIComponent(this.searchModalTerm.trim());
        this.showSearchModal = false;
        location.href = '/search?q=' + term;
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
            location.href = `/organization-profile?id=${this._orgAccountId}`;
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

    handleLogoutClick() {
        this.showMenuOverlay = false;
        const sitePrefix = basePath.replace(/\/s$/i, '');
        const logoutUrl = sitePrefix + '/secur/logout.jsp';
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
            location.href = getUrl(tab);
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
        this.activeTab = tab;
    }

    /* --- App-open tracking + quiet hours sync ----------------------- */

    _recordAppOpenAndSyncQuietHours() {
        this._lastAppOpenTs = Date.now();
        recordAppOpen()
            .then(result => {
                if (result?.quietHoursPreference && window.ReactNativeWebView) {
                    window.ReactNativeWebView.postMessage(
                        JSON.stringify({
                            type: 'quietHours',
                            window: result.quietHoursPreference
                        })
                    );
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
        // Replay tour entry point. Onboarding lives on a dedicated page; flag-driven
        // routing inside fimbyOnboardingPage decides whether to land on Phase 1 or
        // Phase 2 based on the user's existing onboarding state.
        window.location.href = '/onboarding';
    }
}