import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLoanedItemsList from '@salesforce/apex/FimbyLoanedItemsController.getLoanedItemsList';

export default class FimbyLoanedItemsList extends NavigationMixin(LightningElement) {
    @api filterName = 'All';
    @api pageSize = 20;

    @track loanedItems = [];
    @track totalRecords = 0;
    @track currentOffset = 0;
    @track searchTerm = '';
    @track sortField = 'Name';
    @track sortDirection = 'ASC';

    get columns() {
        return [
            { fieldName: 'List_Image__c', label: '', isImage: true, placeholderIcon: 'utility:package', sortable: false },
            { fieldName: 'Name', label: 'Loan', isLink: true },
            { fieldName: 'LibraryItemName', label: 'Item', displayField: 'LibraryItemName' },
            { fieldName: 'LoanedToName', label: 'Borrower', displayField: 'LoanedToName' },
            { fieldName: 'Loan_Due_Date__c', label: 'Due Date' },
            { fieldName: 'Status__c', label: 'Status', isBadge: true }
        ];
    }

    get rowActions() {
        return [
            { name: 'view', label: 'View', icon: 'utility:preview' },
            { name: 'return', label: 'Return', icon: 'utility:undo' }
        ];
    }

    get filterLabel() {
        return this.filterName === 'All' ? 'All Loans' : this.filterName;
    }

    get hasMoreRecords() {
        return this.loanedItems.length < this.totalRecords;
    }

    @wire(getLoanedItemsList, {
        filterName: '$filterName',
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
                LibraryItemName: item.Library_Item__r ? item.Library_Item__r.Name : '—',
                LoanedToName: item.Loaned_To__r ? item.Loaned_To__r.Name : '—'
            }));

            this.loanedItems = this.currentOffset === 0 ? processed : [...this.loanedItems, ...processed];
            this.totalRecords = result.data.totalCount;
        }
    }

    handleItemClick(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.detail.recordId, objectApiName: 'Loaned_Item__c', actionName: 'view' }
        });
    }

    handleRowAction(event) {
        const { recordId, actionName } = event.detail;
        if (actionName === 'view') {
            this.handleItemClick({ detail: { recordId } });
        } else if (actionName === 'return') {
            // Navigate to return flow or open modal
            console.log('Return item:', recordId);
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