import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate } from 'c/fimbyNavigation';
import { fireErrorToast } from 'c/fimbyToastHelper';

import { getModeratorContext, invalidateModeratorContext } from 'c/fimbyModeratorContext';

import getModeratorAssignments from '@salesforce/apex/FimbyModeratorDashboardController.getModeratorAssignments';
import getDashboardSummary from '@salesforce/apex/FimbyModeratorDashboardController.getDashboardSummary';
import getTasksByCategory from '@salesforce/apex/FimbyModeratorDashboardController.getTasksByCategory';
import getEscalatedTasks from '@salesforce/apex/FimbyModeratorDashboardController.getEscalatedTasks';
import getContentReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getContentReviewData';
import getFollowUpReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getFollowUpReviewData';
import getBlockReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getBlockReviewData';
import getFeedbackReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getFeedbackReviewData';
import getSupportReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getSupportReviewData';
import getSupportConcernData from '@salesforce/apex/FimbyModeratorDashboardController.getSupportConcernData';
import getEscalationDetail from '@salesforce/apex/FimbyModeratorDashboardController.getEscalationDetail';
import getWelcomeReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getWelcomeReviewData';
import getNeighbourhoodHealthData from '@salesforce/apex/FimbyModeratorDashboardController.getNeighbourhoodHealthData';
import getSubjectHistory from '@salesforce/apex/FimbyModeratorDashboardController.getSubjectHistory';
import resolveTask from '@salesforce/apex/FimbyModeratorDashboardController.resolveTask';
import escalateTask from '@salesforce/apex/FimbyModeratorDashboardController.escalateTask';
import reopenTask from '@salesforce/apex/FimbyModeratorDashboardController.reopenTask';
import claimTask from '@salesforce/apex/FimbyModeratorDashboardController.claimTask';
import republishContent from '@salesforce/apex/FimbyModeratorDashboardController.republishContent';
import keepContentHidden from '@salesforce/apex/FimbyModeratorDashboardController.keepContentHidden';
import issueCheckIn from '@salesforce/apex/FimbyModeratorDashboardController.issueCheckIn';
import recordConcern from '@salesforce/apex/FimbyModeratorDashboardController.recordConcern';
import sendWelcomeMessage from '@salesforce/apex/FimbyModeratorDashboardController.sendWelcomeMessage';
import markWelcomed from '@salesforce/apex/FimbyModeratorDashboardController.markWelcomed';
import triageFeedback from '@salesforce/apex/FimbyModeratorDashboardController.triageFeedback';
import approveSupportRelationship from '@salesforce/apex/FimbyModeratorDashboardController.approveSupportRelationship';
import declineSupportRelationship from '@salesforce/apex/FimbyModeratorDashboardController.declineSupportRelationship';
import getOrCreateModeratorConversation from '@salesforce/apex/FimbyModeratorDashboardController.getOrCreateModeratorConversation';
import { avatarImageUrl, completeImageUrl } from 'c/fimbyImageUrl';

const PAGE_SIZE = 20;
const STORAGE_KEY = 'fimby-mod-dashboard-state';

const SECTIONS = [
    {
        key: 'adminEscalations',
        label: 'Escalated to Admin',
        icon: 'lifesaver.png',
        accentVar: '--fimby-error-tint',
        borderVar: '--fimby-error',
        helperText: 'Items already handed up for admin support',
        emptyHint: 'No items waiting on admin right now',
        tabs: [
            { key: 'escalated', label: 'Escalated', category: null, isEscalated: true }
        ]
    },
    {
        key: 'attention',
        label: 'Needs Attention',
        icon: 'danger-sign.png',
        accentVar: '--fimby-warning-tint',
        borderVar: '--fimby-warning',
        helperText: 'Items that may need a decision today',
        emptyHint: 'All clear right now',
        tabs: [
            { key: 'content', label: 'Content', category: 'Content_Report' },
            { key: 'blocked', label: 'Blocked', category: 'Blocked_Contact' },
            { key: 'support', label: 'Support', category: 'Support_Relationship_Approval' },
            { key: 'organizations', label: 'Organizations', category: 'Organization_Approval' },
            { key: 'concerns', label: 'Concerns', category: 'Support_Person_Concern' }
        ]
    },
    {
        key: 'daily',
        label: 'Routine Review',
        icon: 'check-in.png',
        accentVar: '--fimby-info-tint',
        borderVar: '--fimby-info',
        helperText: 'Everyday review, welcoming, and follow-up',
        emptyHint: 'No routine review items at this time',
        tabs: [
            { key: 'bulkbuy', label: 'Bulk Buy', category: 'Bulk_Buy_Escalation' },
            { key: 'feedback', label: 'Feedback', category: 'Feedback_Triage' },
            { key: 'signups', label: 'Signups', category: 'New_Signup' }
        ]
    },
    {
        key: 'health',
        label: 'Neighbourhood Health',
        icon: 'analysis.png',
        accentVar: null,
        borderVar: null,
        helperText: 'Patterns and community signals worth keeping an eye on',
        emptyHint: 'No neighbourhood health concerns at this time',
        tabs: [
            { key: 'health', label: 'Health', category: null, isHealth: true }
        ]
    }
];

const COMPLEX_TASK_CATEGORIES = new Set([
    'Content_Report', 'Blocked_Contact',
    'Support_Relationship_Approval', 'Organization_Approval', 'Support_Person_Concern',
    'Bulk_Buy_Escalation'
]);

