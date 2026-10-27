import { LightningElement, api, track } from 'lwc';
import getVouchingContextForContact from '@salesforce/apex/FimbyVouchController.getVouchingContextForContact';
import overrideVouch from '@salesforce/apex/FimbyVouchController.overrideVouch';

const VOUCHING_LABELS = {
    'New':              'Settling in',
    'Vouch_Requested':  'Vouch Pending',
    'Vouched':          'Vouched',
    'Vouch_Declined':   'Vouch Declined'
};

/**
 * Moderator override-vouch: status, pending-request summary, button, and confirm modal.
 * `compact` drops the status block so a host page can trigger the confirm from its own
 * menu via openConfirm(); banners and the modal still render here.
 */
export default class FimbyModeratorVouchAction extends LightningElement {
    @api firstName;
    @api compact = false;

    _contactId;
    @track _ctx = null;
    @track _loading = false;
    @track _inFlight = false;
    @track _error = '';
    @track _success = '';
    @track _showConfirm = false;

    @api
    get contactId() { return this._contactId; }
    set contactId(value) {
        if (value === this._contactId) return;
        this._contactId = value;
        this._success = '';
        this._error = '';
        if (value) this._loadContext();
    }

    @api
    openConfirm() {
        if (this.buttonDisabled) return;
        this._showConfirm = true;
    }

    async _loadContext() {
        const contactId = this._contactId;
        this._loading = true;
        try {
            const ctx = await getVouchingContextForContact({ contactId });
            if (contactId !== this._contactId) return;
            this._ctx = ctx;
        } catch (e) {
            console.error('Vouching context load error', e);
            this._ctx = null;
        } finally {
            this._loading = false;
            this.dispatchEvent(new CustomEvent('vouchcontextchange', {
                detail: {
                    canOverrideVouch: this._ctx?.canOverrideVouch === true,
                    isVouched: this.isAlreadyVouched
                }
            }));
        }
    }

    get showStatus() { return !this.compact; }

    get statusLabel() {
        const status = this._ctx?.vouchedStatus || 'New';
        return VOUCHING_LABELS[status] || VOUCHING_LABELS.New;
    }

    // Same source of truth as buttonDisabled: green pill and dead button always arrive together.
    get badgeClass() {
        return this.isAlreadyVouched ? 'vouch-badge complete' : 'vouch-badge pending';
    }

    get hasPendingRequest() {
        return !!this._ctx?.pendingVouchRecordId;
    }

    get pendingSummary() {
        const ctx = this._ctx;
        if (!ctx?.pendingVouchRecordId) return '';
        const name = ctx.pendingReferenceContactName || 'a neighbour';
        const org = ctx.pendingReferenceOrganizationName ? ` (${ctx.pendingReferenceOrganizationName})` : '';
        let dateStr = '';
        if (ctx.pendingRequestedDate) {
            try {
                dateStr = new Date(ctx.pendingRequestedDate).toLocaleDateString('en-US',
                    { month: 'short', day: 'numeric' });
            } catch { /* ignore */ }
        }
        const datePart = dateStr ? ` on ${dateStr}` : '';
        return `Requested${datePart} from ${name}${org}`;
    }

    get isAlreadyVouched() {
        return this._ctx?.vouchedStatus === 'Vouched';
    }

    // The button stays on screen once they're vouched — a neighbour can be vouched
    // by someone else in the meantime, and a vanishing control reads as a glitch
    // rather than an answer.
    get buttonDisabled() {
        return this.isAlreadyVouched || this._inFlight || this._loading;
    }

    get buttonHint() {
        if (!this.isAlreadyVouched) return 'Vouch for them yourself, without waiting for a neighbour';
        const by = this._ctx?.vouchedByContactName || this._ctx?.vouchedByOrganizationName;
        return by ? `Already vouched by ${by}` : 'Already vouched';
    }

    get displayFirstName() {
        return this.firstName || 'This neighbour';
    }

    get showConfirm() { return this._showConfirm; }
    get inFlight() { return this._inFlight; }
    get errorMessage() { return this._error; }
    get successMessage() { return this._success; }
    get hasMessage() { return !!(this._success || this._error); }

    handleButtonClick() {
        this.openConfirm();
    }

    handleCancel() {
        this._showConfirm = false;
    }

    async handleConfirm() {
        if (this._inFlight || !this._contactId) return;
        const contactId = this._contactId;
        this._inFlight = true;
        this._error = '';
        this._success = '';
        try {
            await overrideVouch({ vouchedContactId: contactId });
            await this._loadContext();
            this._success = `${this.displayFirstName} is vouched. They can borrow from the lending library now.`;
            this.dispatchEvent(new CustomEvent('vouched', { detail: { contactId } }));
        } catch (error) {
            console.error('Override vouch error', error);
            this._error = error?.body?.message || error?.message
                || 'Could not vouch for them just now. Please try again.';
        } finally {
            this._inFlight = false;
            this._showConfirm = false;
        }
    }
}
