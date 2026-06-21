import { LightningElement, api, track } from 'lwc';
export default class FimbyEmergencyAlert extends LightningElement {
    @api alertMessage = 'Emergency alert from your community';
    @track _alertMessageOverride = '';
    @track showAlert = false;

    get displayAlertMessage() {
        return this._alertMessageOverride || this.alertMessage;
    }

    @api show() { this.showAlert = true; }
    @api hide() { this.showAlert = false; }

    connectedCallback() {
        // Show alert based on emergency conditions
        this.checkEmergencyStatus();
    }

    checkEmergencyStatus() {
        // Mock emergency check
        if (Math.random() > 0.9) {
            this._alertMessageOverride = 'Severe weather warning in your area';
            this.show();
        }
    }

    handleDismiss() {
        this.hide();
    }
}
