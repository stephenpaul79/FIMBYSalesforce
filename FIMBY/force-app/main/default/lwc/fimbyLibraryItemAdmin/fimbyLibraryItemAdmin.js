import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { formatLocalDate, formatShortDate } from 'c/fimbyDateUtils';
import { navigate } from 'c/fimbyNavigation';
import { avatarImageUrl } from 'c/fimbyImageUrl';

export default class FimbyLibraryItemAdmin extends NavigationMixin(LightningElement) {
    @api recordId;
    @api adminData;
    @api adminDataLoaded = false;

    @track showLendingRequests = true;
    @track showLendingHistory = false;

    get isLoading() {
        return !this.adminDataLoaded;
    }

    get lendingIconUrl() { return `${IMPACT_ICONS}/borrow.png`; }
    get historyIconUrl() { return `${IMPACT_ICONS}/plannersm.png`; }
    get waitlistIconUrl() { return `${IMPACT_ICONS}/reply.png`; }
    get noProfilePhotoUrl() { return `${IMPACT_ICONS}/NoProfilePhoto.png`; }
    get messageIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get checkIconUrl() { return `${IMPACT_ICONS}/complete.png`; }
    get reviewIconUrl() { return `${IMPACT_ICONS}/Magnify.png`; }
    get removeIconUrl() { return `${IMPACT_ICONS}/trash.png`; }
    get returnIconUrl() { return `${IMPACT_ICONS}/transfer.png`; }
    get extensionIconUrl() { return `${IMPACT_ICONS}/plannersm.png`; }

    // ── Current Loan ──────────────────────────────────────────────

    get hasCurrentLoan() {
        return !!this.adminData?.currentLoan;
    }

    get currentLoan() {
        const loan = this.adminData?.currentLoan;
        if (!loan) return null;
        const phase = loan.loanStatusDerived || 'onLoan';
        const convId = loan.conversationId;
        return {
            ...loan,
            borrowerAvatar: avatarImageUrl(loan.borrowerAvatar),
            isOverdue: phase === 'overdue',
            isExtensionRequested: phase === 'extensionRequested',
            isReturnPending: phase === 'returnPending',
            isOnLoan: phase === 'onLoan',
            showMessageBorrower: !!convId,
            messageUrl: convId ? `/conversation?id=${convId}` : '',
            loanId: loan.id
        };
    }

    get currentLoanBorrowerName() {
        return this.currentLoan?.borrowerName || 'Unknown';
    }

    get currentLoanDueDate() {
        const d = this.currentLoan?.dueDate;
        return d ? formatLocalDate(d) : 'No due date';
    }

    get loanDueDateClass() {
        return this.currentLoan?.isOverdue ? 'loan-due-date loan-overdue' : 'loan-due-date';
    }

    get currentLoanPhaseLabel() {
        const loan = this.currentLoan;
        if (!loan) return '';
        if (loan.isExtensionRequested) return 'Extension Requested';
        if (loan.isReturnPending) return 'Return Pending - Verify';
        if (loan.isOverdue) return 'Overdue';
        return '';
    }

    get currentLoanPillClass() {
        const loan = this.currentLoan;
        if (!loan) return '';
        if (loan.isExtensionRequested) return 'status-pill status-pill-warning';
        if (loan.isReturnPending) return 'status-pill status-pill-success';
        if (loan.isOverdue) return 'status-pill status-pill-danger';
        return '';
    }

    get showCurrentLoanPill() {
        const loan = this.currentLoan;
        return loan && (loan.isExtensionRequested || loan.isReturnPending || loan.isOverdue);
    }

    get loanSectionStripClass() {
        const loan = this.currentLoan;
        if (!loan) return 'admin-section';
        if (loan.isOverdue) return 'admin-section cta-strip-urgent';
        if (loan.isExtensionRequested || loan.isReturnPending) return 'admin-section cta-strip-strong';
        return 'admin-section cta-strip-subtle';
    }

    // ── Lending Requests (Waitlist) ────────────────────────────────

    get lendingRequests() {
        return this.adminData?.lendingRequests || [];
    }

    get hasLendingRequests() {
        return this.lendingRequests.length > 0;
    }

    get lendingRequestCount() {
        return this.lendingRequests.length;
    }

    _formatShortDate(val) {
        return formatShortDate(val);
    }