const CTA_CONFIGS = [
    { category: 'Content_Report', actions: [
        { action: 'review', label: 'Review', icon: 'analysis.png', variant: 'primary' },
        { action: 'dismiss', label: 'No Action Needed' },
        { action: 'escalate', label: 'Escalate to Admin', icon: 'lifesaver.png' }
    ]},
    { category: 'Bulk_Buy_Escalation', actions: [
        { action: 'review', label: 'Review History', icon: 'analysis.png', variant: 'primary' },
        { action: 'escalate', label: 'Escalate to Admin', icon: 'lifesaver.png' }
    ]},
    { category: 'Blocked_Contact', actions: [
        { action: 'review', label: 'View Details', icon: 'analysis.png', variant: 'primary' },
        { action: 'dismiss', label: 'Mark Reviewed' },
        { action: 'escalate', label: 'Escalate to Admin', icon: 'lifesaver.png' }
    ]},
    { category: 'New_Signup', actions: [
        { action: 'welcome', label: 'Send Welcome', variant: 'primary' },
        { action: 'markWelcomed', label: 'Mark Welcomed' },
        { action: 'viewProfile', label: 'View Profile' }
    ]},
    { category: 'Feedback_Triage', actions: [
        { action: 'review', label: 'Review', icon: 'analysis.png', variant: 'primary' }
    ]},
    { category: 'Support_Relationship_Approval', actions: [
        { action: 'review', label: 'Review', icon: 'hiring.png', variant: 'primary' },
        { action: 'escalate', label: 'Escalate to Admin', icon: 'lifesaver.png' }
    ]},
    { category: 'Organization_Approval', actions: [
        { action: 'review', label: 'Review', icon: 'hiring.png', variant: 'primary' },
        { action: 'escalate', label: 'Escalate to Admin', icon: 'lifesaver.png' }
    ]},
    { category: 'Support_Person_Concern', actions: [
        { action: 'review', label: 'Review Concern', icon: 'analysis.png', variant: 'primary' },
        { action: 'escalateUrgent', label: 'Urgent: Escalate', icon: 'lifesaver.png', variant: 'danger' }
    ]},
    { category: 'default', actions: [
        { action: 'review', label: 'Review', icon: 'analysis.png', variant: 'primary' }
    ]}
];

const ESCALATED_CTA_CONFIGS = [
    { category: 'default', actions: [
        { action: 'review', label: 'Review', icon: 'analysis.png', variant: 'primary' }
    ]}
];

const CATEGORY_MODAL_MAP = {
    Content_Report: 'content',
    Bulk_Buy_Escalation: 'followUp',
    Blocked_Contact: 'block',
    Feedback_Triage: 'feedback',
    Support_Relationship_Approval: 'support',
    Support_Person_Concern: 'support',
    New_Signup: 'welcome'
};

const EMPTY_STATES = {
    content: { title: 'No content to review', message: 'Nothing flagged at the moment.' },
    bulkbuy: { title: 'No bulk buy issues', message: 'All bulk buys are running smoothly.' },
    blocked: { title: 'No block reports', message: 'No new blocks to review.' },
    signups: { title: 'No new signups', message: 'Everyone\'s been welcomed!' },
    feedback: { title: 'No feedback to triage', message: 'Inbox zero — well done.' },
    support: { title: 'No support requests', message: 'No pending approvals.' },
    organizations: { title: 'No organization requests', message: 'No new community groups to review.' },
    concerns: { title: 'No support concerns', message: 'No active concerns.' },
    escalated: { title: 'No escalations', message: 'Nothing has been escalated.' },
    health: { title: 'Neighbourhood health', message: 'Patterns and signals worth watching.' }
};

export default class FimbyModeratorDashboard extends NavigationMixin(LightningElement) {
    @track assignments = [];
    @track selectedNeighbourhoodId;
    @track categoryCounts = {};
    @track urgentCount = 0;
    @track escalatedCount = 0;
    @track totalCount = 0;

    @track _expandedSections = {};
    @track _activeTabs = {};
    @track _sectionTasks = {};
    @track _sectionLoading = {};
    @track _sectionLoadingMore = {};
    @track _sectionHasMore = {};
    @track _sectionOffsets = {};

    @track activeModal = null;
    @track modalPanelData = null;
    @track supportPanelMode = 'approval';
    @track _currentModalTask = null;

    @track overdueLoans = [];
    @track stalePosts = [];
    @track inactiveMembers = [];
    @track isHealthLoading = false;

    accessDenied = false;
    isInitialLoading = true;
    _initialized = false;
    _desktopQuery;

    get lockIconUrl() {
        return `${IMPACT_ICONS}/key.png`;
    }

    get isAuthorized() {
        return !this.accessDenied;
    }

    get isReady() {
        return !this.isInitialLoading;
    }

    get showNeighbourhoodToggle() {
        return this.assignments.length > 1;
    }

    get singleNeighbourhoodName() {
        const a = this.assignments[0];
        return a?.Neighbourhood__r?.Name || '';
    }

    get assignmentsWithToggleClass() {
        return this.assignments.map(a => ({
            ...a,
            _toggleClass: a.Neighbourhood__c === this.selectedNeighbourhoodId
                ? 'toggle-btn active'
                : 'toggle-btn'
        }));
    }

