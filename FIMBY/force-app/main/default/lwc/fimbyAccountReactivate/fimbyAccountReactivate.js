import { LightningElement, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import requestReactivationLink from '@salesforce/apex/FimbyReactivationController.requestReactivationLink';

const STATE_FORM = 'form';
const STATE_SENT = 'sent';

export default class FimbyAccountReactivate extends LightningElement {
    @track username = '';
    @track isSubmitting = false;
    @track state = STATE_FORM;

    get formIconUrl() { return `${IMPACT_ICONS}/key.png`; }
    get sentIconUrl() { return `${IMPACT_ICONS}/email.png`; }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        const pre = params.get('username');
        if (pre) {
            this.username = pre;
        }
    }

    get showForm() {
        return this.state === STATE_FORM;
    }

    get showSent() {
        return this.state === STATE_SENT;
    }

    handleUsernameChange(event) {
        this.username = event.target.value;
    }

    async handleSubmit(event) {
        event.preventDefault();
        if (this.isSubmitting) return;
        this.isSubmitting = true;
        try {
            await requestReactivationLink({ username: this.username });
            this.state = STATE_SENT;
        } catch {
            this.state = STATE_SENT;
        } finally {
            this.isSubmitting = false;
        }
    }

    handleTryAgain() {
        this.username = '';
        this.state = STATE_FORM;
    }
}
