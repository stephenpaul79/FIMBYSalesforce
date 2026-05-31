import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyPostsArchive from '@salesforce/apex/FimbyMyStuffController.getMyPostsArchive';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const PAGE_SIZE = 20;
const FILTERS = [
    { label: 'All', value: 'All' },
    { label: 'Asks', value: 'Need' },
    { label: 'Offers', value: 'Offer' },
    { label: 'Events', value: 'Event' },
    { label: 'Bulk Buys', value: 'Bulk_Buy' }
];

const POST_ICON_MAP = {
    'Need':     'BulletinBoardActive.png',
    'Offer':    'BulletinBoardActive.png',
    'Bulk_Buy': 'bulkbuy.png'
};

const EVENT_ICON_MAP = {
    'Community_Event': 'cityscape.png',
    'Open_Event':      'people.png',
    'Gathering':       'dining-table.png'
};

export default class FimbyPostArchive extends NavigationMixin(LightningElement) {
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
        return `${IMPACT_ICONS}/NeighborhoodInactive.png`;
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
            const result = await getMyPostsArchive({
                pageSize: PAGE_SIZE,
                offset: offset,
                filterType: this.activeFilter
            });
            this.totalCount = result.totalCount;
            this.items = result.items.map(item => {
                const badge = this._getBadgeInfo(item);
                return {
                    id: item.Id,
                    title: this.decodeHtmlEntities(item.Name),
                    details: this.decodeHtmlEntities(item.Details__c),
                    type: badge.label,
                    typeBadgeClass: badge.cssClass,
                    badgeIconUrl: badge.iconUrl,
                    status: item.Status__c || '',
                    statusBadgeClass: 'status-badge status-' + (item.Status__c || '').toLowerCase().replace(/\s+/g, '-'),
                    date: this.formatDate(item.CreatedDate),
                    category: item.Category__c || ''
                };
            });
        } catch (error) {
            console.error('Error loading posts archive:', error);
            this.items = [];
        } finally {
            this.isLoading = false;
        }
    }

    _getBadgeInfo(item) {
        const rtName = item.RecordType?.Name || item.Type__c || '';
        const evtType = item.Event_Type__c;

        if (rtName.toLowerCase().includes('need')) {
            return { label: 'Ask', cssClass: 'type-badge need-type', iconUrl: `${IMPACT_ICONS}/${POST_ICON_MAP['Need']}` };
        }
        if (rtName === 'Bulk_Buy' || rtName === 'Bulk Buy') {
            return { label: 'Bulk Buy', cssClass: 'type-badge bulkbuy-type', iconUrl: `${IMPACT_ICONS}/${POST_ICON_MAP['Bulk_Buy']}` };
        }
        if (rtName === 'Event' || item.Type__c === 'Event') {
            if (evtType === 'Community_Event') {
                return { label: 'Community Event', cssClass: 'type-badge community-event-type', iconUrl: `${IMPACT_ICONS}/cityscape.png` };
            }
            return { label: 'Event', cssClass: 'type-badge event-type', iconUrl: `${IMPACT_ICONS}/${EVENT_ICON_MAP[evtType] || 'dining-table.png'}` };
        }
        return { label: rtName || 'Offer', cssClass: 'type-badge offer-type', iconUrl: `${IMPACT_ICONS}/${POST_ICON_MAP['Offer']}` };
    }

    formatDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' });
    }

    decodeHtmlEntities(text) {
        if (!text) return text;
        const textarea = document.createElement('textarea');
        textarea.innerHTML = text;
        return textarea.value;
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
        window.location.href = '/asks-offers/' + itemId;
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