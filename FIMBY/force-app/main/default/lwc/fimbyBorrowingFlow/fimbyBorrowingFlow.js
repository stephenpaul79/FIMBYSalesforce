/**
 * @deprecated Replaced by fimbyQuickResponseModal (library variant).
 * This full-page form and its /borrow-item route should be unpublished in Experience Builder and then deleted.
 */
import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getLibraryItemForLending from '@salesforce/apex/FimbyLibraryController.getLibraryItemForLending';
import checkExistingLendingRequest from '@salesforce/apex/FimbyLibraryController.checkExistingLendingRequest';
import createLendingRequest from '@salesforce/apex/FimbyLibraryController.createLendingRequest';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';

export default class FimbyBorrowingFlow extends NavigationMixin(LightningElement) {
    recordId;

    @track isLoading = true;
    @track isSubmitting = false;

    // View states: 'loading', 'unavailable', 'alreadyRequested', 'form', 'success', 'waitlisted', 'error'
    @track viewState = 'loading';
    @track errorMessage = '';

    // Item data
    @track item = {};

    // Acting as contact
    @track actingAsContactId = '';
    @track realContactId = '';
    @track actingAsContactName = '';
    @track hasMultipleIdentities = false;

    organizationId = null;

    // Form data
    @track requestedDate = '';
    @track daysNeeded = '';
    @track noteToLender = '';

    // Existing request data
    @track existingWaitlistPosition = null;

    // Success data
    @track waitlistPosition = null;
    @track estimatedAvailableDate = null;
    @track isFirstInLine = false;

    connectedCallback() {
        const urlParams = new URLSearchParams(window.location.search);
        this.recordId = urlParams.get('recordId');

        if (!this.recordId) {
            this.viewState = 'error';
            this.errorMessage = 'No item specified. Please select an item from the library.';
            this.isLoading = false;
            return;
        }

        this.requestedDate = this.todayDate;
        this.loadData();
    }

    get todayDate() {
        return new Date().toISOString().split('T')[0];
    }

    get maxDate() {
        const today = new Date();
        today.setDate(today.getDate() + 7);
        return today.toISOString().split('T')[0];
    }

    get noteLength() {
        return this.noteToLender ? this.noteToLender.length : 0;
    }

    get noteCountClass() {
        if (this.noteLength >= 255) return 'char-count at-limit';
        if (this.noteLength >= 230) return 'char-count near-limit';
        return 'char-count';
    }

    get isFormValid() {
        if (!this.requestedDate || !this.daysNeeded) {
            return false;
        }
        const selectedDate = new Date(this.requestedDate);
        const today = new Date();
        const maxAllowedDate = new Date();
        maxAllowedDate.setDate(today.getDate() + 7);
        if (selectedDate > maxAllowedDate) {
            return false;
        }
        if (this.item.maxLendingDays && this.daysNeeded > this.item.maxLendingDays) {
            return false;
        }
        if (this.daysNeeded < 1) {
            return false;
        }
        return true;
    }

    get isFormInvalid() {
        return !this.isFormValid;
    }

    get dateValidationError() {
        if (!this.requestedDate) return '';
        const selectedDate = new Date(this.requestedDate);
        const today = new Date();
        const maxAllowedDate = new Date();
        maxAllowedDate.setDate(today.getDate() + 7);
        if (selectedDate > maxAllowedDate) {
            return 'You cannot make requests more than 1 week in advance.';
        }
        return '';
    }

    get daysValidationError() {
        if (!this.daysNeeded) return '';
        if (this.daysNeeded < 1) {
            return 'Please enter at least 1 day.';
        }
        if (this.item.maxLendingDays && this.daysNeeded > this.item.maxLendingDays) {
            return `Please request ${this.item.maxLendingDays} days or less.`;
        }
        return '';
    }

    get showDateError() {
        return this.dateValidationError !== '';
    }

    get dateErrorDescribedBy() {
        return this.showDateError ? 'pickup-date-error' : undefined;
    }

    get showDaysError() {
        return this.daysValidationError !== '';
    }

    get daysErrorDescribedBy() {
        return this.showDaysError ? 'days-needed-error' : undefined;
    }

    get pageTitle() {
        return this.item.name ? `Borrow: ${this.item.name}` : 'Request to Borrow';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsContactName;
    }

    // View state getters
    get isLoadingState() {
        return this.viewState === 'loading';
    }

