import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate } from 'c/fimbyNavigation';
import { fireToast, fireErrorToast } from 'c/fimbyToastHelper';
import getOnboardingStatus from '@salesforce/apex/FimbyOnboardingController.getOnboardingStatus';
import completeProfileSetup from '@salesforce/apex/FimbyOnboardingController.completeProfileSetup';
import saveQuietHoursPreference from '@salesforce/apex/FimbyOnboardingController.saveQuietHoursPreference';
import dismissWalkthrough from '@salesforce/apex/FimbyOnboardingController.dismissWalkthrough';
import completeWalkthrough from '@salesforce/apex/FimbyOnboardingController.completeWalkthrough';
import getProfileData from '@salesforce/apex/FimbyProfileController.getProfileData';
import searchVouchers from '@salesforce/apex/FimbyVouchController.searchVouchers';
import submitVoucherRequest from '@salesforce/apex/FimbyVouchController.submitVoucherRequest';

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

const TOTAL_PROFILE_STEPS = 6;
const VOUCH_TYPE_PEER = 'peer';
const VOUCH_TYPE_COMMUNITY_GROUP = 'community_group';
const VOUCH_SEARCH_DEBOUNCE_MS = 250;
const VOUCH_SEARCH_MIN_CHARS = 2;
const TOTAL_WALKTHROUGH_SCREENS = WALKTHROUGH_SCREENS.length;
const MIN_ABOUT_FIELDS = 2;

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
    'Ask what would be helpful today'
];

const CARE_UNHELPFUL_VALUES = [
    'Unannounced drop-ins',
    'Lots of questions at once',
    'Advice too quickly',
    'Big group attention',
    'Being posted about publicly',
    'Gifts with expectations',
    'Just pushing through talk',
    "Reaching out before I've asked",
    'Other'
];

export default class FimbyOnboardingPage extends NavigationMixin(LightningElement) {
    /* ----- phase / routing ----- */
    @track _isReady = false;
    @track _currentPhase = 1;
    @track _showPhase3AtEnd = true;
    @track _showIntroModal = false;

    /* ----- phase 1 state (mirrors fimbyOnboardingModal) ----- */
    @track _currentStep = 1;
    @track _showCelebration = false;
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
    @track _careUnhelpful = [];
    @track _careHowToAsk = [];
    @track _careHardNos = '';
    @track _careExpanded = false;
    @track _careStandingVisible = false;
    @track _maskLastName = false;
    @track _maskAvatar = false;
    @track _quietHoursPreference = '10PM_6AM';
    @track _voucherType = VOUCH_TYPE_PEER;
    @track _vouchSearchTerm = '';
    @track _vouchSearchResults = [];
    @track _selectedVoucher = null;
    @track _isVouchSearching = false;
    @track _hasVouchSearched = false;

    _vouchSearchTimeout = null;
    _vouchSearchSeq = 0;

    /* ----- phase 2 state ----- */
    @track _walkthroughIndex = 0;
    @track _carouselSlideIndex = 0;

    _boundKeydown = null;

    /* =============================
     * Lifecycle
     * ============================= */

