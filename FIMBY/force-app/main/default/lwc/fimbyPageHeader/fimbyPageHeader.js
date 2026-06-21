import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate, navigateBack } from 'c/fimbyNavigation';

export default class FimbyPageHeader extends NavigationMixin(LightningElement) {
    _pageTitle = '';
    _pageSubtitle = '';
    @api parentLabel = '';
    @api parentUrl = '';
    @api showSearch = false;
    @api showNotifications = false;
    @api showProgress = false;
    _progressValue = 0;
    @track hasNotifications = false;

    @api get pageTitle() { return this._pageTitle; }
    set pageTitle(value) { this._pageTitle = value || ''; }

    @api get pageSubtitle() { return this._pageSubtitle; }
    set pageSubtitle(value) { this._pageSubtitle = value || ''; }

    @api get progressValue() { return this._progressValue; }
    set progressValue(value) { this._progressValue = value || 0; }

    @api menuItems = [];

    /* Back button (active) */
    _showBack = false;
    @api get showBack() { return this._showBack; }
    set showBack(value) { this._showBack = this._coerceBool(value); }
    @api get showBackButton() { return this._showBack; }
    set showBackButton(value) { this._showBack = this._coerceBool(value); }

    /* Deprecated — kept as harmless no-ops for org-level references */
    @api showMenu = false;
    @api showCustomAction = false;
    @api customActionIcon = '';
    @api customActionImageUrl = '';
    @api customActionVariant = '';

    _coerceBool(value) {
        if (typeof value === 'boolean') return value;
        if (typeof value === 'string') return value.toLowerCase() === 'true';
        return !!value;
    }

    @track _menuOpen = false;
    @track _isDesktop = false;
    @track _menuTop = 0;
    @track _menuRight = 0;

    _mediaQuery;
    _boundKeyDown;

    get hasParent() { return !!this.parentLabel; }
    get progressStyle() { return `width: ${this.progressValue}%`; }
    get searchIconUrl() { return `${IMPACT_ICONS}/Magnify.png`; }
    get notificationIconUrl() { return `${IMPACT_ICONS}/BellActive.png`; }

    /* ── Three-tier menu item resolution ─────────────── */

    get _resolvedItems() {
        if (!this.menuItems || !Array.isArray(this.menuItems) || this.menuItems.length === 0) return [];
        return this.menuItems.map(item => ({
            ...item,
            iconUrl: item.icon ? `${IMPACT_ICONS}/${item.icon}` : '',
            inlineBtnClass: this._inlineBtnClass(item),
            dropdownItemClass: this._dropdownItemClass(item)
        }));
    }

    get inlineItems() {
        return this._resolvedItems.filter(i => i.display === 'inline');
    }

    get responsiveItems() {
        return this._resolvedItems.filter(i => i.display === 'responsive');
    }

    get kebabOnlyItems() {
        return this._resolvedItems.filter(i => i.display === 'kebab');
    }

    get dropdownItems() {
        if (this._isDesktop) return this.kebabOnlyItems;
        return this._resolvedItems.filter(i => i.display === 'responsive' || i.display === 'kebab');
    }

    get showKebab() {
        return this.dropdownItems.length > 0;
    }

    get kebabExpanded() {
        return this._menuOpen ? 'true' : 'false';
    }

    get menuPositionStyle() {
        return `top: ${this._menuTop}px; right: ${this._menuRight}px;`;
    }

    _inlineBtnClass(item) {
        let cls = 'menu-inline-btn';
        if (item.display === 'responsive') cls += ' responsive-only';
        if (item.variant === 'primary') cls += ' primary';
        if (item.variant === 'danger') cls += ' danger';
        return cls;
    }

    _dropdownItemClass(item) {
        let cls = 'menu-dropdown-item';
        if (item.variant === 'danger') cls += ' danger';
        return cls;
    }

    /* ── Lifecycle ───────────────────────────────────── */

    connectedCallback() {
        this._mediaQuery = window.matchMedia('(min-width: 768px)');
        this._isDesktop = this._mediaQuery.matches;
        this._mediaQuery.addEventListener('change', this._handleMediaChange);
        this._boundKeyDown = this._handleKeyDown.bind(this);
    }

    disconnectedCallback() {
        if (this._mediaQuery) {
            this._mediaQuery.removeEventListener('change', this._handleMediaChange);
        }
        document.removeEventListener('keydown', this._boundKeyDown);
    }

    _handleMediaChange = (e) => {
        this._isDesktop = e.matches;
        if (this._menuOpen) this._closeMenu();
    }

    /* ── Kebab dropdown ──────────────────────────────── */

    handleKebabToggle() {
        if (this._menuOpen) {
            this._closeMenu();
        } else {
            this._openMenu();
        }
    }

    _openMenu() {
        const btn = this.template.querySelector('.kebab-trigger');
        if (btn) {
            const rect = btn.getBoundingClientRect();
            this._menuTop = rect.bottom + 4;
            this._menuRight = window.innerWidth - rect.right;
        }
        this._menuOpen = true;
        document.addEventListener('keydown', this._boundKeyDown);
        Promise.resolve().then(() => {
            const firstItem = this.template.querySelector('.menu-dropdown-item');
            if (firstItem) firstItem.focus();
        });
    }

    _closeMenu() {
        this._menuOpen = false;
        document.removeEventListener('keydown', this._boundKeyDown);
        const btn = this.template.querySelector('.kebab-trigger');
        if (btn) btn.focus();
    }

    _handleKeyDown(e) {
        if (e.key === 'Escape') {
            e.stopPropagation();
            this._closeMenu();
        }
    }

    handleMenuClose() {
        this._closeMenu();
    }

    handleMenuItemClick(event) {
        const key = event.currentTarget.dataset.key;
        if (this._menuOpen) this._closeMenu();
        this.dispatchEvent(new CustomEvent('menuaction', { detail: { key } }));
    }

    /* ── Preserved event handlers ────────────────────── */

    handleBackClick() {
        const backEvent = new CustomEvent('back', { cancelable: true });
        const notCancelled = this.dispatchEvent(backEvent);
        if (!notCancelled) return;

        navigateBack(this, this.parentUrl || null);
    }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    handleSearchClick() {
        this.dispatchEvent(new CustomEvent('search', { detail: { action: 'search' } }));
    }

    handleNotificationClick() {
        this.dispatchEvent(new CustomEvent('notification', { detail: { action: 'notification' } }));
    }

    /* ── Public imperative API (preserved) ───────────── */

    @api
    setNotificationStatus(hasNotifications) {
        this.hasNotifications = hasNotifications;
    }

    @api
    updateProgress(value) {
        this._progressValue = Math.max(0, Math.min(100, value));
    }

    @api
    setTitle(title, subtitle = '') {
        this._pageTitle = title;
        this._pageSubtitle = subtitle;
    }
}