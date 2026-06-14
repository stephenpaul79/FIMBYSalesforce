import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fireToast } from 'c/fimbyToastHelper';

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

            // Success navigates straight to the welcome screen — the new
            // surface is its own confirmation, so no banner here.
            this.navigateToWelcome();

        } catch (error) {
            console.error('Quick signup error:', error);
            fireToast({ message: 'We couldn’t create your account just now. Please try again.', variant: 'error' });
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
        fireToast({ message: 'Google signup is coming soon.', variant: 'info' });
    }

    handleFacebookSignup() {
        // Implement Facebook OAuth
        fireToast({ message: 'Facebook signup is coming soon.', variant: 'info' });
    }

    handleAppleSignup() {
        // Implement Apple Sign In
        fireToast({ message: 'Apple Sign In is coming soon.', variant: 'info' });
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
}