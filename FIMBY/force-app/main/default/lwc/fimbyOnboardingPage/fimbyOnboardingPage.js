import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate } from 'c/fimbyNavigation';
import { fireErrorToast } from 'c/fimbyToastHelper';
import getOnboardingStatus from '@salesforce/apex/FimbyOnboardingController.getOnboardingStatus';
import completeProfileSetup from '@salesforce/apex/FimbyOnboardingController.completeProfileSetup';
import saveQuietHoursPreference from '@salesforce/apex/FimbyOnboardingController.saveQuietHoursPreference';
import getProfileData from '@salesforce/apex/FimbyProfileController.getProfileData';

import {
    WALKTHROUGH_SCREENS,
    SCREEN_IDS,
    SHARED_LIFE_PILLS,
    SHARED_LIFE_PHONE_POSTS,
    EVENT_TIERS,
    QUICK_POST_TILES,
    NAV_ITEMS,
    HEADER_ACTIONS,
    FEED_FILTER_PILLS
} from './fimbyWalkthroughContent';

const TOTAL_PROFILE_STEPS = 4;
const TOUR_PENDING_SESSION_KEY = 'fimby_tour_pending';
const TOTAL_WALKTHROUGH_SCREENS = WALKTHROUGH_SCREENS.length;
const MIN_ABOUT_FIELDS = 2;
const DEFAULT_QUIET_HOURS = '10PM_6AM';

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

export default class FimbyOnboardingPage extends NavigationMixin(LightningElement) {
    @track _isReady = false;
    @track _currentPhase = 1;
    @track _showIntroModal = false;

    @track _currentStep = 1;
    @track _isSaving = false;

    @track _contactId = '';
    @track _firstName = '';
    @track _lastName = '';
    @track _pronouns = '';
    @track _aboutTenure = '';
    @track _aboutBroughtYou = '';
    @track _aboutLocalPlace = '';
    @track _aboutEnjoys = '';
    @track _aboutFunFact = '';
    @track _careWelcome = [];
    @track _maskLastName = false;
    @track _maskAvatar = false;

    @track _walkthroughIndex = 0;
    @track _carouselSlideIndex = 0;

    _boundKeydown = null;

    async connectedCallback() {
        try {
            const status = await getOnboardingStatus();
            const profileCompleted = !!status?.profileCompleted;

            if (profileCompleted) {
                window.location.replace('/');
                return;
            }
            this._currentPhase = 1;
            await this._loadExistingProfile();
        } catch (err) {
            console.error('fimbyOnboardingPage connectedCallback', err);
            this._currentPhase = 1;
        } finally {
            this._isReady = true;
            this._addKeyboardListener();
        }
    }

