import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getContactsList from '@salesforce/apex/FimbyContactsController.getContactsList';
import { refreshApex } from '@salesforce/apex';

export default class FimbyContactsList extends NavigationMixin(LightningElement) {
    @api filterName = 'All Strathcona / DTES Contacts';
    @api pageSize = 20;

    @track contacts = [];
    @track totalContacts = 0;
    @track isLoading = true;
    @track errorMessage = '';
    @track currentOffset = 0;
    @track searchTerm = '';
    @track sortField = 'Name';
    @track sortDirection = 'ASC';

    wiredContactsResult;

    // Column configuration based on listview
    get columns() {
        return [
            {
                fieldName: 'SmallPhotoUrl',
                label: '',
                isImage: true,
                placeholderIcon: 'utility:user',
                sortable: false
            },
            {
                fieldName: 'Name',
                label: 'Name',
                isLink: true,
                displayField: 'Name'
            },
            {
                fieldName: 'Active_User__c',
                label: 'Active',
                isBadge: true,
                badgeClass: 'statusBadgeClass'
            },
            {
                fieldName: 'AccountName',
                label: 'Neighbourhood',
                displayField: 'AccountName'
            }
        ];
    }

    get rowActions() {
        return [
            { name: 'view', label: 'View', icon: 'utility:preview' },
            { name: 'message', label: 'Message', icon: 'utility:email' }
        ];
    }

    get filterLabel() {
        return this.filterName;
    }

    get hasMoreRecords() {
        return this.contacts.length < this.totalContacts;
    }

    @wire(getContactsList, {
        filterName: '$filterName',
        searchTerm: '$searchTerm',
        sortField: '$sortField',
        sortDirection: '$sortDirection',
        pageSize: '$pageSize',
        offset: '$currentOffset'
    })
    wiredContacts(result) {
        this.wiredContactsResult = result;
        this.isLoading = false;

        if (result.data) {
            // Process contacts to add computed fields
            const processedContacts = result.data.records.map(contact => ({
                ...contact,
                AccountName: contact.Account ? contact.Account.Name : '—',
                SmallPhotoUrl: contact.SmallPhotoUrl || null,
                statusBadgeClass: contact.Active_User__c ? 'status-badge status-active' : 'status-badge status-inactive'
            }));

            if (this.currentOffset === 0) {
                this.contacts = processedContacts;
            } else {
                this.contacts = [...this.contacts, ...processedContacts];
            }

            this.totalContacts = result.data.totalCount;
            this.errorMessage = '';
        } else if (result.error) {
            console.error('Error loading contacts:', result.error);
            this.errorMessage = result.error.body?.message || 'Failed to load contacts.';
            this.contacts = [];
        }
    }

    handleContactClick(event) {
        const contactId = event.detail.recordId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: contactId,
                objectApiName: 'Contact',
                actionName: 'view'
            }
        });
    }

    handleRowAction(event) {
        const { recordId, actionName } = event.detail;

        switch (actionName) {
            case 'view':
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        objectApiName: 'Contact',
                        actionName: 'view'
                    }
                });
                break;
            case 'message':
                // Handle messaging - could open email composer or internal messaging
                console.log('Message contact:', recordId);
                break;
            default:
                console.log('Unknown action:', actionName);
        }
    }

    handleSearch(event) {
        this.searchTerm = event.detail.searchTerm;
        this.currentOffset = 0;
    }

    handleSort(event) {
        const { field, direction } = event.detail;
        this.sortField = field;
        this.sortDirection = direction.toUpperCase();
        this.currentOffset = 0;
    }

    handleLoadMore() {
        if (this.hasMoreRecords) {
            this.currentOffset += this.pageSize;
        }
    }

    handleNotifications() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'notifications'
            }
        });
    }

    handleTabChange(event) {
        const tab = event.detail.tab;
        let pageName;

        switch (tab) {
            case 'home':
                pageName = 'home';
                break;
            case 'ask-offer-list':
                pageName = 'ask-offer-list';
                break;
            case 'library':
                pageName = 'library';
                break;
            case 'stories':
                pageName = 'stories';
                break;
            default:
                return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: pageName
            }
        });
    }

    async refresh() {
        this.currentOffset = 0;
        return refreshApex(this.wiredContactsResult);
    }
}