    get isUnavailableState() {
        return this.viewState === 'unavailable';
    }

    get isAlreadyRequestedState() {
        return this.viewState === 'alreadyRequested';
    }

    get isFormState() {
        return this.viewState === 'form';
    }

    get isSuccessState() {
        return this.viewState === 'success';
    }

    get isWaitlistedState() {
        return this.viewState === 'waitlisted';
    }

    get isErrorState() {
        return this.viewState === 'error';
    }

    get showItemOnHold() {
        return this.item.status === 'On Hold' || this.item.status === 'Currently Lent Out';
    }

    get processedImageUrl() {
        return this.getCompleteImageUrl(this.item.imageUrl);
    }

    get hasProcessedImage() {
        const url = this.processedImageUrl;
        return !!url && url.trim() !== '';
    }

    getCompleteImageUrl(imageUrl) {
        if (!imageUrl) return null;
        if (this.organizationId && imageUrl.includes(this.organizationId)) return imageUrl;
        if (this.organizationId) return imageUrl + this.organizationId;
        return imageUrl;
    }

    async loadData() {
        try {
            try {
                this.organizationId = await getOrganizationId();
            } catch (e) {
                console.error('Org ID error', e);
            }

            const actingAsResult = await getActingAsContact();
            if (actingAsResult.success) {
                this.actingAsContactId = actingAsResult.actingAsContactId || actingAsResult.contactId;
                this.realContactId = actingAsResult.realContactId;
                this.actingAsContactName = actingAsResult.postingAsDisplayName
                    || actingAsResult.actingAsContactName
                    || actingAsResult.contactName;
            }

            try {
                const identities = await getAvailableIdentities();
                this.hasMultipleIdentities = (identities || []).length > 0;
            } catch (e) {
                console.error('Error loading identities:', e);
                this.hasMultipleIdentities = false;
            }

            const itemResult = await getLibraryItemForLending({ recordId: this.recordId });
            if (!itemResult.success) {
                this.viewState = 'error';
                this.errorMessage = 'Could not load item details.';
                this.isLoading = false;
                return;
            }

            this.item = itemResult.item;

            if (!itemResult.canBeLent) {
                this.viewState = 'unavailable';
                this.isLoading = false;
                return;
            }

            const existingResult = await checkExistingLendingRequest({
                itemId: this.recordId,
                requestedById: this.actingAsContactId
            });

            if (existingResult.hasExistingRequest) {
                this.existingWaitlistPosition = existingResult.existingRequest.waitlistPosition;
                this.viewState = 'alreadyRequested';
                this.isLoading = false;
                return;
            }

            this.viewState = 'form';
            this.isLoading = false;

        } catch (error) {
            console.error('Error loading data:', error);
            this.viewState = 'error';
            this.errorMessage = error.body?.message || 'An error occurred while loading.';
            this.isLoading = false;
        }
    }

    handleDateChange(event) {
        this.requestedDate = event.target.value;
    }

    handleDaysChange(event) {
        this.daysNeeded = parseInt(event.target.value, 10) || '';
    }

    handleNoteChange(event) {
        this.noteToLender = event.target.value;
    }

    handleBack() {
        window.history.back();
    }

    handleDone() {
        const itemId = this.item?.Id || this.recordId;
        window.location.href = itemId ? `/library-item/${itemId}/` : '/library-list/';
    }

    async handleSubmitRequest() {
        if (this.isFormInvalid || this.isSubmitting) return;

        this.isSubmitting = true;

        try {
            const requestData = {
                itemId: this.recordId,
                requestedById: this.actingAsContactId,
                requestedByRealContactId: this.realContactId,
                requestedDate: this.requestedDate,
                daysNeeded: this.daysNeeded,
                message: this.noteToLender || null
            };

            const result = await createLendingRequest({
                requestData: JSON.stringify(requestData)
            });

            if (result.success) {
                this.waitlistPosition = result.waitlistPosition;
                this.estimatedAvailableDate = result.estimatedAvailableDate;
                this.isFirstInLine = result.isFirstInLine;
                this.viewState = result.isFirstInLine ? 'success' : 'waitlisted';
            }
        } catch (error) {
            console.error('Error submitting request:', error);
            this.errorMessage = error.body?.message || 'Failed to submit request.';
            this.viewState = 'error';
        } finally {
            this.isSubmitting = false;
        }
    }
}