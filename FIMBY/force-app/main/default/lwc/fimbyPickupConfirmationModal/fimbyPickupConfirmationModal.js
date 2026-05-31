import { LightningElement, api, track } from 'lwc';
import recordHandoff from '@salesforce/apex/FimbyLendingController.recordHandoff';
import getLendingRequestForHandoff from '@salesforce/apex/FimbyLendingController.getLendingRequestForHandoff';
import { formatLocalDate } from 'c/fimbyDateUtils';

export default class FimbyPickupConfirmationModal extends LightningElement {

    @track _isVisible = false;
    @track _viewState = 'loading'; // loading | form | submitting | success | error
    @track _errorMessage = '';

    _recordId = '';

    @track lendingRequest;
    @track libraryItem;
    @track requesterName;
    @track ownerName;

    // ── Public API ──────────────────────────────────────────────────

    @api
    show(requestId) {
        this._recordId = requestId;
        this._isVisible = true;
        this._viewState = 'loading';
        this._errorMessage = '';
        this._loadRequest();
    }

    @api
    hide() {
        // Parent must refresh lending UI whenever this modal closes (including "already handled"
        // dismiss) — composed + bubbles so the event crosses the child component shadow boundary.
        this.dispatchEvent(new CustomEvent('pickupmodalclosed', {
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

    // ── Computed getters ────────────────────────────────────────────

    get itemName() {
        return this.libraryItem?.name || '';
    }

    get dueDateFormatted() {
        return formatLocalDate(this.lendingRequest?.dueDate) || 'TBD';
    }

    get pickupDateFormatted() {
        return formatLocalDate(this.lendingRequest?.requestedDate) || 'TBD';
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

    // ── Submit ───────────────────────────────────────────────────────

    async handleConfirm() {
        this._viewState = 'submitting';

        try {
            await recordHandoff({ requestId: this._recordId });
            this._viewState = 'success';
            this._notifyComplete();
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    // ── Data loading ────────────────────────────────────────────────

    async _loadRequest() {
        try {
            const result = await getLendingRequestForHandoff({ recordId: this._recordId });

            if (result.success) {
                this.lendingRequest = result.lendingRequest;
                this.libraryItem = result.libraryItem;
                this.requesterName = result.requesterName;
                const oc = result.ownerContact;
                this.ownerName = (oc && oc.name) ? oc.name
                    : [oc?.firstName, oc?.lastName].filter(Boolean).join(' ').trim();
                this._viewState = 'form';
            } else {
                this._errorMessage = result.message || 'Unable to load this request.';
                const err = result.error;
                // Idempotency: when the server says the action is no longer applicable
                // (status advanced, request promoted/declined), skip the "already took
                // action" wall and just refresh the parent banner. The user either took
                // the action on another device or the state changed underneath them.
                if (err !== 'wrongStatus' && err !== 'notParticipant') {
                    this.hide();
                    return;
                }
                this._viewState = 'error';
            }
        } catch (err) {
            this._errorMessage = err.body?.message || 'Something went wrong loading the request.';
            this._viewState = 'error';
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────

    _notifyComplete() {
        this.dispatchEvent(new CustomEvent('pickupcomplete', {
            bubbles: true,
            composed: true,
            detail: { requestId: this._recordId }
        }));
    }

    handleSuccessDone() {
        this.hide();
    }

    handleRetry() {
        this._viewState = 'loading';
        this._errorMessage = '';
        this._loadRequest();
    }

    _resetForm() {
        this.lendingRequest = null;
        this.libraryItem = null;
        this.requesterName = '';
        this.ownerName = '';
        this._errorMessage = '';
    }
}