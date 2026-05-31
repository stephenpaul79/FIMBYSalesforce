import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getResponseForReply from '@salesforce/apex/FimbyResponseController.getResponseForReply';
import submitResponseReply from '@salesforce/apex/FimbyResponseController.submitResponseReply';
import markResponseViewed from '@salesforce/apex/FimbyCommunicationController.markResponseViewed';
import blockContactApex from '@salesforce/apex/FimbyConversationController.blockContact';

/**
 * Response Reply component - matches Response_Reply.flow
 *
 * Allows back-and-forth messaging between poster and responder on a Response__c record.
 * - Posts to Chatter with @mention
 * - Sends email alert
 * - Updates Response__c (Last_Reply__c, Last_Reply_Date__c, etc.)
 * - Poster can update status (Accept, Decline, Complete)
 * - Option to share contact info
 */
export default class FimbyResponseReply extends NavigationMixin(LightningElement) {
    @api recordId = ''; // Response__c ID

    // State
    @track isLoading = true;
    @track isSubmitting = false;
    @track showModal = false;
    _isStandalonePage = false;

    // Error states
    @track errorState = null; // 'notAuthorized', 'loadError'
    @track errorMessage = '';

    // Data
    @track response = null;
    @track needOffer = null;
    @track actingAsContact = null;
    @track hasMultipleIdentities = false;
    @track isPoster = false; // Is the current user the Need/Offer poster?
    @track replyToName = ''; // Name of person we're replying to

    // Form fields
    @track subject = '';
    @track message = '';
    @track selectedStatus = '';
    @track shareContactInfo = false;

    _defaultStatusOptions = [
        { label: 'New', value: 'New' },
        { label: 'Accepted', value: 'Accepted' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Declined', value: 'Declined' }
    ];
    _eventStatusOptions = [
        { label: 'New', value: 'New' },
        { label: 'Accepted', value: 'Accepted' },
        { label: 'Completed', value: 'Completed' },
        { label: "Can't Make It", value: 'Declined' }
    ];

    // Success state
    @track showConfirmation = false;

    // A3: Block / Report state — same shape as fimbyConversationView and
    // fimbyResponseThread. One submit lands through
    // FimbyConversationController.blockContact, which writes
    // Blocked_Contact__c and (when isReporting is true) creates a
    // Moderator_Task__c via FimbyModeratorTaskService.
    @track showBlockModal = false;
    @track blockReason = '';
    @track isReporting = false;
    @track reportDetails = '';
    @track blockError = '';
    @track isBlockSubmitting = false;

    // ============================================
    // LIFECYCLE
    // ============================================

    connectedCallback() {
        if (!this.recordId) {
            this.recordId = this.extractRecordIdFromUrl();
            if (this.recordId) {
                this._isStandalonePage = true;
                this.showModal = true;
            }
        }
        if (this.recordId) {
            this.loadData();
        }
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this.hasMultipleIdentities = data.length > 0;
        } else if (error) {
            console.error('Error loading identities:', error);
            this.hasMultipleIdentities = false;
        }
    }

    extractRecordIdFromUrl() {
        const url = new URL(window.location.href);
        const queryId = url.searchParams.get('recordId');
        if (queryId) return queryId;
        const pathParts = url.pathname.split('/').filter(Boolean);
        const idx = pathParts.findIndex(p => p === 'response-reply');
        if (idx !== -1 && pathParts.length > idx + 1) {
            return pathParts[idx + 1];
        }
        return '';
    }

    // ============================================
    // DATA LOADING
    // ============================================

