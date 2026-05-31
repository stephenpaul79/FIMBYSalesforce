import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getCurrentTosVersion from '@salesforce/apex/FimbyTosController.getCurrentTosVersion';
import getCurrentTosEffectiveDate from '@salesforce/apex/FimbyTosController.getCurrentTosEffectiveDate';
import acceptTos from '@salesforce/apex/FimbyTosController.acceptTos';

const TOS_URL = 'https://fimby.com/terms-of-service';
const PRIVACY_URL = 'https://fimby.com/privacy-policy';
const GUIDELINES_URL = '/community-guidelines';

export default class FimbyTosFlowScreen extends LightningElement {
    @api acceptanceCompleted = false;
    @api source = 'Login Flow';

    linkTapped = false;
    checkboxChecked = false;
    submitting = false;
    errorMessage = '';
    tosVersion;
    effectiveDate;

    @wire(getCurrentTosVersion)
    wiredTosVersion({ data }) {
        if (data) this.tosVersion = data;
    }

    @wire(getCurrentTosEffectiveDate)
    wiredTosEffectiveDate({ data }) {
        if (data) this.effectiveDate = data;
    }

    get tosUrl() {
        return TOS_URL;
    }

    get privacyUrl() {
        return PRIVACY_URL;
    }

    get guidelinesUrl() {
        return GUIDELINES_URL;
    }

    get effectiveDateLabel() {
        if (!this.effectiveDate) return '';
        try {
            return new Date(this.effectiveDate).toLocaleDateString(undefined, {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
        } catch (e) {
            return this.effectiveDate;
        }
    }

    get checkboxDisabled() {
        return !this.linkTapped;
    }

    get agreeDisabled() {
        return !this.linkTapped || !this.checkboxChecked || this.submitting || this.acceptanceCompleted;
    }

    get hintMessage() {
        if (this.acceptanceCompleted) {
            return 'Thanks — you can tap Continue to enter FIMBY.';
        }
        if (!this.linkTapped) {
            return 'Tap the Terms of Service link above first, then come back to check the box.';
        }
        if (!this.checkboxChecked) {
            return 'Check the box once you have read the Terms of Service.';
        }
        return '';
    }

    handleLinkTap() {
        this.linkTapped = true;
    }

    handleCheckboxChange(event) {
        this.checkboxChecked = event.target.checked;
    }

    async handleAgree() {
        if (this.agreeDisabled) return;
        this.submitting = true;
        this.errorMessage = '';
        try {
            await acceptTos({
                version: this.tosVersion,
                source: this.source
            });
            this.acceptanceCompleted = true;
            this.dispatchEvent(
                new FlowAttributeChangeEvent('acceptanceCompleted', true)
            );
            this.dispatchEvent(
                new CustomEvent('complete', {
                    detail: { version: this.tosVersion },
                    bubbles: true,
                    composed: true
                })
            );
        } catch (error) {
            this.errorMessage =
                error?.body?.message ||
                'We couldn’t record your acceptance. Please try again or contact help@fimby.com.';
        } finally {
            this.submitting = false;
        }
    }
}
