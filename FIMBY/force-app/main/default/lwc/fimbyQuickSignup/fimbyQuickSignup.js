import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class FimbyQuickSignup extends NavigationMixin(LightningElement) {
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track selectedLocation = '';
    @track agreeToTerms = false;
    @track isSigningUp = false;

    popularNeighborhoods = [
        { value: 'downtown-vancouver', label: 'Downtown', selected: false },
        { value: 'kitsilano', label: 'Kitsilano', selected: false },
        { value: 'west-end', label: 'West End', selected: false },
        { value: 'mount-pleasant', label: 'Mount Pleasant', selected: false },
        { value: 'commercial-drive', label: 'Commercial Dr', selected: false },
        { value: 'burnaby', label: 'Burnaby', selected: false }
    ];

    get popularNeighborhoods() {
        return this.popularNeighborhoods.map(neighborhood => ({
            ...neighborhood,
            cssClass: neighborhood.selected ? 'neighborhood-chip selected' : 'neighborhood-chip'
        }));
    }

    get isSignupDisabled() {
        return !this.firstName ||
               !this.lastName ||
               !this.email ||
               !this.selectedLocation ||
               !this.agreeToTerms ||
               !this.isValidEmail(this.email) ||
               this.isSigningUp;
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

    handleNeighborhoodSelect(event) {
        const locationValue = event.currentTarget.dataset.location;

        // Update selection
        this.popularNeighborhoods = this.popularNeighborhoods.map(neighborhood => ({
            ...neighborhood,
            selected: neighborhood.value === locationValue
        }));

        this.selectedLocation = locationValue;
    }

    handleOtherLocation() {
        // Navigate to full location picker
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'select-location'
            },
            state: {
                returnUrl: '/quick-signup'
            }
        });
    }

    handleTermsChange(event) {
        this.agreeToTerms = event.target.checked;
    }

    async handleQuickSignup() {
        if (this.isSignupDisabled) return;

        this.isSigningUp = true;

        try {
            const signupData = {
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                phone: this.phone,
                location: this.selectedLocation,
                isQuickSignup: true
            };

            // Call Apex method for quick signup
            // const result = await quickCreateFimbyAccount({ signupData: JSON.stringify(signupData) });

            // Simulate signup
            await this.delay(1500);

            this.showSuccessToast('Account created! Welcome to FIMBY!');
            this.navigateToWelcome();

        } catch (error) {
            console.error('Quick signup error:', error);
            this.showErrorToast('Failed to create account. Please try again.');
        } finally {
            this.isSigningUp = false;
        }
    }

    handleFullRegistration() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'register'
            }
        });
    }

    handleBack() {
        window.history.back();
    }

    handleLogin(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'login'
            }
        });
    }

    // Social login handlers
    handleGoogleSignup() {
        // Implement Google OAuth
        this.showInfoToast('Google signup coming soon!');
    }

    handleFacebookSignup() {
        // Implement Facebook OAuth
        this.showInfoToast('Facebook signup coming soon!');
    }

    handleAppleSignup() {
        // Implement Apple Sign In
        this.showInfoToast('Apple Sign In coming soon!');
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

    showInfoToast(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Info',
            message: message,
            variant: 'info'
        }));
    }
}