import { LightningElement, api, track } from 'lwc';
import { fireErrorToast } from 'c/fimbyToastHelper';
import createFamilyMember from '@salesforce/apex/FimbyParentGuardianService.createFamilyMember';
import { createShellScrimHandle } from 'c/fimbyModalShell';

const FIRST_NAME_MAX = 40;
// Mirrors FimbyParentGuardianService: parent-managed profiles cover ages 10 through 18.
const MIN_AGE = 10;
const ADULT_AGE = 19;
const TOO_YOUNG_MESSAGE = 'Parent-managed profiles are for young people aged 10 to 18. '
    + 'You\'re welcome to add them once they turn 10.';
const TOO_OLD_MESSAGE = 'This person is 19 or older, so they set up their own FIMBY profile. '
    + 'If they need help using it, add them as a support relationship instead.';

/** Same calendar date `years` ago as a YYYY-MM-DD string; Feb 29 falls back to Feb 28 like Apex addYears. */
function isoDateYearsAgo(years, extraDays = 0) {
    const now = new Date();
    const date = new Date(now.getFullYear() - years, now.getMonth(), now.getDate() + extraDays);
    if (extraDays === 0 && date.getMonth() !== now.getMonth()) {
        date.setDate(0);
    }
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    return `${date.getFullYear()}-${mm}-${dd}`;
}

/**
 * Sets up a parent-managed profile for a young person in the guardian's family.
 *
 * The attestation wording below is the thing the guardian actually agrees to, and the
 * server stamps FIMBY_App_Settings__mdt.Guardian_Attestation_Version__c alongside it.
 * If this wording changes, bump that setting in the same change — otherwise the stored
 * version points at wording nobody was ever shown.
 */
export default class FimbyFamilyMemberSetupModal extends LightningElement {
    _shellScrim = createShellScrimHandle();

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
        this._shellScrim.bind(() => this.close(), this.template.host);
    }

    @api
    close() {
        this._shellScrim.clear();
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

    get earliestBirthdate() {
        return isoDateYearsAgo(ADULT_AGE, 1);
    }

    get latestBirthdate() {
        return isoDateYearsAgo(MIN_AGE);
    }

    get birthdateError() {
        if (!this.birthdate) return '';
        if (this.birthdate > this.latestBirthdate) return TOO_YOUNG_MESSAGE;
        if (this.birthdate < this.earliestBirthdate) return TOO_OLD_MESSAGE;
        return '';
    }

    get submitDisabled() {
        return this.isSubmitting || !this.firstName.trim() || !this.birthdate
            || !!this.birthdateError || !this.attested;
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
