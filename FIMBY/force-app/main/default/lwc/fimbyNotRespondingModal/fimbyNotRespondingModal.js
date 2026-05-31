import { LightningElement, api, track, wire } from 'lwc';
import reportFollowUp from '@salesforce/apex/FimbyFollowUpController.reportFollowUp';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

const REASON_OPTIONS = [
    { label: 'Missed pickup', value: 'Missed_Pickup_Window' },
    { label: 'Stopped replying', value: 'Stopped_Replying' },
    { label: 'Payment not yet settled', value: 'Payment_Not_Settled' },
    { label: 'Something else', value: 'Other' }
];

export default class FimbyNotRespondingModal extends LightningElement {
    @track reservationId;
    @track reserverName;
    @track bulkBuyTitle;
    @track isOpen = false;
    @track message = '';
    @track reasonSubtype = '';
    @track isSubmitting = false;
    @track errorMessage = '';

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

    get reasonOptions() {
        return REASON_OPTIONS.map((opt) => ({
            ...opt,
            isSelected: this.reasonSubtype === opt.value
        }));
    }

    get messageLength() {
        return typeof this.message === 'string' ? this.message.length : 0;
    }

    get messageCountClass() {
        if (this.messageLength >= 5000) return 'char-count at-limit';
        if (this.messageLength >= 4500) return 'char-count near-limit';
        return 'char-count';
    }

    get checkinIconUrl() {
        return `${IMPACT_ICONS}/checkin.png`;
    }

    get isValid() {
        return (
            typeof this.message === 'string' &&
            this.message.trim().length > 0 &&
            typeof this.reasonSubtype === 'string' &&
            this.reasonSubtype.length > 0
        );
    }

    get isSubmitDisabled() {
        return this.isSubmitting || !this.isValid;
    }

    @api
    show(reservationId, reserverName) {
        if (reservationId) this.reservationId = reservationId;
        if (reserverName) this.reserverName = reserverName;
        this.isOpen = true;
        this.message = '';
        this.reasonSubtype = '';
        this.errorMessage = '';
    }

    @api
    hide() {
        this.isOpen = false;
        this.isSubmitting = false;
        this.errorMessage = '';
    }

    async handleSubmit() {
        if (!this.isValid || this.isSubmitting || !this.reservationId) return;
        this.isSubmitting = true;
        this.errorMessage = '';
        try {
            const result = await reportFollowUp({
                reservationId: this.reservationId,
                message: this.message.trim(),
                reasonSubtype: this.reasonSubtype
            });
            const followUpId = result?.followUpId;
            const conversationId = result?.conversationId;
            this.dispatchEvent(
                new CustomEvent('checkinsubmitted', {
                    detail: { followUpId, conversationId }
                })
            );
            this.hide();
        } catch (err) {
            this.errorMessage =
                err?.body?.message || err?.message || 'Failed to send check-in';
        } finally {
            this.isSubmitting = false;
        }
    }

    handleReasonChange(event) {
        this.reasonSubtype = event?.target?.value ?? '';
    }

    handleMessageChange(event) {
        this.message = event?.target?.value ?? '';
    }

    handleCancel() {
        this.hide();
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }
}