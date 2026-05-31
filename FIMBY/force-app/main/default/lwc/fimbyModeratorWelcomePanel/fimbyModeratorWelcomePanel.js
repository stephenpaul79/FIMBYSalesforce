import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getVouchingContextForContact from '@salesforce/apex/FimbyVouchController.getVouchingContextForContact';
import overrideVouch from '@salesforce/apex/FimbyVouchController.overrideVouch';

const WELCOME_MAX = 1000;

const VOUCHING_LABELS = {
    'New':              'Settling in',
    'Vouch_Requested':  'Vouch Pending',
    'Vouched':          'Vouched',
    'Vouch_Declined':   'Vouch Declined'
};

export default class FimbyModeratorWelcomePanel extends LightningElement {
    _panelData = {};
    @track _welcomeMessage = '';
    _messageInitialized = false;

    @track _vouchingCtx = null;
    @track _vouchingLoading = false;
    @track _vouchingActionInFlight = false;
    @track _vouchingError = '';

    @api
    get panelData() { return this._panelData; }
    set panelData(value) {
        this._panelData = value || {};
        if (!this._messageInitialized && this._panelData.welcomeTemplate) {
            this._welcomeMessage = this._panelData.welcomeTemplate;
            this._messageInitialized = true;
        }
        if (this._panelData?.contactId) {
            this._loadVouchingContext(this._panelData.contactId);
        }
    }

    async _loadVouchingContext(contactId) {
        this._vouchingLoading = true;
        try {
            this._vouchingCtx = await getVouchingContextForContact({ contactId });
        } catch (e) {
            console.error('Vouching context load error', e);
            this._vouchingCtx = null;
        } finally {
            this._vouchingLoading = false;
        }
    }

    get vouchingStatusLabel() {
        const status = this._vouchingCtx?.vouchedStatus || 'New';
        return VOUCHING_LABELS[status] || VOUCHING_LABELS.New;
    }

    get vouchingBadgeClass() {
        const status = this._vouchingCtx?.vouchedStatus;
        if (status === 'Vouched') return 'onboarding-badge complete';
        if (status === 'Vouch_Requested') return 'onboarding-badge pending';
        return 'onboarding-badge pending';
    }

    get hasPendingVouchRequest() {
        return !!this._vouchingCtx?.pendingVouchRecordId;
    }

    get pendingVouchSummary() {
        const ctx = this._vouchingCtx;
        if (!ctx?.pendingVouchRecordId) return '';
        const name = ctx.pendingReferenceContactName || 'a neighbour';
        const org = ctx.pendingReferenceOrganizationName ? ` (${ctx.pendingReferenceOrganizationName})` : '';
        let dateStr = '';
        if (ctx.pendingRequestedDate) {
            try {
                dateStr = new Date(ctx.pendingRequestedDate).toLocaleDateString('en-US',
                    { month: 'short', day: 'numeric' });
            } catch (e) { /* ignore */ }
        }
        const datePart = dateStr ? ` on ${dateStr}` : '';
        return `Requested${datePart} from ${name}${org}`;
    }

    get canOverrideVouch() {
        const status = this._vouchingCtx?.vouchedStatus;
        return status !== 'Vouched';
    }

    get contactPhoto() {
        return this._panelData?.contactPhotoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
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
    }

    handleSendWelcome() {
        this._dispatch('sendWelcome', {
            contactId: this._panelData?.contactId,
            message: this._welcomeMessage
        });
    }

    handleMarkWelcomed() { this._dispatch('markWelcomed'); }
    handleViewProfile() { this._dispatch('viewProfile', { contactId: this._panelData?.contactId }); }

    async handleOverrideVouchClick() {
        if (this._vouchingActionInFlight) return;
        const contactId = this._panelData?.contactId;
        if (!contactId) return;
        if (!confirm('Mark this neighbour as Vouched directly? They will be able to borrow from the lending library immediately.')) {
            return;
        }
        this._vouchingActionInFlight = true;
        this._vouchingError = '';
        try {
            await overrideVouch({ vouchedContactId: contactId });
            await this._loadVouchingContext(contactId);
        } catch (error) {
            console.error('Override vouch error', error);
            this._vouchingError = error?.body?.message || error?.message
                || 'Could not override-vouch. Please try again.';
        } finally {
            this._vouchingActionInFlight = false;
        }
    }

    get vouchingError() { return this._vouchingError; }

    _dispatch(action, payload) {
        this.dispatchEvent(new CustomEvent('modalaction', {
            detail: { action, payload },
            bubbles: true,
            composed: true
        }));
    }
}