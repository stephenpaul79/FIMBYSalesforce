import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const CATEGORY_LABELS = {
    Content_Report: 'Content for Review',
    Bulk_Buy_Escalation: 'Bulk Buy',
    Blocked_Contact: 'Blocked',
    New_Signup: 'New Signup',
    Feedback_Triage: 'Feedback',
    Support_Relationship_Approval: 'Support Request',
    Organization_Approval: 'Organization Request',
    Support_Person_Concern: 'Support Concern'
};

const SUMMARY_PREFIX_PATTERNS = {
    Content_Report: /^Content\s+Report:\s*/i,
    Blocked_Contact: /^Block(?:\s+Report|\s+report\s+filed):?\s*/i,
    Bulk_Buy_Escalation: /^Bulk\s+Buy(?:\s+Escalation)?:\s*/i,
    New_Signup: /^New\s+Sign[\s-]?up:\s*/i,
    Feedback_Triage: /^Feedback(?:\s+Triage)?:\s*/i,
    Support_Relationship_Approval: /^Support(?:\s+Relationship)?(?:\s+Approval)?:\s*/i,
    Organization_Approval: /^New organization:\s*/i,
    Support_Person_Concern: /^Support(?:\s+Person)?(?:\s+Concern)?:\s*/i
};

export default class FimbyModeratorTaskList extends LightningElement {
    @api isLoading = false;
    @api isLoadingMore = false;
    @api hasMore = false;
    @api emptyTitle = 'All clear';
    @api emptyMessage = 'No tasks waiting for you right now.';

    _ctaConfig = [];
    _rawTasks = [];
    _tasks = [];

    @api
    get ctaConfig() { return this._ctaConfig; }
    set ctaConfig(value) {
        this._ctaConfig = value || [];
        if (this._rawTasks.length) {
            this._tasks = this._rawTasks.map(t => this._processTask(t));
        }
    }

    @api
    get tasks() { return this._tasks; }
    set tasks(value) {
        this._rawTasks = value || [];
        this._tasks = this._rawTasks.map(t => this._processTask(t));
    }

    get analysisIconUrl() { return `${IMPACT_ICONS}/analysis.png`; }
    get hasTasks() { return !this.isLoading && this._tasks.length > 0; }
    get showEmptyState() { return !this.isLoading && this._tasks.length === 0; }
    get processedTasks() { return this._tasks; }
    get showLoadMore() { return this.hasMore && !this.isLoading; }

    _processTask(task) {
        const category = task.Category__c || '';
        const reportCount = task.Report_Count__c || 0;
        const isOverdue = task.Is_Overdue__c === true;

        return {
            ...task,
            _categoryLabel: CATEGORY_LABELS[category] || category.replace(/_/g, ' '),
            _categoryClass: 'category-badge',
            _displaySummary: this._stripPrefix(task.Summary__c, category),
            _reportCountLabel: reportCount > 1 ? `raised ${reportCount} times` : '',
            _age: this._formatAge(task.CreatedDate),
            _isOverdue: isOverdue,
            _ageClass: isOverdue ? 'task-age task-age--overdue' : 'task-age',
            _ctas: this._buildCtas(task)
        };
    }

    _stripPrefix(summary, category) {
        if (!summary) return '';
        const pattern = SUMMARY_PREFIX_PATTERNS[category];
        return pattern ? summary.replace(pattern, '') : summary;
    }

    _buildCtas(task) {
        const category = task.Category__c || '';
        const configs = Array.isArray(this._ctaConfig) ? this._ctaConfig : [];
        const config = configs.find(c => c.category === category) || configs.find(c => c.category === 'default');
        if (!config || !config.actions) return [];

        return config.actions.map(a => ({
            ...a,
            iconUrl: a.icon ? `${IMPACT_ICONS}/${a.icon}` : '',
            btnClass: 'task-cta-btn' + (a.variant === 'primary' ? ' primary' : '') + (a.variant === 'danger' ? ' danger' : '')
        }));
    }

    _formatAge(dateStr) {
        if (!dateStr) return '';
        try {
            const d = new Date(dateStr);
            const now = new Date();
            const diffMs = now - d;
            const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
            if (diffHours < 1) return 'Just now';
            if (diffHours < 24) return `${diffHours}h ago`;
            const diffDays = Math.floor(diffHours / 24);
            if (diffDays === 1) return '1 day ago';
            if (diffDays < 30) return `${diffDays} days ago`;
            return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short' });
        } catch (e) {
            return '';
        }
    }

    handleCtaClick(event) {
        const taskId = event.currentTarget.dataset.taskId;
        const action = event.currentTarget.dataset.action;
        const task = this._tasks.find(t => t.Id === taskId);
        this.dispatchEvent(new CustomEvent('taskaction', {
            detail: { task, action },
            bubbles: true,
            composed: true
        }));
    }

    handleLoadMore() {
        this.dispatchEvent(new CustomEvent('loadmore'));
    }
}