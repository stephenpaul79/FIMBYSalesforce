import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSharedContactsList from '@salesforce/apex/FimbySharedContactsController.getSharedContactsList';

export default class FimbySharedContactsList extends NavigationMixin(LightningElement) {
    @api pageSize = 20;

    @track sharedContacts = [];
    @track totalRecords = 0;
    @track currentOffset = 0;
    @track searchTerm = '';
    @track sortField = 'CreatedDate';
    @track sortDirection = 'DESC';

    get columns() {
        return [
            { fieldName: 'ContactName', label: 'Contact', isLink: true, displayField: 'ContactName' },
            { fieldName: 'Email__c', label: 'Email' },
            { fieldName: 'Phone__c', label: 'Phone' },
            { fieldName: 'Address__c', label: 'Address' },
            { fieldName: 'SharedToName', label: 'Shared To', displayField: 'SharedToName' }
        ];
    }

    get rowActions() {
        return [
            { name: 'view', label: 'View', icon: 'utility:preview' },
            { name: 'call', label: 'Call', icon: 'utility:call' },
            { name: 'email', label: 'Email', icon: 'utility:email' }
        ];
    }

    get hasMoreRecords() {
        return this.sharedContacts.length < this.totalRecords;
    }

    @wire(getSharedContactsList, {
        searchTerm: '$searchTerm',
        sortField: '$sortField',
        sortDirection: '$sortDirection',
        pageSize: '$pageSize',
        offset: '$currentOffset'
    })
    wiredItems(result) {
        if (result.data) {
            const processed = result.data.records.map(item => ({
                ...item,
                ContactName: item.Contact__r ? item.Contact__r.Name : '—',
                SharedToName: item.Shared_To__r ? item.Shared_To__r.Name : '—'
            }));

            this.sharedContacts = this.currentOffset === 0 ? processed : [...this.sharedContacts, ...processed];
            this.totalRecords = result.data.totalCount;
        }
    }

    handleItemClick(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.detail.recordId, objectApiName: 'Shared_Contact_Info__c', actionName: 'view' }
        });
    }

    handleRowAction(event) {
        const { recordId, actionName } = event.detail;
        const record = this.sharedContacts.find(r => r.Id === recordId);

        if (actionName === 'view') {
            this.handleItemClick({ detail: { recordId } });
        } else if (actionName === 'call' && record && record.Phone__c) {
            window.location.href = 'tel:' + record.Phone__c;
        } else if (actionName === 'email' && record && record.Email__c) {
            window.location.href = 'mailto:' + record.Email__c;
        }
    }

    handleSearch(event) {
        this.searchTerm = event.detail.searchTerm;
        this.currentOffset = 0;
    }

    handleSort(event) {
        this.sortField = event.detail.field;
        this.sortDirection = event.detail.direction.toUpperCase();
        this.currentOffset = 0;
    }

    handleLoadMore() {
        if (this.hasMoreRecords) {
            this.currentOffset += this.pageSize;
        }
    }

    handleNotifications() {
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'notifications' }});
    }

    handleTabChange(event) {
        const pageName = event.detail.tab;
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName }});
    }
}