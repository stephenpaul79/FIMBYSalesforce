import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';
import {
    getTourAnchorRect,
    getTourChromeInsets,
    waitForTourAnchorRect
} from 'c/fimbyGuidedTourAnchorRegistry';
import {
    getFilteredSteps,
    getProgressLabel,
    getVineStage,
    TRACK_EXTENDED,
    TRACK_FINALE
} from './fimbyGuidedTourContent';
import TOUR_ICONS from '@salesforce/resourceUrl/Icons';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getLiveTourState from '@salesforce/apex/FimbyGuidedTourController.getLiveTourState';
import setLiveTourStatus from '@salesforce/apex/FimbyGuidedTourController.setLiveTourStatus';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import {
    ensureHomeFeedReadyForTour,
    isHomePath
} from 'c/fimbyGuidedTourLauncher';

const MOBILE_BP = 892;
const PAD = 8;
const CALLOUT_GAP = 12;
const MOBILE_BUBBLE_NAV_GAP = 12;
const MOBILE_CALLOUT_LIFT = 112;
const MOBILE_BOTTOM_NAV_FALLBACK_INSET = 72;
const MOBILE_MENU_BUBBLE_TOP_OFFSET = 52;
const CALLOUT_MAX_WIDTH = 'min(18rem, calc(100vw - 2rem))';
const BOTTOM_NAV_ANCHORS = new Set([
    'nav-home',
    'nav-library',
    'nav-create',
    'nav-messages',
    'nav-mine'
]);
const STATUS_COMPLETED = 'Completed';
const STATUS_DISMISSED = 'Dismissed';

export default class FimbyGuidedTour extends NavigationMixin(LightningElement) {
    @track isActive = false;
    @track _steps = [];
    @track _stepIndex = 0;
    @track _spotlight = null;
    @track _bubbleStyle = '';
    @track _bubbleClass = 'bubble bubble-center';
    @track _calloutStyle = '';
    @track _calloutPointerStyle = '';
    @track _calloutEdgeAlign = '';
    @track _calloutArrowPointsUp = true;
    @track _replay = false;
    @track _extendedTaken = false;
    @track _bioPostCompleted = true;
    @track _hasMultipleIdentities = false;
    @track _awaitingModalDismiss = false;
    @track _modalPassThrough = false;
    @track _stepActionComplete = false;
    @track _actionRevealed = false;

    _revealNavigatedAway = false;
    _resizeHandler;
    _scrollHandler;
    _clickCaptureHandler;
    _quickPostClosedHandler;
    _searchClosedHandler;
    _searchOpenedHandler;
    _menuOpenedHandler;
    _modalAnchorPollId = null;
    _pendingCalloutAnchorX = null;
    _focusableSelector = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';

