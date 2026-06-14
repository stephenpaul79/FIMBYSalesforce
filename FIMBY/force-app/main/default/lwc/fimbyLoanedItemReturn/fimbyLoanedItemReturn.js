import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getLoanedItemForReturn from '@salesforce/apex/FimbyLendingController.getLoanedItemForReturn';
import submitBorrowerReturn from '@salesforce/apex/FimbyLendingController.submitBorrowerReturn';
import submitOwnerReturn from '@salesforce/apex/FimbyLendingController.submitOwnerReturn';
import getConditionPicklistValues from '@salesforce/apex/FimbyLendingController.getConditionPicklistValues';

export default class FimbyLoanedItemReturn extends NavigationMixin(LightningElement) {
    @api recordId;

    isLoading = true;
    hasError = false;
    errorType = '';

    loanedItem = {};
    libraryItem = {};
    isOwner = false;
    isBorrower = false;

    // Form fields
    returnStatus = '';
    dateReturned = '';
    conditionUponReturn = '';
    wouldLendAgain = '';
    wouldBorrowAgain = '';

    // Picklist options
    conditionOptions = [];

    // Confirmation state
    showConfirmation = false;
    confirmationMessage = '';
    isDamaged = false;

    returnStatusOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'Lost or Damaged (No Longer Available)', value: 'Lost or Damaged' }
    ];

    yesNoOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = this.recordId || currentPageReference.state?.recordId;
        }
    }

    connectedCallback() {
        // Set default date to today
        this.dateReturned = new Date().toISOString().split('T')[0];
        this.loadData();
    }

    async loadData() {
        try {
            this.isLoading = true;

            // Load condition picklist values
            const picklistResult = await getConditionPicklistValues();
            if (picklistResult) {
                this.conditionOptions = picklistResult.map(val => ({
                    label: val,
                    value: val
                }));
            }

            // Load loaned item data
            const result = await getLoanedItemForReturn({ recordId: this.recordId });

            if (result.success) {
                this.loanedItem = result.loanedItem;
                this.libraryItem = result.libraryItem;
                this.isOwner = result.isOwner;
                this.isBorrower = result.isBorrower;
                this.hasError = false;
            } else {
                this.hasError = true;
                this.errorType = result.error;
            }
        } catch (error) {
            this.hasError = true;
            this.errorType = 'exception';
            console.error('Error loading data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    get showMainForm() {
        return !this.isLoading && !this.hasError && !this.showConfirmation;
    }

    get showErrorWall() {
        return this.hasError;
    }

    get errorWallMessage() {
        if (this.errorType === 'notAuthorized') {
            return 'You are not the owner or the borrower of this item.';
        }
        if (this.errorType === 'alreadyReturned') {
            return 'This item has already been returned.';
        }
        return 'An error occurred. Please try again.';
    }

    get itemName() {
        return this.libraryItem?.Name || 'Item';
    }

    get borrowerName() {
        return this.loanedItem?.Requester_s_First_Name__c || 'the borrower';
    }

    get ownerName() {
        return this.loanedItem?.Item_Owner_s_First_Name__c || 'the owner';
    }

    get isSubmitDisabled() {
        if (!this.returnStatus || !this.dateReturned) {
            return true;
        }
        // Owner must select condition upon return
        if (this.isOwner && !this.conditionUponReturn) {
            return true;
        }
        return false;
    }

    handleReturnStatusChange(event) {
        this.returnStatus = event.detail.value;
    }

    handleDateChange(event) {
        this.dateReturned = event.detail.value;
    }

    handleConditionChange(event) {
        this.conditionUponReturn = event.detail.value;
    }

    handleLendAgainChange(event) {
        this.wouldLendAgain = event.detail.value;
    }

    handleBorrowAgainChange(event) {
        this.wouldBorrowAgain = event.detail.value;
    }

    async handleSubmit() {
        try {
            this.isLoading = true;

            const isDamaged = this.returnStatus === 'Lost or Damaged';
            let result;

            if (this.isBorrower && !this.isOwner) {
                // Borrower submitting return
                result = await submitBorrowerReturn({
                    recordId: this.recordId,
                    dateReturned: this.dateReturned,
                    isDamaged: isDamaged,
                    wouldBorrowAgain: this.wouldBorrowAgain
                });
            } else {
                // Owner confirming return
                result = await submitOwnerReturn({
                    recordId: this.recordId,
                    dateReturned: this.dateReturned,
                    isDamaged: isDamaged,
                    conditionUponReturn: this.conditionUponReturn,
                    wouldLendAgain: this.wouldLendAgain
                });
            }

            if (result.success) {
                this.showConfirmation = true;
                this.isDamaged = isDamaged;

                if (isDamaged) {
                    if (this.isOwner) {
                        this.confirmationMessage = `Loving others is a risky business, and we are sorry to hear that things worked out like this! We hope that ${this.borrowerName} is able to make amends with you in whatever way they can.`;
                    } else {
                        this.confirmationMessage = `We are sorry to hear that! FYI We have let ${this.ownerName} know of your update so they can follow up with you and confirm the details. Also, we would suggest you attempt to make amends with them in whatever way you can.`;
                    }
                } else {
                    if (this.isOwner) {
                        this.confirmationMessage = `You helped one of your neighbours! Thanks for your generous heart!!`;
                    } else {
                        this.confirmationMessage = `Thanks for returning things in one piece!! PS We have let ${this.ownerName} know of your update so they can confirm the return as well.`;
                    }
                }
            } else {
                this.hasError = true;
                this.errorType = result.error || 'submitError';
            }
        } catch (error) {
            this.hasError = true;
            this.errorType = 'exception';
            console.error('Error submitting return:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleGoToLibraryItem() {
        const libraryItemId = this.libraryItem?.Id;
        if (libraryItemId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: `/library-item/${libraryItemId}/`
                }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: '/library-list/'
                }
            });
        }
    }
}