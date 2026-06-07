import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getProfileData from '@salesforce/apex/FimbyProfileController.getProfileData';
import updateProfileSection from '@salesforce/apex/FimbyProfileController.updateProfileSection';
import removeImage from '@salesforce/apex/FimbyLibraryController.removeImage';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import { getModeratorContext } from 'c/fimbyModeratorContext';

const CARE_WELCOME_OPTIONS = [
    'A check-in message', 'A meal drop-off', 'Help with errands',
    'A ride or accompaniment', 'Help at home', 'Company',
    'Help thinking things through', 'Prayer', 'Other'
];

const CARE_UNHELPFUL_OPTIONS = [
    'Unannounced drop-ins', 'Lots of questions at once', 'Advice too quickly',
    'Big group attention', 'Being posted about publicly', 'Gifts with expectations',
    'Just pushing through talk', 'Other'
];

const CARE_HOW_TO_ASK_OPTIONS = [
    'Message me first', 'Offer one specific thing',
    'Ask what would be helpful today', 'Keep it simple',
    "Please don't reach out unless I've asked"
];

const LANGUAGES_OPTIONS = [
    'English', 'French', 'Spanish', 'Mandarin', 'Cantonese',
    'Tagalog', 'Arabic', 'Hindi', 'Punjabi', 'Korean',
    'Vietnamese', 'Portuguese', 'Other'
];

const AVAILABILITY_OPTIONS = [
    'Weekday mornings', 'Weekday afternoons', 'Weekday evenings',
    'Weekend mornings', 'Weekend afternoons', 'Weekend evenings',
    'Flexible anytime'
];

export default class FimbyUserProfileView extends LightningElement {
    @track isLoading = true;
    @track profile = {};
    @track showImageUploader = false;

    // Section edit states
    @track isEditingIdentity = false;
    @track isEditingContact = false;
    @track isEditingAbout = false;
    @track isEditingAccessibility = false;
    @track isEditingCare = false;
    @track isSaving = false;
    @track isProfileModerator = false;

    // Edit buffers
    @track editPronouns = '';
    @track editFirstName = '';
    @track editLastName = '';
    @track editEmail = '';
    @track editPhone = '';
    @track editStreet = '';
    @track editCity = '';
    @track editState = '';
    @track editPostalCode = '';
    @track editCountry = '';
    @track editAboutTenure = '';
    @track editAboutBroughtYou = '';
    @track editAboutLocalPlace = '';
    @track editAboutEnjoys = '';
    @track editAboutFunFact = '';
    @track editLanguages = [];
    @track editAccessibility = '';
    @track editAvailability = [];
    @track editCareWelcome = [];
    @track editCareUnhelpful = [];
    @track editCareHowToAsk = '';
    @track editCareHardNos = '';

