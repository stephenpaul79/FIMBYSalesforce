/**
 * @deprecated Replaced by fimbyQuickResponseModal.
 * This full-page form and its /respond route should be unpublished in Experience Builder and then deleted.
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import { completeImageUrl } from 'c/fimbyImageUrl';
import getNeedsOffersForResponse from '@salesforce/apex/FimbyResponseController.getNeedsOffersForResponse';
import checkExistingResponse from '@salesforce/apex/FimbyResponseController.checkExistingResponse';
import createResponse from '@salesforce/apex/FimbyResponseController.createResponse';
import { toExperiencePath } from 'c/fimbyExperienceUrl';

/**
 * Quick Response component for responding to Needs & Offers
 * Page layout (like fimbyBorrowingFlow) - no modal.
 *
 * Contact Pattern (consistent across all posting LWCs):
 *   - Contact__c = realContactId (who physically clicked - auto-determined)
 *   - On_Behalf_Of_Contact__c = actingAsContactId (who they're acting as via Logged_In_As_ID__c - auto-determined)
 */
export default class FimbyQuickResponse extends NavigationMixin(LightningElement) {
    @api recordId = '';

    @track isLoading = true;
    @track isSubmitting = false;

    // View states: 'loading', 'noRecordId', 'noneAvailable', 'existingResponse', 'loadError', 'form', 'success'
    @track viewState = 'loading';
    @track errorMessage = '';
    @track existingResponseId = '';
    @track existingResponseUrl = '';

    @track needOffer = null;
    @track actingAsContact = null;

    @track subject = '';
    @track responseDetails = '';
    @track amountRequested = 1;
    @track decline = false;

    @track newResponseUrl = '';

    // ============================================
    // LIFECYCLE
    // ============================================

    connectedCallback() {
        if (!this.recordId) {
            this.recordId = this.extractRecordIdFromUrl();
        }
        if (this.recordId) {
            this.loadData();
        } else {
            this.viewState = 'noRecordId';
            this.isLoading = false;
        }
    }

    extractRecordIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            const queryRecordId = url.searchParams.get('recordId');
            if (queryRecordId) return queryRecordId;
            const pathParts = url.pathname.split('/').filter(part => part && part !== 's');
            const respondIdx = pathParts.findIndex(p => p === 'respond');
            if (respondIdx !== -1 && pathParts.length > respondIdx + 1) {
                return pathParts[respondIdx + 1];
            }
        } catch (e) {
            console.error('fimbyQuickResponse: Could not extract recordId from URL', e);
        }
        return '';
    }

    // ============================================
    // DATA LOADING
    // ============================================

    async loadData() {
        this.isLoading = true;
        this.viewState = 'loading';

        try {
            const contactResult = await getActingAsContact();
            if (contactResult.success) {
                this.actingAsContact = contactResult;
            } else {
                throw new Error('Could not get acting as contact');
            }

            const needOfferResult = await getNeedsOffersForResponse({ recordId: this.recordId });

            if (!needOfferResult.success) {
                this.viewState = needOfferResult.error || 'loadError';
                this.errorMessage = needOfferResult.message || 'Could not load post.';
                this.isLoading = false;
                return;
            }

            this.needOffer = needOfferResult.needOffer;

            const existingResult = await checkExistingResponse({ needOfferId: this.recordId });

            if (existingResult.hasExistingResponse) {
                this.viewState = 'existingResponse';
                this.existingResponseId = existingResult.existingResponse.id;
                this.existingResponseUrl = toExperiencePath(existingResult.existingResponse.responseUrl);
                this.isLoading = false;
                return;
            }

            this.amountRequested = 1;
            this.viewState = 'form';
        } catch (error) {
            console.error('Error loading data:', error);
            this.viewState = 'loadError';
            this.errorMessage = error.body?.message || error.message || 'Error loading data';
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================
    // IMAGE URL (fix broken images - append org id like fimbyBorrowingFlow)
    // ============================================

    get processedImageUrl() {
        return completeImageUrl(this.needOffer?.imageUrl);
    }

    get hasProcessedImage() {
        const url = this.processedImageUrl;
        return !!url && url.trim() !== '';
    }

    // ============================================
    // COMPUTED
    // ============================================

    get pageTitle() {
        return this.needOffer?.name ? `Respond to: ${this.needOffer.name}` : 'New Response';
    }

    get isLoadingState() { return this.viewState === 'loading'; }
    get isNoRecordIdState() { return this.viewState === 'noRecordId'; }
    get isNoneAvailableState() { return this.viewState === 'noneAvailable'; }
    get isExistingResponseState() { return this.viewState === 'existingResponse'; }
    get isLoadErrorState() { return this.viewState === 'loadError'; }
    get isFormState() { return this.viewState === 'form'; }
    get isSuccessState() { return this.viewState === 'success'; }

    get showAmountField() {
        return this.needOffer && this.needOffer.totalAvailable > 1;
    }

    get subjectLength() { return this.subject.length; }
    get subjectExceeded() { return this.subjectLength > 80; }
    get subjectOverBy() { return this.subjectLength - 80; }
    get detailsLength() { return this.responseDetails.length; }
    get detailsExceeded() { return this.detailsLength > 255; }
    get detailsOverBy() { return this.detailsLength - 255; }

    get subjectCountClass() {
        if (this.subjectLength >= 80) return 'character-count at-limit';
        if (this.subjectLength >= 72) return 'character-count near-limit';
        return 'character-count';
    }

    get detailsCountClass() {
        if (this.detailsLength >= 255) return 'character-count at-limit';
        if (this.detailsLength >= 230) return 'character-count near-limit';
        return 'character-count';
    }

    get maxAmount() {
        if (!this.needOffer) return 1;
        const available = this.needOffer.totalAvailable || 1;
        const perResponse = this.needOffer.perResponseLimit || available;
        return Math.min(available, perResponse);
    }

    get amountInvalid() {
        return this.amountRequested > this.maxAmount || this.amountRequested < 0;
    }

    get isFormInvalid() {
        if (!this.subject.trim() || this.subjectLength > 80) return true;
        if (!this.responseDetails.trim() || this.detailsLength > 255) return true;
        if (this.showAmountField && this.amountInvalid) return true;
        return false;
    }

    get respondingAsName() {
        return this.actingAsContact?.actingAsContactName || this.actingAsContact?.contactName || '';
    }

    // ============================================
    // EVENT HANDLERS
    // ============================================

    @api show() {
        if (this.recordId && !this.needOffer) this.loadData();
    }

    @api hide() {
        this.resetForm();
    }

    resetForm() {
        this.subject = '';
        this.responseDetails = '';
        this.amountRequested = 1;
        this.decline = false;
        this.errorMessage = '';
    }

    handleBack() {
        window.history.back();
    }

    handleSubjectChange(event) { this.subject = event.target.value; }
    handleDetailsChange(event) { this.responseDetails = event.target.value; }
    handleAmountChange(event) { this.amountRequested = parseInt(event.target.value, 10) || 1; }
    handleDeclineChange(event) { this.decline = event.target.checked; }

    handleViewExistingResponse() {
        window.location.href = toExperiencePath(this.existingResponseUrl) || this.existingResponseUrl;
    }

    handleBackToNeedOffer() {
        window.location.href = '/asks-offers/' + this.recordId;
    }

    handleViewNewResponse() {
        window.location.href = toExperiencePath(this.newResponseUrl) || this.newResponseUrl;
    }

    handleDone() {
        window.location.href = '/asks-offers/' + this.recordId;
    }

    async handleSubmit() {
        if (this.isFormInvalid || this.isSubmitting) return;

        this.isSubmitting = true;

        try {
            const responseData = {
                needOfferId: this.recordId,
                subject: this.subject,
                responseDetails: this.responseDetails,
                amountRequested: this.showAmountField ? this.amountRequested : 1,
                decline: this.decline
            };

            const result = await createResponse({
                responseData: JSON.stringify(responseData)
            });

            if (result.success) {
                this.newResponseUrl = toExperiencePath(result.responseUrl);
                this.viewState = 'success';
                this.dispatchEvent(new CustomEvent('responsecreated', {
                    detail: {
                        responseId: result.responseId,
                        responseUrl: toExperiencePath(result.responseUrl),
                        status: result.status
                    }
                }));
            } else {
                throw new Error(result.message || 'Error creating response');
            }
        } catch (error) {
            console.error('Error submitting response:', error);
            const rawMsg = error.body?.message || error.message || '';
            const isQuantityError = rawMsg.toLowerCase().includes('amount') ||
                                    rawMsg.toLowerCase().includes('available') ||
                                    rawMsg.toLowerCase().includes('quantity') ||
                                    rawMsg.toLowerCase().includes('validation');
            if (isQuantityError) {
                this.errorMessage = "Looks like this isn't available anymore — someone else responded a bit more quickly.";
                this.viewState = 'noneAvailable';
            } else {
                this.errorMessage = rawMsg || 'Failed to submit response';
                this.viewState = 'loadError';
            }
            this.dispatchEvent(new CustomEvent('responseerror', {
                detail: { error: this.errorMessage }
            }));
        } finally {
            this.isSubmitting = false;
        }
    }
}