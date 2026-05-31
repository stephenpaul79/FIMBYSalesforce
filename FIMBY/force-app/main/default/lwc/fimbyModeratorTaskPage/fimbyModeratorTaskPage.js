import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { invalidateModeratorContext } from 'c/fimbyModeratorContext';

import getTaskPageBootstrap from '@salesforce/apex/FimbyModeratorDashboardController.getTaskPageBootstrap';
import getContentReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getContentReviewData';
import getBlockReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getBlockReviewData';
import getSupportReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getSupportReviewData';
import getSupportConcernData from '@salesforce/apex/FimbyModeratorDashboardController.getSupportConcernData';
import getEscalationDetail from '@salesforce/apex/FimbyModeratorDashboardController.getEscalationDetail';
import getFollowUpReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getFollowUpReviewData';
import getSubjectHistory from '@salesforce/apex/FimbyModeratorDashboardController.getSubjectHistory';
import resolveTask from '@salesforce/apex/FimbyModeratorDashboardController.resolveTask';
import escalateTask from '@salesforce/apex/FimbyModeratorDashboardController.escalateTask';
import reopenTask from '@salesforce/apex/FimbyModeratorDashboardController.reopenTask';
import claimTask from '@salesforce/apex/FimbyModeratorDashboardController.claimTask';
import updateTaskStage from '@salesforce/apex/FimbyModeratorDashboardController.updateTaskStage';
import republishContent from '@salesforce/apex/FimbyModeratorDashboardController.republishContent';
import keepContentHidden from '@salesforce/apex/FimbyModeratorDashboardController.keepContentHidden';
import issueCheckIn from '@salesforce/apex/FimbyModeratorDashboardController.issueCheckIn';
import recordConcern from '@salesforce/apex/FimbyModeratorDashboardController.recordConcern';
import approveSupportRelationship from '@salesforce/apex/FimbyModeratorDashboardController.approveSupportRelationship';
import declineSupportRelationship from '@salesforce/apex/FimbyModeratorDashboardController.declineSupportRelationship';
import getOrganizationReviewData from '@salesforce/apex/FimbyModeratorDashboardController.getOrganizationReviewData';
import approveOrganization from '@salesforce/apex/FimbyModeratorDashboardController.approveOrganization';
import rejectOrganization from '@salesforce/apex/FimbyModeratorDashboardController.rejectOrganization';
import approveOrganizationAndRep from '@salesforce/apex/FimbyModeratorDashboardController.approveOrganizationAndRep';
import adminResolveFollowUp from '@salesforce/apex/FimbyModeratorDashboardController.adminResolveFollowUp';
import getOrCreateModeratorConversation from '@salesforce/apex/FimbyModeratorDashboardController.getOrCreateModeratorConversation';
import getReporterFilingStats from '@salesforce/apex/FimbyModeratorDashboardController.getReporterFilingStats';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';

const NO_PHOTO = '/resource/Impact_Icons/NoProfilePhoto.png';
const BODY_TRUNCATE_LENGTH = 300;