    disconnectedCallback() {
        this._removeKeyboardListener();
    }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    get logoUrl()     { return `${IMPACT_ICONS}/FIMBYwGrass.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get careIconUrl() { return `${IMPACT_ICONS}/care.png`; }

    get isReady()  { return this._isReady; }
    get isPhase1() { return this._isReady && this._currentPhase === 1; }
    get isPhase2() { return this._isReady && this._currentPhase === 2; }
    get showIntroModal() { return this._showIntroModal; }

    get isStep1() { return this._currentPhase === 1 && this._currentStep === 1; }
    get isStep2() { return this._currentPhase === 1 && this._currentStep === 2; }
    get isStep3() { return this._currentPhase === 1 && this._currentStep === 3; }
    get isStep4() { return this._currentPhase === 1 && this._currentStep === 4; }
    get canGoBack() { return this._currentStep > 1; }

    get profileSteps() {
        const steps = [];
        for (let i = 1; i <= TOTAL_PROFILE_STEPS; i++) {
            let dotClass = 'dot';
            if (i < this._currentStep) dotClass = 'dot completed';
            else if (i === this._currentStep) dotClass = 'dot active';
            steps.push({
                index: i,
                dotClass,
                ariaLabel: `Step ${i} of ${TOTAL_PROFILE_STEPS}${i === this._currentStep ? ' (current)' : ''}`
            });
        }
        return steps;
    }

    get firstName()       { return this._firstName; }
    get lastName()        { return this._lastName; }
    get pronouns()        { return this._pronouns; }
    get aboutTenure()     { return this._aboutTenure; }
    get aboutBroughtYou() { return this._aboutBroughtYou; }
    get aboutLocalPlace() { return this._aboutLocalPlace; }
    get aboutEnjoys()     { return this._aboutEnjoys; }
    get aboutFunFact()    { return this._aboutFunFact; }
    get isSaving()        { return this._isSaving; }
    get contactId()       { return this._contactId; }
    get maskLastName()    { return this._maskLastName; }
    get maskAvatar()      { return this._maskAvatar; }

    get personalizedGreeting() {
        return this._firstName ? `Nice to meet you, ${this._firstName}, tell us about yourself` : 'Tell us about yourself';
    }

    get aboutFieldsFilledCount() {
        return [
            this._aboutTenure,
            this._aboutBroughtYou,
            this._aboutLocalPlace,
            this._aboutEnjoys,
            this._aboutFunFact
        ].filter(v => v && v.trim()).length;
    }

    get aboutCounterMessage() {
        const filled = this.aboutFieldsFilledCount;
        if (filled >= MIN_ABOUT_FIELDS) {
            return `Great — your bio post will have some warmth. (${filled} of ${MIN_ABOUT_FIELDS} minimum)`;
        }
        return `Share at least ${MIN_ABOUT_FIELDS} so neighbours have something to say hi about. (${filled} of ${MIN_ABOUT_FIELDS})`;
    }

    get aboutCounterClass() {
        return this.aboutFieldsFilledCount >= MIN_ABOUT_FIELDS
            ? 'about-counter about-counter-met'
            : 'about-counter';
    }

    get nextButtonLabel() {
        return this._currentStep === TOTAL_PROFILE_STEPS ? 'Finish' : 'Next';
    }

    get isNextDisabled() {
        if (this._isSaving) return true;
        if (this._currentStep === 1) {
            return !this._firstName?.trim() || !this._lastName?.trim();
        }
        if (this._currentStep === 3) {
            return this.aboutFieldsFilledCount < MIN_ABOUT_FIELDS;
        }
        return false;
    }

    get careWelcomeOptions() {
        return CARE_WELCOME_VALUES.map(val => ({
            value: val,
            label: val,
            checked: this._careWelcome.includes(val)
        }));
    }

    get walkthroughDots() {
        return WALKTHROUGH_SCREENS.map((s, idx) => {
            let dotClass = 'dot';
            if (idx < this._walkthroughIndex) dotClass = 'dot completed';
            else if (idx === this._walkthroughIndex) dotClass = 'dot active';
            return {
                id: s.id,
                dotClass,
                ariaLabel: `Screen ${idx + 1} of ${TOTAL_WALKTHROUGH_SCREENS}${idx === this._walkthroughIndex ? ' (current)' : ''}`
            };
        });
    }

    get currentScreen()    { return WALKTHROUGH_SCREENS[this._walkthroughIndex]; }
    get currentScreenId()  { return this.currentScreen?.id || ''; }
    get isVisionScreen()   { return this.currentScreenId === SCREEN_IDS.VISION; }
    get isFeedScreen()     { return this.currentScreenId === SCREEN_IDS.FEED; }
    get isAskOfferScreen() { return this.currentScreenId === SCREEN_IDS.ASK_OFFER; }
    get isSharedLifeEventsScreen() { return this.currentScreenId === SCREEN_IDS.SHARED_LIFE_EVENTS; }
    get isLibraryScreen()  { return this.currentScreenId === SCREEN_IDS.LIBRARY; }
    get isLastWalkthroughScreen()  { return this._walkthroughIndex >= TOTAL_WALKTHROUGH_SCREENS - 1; }
    get isFirstWalkthroughScreen() { return this._walkthroughIndex === 0; }
    get isLoading() { return !this._isReady; }

    get visionContent() { return WALKTHROUGH_SCREENS[0]; }
    get feedContent() { return WALKTHROUGH_SCREENS[1]; }

    get feedFilterPills() {
        return FEED_FILTER_PILLS.map(pill => ({
            ...pill,
            iconUrl: pill.iconFile ? `${IMPACT_ICONS}/${pill.iconFile}` : null,
            phonePillClass: pill.isActive ? 'phone-pill active' : 'phone-pill'
        }));
    }

    get navItems() {
        return NAV_ITEMS.map(item => {
            const isCreate = Boolean(item.isCreateButton);
            const phoneItemClass = [
                'phone-nav-item',
                isCreate ? 'create' : '',
                item.isActive ? 'active' : ''
            ].filter(Boolean).join(' ');
            return {
                ...item,
                isCreate,
                iconUrl: `${IMPACT_ICONS}/${item.iconFile}`,
                phoneItemClass
            };
        });
    }

    get headerActions() {
        return HEADER_ACTIONS.map(action => ({
            ...action,
            iconUrl: `${IMPACT_ICONS}/${action.iconFile}`
        }));
    }

    get askOfferContent() { return WALKTHROUGH_SCREENS[2]; }
    get askOfferPlusIconUrl() { return `${IMPACT_ICONS}/add.png`; }

    get quickPostTiles() {
        return QUICK_POST_TILES.map(tile => ({
            ...tile,
            iconUrl: `${IMPACT_ICONS}/${tile.iconFile}`
        }));
    }

    get sharedLifeEventsScreen() { return WALKTHROUGH_SCREENS[3]; }

    get carouselSlides() {
        const slides = this.sharedLifeEventsScreen?.slides || [];
        return slides.map((slide, idx) => ({
            ...slide,
            dotClass: idx === this._carouselSlideIndex ? 'carousel-dot active' : 'carousel-dot',
            ariaLabel: `Slide ${idx + 1} of ${slides.length}`
        }));
    }

    get currentCarouselSlide() {
        const slides = this.sharedLifeEventsScreen?.slides || [];
        return slides[this._carouselSlideIndex] || slides[0];
    }

    get currentCarouselSlideId() { return this.currentCarouselSlide?.id || ''; }
    get isCarouselSharedLifeSlide() { return this.currentCarouselSlideId === 'shared-life'; }
    get isCarouselEventsSlide() { return this.currentCarouselSlideId === 'events'; }
    get isFirstCarouselSlide() { return this._carouselSlideIndex === 0; }
    get isLastCarouselSlide() {
        const slides = this.sharedLifeEventsScreen?.slides || [];
        return this._carouselSlideIndex >= slides.length - 1;
    }
    get carouselTransform() {
        return `transform: translateX(-${this._carouselSlideIndex * 100}%)`;
    }

    get sharedLifePills() {
        return SHARED_LIFE_PILLS.map(p => ({
            ...p,
            iconUrl: `${IMPACT_ICONS}/${p.iconFile}`
        }));
    }

    get sharedLifePhonePosts() {
        return SHARED_LIFE_PHONE_POSTS.map(post => ({
            ...post,
            badgeStyle: `background-color: ${post.badgeColor};`,
            cardStyle: `border-left-color: ${post.accentColor};`
        }));
    }

    get sharedLifeFilterPills() {
        return FEED_FILTER_PILLS.map(pill => ({
            ...pill,
            iconUrl: pill.iconFile ? `${IMPACT_ICONS}/${pill.iconFile}` : null,
            phonePillClass: pill.id === 'shared-life' ? 'phone-pill active' : 'phone-pill'
        }));
    }

    get eventTiers() {
        return EVENT_TIERS.map(t => ({
            ...t,
            iconUrl: `${IMPACT_ICONS}/${t.iconFile}`
        }));
    }

    get libraryScreen() { return WALKTHROUGH_SCREENS[4]; }

    get libraryCards() {
        return (this.libraryScreen?.libraryCards || []).map(card => ({
            ...card,
            badgeClass: `library-card-badge library-card-badge-${card.badgeToken || 'driftwood'}`
        }));
    }

    get libraryFooterNote() { return this.libraryScreen?.footerNote || ''; }
    get libraryNavHint()    { return this.libraryScreen?.navHint || ''; }
    get libraryToolboxActiveIconUrl()   { return `${IMPACT_ICONS}/ToolboxActive.png`; }
    get libraryBorrowIconUrl() { return `${IMPACT_ICONS}/borrow.png`; }

    get libraryNavHintIcons() {
        const make = (id, file, opts = {}) => ({
            id,
            iconUrl: `${IMPACT_ICONS}/${file}`,
            isCreate: !!opts.isCreate,
            itemClass: [
                'wt-nav-hint-item',
                opts.isCreate ? 'create' : '',
                opts.isActive ? 'active' : ''
            ].filter(Boolean).join(' ')
        });
        return [
            make('home', 'NeighborhoodInactive.png'),
            make('library', 'ToolboxActive.png', { isActive: true }),
            make('create', 'add.png', { isCreate: true }),
            make('messages', 'SpeechBubbleInactive.png'),
            make('mine', 'ProfileInactive.png')
        ];
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        this[`_${field}`] = event.target.value;
    }

    handleCheckboxChange(event) {
        const group = event.target.dataset.group;
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        if (group === 'careWelcome') {
            this._careWelcome = checked
                ? [...this._careWelcome, value]
                : this._careWelcome.filter(v => v !== value);
        }
    }

    handleMaskLastNameToggle(event) {
        this._maskLastName = event.target.checked;
    }

    handleMaskAvatarToggle(event) {
        this._maskAvatar = event.target.checked;
    }

    handlePhotoUploaded() {
        // Image uploader manages its own preview
    }

    handleNext() {
        if (this._currentStep === 1 && (!this._firstName?.trim() || !this._lastName?.trim())) return;
        if (this._currentStep === 3 && this.aboutFieldsFilledCount < MIN_ABOUT_FIELDS) return;

        if (this._currentStep === TOTAL_PROFILE_STEPS) {
            this._saveProfileAndExitToHome();
            return;
        }
        if (this._currentStep < TOTAL_PROFILE_STEPS) {
            this._currentStep++;
            this._scrollToTop();
        }
    }

    handleBack() {
        if (this._currentStep > 1) {
            this._currentStep--;
            this._scrollToTop();
        }
    }

    _buildProfileFieldValues() {
        const fieldValues = {
            FirstName: this._firstName?.trim() || '',
            LastName: this._lastName?.trim() || ''
        };
        if (this._pronouns?.trim()) fieldValues.Pronouns__c = this._pronouns.trim();
        if (this._aboutTenure?.trim()) fieldValues.About_Neighbourhood_Tenure__c = this._aboutTenure.trim();
        if (this._aboutBroughtYou?.trim()) fieldValues.About_What_Brought_You__c = this._aboutBroughtYou.trim();
        if (this._aboutLocalPlace?.trim()) fieldValues.About_Local_Place__c = this._aboutLocalPlace.trim();
        if (this._aboutEnjoys?.trim()) fieldValues.About_Enjoys_Doing__c = this._aboutEnjoys.trim();
        if (this._aboutFunFact?.trim()) fieldValues.About_Fun_Fact__c = this._aboutFunFact.trim();
        if (this._careWelcome.length > 0) fieldValues.Care_Welcome_Support__c = this._careWelcome.join(';');
        fieldValues.Mask_Last_Name__c = this._maskLastName ? 'true' : 'false';
        fieldValues.Mask_Avatar__c = this._maskAvatar ? 'true' : 'false';
        return fieldValues;
    }

    async _saveProfileAndExitToHome() {
        this._isSaving = true;
        try {
            await completeProfileSetup({ fieldValues: this._buildProfileFieldValues() });
            await saveQuietHoursPreference({ preference: DEFAULT_QUIET_HOURS });
            try {
                sessionStorage.setItem(TOUR_PENDING_SESSION_KEY, '1');
            } catch {
                // sessionStorage unavailable — home may not autostart tour
            }
            window.location.replace('/');
        } catch (err) {
            console.error('Error saving profile:', err);
            fireErrorToast(err, 'Something went wrong saving your profile. Please try again.');
        } finally {
            this._isSaving = false;
        }
    }

    handlePrevSlide() {
        if (this._carouselSlideIndex > 0) {
            this._carouselSlideIndex--;
        }
    }

    handleNextSlide() {
        const slides = this.sharedLifeEventsScreen?.slides || [];
        if (this._carouselSlideIndex < slides.length - 1) {
            this._carouselSlideIndex++;
        }
    }

    handleWalkthroughBack() {
        if (this._walkthroughIndex > 0) {
            this._walkthroughIndex--;
            this._carouselSlideIndex = 0;
            this._scrollToTop();
        }
    }

    handleWalkthroughNext() {
        if (!this.isLastWalkthroughScreen) {
            this._walkthroughIndex++;
            this._carouselSlideIndex = 0;
            this._scrollToTop();
        }
    }

    handleSkipWalkthrough() {
        window.location.replace('/');
    }

    async _loadExistingProfile() {
        try {
            const profile = await getProfileData();
            if (!profile) return;
            this._contactId = profile.contactId || '';
            this._firstName = profile.firstName || '';
            this._lastName = profile.lastName || '';
            this._pronouns = profile.pronouns || '';
            this._maskLastName = profile.maskLastName === true;
            this._maskAvatar = profile.maskAvatar === true;
            this._aboutTenure = profile.aboutNeighbourhoodTenure || '';
            this._aboutBroughtYou = profile.aboutWhatBroughtYou || '';
            this._aboutLocalPlace = profile.aboutLocalPlace || '';
            this._aboutEnjoys = profile.aboutEnjoysDoing || '';
            this._aboutFunFact = profile.aboutFunFact || '';
            if (profile.careWelcomeSupport) {
                this._careWelcome = profile.careWelcomeSupport.split(';').map(s => s.trim()).filter(Boolean);
            }
        } catch (err) {
            console.error('Error loading existing profile:', err);
        }
    }

    _scrollToTop() {
        const body = this.template.querySelector('.page-body');
        if (body) body.scrollTop = 0;
        try {
            window.scrollTo({ top: 0, behavior: 'instant' });
        } catch {
            window.scrollTo(0, 0);
        }
    }

    handleKeydown(event) {
        if (this._currentPhase === 2 && this.isSharedLifeEventsScreen) {
            if (event.key === 'ArrowLeft') this.handlePrevSlide();
            if (event.key === 'ArrowRight') this.handleNextSlide();
        }
    }

    _addKeyboardListener() {
        this._boundKeydown = this.handleKeydown.bind(this);
        document.addEventListener('keydown', this._boundKeydown);
    }

    _removeKeyboardListener() {
        if (this._boundKeydown) {
            document.removeEventListener('keydown', this._boundKeydown);
            this._boundKeydown = null;
        }
    }
}
