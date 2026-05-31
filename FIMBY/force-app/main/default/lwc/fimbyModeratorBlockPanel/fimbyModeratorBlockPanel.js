import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const NOTE_MAX = 500;

export default class FimbyModeratorBlockPanel extends LightningElement {
    @api panelData = {};
    @track _showOtherBlocks = false;
    @track _activeForm = null;
    @track _formNote = '';

    get checkInIconUrl() { return `${IMPACT_ICONS}/check-in.png`; }
    get dangerSignIconUrl() { return `${IMPACT_ICONS}/danger-sign.png`; }
    get lifesaverIconUrl() { return `${IMPACT_ICONS}/lifesaver.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }

    get blockerPhoto() {
        return this.panelData?.blockerPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get blockedPhoto() {
        return this.panelData?.blockedPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get hasOtherBlocks() {
        return (this.panelData?.otherBlockCount || 0) > 0;
    }

    get chevronIcon() {
        return this._showOtherBlocks ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get ariaExpanded() {
        return this._showOtherBlocks ? 'true' : 'false';
    }

    toggleOtherBlocks() {
        this._showOtherBlocks = !this._showOtherBlocks;
    }

    handleMarkReviewed() { this._dispatch('markReviewed'); }

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
        const subjectContactId = this.panelData?.task?.Subject_Contact__c;
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

    handleContactBlocker() {
        this._dispatch('contactBlocker', { contactId: this.panelData?.blockerContactId });
    }
    handleContactBlocked() {
        this._dispatch('contactBlocked', { contactId: this.panelData?.blockedContactId });
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