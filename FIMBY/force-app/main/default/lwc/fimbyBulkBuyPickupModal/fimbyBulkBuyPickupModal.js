import { LightningElement, api, wire, track } from 'lwc';
import notifyForPickup from '@salesforce/apex/FimbyBulkBuyController.notifyForPickup';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { fireErrorToast } from 'c/fimbyToastHelper';

export default class FimbyBulkBuyPickupModal extends LightningElement {
    @api postId;
    @api postTitle;

    isOpen = false;
    message = '';
    receiptImageUrl = '';
    isLoading = false;

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

    /** Slot 4 used for receipt to avoid overwriting product images (slots 1–3) */
    get receiptImageSlot() {
        return 4;
    }

    get pickupIconUrl() {
        return `${IMPACT_ICONS}/giftsm.png`;
    }

    get isMessageValid() {
        return typeof this.message === 'string' && this.message.trim().length > 0;
    }

    get isSubmitDisabled() {
        return this.isLoading || !this.isMessageValid;
    }

    @api
    show() {
        this.isOpen = true;
        this.message = '';
        this.receiptImageUrl = '';
    }

    @api
    hide() {
        this.isOpen = false;
        this.isLoading = false;
    }

    async handleSubmit() {
        if (!this.isMessageValid || this.isLoading || !this.postId) return;
        this.isLoading = true;
        try {
            await notifyForPickup({
                postId: this.postId,
                message: this.message.trim(),
                receiptImageUrl: this.receiptImageUrl || null
            });
            this.dispatchEvent(new CustomEvent('pickupnotified'));
            this.hide();
        } catch (err) {
            fireErrorToast(err);
        } finally {
            this.isLoading = false;
        }
    }

    handleReceiptUpload(event) {
        const url = event?.detail?.imageUrl;
        this.receiptImageUrl = typeof url === 'string' ? url : '';
    }

    handleReceiptRemoved() {
        this.receiptImageUrl = '';
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