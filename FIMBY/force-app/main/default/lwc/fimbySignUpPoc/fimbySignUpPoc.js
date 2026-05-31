import { LightningElement, track } from 'lwc';
import ping from '@salesforce/apex/FimbySignUpPocController.ping';

export default class FimbySignUpPoc extends LightningElement {
    @track message = '';
    @track isSubmitting = false;
    @track result;
    @track errorText = '';

    handleChange(event) {
        this.message = event.target.value;
    }

    get hasResult() {
        return this.result != null;
    }

    get hasError() {
        return !!this.errorText;
    }

    async handlePing() {
        if (this.isSubmitting) {
            return;
        }
        this.isSubmitting = true;
        this.result = null;
        this.errorText = '';
        try {
            this.result = await ping({ message: this.message });
        } catch (e) {
            this.errorText =
                (e && e.body && e.body.message) ||
                (e && e.message) ||
                'Unknown error';
        } finally {
            this.isSubmitting = false;
        }
    }
}
