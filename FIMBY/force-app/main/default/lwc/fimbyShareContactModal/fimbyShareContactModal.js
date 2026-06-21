import { LightningElement, api, track } from 'lwc';
import { fireToast } from 'c/fimbyToastHelper';
import searchNeighbourhoodContacts from '@salesforce/apex/FimbyMyStuffController.searchNeighbourhoodContacts';
import getMyContactDetailsForSharing from '@salesforce/apex/FimbyMyStuffController.getMyContactDetailsForSharing';
import shareContactInfoDirect from '@salesforce/apex/FimbyMyStuffController.shareContactInfoDirect';

export default class FimbyShareContactModal extends LightningElement {
    @api editMode = false;

    @track shareSearchTerm = '';
    @track shareSearchResults = [];
    @track shareSearching = false;
    @track selectedRecipientId = null;
    @track selectedRecipientName = '';
    @track shareEmail = false;
    @track sharePhone = false;
    @track shareAddress = false;
    @track shareEmailValue = '';
    @track sharePhoneValue = '';
    @track shareStreetValue = '';
    @track shareCityValue = '';
    @track shareStateValue = '';
    @track sharePostalCodeValue = '';
    @track shareCountryValue = '';
    @track shareAdditionalInfoValue = '';
    @track shareSubmitting = false;