    get processedRequests() {
        return this.lendingRequests.map(req => {
            const isPendingApproval = req.status === 'Pending Approval';
            const isApproved = req.status === 'Approved';
            const isRequestingConfirmation = req.status === 'Requesting Confirmation';
            const isWaitlisted = req.status === 'Waitlisted';

            const parts = [];
            if (isWaitlisted && req.waitlistPosition) {
                parts.push(`#${req.waitlistPosition} in line`);
            }
            if (req.daysNeeded) {
                const n = Number(req.daysNeeded);
                parts.push(`Wants ${n} ${n === 1 ? 'day' : 'days'}`);
            }
            if (req.requestedDate && !isApproved) {
                // Requested_Date__c = borrower’s preferred start/pickup day, not “date submitted”
                parts.push(`Starting on ${this._formatShortDate(req.requestedDate)}`);
            }
            if (isWaitlisted && req.estimatedAvailableDate) {
                parts.push(`Est. available ${this._formatShortDate(req.estimatedAvailableDate)}`);
            }

            const rowStripClass = 'request-row';

            return {
                ...req,
                requesterAvatar: avatarImageUrl(req.requesterAvatar),
                formattedMeta: parts.join(' · '),
                isReviewAction: isPendingApproval,
                showRemove: !isPendingApproval && !isApproved,
                showAwaitingPill: isRequestingConfirmation,
                showCoordinatePickup: isApproved,
                showRecordHandoff: isApproved,
                showApprovedPill: isApproved,
                displayStatus: isApproved ? 'Approved - Pickup Pending' : req.status,
                conversationUrl: req.conversationId ? `/conversation?id=${req.conversationId}` : '',
                rowStripClass
            };
        });
    }

    get requestsSectionLabel() {
        const count = this.lendingRequestCount;
        return `Lending Requests (${count})`;
    }

    get requestsChevronClass() {
        return this.showLendingRequests ? 'section-chevron expanded' : 'section-chevron';
    }

    toggleLendingRequests() {
        this.showLendingRequests = !this.showLendingRequests;
    }

    // ── Lending History ────────────────────────────────────────────

    get lendingHistory() {
        return this.adminData?.lendingHistory || [];
    }

    get hasLendingHistory() {
        return this.lendingHistory.length > 0;
    }

    get processedHistory() {
        return this.lendingHistory.map(hist => ({
            ...hist,
            borrowerAvatar: avatarImageUrl(hist.borrowerAvatar),
            displayStartDate: formatLocalDate(hist.startDate),
            displayEndDate: hist.endDate ? formatLocalDate(hist.endDate) : 'Ongoing',
            hasConversation: !!hist.conversationId,
            conversationUrl: hist.conversationId ? `/conversation?id=${hist.conversationId}` : ''
        }));
    }

    get historySectionLabel() {
        return `Lending History (${this.lendingHistory.length})`;
    }

    get historyChevronClass() {
        return this.showLendingHistory ? 'section-chevron expanded' : 'section-chevron';
    }

    toggleLendingHistory() {
        this.showLendingHistory = !this.showLendingHistory;
    }

    // ── Action Handlers ────────────────────────────────────────────

    handleNavigate(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            navigate(this, url);
        }
    }

    handleVerifyReturn() {
        this.dispatchEvent(new CustomEvent('verifyreturn', {
            detail: { loanId: this.currentLoan?.loanId },
            bubbles: true,
            composed: true
        }));
    }

    handleReview(event) {
        const requestId = event.currentTarget.dataset.requestId;
        this.dispatchEvent(new CustomEvent('reviewrequest', {
            detail: { requestId },
            bubbles: true,
            composed: true
        }));
    }

    handleRemove(event) {
        const requestId = event.currentTarget.dataset.requestId;
        const req = this.lendingRequests.find(r => r.id === requestId);
        this.dispatchEvent(new CustomEvent('removerequest', {
            detail: { requestId, requesterName: req?.requesterName || '' },
            bubbles: true,
            composed: true
        }));
    }

    handleRecordHandoff(event) {
        const requestId = event.currentTarget.dataset.requestId;
        this.dispatchEvent(new CustomEvent('confirmpickup', {
            detail: { requestId },
            bubbles: true,
            composed: true
        }));
    }

    handleApproveExtension() {
        this.dispatchEvent(new CustomEvent('approveextension', {
            detail: { loanId: this.currentLoan?.loanId },
            bubbles: true,
            composed: true
        }));
    }
}