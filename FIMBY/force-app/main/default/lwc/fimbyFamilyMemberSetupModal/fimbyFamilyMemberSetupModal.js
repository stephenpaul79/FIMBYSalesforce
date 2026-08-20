import { LightningElement, api, track } from 'lwc';
import { fireErrorToast } from 'c/fimbyToastHelper';
import createFamilyMember from '@salesforce/apex/FimbyParentGuardianService.createFamilyMember';

const FIRST_NAME_MAX = 40;

/**
 * Sets up a parent-managed profile for a young person in the guardian's family.
 *
 * The attestation wording below is the thing the guardian actually agrees to, and the
 * server stamps FIMBY_App_Settings__mdt.Guardian_Attestation_Version__c alongside it.
 * If this wording changes, bump that setting in the same change — otherwise the stored
 * version points at wording nobody was ever shown.
 */
export default class FimbyFamilyMemberSetupModal extends LightningElement {
    @track isOpen = false;
    @track isSubmitting = false;
    @track error = '';

    @track firstName = '';
    @track birthdate = '';
    @track attested = false;

    @track createdContactId = '';
    @track createdName = '';

    @api
    open() {
        this.firstName = '';
        this.birthdate = '';
        this.attested = false;
        this.error = '';
        this.isSubmitting = false;
        this.createdContactId = '';
        this.createdName = '';
        this.isOpen = true;
    }

    @api
    close() {
        this.isOpen = false;
    }

    get isPhotoStep() {
        return !!this.createdContactId;
    }

    get firstNameLength() {
        return this.firstName.length;
    }

    get firstNameCountClass() {
        const len = this.firstName.length;
        if (len >= FIRST_NAME_MAX) return 'character-count at-limit';
        if (len >= Math.floor(FIRST_NAME_MAX * 0.9)) return 'character-count near-limit';
        return 'character-count';
    }

    get submitDisabled() {
        return this.isSubmitting || !this.firstName.trim() || !this.birthdate || !this.attested;
    }

    handleFirstNameChange(event) {
        this.firstName = event.target.value;
        this.error = '';
    }

    handleBirthdateChange(event) {
        this.birthdate = event.target.value;
        this.error = '';
    }

    handleAttestationChange(event) {
        this.attested = event.target.checked;
        this.error = '';
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close();
        }
    }

    handleSubmit() {
        if (this.submitDisabled) return;
        this.isSubmitting = true;
        this.error = '';

        createFamilyMember({
            input: {
                firstName: this.firstName.trim(),
                birthdate: this.birthdate,
                attested: this.attested
            }
        })
            .then(result => {
                this.createdName = result.displayName;
                // Setting this last flips the modal to the photo step, so the profile is
                // already real by the time the guardian sees the uploader.
                this.createdContactId = result.contactId;
                this.isSubmitting = false;
            })
            .catch(error => {
                // The refusals are all things the guardian can act on — a birthdate
                // that says 19, a missing attestation — so they belong beside the form
                // rather than in a toast that scrolls away.
                const message = error?.body?.message;
                if (message) {
                    this.error = message;
                } else {
                    fireErrorToast(error);
                }
                this.isSubmitting = false;
            });
    }

    handlePhotoUploaded() {
        this.handleDone();
    }

    handleDone() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('familymembercreated', {
            detail: { contactId: this.createdContactId }
        }));
    }
}
