import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

import { completeImageUrl } from 'c/fimbyImageUrl';
import getQuickResponseContext from '@salesforce/apex/FimbyQuickResponseController.getQuickResponseContext';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import postStoryComment from '@salesforce/apex/FimbyStoryCommentController.postStoryComment';
import createResponse from '@salesforce/apex/FimbyResponseController.createResponse';
import quickEventResponse from '@salesforce/apex/FimbyResponseController.quickEventResponse';
import createReservation from '@salesforce/apex/FimbyBulkBuyReservationController.createReservation';
import createLendingRequest from '@salesforce/apex/FimbyLibraryController.createLendingRequest';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getSkillOffer from '@salesforce/apex/FimbySkillsController.getSkillOffer';
import requestSkillHelp from '@salesforce/apex/FimbySkillsController.requestSkillHelp';
import searchContactsForMention from '@salesforce/apex/FimbyStoryCommentController.searchContactsForMention';
import { getCategoryIconUrl, getCategoryColor } from 'c/fimbySkillCategoryConfig';

const TYPE_CONFIG = {
    story: {
        modalTitle: 'Add Comment',
        identityLabel: 'Commenting as',
        submitLabel: 'Post Comment',
        celebrationAction: 'response',
        successMessage: 'Comment posted!',
        loadingContext: 'stories',
        submittingContext: 'commenting'
    },
    openEvent: {
        modalTitle: "RSVP",
        identityLabel: 'Responding as',
        submitLabel: "I'm Going",
        celebrationAction: 'event',
        successMessage: "You're going!",
        loadingContext: 'general',
        submittingContext: 'responding'
    },
    gathering: {
        modalTitle: 'RSVP',
        identityLabel: 'Responding as',
        submitLabel: 'Submit Response',
        celebrationAction: 'response',
        successMessage: 'Response sent!',
        loadingContext: 'general',
        submittingContext: 'responding'
    },
    askOffer: {
        modalTitle: 'Respond',
        identityLabel: 'Responding as',
        submitLabel: 'Submit Response',
        celebrationAction: 'response',
        successMessage: 'Response sent!',
        loadingContext: 'general',
        submittingContext: 'responding'
    },
    bulkBuy: {
        modalTitle: 'Reserve A Share',
        identityLabel: 'Reserving as',
        submitLabel: 'Reserve',
        celebrationAction: 'bulkbuy_reserve',
        successMessage: "You're in!",
        loadingContext: 'general',
        submittingContext: 'reserving'
    },
    library: {
        modalTitle: 'Borrow Item',
        identityLabel: 'Requesting as',
        submitLabel: 'Submit Request',
        celebrationAction: 'borrow',
        successMessage: 'Request submitted!',
        loadingContext: 'lending',
        submittingContext: 'lending'
    },
    skill: {
        modalTitle: 'Ask for Help',
        identityLabel: 'Messaging as',
        submitLabel: 'Send Message',
        celebrationAction: 'response',
        successMessage: 'Message sent!',
        loadingContext: 'general',
        submittingContext: 'messaging'
    }
};

export default class FimbyQuickResponseModal extends NavigationMixin(LightningElement) {

    /* ================================================================
     * Modal State
     * ================================================================ */
    @track _isVisible = false;
    _responseType = '';
    _recordId = '';
    @track _viewState = 'loading'; // loading | form | submitting | success | alreadyResponded | unavailable | error
    @track _errorMessage = '';

    /* ================================================================
     * Identity
     * ================================================================ */
    @track _actingAsContactId = '';
    @track _actingAsContactName = '';
    @track _hasMultipleIdentities = false;

    /* ================================================================
     * Context Data (raw from Apex, per type)
     * ================================================================ */
    _context = null;
    _identity = null;

    /* ================================================================
     * Story Form State
     * ================================================================ */
    @track _commentText = '';
    @track _mentionSuggestions = [];
    @track _showMentionSuggestions = false;
    _mentionAtIndex;
    _mentionSearchText;

    /* ================================================================
     * Open Event Form State
     * ================================================================ */
    @track _guestCount = 1;

    /* ================================================================
     * Ask / Offer / Gathering Form State
     * ================================================================ */
    @track _subject = '';
    @track _responseDetails = '';
    @track _amountRequested = 1;
    @track _decline = false;

    /* ================================================================
     * Bulk Buy Form State
     * ================================================================ */
    @track _reserveAmount = 1;