    async loadData() {
        this.isLoading = true;
        this.errorState = null;

        try {
            // Get acting as contact
            const contactResult = await getActingAsContact();
            if (!contactResult.success) {
                throw new Error('Could not get acting as contact');
            }
            this.actingAsContact = contactResult;

            // Get response and need/offer details
            const responseResult = await getResponseForReply({ recordId: this.recordId });

            if (!responseResult.success) {
                this.errorState = responseResult.error || 'loadError';
                this.errorMessage = responseResult.message || 'Could not load response details';
                this.isLoading = false;
                return;
            }

            this.response = responseResult.response;
            this.needOffer = responseResult.needOffer;
            this.isPoster = responseResult.isPoster;
            this.replyToName = responseResult.replyToName;

            // Set default status to current status
            this.selectedStatus = this.response.status;

            // Mark as viewed for unified unread tracking
            markResponseViewed({ responseId: this.recordId }).catch(() => {});

        } catch (error) {
            console.error('Error loading data:', error);
            this.errorState = 'loadError';
            this.errorMessage = error.body?.message || error.message || 'Error loading data';
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================
    // COMPUTED PROPERTIES
    // ============================================

    get hasError() {
        return this.errorState !== null;
    }

    get isNotAuthorized() {
        return this.errorState === 'notAuthorized';
    }

    get isEventType() {
        return this.needOffer?.typeValue === 'Event';
    }

    get isGatheringEvent() {
        return this.isEventType && (!this.needOffer?.eventType || this.needOffer.eventType === 'Gathering');
    }

    get isNonThreadedEvent() {
        const et = this.needOffer?.eventType;
        return this.isEventType && (et === 'Open_Event' || et === 'Community_Event');
    }

    get statusOptions() {
        return this.isEventType ? this._eventStatusOptions : this._defaultStatusOptions;
    }

    get showStatusUpdate() {
        return this.isPoster;
    }

    get modalTitle() {
        if (this.isEventType) return 'Event Reply';
        return 'Reply';
    }

    get nonThreadedEventMessage() {
        if (!this.needOffer) return '';
        const et = this.needOffer.eventType;
        if (et === 'Community_Event') return "This is a Community Event. You can express interest from the event's detail page.";
        return "This is an Open Event. You can join from the event's detail page.";
    }

    get subjectLength() {
        return this.subject.length;
    }

    get subjectExceeded() {
        return this.subjectLength > 80;
    }

    get messageLength() {
        return this.message.length;
    }

    get messageExceeded() {
        return this.messageLength > 255;
    }

    get subjectCountClass() {
        if (this.subjectLength >= 80) return 'char-count at-limit';
        if (this.subjectLength >= 72) return 'char-count near-limit';
        return 'char-count';
    }

    get messageCountClass() {
        if (this.messageLength >= 255) return 'char-count at-limit';
        if (this.messageLength >= 230) return 'char-count near-limit';
        return 'char-count';
    }

    get isFormInvalid() {
        if (!this.subject.trim() || this.subjectLength > 80) return true;
        if (!this.message.trim() || this.messageLength > 255) return true;
        return false;
    }

    get respondingAsName() {
        return this.actingAsContact?.postingAsDisplayName || this.actingAsContact?.actingAsContactName || this.actingAsContact?.contactName || '';
    }

    get respondingAsAvatarUrl() {
        return this.actingAsContact?.actingAsAvatarUrl || null;
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.respondingAsName;
    }

    get responseUrl() {
        return '/response/' + this.recordId;
    }

    get needOfferUrl() {
        return this.needOffer ? '/asks-offers/' + this.needOffer.id : '';
    }

    // ============================================
    // EVENT HANDLERS
    // ============================================

    @api
    show() {
        this.showModal = true;
        if (this.recordId && !this.response) {
            this.loadData();
        }
    }

    @api
    hide() {
        this.showModal = false;
        this.resetForm();
    }

    resetForm() {
        this.subject = '';
        this.message = '';
        this.shareContactInfo = false;
        this.showConfirmation = false;
        this.errorState = null;
        if (this.response) {
            this.selectedStatus = this.response.status;
        }
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            if (this._isStandalonePage) {
                this._navigateBack();
            } else {
                this.hide();
            }
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        if (this._isStandalonePage) {
            this._navigateBack();
        } else {
            this.hide();
        }
    }

    _navigateBack() {
        if (window.history.length > 1) {
            window.history.back();
        } else {
            window.location.href = '/messages';
        }
    }

    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleMessageChange(event) {
        this.message = event.target.value;
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }

    handleShareContactInfoChange(event) {
        this.shareContactInfo = event.target.checked;
    }

    handleGoToResponse() {
        window.location.href = this.responseUrl;
    }

    handleGoToNeedOffer() {
        window.location.href = this.needOfferUrl;
    }

    // ============================================
    // BLOCK / REPORT (A3)
    // ============================================

    /**
     * Resolves the Contact Id of the person we're replying to. The Apex
     * controller already populates response.responderContactId for posters
     * and response.contactId (the post's owner) for responders; we mirror
     * the same fallback chain fimbyResponseThread uses.
     */
    get otherPartyContactId() {
        if (!this.response) return null;
        if (this.isPoster) {
            return this.response.responderContactId
                || this.response.responderId
                || this.response.contactId
                || null;
        }
        if (this.needOffer) {
            return this.needOffer.postedById
                || this.needOffer.posterId
                || this.needOffer.contactId
                || null;
        }
        return null;
    }

    get otherPartyFirstName() {
        const name = this.replyToName || '';
        const first = name.trim().split(/\s+/)[0];
        return first || 'this neighbour';
    }

    get isBlockSubmitDisabled() {
        return !this.otherPartyContactId || this.isBlockSubmitting;
    }

    handleMenuClick() {
        if (!this.otherPartyContactId) return;
        this.showBlockModal = true;
    }

    handleCloseBlockModal() {
        if (this.isBlockSubmitting) return;
        this.showBlockModal = false;
        this.blockReason = '';
        this.isReporting = false;
        this.reportDetails = '';
        this.blockError = '';
    }

    handleBlockReasonChange(event) {
        this.blockReason = event.target.value;
    }

    handleReportToggle(event) {
        this.isReporting = event.target.checked;
    }

    handleReportDetailsChange(event) {
        this.reportDetails = event.target.value;
    }

    async handleConfirmBlock() {
        if (this.isBlockSubmitDisabled) return;
        this.isBlockSubmitting = true;
        this.blockError = '';
        try {
            await blockContactApex({
                blockedContactId: this.otherPartyContactId,
                reason: this.blockReason,
                isReport: this.isReporting,
                reportDetails: this.reportDetails
            });
            this.showBlockModal = false;
            // Land on Messages so the user is out of the reply context for
            // the person they just blocked, matching fimbyConversationView
            // and fimbyResponseThread.
            window.location.href = '/messages';
        } catch (error) {
            console.error('Error blocking contact:', error);
            this.blockError = error?.body?.message
                || error?.message
                || 'Could not block this neighbour. Please try again.';
        } finally {
            this.isBlockSubmitting = false;
        }
    }

    // ============================================
    // FORM SUBMISSION
    // ============================================

    async handleSubmit() {
        if (this.isFormInvalid) return;

        this.isSubmitting = true;

        try {
            const replyData = {
                responseId: this.recordId,
                subject: this.subject,
                message: this.message,
                newStatus: this.isPoster ? this.selectedStatus : null,
                shareContactInfo: this.shareContactInfo
            };

            const result = await submitResponseReply({
                replyData: JSON.stringify(replyData)
            });

            if (result.success) {
                this.showConfirmation = true;

                // If share contact info was checked, launch that flow/component
                if (this.shareContactInfo && result.shareContactInfoUrl) {
                    // Navigate to share contact info
                    window.location.href = result.shareContactInfoUrl;
                    return;
                }

                // Dispatch success event
                this.dispatchEvent(new CustomEvent('replysent', {
                    detail: {
                        responseId: this.recordId,
                        newStatus: result.newStatus
                    }
                }));
            } else {
                throw new Error(result.message || 'Error sending reply');
            }

        } catch (error) {
            console.error('Error submitting reply:', error);
            this.dispatchEvent(new CustomEvent('replyerror', {
                detail: {
                    error: error.body?.message || error.message || 'Failed to send reply'
                }
            }));
        } finally {
            this.isSubmitting = false;
        }
    }
}