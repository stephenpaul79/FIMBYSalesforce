import { LightningElement, api, track } from 'lwc';

const CATEGORY_BADGE_MAP = {
    Content_Report:                  'category-badge error',
    Bulk_Buy_Escalation:             'category-badge warning',
    Blocked_Contact:                    'category-badge info',
    New_Signup:                      'category-badge success',
    Feedback_Triage:                 'category-badge info',
    Support_Relationship_Approval:   'category-badge warning',
    Support_Person_Concern:          'category-badge warning'
};

export default class FimbyModeratorTaskModalShell extends LightningElement {

    @track _isVisible = false;
    @track _taskData = {};
    @track _viewState = 'loading'; // loading | ready | error

    _previousActiveElement = null;
    _savedBodyOverflow = '';

    // ── Public API ──────────────────────────────────────────────────

    @api
    show(taskData) {
        this._previousActiveElement = document.activeElement;
        this._taskData = taskData || {};
        this._viewState = 'ready';
        this._isVisible = true;
        this._lockBodyScroll();

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const container = this.template.querySelector('.modal-container');
            if (container) {
                container.focus({ preventScroll: true });
            }
        });
    }

    @api
    hide() {
        this._unlockBodyScroll();
        this._isVisible = false;
        this.dispatchEvent(new CustomEvent('close'));

        if (this._previousActiveElement) {
            try { this._previousActiveElement.focus(); } catch (_) { /* element may be gone */ }
            this._previousActiveElement = null;
        }
    }

    // ── Lifecycle ───────────────────────────────────────────────────

    disconnectedCallback() {
        if (this._isVisible) {
            this._unlockBodyScroll();
            this._isVisible = false;
        }
    }

    // ── Getters ─────────────────────────────────────────────────────

    get hasSubjectData() {
        return !!(this._taskData && this._taskData.subjectData);
    }

    get hasEvidence() {
        return !!(this._taskData && this._taskData.evidenceItems && this._taskData.evidenceItems.length);
    }

    get categoryBadgeClass() {
        const cat = this._taskData?.category;
        return CATEGORY_BADGE_MAP[cat] || 'category-badge';
    }

    get categoryDisplayLabel() {
        return this._taskData?.categoryLabel || (this._taskData?.category || '').replace(/_/g, ' ');
    }

    get priorityClass() {
        const p = this._taskData?.priority;
        if (p === 'Urgent' || p === 'High' || p === 'Critical') return 'priority-high';
        if (p === 'Standard' || p === 'Medium') return 'priority-medium';
        return 'priority-low';
    }

    // ── Event handlers ──────────────────────────────────────────────

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.hide();
        }
    }

    handleClose() {
        this.hide();
    }

    // ── Body scroll lock/unlock ─────────────────────────────────────

    _lockBodyScroll() {
        this._savedBodyOverflow = document.body.style.overflow;
        document.body.style.overflow = 'hidden';
    }

    _unlockBodyScroll() {
        document.body.style.overflow = this._savedBodyOverflow;
    }
}