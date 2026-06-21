import { LightningElement, api, track, wire } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

import getLoanedItemForExtensionApproval from '@salesforce/apex/FimbyLendingController.getLoanedItemForExtensionApproval';
import approveExtension from '@salesforce/apex/FimbyLendingController.approveExtension';
import declineExtension from '@salesforce/apex/FimbyLendingController.declineExtension';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

export default class FimbyLoanExtensionApprovalModal extends LightningElement {

    @track _isVisible = false;
    @track _viewState = 'loading';
    @track _errorMessage = '';

    _recordId = '';

    @track loanedItem;
    @track decision = 'approve';
    @track declineReason = '';

    @track _successTitle = '';
    @track _successSubtitle = '';

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
    show(loanId) {
        this._recordId = loanId;
        this._isVisible = true;
        this._viewState = 'loading';
        this._resetForm();
        this._loadLoanedItem();
    }

    @api
    hide() {
        this.dispatchEvent(new CustomEvent('extensionapprovalmodalclosed', {
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

    get isApproveDecision() { return this.decision === 'approve'; }
    get isDeclineDecision() { return this.decision === 'decline'; }

    get approveRadioClass() {
        return 'radio-option' + (this.isApproveDecision ? ' selected' : '');
    }
    get declineRadioClass() {
        return 'radio-option' + (this.isDeclineDecision ? ' selected' : '');
    }

    // ── Content getters ─────────────────────────────────────────────

    get loanContext() {
        if (!this.loanedItem) return '';
        return `${this.loanedItem.borrowerFirstName} has requested to extend the loan of your item, ${this.loanedItem.itemName}.`;
    }

    get requestedDateDisplay() {
        return this.loanedItem?.requestedDateDisplay || '';
    }

    get dueDateDisplay() {
        return this.loanedItem?.dueDateDisplay || '';
    }

    // ── Form validation ─────────────────────────────────────────────

    get canSubmit() {
        if (this.isApproveDecision) return true;
        return this.declineReason && this.declineReason.trim().length > 0 && this.declineReason.length <= 255;
    }

    get isSubmitDisabled() {
        return !this.canSubmit;
    }

    get submitButtonLabel() {
        return this.isApproveDecision ? 'Approve Extension' : 'Decline Extension';
    }

    get submitButtonClass() {
        return this.isApproveDecision ? 'submit-btn approve' : 'submit-btn decline';
    }

    get successTitleClass() {
        return this.isApproveDecision ? 'success-title' : 'neutral-title';
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

    handleSelectApprove() { this.decision = 'approve'; }
    handleSelectDecline() { this.decision = 'decline'; }

    handleDeclineReasonChange(event) {
        this.declineReason = event.target.value;
    }

    // ── Submit ───────────────────────────────────────────────────────

    async handleSubmit() {
        if (!this.canSubmit) return;
        this._viewState = 'submitting';

        try {
            if (this.isApproveDecision) {
                const result = await approveExtension({ recordId: this._recordId });

                if (result.success) {
                    this._successTitle = 'Extension Approved!';
                    this._successSubtitle = `Thank you for being so generous with your belongings. We will let ${result.borrowerName} know about the extension.`;
                    this._viewState = 'success';
                    this._notifyComplete();
                } else {
                    this._errorMessage = result.message || 'Something went wrong approving the extension.';
                    this._viewState = 'error';
                }
            } else {
                const result = await declineExtension({
                    recordId: this._recordId,
                    declineReason: this.declineReason
                });

                if (result.success) {
                    this._successTitle = 'Extension Declined';
                    this._successSubtitle = `Thank you for letting us know. We will let ${result.borrowerName} know that the due date needs to stay the same.`;
                    this._viewState = 'success';
                    this._notifyComplete();
                } else {
                    this._errorMessage = result.message || 'Something went wrong declining the extension.';
                    this._viewState = 'error';
                }
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    // ── Data loading ────────────────────────────────────────────────

    async _loadLoanedItem() {
        try {
            const result = await getLoanedItemForExtensionApproval({ recordId: this._recordId });

            if (result.success) {
                this.loanedItem = result.loanedItem;
                this._viewState = 'form';
            } else {
                this._errorMessage = result.message || 'Unable to load this extension request.';
                this.hide();
                
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong loading the extension request.';
            this._viewState = 'error';
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────

    _notifyComplete() {
        this.dispatchEvent(new CustomEvent('extensionapprovalcomplete', {
            bubbles: true,
            composed: true,
            detail: { loanId: this._recordId }
        }));
    }

    handleSuccessDone() {
        this.hide();
    }

    handleRetry() {
        this._loadLoanedItem();
    }

    _resetForm() {
        this.loanedItem = null;
        this._errorMessage = '';
        this._successTitle = '';
        this._successSubtitle = '';
        this.decision = 'approve';
        this.declineReason = '';
    }
}