    _isOpen = false;
    _shareSearchTimeout;
    _initializedForOpen = false;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        const opening = value === true && !this._isOpen;
        this._isOpen = value === true;
        if (!this._isOpen) {
            this._initializedForOpen = false;
        } else if (opening) {
            this._initializedForOpen = false;
             
            Promise.resolve().then(() => this._onOpen());
        }
    }

    @api
    get recipientContactId() {
        return this.selectedRecipientId;
    }
    set recipientContactId(value) {
        this.selectedRecipientId = value || null;
    }

    @api
    get recipientName() {
        return this.selectedRecipientName;
    }
    set recipientName(value) {
        this.selectedRecipientName = value || '';
    }

    @api
    setInitialShareValues(values = {}) {
        this.shareEmailValue = values.email || '';
        this.sharePhoneValue = values.phone || '';
        this.shareStreetValue = values.street || '';
        this.shareCityValue = values.city || '';
        this.shareStateValue = values.state || '';
        this.sharePostalCodeValue = values.postalCode || '';
        this.shareCountryValue = values.country || '';
        this.shareAdditionalInfoValue = values.additionalInfo || '';
        this.shareEmail = !!values.email;
        this.sharePhone = !!values.phone;
        this.shareAddress = !!(
            values.street || values.city || values.state || values.postalCode || values.country
        );
    }

    get shareModalTitle() {
        return this.editMode ? 'Update shared contact info' : 'Share my contact info';
    }

    get shareRecipientSelected() {
        return !!this.selectedRecipientId;
    }

    get shareRecipientNotSelected() {
        return !this.selectedRecipientId;
    }

    get isNotEditMode() {
        return !this.editMode;
    }

    get isShareValid() {
        if (!this.selectedRecipientId) return false;
        if (!this.shareEmail && !this.sharePhone && !this.shareAddress) return false;
        if (this.shareEmail && !this.shareEmailValue) return false;
        if (this.sharePhone && !this.sharePhoneValue) return false;
        return true;
    }

    get isShareSubmitDisabled() {
        return this.shareSubmitting || !this.isShareValid;
    }

    get shareSubmitLabel() {
        if (this.shareSubmitting) return this.editMode ? 'Updating...' : 'Sharing...';
        return this.editMode ? 'Update' : 'Share';
    }

    async _onOpen() {
        if (this._initializedForOpen) return;
        this._initializedForOpen = true;
        this.shareSearchTerm = '';
        this.shareSearchResults = [];
        this.shareSearching = false;
        this.shareSubmitting = false;

        if (!this.editMode) {
            try {
                const details = await getMyContactDetailsForSharing();
                this._applyContactDetails(details);
            } catch (e) {
                console.error('Error loading contact details:', e);
            }
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const closeBtn = this.template.querySelector('.slds-modal__close');
            if (closeBtn) closeBtn.focus();
        }, 50);
    }

    _applyContactDetails(details) {
        if (!details) return;
        this.shareEmailValue = details.email || '';
        this.sharePhoneValue = details.phone || '';
        this.shareStreetValue = details.street || '';
        this.shareCityValue = details.city || '';
        this.shareStateValue = details.state || '';
        this.sharePostalCodeValue = details.postalCode || '';
        this.shareCountryValue = details.country || '';
        this.shareEmail = !!details.email;
        this.sharePhone = !!details.phone;
        this.shareAddress = !!(details.street || details.city || details.state || details.postalCode || details.country);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleShareSearch(event) {
        this.shareSearchTerm = event.target.value;
        clearTimeout(this._shareSearchTimeout);
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce / delayed UI
        this._shareSearchTimeout = setTimeout(() => this._doShareSearch(), 350);
    }

    async _doShareSearch() {
        const term = (this.shareSearchTerm || '').trim();
        if (term.length < 2) {
            this.shareSearchResults = [];
            return;
        }
        this.shareSearching = true;
        try {
            const results = await searchNeighbourhoodContacts({ searchTerm: term });
            this.shareSearchResults = (results || []).map(r => ({
                contactId: r.contactId,
                contactName: r.contactName,
                email: r.email,
                resultClass: r.contactId === this.selectedRecipientId
                    ? 'share-result-item selected' : 'share-result-item'
            }));
        } catch (e) {
            console.error('Search error:', e);
            this.shareSearchResults = [];
        } finally {
            this.shareSearching = false;
        }
    }

    handleSelectRecipient(event) {
        const contactId = event.currentTarget.dataset.contactId;
        const contactName = event.currentTarget.dataset.contactName;
        this.selectedRecipientId = contactId;
        this.selectedRecipientName = contactName || '';
        this.shareSearchResults = this.shareSearchResults.map(r => ({
            ...r,
            resultClass: r.contactId === contactId ? 'share-result-item selected' : 'share-result-item'
        }));
    }

    handleDeselectRecipient() {
        this.selectedRecipientId = null;
        this.selectedRecipientName = '';
        this.shareSearchResults = [];
        this.shareSearchTerm = '';
    }

    handleShareEmailChange(event) { this.shareEmail = event.target.checked; }
    handleSharePhoneChange(event) { this.sharePhone = event.target.checked; }
    handleShareAddressChange(event) { this.shareAddress = event.target.checked; }
    handleShareEmailValueChange(event) { this.shareEmailValue = event.target.value; }
    handleSharePhoneValueChange(event) { this.sharePhoneValue = event.target.value; }
    handleShareStreetChange(event) { this.shareStreetValue = event.target.value; }
    handleShareCityChange(event) { this.shareCityValue = event.target.value; }
    handleShareStateChange(event) { this.shareStateValue = event.target.value; }
    handleSharePostalCodeChange(event) { this.sharePostalCodeValue = event.target.value; }
    handleShareCountryChange(event) { this.shareCountryValue = event.target.value; }

    async handleShareSubmit() {
        if (!this.isShareValid || this.shareSubmitting) return;
        this.shareSubmitting = true;
        try {
            const shareData = {
                recipientContactId: this.selectedRecipientId,
                shareEmail: this.shareEmail,
                sharePhone: this.sharePhone,
                shareAddress: this.shareAddress,
                email: this.shareEmailValue,
                phone: this.sharePhoneValue,
                street: this.shareStreetValue,
                city: this.shareCityValue,
                state: this.shareStateValue,
                postalCode: this.sharePostalCodeValue,
                country: this.shareCountryValue,
                additionalInfo: this.shareAdditionalInfoValue || null
            };
            const result = await shareContactInfoDirect({ shareDataJson: JSON.stringify(shareData) });
            if (result && result.success) {
                this.dispatchEvent(new CustomEvent('shared', {
                    detail: { recipientContactId: this.selectedRecipientId }
                }));
            }
        } catch (error) {
            const msg = error.body?.message || error.message || 'We couldn’t share your info just now. Please try again.';
            fireToast({ message: msg, variant: 'error' });
        } finally {
            this.shareSubmitting = false;
        }
    }
}
