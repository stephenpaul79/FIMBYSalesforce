import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getResponseForShareContactInfo from '@salesforce/apex/FimbyResponseController.getResponseForShareContactInfo';
import shareContactInfo from '@salesforce/apex/FimbyResponseController.shareContactInfo';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

/**
 * Share Contact Info component
 * Converts Share_Contact_Info.flow to LWC
 *
 * Allows a poster or responder to share their contact info with the other party
 * in the context of a Response to a Need/Offer.
 */
export default class FimbyShareContent extends NavigationMixin(LightningElement) {
    @api recordId; // Response__c ID

    @track isLoading = true;
    @track error = null;
    @track errorType = null; // 'notAuthorized', 'householdMatch'

    // Response and participant data
    @track responseData = null;
    @track recipientData = null;
    @track sharingContactData = null;

    // Form state
    @track shareEmail = false;
    @track sharePhone = false;
    @track shareAddress = false;

    // Contact info fields (pre-populated from Contact record)
    @track emailValue = '';
    @track phoneValue = '';
    @track streetValue = '';
    @track cityValue = '';
    @track stateValue = '';
    @track postalCodeValue = '';
    @track countryValue = '';
    @track additionalInfoValue = '';

    // Identity
    @track actingAsName = '';
    @track hasMultipleIdentities = false;

    // Submission state
    @track isSubmitting = false;
    @track submitSuccess = false;

    connectedCallback() {
        this.loadResponseData();
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

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    async loadResponseData() {
        this.isLoading = true;
        this.error = null;
        this.errorType = null;

        try {
            const identityResult = await getActingAsContact();
            if (identityResult?.success) {
                this.actingAsName = identityResult.postingAsDisplayName
                    || identityResult.actingAsContactName
                    || identityResult.contactName
                    || '';
            }

            const result = await getResponseForShareContactInfo({ recordId: this.recordId });

            if (!result.success) {
                this.errorType = result.error;
                this.error = result.message;
                this.isLoading = false;
                return;
            }

            this.responseData = result.response;
            this.recipientData = result.recipient;
            this.sharingContactData = result.sharingContact;

            // Pre-populate form fields from Contact
            if (this.sharingContactData) {
                this.emailValue = this.sharingContactData.email || '';
                this.phoneValue = this.sharingContactData.phone || '';
                this.streetValue = this.sharingContactData.mailingStreet || '';
                this.cityValue = this.sharingContactData.mailingCity || '';
                this.stateValue = this.sharingContactData.mailingState || '';
                this.postalCodeValue = this.sharingContactData.mailingPostalCode || '';
                this.countryValue = this.sharingContactData.mailingCountry || '';
            }

            this.isLoading = false;
        } catch (err) {
            this.error = err.body?.message || err.message || 'An error occurred';
            this.isLoading = false;
        }
    }

    // Checkbox handlers
    handleEmailCheckbox(event) {
        this.shareEmail = event.target.checked;
    }

    handlePhoneCheckbox(event) {
        this.sharePhone = event.target.checked;
    }

    handleAddressCheckbox(event) {
        this.shareAddress = event.target.checked;
    }

    // Input handlers
    handleEmailChange(event) {
        this.emailValue = event.target.value;
    }

    handlePhoneChange(event) {
        this.phoneValue = event.target.value;
    }

    handleStreetChange(event) {
        this.streetValue = event.target.value;
    }

    handleCityChange(event) {
        this.cityValue = event.target.value;
    }

    handleStateChange(event) {
        this.stateValue = event.target.value;
    }

    handlePostalCodeChange(event) {
        this.postalCodeValue = event.target.value;
    }

    handleCountryChange(event) {
        this.countryValue = event.target.value;
    }

    handleAdditionalInfoChange(event) {
        this.additionalInfoValue = event.target.value;
    }

    // Validation
    get isValid() {
        // At least one checkbox must be selected
        if (!this.shareEmail && !this.sharePhone && !this.shareAddress) {
            return false;
        }
        // If email selected, email must be provided
        if (this.shareEmail && !this.emailValue) {
            return false;
        }
        // If phone selected, phone must be provided
        if (this.sharePhone && !this.phoneValue) {
            return false;
        }
        return true;
    }

    get isInvalid() {
        return !this.isValid;
    }

    get validationError() {
        if (!this.shareEmail && !this.sharePhone && !this.shareAddress) {
            return 'Please select at least one type of contact info to share.';
        }
        if (this.shareEmail && !this.emailValue) {
            return 'Please provide an email address.';
        }
        if (this.sharePhone && !this.phoneValue) {
            return 'Please provide a phone number.';
        }
        return '';
    }

    get showValidationError() {
        // Only show validation after user has interacted
        return (this.shareEmail || this.sharePhone || this.shareAddress) && this.validationError;
    }

    // UI State getters
    get showForm() {
        return !this.isLoading && !this.error && !this.submitSuccess;
    }

    get showError() {
        return !this.isLoading && this.error;
    }

    get showSuccess() {
        return this.submitSuccess;
    }

    get recipientFullName() {
        if (!this.recipientData) return '';
        return `${this.recipientData.firstName || ''} ${this.recipientData.lastName || ''}`.trim();
    }

    get confirmationMessage() {
        return `Clicking 'Share' will share the contact info you have selected with ${this.recipientFullName} (via email).`;
    }

    get submitButtonLabel() {
        return this.isSubmitting ? 'Sharing...' : 'Share Contact Info';
    }

    get isSubmitDisabled() {
        return this.isSubmitting || this.isInvalid;
    }

    // Actions
    async handleSubmit() {
        if (!this.isValid) {
            return;
        }

        this.isSubmitting = true;

        try {
            const shareData = {
                responseId: this.recordId,
                recipientContactId: this.recipientData.id,
                sharingContactId: this.sharingContactData.id,
                shareEmail: this.shareEmail,
                sharePhone: this.sharePhone,
                shareAddress: this.shareAddress,
                email: this.emailValue,
                phone: this.phoneValue,
                street: this.streetValue,
                city: this.cityValue,
                state: this.stateValue,
                postalCode: this.postalCodeValue,
                country: this.countryValue,
                additionalInfo: this.additionalInfoValue
            };

            const result = await shareContactInfo({ shareData: JSON.stringify(shareData) });            if (result.success) {
                this.submitSuccess = true;
                // Auto-navigate after short delay
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.navigateToResponse();
                }, 2000);
            }
        } catch (err) {
            this.error = err.body?.message || err.message || 'An error occurred while sharing contact info';
        } finally {
            this.isSubmitting = false;
        }
    }    handleCancel() {
        this.navigateToResponse();
    }    handleFinish() {
        this.navigateToResponse();
    }    navigateToResponse() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Response__c',
                actionName: 'view'
            }
        });
    }
}