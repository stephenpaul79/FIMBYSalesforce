import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import ICONS from '@salesforce/resourceUrl/Icons';
import { navigate } from 'c/fimbyNavigation';
import getAppPromptConfig from '@salesforce/apex/FimbyAppPromptController.getAppPromptConfig';

const STORAGE_KEY = 'fimby.appPrompt.v1';
const MS_PER_DAY = 86400000;

export default class FimbyAppPrompt extends NavigationMixin(LightningElement) {
    @track _show = false;
    @track _config = null;

    _previouslyFocused = null;
    _keydownHandler = null;

    get appIconUrl() {
        return `${ICONS}/FIMBYIcon.png`;
    }

    get platformBadgeUrl() {
        if (this.isIOS) return `${ICONS}/app-store-badge.png`;
        if (this.isAndroid) return `${ICONS}/google-play-badge.png`;
        return null;
    }

    get platformBadgeAlt() {
        if (this.isIOS) return 'Download FIMBY on the App Store';
        if (this.isAndroid) return 'Get FIMBY on Google Play';
        return 'Get the FIMBY app';
    }

    get isInFimbyApp() {
        try {
            const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
            if (ua.indexOf('FIMBY-WebView') !== -1) return true;
            if (typeof window !== 'undefined' && window.__FIMBY_NATIVE_APP__ === true) return true;
        } catch {
            // assume not in app on any UA read failure
        }
        return false;
    }

    get isIOS() {
        const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
        return /iPad|iPhone|iPod/.test(ua) && !/FIMBY-WebView/.test(ua);
    }

    get isAndroid() {
        const ua = (typeof navigator !== 'undefined' && navigator.userAgent) || '';
        return /Android/i.test(ua);
    }

    get isMobileBrowser() {
        return this.isIOS || this.isAndroid;
    }

    get platformStoreUrl() {
        if (!this._config) return null;
        if (this.isIOS) return this._config.iosStoreUrl;
        if (this.isAndroid) return this._config.androidStoreUrl;
        return null;
    }

    get hasStoreUrl() {
        const url = this.platformStoreUrl;
        return typeof url === 'string' && url.length > 0;
    }

    @wire(getAppPromptConfig)
    wiredConfig({ data }) {
        if (!data) return;
        this._config = data;
        this.evaluateGates();
    }

    connectedCallback() {
        // Belt-and-braces: also evaluate after the wire result settles, in case
        // wired data races with mount. evaluateGates() is cheap and idempotent.
        this.evaluateGates();
    }

    disconnectedCallback() {
        this.removeKeydownTrap();
    }

    evaluateGates() {
        if (this._show) return;
        if (!this._config) return;
        if (!this._config.enabled) return;
        if (this.isInFimbyApp) return;
        if (!this.isMobileBrowser) return;
        if (!this.hasStoreUrl) return;

        const state = this.readState();
        if (state.converted) return;

        const cooldownMs = (this._config.cooldownDays || 0) * MS_PER_DAY;
        if (state.lastShownAt && cooldownMs > 0) {
            const elapsed = Date.now() - state.lastShownAt;
            if (elapsed < cooldownMs) return;
        }

        this._show = true;
        this.installKeydownTrap();
        this.captureFocus();
    }

    readState() {
        try {
            const raw = window.localStorage.getItem(STORAGE_KEY);
            if (!raw) return {};
            const parsed = JSON.parse(raw);
            return parsed && typeof parsed === 'object' ? parsed : {};
        } catch {
            return {};
        }
    }

    writeState(next) {
        try {
            const merged = Object.assign({}, this.readState(), next);
            window.localStorage.setItem(STORAGE_KEY, JSON.stringify(merged));
        } catch {
            // localStorage unavailable (private mode, quota, etc.) — fail soft;
            // the modal will simply re-appear on the next mount.
        }
    }

    handleDismiss = () => {
        this.writeState({ lastShownAt: Date.now() });
        this.close();
    };

    handleGetTheApp = () => {
        const url = this.platformStoreUrl;
        this.writeState({ lastShownAt: Date.now(), converted: true });
        this.close();
        if (url) {
            navigate(this, url);
        }
    };

    handleBackdropClick = (event) => {
        // Only treat clicks directly on the backdrop as a dismiss — clicks that
        // bubble up from the dialog itself stop in handleDialogClick.
        if (event.target === event.currentTarget) {
            this.handleDismiss();
        }
    };

    handleDialogClick = (event) => {
        event.stopPropagation();
    };

    close() {
        this._show = false;
        this.removeKeydownTrap();
        this.restoreFocus();
    }

    captureFocus() {
        try {
            this._previouslyFocused = (typeof document !== 'undefined') ? document.activeElement : null;
        } catch {
            this._previouslyFocused = null;
        }
        // Defer until the dialog is in the DOM, then move focus into the primary CTA.
        Promise.resolve().then(() => {
            const primary = this.template.querySelector('.app-prompt-cta-primary');
            if (primary && typeof primary.focus === 'function') {
                primary.focus();
            }
        });
    }

    restoreFocus() {
        const target = this._previouslyFocused;
        this._previouslyFocused = null;
        if (target && typeof target.focus === 'function') {
            try { target.focus(); } catch { /* element may have been removed */ }
        }
    }

    installKeydownTrap() {
        if (this._keydownHandler) return;
        this._keydownHandler = (event) => {
            if (event.key === 'Escape' || event.keyCode === 27) {
                event.preventDefault();
                this.handleDismiss();
            }
        };
        if (typeof window !== 'undefined') {
            window.addEventListener('keydown', this._keydownHandler);
        }
    }

    removeKeydownTrap() {
        if (this._keydownHandler && typeof window !== 'undefined') {
            window.removeEventListener('keydown', this._keydownHandler);
        }
        this._keydownHandler = null;
    }
}
