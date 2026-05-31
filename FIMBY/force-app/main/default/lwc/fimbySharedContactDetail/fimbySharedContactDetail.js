import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

const FIELDS = [
    'Shared_Contact_Info__c.Id',
    'Shared_Contact_Info__c.Name',
    'Shared_Contact_Info__c.Email__c',
    'Shared_Contact_Info__c.Phone__c',
    'Shared_Contact_Info__c.Address__c',
    'Shared_Contact_Info__c.Contact__c',
    'Shared_Contact_Info__c.Contact__r.Name',
    'Shared_Contact_Info__c.Contact__r.SmallPhotoUrl',
    'Shared_Contact_Info__c.Shared_To__c',
    'Shared_Contact_Info__c.Shared_To__r.Name',
    'Shared_Contact_Info__c.CreatedDate'
];

export default class FimbySharedContactDetail extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = true;

    record;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        this.isLoading = false;
        if (data) this.record = data;
    }

    get contactName() {
        return this.record ? getFieldValue(this.record, 'Shared_Contact_Info__c.Contact__r.Name') : '';
    }

    get contactAvatar() {
        return this.record ? getFieldValue(this.record, 'Shared_Contact_Info__c.Contact__r.SmallPhotoUrl') : '';
    }

    get email() {
        return this.record ? getFieldValue(this.record, 'Shared_Contact_Info__c.Email__c') : '';
    }

    get phone() {
        return this.record ? getFieldValue(this.record, 'Shared_Contact_Info__c.Phone__c') : '';
    }

    get address() {
        return this.record ? getFieldValue(this.record, 'Shared_Contact_Info__c.Address__c') : '';
    }

    get sharedByName() {
        return this.record ? getFieldValue(this.record, 'Shared_Contact_Info__c.Shared_To__r.Name') : '';
    }

    get formattedDate() {
        if (!this.record) return '';
        const date = getFieldValue(this.record, 'Shared_Contact_Info__c.CreatedDate');
        return date ? new Date(date).toLocaleDateString() : '';
    }

    get emailLink() {
        return this.email ? 'mailto:' + this.email : '';
    }

    get phoneLink() {
        return this.phone ? 'tel:' + this.phone : '';
    }

    handleBack() {
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'shared-contacts' }});
    }

    handleEmail() {
        if (this.email) window.location.href = this.emailLink;
    }

    handleCall() {
        if (this.phone) window.location.href = this.phoneLink;
    }

    handleMap() {
        if (this.address) {
            const encodedAddress = encodeURIComponent(this.address);
            window.open(`https://maps.google.com/?q=${encodedAddress}`, '_blank');
        }
    }

    handleTabChange(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: event.detail.tab }});
    }
}