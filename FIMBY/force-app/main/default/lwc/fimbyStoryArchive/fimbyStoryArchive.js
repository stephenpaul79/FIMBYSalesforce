import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyStoriesArchive from '@salesforce/apex/FimbyMyStuffController.getMyStoriesArchive';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { decodeHtmlEntities } from 'c/fimbyTextUtils';
import { navigate, navigateToRoute } from 'c/fimbyNavigation';

const PAGE_SIZE = 20;
const FILTERS = [
    { label: 'All', value: 'All' },
    { label: 'Thank You', value: 'Thank You' },
    { label: 'God Story', value: 'God Story' },
    { label: 'Prayer', value: 'Prayer' },
    { label: 'Lament', value: 'Lament' },
    { label: 'Bio', value: 'Bio' },
    { label: 'Neighbourhood', value: 'Neighbourhood Moment' }
];

const TYPE_BADGE_MAP = {
    'Thank You': 'type-badge thankyou-type',
    'God Story': 'type-badge godstory-type',
    'Prayer': 'type-badge prayer-type',
    'Lament': 'type-badge lament-type',
    'Bio': 'type-badge bio-type',
    'Neighbourhood Moment': 'type-badge neighbourhood-type'
};

const STORY_ICON_MAP = {
    'Thank You': 'ThankYouActive.png',
    'God Story': 'GodStoryActive.png',
    'Prayer':    'PrayActive.png',
    'Lament':    'LamentActive.png',
    'Bio':       'BioActive.png',
    'Neighbourhood Moment': 'tulips.png'
};

const STORY_DISPLAY_NAMES = {
    'Neighbourhood Moment': 'Neighbourhood'
};

export default class FimbyStoryArchive extends NavigationMixin(LightningElement) {
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
        return `${IMPACT_ICONS}/GodStoryInactive.png`;
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
            const result = await getMyStoriesArchive({
                pageSize: PAGE_SIZE,
                offset: offset,
                filterType: this.activeFilter
            });
            this.totalCount = result.totalCount;
            this.items = result.items.map(item => ({
                id: item.Id,
                title: decodeHtmlEntities(item.Name || 'Untitled Post'),
                message: decodeHtmlEntities(item.Message__c || ''),
                type: STORY_DISPLAY_NAMES[item.Type__c] || item.Type__c || '',
                typeBadgeClass: TYPE_BADGE_MAP[item.Type__c] || 'type-badge',
                badgeIconUrl: STORY_ICON_MAP[item.Type__c] ? `${IMPACT_ICONS}/${STORY_ICON_MAP[item.Type__c]}` : null,
                date: this.formatDate(item.CreatedDate)
            }));
        } catch (error) {
            console.error('Error loading stories archive:', error);
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
        navigate(this, '/story/' + itemId);
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