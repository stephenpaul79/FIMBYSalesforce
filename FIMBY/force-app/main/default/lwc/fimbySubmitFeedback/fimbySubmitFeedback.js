import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getFeedbackTypePicklist from '@salesforce/apex/FimbyFeedbackController.getFeedbackTypePicklist';
import submitFeedback from '@salesforce/apex/FimbyFeedbackController.submitFeedback';

export default class FimbySubmitFeedback extends NavigationMixin(LightningElement) {
    @api recordId;
    @api isModalMode = false;
    _recordIdFromState = '';

    get activeRecordId() {
        return this.recordId || this._recordIdFromState;
    }

    @track isModalVisible = false;
    isLoading = true;
    currentContact = {};
    @track hasMultipleIdentities = false;

    feedbackType = '';
    feedbackTitle = '';
    feedbackDetails = '';
    feedbackTypeOptions = [];

    showConfirmation = false;
    showPhotoStep = false;
    newFeedbackId = '';

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this._recordIdFromState = this._recordIdFromState || currentPageReference.state?.recordId;
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

    connectedCallback() {
        if (!this.isModalMode) {
            this.loadData();
        }
    }

    _modalTrigger = null;

    @api
    show(relatedRecordId) {
        this._modalTrigger = document.activeElement;
        this.isModalVisible = true;
        if (relatedRecordId) {
            this._recordIdFromState = relatedRecordId;
        }
        this.loadData();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const closeBtn = this.template.querySelector('.modal-container .close-button');
            if (closeBtn) closeBtn.focus();
        }, 50);
    }

    @api
    hide() {
        this.isModalVisible = false;
        this.resetForm();
        if (this._modalTrigger && typeof this._modalTrigger.focus === 'function') {
            this._modalTrigger.focus();
        }
        this._modalTrigger = null;
        this.dispatchEvent(new CustomEvent('close'));
    }

    resetForm() {
        this.feedbackType = '';
        this.feedbackTitle = '';
        this.feedbackDetails = '';
        this.showConfirmation = false;
        this.showPhotoStep = false;
        this.newFeedbackId = '';
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape') {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.hide();
    }

    async loadData() {
        try {
            this.isLoading = true;

            const contactResult = await getActingAsContact();
            if (contactResult.success) {
                this.currentContact = contactResult;
            }

            const picklistResult = await getFeedbackTypePicklist();
            if (picklistResult) {
                this.feedbackTypeOptions = picklistResult.map(val => ({
                    label: val,
                    value: val
                }));
            }
        } catch (error) {
            console.error('Error loading data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    get actingAsName() {
        return this.currentContact?.postingAsDisplayName || this.currentContact?.actingAsContactName || '';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get showMainForm() {
        return !this.isLoading && !this.showConfirmation && !this.showPhotoStep;
    }

    get shouldShowModal() {
        return this.isModalMode && this.isModalVisible;
    }

    get shouldShowPage() {
        return !this.isModalMode;
    }

    get isSubmitDisabled() {
        if (!this.feedbackType || !this.feedbackTitle || !this.feedbackDetails) {
            return true;
        }
        return this.feedbackDetails.length > 32768;
    }

    get detailsCharacterCount() {
        return this.feedbackDetails.length + ' / 32768';
    }

    get detailsCountClass() {
        const len = this.feedbackDetails.length;
        if (len >= 32768) return 'character-count at-limit';
        if (len >= 29491) return 'character-count near-limit';
        return 'character-count';
    }

    handleFeedbackTypeChange(event) {
        this.feedbackType = event.detail.value;
    }

    handleFeedbackTitleChange(event) {
        this.feedbackTitle = event.detail.value;
    }

    handleFeedbackDetailsChange(event) {
        this.feedbackDetails = event.detail.value;
    }

    _scrollTop() {
        const reduced = typeof window !== 'undefined'
            && window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        window.scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' });
    }

    async handleSubmit(event) {
        const addScreenshot = event.target.dataset.action === 'screenshot';

        try {
            this.isLoading = true;

            const feedbackData = {
                feedbackType: this.feedbackType,
                title: this.feedbackTitle,
                details: this.feedbackDetails,
                relatedRecordId: this.activeRecordId || null
            };

            const result = await submitFeedback({ feedbackData: JSON.stringify(feedbackData) });

            if (result.success) {
                this.newFeedbackId = result.feedbackId;

                if (addScreenshot && this.newFeedbackId) {
                    this.showPhotoStep = true;
                    this._scrollTop();
                } else {
                    this.showConfirmation = true;
                    this._scrollTop();
                }
            } else {
                console.error('Error submitting feedback:', result.error);
            }
        } catch (error) {
            console.error('Error submitting feedback:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handlePhotoUploaded() {
        this.showPhotoStep = false;
        this.showConfirmation = true;
        this._scrollTop();
    }

    handleSkipPhoto() {
        this.showPhotoStep = false;
        this.showConfirmation = true;
        this._scrollTop();
    }

    handleGoBack() {
        if (this.isModalMode) {
            this.dispatchEvent(new CustomEvent('feedbacksubmitted', {
                detail: { feedbackId: this.newFeedbackId }
            }));
            this.hide();
            return;
        }

        if (this.activeRecordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: `/${this.activeRecordId}`
                }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: '/'
                }
            });
        }
    }
}
