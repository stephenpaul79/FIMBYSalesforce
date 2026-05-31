import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getOnboardingStatus from '@salesforce/apex/FimbyOnboardingController.getOnboardingStatus';
import getWalkthroughSlides from '@salesforce/apex/FimbyOnboardingController.getWalkthroughSlides';
import completeProfileSetup from '@salesforce/apex/FimbyOnboardingController.completeProfileSetup';
import saveQuietHoursPreference from '@salesforce/apex/FimbyOnboardingController.saveQuietHoursPreference';
import dismissWalkthrough from '@salesforce/apex/FimbyOnboardingController.dismissWalkthrough';
import completeWalkthrough from '@salesforce/apex/FimbyOnboardingController.completeWalkthrough';
import getProfileData from '@salesforce/apex/FimbyProfileController.getProfileData';
import submitVoucherDetails from '@salesforce/apex/FimbyVouchController.submitVoucherDetails';

const TOTAL_PROFILE_STEPS = 7;
const SESSION_DISMISS_KEY = 'fimby_onboarding_dismissed';
const SESSION_COMPLETE_KEY = 'fimby_onboarding_complete';

const CARE_WELCOME_VALUES = [
    'A check-in message',
    'A meal drop-off',
    'Help with errands',
    'A ride or accompaniment',
    'Help at home',
    'Company',
    'Help thinking things through',
    'Prayer',
    'Other'
];

const CARE_HOW_TO_ASK_VALUES = [
    'Message me first',
    'Offer one specific thing',
    'Ask what would be helpful today',
    'Keep it simple',
    'Please don\'t reach out unless I\'ve asked'
];

const CARE_UNHELPFUL_VALUES = [
    'Unannounced drop-ins',
    'Lots of questions at once',
    'Advice too quickly',
    'Big group attention',
    'Being posted about publicly',
    'Gifts with expectations',
    'Just pushing through talk',
    'Other'
];

export default class FimbyOnboardingModal extends LightningElement {
    @track isVisible = false;
    @track currentPhase = 1;
    @track currentStep = 1;
    @track showCelebration = false;
    @track isSaving = false;

    @track contactId = '';
    @track firstName = '';
    @track lastName = '';
    @track pronouns = '';
    @track aboutTenure = '';
    @track aboutBroughtYou = '';
    @track aboutLocalPlace = '';
    @track aboutEnjoys = '';
    @track aboutFunFact = '';
    @track careWelcome = [];
    @track careUnhelpful = [];
    @track careHowToAsk = '';
    @track careHardNos = '';
    @track quietHoursPreference = '10PM_6AM';
    @track vouchFullName = '';
    @track vouchEmail = '';
    @track vouchOrgName = '';
    @track vouchSubmitMessage = '';
    @track saveError = '';

    @track walkthroughPages = [];
    @track currentPageIndex = 0;
    @track currentSlideIndex = 0;
    @track isLoadingContent = false;
    @track dontShowAgain = false;

    _walkthroughContentCache = null;
    _cmsContentLoaded = false;

    /* --- Icon URLs ------------------------------------------------- */

    get logoUrl()         { return `${IMPACT_ICONS}/FIMBYwGrass.png`; }
    get chatIconUrl()     { return `${IMPACT_ICONS}/chat.png`; }
    get careIconUrl()     { return `${IMPACT_ICONS}/care.png`; }
    get cameraIconUrl()   { return `${IMPACT_ICONS}/camera.png`; }
    get confettiIconUrl() { return `${IMPACT_ICONS}/confetti.png`; }

    /* --- Phase / step state ---------------------------------------- */

    get isPhase1()  { return this.isVisible && this.currentPhase === 1; }
    get isPhase2()  { return this.isVisible && this.currentPhase === 2; }
    get isStep1()   { return this.currentPhase === 1 && this.currentStep === 1 && !this.showCelebration; }
    get isStep2()   { return this.currentPhase === 1 && this.currentStep === 2 && !this.showCelebration; }
    get isStep3()   { return this.currentPhase === 1 && this.currentStep === 3 && !this.showCelebration; }
    get isStep4()   { return this.currentPhase === 1 && this.currentStep === 4 && !this.showCelebration; }
    get isStep5()   { return this.currentPhase === 1 && this.currentStep === 5 && !this.showCelebration; }
    get isStep6()   { return this.currentPhase === 1 && this.currentStep === 6 && !this.showCelebration; }
    get isStep7()   { return this.currentPhase === 1 && this.currentStep === 7 && !this.showCelebration; }
    get canGoBack() { return this.currentStep > 1 && !this.showCelebration; }

