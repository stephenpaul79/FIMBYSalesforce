import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fireToast } from 'c/fimbyToastHelper';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import ICONS from '@salesforce/resourceUrl/Icons';
import MEMES4 from '@salesforce/resourceUrl/Memes4';
import getAppPromptConfig from '@salesforce/apex/FimbyAppPromptController.getAppPromptConfig';
import { navigate, navigateBack, navigateToRoute } from 'c/fimbyNavigation';
import { launchGuidedTourReplay } from 'c/fimbyGuidedTourLauncher';
import { fireEmojiConfetti } from 'c/fimbyConfettiHelper';
import getSettingsData from '@salesforce/apex/FimbyProfileController.getSettingsData';
import updateSettingsField from '@salesforce/apex/FimbyProfileController.updateSettingsField';
import updateSettingsToggle from '@salesforce/apex/FimbyProfileController.updateSettingsToggle';
import updatePrivacyPreference from '@salesforce/apex/FimbyProfileController.updatePrivacyPreference';
import triggerPasswordReset from '@salesforce/apex/FimbyProfileController.triggerPasswordReset';
import requestAccountDeletion from '@salesforce/apex/FimbyProfileController.requestAccountDeletion';
import getBlockedContacts from '@salesforce/apex/FimbyConversationController.getBlockedContacts';
import unblockContact from '@salesforce/apex/FimbyConversationController.unblockContact';
import searchNeighboursForBlock from '@salesforce/apex/FimbyConversationController.searchNeighboursForBlock';
import blockContact from '@salesforce/apex/FimbyConversationController.blockContact';

const EMAIL_FREQUENCY_VALUES = [
    { label: 'Daily', value: 'Daily' },
    { label: 'Weekly', value: 'Weekly' },
    { label: 'Never', value: 'Never' }
];

/** Null and legacy 'None' match Never for digest eligibility; normalize for display only. */
function normalizeSummaryEmailFrequency(value) {
    if (!value || value === 'None') {
        return 'Never';
    }
    return value;
}

/** Matches Apex notification gate semantics: null means enabled unless explicitly false. */
function isNotificationToggleEnabled(value) {
    return value !== false;
}

/** Include Sundays is opt-in at the gate (FimbyPushBatchJob / FimbyEmailAlertBatchJob). */
function isOptInToggleEnabled(value) {
    return value === true;
}

const QUIET_HOURS_VALUES = [
    { label: '9 PM \u2013 5 AM', value: '9PM_5AM' },
    { label: '10 PM \u2013 6 AM', value: '10PM_6AM' },
    { label: '11 PM \u2013 7 AM', value: '11PM_7AM' },
    { label: '12 AM \u2013 8 AM', value: '12AM_8AM' },
    { label: 'None', value: 'NONE' }
];

const NOTIFICATION_CATEGORIES = [
    { key: 'messages', label: 'Messages', pushField: 'Push_Messages__c', pushKey: 'pushMessages', emailField: 'Email_Alert_Messages__c', emailKey: 'emailAlertMessages' },
    { key: 'needsOffers', label: 'Asks & Offers', pushField: 'Push_Needs_Offers__c', pushKey: 'pushNeedsOffers', emailField: 'Email_Alert_Needs_Offers__c', emailKey: 'emailAlertNeedsOffers' },
    { key: 'events', label: 'Events', pushField: 'Push_Events__c', pushKey: 'pushEvents', emailField: 'Email_Alert_Events__c', emailKey: 'emailAlertEvents' },
    { key: 'library', label: 'Library', pushField: 'Push_Library__c', pushKey: 'pushLibrary', emailField: 'Email_Alert_Library__c', emailKey: 'emailAlertLibrary' },
    { key: 'stories', label: 'Shared Life', pushField: 'Push_Stories__c', pushKey: 'pushStories', emailField: 'Email_Alert_Stories__c', emailKey: 'emailAlertStories' },
    { key: 'reminders', label: 'Reminders', pushField: 'Push_Reminders__c', pushKey: 'pushReminders', emailField: 'Email_Alert_Reminders__c', emailKey: 'emailAlertReminders' },
    { key: 'bulkBuy', label: 'Bulk Buys', pushField: 'Push_Bulk_Buy__c', pushKey: 'pushBulkBuy', emailField: 'Email_Alert_Bulk_Buy__c', emailKey: 'emailAlertBulkBuy' }
];

