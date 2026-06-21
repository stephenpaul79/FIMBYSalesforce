import { LightningElement, api, track, wire } from 'lwc';
import declineVouch from '@salesforce/apex/FimbyVouchController.declineVouch';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import { fireErrorToast, fireToast } from 'c/fimbyToastHelper';

const REASONS = [
    { value: 'Do_Not_Know_Person', label: "I don't know this person" },
    { value: 'Cannot_Vouch',       label: "I know them but can't vouch for them" },
    { value: 'Not_Right_Person',   label: "I'm not the right person to ask" },
    { value: 'Concerning_Request', label: "This request feels concerning" },
    { value: 'Other',              label: "Other (please share)" }
];

const DETAILS_MAX = 500;

export default class FimbyVouchDeclineModal extends LightningElement {
    @api vouchRecordId = '';
    _vouchRecordId = '';

    get activeVouchRecordId() {
        return this._vouchRecordId || this.vouchRecordId;
    }

    @track isOpen = false;
    @track selectedReason = '';
    @track details = '';
    @track isSubmitting = false;

    @track actingAsContact = null;

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading acting-as contact:', error);
        }
    }

    get isBlockedByActingAs() {
        return this.actingAsContact && this.actingAsContact.isActingAsSelf === false;
    }

    get actingAsBlockMessage() {
        const name = this.actingAsContact?.postingAsDisplayName
            || this.actingAsContact?.actingAsContactName
            || 'another identity';
        return `You're currently acting as ${name}. Vouching is tied to your own identity — please switch back to yourself before declining a vouch request.`;
    }

    @api
    show(vouchRecordId) {
        this._vouchRecordId = vouchRecordId;
        this.selectedReason = '';
        this.details = '';
        this.isOpen = true;
        Promise.resolve().then(() => {
            const first = this.template.querySelector('input[type="radio"]');
            if (first) first.focus();
        });
    }

    @api
    close() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    get reasonOptions() {
        return REASONS.map(r => ({
            ...r,
            checked: this.selectedReason === r.value,
            inputId: 'reason-' + r.value
        }));
    }

    get showDetailsField() {
        return this.selectedReason === 'Other';
    }

    get detailsCharCount() {
        return (this.details || '').length;
    }

    get detailsCountClass() {
        const len = this.detailsCharCount;
        if (len >= DETAILS_MAX) return 'char-count at-limit';
        if (len >= Math.floor(DETAILS_MAX * 0.9)) return 'char-count near-limit';
        return 'char-count';
    }

    get isSubmitDisabled() {
        if (this.isSubmitting) return true;
        if (this.isBlockedByActingAs) return true;
        if (!this.selectedReason) return true;
        if (this.selectedReason === 'Other' && !this.details?.trim()) return true;
        return false;
    }

    handleReasonChange(event) {
        this.selectedReason = event.target.value;
    }

    handleDetailsInput(event) {
        this.details = event.target.value;
    }

    handleCancel() {
        this.close();
    }

    handleBackdrop(event) {
        if (event.target.classList.contains('modal-backdrop')) {
            this.handleCancel();
        }
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleCancel();
        }
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) return;
        if (this.isBlockedByActingAs) {
            fireToast({ message: this.actingAsBlockMessage, variant: 'warning' });
            return;
        }
        this.isSubmitting = true;
        try {
            await declineVouch({
                vouchRecordId: this.activeVouchRecordId,
                reason: this.selectedReason,
                details: this.selectedReason === 'Other' ? this.details.trim() : null
            });
            this.dispatchEvent(new CustomEvent('declinesubmitted'));
            this.isOpen = false;
        } catch (error) {
            fireErrorToast(error);
        } finally {
            this.isSubmitting = false;
        }
    }
}