    async connectedCallback() {
        try {
            const status = await getOnboardingStatus();
            const profileCompleted = !!status?.profileCompleted;
            const bioPostCompleted = !!status?.bioPostCompleted;

            // Always offer the bio madlib at the end of the walkthrough as long
            // as the bio hasn't been posted yet. Skip/Post both flip the flag,
            // so this naturally stops asking once the user has dealt with it.
            this._showPhase3AtEnd = !bioPostCompleted;
            this._currentPhase = profileCompleted ? 2 : 1;

            if (this._currentPhase === 1) {
                await this._loadExistingProfile();
            }
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

    /* =============================
     * Static icon URLs
     * ============================= */

    get logoUrl()         { return `${IMPACT_ICONS}/FIMBYwGrass.png`; }
    get chatIconUrl()     { return `${IMPACT_ICONS}/chat.png`; }
    get careIconUrl()     { return `${IMPACT_ICONS}/care.png`; }
    get vouchHeroIconUrl() { return `${IMPACT_ICONS}/Sapling.png`; }
    get confettiIconUrl() { return `${IMPACT_ICONS}/confetti.png`; }

    /* =============================
     * Phase routing getters
     * ============================= */

    get isReady()   { return this._isReady; }
    get isPhase1()  { return this._isReady && this._currentPhase === 1; }
    get isPhase2()  { return this._isReady && this._currentPhase === 2; }
    get showIntroModal() { return this._showIntroModal; }

    get isStep1()   { return this._currentPhase === 1 && this._currentStep === 1 && !this._showCelebration; }
    get isStep2()   { return this._currentPhase === 1 && this._currentStep === 2 && !this._showCelebration; }
    get isStep3()   { return this._currentPhase === 1 && this._currentStep === 3 && !this._showCelebration; }
    get isStep4()   { return this._currentPhase === 1 && this._currentStep === 4 && !this._showCelebration; }
    get isStep5()   { return this._currentPhase === 1 && this._currentStep === 5 && !this._showCelebration; }
    get isStep6()   { return this._currentPhase === 1 && this._currentStep === 6 && !this._showCelebration; }
    get showCelebration() { return this._showCelebration; }
    get canGoBack() { return this._currentStep > 1 && !this._showCelebration; }

    /* =============================
     * Computed - profile step state
     * ============================= */

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

    get firstName()         { return this._firstName; }
    get lastName()          { return this._lastName; }
    get pronouns()          { return this._pronouns; }
    get aboutTenure()       { return this._aboutTenure; }
    get aboutBroughtYou()   { return this._aboutBroughtYou; }
    get aboutLocalPlace()   { return this._aboutLocalPlace; }
    get aboutEnjoys()       { return this._aboutEnjoys; }
    get aboutFunFact()      { return this._aboutFunFact; }
    get careHardNos()       { return this._careHardNos; }
    get selectedVoucher() { return this._selectedVoucher; }
    get vouchSearchTerm() { return this._vouchSearchTerm; }
    get vouchSearchResults() { return this._vouchSearchResults; }

    get isVouchPeerType() {
        return this._voucherType === VOUCH_TYPE_PEER;
    }

    get isVouchCommunityGroupType() {
        return this._voucherType === VOUCH_TYPE_COMMUNITY_GROUP;
    }

    get vouchPeerToggleClass() {
        return this.isVouchPeerType ? 'toggle-option toggle-option_active' : 'toggle-option';
    }

    get vouchCgToggleClass() {
        return this.isVouchCommunityGroupType ? 'toggle-option toggle-option_active' : 'toggle-option';
    }

    get vouchSearchPlaceholder() {
        return this.isVouchPeerType
            ? 'Start typing a neighbour\u2019s name\u2026'
            : 'Start typing a community group or church\u2026';
    }

    get showVouchResults() {
        return !this._selectedVoucher && this._vouchSearchResults.length > 0;
    }

    get showVouchNoResults() {
        return !this._selectedVoucher
            && this._hasVouchSearched
            && !this._isVouchSearching
            && this._vouchSearchResults.length === 0
            && this._vouchSearchTerm.trim().length >= VOUCH_SEARCH_MIN_CHARS;
    }
    get isSaving()          { return this._isSaving; }
    get contactId()         { return this._contactId; }

    get personalizedGreeting() {
        return this._firstName ? `Nice to meet you, ${this._firstName}, tell us about yourself` : 'Tell us about yourself';
    }

    get aboutFieldsFilledCount() {
        const filled = [
            this._aboutTenure,
            this._aboutBroughtYou,
            this._aboutLocalPlace,
            this._aboutEnjoys,
            this._aboutFunFact
        ].filter(v => v && v.trim()).length;
        return filled;
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
        if (this._currentStep === TOTAL_PROFILE_STEPS) return 'Request a vouch';
        return 'Next';
    }

    get isNextDisabled() {
        if (this._isSaving) return true;
        if (this._currentStep === 1) {
            return !this._firstName?.trim() || !this._lastName?.trim();
        }
        if (this._currentStep === 3) {
            return this.aboutFieldsFilledCount < MIN_ABOUT_FIELDS;
        }
        if (this._currentStep === TOTAL_PROFILE_STEPS) {
            return !this._isVouchStep6Valid;
        }
        return false;
    }

    get _isVouchStep6Valid() {
        return !!this._selectedVoucher;
    }

    get careWelcomeOptions() {
        return CARE_WELCOME_VALUES.map(val => ({
            value: val,
            label: val,
            checked: this._careWelcome.includes(val)
        }));
    }

    get careHowToAskOptions() {
        return CARE_HOW_TO_ASK_VALUES.map(val => ({
            value: val,
            label: val,
            checked: this._careHowToAsk.includes(val)
        }));
    }

    get careExpanded() { return this._careExpanded; }
    get careStandingVisible() { return this._careStandingVisible; }
    get maskLastName() { return this._maskLastName; }
    get maskAvatar() { return this._maskAvatar; }
    get careExpanderLabel() {
        return this._careExpanded
            ? 'Hide optional care questions'
            : 'Want to share a bit more about how neighbours can care for you? (optional)';
    }

    get careUnhelpfulOptions() {
        return CARE_UNHELPFUL_VALUES.map(val => ({
            value: val,
            label: val,
            checked: this._careUnhelpful.includes(val)
        }));
    }

    get quietHoursOptions() {
        const pref = this._quietHoursPreference;
        return [
            { value: '9PM_5AM', label: '9 PM \u2013 5 AM', checked: pref === '9PM_5AM' },
            { value: '10PM_6AM', label: '10 PM \u2013 6 AM', checked: pref === '10PM_6AM' },
            { value: '11PM_7AM', label: '11 PM \u2013 7 AM', checked: pref === '11PM_7AM' },
            { value: '12AM_8AM', label: '12 AM \u2013 8 AM', checked: pref === '12AM_8AM' },
            { value: 'NONE', label: 'No quiet hours \u2013 notify me anytime', checked: pref === 'NONE' }
        ];
    }

    /* =============================
     * Walkthrough screen state
     * ============================= */

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

    get currentScreen() {
        return WALKTHROUGH_SCREENS[this._walkthroughIndex];
    }

    get currentScreenId() {
        return this.currentScreen?.id || '';
    }

    get isVisionScreen()        { return this.currentScreenId === SCREEN_IDS.VISION; }
    get isFeedScreen()          { return this.currentScreenId === SCREEN_IDS.FEED; }
    get isAskOfferScreen()      { return this.currentScreenId === SCREEN_IDS.ASK_OFFER; }
    get isSharedLifeEventsScreen() { return this.currentScreenId === SCREEN_IDS.SHARED_LIFE_EVENTS; }
    get isLibraryScreen()       { return this.currentScreenId === SCREEN_IDS.LIBRARY; }

    get isLastWalkthroughScreen() { return this._walkthroughIndex >= TOTAL_WALKTHROUGH_SCREENS - 1; }
    get isFirstWalkthroughScreen() { return this._walkthroughIndex === 0; }
    get isLoading() { return !this._isReady; }

    /* ---- Screen 1 ---- */
    get visionContent() { return WALKTHROUGH_SCREENS[0]; }

    /* ---- Screen 2 - Feed mock ---- */
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
            const base = 'phone-nav-item';
            const phoneItemClass = [
                base,
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

    /* ---- Screen 3 - Ask / Offer / Bulk Buy ---- */
    get askOfferContent() { return WALKTHROUGH_SCREENS[2]; }
    get askOfferPlusIconUrl() { return `${IMPACT_ICONS}/add.png`; }

    get quickPostTiles() {
        return QUICK_POST_TILES.map(tile => ({
            ...tile,
            iconUrl: `${IMPACT_ICONS}/${tile.iconFile}`
        }));
    }

    /* ---- Screen 4 - Shared Life + Events carousel ---- */
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

    get currentCarouselSlideId() {
        return this.currentCarouselSlide?.id || '';
    }

    get isCarouselSharedLifeSlide() {
        return this.currentCarouselSlideId === 'shared-life';
    }

    get isCarouselEventsSlide() {
        return this.currentCarouselSlideId === 'events';
    }

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

    // Same filter pill set as Screen 2, but with "Shared Life" highlighted
    // to give the phone-frame the right context for Slide 4a.
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

    /* ---- Screen 5 - Library ---- */
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
    get libraryToolboxInactiveIconUrl() { return `${IMPACT_ICONS}/ToolboxInactive.png`; }
    get libraryBorrowIconUrl() { return `${IMPACT_ICONS}/borrow.png`; }

    // Faux desktop header strip used in the nav hint. Mirrors the 5-tab
    // order in fimbyUniversalHeader. Only the Library tab is lit (active
    // icon + teal underline indicator).
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
            make('home',     'NeighborhoodInactive.png'),
            make('library',  'ToolboxActive.png', { isActive: true }),
            make('create',   'add.png', { isCreate: true }),
            make('messages', 'SpeechBubbleInactive.png'),
            make('mine',     'ProfileInactive.png')
        ];
    }

    /* =============================
     * Input handlers
     * ============================= */

    handleInputChange(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        const stateKey = `_${field}`;
        this[stateKey] = event.target.value;
    }

    handleCheckboxChange(event) {
        const group = event.target.dataset.group;
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        const stateKey = `_${group}`;
        if (group === 'careWelcome' || group === 'careUnhelpful' || group === 'careHowToAsk') {
            if (checked) {
                this[stateKey] = [...this[stateKey], value];
            } else {
                this[stateKey] = this[stateKey].filter(v => v !== value);
            }
        }
    }

    handleCareExpanderToggle() {
        this._careExpanded = !this._careExpanded;
    }

    handleCareStandingToggle(event) {
        this._careStandingVisible = event.target.checked;
    }

    handleMaskLastNameToggle(event) {
        this._maskLastName = event.target.checked;
    }

    handleMaskAvatarToggle(event) {
        this._maskAvatar = event.target.checked;
    }

    handleQuietHoursChange(event) {
        this._quietHoursPreference = event.target.value;
    }

    handlePhotoUploaded() {
        // Image uploader manages its own preview
    }

    handleVouchSelectType(event) {
        const nextType = event.currentTarget.dataset.type;
        if (!nextType || nextType === this._voucherType) return;
        this._voucherType = nextType;
        this._vouchSearchTerm = '';
        this._vouchSearchResults = [];
        this._selectedVoucher = null;
        this._hasVouchSearched = false;
        clearTimeout(this._vouchSearchTimeout);
    }

    handleVouchSearchInput(event) {
        this._vouchSearchTerm = event.target.value;
        clearTimeout(this._vouchSearchTimeout);
        if (this._vouchSearchTerm.trim().length < VOUCH_SEARCH_MIN_CHARS) {
            this._vouchSearchResults = [];
            this._hasVouchSearched = false;
            this._isVouchSearching = false;
            return;
        }
        this._isVouchSearching = true;
        this._vouchSearchTimeout = setTimeout(() => this._doVouchSearch(), VOUCH_SEARCH_DEBOUNCE_MS);
    }

    _doVouchSearch() {
        const seq = ++this._vouchSearchSeq;
        searchVouchers({ searchTerm: this._vouchSearchTerm.trim(), voucherType: this._voucherType })
            .then(results => {
                if (seq !== this._vouchSearchSeq) return;
                this._vouchSearchResults = Array.isArray(results) ? results : [];
                this._hasVouchSearched = true;
                this._isVouchSearching = false;
            })
            .catch(() => {
                if (seq !== this._vouchSearchSeq) return;
                this._vouchSearchResults = [];
                this._hasVouchSearched = true;
                this._isVouchSearching = false;
            });
    }

    handleVouchSelectResult(event) {
        const id = event.currentTarget.dataset.id;
        const match = this._vouchSearchResults.find(r => r.id === id);
        if (!match) return;
        this._selectedVoucher = match;
        this._vouchSearchResults = [];
        this._vouchSearchTerm = match.name;
    }

    handleVouchClearSelection() {
        this._selectedVoucher = null;
        this._vouchSearchTerm = '';
        this._vouchSearchResults = [];
        this._hasVouchSearched = false;
    }

    /* =============================
     * Phase 1 navigation
     * ============================= */

    handleNext() {
        if (this._currentStep === 1 && (!this._firstName?.trim() || !this._lastName?.trim())) return;
        if (this._currentStep === 3 && this.aboutFieldsFilledCount < MIN_ABOUT_FIELDS) return;

        if (this._currentStep === 5) {
            this._saveProfileAndAdvanceToVouchStep();
            return;
        }
        if (this._currentStep < TOTAL_PROFILE_STEPS) {
            this._currentStep++;
            this._scrollToTop();
            return;
        }
        this._submitVouchAndCelebrate();
    }

    handleBack() {
        if (this._currentStep > 1) {
            this._currentStep--;
            this._scrollToTop();
        }
    }

    handleSkipIntroduction() {
        this._showCelebration = true;
        this._scrollToTop();
    }

    async _saveProfileAndAdvanceToVouchStep() {
        this._isSaving = true;
        try {
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
            if (this._careUnhelpful.length > 0) fieldValues.Care_Unhelpful_Things__c = this._careUnhelpful.join(';');
            if (this._careHowToAsk.length > 0) fieldValues.Care_How_To_Ask__c = this._careHowToAsk.join(';');
            if (this._careHardNos?.trim()) fieldValues.Care_Hard_Nos__c = this._careHardNos.trim();
            if (this._careStandingVisible) fieldValues.Care_Standing_Visible__c = 'true';
            fieldValues.Mask_Last_Name__c = this._maskLastName ? 'true' : 'false';
            fieldValues.Mask_Avatar__c = this._maskAvatar ? 'true' : 'false';

            await completeProfileSetup({ fieldValues });
            if (this._quietHoursPreference) {
                await saveQuietHoursPreference({ preference: this._quietHoursPreference });
            }
            this._currentStep = TOTAL_PROFILE_STEPS;
            this._scrollToTop();
        } catch (err) {
            console.error('Error saving profile:', err);
            fireErrorToast(err, 'Something went wrong saving your profile. Please try again.');
        } finally {
            this._isSaving = false;
        }
    }

    async _submitVouchAndCelebrate() {
        if (!this._isVouchStep6Valid) return;
        this._isSaving = true;
        try {
            const result = await submitVoucherRequest({
                voucherType: this._selectedVoucher.voucherType,
                referenceId: this._selectedVoucher.id
            });
            if (result?.delivered === true || result?.alreadyHasPending === true) {
                this._showCelebration = true;
                this._scrollToTop();
                return;
            }
            fireToast({
                message: result?.message || 'Something went wrong sending your vouch request. Please try again or skip for now.',
                variant: 'error'
            });
        } catch (err) {
            console.error('Error submitting vouch request:', err);
            fireErrorToast(err, 'Something went wrong sending your vouch request. Please try again or skip for now.');
        } finally {
            this._isSaving = false;
        }
    }

    /* =============================
     * Phase 1 -> Phase 2 transition
     * ============================= */

    handleStartTour() {
        this._showCelebration = false;
        this._currentPhase = 2;
        this._walkthroughIndex = 0;
        this._carouselSlideIndex = 0;
        this._scrollToTop();
    }

    handleSkipTour() {
        this._dismissAndExit(false);
    }

    /* =============================
     * Phase 2 navigation
     * ============================= */

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
            return;
        }
        this._finishWalkthrough();
    }

    handleSkipWalkthrough() {
        this._dismissAndExit(false);
    }

    async _finishWalkthrough() {
        try {
            await completeWalkthrough();
        } catch (err) {
            console.error('Error completing walkthrough:', err);
        }
        if (this._showPhase3AtEnd) {
            this._showIntroModal = true;
            // The intro post modal is gated by lwc:if={showIntroModal} so it
            // mounts on the next render tick. Poll briefly until it's queryable
            // (covers slow renders without depending on a single rAF).
            this._showIntroModalWhenReady();
            return;
        }
        this._exitToHome();
    }

    _showIntroModalWhenReady(attempt = 0) {
        const modal = this.template.querySelector('c-fimby-intro-post-modal');
        if (modal && typeof modal.show === 'function') {
            modal.show();
            return;
        }
        if (attempt >= 20) {
            console.warn('fimbyOnboardingPage: intro post modal failed to mount');
            return;
        }
        // ~16ms per tick × 20 attempts = ~320ms before giving up
        setTimeout(() => this._showIntroModalWhenReady(attempt + 1), 16);
    }

    async _dismissAndExit(permanent) {
        try {
            await dismissWalkthrough({ permanent });
        } catch (err) {
            console.error('Error dismissing walkthrough:', err);
        }
        this._exitToHome();
    }

    /* =============================
     * Phase 3 (intro post modal)
     * ============================= */

    handleBioPosted() {
        this._showIntroModal = false;
        this._exitToHome();
    }

    handleBioSkipped() {
        this._showIntroModal = false;
        this._exitToHome();
    }

    _exitToHome() {
        // Experience Cloud's home page is at the site root, not '/home'.
        window.location.replace('/');
    }

    /* =============================
     * Internal helpers
     * ============================= */

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
            this._careHowToAsk = profile.careHowToAsk
                ? profile.careHowToAsk.split(';').map(s => s.trim()).filter(Boolean)
                : [];
            this._careStandingVisible = profile.careStandingVisible === true;
            this._careHardNos = profile.careHardNos || '';
            if (profile.careWelcomeSupport) {
                this._careWelcome = profile.careWelcomeSupport.split(';').map(s => s.trim()).filter(Boolean);
            }
            if (profile.careUnhelpfulThings) {
                this._careUnhelpful = profile.careUnhelpfulThings.split(';').map(s => s.trim()).filter(Boolean);
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
        } catch (_e) {
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
}
