import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const STATUS_CLASS_MAP = {
    Pending:    'status-badge warning',
    Overdue:    'status-badge error',
    Completed:  'status-badge success',
    Escalated:  'status-badge error'
};

const NOTE_MAX = 500;

export default class FimbyModeratorFollowUpPanel extends LightningElement {
    @api panelData = {};
    @track _activeForm = null;
    @track _formNote = '';

    get checkInIconUrl() { return `${IMPACT_ICONS}/check-in.png`; }
    get dangerSignIconUrl() { return `${IMPACT_ICONS}/danger-sign.png`; }
    get lifesaverIconUrl() { return `${IMPACT_ICONS}/lifesaver.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }

    get reportedUserPhoto() {
        return this.panelData?.reportedUserPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get hasTimeline() {
        return this.panelData?.followUpTimeline?.length > 0;
    }

    get noTimeline() {
        return !this.hasTimeline;
    }

    get timelineItems() {
        return (this.panelData?.followUpTimeline || []).map((entry, idx) => ({
            ...entry,
            _key: `timeline-${idx}`,
            _statusClass: STATUS_CLASS_MAP[entry.status] || 'status-badge',
            _formattedDate: this._formatDate(entry.date)
        }));
    }

    _formatDate(dateStr) {
        if (!dateStr) return '';
        try {
            const d = new Date(dateStr);
            return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' });
        } catch {
            return dateStr;
        }
    }

    get isFormActive() { return this._activeForm != null; }
    get formTitle() {
        return this._activeForm === 'checkIn' ? 'Send Check-In' : 'Record Concern';
    }
    get formPlaceholder() {
        return this._activeForm === 'checkIn'
            ? 'Add a note about this check-in\u2026'
            : 'Describe the concern\u2026';
    }
    get formNote() { return this._formNote; }
    get noteLength() { return this._formNote.length; }
    get noteCountClass() {
        const len = this._formNote.length;
        if (len >= NOTE_MAX) return 'character-count at-limit';
        if (len >= Math.floor(NOTE_MAX * 0.9)) return 'character-count near-limit';
        return 'character-count';
    }
    get formConfirmLabel() {
        return this._activeForm === 'checkIn' ? 'Confirm Check-In' : 'Confirm Concern';
    }
    get formConfirmClass() {
        return this._activeForm === 'checkIn'
            ? 'btn-action btn-escalation-1'
            : 'btn-action btn-escalation-2';
    }

    handleCheckIn() { this._activeForm = 'checkIn'; this._formNote = ''; }
    handleRecordConcern() { this._activeForm = 'recordConcern'; this._formNote = ''; }
    handleFormNoteChange(event) { this._formNote = event.target.value; }
    handleFormCancel() { this._activeForm = null; this._formNote = ''; }

    handleFormConfirm() {
        const subjectContactId = this.panelData?.reportedUserId;
        if (this._activeForm === 'checkIn') {
            this._dispatch('checkIn', {
                subjectContactId,
                reasonCode: 'moderator_action',
                messageBody: this._formNote
            });
        } else {
            this._dispatch('recordConcern', {
                subjectContactId,
                reasonCode: 'moderator_action',
                statement: this._formNote
            });
        }
        this._activeForm = null;
        this._formNote = '';
    }

    handleContactReported() {
        this._dispatch('contactReported', { contactId: this.panelData?.reportedUserId });
    }
    handleContactOrganiser() {
        this._dispatch('contactOrganiser', { contactId: this.panelData?.organiserContactId });
    }
    handleViewBulkBuy() {
        const id = this.panelData?.bulkBuyId;
        this._dispatch('viewBulkBuy', { url: id ? `/asks-offers/${id}` : '' });
    }
    handleEscalate() { this._dispatch('escalate'); }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}