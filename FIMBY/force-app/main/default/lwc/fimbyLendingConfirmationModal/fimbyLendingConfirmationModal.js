import { LightningElement, api, track, wire } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getLendingRequestForConfirmation from '@salesforce/apex/FimbyLendingController.getLendingRequestForConfirmation';
import confirmLendingRequest from '@salesforce/apex/FimbyLendingController.confirmLendingRequest';
import cancelLendingRequest from '@salesforce/apex/FimbyLendingController.cancelLendingRequest';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

export default class FimbyLendingConfirmationModal extends LightningElement {

    @track _isVisible = false;
    @track _viewState = 'loading'; // loading | form | submitting | success | error
    @track _errorMessage = '';

    _recordId = '';

    @track lendingRequest;
    @track decision = '';
    @track borrowDate = '';

    // Success messaging (set after submit based on decision)
    @track _successTitle = '';
    @track _successSubtitle = '';
    @track _wasConfirmed = false;

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
    show(requestId) {
        this._recordId = requestId;
        this._isVisible = true;
        this._viewState = 'loading';
        this._resetForm();
        this._loadRequest();
    }

    @api
    hide() {
        this.dispatchEvent(new CustomEvent('confirmationmodalclosed', {
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

    // ── View state getters ──────────────────────────────────────────

    get isLoading() { return this._viewState === 'loading'; }
    get isForm() { return this._viewState === 'form'; }
    get isSubmitting() { return this._viewState === 'submitting'; }
    get isSuccess() { return this._viewState === 'success'; }
    get isError() { return this._viewState === 'error'; }
    get isAlreadyHandled() { return this._viewState === 'alreadyHandled'; }

    // ── Decision getters ────────────────────────────────────────────

    get isYesDecision() { return this.decision === 'yes'; }
    get isNoDecision() { return this.decision === 'no'; }

    get yesRadioClass() {
        return 'radio-option' + (this.decision === 'yes' ? ' selected' : '');
    }
    get noRadioClass() {
        return 'radio-option' + (this.decision === 'no' ? ' selected' : '');
    }

    get requestInfo() {
        if (!this.lendingRequest) return '';
        const owner = this.lendingRequest.ownerFirstName || 'the owner';
        const item = this.lendingRequest.itemName || 'this item';
        // createdDate is a Datetime (CreatedDate from Salesforce) so the standard parser is fine here.
        const date = this.lendingRequest.createdDate
            ? new Date(this.lendingRequest.createdDate).toLocaleDateString()
            : '';
        return date
            ? `You requested to borrow ${owner}'s "${item}" on ${date}.`
            : `You requested to borrow ${owner}'s "${item}".`;
    }

    get todayDate() {
        return new Date().toISOString().split('T')[0];
    }

    // ── Form validation ─────────────────────────────────────────────

    get canSubmit() {
        if (this.decision === 'yes') return !!this.borrowDate;
        if (this.decision === 'no') return true;
        return false;
    }

    get isSubmitDisabled() {
        return !this.canSubmit;
    }

    get submitButtonLabel() {
        if (this.decision === 'yes') return 'Confirm';
        if (this.decision === 'no') return 'Cancel Request';
        return 'Submit';
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

    // ── Event handlers: form ────────────────────────────────────────

    handleSelectYes() { this.decision = 'yes'; }
    handleSelectNo() { this.decision = 'no'; }

    handleBorrowDateChange(event) {
        this.borrowDate = event.target.value;
    }

    // ── Submit ──────────────────────────────────────────────────────

    async handleSubmit() {
        if (!this.canSubmit) return;
        this._viewState = 'submitting';

        try {
            if (this.decision === 'yes') {
                await this._processConfirm();
            } else {
                await this._processCancel();
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    async _processConfirm() {
        const result = await confirmLendingRequest({
            recordId: this._recordId,
            borrowDate: this.borrowDate
        });

        if (result.success) {
            this._wasConfirmed = true;
            this._successTitle = "We've let the owner know!";
            this._successSubtitle = 'Your request is now waiting for the owner to approve it.';
            this._viewState = 'success';
            this._notifyComplete();
        } else {
            this._errorMessage = result.message || 'Something went wrong confirming your request.';
            this._viewState = 'error';
        }
    }

    async _processCancel() {
        const result = await cancelLendingRequest({
            recordId: this._recordId
        });

        if (result.success) {
            this._wasConfirmed = false;
            this._successTitle = 'Thank you for letting us know.';
            this._successSubtitle = "We've removed your request from the waitlist.";
            this._viewState = 'success';
            this._notifyComplete();
        } else {
            this._errorMessage = result.message || 'Something went wrong cancelling your request.';
            this._viewState = 'error';
        }
    }

    // ── Data loading ────────────────────────────────────────────────

    async _loadRequest() {
        try {
            const result = await getLendingRequestForConfirmation({ recordId: this._recordId });

            if (result.success) {
                this.lendingRequest = result.lendingRequest;
                this.borrowDate = new Date().toISOString().split('T')[0];
                this._viewState = 'form';
            } else {
                const err = result.error;
                if (err === 'notOnWaitlist' || err === 'notFirst' || err === 'notConfirmable') {
                    this._viewState = 'alreadyHandled';
                } else {
                    this._errorMessage = result.message || 'Unable to load this request.';
                    this._viewState = 'error';
                }
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong loading the request.';
            this._viewState = 'error';
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────

    _notifyComplete() {
        this.dispatchEvent(new CustomEvent('confirmationcomplete', {
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
        this._errorMessage = '';
        this.decision = '';
        this.borrowDate = '';
        this._successTitle = '';
        this._successSubtitle = '';
        this._wasConfirmed = false;
    }
}