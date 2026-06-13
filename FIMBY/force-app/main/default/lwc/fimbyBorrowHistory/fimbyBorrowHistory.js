import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyBorrowHistory from '@salesforce/apex/FimbyMyStuffController.getMyBorrowHistory';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getCategoryIconUrl, getCategoryStyle } from 'c/fimbyLibraryCategoryConfig';
import { navigate, navigateToRoute } from 'c/fimbyNavigation';

const PAGE_SIZE = 20;
const FILTERS = [];

export default class FimbyBorrowHistory extends NavigationMixin(LightningElement) {
    @track items = [];
    @track isLoading = true;
    @track totalCount = 0;
    @track currentPage = 1;
    @track activeFilter = 'All';

    filters = FILTERS;

    connectedCallback() {
        this.loadData();
    }

    get emptyIconUrl() {
        return `${IMPACT_ICONS}/ToolboxInactive.png`;
    }

    get recentIconUrl() {
        return `${IMPACT_ICONS}/most-recent.png`;
    }



    get hasItems() {
        return this.items && this.items.length > 0;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalCount / PAGE_SIZE));
    }

    get showPagination() {
        return this.totalPages > 1;
    }

    get isPrevDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage >= this.totalPages;
    }

    get hasFilters() {
        return this.filters && this.filters.length > 0;
    }

    get processedFilters() {
        return this.filters.map(f => ({
            ...f,
            cssClass: 'filter-button' + (f.value === this.activeFilter ? ' active' : '')
        }));
    }

    async loadData() {
        this.isLoading = true;
        try {
            const offset = (this.currentPage - 1) * PAGE_SIZE;
            const result = await getMyBorrowHistory({
                pageSize: PAGE_SIZE,
                offset: offset,
                filterStatus: this.activeFilter
            });
            this.totalCount = result.totalCount;
            this.items = result.items.map(item => {
                const isActive = !item.returnedDate;
                let statusLabel = item.status || (isActive ? 'Active' : 'Returned');
                let statusClass = 'status-badge ';

                if (!isActive) {
                    statusClass += 'status-completed';
                    statusLabel = 'Returned';
                } else if (item.dueDate && new Date(item.dueDate) < new Date()) {
                    statusClass += 'status-overdue';
                    statusLabel = 'Overdue';
                } else if (item.dueDate) {
                    const daysUntilDue = Math.ceil((new Date(item.dueDate) - new Date()) / (1000 * 60 * 60 * 24));
                    if (daysUntilDue <= 3) {
                        statusClass += 'status-due-soon';
                        statusLabel = 'Due Soon';
                    } else {
                        statusClass += 'status-active';
                        statusLabel = 'Active';
                    }
                } else {
                    statusClass += 'status-active';
                }

                const cat = item.category || 'Other';
                return {
                    id: item.Id,
                    itemId: item.itemId,
                    itemName: item.itemName || 'Unknown Item',
                    ownerName: item.ownerName || 'Unknown',
                    category: cat,
                    categoryIconUrl: getCategoryIconUrl(IMPACT_ICONS, cat),
                    categoryBadgeStyle: getCategoryStyle(cat),
                    dueDate: item.dueDate ? this.formatDate(item.dueDate) : 'No due date',
                    returnedDate: item.returnedDate ? this.formatDate(item.returnedDate) : '',
                    isActive: isActive,
                    dateDisplay: isActive ? (item.dueDate ? 'Due: ' + this.formatDate(item.dueDate) : 'No due date') : ('Returned: ' + this.formatDate(item.returnedDate)),
                    statusLabel: statusLabel,
                    statusBadgeClass: statusClass
                };
            });
        } catch (error) {
            console.error('Error loading borrow history:', error);
            this.items = [];
        } finally {
            this.isLoading = false;
        }
    }

    formatDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' });
    }

    handleFilterClick(event) {
        const value = event.currentTarget.dataset.value;
        if (value !== this.activeFilter) {
            this.activeFilter = value;
            this.currentPage = 1;
            this.loadData();
        }
    }

    handleCardClick(event) {
        const itemId = event.currentTarget.dataset.id;
        if (itemId) {
            navigate(this, '/library-item/' + itemId);
        }
    }

    handlePrevPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadData();
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.loadData();
        }
    }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    handleBack() {
        navigate(this, '/my-stuff');
    }

    handleTabChange(event) {
        const selectedTab = event.detail.tab;
        navigateToRoute(this, selectedTab);
    }
}