    @wire(CurrentPageReference)
    wiredPageRef() {
        if (this.isActive) {
            this._checkRouteActionComplete();
            this._checkWaitAnchorComplete();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => this._measureAndPosition());
        }
    }

    connectedCallback() {
        this._resizeHandler = () => this._measureAndPosition();
        this._scrollHandler = () => this._measureAndPosition();
        window.addEventListener('resize', this._resizeHandler);
        window.addEventListener('scroll', this._scrollHandler, true);

        this._clickCaptureHandler = (event) => this._handleDocumentClick(event);

        this._quickPostClosedHandler = (event) => {
            if (this.isActive && this.currentStep?.id === 'create') {
                if (event.detail?.selected) {
                    return;
                }
                this._enterModalStepReveal({ navigatedAway: false });
            }
        };
        this._quickPostOpenedHandler = () => {
            if (
                !this.isActive ||
                this.currentStep?.id !== 'create' ||
                this._modalPassThrough
            ) {
                return;
            }
            this._beginModalPassThrough(this.currentStep);
        };
        this._quickPostOptionHandler = () => {
            if (this.isActive && this.currentStep?.id === 'create') {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                requestAnimationFrame(() => {
                    if (
                        this.isActive &&
                        this.currentStep?.id === 'create' &&
                        !this._stepActionComplete
                    ) {
                        this._enterModalStepReveal({ navigatedAway: true });
                    }
                });
            }
        };
        this._searchClosedHandler = (event) => {
            if (this.isActive && this.currentStep?.opensSearch) {
                this._enterModalStepReveal({
                    navigatedAway: !!event.detail?.navigatedAway
                });
            }
        };
        this._searchOpenedHandler = () => {
            if (
                !this.isActive ||
                !this.currentStep?.opensSearch ||
                this._modalPassThrough
            ) {
                return;
            }
            this._beginModalPassThrough(this.currentStep);
        };
        this._menuOpenedHandler = () => {
            if (this.isActive && this.currentStep?.id === 'menu') {
                this._markStepActionComplete();
            }
            if (this.isActive && this.currentStep?.menuGuided) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                requestAnimationFrame(() => this._measureAndPosition());
            }
        };

        window.addEventListener('fimbyquickpostclosed', this._quickPostClosedHandler);
        window.addEventListener('fimbyquickpostopened', this._quickPostOpenedHandler);
        window.addEventListener('fimbyquickpostoptionselected', this._quickPostOptionHandler);
        window.addEventListener('fimbysearchclosed', this._searchClosedHandler);
        window.addEventListener('fimbysearchopened', this._searchOpenedHandler);
        window.addEventListener('fimbytouropenmenu', this._menuOpenedHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this._resizeHandler);
        window.removeEventListener('scroll', this._scrollHandler, true);
        window.removeEventListener('click', this._clickCaptureHandler, true);
        window.removeEventListener('fimbyquickpostclosed', this._quickPostClosedHandler);
        window.removeEventListener('fimbyquickpostopened', this._quickPostOpenedHandler);
        window.removeEventListener('fimbyquickpostoptionselected', this._quickPostOptionHandler);
        window.removeEventListener('fimbysearchclosed', this._searchClosedHandler);
        window.removeEventListener('fimbysearchopened', this._searchOpenedHandler);
        window.removeEventListener('fimbytouropenmenu', this._menuOpenedHandler);
        this._stopModalAnchorPoll();
        document.body.classList.remove('fimby-modal-open');
    }

    get currentStep() {
        return this._steps[this._stepIndex] || {};
    }

    get showScrim() {
        if (this._modalPassThrough || this.currentStep.menuGuided) {
            return false;
        }
        return this._showActionHighlight;
    }

    get showBubble() {
        return !this._modalPassThrough;
    }

    get _showActionHighlight() {
        if (this._modalPassThrough) {
            return true;
        }
        const step = this.currentStep;
        if (
            (step.advance === 'clickTarget' || step.advance === 'modalDismiss') &&
            this._stepActionComplete
        ) {
            return false;
        }
        return true;
    }

    get showMainDialog() {
        return this.showBubble && !this._modalPassThrough;
    }

    get mainDialogClass() {
        if (this.currentStep.menuGuided) {
            return this._bubbleClass || 'bubble bubble-docked';
        }
        if (this.isIntroPost || (this.currentStep.placement === 'center' && !this.currentStep.anchor)) {
            return 'bubble bubble-center';
        }
        if (this.isOffRamp) {
            return 'bubble bubble-docked';
        }
        return this._bubbleClass || 'bubble bubble-docked';
    }

    get showModalCoach() {
        if (this.currentStep.hideModalCoach) {
            return false;
        }
        return this._modalPassThrough;
    }

    get hasSpotlight() {
        if (this._modalPassThrough) {
            return false;
        }
        if (!this._spotlight) {
            return false;
        }
        if (this.currentStep.menuGuided) {
            return true;
        }
        if (!this._showActionHighlight) {
            return false;
        }
        return this.currentStep.placement !== 'center';
    }

    get showCallout() {
        if (!this._showActionHighlight) {
            return false;
        }
        const step = this.currentStep;
        if (!this.calloutLabel) {
            return false;
        }
        if (this.currentStep.menuGuided && this.hasSpotlight) {
            return !!this._calloutStyle;
        }
        if (this._modalPassThrough && step.advance === 'modalDismiss') {
            return !!this._calloutStyle;
        }
        if (!this.hasSpotlight) {
            return false;
        }
        return step.advance === 'clickTarget' || step.advance === 'modalDismiss';
    }

    get calloutLabel() {
        const step = this.currentStep;
        if (this._modalPassThrough && step.modalActionLabel) {
            return step.modalActionLabel;
        }
        return step.actionLabel || '';
    }

    get calloutSublabel() {
        const step = this.currentStep;
        if (this._modalPassThrough && step.modalActionSublabel) {
            return step.modalActionSublabel;
        }
        return '';
    }

    get calloutSrLabel() {
        const sub = this.calloutSublabel;
        return sub ? `${this.calloutLabel}. ${sub}` : this.calloutLabel;
    }

    get modalCoachHint() {
        return this.currentStep.modalCoachHint || 'Close this menu when you are ready, then tap Next.';
    }

    get calloutStyle() {
        return this._calloutStyle;
    }

    get calloutPointerClass() {
        return this._calloutEdgeAlign === 'right'
            ? 'callout-pointer callout-pointer-edge-right'
            : 'callout-pointer';
    }

    get calloutPointerStyle() {
        return this._calloutPointerStyle;
    }

    get calloutArrowPointsUp() {
        return this._calloutArrowPointsUp;
    }

    get calloutArrowPointsDown() {
        return !this._calloutArrowPointsUp;
    }

    get scrimTopStyle() {
        return this._panelStyle(0, 0, window.innerWidth, this._spotlight.top - PAD);
    }

    get scrimLeftStyle() {
        return this._panelStyle(0, this._spotlight.top - PAD, this._spotlight.left - PAD, this._spotlight.height + PAD * 2);
    }

    get scrimRightStyle() {
        const left = this._spotlight.left + this._spotlight.width + PAD;
        return this._panelStyle(left, this._spotlight.top - PAD, window.innerWidth - left, this._spotlight.height + PAD * 2);
    }

    get scrimBottomStyle() {
        const top = this._spotlight.top + this._spotlight.height + PAD;
        return this._panelStyle(0, top, window.innerWidth, window.innerHeight - top);
    }

    get spotlightRingStyle() {
        const s = this._spotlight;
        return `left:${s.left - PAD}px;top:${s.top - PAD}px;width:${s.width + PAD * 2}px;height:${s.height + PAD * 2}px;`;
    }

    get bubbleStyle() {
        return this._bubbleStyle;
    }

    get bubbleClass() {
        return this._bubbleClass;
    }

    get progressLabel() {
        return getProgressLabel(this.currentStep, this._stepIndex, this._steps, this._trackPhase);
    }

    get showProgressSection() {
        return !!this.progressLabel || !!this.vineUrl;
    }

    get showBubbleHeaderRow() {
        return !!(this.stepIconUrl || this.progressLabel || this.vineUrl);
    }

    get vineUrl() {
        const stage = getVineStage(this.currentStep, this._trackPhase);
        if (!stage) {
            return null;
        }
        return `${TOUR_ICONS}/Vine${stage}.png`;
    }

    get stepIconUrl() {
        const file = this.currentStep.iconFile;
        return file ? `${IMPACT_ICONS}/${file}` : null;
    }

    get heroImageUrl() {
        const file = this.currentStep.heroImage;
        return file ? `${TOUR_ICONS}/${file}` : null;
    }

    get heroAlt() {
        return this.currentStep.heroAlt || '';
    }

    get displayTitle() {
        const step = this.currentStep;
        if (this._actionRevealed && step.advance === 'modalDismiss') {
            if (this._revealNavigatedAway && step.revealNavigateTitle) {
                return step.revealNavigateTitle;
            }
            if (step.revealTitle) {
                return step.revealTitle;
            }
        }
        return step.title || '';
    }

    get displayBody() {
        const step = this.currentStep;
        if (this._actionRevealed && step.advance === 'modalDismiss') {
            if (this._revealNavigatedAway && step.revealNavigateBody) {
                return step.revealNavigateBody;
            }
            if (step.revealBody) {
                return step.revealBody;
            }
        }
        if (this._isMobile() && step.mobileBody) {
            return step.mobileBody;
        }
        return step.body || '';
    }

    get isOffRamp() {
        return this.currentStep.advance === 'offRampChoice';
    }

    get isIntroPost() {
        return this.currentStep.advance === 'introPost';
    }

    get isExtendedFinish() {
        return !!this.currentStep.showFinishOnly;
    }

    get isNextDisabled() {
        const mode = this.currentStep.advance;
        if (mode === 'clickTarget' || mode === 'modalDismiss') {
            return !this._stepActionComplete;
        }
        return false;
    }

    get _trackPhase() {
        return this.currentStep.track || 'essentials';
    }

    _panelStyle(left, top, width, height) {
        return `left:${Math.max(0, left)}px;top:${Math.max(0, top)}px;width:${Math.max(0, width)}px;height:${Math.max(0, height)}px;`;
    }

    /** @param {Object} options @param {boolean} [options.replay] */
    @api
    async startTour(options = {}) {
        this._replay = !!options.replay;
        let hasMultipleIdentities = false;
        let bioPostCompleted = true;

        try {
            const [identities, state] = await Promise.all([
                getAvailableIdentities(),
                getLiveTourState()
            ]);
            hasMultipleIdentities = (identities || []).length > 0;
            bioPostCompleted = !!state?.bioPostCompleted;
            this._bioPostCompleted = bioPostCompleted;
            this._hasMultipleIdentities = hasMultipleIdentities;
        } catch (err) {
            console.error('fimbyGuidedTour startTour', err);
        }

        const includeFinale = !this._replay && !bioPostCompleted;
        this._steps = getFilteredSteps({
            includeExtended: false,
            includeFinale,
            hasMultipleIdentities
        });
        this._stepIndex = 0;
        this._extendedTaken = false;
        this.isActive = true;
        document.body.classList.add('fimby-modal-open');
        window.addEventListener('click', this._clickCaptureHandler, true);

        if (isHomePath()) {
            await ensureHomeFeedReadyForTour();
        }

        await this._prepareCurrentStep();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this._measureAndPosition();
            this._trapFocus();
        });
    }

    @api
    endTour() {
        this.isActive = false;
        this._spotlight = null;
        this._calloutStyle = '';
        this._calloutPointerStyle = '';
        this._calloutEdgeAlign = '';
        this._modalPassThrough = false;
        this._stopModalAnchorPoll();
        window.removeEventListener('click', this._clickCaptureHandler, true);
        document.body.classList.remove('fimby-modal-open');
    }

    async _prepareCurrentStep() {
        const step = this.currentStep;
        if (!step) {
            return;
        }

        this._awaitingModalDismiss = false;
        this._modalPassThrough = false;
        this._actionRevealed = false;
        this._revealNavigatedAway = false;
        this._stopModalAnchorPoll();
        this._stepActionComplete = step.advance === 'next' && !step.menuGuided;

        if (step.id === 'feed-filters' || step.id === 'extended-complete') {
            await ensureHomeFeedReadyForTour();
        }

        if (step.menuGuided) {
            window.dispatchEvent(new CustomEvent('fimbytouropenmenu'));
            await waitForTourAnchorRect(step.anchor, { timeoutMs: 3000 });
            if (step.route) {
                navigate(this, step.route);
                await new Promise((resolve) => {
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    requestAnimationFrame(() => requestAnimationFrame(resolve));
                });
            }
        } else {
            window.dispatchEvent(new CustomEvent('fimbytourclosemenu'));
        }

        if (step.menuGuided) {
            this._stepActionComplete = true;
            this._bubbleClass = 'bubble bubble-docked';
            this._bubbleStyle = '';
        }

        if (step.waitAnchor && getTourAnchorRect(step.waitAnchor)) {
            this._markStepActionComplete();
        }

        this._checkRouteActionComplete();

        if (this._isMobile()) {
            this._applyMobileBubbleForStep(step, step.anchor || '');
        }
    }

    _isMobile() {
        return window.innerWidth < MOBILE_BP;
    }

    _isBottomNavAnchor(name) {
        return !!name && BOTTOM_NAV_ANCHORS.has(name);
    }

    _getMobileBottomInset() {
        if (!this._isMobile()) {
            return 0;
        }
        return getTourChromeInsets().bottom || 0;
    }

    _applyMobileBubbleForStep(step, anchorName = '') {
        if (!this._isMobile()) {
            return;
        }
        if (step?.menuGuided) {
            this._applyMobileMenuBubbleLayout(step);
            return;
        }
        this._applyMobileBubbleLayout({
            anchorName: anchorName || step?.anchor || ''
        });
    }

    _applyMobileMenuBubbleLayout(step) {
        if (step?.mobileBubbleTop) {
            this._bubbleClass = 'bubble bubble-docked bubble-mobile-top';
            this._bubbleStyle =
                'bottom:auto;' +
                `top:calc(env(safe-area-inset-top, 0px) + ${MOBILE_MENU_BUBBLE_TOP_OFFSET}px);`;
            return;
        }
        this._applyMobileBubbleLayout({ anchorName: step?.anchor || '' });
    }

    _applyMobileBubbleLayout({ anchorName = '' } = {}) {
        if (!this._isMobile()) {
            return;
        }
        let inset = this._getMobileBottomInset();
        if (inset <= 0) {
            inset = MOBILE_BOTTOM_NAV_FALLBACK_INSET;
        }
        if (inset <= 0) {
            return;
        }
        const step = this.currentStep;
        let extraLift = 0;
        if (
            this._showActionHighlight &&
            step?.actionLabel &&
            this._isBottomNavAnchor(anchorName)
        ) {
            extraLift = MOBILE_CALLOUT_LIFT;
        }
        this._bubbleClass = 'bubble bubble-docked bubble-mobile-nav-aware';
        this._bubbleStyle = `bottom:${inset + MOBILE_BUBBLE_NAV_GAP + extraLift}px;`;
    }

    _resolveAnchorName(step) {
        if (this._modalPassThrough && step.modalAnchor) {
            const modalRect = getTourAnchorRect(step.modalAnchor);
            if (modalRect) {
                return step.modalAnchor;
            }
        }
        return step.anchor;
    }

    _markStepActionComplete() {
        if (!this._stepActionComplete) {
            this._stepActionComplete = true;
            if (this.currentStep?.advance === 'clickTarget') {
                this._enterContentReveal();
            }
        }
    }

    _enterModalStepReveal({ navigatedAway = false } = {}) {
        const step = this.currentStep;
        if (this._stepActionComplete || step?.advance !== 'modalDismiss') {
            return;
        }
        this._revealNavigatedAway = navigatedAway;
        this._actionRevealed = true;
        this._awaitingModalDismiss = false;
        this._modalPassThrough = false;
        this._stopModalAnchorPoll();
        this._stepActionComplete = true;
        this._enterContentReveal();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this._trapFocus());
    }

    _enterContentReveal() {
        this._spotlight = null;
        this._calloutStyle = '';
        this._calloutPointerStyle = '';
        this._calloutEdgeAlign = '';
        this._bubbleClass = 'bubble bubble-docked';
        this._bubbleStyle = '';
        this._applyMobileBubbleForStep(this.currentStep, this.currentStep?.anchor || '');
    }

    _checkRouteActionComplete() {
        const step = this.currentStep;
        if (!step?.route || step.advance !== 'clickTarget') {
            return;
        }
        const routeKey = step.route.replace(/^\//, '').split('?')[0];
        const path = window.location.pathname || '';
        if (path.includes(routeKey)) {
            this._markStepActionComplete();
        }
    }

    _checkWaitAnchorComplete() {
        const step = this.currentStep;
        if (!step?.waitAnchor || step.advance !== 'clickTarget' || this._stepActionComplete) {
            return;
        }
        if (getTourAnchorRect(step.waitAnchor)) {
            this._markStepActionComplete();
        }
    }

    _handleDocumentClick(event) {
        if (!this.isActive || this._modalPassThrough || this._stepActionComplete) {
            return;
        }
        const step = this.currentStep;
        if (step.advance !== 'clickTarget' && step.advance !== 'modalDismiss') {
            return;
        }

        const anchorName = step.anchor;
        if (!anchorName) {
            return;
        }

        const rect = getTourAnchorRect(anchorName);
        if (!rect) {
            return;
        }

        const { clientX, clientY } = event;
        const inAnchor =
            clientX >= rect.left &&
            clientX <= rect.right &&
            clientY >= rect.top &&
            clientY <= rect.bottom;

        if (!inAnchor) {
            return;
        }

        if (step.advance === 'modalDismiss') {
            this._openModalForStep(step);
            event.preventDefault();
            event.stopPropagation();
            return;
        }

        if (step.id === 'feed-filters') {
            this._markStepActionComplete();
            return;
        }

        if (step.route) {
            this._markStepActionComplete();
            return;
        }

        this._markStepActionComplete();
    }

    async _measureAndPosition() {
        const step = this.currentStep;
        if (!step || !this.isActive) {
            return;
        }

        if (
            this._stepActionComplete &&
            !this._modalPassThrough &&
            (step.advance === 'clickTarget' || step.advance === 'modalDismiss')
        ) {
            this._enterContentReveal();
            return;
        }

        if (this._modalPassThrough && step.advance === 'modalDismiss') {
            this._spotlight = null;
            if (step.modalCalloutFixedTop) {
                this._positionModalPassThroughCallout();
            } else {
                const modalRect = step.modalAnchor
                    ? getTourAnchorRect(step.modalAnchor)
                    : null;
                if (modalRect) {
                    this._positionCallout(modalRect, 'top');
                } else {
                    this._positionModalPassThroughCallout();
                }
            }
            return;
        }

        if (
            (step.placement === 'center' || !step.anchor) &&
            !this._modalPassThrough &&
            !step.menuGuided
        ) {
            this._spotlight = null;
            this._calloutStyle = '';
            this._calloutPointerStyle = '';
            this._calloutEdgeAlign = '';
            this._bubbleClass = 'bubble bubble-center';
            this._bubbleStyle = '';
            return;
        }

        const anchorName = this._resolveAnchorName(step);
        const rect = anchorName ? getTourAnchorRect(anchorName) : null;
        if (!rect) {
            if (this._modalPassThrough && step.modalAnchor) {
                this._spotlight = this._estimateModalSpotlightRect();
                this._positionCallout(this._spotlight, 'bottom');
                return;
            }
            this._spotlight = null;
            this._calloutStyle = '';
            this._calloutPointerStyle = '';
            this._calloutEdgeAlign = '';
            if (!this._modalPassThrough) {
                this._bubbleClass = 'bubble bubble-center';
                this._bubbleStyle = '';
            }
            return;
        }

        this._spotlight = {
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height
        };

        const calloutPlacement = this._modalPassThrough && !step.modalCalloutOnly
            ? 'bottom'
            : (step.placement || 'bottom');
        if (step.menuGuided || step.actionLabel) {
            this._positionCallout(rect, calloutPlacement, step);
        }

        if (!this._modalPassThrough) {
            this._bubbleClass = 'bubble bubble-docked';
            this._bubbleStyle = '';
            this._applyMobileBubbleForStep(step, anchorName || '');
        }
    }

    _setCalloutBox(top, anchorCenterX) {
        this._calloutEdgeAlign = '';
        this._pendingCalloutAnchorX = anchorCenterX;
        this._calloutStyle =
            `left:${anchorCenterX}px;top:${top}px;transform:translateX(-50%);` +
            `width:max-content;max-width:${CALLOUT_MAX_WIDTH};`;
        this._calloutPointerStyle = '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this._finalizeCalloutPosition());
    }

    _setCalloutBoxLeft(top, boxRight, anchorCenterX) {
        this._calloutEdgeAlign = '';
        this._pendingCalloutAnchorX = null;
        this._calloutStyle =
            `right:${Math.max(16, window.innerWidth - boxRight)}px;top:${top}px;left:auto;` +
            `width:max-content;max-width:${CALLOUT_MAX_WIDTH};`;
        this._calloutPointerStyle = '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this._finalizeCalloutPositionLeft(top, boxRight, anchorCenterX));
    }

    _finalizeCalloutPositionLeft(top, boxRight, anchorCenterX) {
        if (!this.showCallout) {
            return;
        }
        const el = this.template.querySelector('.callout');
        if (!el) {
            return;
        }
        const rect = el.getBoundingClientRect();
        if (!rect.width) {
            return;
        }
        let left = boxRight - rect.width;
        left = Math.max(16, Math.min(left, window.innerWidth - rect.width - 16));
        const pointerShift = anchorCenterX - (left + rect.width / 2);
        this._calloutStyle =
            `left:${left}px;top:${top}px;width:max-content;max-width:${CALLOUT_MAX_WIDTH};`;
        this._calloutPointerStyle = pointerShift
            ? `transform:translateX(${pointerShift}px);`
            : '';
    }

    _finalizeCalloutPosition() {
        const anchorCenterX = this._pendingCalloutAnchorX;
        if (anchorCenterX == null || !this.showCallout) {
            return;
        }
        const el = this.template.querySelector('.callout');
        if (!el) {
            return;
        }
        const rect = el.getBoundingClientRect();
        if (!rect.width) {
            return;
        }
        let left = anchorCenterX - rect.width / 2;
        left = Math.max(16, Math.min(left, window.innerWidth - rect.width - 16));
        const pointerShift = anchorCenterX - (left + rect.width / 2);
        this._calloutStyle =
            `left:${left}px;top:${rect.top}px;width:max-content;max-width:${CALLOUT_MAX_WIDTH};`;
        this._calloutPointerStyle = pointerShift
            ? `transform:translateX(${pointerShift}px);`
            : '';
    }

    _setCalloutEdgeRight(rect, top, { arrowUp = true } = {}) {
        this._calloutEdgeAlign = 'right';
        this._pendingCalloutAnchorX = null;
        const anchorCenterX = rect.left + rect.width / 2;
        const edgeInset = Math.max(8, window.innerWidth - rect.right);
        const arrowInset = Math.max(0, Math.round(rect.right - anchorCenterX - 10));
        this._calloutStyle =
            `top:${top}px;right:${edgeInset}px;left:auto;` +
            `width:max-content;max-width:${CALLOUT_MAX_WIDTH};`;
        this._calloutPointerStyle = `--callout-arrow-inset:${arrowInset}px;`;
        this._calloutArrowPointsUp = arrowUp;
    }

    _anchorNearRightEdge(rect) {
        return rect.right > window.innerWidth - 96;
    }

    _positionBottomNavCallout(rect, anchor = '') {
        const calloutH = this.calloutSublabel ? 88 : 56;
        const top = Math.max(16, rect.top - CALLOUT_GAP - calloutH);
        const useEdgeRight = anchor === 'nav-mine' || this._anchorNearRightEdge(rect);

        if (useEdgeRight) {
            this._calloutArrowPointsUp = false;
            this._setCalloutEdgeRight(rect, top, { arrowUp: false });
            return;
        }

        this._calloutArrowPointsUp = false;
        this._setCalloutBox(top, rect.left + rect.width / 2);
    }

    _positionMenuItemCallout(rect, step = this.currentStep) {
        const calloutH = this.calloutSublabel ? 88 : 56;
        const anchorCenterX = rect.left + rect.width / 2;
        const calloutAbove = this._isMobile() && !!step?.menuCalloutAbove;

        if (calloutAbove) {
            this._calloutArrowPointsUp = false;
            const top = Math.max(16, rect.top - CALLOUT_GAP - calloutH);
            this._setCalloutBox(top, anchorCenterX);
            return;
        }

        this._calloutArrowPointsUp = true;
        const top = rect.bottom + 8;
        this._setCalloutBox(top, anchorCenterX);
    }

    _positionHeaderActionCallout(rect, placement, anchor) {
        const anchorCenterX = rect.left + rect.width / 2;
        const useEdgeRight = anchor === 'nav-menu' || this._anchorNearRightEdge(rect);

        if (useEdgeRight) {
            this._calloutArrowPointsUp = true;
            const top = rect.bottom + CALLOUT_GAP;
            this._setCalloutEdgeRight(rect, top, { arrowUp: true });
            return;
        }

        const prefer = placement === 'top' ? 'top' : 'bottom';
        let top;

        if (prefer === 'top') {
            this._calloutArrowPointsUp = true;
            top = rect.bottom + CALLOUT_GAP;
        } else {
            this._calloutArrowPointsUp = false;
            const calloutH = this.calloutSublabel ? 100 : 80;
            top = rect.top - CALLOUT_GAP - calloutH;
            if (top < 16) {
                this._calloutArrowPointsUp = true;
                top = rect.bottom + CALLOUT_GAP;
            }
        }

        this._setCalloutBox(top, anchorCenterX);
    }

    _positionCallout(rect, placement, step = this.currentStep) {
        const anchor = step?.anchor || '';
        if (this._isMobile() && this._isBottomNavAnchor(anchor)) {
            this._positionBottomNavCallout(rect, anchor);
            return;
        }
        if (step?.menuGuided || anchor.startsWith('menu-')) {
            this._positionMenuItemCallout(rect, step);
            return;
        }
        if (anchor === 'nav-menu' || anchor === 'nav-search' || anchor === 'nav-notifications') {
            this._positionHeaderActionCallout(rect, placement, anchor);
            return;
        }

        const anchorCenterX = rect.left + rect.width / 2;

        if (placement === 'left') {
            this._calloutArrowPointsUp = true;
            const calloutH = this.calloutSublabel ? 72 : 52;
            const boxRight = rect.left - CALLOUT_GAP;
            const top = Math.max(
                16,
                Math.min(
                    rect.top + rect.height / 2 - calloutH / 2,
                    window.innerHeight - calloutH - 16
                )
            );
            this._setCalloutBoxLeft(top, boxRight, anchorCenterX);
            return;
        }

        const prefer = placement === 'top' ? 'top' : 'bottom';
        let top;

        if (prefer === 'top') {
            this._calloutArrowPointsUp = true;
            top = rect.bottom + CALLOUT_GAP;
        } else {
            this._calloutArrowPointsUp = false;
            const calloutH = this.calloutSublabel ? 100 : 80;
            top = rect.top - CALLOUT_GAP - calloutH;
            if (top < 16) {
                this._calloutArrowPointsUp = true;
                top = rect.bottom + CALLOUT_GAP;
            }
        }

        this._setCalloutBox(top, anchorCenterX);
    }

    _positionModalPassThroughCallout() {
        const top = 92;
        this._calloutArrowPointsUp = false;
        this._setCalloutBox(top, window.innerWidth / 2);
    }

    _trapFocus() {
        const bubble = this.template.querySelector('[data-id="tour-bubble"]');
        const coach = this.template.querySelector('[data-id="modal-coach"]');
        (bubble || coach)?.focus();
    }

    handleBubbleKeydown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            this.handleSkip();
            return;
        }
        if (event.key !== 'Tab') {
            return;
        }
        const container = event.currentTarget;
        const focusables = [...container.querySelectorAll(this._focusableSelector)].filter(
            (el) => !el.disabled && el.offsetParent !== null
        );
        if (!focusables.length) {
            return;
        }
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
        }
    }

    handleScrimClick(event) {
        event.stopPropagation();
    }

    async handleNext() {
        if (this.isNextDisabled) {
            return;
        }
        const step = this.currentStep;
        if (step?.navigateHomeOnNext) {
            window.dispatchEvent(new CustomEvent('fimbytourclosemenu'));
            if (!isHomePath()) {
                navigate(this, '/');
            }
            await ensureHomeFeedReadyForTour();
        } else if (step?.route && step.advance === 'next' && !step.menuGuided) {
            navigate(this, step.route);
        }
        await this._advanceStep();
    }

    handleCalloutAction() {
        const step = this.currentStep;
        if (step.advance === 'modalDismiss' && !this._modalPassThrough) {
            this._openModalForStep(step);
            return;
        }
        if (step.id === 'menu') {
            window.dispatchEvent(new CustomEvent('fimbytouropenmenu'));
            this._markStepActionComplete();
            return;
        }
        if (step.route) {
            navigate(this, step.route);
        }
    }

    _beginModalPassThrough(step) {
        if (!step) {
            return;
        }
        this._modalPassThrough = true;
        this._awaitingModalDismiss = true;
        if (!step.modalCalloutOnly) {
            this._startModalAnchorPoll();
        }
        this._measureAndPosition();
    }

    _estimateModalSpotlightRect() {
        const insetTop = 86;
        const pad = 20;
        const w = Math.min(420, window.innerWidth - pad * 2);
        const availH = window.innerHeight - insetTop - pad;
        const h = Math.min(520, Math.max(280, availH * 0.85));
        const left = (window.innerWidth - w) / 2;
        const top = insetTop + Math.max(0, (availH - h) / 2);
        return { left, top, width: w, height: h };
    }

    _startModalAnchorPoll() {
        this._stopModalAnchorPoll();
        let attempts = 0;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._modalAnchorPollId = setInterval(() => {
            attempts += 1;
            if (!this._modalPassThrough || !this.isActive) {
                this._stopModalAnchorPoll();
                return;
            }
            this._measureAndPosition();
            const step = this.currentStep;
            const hasLiveRect =
                step?.modalAnchor && getTourAnchorRect(step.modalAnchor);
            if (hasLiveRect || attempts >= 40) {
                this._stopModalAnchorPoll();
            }
        }, 100);
    }

    _stopModalAnchorPoll() {
        if (this._modalAnchorPollId) {
            clearInterval(this._modalAnchorPollId);
            this._modalAnchorPollId = null;
        }
    }

    _openModalForStep(step) {
        this._beginModalPassThrough(step);
        if (step.modalEvent) {
            window.dispatchEvent(new CustomEvent(step.modalEvent));
        } else if (step.opensSearch) {
            window.dispatchEvent(new CustomEvent('fimbytouropensearch'));
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this._measureAndPosition());
    }

    async _advanceStep() {
        if (this._stepIndex >= this._steps.length - 1) {
            await this._completeTour(false);
            return;
        }
        this._stepIndex += 1;
        await this._prepareCurrentStep();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this._measureAndPosition());
    }

    handleOffRampKeep() {
        this._extendedTaken = true;
        const includeFinale = !this._replay && !this._bioPostCompleted;
        this._steps = getFilteredSteps({
            includeExtended: true,
            includeFinale,
            hasMultipleIdentities: this._hasMultipleIdentities
        });
        const offRampIdx = this._steps.findIndex((s) => s.id === 'off-ramp');
        this._stepIndex = offRampIdx >= 0 ? offRampIdx + 1 : 0;
        this._prepareCurrentStep().then(() => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => this._measureAndPosition());
        });
    }

    async handleOffRampDone() {
        if (this._bioPostCompleted || this._replay) {
            await this._completeTour(false);
            return;
        }
        const finaleIdx = this._steps.findIndex((s) => s.id === 'say-hi');
        if (finaleIdx >= 0) {
            this._stepIndex = finaleIdx;
            await this._prepareCurrentStep();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => this._measureAndPosition());
            return;
        }
        await this._completeTour(false);
    }

    handleIntroPostOpen() {
        this._modalPassThrough = true;
        const modal = this.template.querySelector('c-fimby-intro-post-modal');
        if (modal?.show) {
            modal.show();
        }
    }

    async handleIntroPostSkip() {
        await this._persistStatus(STATUS_COMPLETED, this._extendedTaken);
        this.endTour();
    }

    async handleBioPosted() {
        await this._persistStatus(STATUS_COMPLETED, this._extendedTaken);
        this.endTour();
    }

    async handleBioSkipped() {
        await this._persistStatus(STATUS_COMPLETED, this._extendedTaken);
        this.endTour();
    }

    async handleSkip() {
        await this._persistStatus(STATUS_DISMISSED, false);
        this.endTour();
    }

    async _completeTour(fromFinale) {
        if (fromFinale || this.currentStep?.advance === 'introPost') {
            return;
        }
        await this._persistStatus(STATUS_COMPLETED, this._extendedTaken);
        this.endTour();
    }

    async _persistStatus(status, extendedCompleted) {
        try {
            await setLiveTourStatus({ status, extendedCompleted: !!extendedCompleted });
        } catch (err) {
            console.error('fimbyGuidedTour persist status', err);
        }
    }
}