    /* --- Step 7: vouch / introduction icon URLs ------------------- */

    get waveIconUrl() { return `${IMPACT_ICONS}/Wave.png`; }

    get isVouchStep7Valid() {
        const hasNameAndEmail = !!(this.vouchFullName?.trim() && this.vouchEmail?.trim());
        const hasOrgName = !!this.vouchOrgName?.trim();
        return hasNameAndEmail || hasOrgName;
    }

    get showDismissProfile() {
        return !this.showCelebration && !this.isSaving;
    }

    get modalAriaLabel() {
        return this.currentPhase === 1 ? 'Profile setup' : 'Feature walkthrough';
    }

    get personalizedGreeting() {
        return this.firstName ? `Nice to meet you, ${this.firstName}, tell us about yourself` : 'Tell us about yourself';
    }

    get nextButtonLabel() {
        if (this.currentStep === TOTAL_PROFILE_STEPS) return 'Send introduction';
        return 'Next';
    }

    get isNextDisabled() {
        if (this.isSaving) return true;
        if (this.currentStep === 1) {
            return !this.firstName || !this.firstName.trim() || !this.lastName || !this.lastName.trim();
        }
        if (this.currentStep === TOTAL_PROFILE_STEPS) {
            return !this.isVouchStep7Valid;
        }
        return false;
    }

    /* --- Profile step dots ----------------------------------------- */

    get profileSteps() {
        const steps = [];
        for (let i = 1; i <= TOTAL_PROFILE_STEPS; i++) {
            let dotClass = 'dot';
            if (i < this.currentStep) dotClass = 'dot completed';
            else if (i === this.currentStep) dotClass = 'dot active';

            steps.push({
                index: i,
                dotClass,
                ariaLabel: `Step ${i} of ${TOTAL_PROFILE_STEPS}${i === this.currentStep ? ' (current)' : ''}`
            });
        }
        return steps;
    }

    /* --- Care preference options ----------------------------------- */

    get careWelcomeOptions() {
        return CARE_WELCOME_VALUES.map(val => ({
            value: val,
            label: val,
            checked: this.careWelcome.includes(val)
        }));
    }

    get careHowToAskOptions() {
        return CARE_HOW_TO_ASK_VALUES.map(val => ({
            value: val,
            label: val,
            checked: this.careHowToAsk === val
        }));
    }

    get careUnhelpfulOptions() {
        return CARE_UNHELPFUL_VALUES.map(val => ({
            value: val,
            label: val,
            checked: this.careUnhelpful.includes(val)
        }));
    }

    get quietHoursOptions() {
        return [
            { value: '9PM_5AM', label: '9 PM \u2013 5 AM', checked: this.quietHoursPreference === '9PM_5AM' },
            { value: '10PM_6AM', label: '10 PM \u2013 6 AM', checked: this.quietHoursPreference === '10PM_6AM' },
            { value: '11PM_7AM', label: '11 PM \u2013 7 AM', checked: this.quietHoursPreference === '11PM_7AM' },
            { value: '12AM_8AM', label: '12 AM \u2013 8 AM', checked: this.quietHoursPreference === '12AM_8AM' },
            { value: 'NONE', label: 'No quiet hours \u2013 notify me anytime', checked: this.quietHoursPreference === 'NONE' }
        ];
    }

    /* --- Input handlers -------------------------------------------- */

    handleInputChange(event) {
        const field = event.target.dataset.field;
        if (field) {
            this[field] = event.target.value;
        }
    }

    handleCheckboxChange(event) {
        const group = event.target.dataset.group;
        const value = event.target.dataset.value;
        const checked = event.target.checked;

        if (group === 'careWelcome' || group === 'careUnhelpful') {
            if (checked) {
                this[group] = [...this[group], value];
            } else {
                this[group] = this[group].filter(v => v !== value);
            }
        }
    }

    handleRadioChange(event) {
        this.careHowToAsk = event.target.value;
    }

    handleQuietHoursChange(event) {
        this.quietHoursPreference = event.target.value;
    }

    handlePhotoUploaded() {
        // Photo uploaded successfully — the image uploader handles its own preview
    }

    /* --- Phase 1 navigation ---------------------------------------- */

    handleNext() {
        if (this.currentStep === 1 && (!this.firstName?.trim() || !this.lastName?.trim())) {
            return;
        }

        // Step 6 is the last *profile* step; save profile, then move to step 7 (introduction).
        if (this.currentStep === 6) {
            this._saveProfileAndAdvanceToVouchStep();
            return;
        }

        if (this.currentStep < TOTAL_PROFILE_STEPS) {
            this.currentStep++;
            this.saveError = '';
            this._scrollToTop();
            return;
        }

        // Step 7: submit voucher details then celebrate.
        this._submitVouchAndCelebrate();
    }

