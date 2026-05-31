import { LightningElement, api } from 'lwc';

export default class FimbyModeratorEscalationPanel extends LightningElement {
    @api panelData = {};

    get showFollowUp() { return !this.panelData?.isResolved; }
    get showReopen() { return !!this.panelData?.isResolved; }

    handleFollowUp() { this._dispatch('followUp'); }
    handleReopen() { this._dispatch('reopen'); }
    handleTransferOwnership() { this._dispatch('transferOwnership'); }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}