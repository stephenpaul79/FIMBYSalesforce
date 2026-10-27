import { LightningElement, api } from 'lwc';

const STATUS_LABELS = {
    Approved: 'was vouched for',
    Declined: 'was declined',
    Withdrawn: 'was withdrawn',
    Revoked: 'was revoked'
};

export default class FimbyModeratorVouchPanel extends LightningElement {
    @api panelData = {};

    get contactPhoto() {
        return this.panelData?.contactPhotoUrl || '';
    }

    get firstName() {
        const first = (this.panelData?.firstName || '').trim();
        if (first) return first;
        const name = (this.panelData?.contactName || '').trim();
        return name ? name.split(/\s+/)[0] : 'This neighbour';
    }

    get askedWho() {
        const org = this.panelData?.referenceOrganizationName;
        const name = this.panelData?.referenceName || 'a neighbour';
        return org ? `${name} (${org})` : name;
    }

    get waitingSummary() {
        const days = this.panelData?.daysWaiting;
        if (days === null || days === undefined) return `Asked ${this.askedWho} to vouch`;
        if (days === 0) return `Asked ${this.askedWho} to vouch today`;
        return `Asked ${this.askedWho} to vouch ${days} day${days === 1 ? '' : 's'} ago`;
    }

    get isNoLongerPending() {
        return this.panelData?.isStillPending === false;
    }

    get resolvedMessage() {
        const outcome = STATUS_LABELS[this.panelData?.status] || 'is no longer waiting';
        return `This request ${outcome} since the task opened. You can close this task.`;
    }

    get hasReference() {
        return !!this.panelData?.referenceContactId;
    }

    get messageNeighbourLabel() {
        return `Message ${this.firstName}`;
    }

    get nudgeLabel() {
        const name = (this.panelData?.referenceName || '').trim();
        return name ? `Message ${name.split(/\s+/)[0]}` : 'Message the voucher';
    }

    handleVouched() {
        this._dispatch('resolveVouched');
    }

    handleMessageNeighbour() {
        this._dispatch('contactSubject', { contactId: this.panelData?.contactId });
    }

    handleNudgeReference() {
        this._dispatch('contactSubject', { contactId: this.panelData?.referenceContactId });
    }

    handleNoAction() { this._dispatch('noAction'); }
    handleViewProfile() { this._dispatch('viewProfile', { contactId: this.panelData?.contactId }); }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}
