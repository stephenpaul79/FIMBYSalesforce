import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import createNeedsOffersPost from '@salesforce/apex/FimbyAskOfferController.createNeedsOffersPost';
import getBioPostStatus from '@salesforce/apex/FimbyOnboardingController.getBioPostStatus';

const STEP_TYPE_SELECTION = 1;
const STEP_FORM = 2;
const STEP_PHOTO = 3;
const STEP_CONFIRMATION = 4;

const BIO_GATE_SESSION_KEY = 'fimby_bio_gate_dismissed';

export default class FimbyAskOfferComposer extends NavigationMixin(LightningElement) {
    @track currentStep = STEP_TYPE_SELECTION;
    @track preselectedFromUrl = false;
    @track selectedType = '';
    @track selectedTypeValue = '';

    @track actingAsContact = null;
    @track isLoadingContact = true;
    @track hasMultipleIdentities = false;

    @track postTitle = '';
    @track postDescription = '';

    @track quantity = 1;
    @track perResponseLimit = 1;

    @track eventStart = '';
    @track eventEnd = '';
    @track endDate = '';
    @track location = '';

    @track eventType = 'Gathering';
    @track expectedAttendance = '';
    @track eventNotes = '';
    @track eventLink = '';

    @track isUrgent = false;
    @track autoAcceptResponses = false;
    @track autoShareContactInfo = false;

    @track createdRecordId = null;
    @track isPosting = false;
    @track confirmationTitle = '';

    @track _showBioGate = false;
    @track _showIntroPostModal = false;

