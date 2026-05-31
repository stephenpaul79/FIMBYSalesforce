import { LightningElement, api } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const TYPE_BADGE_MAP = {
    Bug: 'type-badge badge-bug',
    Enhancement: 'type-badge badge-enhancement',
    General: 'type-badge badge-general',
    Content_Report: 'type-badge badge-content-report'
};

export default class FimbyModeratorFeedbackPanel extends LightningElement {
    @api panelData = {};

    get submitterPhoto() {
        return this.panelData?.submitterPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get typeBadgeClass() {
        return TYPE_BADGE_MAP[this.panelData?.type] || 'type-badge badge-general';
    }

    get linkIconUrl() { return `${IMPACT_ICONS}/sign.png`; }
    get lifesaverIconUrl() { return `${IMPACT_ICONS}/lifesaver.png`; }

    handleScreenshotClick() {
        if (this.panelData?.screenshotUrl) {
            window.open(this.panelData.screenshotUrl, '_blank');
        }
    }

    handleTriageTraining() {
        this._dispatch('triageTraining');
    }

    handleTriageEnhancement() {
        this._dispatch('triageEnhancement');
    }

    handleTriageNotActionable() {
        this._dispatch('triageNotActionable');
    }

    handleRespondToUser() {
        this._dispatch('respondToUser', { contactId: this.panelData?.submitterContactId });
    }

    handleEscalate() {
        this._dispatch('escalate');
    }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}