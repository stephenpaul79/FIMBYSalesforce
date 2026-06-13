import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate } from 'c/fimbyNavigation';
import submitContentReport from '@salesforce/apex/FimbyContentReportController.submitContentReport';
import checkExistingReport from '@salesforce/apex/FimbyContentReportController.checkExistingReport';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

/**
 * Confidential content report modal. Embedded by detail/card LWCs to surface
 * the "Report" affordance. The Apex controller writes to Moderator_Task__c
 * via FimbyModeratorTaskService — see /community-guidelines for the public
 * promise this UI implements (24h SLA, plain-English reasons).
 */
export default class FimbyReportContent extends NavigationMixin(LightningElement) {
    @api contentId = '';
    @api contentType = ''; // 'Story', 'Need_Offer', 'Library_Item', 'Response', etc.
    @track showModal = false;
    @track selectedReason = '';
    @track additionalInfo = '';
    @track isSubmitting = false;
    @track errorMessage = '';
    @track showConfirmation = false;
    @track showAlreadyReported = false;
    @track isCheckingExisting = false;

    @track actingAsContact = null;
    @track hasMultipleIdentities = false;

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading acting-as contact:', error);
        }
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this.hasMultipleIdentities = data.length > 0;
        } else if (error) {
            console.error('Error loading identities:', error);
            this.hasMultipleIdentities = false;
        }
    }

    get postingAsDisplayName() {
        return this.actingAsContact?.postingAsDisplayName
            || this.actingAsContact?.actingAsContactName
            || this.actingAsContact?.contactName
            || '';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.postingAsDisplayName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get alreadyReportedMessage() {
        return 'We\u2019ve already received your report on this. A moderator is reviewing it \u2014 no need to flag it again.';
    }

    get alreadyReportedNote() {
        return 'If something urgent comes up, email safety@fimby.ca.';
    }

    get reportReasons() {
        return [
            { id: 'inappropriate', label: 'Inappropriate content' },
            { id: 'spam', label: 'Spam or misleading' },
            { id: 'harassment', label: 'Harassment or bullying' },
            { id: 'privacy', label: 'Privacy violation' },
            { id: 'safety', label: 'Safety concern' },
            { id: 'other', label: 'Other' }
        ];
    }

    get isSubmitDisabled() {
        return !this.selectedReason || this.isSubmitting || this.isCheckingExisting || this.showAlreadyReported;
    }

    @api
    async show(contentId, contentType) {
        if (contentId) this.contentId = contentId;
        if (contentType) this.contentType = contentType;
        this.showModal = true;
        this.resetForm();
        await this.loadExistingReportState();
    }

    @api
    hide() {
        this.showModal = false;
        this.resetForm();
    }

    resetForm() {
        this.selectedReason = '';
        this.additionalInfo = '';
        this.errorMessage = '';
        this.isSubmitting = false;
        this.isCheckingExisting = false;
        this.showConfirmation = false;
        this.showAlreadyReported = false;
    }

    async loadExistingReportState() {
        if (!this.contentId || !this.contentType) {
            return;
        }
        this.isCheckingExisting = true;
        try {
            const result = await checkExistingReport({
                contentId: this.contentId,
                contentType: this.contentType
            });
            if (result?.alreadyReported) {
                this.showAlreadyReported = true;
            }
        } catch (error) {
            console.error('Error checking existing report:', error);
        } finally {
            this.isCheckingExisting = false;
        }
    }

    handleReasonChange(event) {
        this.selectedReason = event.target.value;
    }

    handleInfoChange(event) {
        this.additionalInfo = event.target.value;
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) this.hide();
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.hide();
    }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    handleCancel() {
        this.hide();
    }

    async handleSubmitReport() {
        if (this.isSubmitDisabled) return;
        this.isSubmitting = true;
        this.errorMessage = '';

        const reportData = {
            contentId: this.contentId,
            contentType: this.contentType,
            reason: this.selectedReason,
            additionalInfo: this.additionalInfo
        };

        try {
            const result = await submitContentReport({
                reportData: JSON.stringify(reportData)
            });

            if (result && result.success) {
                this.showConfirmation = true;
                this.dispatchEvent(new CustomEvent('reportsubmitted', {
                    detail: {
                        contentId: this.contentId,
                        reason: this.selectedReason
                    }
                }));
            } else if (result?.alreadyReported) {
                this.showAlreadyReported = true;
            } else {
                // Apex returned success=false — surface the message and let
                // the user retry. Do NOT dispatch reportsubmitted, do NOT
                // close the modal: the caller would otherwise show a green
                // "Thank you" state for a report that did not actually land.
                this.errorMessage = (result && result.message)
                    ? result.message
                    : 'We could not submit your report. Please try again.';
            }
        } catch (error) {
            // Apex callout failed (network, auth, server exception, etc.).
            // Same rules as the success=false branch — surface the error and
            // preserve the form so the user can retry without re-entering.
            console.error('Error submitting report:', error);
            this.errorMessage = error?.body?.message
                || error?.message
                || 'We could not submit your report. Please try again or email safety@fimby.ca.';
        } finally {
            this.isSubmitting = false;
        }
    }
}
