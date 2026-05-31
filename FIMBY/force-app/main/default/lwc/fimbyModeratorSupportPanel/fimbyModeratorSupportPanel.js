import { LightningElement, api } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyModeratorSupportPanel extends LightningElement {
    @api panelData = {};
    @api mode = 'approval';

    get isApprovalMode() { return this.mode === 'approval'; }
    get isConcernMode() { return this.mode === 'concern'; }

    get helperPhoto() {
        return this.panelData?.helperPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get subjectPhoto() {
        return this.panelData?.subjectPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get warningIconUrl() { return `${IMPACT_ICONS}/warning.png`; }
    get lifesaverIconUrl() { return `${IMPACT_ICONS}/lifesaver.png`; }

    get hasRecentActivity() {
        return this.panelData?.helperRecentActivity?.length > 0;
    }

    handleAuthImageClick() {
        if (this.panelData?.authorizationImageUrl) {
            window.open(this.panelData.authorizationImageUrl, '_blank');
        }
    }

    /* Approval mode actions */
    handleApprove() { this._dispatch('approve'); }
    handleDecline() { this._dispatch('decline', { reasonCode: 'moderator_declined' }); }
    handleRequestMoreInfo() { this._dispatch('requestMoreInfo', { contactId: this.panelData?.helperContactId }); }
    handleContactSubject() { this._dispatch('contactSubject', { contactId: this.panelData?.subjectContactId }); }
    handleEscalate() { this._dispatch('escalate'); }

    /* Concern mode actions */
    handleEscalateUrgent() { this._dispatch('escalateUrgent'); }
    handleWelfareCheck() { this._dispatch('welfareCheck', { subjectContactId: this.panelData?.subjectContactId }); }
    handleContactHelper() { this._dispatch('contactHelper', { contactId: this.panelData?.helperContactId }); }
    handleNoAction() { this._dispatch('noAction'); }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}