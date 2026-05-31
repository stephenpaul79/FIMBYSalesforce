import { LightningElement, api, track, wire } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getLoanedItemForReturn from '@salesforce/apex/FimbyLendingController.getLoanedItemForReturn';
import submitBorrowerReturn from '@salesforce/apex/FimbyLendingController.submitBorrowerReturn';
import submitOwnerReturn from '@salesforce/apex/FimbyLendingController.submitOwnerReturn';
import getConditionPicklistValues from '@salesforce/apex/FimbyLendingController.getConditionPicklistValues';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

export default class FimbyItemReturnModal extends LightningElement {

    @track _isVisible = false;
    @track _viewState = 'loading';
    @track _errorMessage = '';

    _recordId = '';

    // Apex data
    @track _loanedItem;
    @track _libraryItem;
    @track _isOwner = false;
    @track _isBorrower = false;
    @track _conditionOptions = [];

    // Form fields
    @track _returnStatus = '';
    @track _dateReturned = '';
    @track _conditionUponReturn = '';
    @track _wouldLendAgain = '';
    @track _wouldBorrowAgain = '';

    // Success state
    @track _confirmationMessage = '';
    @track _isDamaged = false;

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
        if (this._isOwner) return 'Confirming return as:';
        if (this._isBorrower) return 'Returning as:';
        return 'Acting as:';
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
        this._loadData();
    }

    @api
    hide() {
        this.dispatchEvent(new CustomEvent('returnmodalclosed', {
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

    get modalTitle() {
        const name = this._libraryItem?.Name || 'Item';
        return `Return: ${name}`;
    }

    // ── Form state getters ──────────────────────────────────────────

    get returnedRadioClass() {
        return 'radio-option' + (this._returnStatus === 'Yes' ? ' selected' : '');
    }
    get damagedRadioClass() {
        return 'radio-option' + (this._returnStatus === 'Lost or Damaged' ? ' selected' : '');
    }

    get showOwnerFeedback() {
        return this._isOwner;
    }
    get showBorrowerFeedback() {
        return this._isBorrower && !this._isOwner;
    }

    get lendAgainYesClass() {
        return 'radio-option' + (this._wouldLendAgain === 'Yes' ? ' selected' : '');
    }
    get lendAgainNoClass() {
        return 'radio-option' + (this._wouldLendAgain === 'No' ? ' selected' : '');
    }
    get borrowAgainYesClass() {
        return 'radio-option' + (this._wouldBorrowAgain === 'Yes' ? ' selected' : '');
    }
    get borrowAgainNoClass() {
        return 'radio-option' + (this._wouldBorrowAgain === 'No' ? ' selected' : '');
    }

    get isSubmitDisabled() {
        if (!this._returnStatus || !this._dateReturned) return true;
        if (this._isOwner && !this._conditionUponReturn) return true;
        return false;
    }

    get borrowerName() {
        return this._loanedItem?.Requester_s_First_Name__c || 'the borrower';
    }
    get ownerName() {
        return this._loanedItem?.Item_Owner_s_First_Name__c || 'the owner';
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

    // ── Event handlers: form fields ─────────────────────────────────

    handleSelectReturned() { this._returnStatus = 'Yes'; }
    handleSelectDamaged() { this._returnStatus = 'Lost or Damaged'; }

    handleDateChange(event) { this._dateReturned = event.target.value; }
    handleConditionChange(event) { this._conditionUponReturn = event.target.value; }

    handleLendAgainYes() { this._wouldLendAgain = 'Yes'; }
    handleLendAgainNo() { this._wouldLendAgain = 'No'; }
    handleBorrowAgainYes() { this._wouldBorrowAgain = 'Yes'; }
    handleBorrowAgainNo() { this._wouldBorrowAgain = 'No'; }

    // ── Submit ──────────────────────────────────────────────────────

    async handleSubmit() {
        if (this.isSubmitDisabled) return;
        this._viewState = 'submitting';

        try {
            const isDamaged = this._returnStatus === 'Lost or Damaged';
            let result;

            if (this._isBorrower && !this._isOwner) {
                result = await submitBorrowerReturn({
                    recordId: this._recordId,
                    dateReturned: this._dateReturned,
                    isDamaged,
                    wouldBorrowAgain: this._wouldBorrowAgain
                });
            } else {
                result = await submitOwnerReturn({
                    recordId: this._recordId,
                    dateReturned: this._dateReturned,
                    isDamaged,
                    conditionUponReturn: this._conditionUponReturn,
                    wouldLendAgain: this._wouldLendAgain
                });
            }

            if (result.success) {
                this._isDamaged = isDamaged;
                this._confirmationMessage = this._buildConfirmationMessage(isDamaged);
                this._viewState = 'success';
                this._notifyComplete();
            } else {
                this._errorMessage = result.message || 'Something went wrong processing the return.';
                this._viewState = 'error';
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    // ── Success / retry handlers ────────────────────────────────────

    handleSuccessDone() {
        this.hide();
    }

    handleRetry() {
        this._loadData();
    }

    // ── Data loading ────────────────────────────────────────────────

    async _loadData() {
        this._viewState = 'loading';
        try {
            const [picklistResult, result] = await Promise.all([
                getConditionPicklistValues(),
                getLoanedItemForReturn({ recordId: this._recordId })
            ]);

            if (picklistResult) {
                this._conditionOptions = picklistResult.map(val => ({ label: val, value: val }));
            }

            if (result.success) {
                this._loanedItem = result.loanedItem;
                this._libraryItem = result.libraryItem;
                this._isOwner = result.isOwner;
                this._isBorrower = result.isBorrower;
                this._dateReturned = new Date().toISOString().split('T')[0];
                this._viewState = 'form';
            } else {
                this._errorMessage = this._mapErrorMessage(result.error);
                this._viewState = 'error';
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong loading return details.';
            this._viewState = 'error';
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────

    _mapErrorMessage(errorType) {
        const messages = {
            notAuthorized: 'You are not the owner or the borrower of this item.',
            alreadyReturned: 'This item has already been returned.'
        };
        return messages[errorType] || 'An error occurred. Please try again.';
    }

    _buildConfirmationMessage(isDamaged) {
        if (isDamaged) {
            return this._isOwner
                ? `Loving others is a risky business, and we are sorry to hear that things worked out like this! We hope that ${this.borrowerName} is able to make amends with you in whatever way they can.`
                : `We are sorry to hear that! FYI We have let ${this.ownerName} know of your update so they can follow up with you and confirm the details. Also, we would suggest you attempt to make amends with them in whatever way you can.`;
        }
        return this._isOwner
            ? 'You helped one of your neighbours! Thanks for your generous heart!!'
            : `Thanks for returning things in one piece!! PS We have let ${this.ownerName} know of your update so they can confirm the return as well.`;
    }

    _notifyComplete() {
        this.dispatchEvent(new CustomEvent('returncomplete', {
            bubbles: true,
            composed: true,
            detail: { loanId: this._recordId }
        }));
    }

    _resetForm() {
        this._loanedItem = null;
        this._libraryItem = null;
        this._isOwner = false;
        this._isBorrower = false;
        this._conditionOptions = [];
        this._errorMessage = '';
        this._returnStatus = '';
        this._dateReturned = '';
        this._conditionUponReturn = '';
        this._wouldLendAgain = '';
        this._wouldBorrowAgain = '';
        this._confirmationMessage = '';
        this._isDamaged = false;
    }
}