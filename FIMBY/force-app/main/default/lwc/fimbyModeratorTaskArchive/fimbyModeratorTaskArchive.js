import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getModeratorAssignments from '@salesforce/apex/FimbyModeratorDashboardController.getModeratorAssignments';
import getClosedTasks from '@salesforce/apex/FimbyModeratorDashboardController.getClosedTasks';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate, navigateToRoute } from 'c/fimbyNavigation';

const PAGE_SIZE = 20;

const STATUS_FILTERS = [
    { label: 'All', value: 'All' },
    { label: 'Resolved', value: 'Resolved' },
    { label: 'Dismissed', value: 'Dismissed' }
];

const CATEGORY_FILTERS = [
    { label: 'All', value: 'All' },
    { label: 'Content', value: 'Content_Report' },
    { label: 'Blocked', value: 'Blocked_Contact' },
    { label: 'Support', value: 'Support_Relationship_Approval' },
    { label: 'Concerns', value: 'Support_Person_Concern' },
    { label: 'Bulk Buy', value: 'Bulk_Buy_Escalation' },
    { label: 'Feedback', value: 'Feedback_Triage' },
    { label: 'Signups', value: 'New_Signup' }
];

const CATEGORY_LABELS = {
    Content_Report: 'Content for Review',
    Bulk_Buy_Escalation: 'Bulk Buy',
    Blocked_Contact: 'Blocked',
    New_Signup: 'New Signup',
    Feedback_Triage: 'Feedback',
    Support_Relationship_Approval: 'Support Request',
    Support_Person_Concern: 'Support Concern'
};

const SUMMARY_PREFIX_PATTERNS = {
    Content_Report: /^Content\s+Report:\s*/i,
    Blocked_Contact: /^Block(?:\s+Report|\s+report\s+filed):?\s*/i,
    Bulk_Buy_Escalation: /^Bulk\s+Buy(?:\s+Escalation)?:\s*/i,
    New_Signup: /^New\s+Sign[\s-]?up:\s*/i,
    Feedback_Triage: /^Feedback(?:\s+Triage)?:\s*/i,
    Support_Relationship_Approval: /^Support(?:\s+Relationship)?(?:\s+Approval)?:\s*/i,
    Support_Person_Concern: /^Support(?:\s+Person)?(?:\s+Concern)?:\s*/i
};

/** Tier-3 row badges — saturated `--fimby-badge-*` fills (home feed pattern). */
const CATEGORY_BADGE_CLASS_MAP = {
    Content_Report: 'category-badge badge-content',
    Blocked_Contact: 'category-badge badge-blocked',
    Support_Relationship_Approval: 'category-badge badge-support',
    Support_Person_Concern: 'category-badge badge-concern',
    Bulk_Buy_Escalation: 'category-badge badge-bulk-buy',
    Feedback_Triage: 'category-badge badge-feedback',
    New_Signup: 'category-badge badge-signup'
};

export default class FimbyModeratorTaskArchive extends NavigationMixin(LightningElement) {
    @track items = [];
    @track isLoading = true;
    @track accessDenied = false;
    @track totalCount = 0;
    @track currentPage = 1;
    @track activeStatusFilter = 'All';
    @track activeCategoryFilter = 'All';
    @track assignments = [];
    @track selectedNeighbourhoodId;

    statusFilters = STATUS_FILTERS;
    categoryFilters = CATEGORY_FILTERS;

    connectedCallback() {
        this._init();
    }

    get emptyIconUrl() {
        return `${IMPACT_ICONS}/NeighborhoodInactive.png`;
    }

    get isAuthorized() {
        return !this.accessDenied;
    }

    get isReady() {
        return this.isAuthorized && !this.isLoading && this.selectedNeighbourhoodId;
    }

    get showNeighbourhoodToggle() {
        return this.assignments && this.assignments.length > 1;
    }

    get singleNeighbourhoodName() {
        return this.assignments?.[0]?.Neighbourhood__r?.Name || '';
    }

