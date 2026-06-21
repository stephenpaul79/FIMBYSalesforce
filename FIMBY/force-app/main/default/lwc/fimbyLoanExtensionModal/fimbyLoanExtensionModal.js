import { LightningElement, api, track, wire } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

import getLoanedItemForExtension from '@salesforce/apex/FimbyLendingController.getLoanedItemForExtension';
import requestLoanExtension from '@salesforce/apex/FimbyLendingController.requestLoanExtension';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

const MS_PER_DAY = 1000 * 60 * 60 * 24;

export default class FimbyLoanExtensionModal extends LightningElement {

    @track _isVisible = false;
    @track _viewState = 'loading';
    @track _errorMessage = '';

    _recordId = '';

    @track loanedItem;
    @track libraryItem;
    @track isOwner = false;
    @track requestedDueDate;

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

    get identityLabel() {
        return this.isOwner ? 'Extending as:' : 'Requesting as:';
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
        this.dispatchEvent(new CustomEvent('extensionmodalclosed', {
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

    get isLoading()    { return this._viewState === 'loading'; }
    get isForm()       { return this._viewState === 'form'; }
    get isSubmitting() { return this._viewState === 'submitting'; }
    get isSuccess()    { return this._viewState === 'success'; }
    get isError()      { return this._viewState === 'error'; }
    get isAlreadyHandled() { return this._viewState === 'alreadyHandled'; }

    // ── Form getters ────────────────────────────────────────────────

    get minDueDate() {
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);

        if (this.loanedItem?.dueDate) {
            const currentDue = new Date(this.loanedItem.dueDate);
            currentDue.setDate(currentDue.getDate() + 1);
            return currentDue > tomorrow
                ? currentDue.toISOString().split('T')[0]
                : tomorrow.toISOString().split('T')[0];
        }
        return tomorrow.toISOString().split('T')[0];
    }

    get canSubmit() {
        if (!this.requestedDueDate) return false;

        const requestedDate = new Date(this.requestedDueDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        if (requestedDate <= today) return false;

        if (this.loanedItem?.dueDate) {
            const currentDue = new Date(this.loanedItem.dueDate);
            if (requestedDate <= currentDue) return false;
        }

        return true;
    }

    get isSubmitDisabled() {
        return !this.canSubmit;
    }

    get daysOnLoan() {
        if (!this.loanedItem?.startDate) return 0;
        const start = new Date(this.loanedItem.startDate);
        const today = new Date();
        return Math.floor((today - start) / MS_PER_DAY);
    }

    get ownerNote() {
        return 'As the owner of this item, the due date will be immediately updated, and an email sent to the borrower to let them know of the extension.';
    }

    get borrowerNote() {
        return 'The owner of this item needs to approve the extension before the due date is updated. You will receive an email once they have approved or declined your request.';
    }

    get submitLabel() {
        return this.isOwner ? 'Extend Due Date' : 'Request Extension';
    }

    get celebrationActionType() {
        return this.isOwner ? 'extension-set' : 'extension-requested';
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

    handleDueDateChange(event) {
        this.requestedDueDate = event.target.value;
    }

    // ── Submit ──────────────────────────────────────────────────────

    async handleSubmit() {
        if (!this.canSubmit) return;

        this._viewState = 'submitting';

        try {
            const result = await requestLoanExtension({
                recordId: this._recordId,
                newDueDate: this.requestedDueDate
            });

            if (result.success) {
                if (result.approved) {
                    this._successTitle = 'Extension Approved!';
                    this._successSubtitle = `We will let ${result.borrowerName} know about the extension. Thank you for being so generous with your belongings!`;
                } else {
                    this._successTitle = 'Extension Requested!';
                    this._successSubtitle = `We will let ${result.ownerName} know about the extension request. You will be emailed once they approve or decline the request. Thank you for being thoughtful and not just keeping the item past due!`;
                }
                this._viewState = 'success';
                this._notifyComplete();
            } else if (result.error === 'extensionPending') {
                this._notifyComplete();
                this.hide();
            } else {
                this._errorMessage = result.message || 'Something went wrong processing the extension.';
                this._viewState = 'error';
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    // ── Success / Error actions ─────────────────────────────────────

    handleSuccessDone() {
        this.hide();
    }

    handleRetry() {
        this._loadLoanedItem();
    }

    // ── Data loading ────────────────────────────────────────────────

    async _loadLoanedItem() {
        this._viewState = 'loading';

        try {
            const result = await getLoanedItemForExtension({ recordId: this._recordId });

            if (result.success) {
                this.loanedItem = result.loanedItem;
                this.libraryItem = result.libraryItem;
                this.isOwner = result.isOwner;

                if (this.loanedItem.dueDate) {
                    const dueDate = new Date(this.loanedItem.dueDate);
                    dueDate.setDate(dueDate.getDate() + 7);
                    this.requestedDueDate = dueDate.toISOString().split('T')[0];
                }

                this._viewState = 'form';
            } else {
                const err = result.error;
                if (err === 'extensionPending' || err === 'waitlist' || err === 'notAuthorized') {
                    this._notifyComplete();
                    this.hide();
                    return;
                }
                this._errorMessage = result.message || 'Unable to load loan details.';
                this.hide();
                
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong loading loan details.';
            this._viewState = 'error';
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────

    _notifyComplete() {
        this.dispatchEvent(new CustomEvent('extensioncomplete', {
            bubbles: true,
            composed: true,
            detail: { loanId: this._recordId }
        }));
    }

    _resetForm() {
        this.loanedItem = null;
        this.libraryItem = null;
        this.isOwner = false;
        this.requestedDueDate = undefined;
        this._errorMessage = '';
        this._successTitle = '';
        this._successSubtitle = '';
    }
}