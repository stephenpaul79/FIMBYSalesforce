import { LightningElement, api, track } from 'lwc';

const WELCOME_MAX = 1000;

export default class FimbyModeratorWelcomePanel extends LightningElement {
    _panelData = {};
    @track _welcomeMessage = '';
    _messageInitialized = false;

    @api
    get panelData() { return this._panelData; }
    set panelData(value) {
        this._panelData = value || {};
        if (!this._messageInitialized && this._panelData.welcomeTemplate) {
            this._welcomeMessage = this._panelData.welcomeTemplate;
            this._messageInitialized = true;
        }
    }

    get contactPhoto() {
        return this._panelData?.contactPhotoUrl || '';
    }

    get onboardingBadgeClass() {
        return this._panelData?.onboardingComplete
            ? 'onboarding-badge complete'
            : 'onboarding-badge pending';
    }

    get onboardingStatusLabel() {
        return this._panelData?.onboardingComplete ? 'Complete' : 'Incomplete';
    }

    get welcomeMessage() {
        return this._welcomeMessage;
    }

    get messageLength() {
        return this._welcomeMessage.length;
    }

    get messageCountClass() {
        const len = this._welcomeMessage.length;
        if (len >= WELCOME_MAX) return 'character-count at-limit';
        if (len >= Math.floor(WELCOME_MAX * 0.9)) return 'character-count near-limit';
        return 'character-count';
    }

    handleMessageChange(event) {
        this._welcomeMessage = event.target.value;
        this._notifyDirty();
    }

    // An untouched prefilled template is not worth protecting; only edits are.
    _notifyDirty(forceClean) {
        const baseline = this._panelData?.welcomeTemplate || '';
        this.dispatchEvent(new CustomEvent('dirtychange', {
            detail: { isDirty: !forceClean && this._welcomeMessage !== baseline },
            bubbles: true,
            composed: true
        }));
    }

    handleSendWelcome() {
        this._notifyDirty(true);
        this._dispatch('sendWelcome', {
            contactId: this._panelData?.contactId,
            message: this._welcomeMessage
        });
    }

    handleMarkWelcomed() { this._notifyDirty(true); this._dispatch('markWelcomed'); }
    handleViewProfile() { this._dispatch('viewProfile', { contactId: this._panelData?.contactId }); }

    get firstName() {
        const name = (this._panelData?.contactName || '').trim();
        return name ? name.split(/\s+/)[0] : 'This neighbour';
    }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}
