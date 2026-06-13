import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import MEMES4 from '@salesforce/resourceUrl/Memes4';
import { navigate, navigateToRoute } from 'c/fimbyNavigation';
import { fireEmojiConfetti } from 'c/fimbyConfettiHelper';
import getSettingsData from '@salesforce/apex/FimbyProfileController.getSettingsData';
import updateSettingsField from '@salesforce/apex/FimbyProfileController.updateSettingsField';
import updateSettingsToggle from '@salesforce/apex/FimbyProfileController.updateSettingsToggle';
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
    @track themePreference = 'auto'; // 'light', 'dark', 'auto'

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

    // Fun stuff
    @track funToggleGifUrl = null;
    _confettiLoaded = false;

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
        await this.loadSettings();
    }

    disconnectedCallback() {
        if (this._pushResultHandler && window.__fimbyPushResult === this._pushResultHandler) {
            delete window.__fimbyPushResult;
        }
        this._pushResultHandler = null;
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
        } catch (e) { /* native bridge / LWS unavailable */ }
    }

    handleClosePushPermissionModal() {
        this.showPushPermissionModal = false;
    }

    async loadSettings() {
        this.isLoading = true;
        try {
            this.settings = await getSettingsData();
            this._syncThemeFromServer();
        } catch (error) {
            this.showToast('Error', 'Could not load settings.', 'error');
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
            this.showToast('Email Sent', result.message || 'Password reset email sent.', 'success');
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Could not send reset email.', 'error');
        } finally {
            this.isResettingPassword = false;
        }
    }

    // ============================================
    // EMAIL PREFERENCES
    // ============================================
    async handleEmailFrequencyChange(event) {
        const value = event.target.value;
        try {
            await updateSettingsField({ fieldName: 'FIMBY_Summary_Emails__c', value });
            this.settings = { ...this.settings, summaryEmailFrequency: value };
        } catch (error) {
            this.showToast('Error', 'Could not update email preference.', 'error');
        }
    }

    async handleQuietHoursChange(event) {
        const value = event.target.value;
        try {
            await updateSettingsField({ fieldName: 'Quiet_Hours_Preference__c', value });
            this.settings = { ...this.settings, quietHoursPreference: value };
        } catch (error) {
            this.showToast('Error', 'Could not update quiet hours.', 'error');
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
        } catch (error) {
            this.showToast('Error', 'Could not update setting.', 'error');
            event.target.checked = !checked;
        }
    }

    _firePreviewConfetti(emojis) {
        try {
            const styles = ['Cannon', 'Fall', 'Rise', 'Drift', 'Approach'];
            const style = styles[Math.floor(Math.random() * styles.length)];
            fireEmojiConfetti({ emojis, style, intensity: 'normal' });
        } catch (e) {
            // Non-critical -- confetti is progressive enhancement
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
        } catch (error) {
            this.showToast('Error', 'Could not update notification setting.', 'error');
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
        } catch (e) { /* native bridge unavailable (desktop web) */ }
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
            this.showToast('Saved', 'Regional settings updated.', 'success');
            await this.loadSettings();
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Could not save regional settings.', 'error');
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
        } catch (e) { /* bridge unavailable */ }
        try { localStorage.setItem('fimby-theme-pref', pref); } catch (e) { /* LWS may namespace */ }
        try { document.cookie = 'fimby-theme-pref=' + encodeURIComponent(pref) + ';path=/;max-age=31536000;SameSite=Lax'; } catch (e) { /* */ }
        this._notifyNativeShell(pref);
    }

    _notifyNativeShell(pref) {
        try {
            if (window.ReactNativeWebView) {
                const effective = (pref === 'dark' || pref === 'light')
                    ? pref
                    : (window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
                window.ReactNativeWebView.postMessage(JSON.stringify({
                    type: 'themeChange',
                    theme: effective
                }));
            }
        } catch (e) { /* native bridge unavailable */ }
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
        } catch (error) {
            this.showToast('Error', 'Could not save theme preference.', 'error');
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
            this.blockedContacts = this.blockedContacts.filter(bc => bc.contactId !== contactId);
            this.showToast('Unblocked', 'Contact has been unblocked.', 'success');
        } catch (error) {
            this.showToast('Error', 'Could not unblock contact.', 'error');
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
            this.showToast('Error', 'Could not search neighbours.', 'error');
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
            const result = await blockContact({
                blockedContactId: this.blockSelectedContactId,
                reason: this.blockReason,
                isReport: this.blockIsReporting,
                reportDetails: this.blockReportDetails
            });
            const alreadyBlocked = result?.alreadyBlocked === true;
            this.showBlockModal = false;
            this._resetBlockModal();
            await this.loadBlockedContacts();
            this.showBlockedSection = true;
            const message = alreadyBlocked
                ? 'That neighbour was already on your blocked list.'
                : 'You will no longer see each other\u2019s content or be able to message.';
            this.showToast(
                alreadyBlocked ? 'Already blocked' : 'Neighbour blocked',
                message,
                alreadyBlocked ? 'info' : 'success'
            );
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || 'Could not block that neighbour.',
                'error'
            );
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
            const toastTitle = this.skipGrace
                ? 'Account deleted'
                : 'Account deactivated';
            const toastBody = this.skipGrace
                ? 'Your account has been deleted. You\u2019ll be logged out shortly.'
                : 'Your account is scheduled for deletion in 30 days. Check your email for the restore link if you change your mind. You\u2019ll be logged out shortly.';
            this.showToast(toastTitle, toastBody, 'warning');
            setTimeout(() => {
                window.location.href = '/secur/logout.jsp';
            }, 2500);
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Could not process the request.', 'error');
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
        } catch (e) {
            return '';
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleBack() {
        if (window.history.length > 1) {
            window.history.back();
        } else {
            navigate(this, '/my-stuff');
        }
    }

    // ============================================
    // WALKTHROUGH
    // ============================================
    handleLaunchWalkthrough() {
        // Onboarding lives on a dedicated page now. Phase routing inside
        // fimbyOnboardingPage is flag-driven, so a returning member who taps
        // Run Walkthrough lands directly on Phase 2 (the 5-screen tour) and
        // skips the Phase 3 intro-post modal.
        navigate(this, '/onboarding');
    }

    handleTabChange(event) {
        navigateToRoute(this, event.detail.tab);
    }
}