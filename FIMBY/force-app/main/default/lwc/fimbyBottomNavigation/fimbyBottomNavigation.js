import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getPageReference, getUrl, resolveTabFromPath, startNavTiming, endNavTiming } from 'c/fimbyNavigation';

const FOOTER_HEIGHT_PX = 72;

/* Tab-prefix → tab mapping now lives in c/fimbyNavigation (resolveTabFromPath). */

/* Icon file-name map (inside the Impact_Icons static resource zip) */
const TAB_ICONS = {
    home:     { active: 'NeighborhoodActive.png',  inactive: 'NeighborhoodInactive.png' },
    library:  { active: 'ToolboxActive.png',        inactive: 'ToolboxInactive.png' },
    messages: { active: 'SpeechBubbleActive.png',   inactive: 'SpeechBubbleInactive.png' },
    mine:     { active: 'ProfileActive.png',        inactive: 'ProfileInactive.png' }
};

const CREATE_ICON = 'add.png';

export default class FimbyBottomNavigation extends NavigationMixin(LightningElement) {
    @api activeTab = 'home';
    @track hasUnread = false;
    @track messageCount = 0;

    /* ---------------------------------------------------------------
     * Lifecycle
     * --------------------------------------------------------------- */
    _resizeHandler;
    _badgeCountHandler;

    // Reactive active-tab highlight under the persistent shell (the footer no
    // longer remounts per navigation, so the tab must recompute on page change).
    @wire(CurrentPageReference)
    wiredPageRef() {
        this.activeTab = this._detectActiveTab();
        endNavTiming();
    }

    connectedCallback() {
        this.activeTab = this._detectActiveTab();
        this._applyBodyPadding();
        this._resizeHandler = () => this._applyBodyPadding();
        window.addEventListener('resize', this._resizeHandler);
        this._badgeCountHandler = (e) => {
            const detail = e.detail || {};
            this.messageCount = detail.messageCount || 0;
            this.hasUnread = this.messageCount > 0 || !!detail.hasUnread;
        };
        window.addEventListener('fimbybadgecounts', this._badgeCountHandler);
    }

    disconnectedCallback() {
        try {
            document.body.style.paddingBottom = '';
            window.removeEventListener('resize', this._resizeHandler);
            if (this._badgeCountHandler) {
                window.removeEventListener('fimbybadgecounts', this._badgeCountHandler);
            }
        } catch (e) {
            // Fail silently
        }
    }

    /* ---------------------------------------------------------------
     * Fixed-footer body-padding (mobile only)
     * --------------------------------------------------------------- */
    _applyBodyPadding() {
        try {
            if (window.innerWidth < 892) {
                const currentPadding = parseInt(document.body.style.paddingBottom, 10) || 0;
                if (currentPadding < FOOTER_HEIGHT_PX) {
                    document.body.style.paddingBottom = FOOTER_HEIGHT_PX + 'px';
                }
            } else {
                document.body.style.paddingBottom = '';
            }
        } catch (e) {
            // Fail silently
        }
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
     * Custom icon URL getters (active/inactive PNGs)
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
    get createIconUrl()   { return `${IMPACT_ICONS}/${CREATE_ICON}`; }

    /* --- Active indicator classes ----------------------------------- */

    get homeIndicator()     { return this.activeTab === 'home'     ? 'nav-indicator active' : 'nav-indicator'; }
    get libraryIndicator()  { return this.activeTab === 'library'  ? 'nav-indicator active' : 'nav-indicator'; }
    get messagesIndicator() { return this.activeTab === 'messages' ? 'nav-indicator active' : 'nav-indicator'; }
    get mineIndicator()     { return this.activeTab === 'mine'     ? 'nav-indicator active' : 'nav-indicator'; }

    /* --- Active CSS class on each nav item container ---------------- */

    get homeItemClass()     { return this.activeTab === 'home'     ? 'nav-item active' : 'nav-item'; }
    get libraryItemClass()  { return this.activeTab === 'library'  ? 'nav-item active' : 'nav-item'; }
    get messagesItemClass() { return this.activeTab === 'messages' ? 'nav-item active' : 'nav-item'; }
    get mineItemClass()     { return this.activeTab === 'mine'     ? 'nav-item active' : 'nav-item'; }

    get hasUnreadMessages() {
        return this.messageCount > 0;
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

    /* --- Navigation handlers --------------------------------------- */

    handleNavClick(event) {
        const selectedTab = event.currentTarget.dataset.tab;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { tab: selectedTab } }));
        this.activeTab = selectedTab;
        this.navigateToPage(selectedTab);
    }

    handleCreateClick() {
        const quickPostForm = this.template.querySelector('c-fimby-quick-post-form');
        if (quickPostForm) {
            quickPostForm.show();
        }
    }

    handleQuickPostClose() {
        // Modal closed
    }

    navigateToPage(tab) {
        startNavTiming(tab);
        // Soft navigation keeps the theme layout mounted; fall back to a hard
        // load only for routes without a named-page equivalent.
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
    }

    @api
    setActiveTab(tab) {
        this.activeTab = tab;
    }
}