    // Section icons
    get identityIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }
    get contactIconUrl() { return `${IMPACT_ICONS}/sign.png`; }
    get aboutIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get accessibilityIconUrl() { return `${IMPACT_ICONS}/accessibility.png`; }
    get careIconUrl() { return `${IMPACT_ICONS}/care.png`; }
    get moderatorBadgeIconUrl() { return `${IMPACT_ICONS}/moderatoractive.png`; }

    get contactId() { return this.profile?.contactId || null; }
    get vouchingIsPaused() { return this.profile?.vouchingDisabled === true; }

    /* ---- Settling-in / Vouched chip ---------------------------- */

    get vouchedStatus() {
        return this.profile?.vouchedStatus || 'New';
    }

    get showVouchChip() {
        // Show on any owner profile that has a known vouched status.
        return !!this.profile?.contactId;
    }

    get vouchChipLabel() {
        switch (this.vouchedStatus) {
            case 'Vouched':         return 'Vouched';
            case 'Vouch_Requested': return 'Vouch Pending';
            default:                return 'Settling in';
        }
    }

    get vouchChipClass() {
        switch (this.vouchedStatus) {
            case 'Vouched':         return 'vouch-chip vouch-chip-vouched';
            case 'Vouch_Requested': return 'vouch-chip vouch-chip-pending';
            default:                return 'vouch-chip vouch-chip-settling';
        }
    }

    get vouchChipIconUrl() {
        switch (this.vouchedStatus) {
            case 'Vouched':         return `${IMPACT_ICONS}/enter.png`;
            case 'Vouch_Requested': return `${IMPACT_ICONS}/Wave.png`;
            default:                return `${IMPACT_ICONS}/Sapling.png`;
        }
    }

    get vouchChipHelper() {
        switch (this.vouchedStatus) {
            case 'Vouched':         return 'Welcomed in — the lending library is open';
            case 'Vouch_Requested': return 'Vouch request pending — we will let you know';
            default:                return 'Settling in — the library opens up once someone vouches for you';
        }
    }

    get showVouchChipHelper() {
        // Only show the actionable hint when they still need a vouch.
        return this.vouchedStatus !== 'Vouched' && this.vouchedStatus !== 'Vouch_Requested';
    }

    handleOpenVouchModal() {
        const modal = this.template.querySelector('c-fimby-vouching-required-modal');
        if (modal) modal.show();
    }

    get trustHistoryIconUrl() {
        return `${IMPACT_ICONS}/trust.png`;
    }

    // Option arrays for template iteration
    get languageOptions() {
        return LANGUAGES_OPTIONS.map(opt => ({
            label: opt, value: opt,
            checked: this.editLanguages.includes(opt)
        }));
    }
    get availabilityOptions() {
        return AVAILABILITY_OPTIONS.map(opt => ({
            label: opt, value: opt,
            checked: this.editAvailability.includes(opt)
        }));
    }
    get careWelcomeOptions() {
        return CARE_WELCOME_OPTIONS.map(opt => ({
            label: opt, value: opt,
            checked: this.editCareWelcome.includes(opt)
        }));
    }
    get careUnhelpfulOptions() {
        return CARE_UNHELPFUL_OPTIONS.map(opt => ({
            label: opt, value: opt,
            checked: this.editCareUnhelpful.includes(opt)
        }));
    }
    get careHowToAskOptions() {
        return CARE_HOW_TO_ASK_OPTIONS.map(opt => ({
            label: opt, value: opt,
            checked: this.editCareHowToAsk === opt
        }));
    }

    // View-mode display helpers — always return a value, dash for empty
    _d(val) { return val || '—'; }
    _dMulti(val) { return this._multiSelectToDisplay(val) || '—'; }

    get displayPronouns() { return this._d(this.profile.pronouns); }
    get hasPronouns() { return !!this.profile.pronouns; }
    get displayEmail() { return this._d(this.profile.email); }
    get displayPhone() { return this._d(this.profile.phone); }
    get displayAddress() { return this.mailingAddress || '—'; }
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
    get displayCareHowToAsk() { return this._d(this.profile.careHowToAsk); }
    get displayCareHardNos() { return this._d(this.profile.careHardNos); }

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
    get mailingAddress() {
        const parts = [
            this.profile.mailingStreet, this.profile.mailingCity,
            this.profile.mailingState, this.profile.mailingPostalCode,
            this.profile.mailingCountry
        ].filter(Boolean);
        return parts.join(', ');
    }
    get hasMailingAddress() { return !!this.mailingAddress; }
    get languagesDisplay() {
        return this._multiSelectToDisplay(this.profile.languagesSpoken);
    }
    get hasLanguages() { return !!this.profile.languagesSpoken; }
    get availabilityDisplay() {
        return this._multiSelectToDisplay(this.profile.generalAvailability);
    }
    get hasAvailability() { return !!this.profile.generalAvailability; }
    get careWelcomeDisplay() {
        return this._multiSelectToDisplay(this.profile.careWelcomeSupport);
    }
    get hasCareWelcome() { return !!this.profile.careWelcomeSupport; }
    get careUnhelpfulDisplay() {
        return this._multiSelectToDisplay(this.profile.careUnhelpfulThings);
    }
    get hasCareUnhelpful() { return !!this.profile.careUnhelpfulThings; }
    get hasAboutContent() {
        return this.profile.aboutNeighbourhoodTenure || this.profile.aboutWhatBroughtYou ||
               this.profile.aboutLocalPlace || this.profile.aboutEnjoysDoing ||
               this.profile.aboutFunFact || this.profile.languagesSpoken;
    }
    get hasAccessibilityContent() {
        return this.profile.accessibilityNotes || this.profile.generalAvailability;
    }
    get hasCareContent() {
        return this.profile.careWelcomeSupport || this.profile.careUnhelpfulThings ||
               this.profile.careHowToAsk || this.profile.careHardNos;
    }

    // Character counters
    get tenureCharCount() { return `${(this.editAboutTenure || '').length}/40`; }
    get broughtYouCharCount() { return `${(this.editAboutBroughtYou || '').length}/120`; }
    get localPlaceCharCount() { return `${(this.editAboutLocalPlace || '').length}/80`; }
    get enjoysCharCount() { return `${(this.editAboutEnjoys || '').length}/100`; }
    get funFactCharCount() { return `${(this.editAboutFunFact || '').length}/120`; }
    get accessibilityCharCount() { return `${(this.editAccessibility || '').length}/200`; }
    get hardNosCharCount() { return `${(this.editCareHardNos || '').length}/200`; }

    // Character count dynamic classes
    _charCountClass(len, max) {
        if (len >= max) return 'char-count at-limit';
        if (len >= Math.floor(max * 0.9)) return 'char-count near-limit';
        return 'char-count';
    }
    get tenureCountClass() { return this._charCountClass((this.editAboutTenure || '').length, 40); }
    get broughtYouCountClass() { return this._charCountClass((this.editAboutBroughtYou || '').length, 120); }
    get localPlaceCountClass() { return this._charCountClass((this.editAboutLocalPlace || '').length, 80); }
    get enjoysCountClass() { return this._charCountClass((this.editAboutEnjoys || '').length, 100); }
    get funFactCountClass() { return this._charCountClass((this.editAboutFunFact || '').length, 120); }
    get accessibilityCountClass() { return this._charCountClass((this.editAccessibility || '').length, 200); }
    get hardNosCountClass() { return this._charCountClass((this.editCareHardNos || '').length, 200); }

    async connectedCallback() {
        await this.loadProfile();
    }

    async loadProfile() {
        this.isLoading = true;
        try {
            this.profile = await getProfileData();
            this._checkIfModerator();
        } catch (error) {
            this.showToast('Error', 'Could not load profile data.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================
    // IDENTITY SECTION EDIT
    // ============================================
    handleEditIdentity() {
        this.editPronouns = this.profile.pronouns || '';
        this.editFirstName = this.profile.firstName || '';
        this.editLastName = this.profile.lastName || '';
        this.isEditingIdentity = true;
    }
    handleCancelIdentity() { this.isEditingIdentity = false; }
    async handleSaveIdentity() {
        await this._saveSection({
            'FirstName': this.editFirstName,
            'LastName': this.editLastName,
            'Pronouns__c': this.editPronouns
        }, 'isEditingIdentity');
    }

    // ============================================
    // CONTACT INFO SECTION EDIT
    // ============================================
    handleEditContact() {
        this.editEmail = this.profile.email || '';
        this.editPhone = this.profile.phone || '';
        this.editStreet = this.profile.mailingStreet || '';
        this.editCity = this.profile.mailingCity || '';
        this.editState = this.profile.mailingState || '';
        this.editPostalCode = this.profile.mailingPostalCode || '';
        this.editCountry = this.profile.mailingCountry || '';
        this.isEditingContact = true;
    }
    handleCancelContact() { this.isEditingContact = false; }
    async handleSaveContact() {
        await this._saveSection({
            'Email': this.editEmail,
            'Phone': this.editPhone,
            'MailingStreet': this.editStreet,
            'MailingCity': this.editCity,
            'MailingState': this.editState,
            'MailingPostalCode': this.editPostalCode,
            'MailingCountry': this.editCountry
        }, 'isEditingContact');
    }

    // ============================================
    // ABOUT YOU SECTION EDIT
    // ============================================
    handleEditAbout() {
        this.editAboutTenure = this.profile.aboutNeighbourhoodTenure || '';
        this.editAboutBroughtYou = this.profile.aboutWhatBroughtYou || '';
        this.editAboutLocalPlace = this.profile.aboutLocalPlace || '';
        this.editAboutEnjoys = this.profile.aboutEnjoysDoing || '';
        this.editAboutFunFact = this.profile.aboutFunFact || '';
        this.editLanguages = this._parseMultiSelect(this.profile.languagesSpoken);
        this.isEditingAbout = true;
    }
    handleCancelAbout() { this.isEditingAbout = false; }
    async handleSaveAbout() {
        await this._saveSection({
            'About_Neighbourhood_Tenure__c': this.editAboutTenure,
            'About_What_Brought_You__c': this.editAboutBroughtYou,
            'About_Local_Place__c': this.editAboutLocalPlace,
            'About_Enjoys_Doing__c': this.editAboutEnjoys,
            'About_Fun_Fact__c': this.editAboutFunFact,
            'Languages_Spoken__c': this.editLanguages.join(';')
        }, 'isEditingAbout');
    }

    // ============================================
    // ACCESSIBILITY & AVAILABILITY SECTION EDIT
    // ============================================
    handleEditAccessibility() {
        this.editAccessibility = this.profile.accessibilityNotes || '';
        this.editAvailability = this._parseMultiSelect(this.profile.generalAvailability);
        this.isEditingAccessibility = true;
    }
    handleCancelAccessibility() { this.isEditingAccessibility = false; }
    async handleSaveAccessibility() {
        await this._saveSection({
            'Accessibility_Notes__c': this.editAccessibility,
            'General_Availability__c': this.editAvailability.join(';')
        }, 'isEditingAccessibility');
    }

    // ============================================
    // CARE PREFERENCES SECTION EDIT
    // ============================================
    handleEditCare() {
        this.editCareWelcome = this._parseMultiSelect(this.profile.careWelcomeSupport);
        this.editCareUnhelpful = this._parseMultiSelect(this.profile.careUnhelpfulThings);
        this.editCareHowToAsk = this.profile.careHowToAsk || '';
        this.editCareHardNos = this.profile.careHardNos || '';
        this.isEditingCare = true;
    }
    handleCancelCare() { this.isEditingCare = false; }
    async handleSaveCare() {
        await this._saveSection({
            'Care_Welcome_Support__c': this.editCareWelcome.join(';'),
            'Care_Unhelpful_Things__c': this.editCareUnhelpful.join(';'),
            'Care_How_To_Ask__c': this.editCareHowToAsk,
            'Care_Hard_Nos__c': this.editCareHardNos
        }, 'isEditingCare');
    }

    // ============================================
    // INPUT HANDLERS
    // ============================================
    handleInputChange(event) {
        const field = event.target.dataset.field;
        if (field) {
            this[field] = event.target.value;
        }
    }

    handleCheckboxChange(event) {
        const { group, value } = event.target.dataset;
        const checked = event.target.checked;
        const arr = [...this[group]];
        if (checked) {
            if (!arr.includes(value)) arr.push(value);
        } else {
            const idx = arr.indexOf(value);
            if (idx > -1) arr.splice(idx, 1);
        }
        this[group] = arr;
    }

    handleRadioChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;
    }

    // ============================================
    // AVATAR HANDLERS
    // ============================================
    handleAvatarClick() {
        this.showImageUploader = !this.showImageUploader;
    }

    handlePhotoUploaded() {
        this.showImageUploader = false;
        this.showToast('Success', 'Photo updated.', 'success');
        this.loadProfile();
    }

    async handleRemoveAvatar() {
        try {
            await removeImage({
                recordId: this.profile.contactId,
                objectApiName: 'Contact',
                imageSlot: null
            });
            this.showToast('Success', 'Photo removed.', 'success');
            await this.loadProfile();
        } catch (error) {
            this.showToast('Error', 'Could not remove photo.', 'error');
        }
    }

    // ============================================
    // SHARED HELPERS
    // ============================================
    async _saveSection(fieldMap, editFlag) {
        this.isSaving = true;
        try {
            await updateProfileSection({ fieldValues: fieldMap });
            this[editFlag] = false;
            this.showToast('Saved', 'Profile updated.', 'success');
            await this.loadProfile();
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Could not save changes.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    _parseMultiSelect(val) {
        if (!val) return [];
        return val.split(';').map(s => s.trim()).filter(Boolean);
    }

    _multiSelectToDisplay(val) {
        if (!val) return '';
        return val.split(';').map(s => s.trim()).filter(Boolean).join(', ');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleBack() {
        if (window.history.length > 1) {
            window.history.back();
        } else {
            location.href = '/my-stuff';
        }
    }

    async _checkIfModerator() {
        try {
            const ctx = await getModeratorContext();
            this.isProfileModerator = ctx.isModerator;
        } catch (e) {
            this.isProfileModerator = false;
        }
    }

    handleTabChange(event) {
        location.href = '/' + (event.detail.tab === 'home' ? '' : event.detail.tab);
    }
}