    get assignmentsWithToggleClass() {
        return (this.assignments || []).map(a => ({
            ...a,
            _toggleClass: a.Neighbourhood__c === this.selectedNeighbourhoodId
                ? 'nbh-toggle-btn active'
                : 'nbh-toggle-btn'
        }));
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

    get processedStatusFilters() {
        return this.statusFilters.map(f => ({
            ...f,
            cssClass: 'filter-button' + (f.value === this.activeStatusFilter ? ' active' : ''),
            ariaPressed: f.value === this.activeStatusFilter ? 'true' : 'false'
        }));
    }

    get processedCategoryFilters() {
        return this.categoryFilters.map(f => ({
            ...f,
            cssClass: 'filter-button sub-filter' + (f.value === this.activeCategoryFilter ? ' active' : ''),
            ariaPressed: f.value === this.activeCategoryFilter ? 'true' : 'false'
        }));
    }

    async _init() {
        this.isLoading = true;
        try {
            const assignments = await getModeratorAssignments();
            if (!assignments || assignments.length === 0) {
                this.accessDenied = true;
                this.isLoading = false;
                return;
            }
            this.assignments = assignments;
            this._resolveNeighbourhoodFromUrl(assignments);
            await this.loadData();
        } catch (error) {
            console.error('Error initializing moderator archive:', error);
            this.accessDenied = true;
            this.isLoading = false;
        }
    }

    _resolveNeighbourhoodFromUrl(assignments) {
        let nbhId = null;
        try {
            const params = new URLSearchParams(window.location.search);
            nbhId = params.get('nbh');
        } catch {
            nbhId = null;
        }
        if (nbhId && assignments.some(a => a.Neighbourhood__c === nbhId)) {
            this.selectedNeighbourhoodId = nbhId;
        } else {
            this.selectedNeighbourhoodId = assignments[0].Neighbourhood__c;
        }
    }

    async loadData() {
        if (!this.selectedNeighbourhoodId) return;
        this.isLoading = true;
        try {
            const offset = (this.currentPage - 1) * PAGE_SIZE;
            const result = await getClosedTasks({
                neighbourhoodId: this.selectedNeighbourhoodId,
                category: this.activeCategoryFilter,
                statusFilter: this.activeStatusFilter,
                pageSize: PAGE_SIZE,
                offset
            });
            this.totalCount = result.totalCount || 0;
            this.items = (result.items || []).map(item => this._processItem(item));
        } catch (error) {
            console.error('Error loading closed tasks:', error);
            this.items = [];
            this.totalCount = 0;
        } finally {
            this.isLoading = false;
        }
    }

    _processItem(item) {
        const category = item.Category__c || '';
        const status = item.Status__c || '';
        const resolvedBy = item.Resolved_By__r?.Name;
        const closedDate = this._formatClosedDate(item.Resolved_Date__c);
        const summary = this._stripPrefix(item.Summary__c, category);
        const taskUrl = `/moderator-task?recordId=${item.Id}&from=archive`;

        return {
            id: item.Id,
            taskUrl,
            ariaLabel: `View closed task: ${summary || category}`,
            categoryLabel: CATEGORY_LABELS[category] || category.replace(/_/g, ' '),
            categoryBadgeClass: CATEGORY_BADGE_CLASS_MAP[category] || 'category-badge badge-default',
            summary,
            closedByLine: resolvedBy ? `Closed by ${resolvedBy}` : '',
            statusLabel: status === 'Dismissed' ? 'Dismissed' : 'Resolved',
            statusBadgeClass: status === 'Dismissed'
                ? 'status-badge status-dismissed'
                : 'status-badge status-resolved',
            closedDate: closedDate ? `Closed ${closedDate}` : ''
        };
    }

    _stripPrefix(summary, category) {
        if (!summary) return '';
        const pattern = SUMMARY_PREFIX_PATTERNS[category];
        return pattern ? summary.replace(pattern, '') : summary;
    }

    _formatClosedDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        if (Number.isNaN(d.getTime())) return '';
        return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(d);
    }

    handleNeighbourhoodChange(event) {
        const id = event.currentTarget.dataset.id;
        if (!id || id === this.selectedNeighbourhoodId) return;
        this.selectedNeighbourhoodId = id;
        this.currentPage = 1;
        this.loadData();
    }

    handleStatusFilterClick(event) {
        const value = event.currentTarget.dataset.value;
        if (value !== this.activeStatusFilter) {
            this.activeStatusFilter = value;
            this.currentPage = 1;
            this.loadData();
        }
    }

    handleCategoryFilterClick(event) {
        const value = event.currentTarget.dataset.value;
        if (value !== this.activeCategoryFilter) {
            this.activeCategoryFilter = value;
            this.currentPage = 1;
            this.loadData();
        }
    }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    handleRowClick(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            navigate(this, url);
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

    handleBottomTabChange(event) {
        const selectedTab = event.detail.tab;
        navigateToRoute(this, selectedTab);
    }
}