    handleSkipIntroduction() {
        // User chose "I will do this later". Skip the vouch submit, show celebration.
        // The Contact.Onboarding_Vouch_Skipped__c flag is set server-side in a follow-up
        // ping; for now we just advance to celebration. The universal header banner will
        // remind them per-session.
        this.showCelebration = true;
    }

    handleBack() {
        if (this.currentStep > 1) {
            this.currentStep--;
            this.saveError = '';
            this._scrollToTop();
        }
    }

    async _saveProfileAndAdvanceToVouchStep() {
        this.isSaving = true;
        this.saveError = '';
        try {
            const fieldValues = {
                'FirstName': this.firstName?.trim() || '',
                'LastName': this.lastName?.trim() || ''
            };

            if (this.pronouns?.trim()) fieldValues['Pronouns__c'] = this.pronouns.trim();
            if (this.aboutTenure?.trim()) fieldValues['About_Neighbourhood_Tenure__c'] = this.aboutTenure.trim();
            if (this.aboutBroughtYou?.trim()) fieldValues['About_What_Brought_You__c'] = this.aboutBroughtYou.trim();
            if (this.aboutLocalPlace?.trim()) fieldValues['About_Local_Place__c'] = this.aboutLocalPlace.trim();
            if (this.aboutEnjoys?.trim()) fieldValues['About_Enjoys_Doing__c'] = this.aboutEnjoys.trim();
            if (this.aboutFunFact?.trim()) fieldValues['About_Fun_Fact__c'] = this.aboutFunFact.trim();
            if (this.careWelcome.length > 0) fieldValues['Care_Welcome_Support__c'] = this.careWelcome.join(';');
            if (this.careUnhelpful.length > 0) fieldValues['Care_Unhelpful_Things__c'] = this.careUnhelpful.join(';');
            if (this.careHowToAsk) fieldValues['Care_How_To_Ask__c'] = this.careHowToAsk;
            if (this.careHardNos?.trim()) fieldValues['Care_Hard_Nos__c'] = this.careHardNos.trim();

            await completeProfileSetup({ fieldValues });
            if (this.quietHoursPreference) {
                await saveQuietHoursPreference({ preference: this.quietHoursPreference });
            }
            this.currentStep = TOTAL_PROFILE_STEPS;
            this._scrollToTop();
        } catch (error) {
            console.error('Error saving profile:', error);
            const msg = error?.body?.message || error?.message || 'Something went wrong saving your profile. Please try again.';
            this.saveError = msg;
        } finally {
            this.isSaving = false;
        }
    }

    async _submitVouchAndCelebrate() {
        if (!this.isVouchStep7Valid) return;
        this.isSaving = true;
        this.saveError = '';
        this.vouchSubmitMessage = '';
        try {
            const result = await submitVoucherDetails({
                fullName: this.vouchFullName?.trim() || '',
                email: this.vouchEmail?.trim() || '',
                organizationName: this.vouchOrgName?.trim() || ''
            });
            this.vouchSubmitMessage = result?.message || '';
            if (result?.delivered === false && !result?.alreadyHasPending) {
                // Not delivered (no match). Show inline message; don't celebrate.
                return;
            }
            // Delivered or already had a pending request — proceed to celebration either way.
            this.showCelebration = true;
        } catch (error) {
            console.error('Error submitting vouch request:', error);
            const msg = error?.body?.message || error?.message
                || 'Something went wrong sending your introduction. Please try again or skip for now.';
            this.saveError = msg;
        } finally {
            this.isSaving = false;
        }
    }

    /* --- Celebration → Phase 2 transition -------------------------- */

    handleStartTour() {
        this.showCelebration = false;
        this.currentPhase = 2;
        this._loadWalkthroughContent();
    }

    handleSkipTour() {
        this._dismiss(false);
    }

    handleDismissProfile() {
        sessionStorage.setItem(SESSION_DISMISS_KEY, '1');
        this._close();
    }

    /* --- Phase 2: Walkthrough -------------------------------------- */