    connectedCallback() {
        this._checkBioGate();

        const urlParams = new URLSearchParams(window.location.search);
        const typeParam = urlParams.get('type');

        if (typeParam) {
            const normalized = typeParam.charAt(0).toUpperCase() + typeParam.slice(1).toLowerCase();

            if (normalized === 'Bulkbuy') {
                this.selectedType = 'BulkBuy';
            } else if (normalized === 'Event') {
                this.selectedType = 'Offer';
                this.selectedTypeValue = 'Event';
                this.endDate = this._endDateOffset(21);
            } else if (normalized === 'Need' || normalized === 'Offer') {
                this.selectedType = normalized;
                this.selectedTypeValue = normalized === 'Need' ? 'Need' : '';
                this.endDate = this._endDateOffset(normalized === 'Need' ? 7 : 21);
            }

            this.preselectedFromUrl = true;
            this.currentStep = STEP_FORM;
        }
    }

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        this.isLoadingContact = false;
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading contact:', error);
            this.showErrorToast('Error loading user information');
        }
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this.hasMultipleIdentities = data.length > 0;
        } else if (error) {
            console.error('Error loading identities:', error);
            this.hasMultipleIdentities = false;
        }
    }

    // ============================================
    // ICONS
    // ============================================

    get needIconUrl() { return `${IMPACT_ICONS}/needsm.png`; }
    get offerIconUrl() { return `${IMPACT_ICONS}/giftsm.png`; }
    get posterIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }
    get postDetailsIconUrl() { return `${IMPACT_ICONS}/BulletinBoardActive.png`; }
    get eventDetailsIconUrl() { return `${IMPACT_ICONS}/plannersm.png`; }
    get settingsIconUrl() { return `${IMPACT_ICONS}/gear.png`; }
    get bulkBuyIconUrl() { return `${IMPACT_ICONS}/bulkbuy.png`; }
    get rsvpIconUrl() { return `${IMPACT_ICONS}/rsvp.png`; }
    get diningTableIconUrl() { return `${IMPACT_ICONS}/dining-table.png`; }
    get peopleIconUrl() { return `${IMPACT_ICONS}/people.png`; }
    get cityscapeIconUrl() { return `${IMPACT_ICONS}/cityscape.png`; }

    // ============================================
    // STEP VISIBILITY
    // ============================================

    get showPageHeader() {
        return !this.isLoadingContact && (this.currentStep === STEP_TYPE_SELECTION || this.currentStep === STEP_FORM);
    }

    get showTypeSelection() {
        return this.currentStep === STEP_TYPE_SELECTION && !this.isLoadingContact;
    }

    get showForm() {
        return this.currentStep === STEP_FORM && !this.isBulkBuy && !this.isLoadingContact;
    }

    get showBulkBuyForm() {
        return this.currentStep === STEP_FORM && this.isBulkBuy && !this.isLoadingContact;
    }

    get showPhotoStep() {
        return this.currentStep === STEP_PHOTO;
    }

    get showConfirmation() {
        return this.currentStep === STEP_CONFIRMATION;
    }

    // ============================================
    // TYPE HELPERS
    // ============================================

    get isNeed() { return this.selectedType === 'Need'; }
    get isOffer() { return this.selectedType === 'Offer' && this.selectedTypeValue !== 'Event'; }
    get isBulkBuy() { return this.selectedType === 'BulkBuy'; }
    get isEventType() { return this.selectedTypeValue === 'Event'; }
    get isOfferOrEvent() { return this.selectedType === 'Offer'; }

    get isGathering() { return this.isEventType && this.eventType === 'Gathering'; }
    get isOpenEvent() { return this.isEventType && this.eventType === 'Open_Event'; }
    get isCommunityEvent() { return this.isEventType && this.eventType === 'Community_Event'; }

    get showQuantityField() {
        return this.isOffer || this.isGathering;
    }

    get showPerResponseLimit() {
        return (this.isOffer || this.isGathering) && this.quantity > 1;
    }

    get showExpectedAttendance() {
        return this.isOpenEvent;
    }

    get showEventNotes() {
        return this.isOpenEvent || this.isCommunityEvent;
    }

    get showEventLink() {
        return this.isCommunityEvent;
    }

    get showAutoAcceptSection() {
        return this.isGathering || !this.isEventType;
    }

    get showAutoShareSection() {
        return this.isGathering || !this.isEventType;
    }

    get showPostSettingsSection() {
        return this.showAutoAcceptSection || this.showAutoShareSection;
    }

    get eventTypeInfoText() {
        if (this.isOpenEvent) {
            return 'Responses are automatically accepted. Your contact details are not shown to attendees. You can message attendees directly from your event page.';
        }
        if (this.isCommunityEvent) {
            return 'Your contact details are not shown. Interested neighbours can message you through FIMBY.';
        }
        return '';
    }

    get showEventTypeInfoBanner() {
        return this.isOpenEvent || this.isCommunityEvent;
    }

    // ============================================
    // PAGE TITLE & LABELS
    // ============================================

    get pageTitle() {
        if (this.currentStep === STEP_TYPE_SELECTION) return 'Create Post';
        if (this.isBulkBuy) return 'Post a Bulk Buy';
        if (this.isEventType) return 'Post an Event';
        return this.isNeed ? 'Post an Ask' : 'Post an Offer';
    }

    get readOnlyTypeLabel() {
        if (this.isEventType) return 'Event';
        if (this.isNeed) return 'Ask';
        if (this.isOffer) return 'Offer';
        return '';
    }

    get formSectionTitle() {
        if (this.isEventType) return 'Event Details';
        if (this.isNeed) return 'Your Ask';
        return 'Your Offer';
    }

    get quantityLabel() {
        return this.isGathering ? 'Spots Available' : 'Quantity Available';
    }

    get perResponseLimitLabel() {
        return this.isGathering ? 'Max RSVPs per Person' : 'Per Response Limit';
    }

    get autoAcceptLabel() {
        return this.isGathering ? 'Auto-Accept RSVPs' : 'Auto-Accept Responses';
    }

    get endDateLabel() {
        return this.isEventType ? 'Post Expires' : 'Post Expiration Date';
    }

    get eventNotesLabel() {
        return this.isOpenEvent ? 'What to Bring' : 'Additional Info';
    }

    get eventNotesPlaceholder() {
        return this.isOpenEvent
            ? 'e.g., Bring a lawn chair and a dish to share'
            : 'Venue details, parking, anything not in the link';
    }

    get titleCharacterCount() {
        return `${this.postTitle.length}/80`;
    }

    get descriptionCharacterCount() {
        return `${this.postDescription.length}/2000`;
    }

    get titleCountClass() {
        const len = this.postTitle.length;
        if (len >= 80) return 'character-count at-limit';
        if (len >= 72) return 'character-count near-limit';
        return 'character-count';
    }

    get descriptionCountClass() {
        const len = this.postDescription.length;
        if (len >= 2000) return 'character-count at-limit';
        if (len >= 1800) return 'character-count near-limit';
        return 'character-count';
    }

    get postingAsDisplayName() {
        return this.actingAsContact?.postingAsDisplayName || this.actingAsContact?.contactName || 'Loading...';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsContact;
    }

    get submitLabel() {
        if (this.isPosting) return 'Posting...';
        return 'Next';
    }

    get submitLabelHasChevron() {
        return !this.isPosting;
    }

    get navNextLabel() {
        return this.submitLabelHasChevron ? `  Next >` : this.submitLabel;
    }

    get isNextDisabled() {
        return !this.selectedType;
    }

    get isSubmitDisabled() {
        if (!this.postTitle.trim() || !this.postDescription.trim()) return true;
        if (this.showQuantityField && this.quantity < 1) return true;
        if (this.showPerResponseLimit && this.perResponseLimit > this.quantity) return true;
        if (this.isEventType && !this.eventStart) return true;
        if (this.isEventType && !this.isCommunityEvent && !this.location) return true;
        return this.isPosting;
    }

    get celebrationActionType() {
        if (this.isBulkBuy) return 'bulkbuy';
        if (this.isEventType) return 'event';
        return this.isNeed ? 'ask' : 'offer';
    }

    get confirmationTypeLabel() {
        if (this.isBulkBuy) return 'bulk buy';
        if (this.isEventType) return 'event';
        return this.isNeed ? 'ask' : 'offer';
    }

    // ============================================
    // BUTTON CLASSES
    // ============================================

    get needButtonClass() {
        return this.selectedType === 'Need' ? 'type-button selected' : 'type-button';
    }

    get offerButtonClass() {
        return this.selectedType === 'Offer' && this.selectedTypeValue !== 'Event' ? 'type-button selected' : 'type-button';
    }

    get eventButtonClass() {
        return this.selectedType === 'Offer' && this.selectedTypeValue === 'Event' ? 'type-button selected' : 'type-button';
    }

    get bulkBuyButtonClass() {
        return this.selectedType === 'BulkBuy' ? 'type-button selected' : 'type-button';
    }

    get gatheringButtonClass() { return this.eventType === 'Gathering' ? 'event-type-btn selected' : 'event-type-btn'; }
    get openEventButtonClass() { return this.eventType === 'Open_Event' ? 'event-type-btn selected' : 'event-type-btn'; }
    get communityEventButtonClass() { return this.eventType === 'Community_Event' ? 'event-type-btn selected' : 'event-type-btn'; }

    // ============================================
    // TYPE SELECTION HANDLERS
    // ============================================

    handleNeedSelect() {
        this.selectedType = 'Need';
        this.selectedTypeValue = 'Need';
    }

    handleOfferSelect() {
        this.selectedType = 'Offer';
        this.selectedTypeValue = '';
    }

    handleEventSelect() {
        this.selectedType = 'Offer';
        this.selectedTypeValue = 'Event';
    }

    handleBulkBuySelect() {
        this.selectedType = 'BulkBuy';
        this.selectedTypeValue = '';
    }

    handleNext() {
        if (!this.selectedType) return;

        this.resetForm();

        if (this.isNeed) {
            this.selectedTypeValue = 'Need';
            this.endDate = this._endDateOffset(7);
        } else if (this.isEventType) {
            this.selectedTypeValue = 'Event';
            this.endDate = this._endDateOffset(21);
        } else if (this.selectedType === 'Offer') {
            this.endDate = this._endDateOffset(21);
        }

        this.currentStep = STEP_FORM;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    // ============================================
    // EVENT TYPE SELECTION
    // ============================================

    handleEventTypeSelect(event) {
        const selected = event.currentTarget.dataset.eventType;
        this.eventType = selected;
        this._applyEventTypeDefaults(selected);
    }

    _applyEventTypeDefaults(evtType) {
        if (evtType === 'Gathering') {
            this.endDate = this._endDateOffset(21);
        } else if (evtType === 'Open_Event') {
            this.autoAcceptResponses = true;
            this.endDate = this._endDateOffset(21);
        } else if (evtType === 'Community_Event') {
            this.autoAcceptResponses = false;
            this.autoShareContactInfo = false;
            this.endDate = this._endDateOffset(28);
        }
    }

    // ============================================
    // FORM FIELD HANDLERS
    // ============================================

    handleTitleChange(event) { this.postTitle = event.target.value; }
    handleDescriptionChange(event) { this.postDescription = event.target.value; }
    handleEndDateChange(event) { this.endDate = event.target.value; }
    handleLocationChange(event) { this.location = event.target.value; }
    handleEventStartChange(event) { this.eventStart = event.target.value; }
    handleEventEndChange(event) { this.eventEnd = event.target.value; }
    handleExpectedAttendanceChange(event) { this.expectedAttendance = event.target.value; }
    handleEventNotesChange(event) { this.eventNotes = event.target.value; }
    handleEventLinkChange(event) { this.eventLink = event.target.value; }

    handleQuantityChange(event) {
        this.quantity = parseInt(event.target.value, 10) || 1;
        this.perResponseLimit = this.quantity;
    }

    handlePerResponseLimitChange(event) {
        const val = parseInt(event.target.value, 10) || 1;
        this.perResponseLimit = Math.min(Math.max(1, val), this.quantity);
    }

    handleUrgentChange(event) { this.isUrgent = event.target.checked; }
    handleAutoAcceptChange(event) { this.autoAcceptResponses = event.target.checked; }
    handleAutoShareChange(event) { this.autoShareContactInfo = event.target.checked; }

    // ============================================
    // SUBMIT
    // ============================================

    async handlePost() {
        if (this.isSubmitDisabled) return;

        this.isPosting = true;

        try {
            const postData = {
                postType: this.selectedType,
                title: this.postTitle.trim(),
                description: this.postDescription.trim(),
                type: this.isEventType ? 'Event' : null,
                isUrgent: this.isNeed ? this.isUrgent : false,
                quantity: this.showQuantityField ? this.quantity : null,
                perResponseLimit: this.showPerResponseLimit ? this.perResponseLimit : 1,
                endDate: this.endDate || null,
                autoAcceptResponses: this.isOpenEvent ? true : this.autoAcceptResponses,
                autoShareContactInfo: this.isCommunityEvent ? false : this.autoShareContactInfo
            };

            if (this.isEventType) {
                postData.eventStart = this.eventStart || null;
                postData.eventEnd = this.eventEnd || null;
                postData.location = this.location || null;
                postData.eventType = this.eventType;
                postData.expectedAttendance = this.showExpectedAttendance && this.expectedAttendance ? parseInt(this.expectedAttendance, 10) : null;
                postData.eventNotes = this.showEventNotes ? this.eventNotes.trim() || null : null;
                postData.eventLink = this.showEventLink ? this.eventLink.trim() || null : null;
            }

            const result = await createNeedsOffersPost({ postData: JSON.stringify(postData) });

            if (result.success) {
                this.createdRecordId = result.recordId;
                this.confirmationTitle = this.postTitle;
                this.currentStep = STEP_PHOTO;
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        } catch (error) {
            console.error('Post creation error:', error);
            this.showErrorToast(error.body?.message || 'Failed to create post. Please try again.');
        } finally {
            this.isPosting = false;
        }
    }

    handleBulkBuySubmit(event) {
        const { recordId, title } = event.detail;
        this.createdRecordId = recordId;
        this.confirmationTitle = title || 'Bulk Buy';
        this.currentStep = STEP_PHOTO;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    // ============================================
    // PHOTO & CONFIRMATION
    // ============================================

    handlePhotoUploaded() {
        this.currentStep = STEP_CONFIRMATION;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    handleSkipPhoto() {
        this.currentStep = STEP_CONFIRMATION;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    handleViewPost() {
        this._navigateToPost();
    }

    // ============================================
    // NAVIGATION
    // ============================================

    handleBack() {
        if (this.currentStep === STEP_CONFIRMATION || this.currentStep === STEP_PHOTO) {
            this._navigateToPost();
            return;
        }

        if (this.currentStep === STEP_FORM) {
            if (this.hasUnsavedChanges()) {
                // eslint-disable-next-line no-alert
                if (!confirm('You have unsaved changes. Are you sure you want to go back?')) {
                    return;
                }
            }
            this.resetForm();
            this.currentStep = STEP_TYPE_SELECTION;
            window.scrollTo({ top: 0, behavior: 'smooth' });
            return;
        }

        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'home' } });
    }

    hasUnsavedChanges() {
        return !!(this.postTitle.trim() || this.postDescription.trim());
    }

    // ============================================
    // PRIVATE HELPERS
    // ============================================

    resetForm() {
        this.postTitle = '';
        this.postDescription = '';
        this.quantity = 1;
        this.perResponseLimit = 1;
        this.isUrgent = false;
        this.eventStart = '';
        this.eventEnd = '';
        this.endDate = '';
        this.location = '';
        this.eventType = 'Gathering';
        this.expectedAttendance = '';
        this.eventNotes = '';
        this.eventLink = '';
        this.autoAcceptResponses = false;
        this.autoShareContactInfo = false;
    }

    _endDateOffset(days) {
        const d = new Date();
        d.setDate(d.getDate() + days);
        return d.toISOString().split('T')[0];
    }

    // ============================================
    // BIO SOFT GATE
    // ============================================

    get showBioGate()        { return this._showBioGate; }
    get showIntroPostModal() { return this._showIntroPostModal; }
    get bioGateIconUrl()     { return `${IMPACT_ICONS}/Wave.png`; }

    async _checkBioGate() {
        try {
            if (sessionStorage.getItem(BIO_GATE_SESSION_KEY)) return;
            const completed = await getBioPostStatus();
            if (completed === false) {
                this._showBioGate = true;
            }
        } catch (err) {
            console.error('fimbyAskOfferComposer: bio gate check failed', err);
        }
    }

    handleBioGateOpenModal() {
        this._showBioGate = false;
        this._showIntroPostModal = true;
        window.requestAnimationFrame(() => {
            const modal = this.template.querySelector('c-fimby-intro-post-modal');
            if (modal && typeof modal.show === 'function') {
                modal.show();
            }
        });
    }

    handleBioGateDismiss() {
        sessionStorage.setItem(BIO_GATE_SESSION_KEY, '1');
        this._showBioGate = false;
    }

    handleBioPosted() {
        this._showIntroPostModal = false;
        this._showBioGate = false;
    }

    handleBioSkipped() {
        sessionStorage.setItem(BIO_GATE_SESSION_KEY, '1');
        this._showIntroPostModal = false;
        this._showBioGate = false;
    }

    _navigateToPost() {
        if (this.createdRecordId) {
            window.location.href = '/asks-offers/' + this.createdRecordId;
        }
    }

    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }
}