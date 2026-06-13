import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getNeighbourProfile from '@salesforce/apex/FimbyMyStuffController.getNeighbourProfile';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import { navigate, navigateToRoute } from 'c/fimbyNavigation';
import blockContact from '@salesforce/apex/FimbyConversationController.blockContact';
import isModeratorContact from '@salesforce/apex/FimbyModeratorDashboardController.isModeratorContact';

export default class FimbyNeighbourProfile extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track profile = {};
    @track neighbourContactId = null;
    @track showBlockConfirm = false;
    @track isBlocking = false;
    @track isProfileModerator = false;

    get contactIconUrl() { return `${IMPACT_ICONS}/sign.png`; }
    get aboutIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get accessibilityIconUrl() { return `${IMPACT_ICONS}/accessibility.png`; }
    get careIconUrl() { return `${IMPACT_ICONS}/care.png`; }
    get moderatorBadgeIconUrl() { return `${IMPACT_ICONS}/moderatoractive.png`; }

    _d(val) { return val || '—'; }
    _dMulti(val) { return this._multiSelectToDisplay(val) || '—'; }

    get displayPronouns() { return this._d(this.profile.pronouns); }
    get displayAboutTenure() { return this._d(this.profile.aboutNeighbourhoodTenure); }
    get displayAboutBroughtYou() { return this._d(this.profile.aboutWhatBroughtYou); }
    get displayAboutLocalPlace() { return this._d(this.profile.aboutLocalPlace); }
    get displayAboutEnjoys() { return this._d(this.profile.aboutEnjoysDoing); }
    get displayAboutFunFact() { return this._d(this.profile.aboutFunFact); }
    get displayLanguages() { return this._dMulti(this.profile.languagesSpoken); }
    get displayAccessibility() { return this._d(this.profile.accessibilityNotes); }
    get displayAvailability() { return this._dMulti(this.profile.generalAvailability); }
    get displayCareWelcome() { return this._dMulti(this.profile.careWelcomeSupport); }
    get displayCareUnhelpful() { return this._dMulti(this.profile.careUnhelpfulThings); }
    get displayCareHowToAsk() { return this._dMulti(this.profile.careHowToAsk); }
    get displayCareTooMuch() {
        const parts = [
            this._multiSelectToDisplay(this.profile.careUnhelpfulThings),
            this.profile.careHardNos
        ].filter(Boolean);
        return parts.length ? parts.join('; ') : '';
    }

    get avatarUrl() {
        return avatarImageUrl(this.profile.imageUrl);
    }
    get hasAvatar() { return !!this.profile.imageUrl; }
    get initials() {
        const f = (this.profile.firstName || '').charAt(0);
        const l = (this.profile.lastName || '').charAt(0);
        return (f + l).toUpperCase() || '?';
    }
    get formattedMemberSince() {
        if (!this.profile.memberSince) return '';
        const d = new Date(this.profile.memberSince);
        return d.toLocaleDateString('en-AU', { month: 'long', year: 'numeric' });
    }

    get hasSharedContactInfo() { return this.profile.hasSharedContactInfo === true; }
    get sharedEmail() { return this.profile.sharedEmail; }
    get sharedPhone() { return this.profile.sharedPhone; }
    get sharedAddress() {
        const parts = [
            this.profile.sharedStreet, this.profile.sharedCity,
            this.profile.sharedProvinceState, this.profile.sharedPostalCode,
            this.profile.sharedCountry
        ].filter(Boolean);
        return parts.join(', ');
    }
    get hasSharedEmail() { return !!this.profile.sharedEmail; }
    get hasSharedPhone() { return !!this.profile.sharedPhone; }
    get hasSharedAddress() { return !!this.sharedAddress; }

    get emailHref() { return this.sharedEmail ? 'mailto:' + this.sharedEmail : '#'; }
    get phoneHref() { return this.sharedPhone ? 'tel:' + this.sharedPhone : '#'; }

    get showNotFound() {
        return !this.isLoading && !this.profile.contactId;
    }

    get headerMenuItems() {
        if (this.isLoading || this.showNotFound) return [];
        return [
            { key: 'block', label: 'Block', icon: 'block-user.png', display: 'kebab' }
        ];
    }

    handleHeaderMenuAction(event) {
        if (event.detail.key === 'block') {
            this.showBlockConfirm = true;
        }
    }

    handleBlockCancel() {
        this.showBlockConfirm = false;
    }

    async handleBlockConfirm() {
        this.isBlocking = true;
        try {
            await blockContact({ blockedContactId: this.neighbourContactId, reason: 'Blocked from profile', isReport: false, reportDetails: null });
            this.dispatchEvent(new ShowToastEvent({ title: 'Blocked', message: 'This neighbour has been blocked', variant: 'success' }));
            this.showBlockConfirm = false;
            window.history.back();
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: err?.body?.message || 'Could not block this neighbour', variant: 'error' }));
        } finally {
            this.isBlocking = false;
        }
    }

    get hasAboutContent() {
        return this.profile.aboutNeighbourhoodTenure || this.profile.aboutWhatBroughtYou ||
               this.profile.aboutLocalPlace || this.profile.aboutEnjoysDoing ||
               this.profile.aboutFunFact || this.profile.languagesSpoken;
    }
    get hasAccessibilityContent() {
        return this.profile.accessibilityNotes || this.profile.generalAvailability;
    }
    get hasCareContent() {
        if (this.profile.careStandingVisible !== true) {
            return false;
        }
        return this.profile.careWelcomeSupport || this.profile.careUnhelpfulThings ||
               this.profile.careHowToAsk || this.profile.careHardNos;
    }

    get completedBulkBuysText() {
        const count = this.profile.completedBulkBuys;
        if (!count || count < 1) return '';
        return `Completed ${count} shared purchase${count > 1 ? 's' : ''}`;
    }

    async connectedCallback() {
        this.neighbourContactId = this._getContactIdFromUrl();
        if (!this.neighbourContactId) {
            this.isLoading = false;
            return;
        }
        await this._loadProfile();
    }

    _getContactIdFromUrl() {
        const params = new URLSearchParams(window.location.search);
        return params.get('id') || null;
    }

    async _loadProfile() {
        this.isLoading = true;
        try {
            this.profile = await getNeighbourProfile({ neighbourContactId: this.neighbourContactId });
            this._checkIfModerator();
        } catch (error) {
            console.error('Error loading neighbour profile:', error);
        } finally {
            this.isLoading = false;
        }
    }

    _multiSelectToDisplay(val) {
        if (!val) return '';
        return val.split(';').map(s => s.trim()).filter(Boolean).join(', ');
    }

    handleMessage() {
        if (!this.neighbourContactId) return;
        navigate(this, '/conversation?contactId=' + this.neighbourContactId);
    }

    handleBack() {
        if (window.history.length > 1) {
            window.history.back();
        } else {
            navigate(this, '/my-stuff/my-contacts');
        }
    }

    async _checkIfModerator() {
        try {
            if (!this.profile?.contactId) return;
            this.isProfileModerator = await isModeratorContact({ contactId: this.profile.contactId });
        } catch (e) {
            this.isProfileModerator = false;
        }
    }

    handleTabChange(event) {
        navigateToRoute(this, event.detail.tab);
    }
}