    get archiveHref() {
        const nbh = this.selectedNeighbourhoodId || '';
        return nbh ? `/moderator-task-archive?nbh=${nbh}` : '/moderator-task-archive';
    }

    get archiveIconUrl() {
        return `${IMPACT_ICONS}/archive.png`;
    }

    get isDesktop() {
        return this._desktopQuery?.matches ?? false;
    }

    // ================================================================
    // Triage Summary
    // ================================================================

    get triageSummaryText() {
        const parts = [];
        if (this.escalatedCount > 0) {
            parts.push(`${this.escalatedCount} item${this.escalatedCount !== 1 ? 's are' : ' is'} escalated to admin`);
        }
        if (this.urgentCount > 0) {
            parts.push(`${this.urgentCount} urgent item${this.urgentCount !== 1 ? 's' : ''} need${this.urgentCount === 1 ? 's' : ''} review`);
        }
        if (parts.length === 0) {
            return this.totalCount > 0
                ? `${this.totalCount} open task${this.totalCount !== 1 ? 's' : ''} — nothing urgent`
                : 'All clear — no open tasks right now';
        }
        return parts.join(' and ');
    }

    get showTriageEscalated() {
        return this.escalatedCount > 0;
    }

    get showTriageUrgent() {
        return this.urgentCount > 0;
    }

    // ================================================================
    // Sections
    // ================================================================