    async _loadWalkthroughContent() {
        if (this._walkthroughContentCache) {
            this._processWalkthroughContent(this._walkthroughContentCache);
            this.isLoadingContent = false;
            return;
        }

        this.isLoadingContent = true;
        try {
            const slides = await getWalkthroughSlides();
            const mapped = (slides || []).map(s => ({
                contentKey: s.contentKey || '',
                title: s.title || '',
                body: s.body || '',
                heroImage: s.heroImage || '',
                pageOrder: s.pageOrder || '999',
                slideOrder: s.slideOrder || '010',
                pageTitle: s.pageTitle || '',
                buttonLabel: s.buttonLabel || '',
                buttonUrl: s.buttonUrl || ''
            })).filter(s => s.pageOrder && s.slideOrder)
              .sort((a, b) => {
                  const pc = a.pageOrder.localeCompare(b.pageOrder);
                  return pc !== 0 ? pc : a.slideOrder.localeCompare(b.slideOrder);
              });

            this._walkthroughContentCache = mapped;
            this._cmsContentLoaded = true;
            this._processWalkthroughContent(mapped);
        } catch (err) {
            console.error('Error loading walkthrough slides:', err);
            this._cmsContentLoaded = true;
            this.walkthroughPages = [];
        } finally {
            this.isLoadingContent = false;
        }
    }

    _processWalkthroughContent(slides) {
        if (!slides || slides.length === 0) {
            this.walkthroughPages = [];
            return;
        }

        const pageMap = new Map();
        for (const slide of slides) {
            const key = slide.pageOrder;
            if (!pageMap.has(key)) {
                pageMap.set(key, {
                    pageOrder: key,
                    pageTitle: slide.pageTitle || '',
                    slides: []
                });
            }
            pageMap.get(key).slides.push({ ...slide });
        }

        this.walkthroughPages = Array.from(pageMap.values())
            .sort((a, b) => a.pageOrder.localeCompare(b.pageOrder))
            .map((page, idx) => ({
                ...page,
                index: idx,
                dotClass: idx === 0 ? 'dot active' : 'dot',
                ariaLabel: `Page ${idx + 1}${idx === 0 ? ' (current)' : ''}`
            }));

        this.currentPageIndex = 0;
        this.currentSlideIndex = 0;
    }

    get hasWalkthroughContent() {
        return !this.isLoadingContent && this.walkthroughPages.length > 0;
    }

    get noWalkthroughContent() {
        return !this.isLoadingContent && this.walkthroughPages.length === 0;
    }

    get currentPage() {
        if (this.walkthroughPages.length === 0) return null;
        return this.walkthroughPages[this.currentPageIndex];
    }

    get currentPageSlides() {
        if (!this.currentPage) return [];
        return this.currentPage.slides.map((slide, idx) => ({
            ...slide,
            slideDotClass: idx === this.currentSlideIndex ? 'carousel-dot active' : 'carousel-dot'
        }));
    }

    get currentPageIsCarousel() {
        return this.currentPage && this.currentPage.slides.length > 1;
    }

    get currentSlide() {
        if (!this.currentPage) return null;
        return this.currentPage.slides[this.currentSlideIndex] || this.currentPage.slides[0];
    }

    get currentSlideTitle()       { return this.currentSlide?.title || ''; }
    get currentSlideBody()        { return this.currentSlide?.body || ''; }
    get currentSlideImage()       { return this.currentSlide?.heroImage || ''; }
    get currentSlideButtonLabel() { return this.currentSlide?.buttonLabel || ''; }
    get currentSlideButtonUrl()   { return this.currentSlide?.buttonUrl || ''; }

    get isFirstSlide() { return this.currentSlideIndex === 0; }
    get isLastSlide()  { return !this.currentPage || this.currentSlideIndex >= this.currentPage.slides.length - 1; }

    get isLastWalkthroughPage() {
        return this.currentPageIndex >= this.walkthroughPages.length - 1;
    }

    get carouselTransform() {
        return `transform: translateX(-${this.currentSlideIndex * 100}%)`;
    }

    /* --- Walkthrough navigation ------------------------------------ */

    handlePrevSlide() {
        if (this.currentSlideIndex > 0) {
            this.currentSlideIndex--;
        }
    }

    handleNextSlide() {
        if (this.currentPage && this.currentSlideIndex < this.currentPage.slides.length - 1) {
            this.currentSlideIndex++;
        }
    }

    handleNextPage() {
        if (this.currentPageIndex < this.walkthroughPages.length - 1) {
            this.currentPageIndex++;
            this.currentSlideIndex = 0;
            this._updatePageDots();
            this._scrollToTop();
        }
    }

    handleFinishTour() {
        completeWalkthrough()
            .then(() => {
                this._close();
            })
            .catch(err => {
                console.error('Error completing walkthrough:', err);
                this._close();
            });
    }

    handleDismissWalkthrough() {
        this._dismiss(this.dontShowAgain);
    }

    handleDontShowChange(event) {
        this.dontShowAgain = event.target.checked;
    }