    /* ================================================================
     * Library Form State
     * ================================================================ */
    @track _requestedDate = '';
    @track _daysNeeded = '';
    @track _noteToLender = '';

    /* ================================================================
     * Skill Form State
     * ================================================================ */
    @track _skillNote = '';
    @track _skillCategoryIconUrl = '';

    /* ================================================================
     * Submit State
     * ================================================================ */
    @track _isSubmitting = false;
    _submittedResponseData = null;
    @track _isWaitlisted = false;
    @track _waitlistPosition = 0;
    @track _confirmationWindowDays = 3;
    @track _isItemAvailable = true;

    /* ================================================================
     * PUBLIC API
     * ================================================================ */

    @api
    show(recordId, responseType, options) {
        this._recordId = recordId;
        this._responseType = responseType;
        this._isItemAvailable = options?.isItemAvailable !== false;
        this._isVisible = true;
        this._viewState = 'loading';
        this._resetForm();
        this._loadContext();
    }

    @api
    hide() {
        this._isVisible = false;
        this._resetForm();
        this.dispatchEvent(new CustomEvent('modalclosed', {
            bubbles: true,
            composed: true
        }));
    }

    /* ================================================================
     * LIFECYCLE
     * ================================================================ */

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this._hasMultipleIdentities = data.length > 0;
        } else if (error) {
            console.error('Error loading identities:', error);
            this._hasMultipleIdentities = false;
        }
    }

    disconnectedCallback() {
        this._isVisible = false;
    }

    /* ================================================================
     * TYPE CONFIG GETTERS
     * ================================================================ */

    get _config() {
        return TYPE_CONFIG[this._responseType] || TYPE_CONFIG.askOffer;
    }

    get modalTitle() { return this._config.modalTitle; }
    get identityLabel() { return this._config.identityLabel; }
    get submitLabel() { return this._config.submitLabel; }
    get celebrationActionType() { return this._config.celebrationAction; }
    get successMessage() { return this._config.successMessage; }
    get loadingContext() { return this._config.loadingContext; }
    get submittingContext() { return this._config.submittingContext || 'general'; }

    /* ================================================================
     * VIEW STATE GETTERS
     * ================================================================ */

    get isLoading() { return this._viewState === 'loading'; }
    get isForm() { return this._viewState === 'form'; }
    get isSubmittingState() { return this._viewState === 'submitting'; }
    get isSuccess() { return this._viewState === 'success'; }
    get isAlreadyResponded() { return this._viewState === 'alreadyResponded'; }
    get isUnavailable() { return this._viewState === 'unavailable'; }
    get isError() { return this._viewState === 'error'; }
    get errorMessage() { return this._errorMessage; }

    /* ================================================================
     * TYPE FLAG GETTERS
     * ================================================================ */

    get isStoryType() { return this._responseType === 'story'; }
    get isOpenEventType() { return this._responseType === 'openEvent'; }
    get isAskOfferType() { return this._responseType === 'askOffer' || this._responseType === 'gathering'; }
    get isBulkBuyType() { return this._responseType === 'bulkBuy'; }
    get isLibraryType() { return this._responseType === 'library'; }
    get isSkillType() { return this._responseType === 'skill'; }

    get showFormFooter() {
        return this.isForm && !this.isOpenEventType;
    }

    get showIdentityBanner() {
        return this._hasMultipleIdentities && !!this._actingAsContactName;
    }

    /* ================================================================
     * SUMMARY CARD GETTERS
     * ================================================================ */

    get summaryTitle() {
        if (!this._context) return '';
        if (this.isStoryType) return this._context.story?.name || '';
        if (this.isBulkBuyType) return this._context.post?.Name || '';
        if (this.isLibraryType) return this._context.item?.name || '';
        if (this.isSkillType) return this._context.title || '';
        return this._context.name || '';
    }

    get summaryImageUrl() {
        if (!this._context) return '';
        let raw = '';
        if (this.isStoryType) raw = this._context.story?.imageUrl || '';
        else if (this.isBulkBuyType) raw = this._context.post?.Image_1_URL__c || '';
        else if (this.isLibraryType) raw = this._context.item?.imageUrl || '';
        else raw = this._context.imageUrl || '';
        return completeImageUrl(raw);
    }

    get hasSummaryImage() {
        if (this.isSkillType) return !!this._skillCategoryIconUrl;
        return !!this.summaryImageUrl;
    }

    get summaryIconUrl() {
        return this._skillCategoryIconUrl;
    }

    get summarySubtitle() {
        if (!this._context) return '';
        if (this.isStoryType) {
            return this._context.story?.ownerName || '';
        }
        if (this.isBulkBuyType) {
            const post = this._context.post;
            if (!post) return '';
            const first = post.Posted_By__r?.FirstName || '';
            const last = post.Posted_By__r?.LastName || '';
            return (first + ' ' + last).trim();
        }
        if (this.isLibraryType) return this._context.item?.ownerName || '';
        if (this.isSkillType) return this._context.ownerName || '';
        return this._context.posterName || '';
    }

    get summaryMeta() {
        if (!this._context) return '';
        if (this.isOpenEventType) {
            const parts = [];
            if (this._context.eventDetails) {
                const atIdx = this._context.eventDetails.indexOf(' @ ');
                parts.push(atIdx > -1 ? this._context.eventDetails.substring(0, atIdx) : this._context.eventDetails);
            }
            if (this._context.location) parts.push(this._context.location);
            return parts.join(' · ');
        }
        if (this.isAskOfferType && this._context.totalAvailable > 1) {
            return this._context.totalAvailable + ' available';
        }
        if (this.isBulkBuyType) {
            const post = this._context.post;
            if (!post) return '';
            const available = (post.Total_Available__c || 0);
            const price = post.Estimated_Cost_Per_Share__c;
            const parts = [];
            if (price) parts.push('$' + Number(price).toFixed(2) + ' per share');
            parts.push(available + ' available');
            return parts.join(' · ');
        }
        if (this.isLibraryType) {
            return this._context.item?.category || '';
        }
        if (this.isSkillType) {
            return this._context.category || '';
        }
        return '';
    }

    /* ================================================================
     * STORY FORM GETTERS
     * ================================================================ */

    get commentCharacterCount() { return this._commentText.length; }
    get commentCharacterDisplay() { return `${this.commentCharacterCount}/1000`; }
    get isCommentNearLimit() { return this.commentCharacterCount > 900; }
    get isCommentOverLimit() { return this.commentCharacterCount >= 1000; }
    get commentCountClass() {
        if (this.isCommentOverLimit) return 'char-count over-limit';
        if (this.isCommentNearLimit) return 'char-count near-limit';
        return 'char-count';
    }

    /* ================================================================
     * ASK / OFFER / GATHERING FORM GETTERS
     * ================================================================ */

    get subjectLength() { return this._subject.length; }
    get subjectDisplay() { return `${this.subjectLength}/80`; }
    get isSubjectOver() { return this.subjectLength >= 80; }
    get subjectCountClass() {
        return this.isSubjectOver ? 'char-count over-limit' : (this.subjectLength > 72 ? 'char-count near-limit' : 'char-count');
    }

    get detailsLength() { return this._responseDetails.length; }
    get detailsDisplay() { return `${this.detailsLength}/255`; }
    get isDetailsOver() { return this.detailsLength >= 255; }
    get detailsCountClass() {
        return this.isDetailsOver ? 'char-count over-limit' : (this.detailsLength > 230 ? 'char-count near-limit' : 'char-count');
    }

    get showAmountField() {
        return this._context && this._context.totalAvailable > 1;
    }

    get maxAmount() {
        if (!this._context) return 1;
        const available = this._context.totalAvailable || 1;
        const perResponse = this._context.perResponseLimit || available;
        return Math.min(available, perResponse);
    }

    /* ================================================================
     * BULK BUY FORM GETTERS
     * ================================================================ */

    get bulkBuyMaxAmount() {
        if (!this._context?.post) return 1;
        const available = this._context.post.Total_Available__c || 0;
        const perResponse = this._context.post.Per_Response_Limit__c || available;
        return Math.min(available, perResponse);
    }

    get thermoTakenCount() {
        if (!this._context?.post) return 0;
        const owner = this._context.post.Owner_Shares__c || 0;
        const reserved = this._context.post.Total_Reserved__c || 0;
        return owner + reserved;
    }

    get thermoPendingCount() {
        return this._reserveAmount || 0;
    }

    get thermoRemainingCount() {
        if (!this._context?.post) return 0;
        const available = this._context.post.Total_Available__c || 0;
        return Math.max(0, available - (this._reserveAmount || 0));
    }

    get thermometerTotal() {
        if (!this._context?.post) return 1;
        return this._context.post.Total_Quantity__c || 1;
    }

    get takenWidth() { return `width: ${(this.thermoTakenCount / this.thermometerTotal) * 100}%`; }
    get pendingWidth() { return `width: ${(this.thermoPendingCount / this.thermometerTotal) * 100}%`; }
    get remainingWidth() { return `width: ${(this.thermoRemainingCount / this.thermometerTotal) * 100}%`; }

    /* ================================================================
     * LIBRARY FORM GETTERS
     * ================================================================ */

    get todayDate() {
        return new Date().toISOString().split('T')[0];
    }

    get maxPickupDate() {
        const d = new Date();
        d.setDate(d.getDate() + 7);
        return d.toISOString().split('T')[0];
    }

    get maxLendingDays() {
        return this._context?.item?.maxLendingDays || 14;
    }

    get noteCharCount() { return this._noteToLender.length; }
    get noteCharDisplay() { return `${this.noteCharCount}/255`; }
    get noteCountClass() {
        return this.noteCharCount >= 255 ? 'char-count over-limit' : (this.noteCharCount > 230 ? 'char-count near-limit' : 'char-count');
    }

    get skillNoteLength() { return this._skillNote.length; }
    get skillNoteDisplay() { return `${this.skillNoteLength}/1000`; }
    get skillNoteCountClass() {
        if (this.skillNoteLength >= 1000) return 'char-count at-limit';
        if (this.skillNoteLength >= 900) return 'char-count near-limit';
        return 'char-count';
    }

    get skillSummaryIconStyle() {
        const color = getCategoryColor(this._context?.category);
        return `background-color: ${color};`;
    }

    get dateValidationError() {
        if (!this._requestedDate) return '';
        const max = new Date();
        max.setDate(max.getDate() + 7);
        if (new Date(this._requestedDate) > max) return 'Requests must be within the next 7 days.';
        return '';
    }

    get daysValidationError() {
        if (this._daysNeeded === '' || this._daysNeeded === undefined) return '';
        const days = Number(this._daysNeeded);
        if (days < 1) return 'Please enter at least 1 day.';
        if (days > this.maxLendingDays) return `Please request ${this.maxLendingDays} days or less.`;
        return '';
    }

    get showDateField() {
        return !this.isLibraryType || this._isItemAvailable;
    }

    get showDateHint() {
        return this.isLibraryType && !this._isItemAvailable;
    }

    /* ================================================================
     * SUBMIT DISABLED GETTER (universal)
     * ================================================================ */

    get isSubmitDisabled() {
        if (this._isSubmitting) return true;

        if (this.isStoryType) {
            return !this._commentText.trim() || this.isCommentOverLimit;
        }
        if (this.isOpenEventType) {
            return this._guestCount < 1;
        }
        if (this.isAskOfferType) {
            if (!this._subject.trim() || this.isSubjectOver) return true;
            if (!this._responseDetails.trim() || this.isDetailsOver) return true;
            if (this.showAmountField && (this._amountRequested < 1 || this._amountRequested > this.maxAmount)) return true;
            return false;
        }
        if (this.isBulkBuyType) {
            return this._reserveAmount < 1 || this._reserveAmount > this.bulkBuyMaxAmount;
        }
        if (this.isLibraryType) {
            if (this.showDateField && !this._requestedDate) return true;
            if (!this._daysNeeded) return true;
            if (this.showDateField && this.dateValidationError) return true;
            if (this.daysValidationError) return true;
            if (this.noteCharCount > 255) return true;
            return false;
        }
        if (this.isSkillType) {
            return this.skillNoteLength > 1000;
        }
        return true;
    }

    get submitButtonClass() {
        return 'submit-btn' + (this._isSubmitting ? ' submitting' : '');
    }

    get showCelebration() {
        return this._viewState === 'success' && !this._isWaitlisted;
    }

    get successDisplayMessage() {
        if (this._isWaitlisted && this._waitlistPosition > 0) {
            return `Request submitted! You\u2019re #${this._waitlistPosition} on the waitlist.`;
        }
        return this._config.successMessage;
    }

    get showWaitlistDisclaimer() {
        return this._isWaitlisted && this.isLibraryType;
    }

    get waitlistDisclaimer() {
        const days = this._confirmationWindowDays || 3;
        return `When it\u2019s your turn, you\u2019ll have ${days} day${days !== 1 ? 's' : ''} to confirm you still want to borrow this. If you don\u2019t respond in time, the next person in line will get a chance.`;
    }

    /* ================================================================
     * ICON GETTERS
     * ================================================================ */

    get identityIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }
    get successIconUrl() { return `${IMPACT_ICONS}/confetti.png`; }
    get closeIconName() { return 'utility:close'; }

    /* ================================================================
     * MODAL EVENT HANDLERS
     * ================================================================ */

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.hide();
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.hide();
        }
    }

    /* ================================================================
     * DATA LOADING
     * ================================================================ */

    async _loadContext() {
        this._viewState = 'loading';
        try {
            if (this.isSkillType) {
                await this._loadSkillContext();
                return;
            }

            const result = await getQuickResponseContext({
                recordId: this._recordId,
                responseType: this._responseType
            });

            if (!result.success) {
                this._errorMessage = result.message || 'Unable to load. Please try again.';
                this._viewState = 'error';
                return;
            }

            const identity = result.identity;
            if (identity?.success) {
                this._actingAsContactId = identity.actingAsContactId || identity.contactId;
                this._actingAsContactName = identity.postingAsDisplayName || identity.actingAsContactName || identity.contactName || 'You';
            } else {
                this._actingAsContactName = 'You';
            }
            this._identity = identity;

            this._context = result.context;

            if (this.isBulkBuyType && this._context) {
                this._reserveAmount = 1;
            }

            const vs = result.viewState;
            if (vs === 'alreadyResponded') {
                this._viewState = 'alreadyResponded';
            } else if (vs === 'unavailable' || vs === 'fullyReserved' || vs === 'blocked') {
                this._viewState = 'unavailable';
                this._errorMessage = vs === 'blocked'
                    ? "You're unable to reserve at this time."
                    : 'This is no longer available.';
            } else {
                this._viewState = 'form';
            }

        } catch (error) {
            this._errorMessage = error.body?.message || error.message || 'Something went wrong. Please try again.';
            this._viewState = 'error';
        }
    }

    /* ================================================================
     * STORY FORM HANDLERS
     * ================================================================ */

    handleCommentChange(event) {
        this._commentText = event.target.value;
        const inputEl = event.target.querySelector('textarea') || event.target;
        this._cursorPosition = inputEl.selectionStart || this._commentText.length;
        this._checkForMentions();
    }

    _checkForMentions() {
        const text = this._commentText;
        const cursorPos = this._cursorPosition || text.length;
        const beforeCursor = text.substring(0, cursorPos);
        const atIndex = beforeCursor.lastIndexOf('@');

        if (atIndex !== -1) {
            const mentionText = beforeCursor.substring(atIndex + 1);
            if (mentionText.indexOf(' ') === -1) {
                this._mentionAtIndex = atIndex;
                this._mentionSearchText = mentionText;
                this._searchMentions(mentionText);
                return;
            }
        }
        this._closeMentionSuggestions();
    }

    async _searchMentions(searchTerm) {
        try {
            const results = await searchContactsForMention({ searchTerm });
            if (results?.length > 0) {
                this._mentionSuggestions = results.map(c => ({
                    id: c.id, name: c.name, neighbourhood: c.neighbourhood || ''
                }));
                this._showMentionSuggestions = true;
            } else {
                this._closeMentionSuggestions();
            }
        } catch (_e) {
            this._closeMentionSuggestions();
        }
    }

    handleMentionSelect(event) {
        const name = event.currentTarget.dataset.personName;
        const text = this._commentText;
        const atIndex = this._mentionAtIndex;
        const searchText = this._mentionSearchText || '';

        if (atIndex !== undefined && atIndex !== -1) {
            const beforeAt = text.substring(0, atIndex);
            const afterMention = text.substring(atIndex + 1 + searchText.length);
            this._commentText = `${beforeAt}@${name} ${afterMention.trimStart()}`;
        }
        this._closeMentionSuggestions();
    }

    _closeMentionSuggestions() {
        this._showMentionSuggestions = false;
        this._mentionSuggestions = [];
    }

    /* ================================================================
     * OPEN EVENT FORM HANDLERS
     * ================================================================ */

    handleGuestIncrement() {
        this._guestCount += 1;
    }

    handleGuestDecrement() {
        if (this._guestCount > 1) this._guestCount -= 1;
    }

    /* ================================================================
     * ASK / OFFER FORM HANDLERS
     * ================================================================ */

    handleSubjectChange(event) { this._subject = event.target.value; }
    handleDetailsChange(event) { this._responseDetails = event.target.value; }
    handleAmountChange(event) {
        const val = parseInt(event.target.value, 10);
        this._amountRequested = isNaN(val) ? 1 : Math.max(1, Math.min(val, this.maxAmount));
    }
    handleDeclineChange(event) { this._decline = event.target.checked; }

    /* ================================================================
     * BULK BUY FORM HANDLERS
     * ================================================================ */

    handleReserveAmountChange(event) {
        const val = parseInt(event.target.value, 10);
        this._reserveAmount = isNaN(val) ? 1 : Math.max(1, Math.min(val, this.bulkBuyMaxAmount));
    }
    handleReserveIncrement() {
        if (this._reserveAmount < this.bulkBuyMaxAmount) this._reserveAmount += 1;
    }
    handleReserveDecrement() {
        if (this._reserveAmount > 1) this._reserveAmount -= 1;
    }

    /* ================================================================
     * LIBRARY FORM HANDLERS
     * ================================================================ */

    handleDateChange(event) { this._requestedDate = event.target.value; }
    handleDaysChange(event) { this._daysNeeded = event.target.value; }
    handleNoteChange(event) { this._noteToLender = event.target.value; }
    handleSkillNoteChange(event) { this._skillNote = event.target.value; }

    async _loadSkillContext() {
        try {
            const [skill, identity] = await Promise.all([
                getSkillOffer({ recordId: this._recordId }),
                getActingAsContact()
            ]);

            if (identity) {
                this._actingAsContactId = identity.actingAsContactId || identity.contactId;
                this._actingAsContactName = identity.postingAsDisplayName || identity.actingAsContactName || identity.contactName || 'You';
            } else {
                this._actingAsContactName = 'You';
            }

            if (skill.isOwner) {
                this._viewState = 'unavailable';
                this._errorMessage = 'This is your own skill offer.';
                return;
            }

            if (skill.status !== 'Active') {
                this._viewState = 'unavailable';
                this._errorMessage = 'This skill is not available right now.';
                return;
            }

            this._context = skill;
            this._skillCategoryIconUrl = getCategoryIconUrl(IMPACT_ICONS, skill.category);
            this._viewState = 'form';
        } catch (error) {
            this._errorMessage = error.body?.message || error.message || 'Unable to load skill.';
            this._viewState = 'error';
        }
    }

    /* ================================================================
     * SUBMIT DISPATCHER
     * ================================================================ */

    async handleSubmit() {
        if (this._isSubmitting) return;
        this._isSubmitting = true;
        this._viewState = 'submitting';
        this._errorMessage = '';

        try {
            let result;
            switch (this._responseType) {
                case 'story':
                    result = await this._submitStoryComment();
                    break;
                case 'openEvent':
                    result = await this._submitEventResponse();
                    break;
                case 'askOffer':
                case 'gathering':
                    result = await this._submitResponse();
                    break;
                case 'bulkBuy':
                    result = await this._submitReservation();
                    break;
                case 'library':
                    result = await this._submitBorrowRequest();
                    break;
                case 'skill':
                    result = await this._submitSkillHelp();
                    break;
                default:
                    throw new Error('Unknown response type');
            }

            this._submittedResponseData = result;
            this._viewState = 'success';

            this.dispatchEvent(new CustomEvent('responsesaved', {
                bubbles: true,
                composed: true,
                detail: {
                    recordId: this._recordId,
                    responseType: this._responseType,
                    responseData: result
                }
            }));

            // No auto-close — let the user enjoy the celebration and dismiss when ready.

        } catch (error) {
            const msg = error.body?.message || error.message || '';
            const isQuantityError = /amount|available|quantity|validation/i.test(msg);
            if (isQuantityError) {
                this._errorMessage = "Looks like this isn't available anymore — someone responded a bit more quickly.";
                this._viewState = 'unavailable';
            } else {
                this._errorMessage = msg || 'Something went wrong. Please try again.';
                this._viewState = 'error';
            }
        } finally {
            this._isSubmitting = false;
        }
    }

    /* ================================================================
     * TYPE-SPECIFIC SUBMIT METHODS
     * ================================================================ */

    async _submitStoryComment() {
        const commentData = {
            storyId: this._recordId,
            commentText: this._commentText.trim(),
            commentContactId: this._actingAsContactId || null
        };
        const result = await postStoryComment({ commentData: JSON.stringify(commentData) });
        if (!result.success) throw new Error(result.message || 'Failed to post comment.');
        return { commentId: result.commentId };
    }

    async _submitEventResponse() {
        const result = await quickEventResponse({
            eventId: this._recordId,
            action: 'respond',
            guestCount: this._guestCount
        });
        if (!result.success) throw new Error(result.message || 'Failed to respond.');
        return { responseId: result.responseId, guestCount: this._guestCount };
    }

    async _submitResponse() {
        const responseData = {
            needOfferId: this._recordId,
            subject: this._subject.trim(),
            responseDetails: this._responseDetails.trim(),
            amountRequested: this.showAmountField ? this._amountRequested : 1,
            decline: this._decline
        };
        const result = await createResponse({ responseData: JSON.stringify(responseData) });
        if (!result.success) throw new Error(result.message || 'Failed to submit response.');
        return { responseId: result.responseId, status: result.status };
    }

    async _submitReservation() {
        const result = await createReservation({
            postId: this._recordId,
            amount: this._reserveAmount
        });
        if (!result.success) throw new Error(result.message || 'Failed to reserve.');
        return { reservationId: result.reservationId, amount: this._reserveAmount };
    }

    async _submitSkillHelp() {
        const result = await requestSkillHelp({
            skillOfferId: this._recordId,
            note: this._skillNote.trim() || null
        });
        if (!result.success) {
            throw new Error(result.message || 'Failed to send message.');
        }
        return {
            conversationId: result.conversationId,
            messageId: result.messageId
        };
    }

    async _submitBorrowRequest() {
        const requestData = {
            itemId: this._recordId,
            requestedById: this._actingAsContactId,
            requestedDate: this._isItemAvailable ? this._requestedDate : null,
            daysNeeded: Number(this._daysNeeded),
            message: this._noteToLender.trim() || null
        };
        const result = await createLendingRequest({ requestData: JSON.stringify(requestData) });
        if (!result.success) throw new Error(result.message || 'Failed to submit request.');
        this._isWaitlisted = !result.isFirstInLine;
        this._waitlistPosition = result.waitlistPosition || 0;
        if (result.confirmationWindowDays) {
            this._confirmationWindowDays = result.confirmationWindowDays;
        }
        return { requestId: result.requestId, waitlistPosition: result.waitlistPosition };
    }

    /* ================================================================
     * RESET
     * ================================================================ */

    _resetForm() {
        this._context = null;
        this._identity = null;
        this._errorMessage = '';
        this._isSubmitting = false;
        this._submittedResponseData = null;
        this._isWaitlisted = false;
        this._waitlistPosition = 0;
        this._confirmationWindowDays = 3;

        this._commentText = '';
        this._mentionSuggestions = [];
        this._showMentionSuggestions = false;

        this._guestCount = 1;

        this._subject = '';
        this._responseDetails = '';
        this._amountRequested = 1;
        this._decline = false;

        this._reserveAmount = 1;

        this._requestedDate = '';
        this._daysNeeded = '';
        this._noteToLender = '';
        this._isItemAvailable = true;

        this._skillNote = '';
        this._skillCategoryIconUrl = '';
    }

    /* ================================================================
     * VIEW DETAILS NAVIGATION (from success state)
     * ================================================================ */

    handleViewDetails() {
        // Close the modal before navigating so it isn't left stranded in the
        // persistent shell once these links move to soft navigation.
        this.hide();
        if (this.isStoryType) {
            navigate(this, `/sharedlife/${this._recordId}`);
        } else if (this.isLibraryType) {
            navigate(this, `/library-item/${this._recordId}`);
        } else if (this.isSkillType) {
            const convId = this._submittedResponseData?.conversationId;
            if (convId) {
                navigate(this, `/conversation?id=${convId}`);
            } else {
                navigate(this, `/skill-offer/${this._recordId}`);
            }
        } else {
            navigate(this, `/asks-offers/${this._recordId}`);
        }
    }

    handleRetry() {
        this._loadContext();
    }
}