    get sections() {
        return SECTIONS.map(section => {
            const sectionCount = this._getSectionCount(section);
            const isExpanded = !!this._expandedSections[section.key];
            const activeTabKey = this._activeTabs[section.key] || section.tabs[0]?.key;
            const hasTabs = section.tabs.length > 1;
            const iconUrl = section.icon ? `${IMPACT_ICONS}/${section.icon}` : '';

            const tabs = section.tabs.map(tab => {
                const tabCount = this._getTabCount(tab);
                const isActive = tab.key === activeTabKey;
                return {
                    ...tab,
                    count: tabCount,
                    isActive,
                    tabClass: isActive ? 'section-tab active' : 'section-tab' + (tabCount === 0 ? ' muted' : ''),
                    ariaSelected: isActive ? 'true' : 'false',
                    countLabel: `${tabCount}`
                };
            });

            const activeTab = tabs.find(t => t.isActive) || tabs[0];
            const tasks = this._sectionTasks[this._taskKey(section.key, activeTab.key)] || [];
            const isLoading = !!this._sectionLoading[this._taskKey(section.key, activeTab.key)];
            const isLoadingMore = !!this._sectionLoadingMore[this._taskKey(section.key, activeTab.key)];
            const hasMore = !!this._sectionHasMore[this._taskKey(section.key, activeTab.key)];
            const emptyTitle = (EMPTY_STATES[activeTab.key] || { title: 'All clear' }).title;
            const emptyMessage = (EMPTY_STATES[activeTab.key] || { message: 'No tasks waiting.' }).message;

            const isHealthSection = section.key === 'health';
            const isEscalatedSection = section.key === 'adminEscalations';
            const isTaskSection = !isHealthSection;
            const sectionCtaConfigs = isEscalatedSection ? ESCALATED_CTA_CONFIGS : CTA_CONFIGS;

            return {
                ...section,
                sectionCount,
                isExpanded,
                isEmpty: sectionCount === 0,
                iconUrl,
                hasTabs,
                tabs,
                activeTab,
                tasks,
                isLoading,
                isLoadingMore,
                hasMore,
                emptyTitle,
                emptyMessage,
                isHealthSection,
                isTaskSection,
                ctaConfigs: sectionCtaConfigs,
                headerClass: 'section-header' + (isExpanded ? ' expanded' : ''),
                bodyId: `section-body-${section.key}`,
                ariaExpanded: isExpanded ? 'true' : 'false',
                sectionClass: this._buildSectionClass(section, sectionCount, isExpanded),
                sectionStyle: this._buildSectionStyle(section),
                countDisplay: sectionCount === 0 ? 'quiet' : `${sectionCount}`,
                chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    _buildSectionClass(section, count, isExpanded) {
        let cls = 'priority-section';
        if (count === 0) cls += ' empty-section';
        if (isExpanded) cls += ' expanded';
        if (section.borderVar) cls += ` accent-${section.key}`;
        return cls;
    }

    _buildSectionStyle(section) {
        if (!section.borderVar) return '';
        return `--section-border-color: var(${section.borderVar}); --section-bg-color: var(${section.accentVar});`;
    }

    _getSectionCount(section) {
        if (section.key === 'adminEscalations') return this.escalatedCount;
        if (section.key === 'health') return 0;
        return section.tabs.reduce((sum, tab) => {
            return sum + (this.categoryCounts[tab.category] || 0);
        }, 0);
    }

    _getTabCount(tab) {
        if (tab.isEscalated) return this.escalatedCount;
        if (tab.isHealth) return 0;
        return this.categoryCounts[tab.category] || 0;
    }

    _taskKey(sectionKey, tabKey) {
        return `${sectionKey}__${tabKey}`;
    }

    // ================================================================
    // Modal Getters
    // ================================================================

    get isContentModal() { return this.activeModal === 'content'; }
    get isFollowUpModal() { return this.activeModal === 'followUp'; }
    get isBlockModal() { return this.activeModal === 'block'; }
    get isWelcomeModal() { return this.activeModal === 'welcome'; }
    get isFeedbackModal() { return this.activeModal === 'feedback'; }
    get isSupportModal() { return this.activeModal === 'support'; }
    get isEscalationModal() { return this.activeModal === 'escalation'; }

    // ================================================================
    // Lifecycle
    // ================================================================

    async connectedCallback() {
        if (this._initialized) return;
        this._initialized = true;
        this._desktopQuery = window.matchMedia('(min-width: 1024px)');
        this._restoreState();
        await this._initDashboard();
    }

    // ================================================================
    // Initialization
    // ================================================================

    async _initDashboard() {
        try {
            const assignments = await getModeratorAssignments();
            if (!assignments || assignments.length === 0) {
                this.accessDenied = true;
                this.isInitialLoading = false;
                return;
            }
            this.assignments = assignments;

            if (!this.selectedNeighbourhoodId || !assignments.some(a => a.Neighbourhood__c === this.selectedNeighbourhoodId)) {
                this.selectedNeighbourhoodId = assignments[0].Neighbourhood__c;
            }

            await this._loadSummary();
            this._autoExpandSections();
            await this._loadVisibleSections();
            this.isInitialLoading = false;
        } catch (error) {
            this._showError('Failed to load dashboard', error);
            this.isInitialLoading = false;
        }
    }

    async _loadSummary() {
        try {
            const result = await getDashboardSummary({ neighbourhoodId: this.selectedNeighbourhoodId });
            this.categoryCounts = result.categoryCounts || {};
            this.urgentCount = result.urgentCount || 0;
            this.escalatedCount = result.escalatedCount || 0;
            this.totalCount = result.totalCount || 0;
        } catch (error) {
            this._showError('Failed to load summary', error);
        }
    }

    _autoExpandSections() {
        const hasStoredState = Object.keys(this._expandedSections).length > 0;
        if (hasStoredState) return;

        if (!this.isDesktop) {
            this._expandedSections = {};
            return;
        }

        const expanded = {};
        for (const section of SECTIONS) {
            if (this._getSectionCount(section) > 0) {
                expanded[section.key] = true;
            }
        }
        this._expandedSections = { ...expanded };
    }

    async _loadVisibleSections() {
        const promises = [];
        for (const section of SECTIONS) {
            if (this._expandedSections[section.key]) {
                const activeTabKey = this._activeTabs[section.key] || section.tabs[0]?.key;
                const tab = section.tabs.find(t => t.key === activeTabKey) || section.tabs[0];
                if (tab) {
                    promises.push(this._loadSectionTab(section, tab));
                }
            }
        }
        await Promise.all(promises);
    }

    async _loadSectionTab(section, tab) {
        const key = this._taskKey(section.key, tab.key);
        this._sectionLoading = { ...this._sectionLoading, [key]: true };
        this._sectionOffsets = { ...this._sectionOffsets, [key]: 0 };

        try {
            let tasks;
            if (tab.isEscalated) {
                tasks = await getEscalatedTasks({
                    neighbourhoodId: this.selectedNeighbourhoodId,
                    pageSize: PAGE_SIZE,
                    offset: 0
                });
            } else if (tab.isHealth) {
                await this._loadHealthData();
                this._sectionLoading = { ...this._sectionLoading, [key]: false };
                return;
            } else {
                tasks = await getTasksByCategory({
                    neighbourhoodId: this.selectedNeighbourhoodId,
                    category: tab.category,
                    pageSize: PAGE_SIZE,
                    offset: 0
                });
            }
            const fetched = tasks || [];
            this._sectionTasks = { ...this._sectionTasks, [key]: fetched };
            this._sectionHasMore = { ...this._sectionHasMore, [key]: fetched.length >= PAGE_SIZE };
            this._sectionOffsets = { ...this._sectionOffsets, [key]: fetched.length };
        } catch (error) {
            this._showError('Failed to load tasks', error);
            this._sectionTasks = { ...this._sectionTasks, [key]: [] };
        } finally {
            this._sectionLoading = { ...this._sectionLoading, [key]: false };
        }
    }

    async _loadHealthData() {
        this.isHealthLoading = true;
        try {
            const data = await getNeighbourhoodHealthData({
                neighbourhoodId: this.selectedNeighbourhoodId
            });
            this.overdueLoans = (data?.overdueLoans || []).map(loan => ({
                ...loan,
                _overdueClass: loan.daysOverdue > 14 ? 'overdue-critical' : 'overdue-warning'
            }));
            this.stalePosts = data?.stalePosts || [];
            this.inactiveMembers = data?.inactiveMembers || [];
        } catch (error) {
            this._showError('Failed to load health data', error);
            this.overdueLoans = [];
            this.stalePosts = [];
            this.inactiveMembers = [];
        } finally {
            this.isHealthLoading = false;
        }
    }

    // ================================================================
    // Event Handlers — Neighbourhood & Sections
    // ================================================================

    handleNeighbourhoodChange(event) {
        const id = event.currentTarget.dataset.id;
        if (id === this.selectedNeighbourhoodId) return;
        this.selectedNeighbourhoodId = id;
        this._sectionTasks = {};
        this._sectionOffsets = {};
        this._persistState();
        this._loadSummary().then(() => {
            this._autoExpandSections();
            this._loadVisibleSections();
        });
    }

    handleSectionToggle(event) {
        const sectionKey = event.currentTarget.dataset.section;
        const wasExpanded = !!this._expandedSections[sectionKey];
        this._expandedSections = { ...this._expandedSections, [sectionKey]: !wasExpanded };
        this._persistState();

        if (!wasExpanded) {
            const section = SECTIONS.find(s => s.key === sectionKey);
            if (section) {
                const activeTabKey = this._activeTabs[sectionKey] || section.tabs[0]?.key;
                const tab = section.tabs.find(t => t.key === activeTabKey) || section.tabs[0];
                const key = this._taskKey(sectionKey, tab.key);
                if (!this._sectionTasks[key]) {
                    this._loadSectionTab(section, tab);
                }
            }
        }
    }

    handleTabChange(event) {
        const sectionKey = event.currentTarget.dataset.section;
        const tabKey = event.currentTarget.dataset.tab;
        if (this._activeTabs[sectionKey] === tabKey) return;

        this._activeTabs = { ...this._activeTabs, [sectionKey]: tabKey };
        this._persistState();

        const section = SECTIONS.find(s => s.key === sectionKey);
        if (section) {
            const tab = section.tabs.find(t => t.key === tabKey);
            const key = this._taskKey(sectionKey, tab.key);
            if (!this._sectionTasks[key]) {
                this._loadSectionTab(section, tab);
            }
        }
    }

    handleTriageEscalated() {
        this._expandedSections = { ...this._expandedSections, adminEscalations: true };
        this._persistState();
        const section = SECTIONS[0];
        const tab = section.tabs[0];
        const key = this._taskKey(section.key, tab.key);
        if (!this._sectionTasks[key]) {
            this._loadSectionTab(section, tab);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const el = this.template.querySelector('[data-section-id="adminEscalations"]');
            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
    }

    handleTriageUrgent() {
        this._expandedSections = { ...this._expandedSections, attention: true };
        this._persistState();
        const section = SECTIONS[1];
        const tab = section.tabs[0];
        const key = this._taskKey(section.key, tab.key);
        if (!this._sectionTasks[key]) {
            this._loadSectionTab(section, tab);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const el = this.template.querySelector('[data-section-id="attention"]');
            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
    }

    async handleLoadMore(event) {
        const sectionKey = event.currentTarget.dataset.section;
        const tabKey = event.currentTarget.dataset.tab;
        const key = this._taskKey(sectionKey, tabKey);

        if (this._sectionLoadingMore[key] || !this._sectionHasMore[key]) return;
        this._sectionLoadingMore = { ...this._sectionLoadingMore, [key]: true };

        try {
            const section = SECTIONS.find(s => s.key === sectionKey);
            const tab = section?.tabs.find(t => t.key === tabKey);
            const offset = this._sectionOffsets[key] || 0;
            let moreTasks;

            if (tab?.isEscalated) {
                moreTasks = await getEscalatedTasks({
                    neighbourhoodId: this.selectedNeighbourhoodId,
                    pageSize: PAGE_SIZE,
                    offset
                });
            } else {
                moreTasks = await getTasksByCategory({
                    neighbourhoodId: this.selectedNeighbourhoodId,
                    category: tab?.category,
                    pageSize: PAGE_SIZE,
                    offset
                });
            }
            const fetched = moreTasks || [];
            const existing = this._sectionTasks[key] || [];
            this._sectionTasks = { ...this._sectionTasks, [key]: [...existing, ...fetched] };
            this._sectionHasMore = { ...this._sectionHasMore, [key]: fetched.length >= PAGE_SIZE };
            this._sectionOffsets = { ...this._sectionOffsets, [key]: offset + fetched.length };
        } catch (error) {
            this._showError('Failed to load more tasks', error);
        } finally {
            this._sectionLoadingMore = { ...this._sectionLoadingMore, [key]: false };
        }
    }

    handleBottomTabChange(event) {
        const tab = event.detail?.tab;
        if (tab) {
            const path = tab === 'home' ? '/'
                : tab === 'mine' ? '/my-stuff'
                : tab === 'library' ? '/library-list'
                : `/${tab}`;
            navigate(this, path);
        }
    }

    handleArchiveClick() {
        navigate(this, this.archiveHref);
    }

    // ================================================================
    // Task Actions (from task list row CTAs)
    // ================================================================

    async handleTaskAction(event) {
        const { action, task } = event.detail;
        const category = task.Category__c || '';
        const isDesktop = this._desktopQuery?.matches;

        if (action === 'review' && this._isComplexCategory(category)) {
            navigate(this, `/moderator-task?recordId=${task.Id}`);
            return;
        }

        switch (action) {
            case 'review':
                await this._openReviewModal(task);
                break;
            case 'welcome':
                await this._openWelcomeModal(task);
                break;
            case 'dismiss':
            case 'markReviewed':
                await this._resolveTaskInline(task, 'Dismissed');
                break;
            case 'markWelcomed':
                await this._markWelcomedInline(task);
                break;
            case 'viewProfile':
                this._navigateToProfile(task);
                break;
            case 'escalate':
            case 'escalateUrgent':
                navigate(this, `/moderator-task?recordId=${task.Id}`);
                break;
            default:
                break;
        }
    }

    _isComplexCategory(category) {
        return COMPLEX_TASK_CATEGORIES.has(category) || category === 'Escalated';
    }

    async _openReviewModal(task) {
        const category = task.Category__c;
        const modalType = CATEGORY_MODAL_MAP[category];
        if (!modalType) return;

        this._currentModalTask = task;
        try {
            let panelData;
            switch (category) {
                case 'Content_Report':
                    panelData = await getContentReviewData({
                        recordId: task.Related_Record_Id__c,
                        recordType: task.Related_Record_Type__c,
                        taskId: task.Id
                    });
                    break;
                case 'Bulk_Buy_Escalation':
                    panelData = await getFollowUpReviewData({ followUpId: task.Related_Record_Id__c });
                    break;
                case 'Blocked_Contact':
                    panelData = await getBlockReviewData({ blockedContactId: task.Related_Record_Id__c });
                    break;
                case 'Feedback_Triage':
                    panelData = await getFeedbackReviewData({ feedbackId: task.Related_Record_Id__c });
                    break;
                case 'Support_Relationship_Approval':
                    panelData = await getSupportReviewData({ supportRelationshipId: task.Related_Record_Id__c });
                    this.supportPanelMode = 'approval';
                    break;
                case 'Support_Person_Concern':
                    panelData = await getSupportConcernData({ taskId: task.Id });
                    this.supportPanelMode = 'concern';
                    break;
                default:
                    return;
            }
            this._resolveImageUrls(panelData);
            this.modalPanelData = { ...panelData, task };
            this.activeModal = modalType;
            this._showModalShell(task, panelData);
        } catch (error) {
            this._showError('Failed to load review data', error);
        }
    }

    async _openWelcomeModal(task) {
        this._currentModalTask = task;
        try {
            const contactId = task.Subject_Contact__c || task.Related_Record_Id__c;
            const panelData = await getWelcomeReviewData({ contactId });
            this._resolveImageUrls(panelData);
            this.modalPanelData = { ...panelData, task };
            this.activeModal = 'welcome';
            this._showModalShell(task, panelData);
        } catch (error) {
            this._showError('Failed to load welcome data', error);
        }
    }

    async _openEscalateModal(task) {
        this._currentModalTask = task;
        try {
            const detail = await getEscalationDetail({ taskId: task.Id });
            this._resolveImageUrls(detail);
            this.modalPanelData = { ...detail, task };
            this.activeModal = 'escalation';
            this._showModalShell(task, detail);
        } catch (error) {
            this._showError('Failed to load escalation data', error);
        }
    }

    _showModalShell(task, panelData = {}) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            const shell = this.template.querySelector('c-fimby-moderator-task-modal-shell');
            if (shell) {
                shell.show({
                    category: task.Category__c,
                    categoryLabel: this._formatCategoryLabel(task.Category__c),
                    summary: this._stripSummaryPrefix(task.Summary__c, task.Category__c),
                    priority: task.Priority__c,
                    subjectData: panelData.subjectData,
                    evidenceItems: panelData.evidenceItems
                });
            }
        });
    }

    _formatCategoryLabel(category) {
        const labels = {
            Content_Report: 'Content for Review',
            Bulk_Buy_Escalation: 'Bulk Buy',
            Blocked_Contact: 'Blocked',
            New_Signup: 'New Signup',
            Feedback_Triage: 'Feedback',
            Support_Relationship_Approval: 'Support Request',
            Organization_Approval: 'Organization Request',
            Support_Person_Concern: 'Support Concern'
        };
        return labels[category] || (category || '').replace(/_/g, ' ');
    }

    _stripSummaryPrefix(summary, category) {
        if (!summary) return '';
        const patterns = {
            Content_Report: /^Content\s+Report:\s*/i,
            Blocked_Contact: /^Block(?:\s+Report|\s+report\s+filed):?\s*/i,
            Bulk_Buy_Escalation: /^Bulk\s+Buy(?:\s+Escalation)?:\s*/i,
            New_Signup: /^New\s+Sign[\s-]?up:\s*/i,
            Feedback_Triage: /^Feedback(?:\s+Triage)?:\s*/i,
            Support_Relationship_Approval: /^Support(?:\s+Relationship)?(?:\s+Approval)?:\s*/i,
            Organization_Approval: /^New organization:\s*/i,
            Support_Person_Concern: /^Support(?:\s+Person)?(?:\s+Concern)?:\s*/i
        };
        const pattern = patterns[category];
        return pattern ? summary.replace(pattern, '') : summary;
    }

    _resolveImageUrls(data) {
        if (!data) return;
        const photoKeys = [
            'authorPhotoUrl', 'reportedUserPhotoUrl', 'blockerPhotoUrl',
            'blockedPhotoUrl', 'submitterPhotoUrl', 'helperPhotoUrl',
            'subjectPhotoUrl', 'contactPhotoUrl', 'authorizationImageUrl',
            'screenshotUrl'
        ];
        for (const key of photoKeys) {
            if (data[key]) {
                data[key] = avatarImageUrl(data[key]);
            }
        }
        if (data.subjectData?.photoUrl) {
            data.subjectData.photoUrl = avatarImageUrl(data.subjectData.photoUrl);
        }
        if (Array.isArray(data.imageUrls)) {
            data.imageUrls = data.imageUrls.map(u => completeImageUrl(u));
        }
    }

    async _resolveTaskInline(task, resolution) {
        // Optimistically drop the row so the list reflows in place (no spinner flash).
        // The synchronous removal also closes the double-tap window before the await.
        const removed = this._removeTaskAndCounts(task);
        try {
            await resolveTask({ taskId: task.Id, resolution, notes: '' });
            invalidateModeratorContext();
            this._loadSummary();
        } catch (error) {
            this._showError('Failed to resolve task', error);
            if (removed) await this._refreshAfterAction();
        }
    }

    async _markWelcomedInline(task) {
        const removed = this._removeTaskAndCounts(task);
        try {
            const contactId = task.Subject_Contact__c || task.Related_Record_Id__c;
            await markWelcomed({ contactId, taskId: task.Id, notes: '' });
            invalidateModeratorContext();
            this._loadSummary();
        } catch (error) {
            this._showError('Failed to mark welcomed', error);
            if (removed) await this._refreshAfterAction();
        }
    }

    // Remove a single resolved task from every section list and decrement its
    // counts, without re-fetching — keeps the other rows mounted.
    _removeTaskAndCounts(task) {
        const removed = this._removeTaskLocally(task.Id);
        if (removed) this._decrementCounts(task.Category__c);
        return removed;
    }

    _removeTaskLocally(taskId) {
        let removed = false;
        const next = {};
        for (const key of Object.keys(this._sectionTasks)) {
            const arr = this._sectionTasks[key] || [];
            const filtered = arr.filter(t => t.Id !== taskId);
            if (filtered.length !== arr.length) removed = true;
            next[key] = filtered;
        }
        if (removed) this._sectionTasks = next;
        return removed;
    }

    _decrementCounts(category) {
        if (category && this.categoryCounts[category] > 0) {
            this.categoryCounts = {
                ...this.categoryCounts,
                [category]: this.categoryCounts[category] - 1
            };
        }
        if (this.totalCount > 0) this.totalCount -= 1;
    }

    _navigateToProfile(task) {
        const contactId = task.Subject_Contact__c || task.Related_Record_Id__c;
        if (contactId) {
            navigate(this, `/neighbour?id=${contactId}`);
        }
    }

    // ================================================================
    // Modal Actions (from modal panels)
    // ================================================================

    async handleModalAction(event) {
        const { action, payload = {} } = event.detail;
        const task = this._currentModalTask;
        if (!task) return;

        try {
            switch (action) {
                case 'republish':
                    await republishContent({
                        recordId: payload.recordId || task.Related_Record_Id__c,
                        recordType: payload.recordType || task.Related_Record_Type__c,
                        taskId: task.Id
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'keepHidden':
                    await keepContentHidden({
                        taskId: task.Id,
                        reasonCode: payload.reasonCode || '',
                        statement: payload.statement || '',
                        notes: payload.notes || ''
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'checkIn':
                    await issueCheckIn({
                        taskId: task.Id,
                        subjectContactId: payload.subjectContactId || task.Subject_Contact__c,
                        reasonCode: payload.reasonCode || '',
                        messageBody: payload.messageBody || ''
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'recordConcern':
                    await recordConcern({
                        taskId: task.Id,
                        subjectContactId: payload.subjectContactId || task.Subject_Contact__c,
                        reasonCode: payload.reasonCode || '',
                        statement: payload.statement || ''
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'contactAuthor':
                case 'contactReporter':
                case 'contactBlocked':
                case 'contactBlocker':
                case 'contactReported':
                case 'contactOrganiser':
                case 'contactHelper':
                case 'contactSubject':
                case 'respondToUser':
                    await this._navigateToConversation(
                        payload.contactId
                        || this.modalPanelData?.submitterContactId
                        || this.modalPanelData?.helperContactId
                        || this.modalPanelData?.subjectContactId
                    );
                    break;

                case 'sendWelcome': {
                    const contactId = payload.contactId || task.Subject_Contact__c || task.Related_Record_Id__c;
                    await sendWelcomeMessage({
                        contactId,
                        messageBody: payload.message || '',
                        taskId: task.Id
                    });
                    const conversationId = await getOrCreateModeratorConversation({ targetContactId: contactId });
                    this._closeModal();
                    invalidateModeratorContext();
                    this._refreshAfterAction();
                    navigate(this, `/conversation?id=${conversationId}`);
                    break;
                }

                case 'markWelcomed': {
                    const contactId = payload.contactId || task.Subject_Contact__c || task.Related_Record_Id__c;
                    await markWelcomed({ contactId, taskId: task.Id, notes: payload.notes || '' });
                    this._closeModalAndRemoveTask(task);
                    break;
                }

                case 'markReviewed':
                case 'dismiss':
                case 'noAction':
                    await resolveTask({ taskId: task.Id, resolution: 'Dismissed', notes: payload.notes || '' });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'triageTraining':
                    await triageFeedback({
                        feedbackId: payload.feedbackId || task.Related_Record_Id__c,
                        triageStatus: 'Training_Needed',
                        taskId: task.Id
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'triageEnhancement':
                    await triageFeedback({
                        feedbackId: payload.feedbackId || task.Related_Record_Id__c,
                        triageStatus: 'Enhancement_Flagged',
                        taskId: task.Id
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'triageNotActionable':
                    await triageFeedback({
                        feedbackId: payload.feedbackId || task.Related_Record_Id__c,
                        triageStatus: 'Not_Actionable',
                        taskId: task.Id
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'approve':
                    await approveSupportRelationship({
                        supportRelationshipId: payload.supportRelationshipId || task.Related_Record_Id__c,
                        taskId: task.Id
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'decline':
                    await declineSupportRelationship({
                        supportRelationshipId: payload.supportRelationshipId || task.Related_Record_Id__c,
                        reasonCode: payload.reasonCode || '',
                        statement: payload.statement || '',
                        taskId: task.Id
                    });
                    this._closeModalAndRemoveTask(task);
                    break;

                case 'requestMoreInfo':
                    await this._navigateToConversation(payload.contactId || this.modalPanelData?.helperContactId);
                    break;

                case 'escalate':
                case 'escalateUrgent':
                    await escalateTask({
                        taskId: task.Id,
                        reason: payload.reason || '',
                        adminContactId: payload.adminContactId || null
                    });
                    this._closeModalAndRefresh();
                    break;

                case 'viewOriginal':
                case 'viewBulkBuy':
                    if (payload.url) {
                        navigate(this, payload.url);
                    }
                    break;

                case 'viewImage': {
                    const imageUrls = payload.imageUrls || [];
                    const imageUrl = imageUrls[payload.index];
                    if (imageUrl) window.open(imageUrl, '_blank');
                    break;
                }

                case 'viewProfile':
                    if (payload.contactId || this.modalPanelData?.contactId) {
                        navigate(this, `/neighbour?id=${payload.contactId || this.modalPanelData?.contactId}`);
                    }
                    break;

                case 'followUp':
                    await this._navigateToConversation(
                        payload.escalatedToContactId
                        || payload.contactId
                        || this.modalPanelData?.escalatedToContactId
                    );
                    break;

                case 'reopen':
                    await reopenTask({ taskId: task.Id });
                    this._closeModalAndRefresh();
                    break;

                case 'transferOwnership':
                    await reopenTask({ taskId: task.Id });
                    this._closeModalAndRefresh();
                    break;

                case 'welfareCheck':
                    await this._navigateToConversation(
                        payload.subjectContactId
                        || payload.contactId
                        || this.modalPanelData?.subjectContactId
                    );
                    break;

                default:
                    break;
            }
        } catch (error) {
            this._showError('Action failed', error);
        }
    }

    // ================================================================
    // Health Tab Actions
    // ================================================================

    handleHealthAction(event) {
        const { action, recordId, contactId } = event.detail || {};
        switch (action) {
            case 'viewItem':
                if (recordId) navigate(this, `/library-item/${recordId}`);
                break;
            case 'viewPost':
                if (recordId) navigate(this, `/ask-or-offer-post?recordId=${recordId}`);
                break;
            case 'viewProfile':
                if (recordId) navigate(this, `/neighbour?id=${recordId}`);
                break;
            case 'contactBorrower':
            case 'contactOwner':
            case 'contactAuthor':
            case 'sendCheckin':
                if (contactId) this._navigateToConversation(contactId);
                break;
            default:
                break;
        }
    }

    // ================================================================
    // Modal Close
    // ================================================================

    handleModalClose() {
        this._closeModal();
    }

    _closeModal() {
        const shell = this.template.querySelector('c-fimby-moderator-task-modal-shell');
        if (shell) shell.hide();
        this.activeModal = null;
        this.modalPanelData = null;
        this._currentModalTask = null;
    }

    _closeModalAndRefresh() {
        this._closeModal();
        this._refreshAfterAction();
    }

    // For modal actions that resolve a task in place: drop the underlying row and
    // refresh counts only, so closing the modal doesn't flash the list behind it.
    _closeModalAndRemoveTask(task) {
        if (task) this._removeTaskAndCounts(task);
        this._closeModal();
        invalidateModeratorContext();
        this._loadSummary();
    }

    async _refreshAfterAction() {
        invalidateModeratorContext();
        this._sectionTasks = {};
        this._sectionOffsets = {};
        await this._loadSummary();
        await this._loadVisibleSections();
    }

    // ================================================================
    // Navigation Helpers
    // ================================================================

    async _navigateToConversation(contactId) {
        if (!contactId) return;
        try {
            const conversationId = await getOrCreateModeratorConversation({ targetContactId: contactId });
            this._closeModal();
            navigate(this, `/conversation?id=${conversationId}`);
        } catch (error) {
            this._showError('Failed to open conversation', error);
        }
    }

    // ================================================================
    // State Persistence
    // ================================================================

    _persistState() {
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify({
                selectedNeighbourhoodId: this.selectedNeighbourhoodId,
                expandedSections: this._expandedSections,
                activeTabs: this._activeTabs
            }));
        } catch (_e) { /* storage unavailable */ }
    }

    _restoreState() {
        try {
            const raw = localStorage.getItem(STORAGE_KEY);
            if (raw) {
                const state = JSON.parse(raw);
                if (state.selectedNeighbourhoodId) this.selectedNeighbourhoodId = state.selectedNeighbourhoodId;
                if (state.expandedSections) this._expandedSections = state.expandedSections;
                if (state.activeTabs) this._activeTabs = state.activeTabs;
            }
        } catch (_e) { /* storage unavailable */ }
    }

    // ================================================================
    // Toast Helpers
    // ================================================================

    // Success needs no banner here: every action closes the modal and removes
    // the task from the queue, so the surface itself confirms the change.
    // Operation failures route to the shell toast (assertive, global).
    _showError(title, error) {
        fireErrorToast(error);
    }
}