    _dismiss(permanent) {
        sessionStorage.setItem(SESSION_DISMISS_KEY, '1');
        dismissWalkthrough({ permanent })
            .then(() => {
                this._close();
            })
            .catch(err => {
                console.error('Error dismissing walkthrough:', err);
                this._close();
            });
    }

    _updatePageDots() {
        this.walkthroughPages = this.walkthroughPages.map((page, idx) => ({
            ...page,
            dotClass: idx < this.currentPageIndex ? 'dot completed'
                    : idx === this.currentPageIndex ? 'dot active'
                    : 'dot',
            ariaLabel: `Page ${idx + 1}${idx === this.currentPageIndex ? ' (current)' : ''}`
        }));
    }

    /* --- Keyboard handling ----------------------------------------- */

    handleKeydown(event) {
        if (this.currentPhase === 1 && event.key === 'Escape' && this.showDismissProfile) {
            this.handleDismissProfile();
        }
        if (this.currentPhase === 2 && event.key === 'Escape') {
            this.handleDismissWalkthrough();
        }
        if (this.currentPhase === 2 && this.currentPageIsCarousel) {
            if (event.key === 'ArrowLeft')  this.handlePrevSlide();
            if (event.key === 'ArrowRight') this.handleNextSlide();
        }
    }

    /* --- Public API ------------------------------------------------ */

    @api
    async checkAndShow() {
        try {
            if (sessionStorage.getItem(SESSION_DISMISS_KEY) || sessionStorage.getItem(SESSION_COMPLETE_KEY)) {
                return;
            }

            const status = await getOnboardingStatus();

            if (!status.profileCompleted) {
                await this._loadExistingProfile();
                this.currentPhase = 1;
                this.currentStep = 1;
                this.showCelebration = false;
                this.isVisible = true;
                this._addKeyboardListener();
                return;
            }

            if (status.showWalkthrough) {
                this.currentPhase = 2;
                this.isVisible = true;
                this._addKeyboardListener();
                this._loadWalkthroughContent();
                return;
            }

            sessionStorage.setItem(SESSION_COMPLETE_KEY, '1');
        } catch (error) {
            console.error('Error checking onboarding status:', error);
        }
    }

    @api
    showWalkthrough() {
        this.currentPhase = 2;
        this.currentPageIndex = 0;
        this.currentSlideIndex = 0;
        this.dontShowAgain = false;
        this.isVisible = true;
        this._addKeyboardListener();
        this._loadWalkthroughContent();
    }

    @api
    hide() {
        this._close();
    }

    /* --- Internal helpers ------------------------------------------ */

    async _loadExistingProfile() {
        try {
            const profile = await getProfileData();
            if (profile) {
                this.contactId = profile.contactId || '';
                this.firstName = profile.firstName || '';
                this.lastName = profile.lastName || '';
                this.pronouns = profile.pronouns || '';
                this.aboutTenure = profile.aboutNeighbourhoodTenure || '';
                this.aboutBroughtYou = profile.aboutWhatBroughtYou || '';
                this.aboutLocalPlace = profile.aboutLocalPlace || '';
                this.aboutEnjoys = profile.aboutEnjoysDoing || '';
                this.aboutFunFact = profile.aboutFunFact || '';
                this.careHowToAsk = profile.careHowToAsk || '';
                this.careHardNos = profile.careHardNos || '';

                if (profile.careWelcomeSupport) {
                    this.careWelcome = profile.careWelcomeSupport.split(';').map(s => s.trim());
                }
                if (profile.careUnhelpfulThings) {
                    this.careUnhelpful = profile.careUnhelpfulThings.split(';').map(s => s.trim());
                }
            }
        } catch (error) {
            console.error('Error loading existing profile:', error);
        }
    }

    _close() {
        this.isVisible = false;
        this._removeKeyboardListener();
        this.dispatchEvent(new CustomEvent('onboardingcomplete'));
    }

    _scrollToTop() {
        const body = this.template.querySelector('.modal-body');
        if (body) body.scrollTop = 0;
    }

    _boundKeydown;

    _addKeyboardListener() {
        this._boundKeydown = this.handleKeydown.bind(this);
        // eslint-disable-next-line @lwc/lwc/no-document-query
        document.addEventListener('keydown', this._boundKeydown);
    }

    _removeKeyboardListener() {
        if (this._boundKeydown) {
            // eslint-disable-next-line @lwc/lwc/no-document-query
            document.removeEventListener('keydown', this._boundKeydown);
            this._boundKeydown = null;
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    disconnectedCallback() {
        this._removeKeyboardListener();
    }
}