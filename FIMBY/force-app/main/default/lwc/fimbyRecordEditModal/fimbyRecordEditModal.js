import { LightningElement, api, track, wire } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getFieldSetFields from '@salesforce/apex/FimbyFieldSetController.getFieldSetFields';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyRecordEditModal extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api fieldSetName = 'FIMBY_Editable_Fields';

    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }
    get saveIconUrl() { return `${IMPACT_ICONS}/save.png`; }
    get posterIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }

    get showFooter() { return !this.isLoading && !this.hasError; }

    @track isVisible = false;
    @track isLoading = false;
    @track isSaving = false;
    @track hasError = false;
    @track errorMessage = '';
    @track fieldSetFields = [];
    @track objectLabel = '';
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

    // Get object info for the label
    @wire(getObjectInfo, { objectApiName: '$objectApiName' })
    handleObjectInfo({ error, data }) {
        if (data) {
            this.objectLabel = data.label;
        } else if (error) {
            console.error('Error getting object info:', error);
            this.objectLabel = this.objectApiName;
        }
    }

    // Public API to show the modal
    @api
    show(recordId, objectApiName, fieldSetName) {
        if (recordId) this.recordId = recordId;
        if (objectApiName) this.objectApiName = objectApiName;
        if (fieldSetName) this.fieldSetName = fieldSetName;

        this.isVisible = true;
        this.hasError = false;
        this.errorMessage = '';
        this.loadFieldSet();
    }

    // Public API to hide the modal
    @api
    hide() {
        this.isVisible = false;
        this.isSaving = false;
    }

    // Load field set fields from Apex
    async loadFieldSet() {
        if (!this.objectApiName || !this.fieldSetName) {
            this.hasError = true;
            this.errorMessage = 'Object or field set not specified.';
            return;
        }

        this.isLoading = true;
        this.hasError = false;

        try {
            const fields = await getFieldSetFields({
                objectApiName: this.objectApiName,
                fieldSetName: this.fieldSetName
            });

            this.fieldSetFields = fields;

            if (fields.length === 0) {
                this.hasError = true;
                this.errorMessage = `No editable fields found. Please ensure the "${this.fieldSetName}" field set exists on ${this.objectLabel}.`;
            }
        } catch (error) {
            console.error('Error loading field set:', error);
            this.hasError = true;
            this.errorMessage = error.body?.message || 'Failed to load editable fields. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }

    handleRetry() {
        this.loadFieldSet();
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget && !this.isSaving) {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        if (!this.isSaving) {
            this.hide();
        }
    }

    handleCancel() {
        if (!this.isSaving) {
            this.hide();
        }
    }

    handleSave() {
        // Find and click the hidden submit button
        const submitBtn = this.template.querySelector('.submit-btn-hidden');
        if (submitBtn) {
            submitBtn.click();
        }
    }

    handleSubmit(event) {
        this.isSaving = true;
        // Let the form submit naturally
    }

    handleSuccess(event) {
        this.isSaving = false;

        // Dispatch success event with record details
        this.dispatchEvent(new CustomEvent('recordsaved', {
            detail: {
                recordId: event.detail.id,
                objectApiName: this.objectApiName
            }
        }));

        // Close the modal
        this.hide();
    }

    handleError(event) {
        this.isSaving = false;
        console.error('Save error:', event.detail);
        // Error messages are shown by lightning-messages component
    }
}