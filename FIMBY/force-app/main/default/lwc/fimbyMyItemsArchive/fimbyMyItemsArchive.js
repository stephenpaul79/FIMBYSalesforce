import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyLibraryItemsArchive from '@salesforce/apex/FimbyMyStuffController.getMyLibraryItemsArchive';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const PAGE_SIZE = 20;
const FILTERS = [];

export default class FimbyMyItemsArchive extends NavigationMixin(LightningElement) {
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

    get libraryBadgeIconUrl() {
        return `${IMPACT_ICONS}/ToolboxActive.png`;
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
            const result = await getMyLibraryItemsArchive({
                pageSize: PAGE_SIZE,
                offset: offset,
                filterStatus: this.activeFilter
            });
            this.totalCount = result.totalCount;
            this.items = result.items.map(item => {
                const hasLoan = !!item.loanedToName;
                const isUnavailable = item.status === 'Unavailable';
                return {
                    id: item.Id,
                    title: item.Name,
                    category: item.category || '',
                    statusLabel: isUnavailable ? 'Unavailable' : (hasLoan ? 'On Loan' : 'Available'),
                    statusBadgeClass: 'status-badge ' + (isUnavailable ? 'status-unavailable' : (hasLoan ? 'status-on-loan' : 'status-available')),
                    loanedToName: item.loanedToName || '',
                    dueDate: item.dueDate ? this.formatDate(item.dueDate) : '',
                    date: this.formatDate(item.CreatedDate)
                };
            });
        } catch (error) {
            console.error('Error loading library items archive:', error);
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
        window.location.href = '/library-item/' + itemId;
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

    handleBack() {
        window.location.href = '/my-stuff';
    }

    handleTabChange(event) {
        const selectedTab = event.detail.tab;
        const validPages = {
            'home': '/',
            'library': '/library-list',
            'messages': '/messages',
            'myStuff': '/my-stuff'
        };
        if (validPages[selectedTab]) {
            location.href = validPages[selectedTab];
        }
    }
}