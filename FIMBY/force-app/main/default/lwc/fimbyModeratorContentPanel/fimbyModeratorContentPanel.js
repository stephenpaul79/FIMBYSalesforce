import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const TRUNCATE_LENGTH = 300;

const NOTE_MAX = 500;

export default class FimbyModeratorContentPanel extends LightningElement {
    @api panelData = {};
    @track _isExpanded = false;
    @track _activeForm = null;
    @track _formNote = '';

    get checkInIconUrl() { return `${IMPACT_ICONS}/check-in.png`; }
    get dangerSignIconUrl() { return `${IMPACT_ICONS}/danger-sign.png`; }
    get lifesaverIconUrl() { return `${IMPACT_ICONS}/lifesaver.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }

    get authorPhoto() {
        return this.panelData?.authorPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get hasImages() {
        return this.panelData?.imageUrls?.length > 0;
    }

    get isBodyLong() {
        return (this.panelData?.contentBody?.length || 0) > TRUNCATE_LENGTH;
    }

    get displayBody() {
        const body = this.panelData?.contentBody || '';
        if (this.isBodyLong && !this._isExpanded) {
            return body.substring(0, TRUNCATE_LENGTH) + '\u2026';
        }
        return body;
    }

    get readMoreLabel() {
        return this._isExpanded ? 'Read Less' : 'Read More';
    }

    toggleReadMore() {
        this._isExpanded = !this._isExpanded;
    }

    handleImageClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this._dispatch('viewImage', { index, imageUrls: this.panelData.imageUrls });
    }

    handleRepublish() {
        this._dispatch('republish', {
            recordId: this.panelData?.recordId,
            recordType: this.panelData?.recordType
        });
    }
    handleKeepHidden() { this._dispatch('keepHidden'); }

    get isFormActive() { return this._activeForm != null; }
    get isCheckInForm() { return this._activeForm === 'checkIn'; }
    get isRecordConcernForm() { return this._activeForm === 'recordConcern'; }
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
        const subjectContactId = this.panelData?.authorContactId;
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
    handleContactAuthor() {
        this._dispatch('contactAuthor', { contactId: this.panelData?.authorContactId });
    }
    handleContactReporter() {
        this._dispatch('contactReporter', { contactId: this.panelData?.reporterContactId });
    }
    handleEscalate() { this._dispatch('escalate'); }
    handleViewOriginal() {
        this._dispatch('viewOriginal', { url: this._buildOriginalUrl() });
    }

    _buildOriginalUrl() {
        const type = this.panelData?.recordType;
        const id = this.panelData?.recordId;
        if (!type || !id) return '';
        const routes = {
            'Needs_Offers__c': '/asks-offers/',
            'Story__c': '/sharedlife/',
            'Library_Item__c': '/library-item/',
            'Response__c': '/response-reply?recordId='
        };
        return (routes[type] || '/') + id;
    }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}