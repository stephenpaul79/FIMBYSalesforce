import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const FIELDS = [
    'Contact.Id',
    'Contact.Name',
    'Contact.FirstName',
    'Contact.LastName',
    'Contact.Email',
    'Contact.Phone',
    'Contact.MailingStreet',
    'Contact.MailingCity',
    'Contact.MailingState',
    'Contact.MailingPostalCode',
    'Contact.MailingCountry',
    'Contact.Description',
    'Contact.AccountId',
    'Contact.Account.Name',
    'Contact.SmallPhotoUrl'
];

export default class FimbyContactDetail extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = true;
    @track showEditModal = false;

    currentUserId = Id;
    contact;
    error;
    _wiredContactResult;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredContact(result) {
        this._wiredContactResult = result;
        const { error, data } = result;
        this.isLoading = false;
        if (data) {
            this.contact = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.contact = undefined;
        }
    }

    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }

    get headerMenuItems() {
        if (!this.canEdit) return [];
        return [
            { key: 'edit', label: 'Edit', icon: 'edit.png', display: 'responsive' }
        ];
    }

    handleHeaderMenuAction(event) {
        if (event.detail.key === 'edit') {
            this.handleEdit();
        }
    }

    get contactName() {
        return this.contact ? getFieldValue(this.contact, 'Contact.Name') : '';
    }

    get email() {
        return this.contact ? getFieldValue(this.contact, 'Contact.Email') : '';
    }

    get phone() {
        return this.contact ? getFieldValue(this.contact, 'Contact.Phone') : '';
    }

    get accountName() {
        return this.contact ? getFieldValue(this.contact, 'Contact.Account.Name') : '';
    }

    get avatarUrl() {
        return this.contact ? getFieldValue(this.contact, 'Contact.SmallPhotoUrl') : '';
    }

    get description() {
        return this.contact ? getFieldValue(this.contact, 'Contact.Description') : '';
    }

    get mailingAddress() {
        if (!this.contact) return '';
        const parts = [
            getFieldValue(this.contact, 'Contact.MailingStreet'),
            getFieldValue(this.contact, 'Contact.MailingCity'),
            getFieldValue(this.contact, 'Contact.MailingState'),
            getFieldValue(this.contact, 'Contact.MailingPostalCode'),
            getFieldValue(this.contact, 'Contact.MailingCountry')
        ].filter(Boolean);
        return parts.join(', ');
    }

    get emailLink() {
        return this.email ? 'mailto:' + this.email : '';
    }

    get phoneLink() {
        return this.phone ? 'tel:' + this.phone : '';
    }

    get isActiveUser() {
        // Could be enhanced with actual Active_User__c field check
        return true;
    }

    get canEdit() {
        // For now, allow edit - could add permission check
        return true;
    }

    // Activity counts - these would come from Apex in a real implementation
    get postCount() { return 0; }
    get responseCount() { return 0; }
    get storyCount() { return 0; }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'contacts' }
        });
    }

    handleEdit() {
        const modal = this.template.querySelector('c-fimby-record-edit-modal');
        if (modal) {
            modal.show();
        }
    }

    async handleEditSave() {
        if (this._wiredContactResult) {
            await refreshApex(this._wiredContactResult);
        }
    }

    handleEditCancel() {
        // Modal closed
    }

    handleEmail() {
        if (this.email) {
            window.location.href = this.emailLink;
        }
    }

    handleCall() {
        if (this.phone) {
            window.location.href = this.phoneLink;
        }
    }

    handleMessage() {
        // Navigate to messaging or open message modal
        console.log('Message contact:', this.recordId);
    }

    handleTabChange(event) {
        const pageName = event.detail.tab;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName }
        });
    }
}