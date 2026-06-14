import { LightningElement, api, track, wire } from 'lwc';
import sendThanks from '@salesforce/apex/FimbyThanksController.sendThanks';
import { fireToast, fireErrorToast } from 'c/fimbyToastHelper';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

export default class FimbyThanksGiving extends LightningElement {
    @api recordId = ''; // Response__c or other record ID
    @api recipientId = ''; // Contact ID to thank
    @api recipientName = '';
    @api isModalMode = false;

    @track thankYouMessage = '';
    @track isModalVisible = false;
    @track isSubmitting = false;
    @track showSuccess = false;

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

    // Modal API methods
    @api
    show(recipientId, recipientName, relatedRecordId) {
        this.isModalVisible = true;
        if (recipientId) this.recipientId = recipientId;
        if (recipientName) this.recipientName = recipientName;
        if (relatedRecordId) this.recordId = relatedRecordId;
        this.resetForm();
    }

    @api
    hide() {
        this.isModalVisible = false;
        this.resetForm();
        this.dispatchEvent(new CustomEvent('close'));
    }

    resetForm() {
        this.thankYouMessage = '';
        this.showSuccess = false;
        this.isSubmitting = false;
    }

    get shouldShowModal() {
        return this.isModalMode && this.isModalVisible;
    }

    get shouldShowPage() {
        return !this.isModalMode;
    }

    get isSubmitDisabled() {
        return !this.thankYouMessage.trim() || this.isSubmitting;
    }

    get displayRecipientName() {
        return this.recipientName || 'your neighbor';
    }

    get thanksIconUrl() {
        return `${IMPACT_ICONS}/ThankYouActive.png`;
    }

    handleMessageChange(event) {
        this.thankYouMessage = event.target.value;
    }

    async handleSendThanks() {
        if (this.isSubmitDisabled) return;

        this.isSubmitting = true;

        try {
            const result = await sendThanks({
                thanksData: JSON.stringify({
                    recipientId: this.recipientId,
                    message: this.thankYouMessage.trim(),
                    relatedRecordId: this.recordId
                })
            });

            if (result.success) {
                this.showSuccess = true;

                // Dispatch success event
                this.dispatchEvent(new CustomEvent('thankssent', {
                    detail: {
                        recipientId: this.recipientId,
                        message: this.thankYouMessage
                    }
                }));

                // Auto-close modal after brief success display
                if (this.isModalMode) {
                    setTimeout(() => {
                        this.hide();
                    }, 1500);
                }
            } else {
                fireToast({ message: result.message || 'We couldn’t send your thanks just now. Please try again.', variant: 'error' });
            }
        } catch (error) {
            console.error('Error sending thanks:', error);
            fireErrorToast(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    handleBack() {
        window.history.back();
    }    handleTabChange(event) {
        console.log('Tab change:', event.detail.tab);
    }    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }    handleModalClick(event) {
        event.stopPropagation();
    }    handleClose() {
        this.hide();
    }
}