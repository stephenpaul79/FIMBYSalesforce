import { LightningElement, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import consumeReactivationToken from '@salesforce/apex/FimbyReactivationController.consumeReactivationToken';

const STATE_PROCESSING = 'processing';
const STATE_RESTORED = 'restored';
const STATE_EXPIRED = 'expired';
const STATE_USED = 'used';
const STATE_NOT_FOUND = 'not_found';
const STATE_PAST_GRACE = 'past_grace';

export default class FimbyReactivationLanding extends LightningElement {
    @track state = STATE_PROCESSING;

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        const token = params.get('token');
        if (!token) {
            this.state = STATE_NOT_FOUND;
            return;
        }
        this.consume(token);
    }

    async consume(token) {
        try {
            const resp = await consumeReactivationToken({ token });
            const status = (resp && resp.status) || STATE_NOT_FOUND;
            if ([STATE_RESTORED, STATE_EXPIRED, STATE_USED, STATE_NOT_FOUND, STATE_PAST_GRACE].includes(status)) {
                this.state = status;
            } else {
                this.state = STATE_NOT_FOUND;
            }
        } catch (e) {
            this.state = STATE_NOT_FOUND;
        }
    }

    get isProcessing() { return this.state === STATE_PROCESSING; }
    get isRestored() { return this.state === STATE_RESTORED; }
    get isExpiredOrUsed() {
        return this.state === STATE_EXPIRED || this.state === STATE_USED;
    }
    get isPastGrace() { return this.state === STATE_PAST_GRACE; }
    get isNotFound() { return this.state === STATE_NOT_FOUND; }

    get restoredIconUrl()      { return `${IMPACT_ICONS}/NeighborhoodActive.png`; }
    get warningIconUrl()       { return `${IMPACT_ICONS}/warning.png`; }
    get pastGraceIconUrl()     { return `${IMPACT_ICONS}/sad.png`; }

    get expiredMessage() {
        return this.state === STATE_USED
            ? 'This restore link has already been used. If you didn\u2019t restore your account, request a new link below.'
            : 'This restore link has expired.';
    }
}