const CATEGORY_LABELS = {
    Content_Report: 'Content for Review',
    Blocked_Contact: 'Block Report',
    Support_Relationship_Approval: 'Support Request',
    Organization_Approval: 'Organization Request',
    Support_Person_Concern: 'Support Concern',
    Escalated: 'Escalated to Admin',
    Bulk_Buy_Escalation: 'Bulk Buy Follow-Up'
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

const CATEGORY_ICONS = {
    Content_Report: 'danger-sign.png',
    Blocked_Contact: 'block-user.png',
    Support_Relationship_Approval: 'hiring.png',
    Organization_Approval: 'CommunityReps.png',
    Support_Person_Concern: 'danger-sign.png',
    Escalated: 'lifesaver.png',
    Bulk_Buy_Escalation: 'checkin.png'
};

const REASON_SUBTYPE_LABELS = {
    Missed_Pickup_Window: 'Missed Pickup',
    Not_Responding: 'Stopped Replying',
    Payment_Not_Settled: 'Payment Not Settled',
    Other: 'Other'
};

export default class FimbyModeratorTaskPage extends LightningElement {
    @track _task = null;
    @track _category = '';
    @track _panelData = null;

    @track _status = '';
    @track _enforcementLevel = '';

    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    @track _activeForm = '';
    @track _formNote = '';
    @track _showReadMore = false;
    @track _collapsedSections = {};
    @track _isProcessing = false;
    @track _showReopenConfirm = false;
    @track _reporterStats = null;
    @track _subjectHistoryExpanded = window.matchMedia('(min-width: 1024px)').matches;
    @track _reporterHistoryExpanded = window.matchMedia('(min-width: 1024px)').matches;

    @track showLightbox = false;
    @track lightboxImages = [];
    @track lightboxStartIndex = 0;

    _recordId;
    _organizationId;
    _initialized = false;

    // ================================================================
    // Icon URLs
    // ================================================================

    get analysisIconUrl() { return `${IMPACT_ICONS}/analysis.png`; }

    get categoryIconUrl() {
        const file = CATEGORY_ICONS[this._category] || 'analysis.png';
        return `${IMPACT_ICONS}/${file}`;
    }

    // ================================================================
    // Header Getters
    // ================================================================

    get categoryLabel() {
        return CATEGORY_LABELS[this._category] || this._category?.replace(/_/g, ' ') || '';
    }

    get taskSummary() {
        const raw = this._task?.Summary__c || '';
        const pattern = SUMMARY_PREFIX_PATTERNS[this._category];
        return pattern ? raw.replace(pattern, '') : raw;
    }
    get taskPriority() { return this._task?.Priority__c || 'Standard'; }
    get isUrgent() { return this.taskPriority === 'Urgent'; }
    get taskAge() { return this._formatAge(this._task?.CreatedDate); }

    // ================================================================
    // Category Booleans
    // ================================================================

    get isContentPage() { return this._category === 'Content_Report'; }
    get isBlockPage() { return this._category === 'Blocked_Contact'; }
    get isSupportApprovalPage() { return this._category === 'Support_Relationship_Approval'; }
    get isOrganizationApprovalPage() { return this._category === 'Organization_Approval'; }

    get taskPageClass() {
        return this.isOrganizationApprovalPage ? 'task-page task-page--org-approval' : 'task-page';
    }

    get reviewMainClass() {
        return this.isOrganizationApprovalPage ? 'review-main review-main--org' : 'review-main';
    }
    get isSupportConcernPage() { return this._category === 'Support_Person_Concern'; }
    get isEscalationPage() { return this._category === 'Escalated'; }
    get isBulkBuyPage() { return this._category === 'Bulk_Buy_Escalation'; }

    get showContent() {
        return !this.isLoading && !this.hasError && this._panelData;
    }

    // ================================================================
    // Lifecycle Stage Computation
    // ================================================================

    get currentStage() {
        const s = this._status;
        const e = this._enforcementLevel;
        if (s === 'New') return 'review';
        if (s === 'Awaiting_Info') return 'awaiting';
        if (s === 'Resolved' || s === 'Dismissed') return 'closed';
        if (s === 'Escalated') return 'escalated';
        if (s === 'In_Progress') {
            if (e === 'Recorded_Concern') return 'logged_concern';
            if (e === 'Check_In') return 'logged_checkin';
            return 'communicate';
        }
        return 'review';
    }

    get stagePrompt() {
        const prompts = {
            review: 'Start by reviewing the details below, then reach out to the people involved',
            communicate: 'Talk to the people involved. When you\'re ready, make your decision or log your response',
            logged_checkin: 'A check-in has been logged. Make your decision, or record a concern if the situation continues',
            logged_concern: 'A concern is on record. Make your decision or ask for help if local facilitation hasn\'t resolved things',
            awaiting: 'Waiting on a response. Follow up or make your decision when you\'re ready',
            closed: 'This task is closed. If something has changed, you can reopen it to take action.',
            escalated: 'This task has been escalated. Follow up with the admin or reopen if needed'
        };
        return prompts[this.currentStage] || '';
    }

    get activeSectionKey() {
        const map = {
            review: 'what-happened',
            awaiting: 'what-happened',
            communicate: 'whos-involved',
            logged_checkin: 'log-response',
            logged_concern: 'log-response',
            closed: 'decision',
            escalated: 'ask-for-help'
        };
        return map[this.currentStage] || 'what-happened';
    }

    sectionClass(sectionKey) {
        const active = this.activeSectionKey;
        const order = ['what-happened', 'decision', 'whos-involved', 'log-response', 'ask-for-help'];
        const activeIdx = order.indexOf(active);
        const thisIdx = order.indexOf(sectionKey);

        let cls = 'page-section';
        if (sectionKey === active) cls += ' section-active';
        else if (thisIdx < activeIdx) cls += ' section-completed';
        return cls;
    }

    get whatHappenedClass() { return this.sectionClass('what-happened'); }
    get decisionClass() { return this.sectionClass('decision'); }
    get whosInvolvedClass() { return 'grid-col-whos ' + this.sectionClass('whos-involved'); }
    get logResponseClass() { return 'grid-col-log ' + this.sectionClass('log-response'); }
    get askForHelpClass() { return 'grid-col-ask ' + this.sectionClass('ask-for-help'); }

    get isClosed() { return this.currentStage === 'closed'; }
    get showTaskActions() { return !this.isClosed; }

    get closedSummaryCardClass() {
        const status = this._task?.Status__c;
        return status === 'Dismissed'
            ? 'closed-summary-card closed-summary-dismissed'
            : 'closed-summary-card closed-summary-resolved';
    }

    get closedStatusLabel() {
        return this._task?.Status__c === 'Dismissed' ? 'Dismissed' : 'Resolved';
    }

    get closedDecisionLabel() {
        const code = this._task?.Decision_Reason_Code__c;
        if (code) {
            return code.replace(/_/g, ' ');
        }
        const level = this._task?.Enforcement_Level__c;
        if (level && level !== 'None') {
            return level.replace(/_/g, ' ');
        }
        return '';
    }

    get closedByLine() {
        const name = this._task?.Resolved_By__r?.Name;
        const date = this._formatClosedDate(this._task?.Resolved_Date__c);
        if (name && date) {
            return `Closed by ${name} · ${date}`;
        }
        if (name) {
            return `Closed by ${name}`;
        }
        if (date) {
            return `Closed ${date}`;
        }
        return '';
    }

    get closedNotes() {
        return this._task?.Notes__c || '';
    }

    get hasClosedNotes() {
        return !!this.closedNotes;
    }

    get showReopenConfirm() {
        return this._showReopenConfirm === true;
    }

    // ================================================================
    // Content Getters (Content Report)
    // ================================================================

    get contentTypeBadge() { return this._panelData?.contentType || ''; }
    get contentTitle() { return this._panelData?.contentTitle || ''; }
    get postDate() { return this._formatAge(this._panelData?.postDate); }

    get contentBody() {
        const body = this._panelData?.contentBody || '';
        if (!this._showReadMore && body.length > BODY_TRUNCATE_LENGTH) {
            return body.substring(0, BODY_TRUNCATE_LENGTH) + '...';
        }
        return body;
    }

    get isBodyLong() {
        return (this._panelData?.contentBody || '').length > BODY_TRUNCATE_LENGTH;
    }

    get readMoreLabel() { return this._showReadMore ? 'Show less' : 'Read more'; }

    get hasImages() {
        return this._panelData?.imageUrls?.length > 0;
    }

    get imageUrls() { return this._panelData?.imageUrls || []; }

    get originalPostUrl() { return this._buildOriginalUrl(); }

    // ================================================================
    // People Getters (shared across categories)
    // ================================================================

    get authorName() { return this._panelData?.authorName || ''; }
    get authorPhoto() { return this._panelData?.authorPhotoUrl || NO_PHOTO; }
    get authorContactId() { return this._panelData?.authorContactId; }

    get reporterName() { return this._panelData?.reporterName || ''; }
    get reporterPhoto() { return this._panelData?.reporterPhotoUrl || NO_PHOTO; }
    get reporterContactId() { return this._panelData?.reporterContactId; }

    get blockerName() { return this._panelData?.blockerName || ''; }
    get blockerPhoto() { return this._panelData?.blockerPhotoUrl || NO_PHOTO; }
    get blockerContactId() { return this._panelData?.blockerContactId; }

    get blockedName() { return this._panelData?.blockedName || ''; }
    get blockedPhoto() { return this._panelData?.blockedPhotoUrl || NO_PHOTO; }
    get blockedContactId() { return this._panelData?.blockedContactId; }

    get helperName() { return this._panelData?.helperName || ''; }
    get helperPhoto() { return this._panelData?.helperPhotoUrl || NO_PHOTO; }
    get helperContactId() { return this._panelData?.helperContactId; }

    get subjectName() { return this._panelData?.subjectName || ''; }
    get subjectPhoto() { return this._panelData?.subjectPhotoUrl || NO_PHOTO; }
    get subjectContactId() { return this._panelData?.subjectContactId; }

    // ================================================================
    // Block Report Getters
    // ================================================================

    get blockDate() { return this._panelData?.date ? this._formatDate(this._panelData.date) : ''; }
    get blockReason() { return this._panelData?.reportDetails || ''; }
    get hasBlockReason() { return !!this._panelData?.reportDetails; }
    get otherBlockCount() { return this._panelData?.otherBlockCount || 0; }
    get hasOtherBlocks() { return this.otherBlockCount > 0; }
    get otherBlocks() { return this._panelData?.otherBlocks || []; }

    // ================================================================
    // Support Getters
    // ================================================================

    get relationshipType() { return this._panelData?.relationshipType || ''; }
    get consentMethod() { return this._panelData?.consentMethod || ''; }
    get supportNotes() { return this._panelData?.notes || ''; }
    get submissionDate() { return this._panelData?.submissionDate ? this._formatDate(this._panelData.submissionDate) : ''; }
    get hasPriorRevocation() { return !!this._panelData?.hasPriorRevocation; }
    get supportRepApproveDisabled() {
        return this._isProcessing || this.supportRepBlockedByOrg;
    }
    get hasAuthorizationImage() { return !!this._panelData?.authorizationImageUrl; }
    get supportAuthorizationImageUrl() { return this._panelData?.authorizationImageUrl || ''; }

    get concernSummary() { return this._panelData?.concernSummary || ''; }
    get helperRecentActivity() { return this._panelData?.helperRecentActivity || []; }
    get hasRecentActivity() { return this.helperRecentActivity.length > 0; }

    // ================================================================
    // Escalation Getters
    // ================================================================

    get originalCategory() { return this._panelData?.originalCategory || ''; }
    get escalationSummary() { return this._panelData?.summary || ''; }
    get escalationReason() { return this._panelData?.escalationReason || ''; }
    get escalatedToName() { return this._panelData?.escalatedToName || ''; }
    get escalatedDate() { return this._panelData?.escalatedDate ? this._formatDate(this._panelData.escalatedDate) : ''; }
    get isResolved() { return !!this._panelData?.isResolved; }
    get resolutionDate() { return this._panelData?.resolutionDate ? this._formatDate(this._panelData.resolutionDate) : ''; }
    get resolutionNotes() { return this._panelData?.resolutionNotes || ''; }

    // ================================================================
    // Bulk Buy Getters
    // ================================================================

    get bulkBuyName() { return this._panelData?.bulkBuyName || ''; }
    get bulkBuyUrl() { return this._panelData?.bulkBuyId ? `/asks-offers/${this._panelData.bulkBuyId}` : ''; }
    get reasonSubtypeLabel() { return REASON_SUBTYPE_LABELS[this._panelData?.reasonSubtype] || this._panelData?.reasonSubtype || ''; }
    get reportMessage() { return this._panelData?.reportMessage || ''; }
    get hasReportMessage() { return !!this._panelData?.reportMessage; }

    get reportedUserName() { return this._panelData?.reportedUserName || ''; }
    get reportedUserPhoto() { return this._panelData?.reportedUserPhotoUrl || NO_PHOTO; }
    get reportedUserId() { return this._panelData?.reportedUserId; }

    get organiserName() { return this._panelData?.organiserName || ''; }
    get organiserPhoto() { return this._panelData?.organiserPhotoUrl || NO_PHOTO; }
    get organiserContactId() { return this._panelData?.organiserContactId; }

    get isBulkBuyBlocked() { return !!this._panelData?.isBlocked; }
    get bulkBuyBlockReason() { return this._panelData?.blockReason || ''; }

    get followUpTimeline() { return this._panelData?.followUpTimeline || []; }
    get hasFollowUpTimeline() { return this.followUpTimeline.length > 0; }

    get showOrganiserCard() {
        return this.organiserContactId && this.organiserContactId !== this.reporterContactId;
    }

    // ================================================================
    // Sidebar Getters (Follow-Up Timeline & Evidence only)
    // ================================================================

    get hasEvidenceTimeline() { return !!this._panelData?.evidenceItems?.length; }
    get evidenceIconUrl() { return `${IMPACT_ICONS}/info.png`; }
    get timelineIconUrl() { return `${IMPACT_ICONS}/checkin.png`; }

    get showFollowUpTimelineSidebar() { return this.isBulkBuyPage && this.hasFollowUpTimeline; }
    get showEvidenceTimeline() { return !this.isBulkBuyPage && this.hasEvidenceTimeline; }

    get hasSidebarContent() {
        return this.showFollowUpTimelineSidebar || this.showEvidenceTimeline;
    }

    // ================================================================
    // Inline History Cards (Subject & Reporter)
    // ================================================================

    get hasSubjectSnapshot() { return !!this._panelData?.subjectData; }
    get showReporterHistory() { return !!this._reporterStats; }
    get showHistoryRow() { return this.hasSubjectSnapshot || this.showReporterHistory; }

    get subjectHistoryName() { return this._panelData?.subjectData?.name || ''; }
    get subjectHistoryPhoto() { return this._panelData?.subjectData?.photoUrl || NO_PHOTO; }
    get subjectHistoryPronouns() { return this._panelData?.subjectData?.pronouns || ''; }
    get subjectReportCount() { return this._panelData?.subjectData?.totalReports || 0; }
    get subjectCheckInCount() { return this._panelData?.subjectData?.checkIns || 0; }
    get subjectConcernCount() { return this._panelData?.subjectData?.recordedConcerns || 0; }
    get subjectBlockCount() { return this._panelData?.subjectData?.blockIncidents || 0; }
    get subjectRecentCases() { return this._panelData?.subjectData?.recentCases || []; }
    get hasSubjectRecentCases() { return this.subjectRecentCases.length > 0; }

    get noSubjectHistory() {
        const sd = this._panelData?.subjectData;
        if (!sd) return false;
        return !this.hasSubjectRecentCases && sd.totalReports === 0 && sd.checkIns === 0
            && sd.recordedConcerns === 0 && sd.blockIncidents === 0;
    }

    get reporterHistoryName() { return this.reporterName || 'Reporter'; }
    get reporterHistoryPhoto() { return this.reporterPhoto; }
    get reporterLast90() { return this._reporterStats?.reportsLast90Days || 0; }
    get reporterTotal() { return this._reporterStats?.reportsTotal || 0; }

    get isSubjectExpanded() { return this._subjectHistoryExpanded; }
    get isReporterExpanded() { return this._reporterHistoryExpanded; }
    get subjectChevronIcon() { return this._subjectHistoryExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get reporterChevronIcon() { return this._reporterHistoryExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get subjectAriaExpanded() { return String(this._subjectHistoryExpanded); }
    get reporterAriaExpanded() { return String(this._reporterHistoryExpanded); }

    toggleSubjectHistory() { this._subjectHistoryExpanded = !this._subjectHistoryExpanded; }
    toggleReporterHistory() { this._reporterHistoryExpanded = !this._reporterHistoryExpanded; }

    // ================================================================
    // Enforcement State & Disabled Getters
    // ================================================================

    get isCheckInDone() {
        return ['Check_In', 'Recorded_Concern', 'Admin_Review'].includes(this._enforcementLevel);
    }

    get isConcernDone() {
        return ['Recorded_Concern', 'Admin_Review'].includes(this._enforcementLevel);
    }

    get isEscalateDone() {
        return this._status === 'Escalated' || this._enforcementLevel === 'Admin_Review';
    }

    get checkInDisabled() { return this.isCheckInDone || this._isProcessing; }
    get concernDisabled() { return this.isConcernDone || this._isProcessing; }
    get escalateDisabled() { return this.isEscalateDone || this._isProcessing; }

    get checkInStatusText() {
        return this.isCheckInDone ? 'Check-in logged' : '';
    }

    get concernStatusText() {
        return this.isConcernDone ? 'Concern recorded' : '';
    }

    get escalateStatusText() {
        if (!this.isEscalateDone) return '';
        const d = this._panelData?.escalatedDate;
        return d ? `Escalated ${this._formatAge(d)}` : 'Escalated to admin';
    }

    // ================================================================
    // History Badge Getters
    // ================================================================

    get authorHistoryBadges() {
        const sd = this._panelData?.subjectData;
        if (!sd) return [];
        const badges = [];
        if (sd.totalReports > 0) badges.push({ label: `${sd.totalReports} report${sd.totalReports !== 1 ? 's' : ''}`, key: 'reports' });
        if (sd.checkIns > 0) badges.push({ label: `${sd.checkIns} check-in${sd.checkIns !== 1 ? 's' : ''}`, key: 'checkins' });
        if (sd.recordedConcerns > 0) badges.push({ label: `${sd.recordedConcerns} concern${sd.recordedConcerns !== 1 ? 's' : ''}`, key: 'concerns', variant: 'warning' });
        if (sd.blockIncidents > 0) badges.push({ label: `${sd.blockIncidents} block${sd.blockIncidents !== 1 ? 's' : ''}`, key: 'blocks', variant: 'danger' });
        return badges;
    }

    get hasAuthorHistory() { return this.authorHistoryBadges.length > 0; }

    get reporterFilingBadges() {
        const rs = this._reporterStats;
        if (!rs) return [];
        const badges = [];
        if (rs.reportsLast90Days > 0) badges.push({ label: `${rs.reportsLast90Days} report${rs.reportsLast90Days !== 1 ? 's' : ''} (90 days)`, key: 'recent' });
        if (rs.reportsTotal > 0 && rs.reportsTotal !== rs.reportsLast90Days) badges.push({ label: `${rs.reportsTotal} total`, key: 'total' });
        return badges;
    }

    get hasReporterFilings() { return this.reporterFilingBadges.length > 0; }

    // ================================================================
    // Inline Form Getters
    // ================================================================

    get showInlineForm() { return !!this._activeForm; }

    get formTitle() {
        return this._activeForm === 'checkIn' ? 'Log Check-In' : 'Record Concern';
    }

    get formPlaceholder() {
        return this._activeForm === 'checkIn'
            ? 'Describe the check-in and what was discussed...'
            : 'Describe the concern and any relevant context...';
    }

    get formConfirmLabel() {
        return this._activeForm === 'checkIn' ? 'Log Check-In' : 'Record Concern';
    }

    get formNoteLength() { return (this._formNote || '').length; }

    get formCountClass() {
        const len = this.formNoteLength;
        if (len >= 1000) return 'character-count at-limit';
        if (len >= 900) return 'character-count near-limit';
        return 'character-count';
    }

    get isFormSubmitDisabled() { return this.formNoteLength < 10 || this._isProcessing; }

    // ================================================================
    // Lifecycle
    // ================================================================

    async connectedCallback() {
        if (this._initialized) return;
        this._initialized = true;
        this._recordId = this._getRecordIdFromUrl();

        if (!this._recordId) {
            this.hasError = true;
            this.errorMessage = 'No task ID found in the URL.';
            this.isLoading = false;
            return;
        }

        try { this._organizationId = await getOrganizationId(); } catch { /* non-fatal */ }
        await this._loadTask();
    }

    _getRecordIdFromUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            return params.get('recordId') || null;
        } catch {
            return null;
        }
    }

    // ================================================================
    // Data Loading
    // ================================================================

    async _loadTask() {
        this.isLoading = true;
        try {
            const bootstrap = await getTaskPageBootstrap({ taskId: this._recordId });
            this._task = bootstrap.task;
            this._category = bootstrap.category;
            this._status = bootstrap.status || 'New';
            this._enforcementLevel = bootstrap.enforcementLevel || 'None';

            if (this._task?.Status__c === 'Escalated' && !CATEGORY_LABELS[this._category]) {
                this._category = 'Escalated';
            }

            await this._loadReviewData();

            if (this._status === 'New') {
                try {
                    await claimTask({ taskId: this._recordId });
                    this._status = 'In_Progress';
                } catch { /* non-fatal */ }
            }

            this.isLoading = false;
        } catch (error) {
            this.hasError = true;
            this.errorMessage = error?.body?.message || error?.message || 'Failed to load task';
            this.isLoading = false;
        }
    }

    async _loadReviewData() {
        let panelData;
        const task = this._task;

        switch (this._category) {
            case 'Content_Report':
                panelData = await getContentReviewData({
                    recordId: task.Related_Record_Id__c,
                    recordType: task.Related_Record_Type__c,
                    taskId: task.Id
                });
                break;
            case 'Blocked_Contact':
                panelData = await getBlockReviewData({
                    blockedContactId: task.Related_Record_Id__c
                });
                if (panelData?.recordMissing) {
                    panelData = {
                        ...panelData,
                        blockedContactId: task.Subject_Contact__c,
                        blockedName: task.Subject_Contact__r?.Name || '',
                        blockerContactId: task.Secondary_Contact__c,
                        blockerName: task.Secondary_Contact__r?.Name || ''
                    };
                }
                break;
            case 'Support_Relationship_Approval':
                panelData = await getSupportReviewData({
                    supportRelationshipId: task.Related_Record_Id__c
                });
                break;
            case 'Organization_Approval':
                panelData = await getOrganizationReviewData({
                    accountId: task.Related_Record_Id__c,
                    taskId: task.Id
                });
                break;
            case 'Support_Person_Concern':
                panelData = await getSupportConcernData({ taskId: task.Id });
                break;
            case 'Escalated':
                panelData = await getEscalationDetail({ taskId: task.Id });
                break;
            case 'Bulk_Buy_Escalation':
                panelData = await getFollowUpReviewData({
                    followUpId: task.Related_Record_Id__c
                });
                break;
            default:
                panelData = {};
        }

        panelData = panelData ? JSON.parse(JSON.stringify(panelData)) : {};
        this._resolveImageUrls(panelData);

        const nhId = task.Neighbourhood__c;
        let subjectId = task.Subject_Contact__c
            || panelData.requesterContactId
            || panelData.authorContactId
            || panelData.blockerContactId
            || panelData.reportedUserId;
        const reporterId = task.Secondary_Contact__c
            || panelData.reporterContactId;

        const historyPromises = [];
        if (subjectId && nhId) {
            historyPromises.push(
                getSubjectHistory({
                    subjectContactId: subjectId,
                    neighbourhoodId: nhId,
                    excludeTaskId: this._recordId
                }).then(h => {
                    const contact = h.subject || {};
                    panelData.subjectData = {
                        name: contact.Name || '',
                        photoUrl: contact.Image_URL__c ? this._completeImageUrl(contact.Image_URL__c) : '',
                        pronouns: contact.Pronouns__c || '',
                        memberSince: contact.CreatedDate,
                        totalReports: h.totalReports || 0,
                        checkIns: h.checkIns || 0,
                        recordedConcerns: h.recordedConcerns || 0,
                        blockIncidents: h.blockIncidents || 0,
                        recentCases: (h.recentCases || []).map(c => ({
                            id: c.Id,
                            dateFormatted: this._formatAge(c.CreatedDate),
                            summary: c.Summary__c || (c.Category__c || '').replace(/_/g, ' '),
                            status: c.Status__c
                        }))
                    };
                }).catch(() => {})
            );
        }
        if (reporterId && nhId) {
            historyPromises.push(
                getReporterFilingStats({
                    reporterContactId: reporterId,
                    neighbourhoodId: nhId,
                    excludeTaskId: this._recordId
                }).then(stats => { this._reporterStats = stats; })
                  .catch(() => {})
            );
        }
        await Promise.all(historyPromises);

        this._panelData = { ...panelData, task };
    }

    // ================================================================
    // UI Handlers
    // ================================================================

    toggleReadMore() { this._showReadMore = !this._showReadMore; }

    handleOpenForm(event) {
        this._activeForm = event.currentTarget.dataset.form;
        this._formNote = '';
    }

    handleFormNoteChange(event) {
        this._formNote = event.target.value;
    }

    handleFormCancel() {
        this._activeForm = '';
        this._formNote = '';
    }

    handleImageClick(event) {
        const url = event.currentTarget.dataset.url;
        if (!url) return;
        if (this._isPdfUrl(url)) {
            window.open(url, '_blank', 'noopener,noreferrer');
            return;
        }
        const alt = event.currentTarget.dataset.alt || 'Attached image';
        this._openLightbox([{ url, alt }], 0);
    }

    handleVerificationDocClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10) || 0;
        const doc = this.orgVerificationDocs[index];
        if (doc?.url && this._isPdfDoc(doc)) {
            window.open(doc.url, '_blank', 'noopener,noreferrer');
            return;
        }
        const images = this.orgVerificationDocs
            .filter(d => !this._isPdfDoc(d))
            .map(d => ({ url: d.url, alt: d.label || 'Verification document' }));
        if (images.length === 0) return;
        const imageIndex = Math.min(index, images.length - 1);
        this._openLightbox(images, imageIndex);
    }

    handleDocumentLinkClick(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank', 'noopener,noreferrer');
        }
    }

    _isPdfUrl(url) {
        if (!url) return false;
        const u = url.toLowerCase();
        return u.includes('original_pdf') || u.includes('.pdf?') || u.endsWith('.pdf');
    }

    _isPdfDoc(doc) {
        if (!doc) return false;
        const ext = (doc.fileExtension || '').toLowerCase();
        return ext === 'pdf' || this._isPdfUrl(doc.url);
    }

    handleLightboxClose() {
        this.showLightbox = false;
        this.lightboxImages = [];
        this.lightboxStartIndex = 0;
    }

    _openLightbox(images, startIndex) {
        this.lightboxImages = images;
        this.lightboxStartIndex = startIndex;
        this.showLightbox = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const lb = this.template.querySelector('c-fimby-lightbox');
            if (lb) lb.open(startIndex);
        });
    }

    toggleSection(event) {
        const key = event.currentTarget.dataset.section;
        this._collapsedSections = {
            ...this._collapsedSections,
            [key]: !this._collapsedSections[key]
        };
    }

    isSectionCollapsed(key) {
        return !!this._collapsedSections[key];
    }

    // ================================================================
    // Action Handlers — Content Report
    // ================================================================

    async handleRepublish() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await republishContent({
                recordId: this._task.Related_Record_Id__c,
                recordType: this._task.Related_Record_Type__c,
                taskId: this._task.Id
            });
            await this._advanceStage('Resolved', null);
            this._showSuccess('Content republished');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    async handleKeepHidden() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await keepContentHidden({
                taskId: this._task.Id,
                reasonCode: '',
                statement: '',
                notes: ''
            });
            await this._advanceStage('Resolved', null);
            this._showSuccess('Content will remain hidden');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    // ================================================================
    // Action Handlers — Block Report
    // ================================================================

    async handleMarkReviewed() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await resolveTask({ taskId: this._task.Id, resolution: 'Dismissed', notes: '' });
            await this._advanceStage('Resolved', null);
            this._showSuccess('Block reviewed');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    // ================================================================
    // Action Handlers — Support Approval
    // ================================================================

    async handleApprove() {
        if (this._isProcessing || this.supportRepApproveDisabled) return;
        this._isProcessing = true;
        try {
            await approveSupportRelationship({
                supportRelationshipId: this._task.Related_Record_Id__c,
                taskId: this._task.Id
            });
            this._showSuccess('Support relationship approved');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    async handleDecline() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await declineSupportRelationship({
                supportRelationshipId: this._task.Related_Record_Id__c,
                reasonCode: '',
                statement: '',
                taskId: this._task.Id
            });
            this._showSuccess('Support relationship declined');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    get supportRepBlockedByOrg() {
        return this._panelData?.relationshipType === 'Community_Group_Rep'
            && !this._panelData?.orgVerified;
    }

    get orgName() { return this._panelData?.orgName || ''; }
    get orgTypeLabel() { return (this._panelData?.orgType || '').replace(/_/g, ' '); }
    get orgStreet() { return this._panelData?.billingStreet || ''; }
    get orgCity() { return this._panelData?.billingCity || ''; }
    get orgState() { return this._panelData?.billingState || ''; }
    get orgPostalCode() { return this._panelData?.billingPostalCode || ''; }
    get orgCountry() { return this._panelData?.billingCountry || ''; }
    get orgPhone() { return this._panelData?.orgPhone || ''; }
    get orgEmail() { return this._panelData?.orgEmail || ''; }
    get orgWebsite() { return this._panelData?.orgWebsite || ''; }
    get orgDescription() { return this._panelData?.orgDescription || ''; }
    get orgCharityUrl() { return this._panelData?.charityVerificationUrl || ''; }
    get orgCharityNumber() { return this._panelData?.charityRegistrationNumber || ''; }
    get orgIsCharity() { return this._panelData?.isRegisteredCharity === true; }
    get orgRequesterRole() { return this._panelData?.requesterOrgRole || ''; }
    get orgRepNotes() { return this._panelData?.repNotes || ''; }
    get hasOrgRepNotes() { return !!this.orgRepNotes; }
    get orgRequesterName() { return this._panelData?.requesterName || ''; }
    get orgRequesterContactId() { return this._panelData?.requesterContactId; }
    get orgVerificationDocs() { return this._panelData?.verificationDocs || []; }
    get orgVerificationDocsIndexed() {
        return this.orgVerificationDocs.map((doc, index) => ({
            ...doc,
            key: doc.url || String(index),
            index,
            isPdf: this._isPdfDoc(doc)
        }));
    }
    get authorizationIsPdf() {
        return this._isPdfUrl(this.supportAuthorizationImageUrl);
    }
    get hasOrgVerificationDocs() { return this.orgVerificationDocs.length > 0; }
    get orgHasPendingRep() { return this._panelData?.repPending === true; }

    async handleApproveOrganization() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await approveOrganization({
                accountId: this._task.Related_Record_Id__c,
                taskId: this._task.Id
            });
            this._showSuccess('Organization approved');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    async handleRejectOrganization() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await rejectOrganization({
                accountId: this._task.Related_Record_Id__c,
                reasonCode: '',
                statement: '',
                taskId: this._task.Id
            });
            this._showSuccess('Organization request declined');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    async handleApproveOrganizationAndRep() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await approveOrganizationAndRep({
                accountId: this._task.Related_Record_Id__c,
                orgTaskId: this._task.Id,
                supportRelationshipId: this._panelData?.pendingSupportRelationshipId,
                repTaskId: this._panelData?.pendingRepTaskId
            });
            this._showSuccess('Organization and representative approved');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    // ================================================================
    // Action Handlers — Support Concern
    // ================================================================

    async handleNoAction() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await resolveTask({ taskId: this._task.Id, resolution: 'Dismissed', notes: 'No action needed' });
            await this._advanceStage('Resolved', null);
            this._showSuccess('Marked as no action needed');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    // ================================================================
    // Action Handlers — Escalation
    // ================================================================

    async handleFollowUp() {
        await this._navigateToConversation(this._panelData?.escalatedToContactId);
    }

    async handleReopen() {
        if (this._isProcessing) return;
        if (this.isClosed && !this._showReopenConfirm) {
            this._showReopenConfirm = true;
            return;
        }
        await this._executeReopen();
    }

    handleReopenCancel() {
        this._showReopenConfirm = false;
    }

    async handleReopenConfirm() {
        if (this._isProcessing) return;
        await this._executeReopen();
    }

    async _executeReopen() {
        this._isProcessing = true;
        const wasClosed = this.isClosed;
        try {
            await reopenTask({ taskId: this._task.Id });
            this._showReopenConfirm = false;
            this._showSuccess('Task reopened');
            if (wasClosed) {
                this._status = 'In_Progress';
                await this._loadTask();
            } else {
                this._navigateBack();
            }
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    // ================================================================
    // Action Handlers — Bulk Buy
    // ================================================================

    async handleConfirmFlag() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await adminResolveFollowUp({
                followUpId: this._panelData?.followUpId,
                resolution: this._formNote || 'Confirmed after review',
                isConfirmed: true
            });
            await this._advanceStage('Resolved', null);
            this._showSuccess('Flag confirmed');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    async handleClearFlag() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await adminResolveFollowUp({
                followUpId: this._panelData?.followUpId,
                resolution: this._formNote || 'Cleared after review',
                isConfirmed: false
            });
            await this._advanceStage('Resolved', null);
            this._showSuccess('Flag cleared');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    handleViewBulkBuy() {
        if (this.bulkBuyUrl) window.location.href = this.bulkBuyUrl;
    }

    // ================================================================
    // Action Handlers — Shared (Contact, Log, Escalate)
    // ================================================================

    async handleContactPerson(event) {
        const contactId = event.currentTarget.dataset.contactId;
        if (!contactId) return;
        await this._navigateToConversation(contactId);
        if (this._status === 'In_Progress' && this._enforcementLevel === 'None') {
            try {
                await this._advanceStage('Awaiting_Info', null);
            } catch { /* non-fatal */ }
        }
    }

    async handleFormConfirm() {
        if (this._isProcessing || this.formNoteLength < 10) return;
        this._isProcessing = true;
        try {
            const subjectContactId = this._task?.Subject_Contact__c;
            if (this._activeForm === 'checkIn') {
                await issueCheckIn({
                    taskId: this._task.Id,
                    subjectContactId,
                    reasonCode: '',
                    messageBody: this._formNote
                });
                await this._advanceStage(null, 'Check_In');
                this._showSuccess('Check-in logged');
            } else {
                await recordConcern({
                    taskId: this._task.Id,
                    subjectContactId,
                    reasonCode: '',
                    statement: this._formNote
                });
                await this._advanceStage(null, 'Recorded_Concern');
                this._showSuccess('Concern recorded');
            }
            this._activeForm = '';
            this._formNote = '';
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    async handleEscalate() {
        if (this._isProcessing) return;
        this._isProcessing = true;
        try {
            await escalateTask({
                taskId: this._task.Id,
                reason: '',
                adminContactId: null
            });
            this._status = 'Escalated';
            this._enforcementLevel = 'Admin_Review';
            this._showSuccess('Task escalated');
            this._navigateBack();
        } catch (error) {
            this._showError('Action failed', error);
        } finally {
            this._isProcessing = false;
        }
    }

    handleViewOriginalPost() {
        const url = this._buildOriginalUrl();
        if (url) window.location.href = url;
    }

    // ================================================================
    // Navigation
    // ================================================================

    handleBack() { this._navigateBack(); }

    _navigateBack() {
        invalidateModeratorContext();
        let destination = '/moderator-dashboard';
        try {
            const params = new URLSearchParams(window.location.search);
            if (params.get('from') === 'archive') {
                destination = '/moderator-task-archive';
            }
        } catch {
            /* use default */
        }
        window.location.href = destination;
    }

    async _navigateToConversation(contactId) {
        if (!contactId) return;
        try {
            const conversationId = await getOrCreateModeratorConversation({ targetContactId: contactId });
            window.location.href = `/conversation?id=${conversationId}`;
        } catch (error) {
            this._showError('Failed to open conversation', error);
        }
    }

    // ================================================================
    // Stage Transitions
    // ================================================================

    async _advanceStage(newStatus, newEnforcement) {
        try {
            await updateTaskStage({
                taskId: this._recordId,
                newStatus: newStatus,
                enforcementLevel: newEnforcement
            });
            if (newStatus) this._status = newStatus;
            if (newEnforcement) this._enforcementLevel = newEnforcement;
        } catch { /* non-fatal — UI still updates locally */ }
    }

    // ================================================================
    // Helpers
    // ================================================================

    _buildOriginalUrl() {
        const task = this._task;
        if (!task?.Related_Record_Id__c || !task?.Related_Record_Type__c) return '';
        const type = task.Related_Record_Type__c;
        const id = task.Related_Record_Id__c;
        const routes = {
            'Needs_Offers__c': '/asks-offers/',
            'Story__c': '/sharedlife/',
            'Library_Item__c': '/library-item/',
            'Response__c': '/response-reply?recordId='
        };
        return (routes[type] || '/') + id;
    }

    _completeImageUrl(url) {
        if (!url) return '';
        if (url.endsWith('oid=') && this._organizationId) {
            return url + this._organizationId;
        }
        return url;
    }

    _resolveImageUrls(data) {
        if (!data) return;
        const photoKeys = [
            'authorPhotoUrl', 'reportedUserPhotoUrl', 'blockerPhotoUrl',
            'blockedPhotoUrl', 'submitterPhotoUrl', 'helperPhotoUrl',
            'subjectPhotoUrl', 'contactPhotoUrl', 'authorizationImageUrl',
            'screenshotUrl', 'reporterPhotoUrl', 'organiserPhotoUrl',
            'requesterPhotoUrl'
        ];
        for (const key of photoKeys) {
            if (data[key]) {
                data[key] = this._completeImageUrl(data[key]);
            }
        }
        if (data.subjectData?.photoUrl) {
            data.subjectData = {
                ...data.subjectData,
                photoUrl: this._completeImageUrl(data.subjectData.photoUrl)
            };
        }
        if (Array.isArray(data.imageUrls)) {
            data.imageUrls = data.imageUrls.map(u => this._completeImageUrl(u));
        }
        if (Array.isArray(data.verificationDocs)) {
            data.verificationDocs = data.verificationDocs.map(doc => ({
                ...doc,
                url: doc.url ? this._completeImageUrl(doc.url) : ''
            }));
        }
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
        } catch {
            return '';
        }
    }

    _formatClosedDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        if (Number.isNaN(d.getTime())) return '';
        return new Intl.DateTimeFormat(undefined, {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(d);
    }

    _formatDate(dateStr) {
        if (!dateStr) return '';
        try {
            return new Date(dateStr).toLocaleDateString('en-AU', {
                day: 'numeric', month: 'short', year: 'numeric'
            });
        } catch {
            return '';
        }
    }

    _showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Done', message, variant: 'success' }));
    }

    _showError(title, error) {
        const message = error?.body?.message || error?.message || 'Something went wrong';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }
}