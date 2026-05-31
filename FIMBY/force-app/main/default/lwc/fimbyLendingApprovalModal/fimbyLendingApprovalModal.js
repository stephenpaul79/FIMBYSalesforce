import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

import getLendingRequestForApproval from '@salesforce/apex/FimbyLendingController.getLendingRequestForApproval';
import approveLendingRequest from '@salesforce/apex/FimbyLendingController.approveLendingRequest';
import declineLendingRequest from '@salesforce/apex/FimbyLendingController.declineLendingRequest';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import { formatLocalDate } from 'c/fimbyDateUtils';

export default class FimbyLendingApprovalModal extends LightningElement {

    @track _isVisible = false;
    @track _viewState = 'loading'; // loading | form | shareContact | submitting | success | error
    @track _errorMessage = '';

    _recordId = '';

    // Apex data
    @track lendingRequest;
    @track libraryItem;
    @track requesterName;
    @track ownerContact;

    // Decision form
    @track decision = 'approve';
    @track pickupDate;
    @track declineReason = '';
    @track riskAcknowledged = false;

    // Share contact info
    @track shareEmail = true;
    @track sharePhone = true;
    @track shareAddress = false;
    @track emailToShare = '';
    @track phoneToShare = '';
    @track streetToShare = '';
    @track cityToShare = '';
    @track stateToShare = '';
    @track postalCodeToShare = '';
    @track countryToShare = '';
    @track additionalInfo = '';

    // Identity
    @track actingAsContact = null;
    @track hasMultipleIdentities = false;

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading acting-as contact:', error);
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

