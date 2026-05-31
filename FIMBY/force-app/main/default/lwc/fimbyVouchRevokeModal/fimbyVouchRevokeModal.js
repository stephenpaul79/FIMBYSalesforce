import { LightningElement, api, track, wire } from 'lwc';
import revokeVouch from '@salesforce/apex/FimbyVouchController.revokeVouch';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';

const COUNTING_CATEGORIES = [
    { value: 'Safety_Trust_Concern',       label: 'Safety / Trust Concern' },
    { value: 'Theft_Or_Misuse',            label: 'Theft or Misuse' },
    { value: 'Repeated_No_Return',         label: 'Repeated No Return' },
    { value: 'Serious_Conduct_Issue',      label: 'Serious Conduct Issue' },
    { value: 'Identity_Misrepresentation', label: 'Identity Misrepresentation' },
    { value: 'Other_For_Cause',            label: 'Other (For Cause)' }
];

const NON_COUNTING_CATEGORIES = [
    { value: 'Admin_Correction',                label: 'Admin Correction' },
    { value: 'Wrong_Contact_Selected',          label: 'Wrong Contact Selected' },
    { value: 'Duplicate_Or_Test_Record',        label: 'Duplicate or Test Record' },
    { value: 'Neighbourhood_Move',              label: 'Neighbourhood Move' },
    { value: 'Support_Relationship_Ended',      label: 'Support Relationship Ended' },
    { value: 'Organization_Rep_Link_Corrected', label: 'Organization Rep Link Corrected' }
];

const DETAILS_MAX = 1000;

export default class FimbyVouchRevokeModal extends LightningElement {
    @api vouchRecordId = '';

    @track isOpen = false;
    @track selectedCategory = '';
    @track details = '';
    @track isSubmitting = false;
    @track errorMessage = '';

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
        return `You're currently acting as ${name}. Vouching is tied to your own identity — please switch back to yourself before revoking a vouch.`;
    }

    @api
    show(vouchRecordId) {
        this.vouchRecordId = vouchRecordId;
        this.selectedCategory = '';
        this.details = '';
        this.errorMessage = '';
        this.isOpen = true;
    }

    @api
    close() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    get countingOptions() {
        return COUNTING_CATEGORIES.map(c => ({
            ...c,
            checked: this.selectedCategory === c.value,
            inputId: 'cat-c-' + c.value
        }));
    }

    get nonCountingOptions() {
        return NON_COUNTING_CATEGORIES.map(c => ({
            ...c,
            checked: this.selectedCategory === c.value,
            inputId: 'cat-n-' + c.value
        }));
    }

    get detailsRequired() {
        return this.selectedCategory === 'Other_For_Cause';
    }

    get isSubmitDisabled() {
        if (this.isSubmitting) return true;
        if (this.isBlockedByActingAs) return true;
        if (!this.selectedCategory) return true;
        if (this.detailsRequired && !this.details?.trim()) return true;
        return false;
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

    handleCategoryChange(event) {
        this.selectedCategory = event.target.value;
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
            this.errorMessage = this.actingAsBlockMessage;
            return;
        }
        this.isSubmitting = true;
        this.errorMessage = '';
        try {
            await revokeVouch({
                vouchRecordId: this.vouchRecordId,
                revocationCategory: this.selectedCategory,
                details: this.details?.trim() || null
            });
            this.dispatchEvent(new CustomEvent('revokesubmitted'));
            this.isOpen = false;
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message
                || 'Something went wrong. Please try again.';
        } finally {
            this.isSubmitting = false;
        }
    }
}
