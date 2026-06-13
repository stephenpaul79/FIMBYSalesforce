import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { navigate } from 'c/fimbyNavigation';

const FIELDS = [
    'Loaned_Item__c.Id',
    'Loaned_Item__c.Name',
    'Loaned_Item__c.Status__c',
    'Loaned_Item__c.Loan_Due_Date__c',
    'Loaned_Item__c.List_Image__c',
    'Loaned_Item__c.Library_Item__c',
    'Loaned_Item__c.Library_Item__r.Name',
    'Loaned_Item__c.Library_Item__r.Category__c',
    'Loaned_Item__c.Library_Item__r.Portal_Image__c',
    'Loaned_Item__c.Loaned_To__c',
    'Loaned_Item__c.Loaned_To__r.Name',
    'Loaned_Item__c.Loaned_To__r.SmallPhotoUrl',
    'Loaned_Item__c.Library_Item__r.Owner_Contact__r.Name',
    'Loaned_Item__c.Library_Item__r.Owner_Contact__r.SmallPhotoUrl'
];

export default class FimbyLoanedItemDetail extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = true;

    record;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        this.isLoading = false;
        if (data) this.record = data;
    }

    get loanName() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Name') : '';
    }

    get status() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Status__c') : '';
    }

    get statusType() {
        const status = this.status.toLowerCase();
        if (status.includes('overdue')) return 'overdue';
        if (status.includes('extension')) return 'pending';
        return 'active';
    }

    get dueDate() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Loan_Due_Date__c') : null;
    }

    get dueDateLabel() {
        if (!this.dueDate) return '';
        const due = new Date(this.dueDate);
        const today = new Date();
        const diff = Math.ceil((due - today) / (1000 * 60 * 60 * 24));
        if (diff < 0) return `${Math.abs(diff)} days overdue`;
        if (diff === 0) return 'Due today';
        if (diff === 1) return 'Due tomorrow';
        return `Due in ${diff} days`;
    }

    get statusMessage() {
        const status = this.status.toLowerCase();
        if (status.includes('overdue')) return 'Please return this item as soon as possible.';
        if (status.includes('extension')) return 'Extension request pending owner approval.';
        return 'Remember to return the item by the due date.';
    }

    get progressStyle() {
        if (!this.dueDate) return 'width: 0%';
        const due = new Date(this.dueDate);
        const today = new Date();
        const diff = Math.ceil((due - today) / (1000 * 60 * 60 * 24));
        const percent = Math.max(0, Math.min(100, 100 - (diff / 14) * 100));
        return `width: ${percent}%`;
    }

    get itemName() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__r.Name') : '';
    }

    get itemCategory() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__r.Category__c') : '';
    }

    get itemImage() {
        return this.record ? (getFieldValue(this.record, 'Loaned_Item__c.List_Image__c') || getFieldValue(this.record, 'Loaned_Item__c.Library_Item__r.Portal_Image__c')) : '';
    }

    get borrowerName() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Loaned_To__r.Name') : '';
    }

    get borrowerAvatar() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Loaned_To__r.SmallPhotoUrl') : '';
    }

    get ownerName() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__r.Owner_Contact__r.Name') : '';
    }

    get ownerAvatar() {
        return this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__r.Owner_Contact__r.SmallPhotoUrl') : '';
    }

    get actionsCardClass() {
        if (this.statusType === 'overdue') return 'actions-card cta-strip-urgent';
        return 'actions-card cta-strip-strong';
    }

    get canReturn() {
        return !this.status.toLowerCase().includes('return');
    }

    get canExtend() {
        return !this.status.toLowerCase().includes('extension');
    }

    get headerMenuItems() {
        return [
            { key: 'flag', label: 'Report', icon: 'warning.png', display: 'kebab' }
        ];
    }

    handleHeaderMenuAction(event) {
        if (event.detail.key === 'flag') {
            this.handleFlag();
        }
    }

    handleFlag() {
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) modal.show(this.recordId, 'Loaned_Item__c');
    }

    handleBack() {
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'loaned-items' }});
    }

    handleViewItem() {
        const itemId = this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__c') : null;
        if (itemId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: itemId, objectApiName: 'Library_Item__c', actionName: 'view' }
            });
        }
    }

    handleReturn() {
        const libraryItemId = this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__c') : null;
        if (libraryItemId) {
            navigate(this, `/library-item/${libraryItemId}/?action=return&loanId=${this.recordId}`);
        }
    }

    handleExtend() {
        const libraryItemId = this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__c') : null;
        if (libraryItemId) {
            navigate(this, `/library-item/${libraryItemId}/?action=requestExtension&loanId=${this.recordId}`);
        }
    }

    handleMessage() {
        const libraryItemId = this.record ? getFieldValue(this.record, 'Loaned_Item__c.Library_Item__c') : null;
        if (libraryItemId) {
            navigate(this, `/library-item/${libraryItemId}/`);
        }
    }

    handleTabChange(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: event.detail.tab }});
    }
}