    get postingAsDisplayName() {
        return this.actingAsContact?.postingAsDisplayName
            || this.actingAsContact?.actingAsContactName
            || this.actingAsContact?.contactName
            || '';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.postingAsDisplayName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    // ── Public API ──────────────────────────────────────────────────

    @api
    show(recordId) {
        this._recordId = recordId;
        this._isVisible = true;
        this._viewState = 'loading';
        this._resetForm();
        this._loadRequest();
    }

    @api
    hide() {
        this.dispatchEvent(new CustomEvent('approvalmodalclosed', {
            bubbles: true,
            composed: true
        }));
        this._isVisible = false;
        this._resetForm();
    }

    // ── Lifecycle ───────────────────────────────────────────────────

    disconnectedCallback() {
        this._isVisible = false;
    }

    // ── Icons ───────────────────────────────────────────────────────

    get noProfilePhotoUrl() { return `${IMPACT_ICONS}/NoProfilePhoto.png`; }

    // ── View state getters ──────────────────────────────────────────

    get isLoading() { return this._viewState === 'loading'; }
    get isForm() { return this._viewState === 'form'; }
    get isShareContact() { return this._viewState === 'shareContact'; }
    get isSubmitting() { return this._viewState === 'submitting'; }
    get isSuccess() { return this._viewState === 'success'; }
    get isError() { return this._viewState === 'error'; }
    get isAlreadyHandled() { return this._viewState === 'alreadyHandled'; }

    // ── Decision getters ────────────────────────────────────────────

    get isApproveDecision() { return this.decision === 'approve'; }
    get isDeclineDecision() { return this.decision === 'decline'; }

    get approveRadioClass() {
        return 'radio-option' + (this.isApproveDecision ? ' selected' : '');
    }
    get declineRadioClass() {
        return 'radio-option' + (this.isDeclineDecision ? ' selected' : '');
    }

    get requestDetails() {
        if (!this.lendingRequest) return '';
        const raw = this.lendingRequest.requestedDate;
        const formatted = (raw && raw !== 'Not specified') ? formatLocalDate(raw) : '';
        const date = formatted || 'TBD';
        const days = this.lendingRequest.daysNeeded || '?';
        return `Starting ${date} for ${days} day(s)`;
    }

    get requesterAvatar() {
        return this.lendingRequest?.requesterAvatar || '';
    }
    get hasRequesterAvatar() {
        return !!this.requesterAvatar;
    }

    get modalTitle() {
        if (this.isShareContact) return 'Share Contact Info';
        return 'Review Request';
    }

    // ── Approve form validation ─────────────────────────────────────

    get canSubmitApprove() {
        return this.pickupDate && this.riskAcknowledged;
    }

    get canSubmitDecline() {
        return this.declineReason && this.declineReason.trim().length > 0;
    }

    get isSubmitDisabled() {
        if (this.isApproveDecision) return !this.canSubmitApprove;
        return !this.canSubmitDecline;
    }

    get submitButtonLabel() {
        return this.isApproveDecision ? 'Approve Request' : 'Decline Request';
    }

    get submitButtonClass() {
        return this.isApproveDecision ? 'submit-btn approve' : 'submit-btn decline';
    }

    // ── Share contact validation ────────────────────────────────────

    get atLeastOneShareSelected() {
        return this.shareEmail || this.sharePhone || this.shareAddress;
    }

    get isShareDisabled() {
        return !this.atLeastOneShareSelected;
    }

    // ── Event handlers: modal chrome ────────────────────────────────

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) this.hide();
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.hide();
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') this.hide();
    }

    // ── Event handlers: decision form ───────────────────────────────

    handleSelectApprove() { this.decision = 'approve'; }
    handleSelectDecline() { this.decision = 'decline'; }

    handlePickupDateChange(event) {
        this.pickupDate = event.target.value;
    }

    handleDeclineReasonChange(event) {
        this.declineReason = event.target.value;
    }

    handleRiskAcknowledgedChange(event) {
        this.riskAcknowledged = event.target.checked;
    }

    // ── Event handlers: share contact ───────────────────────────────

    handleShareEmailChange(event) { this.shareEmail = event.target.checked; }
    handleSharePhoneChange(event) { this.sharePhone = event.target.checked; }
    handleShareAddressChange(event) { this.shareAddress = event.target.checked; }
    handleEmailChange(event) { this.emailToShare = event.target.value; }
    handlePhoneChange(event) { this.phoneToShare = event.target.value; }
    handleStreetChange(event) { this.streetToShare = event.target.value; }
    handleCityChange(event) { this.cityToShare = event.target.value; }
    handleStateChange(event) { this.stateToShare = event.target.value; }
    handlePostalCodeChange(event) { this.postalCodeToShare = event.target.value; }
    handleCountryChange(event) { this.countryToShare = event.target.value; }
    handleAdditionalInfoChange(event) { this.additionalInfo = event.target.value; }

    // ── Submit: step 1 ──────────────────────────────────────────────

    handleSubmit() {
        if (this.isApproveDecision) {
            if (!this.canSubmitApprove) return;
            this._viewState = 'shareContact';
        } else {
            if (!this.canSubmitDecline) return;
            this._processDecline();
        }
    }

    handleBackToForm() {
        this._viewState = 'form';
    }

    // ── Submit: step 2 (approve + share) ────────────────────────────

    async handleShareAndApprove() {
        if (!this.atLeastOneShareSelected) return;
        this._viewState = 'submitting';

        try {
            const shareData = {
                shareEmail: this.shareEmail,
                sharePhone: this.sharePhone,
                shareAddress: this.shareAddress,
                email: this.emailToShare,
                phone: this.phoneToShare,
                street: this.streetToShare,
                city: this.cityToShare,
                state: this.stateToShare,
                postalCode: this.postalCodeToShare,
                country: this.countryToShare,
                additionalInfo: this.additionalInfo
            };

            const result = await approveLendingRequest({
                recordId: this._recordId,
                pickupDate: this.pickupDate,
                shareContactData: JSON.stringify(shareData)
            });

            if (result.success) {
                this._viewState = 'success';
                this._notifyComplete();
            } else {
                this._errorMessage = result.message || 'Something went wrong approving the request.';
                this._viewState = 'error';
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    // ── Submit: decline ─────────────────────────────────────────────

    async _processDecline() {
        this._viewState = 'submitting';

        try {
            const result = await declineLendingRequest({
                recordId: this._recordId,
                declineReason: this.declineReason
            });

            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Request Declined',
                    message: 'The requester has been notified.',
                    variant: 'info'
                }));
                this._notifyComplete();
                this.hide();
            } else {
                this._errorMessage = result.message || 'Something went wrong declining the request.';
                this._viewState = 'error';
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    // ── Data loading ────────────────────────────────────────────────

    async _loadRequest() {
        try {
            const result = await getLendingRequestForApproval({ recordId: this._recordId });

            if (result.success) {
                this.lendingRequest = result.lendingRequest;
                this.libraryItem = result.libraryItem;
                this.requesterName = result.requesterName;
                this.ownerContact = result.ownerContact;

                if (this.ownerContact) {
                    this.emailToShare = this.ownerContact.email || '';
                    this.phoneToShare = this.ownerContact.phone || '';
                    this.streetToShare = this.ownerContact.mailingStreet || '';
                    this.cityToShare = this.ownerContact.mailingCity || '';
                    this.stateToShare = this.ownerContact.mailingState || '';
                    this.postalCodeToShare = this.ownerContact.mailingPostalCode || '';
                    this.countryToShare = this.ownerContact.mailingCountry || '';
                }

                this.pickupDate = new Date().toISOString().split('T')[0];
                this._viewState = 'form';
            } else {
                this._errorMessage = result.message || 'Unable to load this request.';
                // Idempotency: server state has moved on. Close + refresh parent banner
                // rather than show a dead-end "already took action" wall.
                this.hide();
                return;
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong loading the request.';
            this._viewState = 'error';
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────

    _notifyComplete() {
        this.dispatchEvent(new CustomEvent('approvalcomplete', {
            bubbles: true,
            composed: true,
            detail: { requestId: this._recordId }
        }));
    }

    handleSuccessDone() {
        this.hide();
    }

    handleRetry() {
        this._loadRequest();
    }

    _resetForm() {
        this.lendingRequest = null;
        this.libraryItem = null;
        this.requesterName = '';
        this.ownerContact = null;
        this._errorMessage = '';

        this.decision = 'approve';
        this.pickupDate = '';
        this.declineReason = '';
        this.riskAcknowledged = false;

        this.shareEmail = true;
        this.sharePhone = true;
        this.shareAddress = false;
        this.emailToShare = '';
        this.phoneToShare = '';
        this.streetToShare = '';
        this.cityToShare = '';
        this.stateToShare = '';
        this.postalCodeToShare = '';
        this.countryToShare = '';
        this.additionalInfo = '';
    }
}