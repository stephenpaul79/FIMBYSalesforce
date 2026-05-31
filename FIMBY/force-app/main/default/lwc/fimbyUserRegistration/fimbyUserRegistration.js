import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class FimbyUserRegistration extends NavigationMixin(LightningElement) {
    @track currentStep = 1;
    @track isCreatingAccount = false;

    // Form data
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track whyJoin = '';
    @track selectedLocation = '';
    @track selectedLocationLabel = '';
    @track profilePhotoUrl = '';
    @track selectedInterests = [];
    @track agreeToTerms = false;

    // Registration steps
    registrationSteps = [
        { key: 'step1', number: '1', title: 'Info', active: true, completed: false, showConnector: true },
        { key: 'step2', number: '2', title: 'Location', active: false, completed: false, showConnector: true },
        { key: 'step3', number: '3', title: 'Photo', active: false, completed: false, showConnector: true },
        { key: 'step4', number: '4', title: 'Interests', active: false, completed: false, showConnector: true },
        { key: 'step5', number: '5', title: 'Review', active: false, completed: false, showConnector: false }
    ];

    // Available interests
    interests = [
        { value: 'gardening', label: 'Gardening', icon: 'utility:world', selected: false },
        { value: 'cooking', label: 'Cooking', icon: 'utility:food_and_drink', selected: false },
        { value: 'diy', label: 'DIY & Crafts', icon: 'utility:builder', selected: false },
        { value: 'fitness', label: 'Fitness', icon: 'utility:like', selected: false },
        { value: 'books', label: 'Books', icon: 'utility:knowledge_base', selected: false },
        { value: 'music', label: 'Music', icon: 'utility:volume_high', selected: false },
        { value: 'pets', label: 'Pets', icon: 'utility:animal_and_nature', selected: false },
        { value: 'tech', label: 'Technology', icon: 'utility:desktop', selected: false },
        { value: 'parenting', label: 'Parenting', icon: 'utility:people', selected: false },
        { value: 'volunteering', label: 'Volunteering', icon: 'utility:heart', selected: false }
    ];

    get progressValue() {
        return (this.currentStep / 5) * 100;
    }

    get registrationSteps() {
        return this.registrationSteps.map(step => ({
            ...step,
            cssClass: this.getStepClass(parseInt(step.number))
        }));
    }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }

    get whyJoinCharacterCount() {
        return this.whyJoin.length;
    }

    get whyJoinCountClass() {
        const len = this.whyJoin ? this.whyJoin.length : 0;
        if (len >= 500) return 'character-count at-limit';
        if (len >= 450) return 'character-count near-limit';
        return 'character-count';
    }

    get fullName() {
        return `${this.firstName} ${this.lastName}`.trim();
    }

    get isStep1Invalid() {
        return !this.firstName || !this.lastName || !this.email || !this.isValidEmail(this.email);
    }

    get isStep2Invalid() {
        return !this.selectedLocation;
    }

    get isCreateDisabled() {
        return !this.agreeToTerms || this.isCreatingAccount;
    }

    get interests() {
        return this.interests.map(interest => ({
            ...interest,
            cssClass: interest.selected ? 'interest-chip selected' : 'interest-chip',
            iconVariant: interest.selected ? 'inverse' : 'neutral'
        }));
    }

    get selectedInterests() {
        return this.interests.filter(i => i.selected).map(i => i.label);
    }

    getStepClass(stepNumber) {
        let classes = ['progress-step'];

        if (stepNumber < this.currentStep) {
            classes.push('completed');
        } else if (stepNumber === this.currentStep) {
            classes.push('active');
        }

        return classes.join(' ');
    }

    // Event handlers
    handleFirstNameChange(event) {
        this.firstName = event.target.value;
    }

    handleLastNameChange(event) {
        this.lastName = event.target.value;
    }

    handleEmailChange(event) {
        this.email = event.target.value;
    }

    handlePhoneChange(event) {
        this.phone = event.target.value;
    }

    handleWhyJoinChange(event) {
        this.whyJoin = event.target.value;
    }

    handleLocationSelected(event) {
        this.selectedLocation = event.detail.value;
        this.selectedLocationLabel = event.detail.location.label;
    }

    handlePhotoSelected(event) {
        this.profilePhotoUrl = event.detail.imageUrl;
    }

    handlePhotoRemoved() {
        this.profilePhotoUrl = '';
    }

    handleInterestToggle(event) {
        const interestValue = event.currentTarget.dataset.interest;
        this.interests = this.interests.map(interest => {
            if (interest.value === interestValue) {
                return { ...interest, selected: !interest.selected };
            }
            return interest;
        });
    }

    handleTermsChange(event) {
        this.agreeToTerms = event.target.checked;
    }

    // Step navigation
    handleStep1Continue() {
        if (this.isStep1Invalid) return;
        this.goToStep(2);
    }

    handleStep2Continue() {
        if (this.isStep2Invalid) return;
        this.goToStep(3);
    }

    handleStep3Continue() {
        this.goToStep(4);
    }

    handleStep4Continue() {
        this.goToStep(5);
    }

    handleBack() {
        if (this.currentStep > 1) {
            this.goToStep(this.currentStep - 1);
        } else {
            // Navigate to login or home
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: {
                    pageName: 'login'
                }
            });
        }
    }

    goToStep(stepNumber) {
        this.currentStep = stepNumber;
        this.updateStepStates();
    }

    updateStepStates() {
        this.registrationSteps = this.registrationSteps.map((step, index) => ({
            ...step,
            active: (index + 1) === this.currentStep,
            completed: (index + 1) < this.currentStep
        }));
    }

    async handleCreateAccount() {
        if (this.isCreateDisabled) return;

        this.isCreatingAccount = true;

        try {
            const registrationData = {
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                phone: this.phone,
                whyJoin: this.whyJoin,
                location: this.selectedLocation,
                locationLabel: this.selectedLocationLabel,
                profilePhotoUrl: this.profilePhotoUrl,
                interests: this.selectedInterests
            };

            // Call Apex method to create account
            // const result = await createFimbyAccount({ registrationData: JSON.stringify(registrationData) });

            // Simulate account creation
            await this.delay(2000);

            this.showSuccessToast('Welcome to FIMBY! Your account has been created.');
            this.navigateToWelcome();

        } catch (error) {
            console.error('Registration error:', error);
            this.showErrorToast('Failed to create account. Please try again.');
        } finally {
            this.isCreatingAccount = false;
        }
    }

    // Helper methods
    isValidEmail(email) {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    }

    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    navigateToWelcome() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'welcome'
            }
        });
    }

    showSuccessToast(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: message,
            variant: 'success'
        }));
    }

    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: message,
            variant: 'error'
        }));
    }
}