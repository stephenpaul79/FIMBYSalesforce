import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';
import getResponseForStatusUpdate from '@salesforce/apex/FimbyResponseController.getResponseForStatusUpdate';
import updateResponseStatus from '@salesforce/apex/FimbyResponseController.updateResponseStatus';

/**
 * Response Status Update component - matches Response_Status_Update.flow
 *
 * Simple status update for a Response__c record.
 * - Checks if user is Response owner OR Need/Offer owner
 * - Provides dropdown of status options
 */
export default class FimbyResponseStatusUpdate extends NavigationMixin(LightningElement) {
    @api recordId = ''; // Response__c ID

    // State
    @track isLoading = true;
    @track isSubmitting = false;
    @track showModal = false;

    // Error states
    @track errorState = null; // 'noAccess', 'loadError'
    @track errorMessage = '';

    // Data
    @track response = null;
    @track selectedStatus = '';

    // Status options (from Response__c.Status__c picklist)
    statusOptions = [
        { label: 'New', value: 'New' },
        { label: 'Accepted', value: 'Accepted' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Declined', value: 'Declined' }
    ];

    // Success state
    @track showConfirmation = false;

    // ============================================
    // LIFECYCLE
    // ============================================

    connectedCallback() {
        if (this.recordId) {
            this.loadData();
        }
    }

    // ============================================
    // DATA LOADING
    // ============================================

    async loadData() {
        this.isLoading = true;
        this.errorState = null;

        try {
            const result = await getResponseForStatusUpdate({ recordId: this.recordId });

            if (!result.success) {
                this.errorState = result.error || 'loadError';
                this.errorMessage = result.message || 'Could not load response details';
                this.isLoading = false;
                return;
            }

            this.response = result.response;
            this.selectedStatus = result.response.status;

            // Check access
            if (!result.hasAccess) {
                this.errorState = 'noAccess';
                this.errorMessage = 'You do not have the correct access level to update the status on this record.';
            }

        } catch (error) {
            console.error('Error loading data:', error);
            this.errorState = 'loadError';
            this.errorMessage = error.body?.message || error.message || 'Error loading data';
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================
    // COMPUTED PROPERTIES
    // ============================================

    get hasError() {
        return this.errorState !== null;
    }

    get isNoAccess() {
        return this.errorState === 'noAccess';
    }

    get isStatusUnchanged() {
        return this.selectedStatus === this.response?.status;
    }

    get responseUrl() {
        return '/response-reply?recordId=' + this.recordId;
    }

    // ============================================
    // EVENT HANDLERS
    // ============================================

    @api
    show() {
        this.showModal = true;
        if (this.recordId && !this.response) {
            this.loadData();
        }
    }

    @api
    hide() {
        this.showModal = false;
        this.resetForm();
    }

    resetForm() {
        this.showConfirmation = false;
        this.errorState = null;
        if (this.response) {
            this.selectedStatus = this.response.status;
        }
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.hide();
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }

    handleGoToResponse() {
        navigate(this, this.responseUrl);
    }

    // ============================================
    // FORM SUBMISSION
    // ============================================

    async handleSubmit() {
        if (this.isStatusUnchanged) return;

        this.isSubmitting = true;

        try {
            const result = await updateResponseStatus({
                responseId: this.recordId,
                newStatus: this.selectedStatus
            });

            if (result.success) {
                this.showConfirmation = true;

                // Update local state
                this.response.status = this.selectedStatus;

                // Dispatch success event
                this.dispatchEvent(new CustomEvent('statusupdated', {
                    detail: {
                        responseId: this.recordId,
                        newStatus: this.selectedStatus
                    }
                }));
            } else {
                throw new Error(result.message || 'Error updating status');
            }

        } catch (error) {
            console.error('Error updating status:', error);
            this.dispatchEvent(new CustomEvent('statuserror', {
                detail: {
                    error: error.body?.message || error.message || 'Failed to update status'
                }
            }));
        } finally {
            this.isSubmitting = false;
        }
    }
}