export default class FimbySettingsView extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track settings = {};
    @track showQuietHoursHint = false;
    @track showDigestHint = false;
    @track themePreference = 'auto'; // 'light', 'dark', 'auto'

    // Inline success banner — shown when a save keeps the user on this page
    // (password reset, regional settings). Auto-dismisses. Operation failures
    // go to the shell toast instead.
    @track _successMessage = '';
    _successTimer = null;

    // Regional edit
    @track isEditingRegional = false;
    @track editTimeZone = '';
    @track editLocale = '';
    @track editLanguage = '';
    @track isSavingRegional = false;

    // Blocked contacts
    @track blockedContacts = [];
    @track showBlockedSection = false;
    @track isLoadingBlocked = false;

    // Block neighbour modal (search + confirm)
    @track showBlockModal = false;
    @track blockModalStep = 'search';
    @track blockSearchTerm = '';
    @track blockSearchResults = [];
    @track blockSearching = false;
    @track blockSelectedContactId = null;
    @track blockSelectedContactName = '';
    @track blockReason = '';
    @track blockIsReporting = false;
    @track blockReportDetails = '';
    @track isBlocking = false;
    _blockSearchTimeout;

    // Account deletion (graceful default, opt-in immediate)
    @track showDeleteConfirm = false;
    @track skipGrace = false;
    @track isDeleting = false;

    // Password reset
    @track isResettingPassword = false;

    // Native push-permission feedback (mobile shell reports back via window.__fimbyPushResult)
    @track showPushPermissionModal = false;
    _pushResultHandler = null;

    // Biometric app lock (native app only). Capability + current enabled state
    // are pulled on-demand at connectedCallback via an appLockCapabilityRequest
    // message — the shell replies through window.__fimbyAppLockCapabilityResult.
    // This avoids racing first paint against async LocalAuthentication reads.
    // The shell also confirms enable/disable via window.__fimbyAppLockResult
    // after each biometric prompt.
    @track appLockAvailable = false;
    @track appLockEnabled = false;
    @track appLockMethodLabel = 'biometric unlock';
    _appLockResultHandler = null;
    _appLockCapabilityHandler = null;
    _appLockCapabilityTimeout = null;
    _appLockPending = null;

    // Fun stuff
    @track funToggleGifUrl = null;
    _confettiLoaded = false;

    // App store links (config from CMDT via FimbyAppPromptController — single source of truth)
    @track _appConfig = null;

    @wire(getAppPromptConfig)
    wiredAppConfig({ data }) {
        if (data) this._appConfig = data;
    }

    // Icons
    get accountIconUrl() { return `${IMPACT_ICONS}/key.png`; }
    get emailIconUrl() { return `${IMPACT_ICONS}/email.png`; }
    get notificationsIconUrl() { return `${IMPACT_ICONS}/BellActive.png`; }
    get safetyIconUrl() { return `${IMPACT_ICONS}/warning.png`; }
    get fimbyUpdatesIconUrl() { return `${IMPACT_ICONS}/email.png`; }
    get regionalIconUrl() { return `${IMPACT_ICONS}/globe.png`; }
    get appearanceIconUrl() { return `${IMPACT_ICONS}/day-and-night.png`; }
    get blockedIconUrl() { return `${IMPACT_ICONS}/block-user.png`; }
    get deactivationIconUrl() { return `${IMPACT_ICONS}/deactivation.png`; }
    get confettiIconUrl() { return `${IMPACT_ICONS}/confetti.png`; }
    get walkthroughIconUrl() { return `${IMPACT_ICONS}/lightbulb.png`; }
    get neighbourhoodIconUrl() { return `${IMPACT_ICONS}/NeighborhoodActive.png`; }

    // App store badges — shown only on the web (desktop or mobile browser), not
    // inside the native app, where "Download on the App Store" makes no sense.
    get appStoreBadgeUrl() { return `${ICONS}/app-store-badge.png`; }
    get googlePlayBadgeUrl() { return `${ICONS}/google-play-badge.png`; }
    get iosStoreUrl() { return this._appConfig?.iosStoreUrl; }
    get androidStoreUrl() { return this._appConfig?.androidStoreUrl; }

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

    get showStoreBadges() {
        return !this.isInFimbyApp && !!this.iosStoreUrl && !!this.androidStoreUrl;
    }

    // Only in the native app, and only on devices that actually have biometrics
    // enrolled — desktop/web and non-capable devices never see this.
    get showAppLock() {
        return this.isInFimbyApp && this.appLockAvailable;
    }

    get appLockToggleLabel() {
        return `Require ${this.appLockMethodLabel} to open FIMBY`;
    }
    get themeLightIconUrl() { return `${IMPACT_ICONS}/lightbulb.png`; }
    get themeDarkIconUrl() { return `${IMPACT_ICONS}/moon.png`; }
    get themeAutoIconUrl() { return `${IMPACT_ICONS}/gear.png`; }

    get emailFrequencyOptions() {
        const current = normalizeSummaryEmailFrequency(this.settings.summaryEmailFrequency);
        return EMAIL_FREQUENCY_VALUES.map(opt => ({
            ...opt,
            selected: opt.value === current
        }));
    }

    get quietHoursOptions() {
        const current = this.settings.quietHoursPreference || '10PM_6AM';
        return QUIET_HOURS_VALUES.map(opt => ({
            ...opt,
            selected: opt.value === current
        }));
    }

    get notificationCategories() {
        const pushMaster = isNotificationToggleEnabled(this.settings.pushNotificationsEnabled);
        const emailMaster = isNotificationToggleEnabled(this.settings.emailAlertsEnabled);
        return NOTIFICATION_CATEGORIES.map(cat => ({
            ...cat,
            pushChecked: isNotificationToggleEnabled(this.settings[cat.pushKey]),
            emailChecked: isNotificationToggleEnabled(this.settings[cat.emailKey]),
            pushDisabled: !pushMaster,
            emailDisabled: !emailMaster
        }));
    }

    get pushEnabled() {
        return isNotificationToggleEnabled(this.settings.pushNotificationsEnabled);
    }

    get emailAlertsEnabled() {
        return isNotificationToggleEnabled(this.settings.emailAlertsEnabled);
    }

    get includeSundaysEnabled() {
        return isOptInToggleEnabled(this.settings.includeSundays);
    }

    get fimbyOperatingUpdatesEnabled() {
        return isNotificationToggleEnabled(this.settings.fimbyOperatingUpdatesEnabled);
    }

    get celebrationConfettiEnabled() {
        return isNotificationToggleEnabled(this.settings.celebrationConfettiEnabled);
    }

    get celebrationMemesEnabled() {
        return isNotificationToggleEnabled(this.settings.celebrationMemesEnabled);
    }

    get canDeleteAccount() { return !!this.settings.isActingAsSelf; }

    get canBlockNeighbours() { return !!this.settings.isActingAsSelf; }

    get showBlockSearchStep() { return this.blockModalStep === 'search'; }

    get showBlockConfirmStep() { return this.blockModalStep === 'confirm'; }

    get blockModalTitle() {
        if (this.showBlockConfirmStep && this.blockSelectedContactName) {
            return `Block ${this.blockSelectedContactName}?`;
        }
        return 'Block someone';
    }

    get blockConfirmDisabled() {
        return this.isBlocking;
    }

    get deleteConfirmButtonLabel() {
        return this.skipGrace ? 'Delete immediately' : 'Delete my account';
    }

    get deleteConfirmButtonClass() {
        return this.skipGrace
            ? 'btn btn-danger btn-danger-strong'
            : 'btn btn-danger';
    }

    get deleteConfirmTitle() {
        return this.skipGrace
            ? 'Delete immediately?'
            : 'Delete your account?';
    }

    get deleteConfirmBody() {
        return this.skipGrace
            ? 'Your account will be deactivated right now and your data will be ' +
              'permanently removed on tonight\u2019s cleanup. This cannot be undone.'
            : 'Your account will be deactivated immediately. After 30 days, your ' +
              'posts, library items, messages, and personal data are permanently ' +
              'removed. You can restore your account anytime in those 30 days using ' +
              'the link we\u2019ll email you.';
    }

    get hasBlockedContacts() { return this.blockedContacts.length > 0; }
    get blockedCountLabel() {
        const count = this.blockedContacts.length;
        return count === 1 ? '1 blocked' : `${count} blocked`;
    }
    get blockedChevron() {
        return this.showBlockedSection ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get isThemeLight() { return this.themePreference === 'light'; }
    get isThemeDark() { return this.themePreference === 'dark'; }
    get isThemeAuto() { return this.themePreference === 'auto'; }
    get themeLightClass() { return 'theme-option' + (this.isThemeLight ? ' selected' : ''); }
    get themeDarkClass() { return 'theme-option' + (this.isThemeDark ? ' selected' : ''); }
    get themeAutoClass() { return 'theme-option' + (this.isThemeAuto ? ' selected' : ''); }

    async connectedCallback() {
        this._loadThemeCacheFast();
        this._registerPushResultBridge();
        this._initAppLock();
        this._registerAppLockBridge();
        await this.loadSettings();
    }

    disconnectedCallback() {
        if (this._pushResultHandler && window.__fimbyPushResult === this._pushResultHandler) {
            delete window.__fimbyPushResult;
        }
        this._pushResultHandler = null;
        if (this._appLockResultHandler && window.__fimbyAppLockResult === this._appLockResultHandler) {
            delete window.__fimbyAppLockResult;
        }
        this._appLockResultHandler = null;
        if (this._appLockCapabilityHandler && window.__fimbyAppLockCapabilityResult === this._appLockCapabilityHandler) {
            delete window.__fimbyAppLockCapabilityResult;
        }
        this._appLockCapabilityHandler = null;
        if (this._appLockCapabilityTimeout) {
            clearTimeout(this._appLockCapabilityTimeout);
            this._appLockCapabilityTimeout = null;
        }
        if (this._successTimer) {
            clearTimeout(this._successTimer);
            this._successTimer = null;
        }
    }

    // ============================================
    // APP SECURITY (biometric app lock — native only)
    // ============================================
    _appLockLabelForType(type) {
        switch (type) {
            case 'faceId': return 'Face ID';
            case 'touchId': return 'Touch ID';
            case 'fingerprint': return 'fingerprint';
            default: return 'biometric unlock';
        }
    }

    // Ask the shell — on Settings mount — whether biometrics are available on
    // this device and whether the user has the lock enabled. The reply comes
    // back through window.__fimbyAppLockCapabilityResult (registered here).
    // Older app builds that don't understand the message simply never reply,
    // and the safety timeout leaves the section hidden.
    _initAppLock() {
        if (!this.isInFimbyApp) return;

        this._appLockCapabilityHandler = (payload) => {
            if (this._appLockCapabilityTimeout) {
                clearTimeout(this._appLockCapabilityTimeout);
                this._appLockCapabilityTimeout = null;
            }
            if (!payload || typeof payload !== 'object') return;
            this.appLockAvailable = payload.available === true;
            this.appLockEnabled = payload.enabled === true;
            this.appLockMethodLabel = this._appLockLabelForType(payload.type);
        };
        try {
            window.__fimbyAppLockCapabilityResult = this._appLockCapabilityHandler;
        } catch { /* native bridge / LWS unavailable */ }

        try {
            if (window.ReactNativeWebView) {
                window.ReactNativeWebView.postMessage(JSON.stringify({
                    type: 'appLockCapabilityRequest'
                }));
            }
        } catch { /* native bridge unavailable */ }

        this._appLockCapabilityTimeout = setTimeout(() => {
            this._appLockCapabilityTimeout = null;
            // No reply within the safety window — leave the section hidden.
        }, 500);
    }

    // The native shell calls window.__fimbyAppLockResult({ granted, enabled })
    // after it runs the biometric confirm for an enable/disable request. On a
    // cancel/failure we revert the toggle to its previous state so the UI never
    // claims a lock that isn't actually armed.
    _registerAppLockBridge() {
        this._appLockResultHandler = (payload) => {
            const granted = payload && payload.granted;
            if (granted) {
                if (typeof payload.enabled === 'boolean') {
                    this.appLockEnabled = payload.enabled;
                }
            } else if (this._appLockPending !== null) {
                // Revert to the state before the user flipped it.
                this.appLockEnabled = !this._appLockPending;
            }
            this._appLockPending = null;
        };
        try {
            window.__fimbyAppLockResult = this._appLockResultHandler;
        } catch { /* native bridge / LWS unavailable */ }
    }

    handleAppLockToggle(event) {
        const desired = event.target.checked;
        // Optimistic; the shell confirms (or reverts via __fimbyAppLockResult)
        // after the biometric check.
        this._appLockPending = desired;
        this.appLockEnabled = desired;
        try {
            if (window.ReactNativeWebView) {
                window.ReactNativeWebView.postMessage(JSON.stringify({
                    type: 'appLock',
                    enabled: desired
                }));
            }
        } catch { /* native bridge unavailable */ }
    }

    // The native shell calls window.__fimbyPushResult({ granted }) after it
    // tries to acquire an OS push token in response to our toggle. When the OS
    // permission is denied/blocked there is no token, so we revert the master
    // toggle to OFF (keeping Salesforce in sync with device reality) and tell
    // the user how to re-enable it from their device settings.
    _registerPushResultBridge() {
        this._pushResultHandler = (payload) => {
            const granted = payload && payload.granted;
            if (granted) {
                return;
            }
            this.settings = { ...this.settings, pushNotificationsEnabled: false };
            updateSettingsToggle({ fieldName: 'Push_Notifications_Enabled__c', value: false })
                .catch(() => { /* best-effort; UI already reflects OFF */ });
            this.showPushPermissionModal = true;
        };
        try {
            window.__fimbyPushResult = this._pushResultHandler;
        } catch { /* native bridge / LWS unavailable */ }
    }

    handleClosePushPermissionModal() {
        this.showPushPermissionModal = false;
    }

    async loadSettings() {
        this.isLoading = true;
        try {
            this.settings = await getSettingsData();
            this._syncThemeFromServer();
            this._evaluateQuietHoursHint();
            this._evaluateDigestHint();
        } catch {
            this._showError('Could not load your settings. Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================
    // ACCOUNT SECTION
    // ============================================
    async handlePasswordReset() {
        this.isResettingPassword = true;
        try {
            const result = await triggerPasswordReset();
            this._showSuccess(result.message || 'Password reset email sent. Check your inbox.');
        } catch (error) {
            this._showError(error.body?.message || 'Could not send the reset email. Please try again.');
        } finally {
            this.isResettingPassword = false;
        }
    }

    handleDismissQuietHoursHint() {
        this._dismissQuietHoursHint();
    }

    handleDismissDigestHint() {
        this._dismissDigestHint();
    }

    _evaluateQuietHoursHint() {
        try {
            if (localStorage.getItem('fimby_quiet_hours_hint_dismissed') === '1') {
                this.showQuietHoursHint = false;
                return;
            }
        } catch {
            // ignore
        }
        const pref = this.settings?.quietHoursPreference;
        const isDefault = !pref || pref === '10PM_6AM';
        if (!isDefault) {
            this.showQuietHoursHint = false;
            return;
        }
        let appVisits = 0;
        let notifications = 0;
        try {
            appVisits = parseInt(sessionStorage.getItem('fimby_app_visit_count') || '0', 10);
            const cached = JSON.parse(sessionStorage.getItem('fimby-badge-counts') || '{}');
            notifications = cached.notifications || 0;
        } catch {
            // ignore
        }
        this.showQuietHoursHint = appVisits >= 2 || notifications >= 1;
    }

    _dismissQuietHoursHint() {
        this.showQuietHoursHint = false;
        try {
            localStorage.setItem('fimby_quiet_hours_hint_dismissed', '1');
        } catch {
            // ignore
        }
    }

    _evaluateDigestHint() {
        try {
            if (localStorage.getItem('fimby_digest_hint_dismissed') === '1') {
                this.showDigestHint = false;
                return;
            }
        } catch {
            // ignore
        }
        const freq = normalizeSummaryEmailFrequency(this.settings?.summaryEmailFrequency);
        this.showDigestHint = freq === 'Daily';
    }

    _dismissDigestHint() {
        this.showDigestHint = false;
        try {
            localStorage.setItem('fimby_digest_hint_dismissed', '1');
        } catch {
            // ignore
        }
    }

    // ============================================
    // EMAIL PREFERENCES
    // ============================================
    async handleEmailFrequencyChange(event) {
        const value = event.target.value;
        this._dismissDigestHint();
        try {
            await updateSettingsField({ fieldName: 'FIMBY_Summary_Emails__c', value });
            this.settings = { ...this.settings, summaryEmailFrequency: value };
        } catch {
            this._showError('Could not update your email preference. Please try again.');
        }
    }

    async handleQuietHoursChange(event) {
        const value = event.target.value;
        this._dismissQuietHoursHint();
        try {
            await updateSettingsField({ fieldName: 'Quiet_Hours_Preference__c', value });
            this.settings = { ...this.settings, quietHoursPreference: value };
        } catch {
            this._showError('Could not update your quiet hours. Please try again.');
        }
    }

    // ============================================
    // FUN STUFF TOGGLES
    // ============================================
    async handleFunToggle(event) {
        const field = event.target.dataset.field;
        const checked = event.target.checked;
        const settingsKey = event.target.dataset.key;

        try {
            await updateSettingsToggle({ fieldName: field, value: checked });
            this.settings = { ...this.settings, [settingsKey]: checked };

            this.funToggleGifUrl = checked
                ? `${MEMES4}/turnon.gif`
                : `${MEMES4}/turnoff.gif`;

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.funToggleGifUrl = null; }, 3000);

            if (checked && field === 'Celebration_Confetti_Enabled__c') {
                this._firePreviewConfetti(['🎉', '🥳', '✨', '💛']);
            }
        } catch {
            this._showError('Could not update that setting. Please try again.');
            event.target.checked = !checked;
        }
    }

    _firePreviewConfetti(emojis) {
        try {
            const styles = ['Cannon', 'Fall', 'Rise', 'Drift', 'Approach'];
            const style = styles[Math.floor(Math.random() * styles.length)];
            fireEmojiConfetti({ emojis, style, intensity: 'normal' });
        } catch {
            // Non-critical -- confetti is progressive enhancement
        }
    }

    // ============================================
    // PRIVACY TOGGLES (how neighbours see you)
    // ============================================
    async handlePrivacyToggle(event) {
        const field = event.target.dataset.field;
        const checked = event.target.checked;
        const settingsKey = event.target.dataset.key;

        try {
            await updatePrivacyPreference({ fieldName: field, value: checked });
            this.settings = { ...this.settings, [settingsKey]: checked };
        } catch {
            this._showError('Could not update that privacy setting. Please try again.');
            event.target.checked = !checked;
        }
    }

    // ============================================
    // NOTIFICATION TOGGLES
    // ============================================
    async handleToggle(event) {
        const field = event.target.dataset.field;
        const checked = event.target.checked;
        const settingsKey = event.target.dataset.key;

        try {
            await updateSettingsToggle({ fieldName: field, value: checked });
            this.settings = { ...this.settings, [settingsKey]: checked };

            // Only the master push toggle drives device token lifecycle. Tell the
            // native shell so it can register (acquire OS permission + token) or
            // unregister (delete the token) immediately, rather than waiting for
            // the next app open. Per-category toggles stay Salesforce-only.
            if (field === 'Push_Notifications_Enabled__c') {
                this._notifyNativePushToggle(checked);
            }
        } catch {
            this._showError('Could not update that notification setting. Please try again.');
            event.target.checked = !checked;
        }
    }

    _notifyNativePushToggle(enabled) {
        try {
            if (window.ReactNativeWebView) {
                window.ReactNativeWebView.postMessage(JSON.stringify({
                    type: 'pushNotifications',
                    enabled: enabled
                }));
            }
        } catch { /* native bridge unavailable (desktop web) */ }
    }

    // View-mode display labels
    get displayTimeZone() { return this.settings.timeZoneLabel || this.settings.timeZone || '—'; }
    get displayLocale() { return this.settings.localeLabel || this.settings.locale || '—'; }
    get displayLanguage() { return this.settings.languageLabel || this.settings.language || '—'; }

    get timeZonePicklist() { return this.settings.timeZoneOptions || []; }
    get localePicklist() { return this.settings.localeOptions || []; }
    get languagePicklist() { return this.settings.languageOptions || []; }

    get timeZoneEditOptions() {
        const current = this.editTimeZone || this.settings.timeZone || '';
        return this.timeZonePicklist.map(opt => ({
            ...opt,
            selected: opt.value === current
        }));
    }

    get localeEditOptions() {
        const current = this.editLocale || this.settings.locale || '';
        return this.localePicklist.map(opt => ({
            ...opt,
            selected: opt.value === current
        }));
    }

    get languageEditOptions() {
        const current = this.editLanguage || this.settings.language || '';
        return this.languagePicklist.map(opt => ({
            ...opt,
            selected: opt.value === current
        }));
    }

    // ============================================
    // REGIONAL SETTINGS
    // ============================================
    handleEditRegional() {
        this.editTimeZone = this.settings.timeZone || '';
        this.editLocale = this.settings.locale || '';
        this.editLanguage = this.settings.language || '';
        this.isEditingRegional = true;
    }

    handleCancelRegional() { this.isEditingRegional = false; }

    async handleSaveRegional() {
        this.isSavingRegional = true;
        try {
            if (this.editTimeZone !== this.settings.timeZone) {
                await updateSettingsField({ fieldName: 'TimeZoneSidKey', value: this.editTimeZone });
            }
            if (this.editLocale !== this.settings.locale) {
                await updateSettingsField({ fieldName: 'LocaleSidKey', value: this.editLocale });
            }
            if (this.editLanguage !== this.settings.language) {
                await updateSettingsField({ fieldName: 'LanguageLocaleKey', value: this.editLanguage });
            }
            this.isEditingRegional = false;
            this._showSuccess('Your regional settings have been updated.');
            await this.loadSettings();
        } catch (error) {
            this._showError(error.body?.message || 'Could not save your regional settings. Please try again.');
        } finally {
            this.isSavingRegional = false;
        }
    }

    handleRegionalSelect(event) {
        const field = event.target.dataset.field;
        if (field) this[field] = event.target.value;
    }

    // ============================================
    // APPEARANCE (Light / Dark / Auto)
    // Source of truth: User.Theme_Preference__c
    // localStorage is a fast-paint cache only
    // ============================================
    _loadThemeCacheFast() {
        const cached = localStorage.getItem('fimby-theme-pref');
        if (cached) this.themePreference = cached;
    }

    _syncThemeFromServer() {
        const serverPref = (this.settings.themePreference || 'Auto').toLowerCase();
        if (serverPref !== this.themePreference) {
            this.themePreference = serverPref;
            this._applyThemeToDOM(serverPref);
        }
    }

    _applyThemeToDOM(pref) {
        if (pref === 'dark') {
            document.documentElement.setAttribute('data-theme', 'dark');
        } else if (pref === 'light') {
            document.documentElement.setAttribute('data-theme', 'light');
        } else {
            document.documentElement.removeAttribute('data-theme');
        }
        try {
            if (typeof window.__fimbySetTheme === 'function') {
                window.__fimbySetTheme(pref);
            }
        } catch { /* bridge unavailable */ }
        try { localStorage.setItem('fimby-theme-pref', pref); } catch { /* LWS may namespace */ }
        try { document.cookie = 'fimby-theme-pref=' + encodeURIComponent(pref) + ';path=/;max-age=31536000;SameSite=Lax'; } catch { /* */ }
        this._notifyNativeShell(pref);
    }

    _notifyNativeShell(pref) {
        try {
            if (window.ReactNativeWebView) {
                // Send the raw preference, not a resolved colour. The native shell
                // stores 'auto' and resolves it against the device scheme live, so
                // an OS light/dark flip tracks without re-loading the WebView.
                const normalized = (pref === 'dark' || pref === 'light') ? pref : 'auto';
                window.ReactNativeWebView.postMessage(JSON.stringify({
                    type: 'themeChange',
                    theme: normalized
                }));
            }
        } catch { /* native bridge unavailable */ }
    }

    async handleThemeChange(event) {
        const pref = event.currentTarget.dataset.theme;
        this.themePreference = pref;
        this._applyThemeToDOM(pref);

        if (this.settings.celebrationConfettiEnabled && pref !== 'auto') {
            const emojis = pref === 'dark'
                ? ['🌙', '⭐', '🌃', '✨', '🦉']
                : ['☀️', '🌻', '🌈', '✨', '🌤️'];
            this._firePreviewConfetti(emojis);
        }

        const sfValue = pref.charAt(0).toUpperCase() + pref.slice(1);
        try {
            await updateSettingsField({ fieldName: 'Theme_Preference__c', value: sfValue });
        } catch {
            this._showError('Could not save your theme preference. Please try again.');
        }
    }

    // ============================================
    // BLOCKED CONTACTS
    // ============================================
    async handleToggleBlocked() {
        this.showBlockedSection = !this.showBlockedSection;
        if (this.showBlockedSection && this.blockedContacts.length === 0) {
            await this.loadBlockedContacts();
        }
    }

    async loadBlockedContacts() {
        this.isLoadingBlocked = true;
        try {
            const result = await getBlockedContacts();
            this.blockedContacts = result.map(bc => ({
                ...bc,
                initials: this._getInitials(bc.contactName),
                formattedDate: this._formatDate(bc.blockedDate)
            }));
        } catch (error) {
            console.error('Error loading blocked contacts:', error);
        } finally {
            this.isLoadingBlocked = false;
        }
    }

    async handleUnblock(event) {
        const contactId = event.currentTarget.dataset.contactId;
        try {
            await unblockContact({ blockedContactId: contactId });
            // The neighbour drops off the blocked list — the surface change is the
            // confirmation, so no banner.
            this.blockedContacts = this.blockedContacts.filter(bc => bc.contactId !== contactId);
        } catch {
            this._showError('Could not unblock that contact. Please try again.');
        }
    }

    handleOpenBlockModal() {
        this._resetBlockModal();
        this.showBlockModal = true;
    }

    handleCloseBlockModal() {
        this.showBlockModal = false;
        this._resetBlockModal();
    }

    _resetBlockModal() {
        this.blockModalStep = 'search';
        this.blockSearchTerm = '';
        this.blockSearchResults = [];
        this.blockSearching = false;
        this.blockSelectedContactId = null;
        this.blockSelectedContactName = '';
        this.blockReason = '';
        this.blockIsReporting = false;
        this.blockReportDetails = '';
        this.isBlocking = false;
        clearTimeout(this._blockSearchTimeout);
    }

    handleBlockSearch(event) {
        this.blockSearchTerm = event.target.value;
        clearTimeout(this._blockSearchTimeout);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._blockSearchTimeout = setTimeout(() => this._doBlockSearch(), 350);
    }

    async _doBlockSearch() {
        const term = (this.blockSearchTerm || '').trim();
        if (term.length < 2) {
            this.blockSearchResults = [];
            return;
        }
        this.blockSearching = true;
        try {
            const results = await searchNeighboursForBlock({ searchTerm: term });
            this.blockSearchResults = (results || []).map(r => ({
                contactId: r.contactId,
                contactName: r.contactName,
                email: r.email,
                resultClass: r.contactId === this.blockSelectedContactId
                    ? 'block-result-item selected' : 'block-result-item'
            }));
        } catch (error) {
            console.error('Block search error:', error);
            this.blockSearchResults = [];
            this._showError('Could not search neighbours just now. Please try again.');
        } finally {
            this.blockSearching = false;
        }
    }

    handleSelectBlockTarget(event) {
        const contactId = event.currentTarget.dataset.contactId;
        const contactName = event.currentTarget.dataset.contactName;
        this.blockSelectedContactId = contactId;
        this.blockSelectedContactName = contactName || '';
        this.blockModalStep = 'confirm';
        this.blockReason = '';
        this.blockIsReporting = false;
        this.blockReportDetails = '';
    }

    handleBackToBlockSearch() {
        this.blockModalStep = 'search';
        this.blockSelectedContactId = null;
        this.blockSelectedContactName = '';
    }

    handleBlockReasonChange(event) {
        this.blockReason = event.target.value;
    }

    handleBlockReportToggle(event) {
        this.blockIsReporting = event.target.checked;
    }

    handleBlockReportDetailsChange(event) {
        this.blockReportDetails = event.target.value;
    }

    async handleConfirmBlock() {
        if (!this.blockSelectedContactId) {
            return;
        }
        this.isBlocking = true;
        try {
            await blockContact({
                blockedContactId: this.blockSelectedContactId,
                reason: this.blockReason,
                isReport: this.blockIsReporting,
                reportDetails: this.blockReportDetails
            });
            // Whether newly blocked or already on the list, the modal closes and the
            // neighbour now appears in the (expanded) blocked section \u2014 the surface
            // change is the confirmation, so no banner.
            this.showBlockModal = false;
            this._resetBlockModal();
            await this.loadBlockedContacts();
            this.showBlockedSection = true;
        } catch (error) {
            this._showError(error.body?.message || 'Could not block that neighbour. Please try again.');
        } finally {
            this.isBlocking = false;
        }
    }

    // ============================================
    // ACCOUNT DELETION (graceful default + skip-grace escape valve)
    // ============================================
    handleDeleteClick() {
        this.skipGrace = false;
        this.showDeleteConfirm = true;
    }

    handleDeleteCancel() {
        this.showDeleteConfirm = false;
        this.skipGrace = false;
    }

    handleSkipGraceToggle(event) {
        this.skipGrace = !!event.target.checked;
    }

    async handleDeleteConfirm() {
        this.isDeleting = true;
        try {
            await requestAccountDeletion({ skipGrace: this.skipGrace });
            this.showDeleteConfirm = false;
            // The user is logged out moments later, so there's no surface left to
            // confirm on \u2014 drop the message and let the logout speak for itself.
            // In the native app, route logout through the native shell so the app
            // session token is revoked and teardown is explicit (never mistaken
            // for a session timeout, which would silently re-authenticate the
            // just-deleted account). Web falls back to the redirect.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (window.ReactNativeWebView) {
                    window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'logout' }));
                    return;
                }
                window.location.href = '/secur/logout.jsp';
            }, 2500);
        } catch (error) {
            this._showError(error.body?.message || 'Could not process that request. Please try again.');
        } finally {
            this.isDeleting = false;
        }
    }

    stopPropagation(event) { event.stopPropagation(); }

    // ============================================
    // HELPERS
    // ============================================
    _getInitials(name) {
        if (!name) return '?';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    _formatDate(dateValue) {
        if (!dateValue) return '';
        try {
            const d = new Date(dateValue);
            return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' });
        } catch {
            return '';
        }
    }

    get successMessage() {
        return this._successMessage;
    }

    // Quiet, contextual success — the surface stays put, so we show an inline
    // banner that fades away on its own rather than a toast.
    _showSuccess(message) {
        this._successMessage = message;
        if (this._successTimer) {
            clearTimeout(this._successTimer);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._successTimer = setTimeout(() => {
            this._successMessage = '';
            this._successTimer = null;
        }, 5000);
    }

    // Operation failures route to the shell toast (assertive, global).
    _showError(message) {
        fireToast({ message, variant: 'error' });
    }

    handleBack() {
        navigateBack(this, '/my-stuff');
    }

    // ============================================
    // WALKTHROUGH
    // ============================================
    handleLaunchWalkthrough() {
        launchGuidedTourReplay(this);
    }

    handleTabChange(event) {
        navigateToRoute(this, event.detail.tab);
    }
}