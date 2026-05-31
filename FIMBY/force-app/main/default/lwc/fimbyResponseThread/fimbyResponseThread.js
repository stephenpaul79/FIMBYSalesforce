import { LightningElement, api, track, wire } from 'lwc';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getThread from '@salesforce/apex/FimbyResponseThreadController.getThread';
import getMessages from '@salesforce/apex/FimbyResponseThreadController.getMessages';
import sendMessageApex from '@salesforce/apex/FimbyResponseThreadController.sendMessage';
import updateResponseAmount from '@salesforce/apex/FimbyResponseThreadController.updateResponseAmount';
import cancelResponseApex from '@salesforce/apex/FimbyResponseThreadController.cancelResponse';
import acceptResponseApex from '@salesforce/apex/FimbyResponseThreadController.acceptResponse';
import declineResponseApex from '@salesforce/apex/FimbyResponseThreadController.declineResponse';
import completeResponseApex from '@salesforce/apex/FimbyResponseThreadController.completeResponse';
import getShareContactInfoData from '@salesforce/apex/FimbyResponseThreadController.getShareContactInfoData';
import shareContactInfoApex from '@salesforce/apex/FimbyResponseThreadController.shareContactInfo';
import blockContactApex from '@salesforce/apex/FimbyConversationController.blockContact';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const PAGE_SIZE = 50;
const TERMINAL_STATUSES = ['Declined', 'Cancelled', 'Expired'];
const ZONE_THRESHOLD = 3;
const PILL_THRESHOLD = 5;
const SNIPPET_LENGTH = 80;

export default class FimbyResponseThread extends LightningElement {
    @api responseId = '';

    @track isLoading = true;
    @track error = null;

    @track response = {};
    @track post = {};
    @track messages = [];
    @track processedMessages = [];
    @track isPoster = false;
    @track isResponder = false;
    @track myContactId = '';
    @track myContactName = '';
    @track myContactImageUrl = '';
    @track contactShared = false;

    @track messageText = '';
    @track isSending = false;
    @track showCompose = false;

    @track showConfirmDialog = false;
    @track confirmAction = null;
    @track confirmTitle = '';
    @track confirmMessage = '';
    @track confirmButtonLabel = '';
    @track confirmButtonVariant = 'brand';

    @track showEditAmount = false;
    @track editAmountValue = null;
    @track editAmountError = '';

    @track showShareContact = false;
    @track shareContactData = null;
    @track shareEmail = true;
    @track sharePhone = true;
    @track shareAddress = false;
    @track shareEmailValue = '';
    @track sharePhoneValue = '';
    @track shareStreet = '';
    @track shareCity = '';
    @track shareState = '';
    @track sharePostalCode = '';
    @track shareContactError = '';
    @track isShareSubmitting = false;

    @track organizationId = null;
    @track hasMultipleIdentities = false;
    @track postExpanded = false;
    @track hasMoreMessages = false;
    @track isLoadingMore = false;
    @track currentOffset = 0;

    // Collapsible thread zones
    @track headerHidden = false;
    _lastScrollY = 0;
    _scrollTicking = false;

    @track useZones = false;
    @track firstMessage = null;
    @track headerSystemMessages = [];
    @track middleMessages = [];
    @track middleSystemMessages = [];
    @track lastMessages = [];
    @track middleRevealed = false;
    @track expandedIds = [];

    _rawMiddle = [];
    _allowEventMessaging = false;

    // Block/Report state. Mirrors the fimbyConversationView pattern:
    // a single kebab in the header opens one modal that handles both Block
    // (always) and Report (opt-in checkbox). Both actions land through the
    // existing FimbyConversationController.blockContact entry point — one
    // server round-trip writes Blocked_Contact__c and (when isReport is true)
    // creates a Moderator_Task__c via FimbyModeratorTaskService.
    @track showBlockModal = false;
    @track blockReason = '';
    @track isReporting = false;
    @track reportDetails = '';
    @track blockError = '';
    @track isBlockSubmitting = false;

    // --- Getters ---

    get stickyHeaderClass() {
        return this.headerHidden ? 'thread-header header-hidden' : 'thread-header';
    }

    get isFirstExpanded() {
        return this.firstMessage ? this.expandedIds.includes(this.firstMessage.id) : false;
    }

    get isSendDisabled() {
        return !this.messageText || !this.messageText.trim() || this.isSending;
    }

    get isThreadActive() {
        return !TERMINAL_STATUSES.includes(this.response.status);
    }

    get canSendMessage() {
        return this.isThreadActive || this.response.status === 'Completed';
    }

    get statusBadgeClass() {
        const s = (this.response.status || '').toLowerCase();
        return `status-badge status-${s}`;
    }

    get terminalBannerMessage() {
        const s = this.response.status;
        if (s === 'Expired') return 'This post is no longer active. You can still read this conversation.';
        if (s === 'Declined') return 'This response was declined.';
        if (s === 'Cancelled') return 'This response was cancelled.';
        if (s === 'Completed') return 'This response is complete.';
        return '';
    }

    get showTerminalBanner() {
        return TERMINAL_STATUSES.includes(this.response.status);
    }

    get showCompleteBanner() {
        return this.response.status === 'Completed';
    }

    get contactNotShared() {
        return !this.contactShared;
    }

    /** Hide status badge and amount pill when Completed (redundant with green banner) */
    get showHeaderPills() {
        return !this.isNonThreadedEventOnly && this.response.status !== 'Completed';
    }

    get messagesListClass() {
        const base = 'messages-list';
        return this.showCompleteBanner ? `${base} complete-thread` : base;
    }

    /** True when status is Completed and within 7 days of completion (allows final messages before DM) */
    get isWithinCompletedGracePeriod() {
        if (this.response.status !== 'Completed') return false;
        const completed = this.response.completedDate;
        if (!completed) return false;
        const completedMs = new Date(completed).getTime();
        const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
        return Date.now() - completedMs <= sevenDaysMs;
    }

    get showReplyArea() {
        if (this.isNonThreadedEventOnly) return false;
        if (!this.canSendMessage || this.showTerminalBanner) return false;
        if (!this.showCompleteBanner) return true;
        return this.isWithinCompletedGracePeriod;
    }

    get tracksQuantity() {
        return this.post.totalQuantity != null && this.post.totalQuantity > 0;
    }

    get amountLabel() {
        const rt = this.post.recordType;
        if (rt === 'Need' || rt === 'Ask') return 'Offering';
        if (rt === 'Offer') return 'Requesting';
        if (rt === 'Event') return 'Attending';
        return 'Amount';
    }

    get amountDisplay() {
        return this.amountLabel + ' ' + (this.response.amountRequested || 0);
    }

    get showPosterActions() {
        return this.isPoster && this.isThreadActive;
    }

    get showResponderActions() {
        return this.isResponder && !this.isPoster && this.isThreadActive;
    }

    get showAcceptDecline() {
        return !this.isNonThreadedEventOnly && this.isPoster && this.response.status === 'New';
    }

    get showComplete() {
        return !this.isNonThreadedEventOnly && this.isPoster && this.response.status === 'Accepted';
    }

    get showCancelForResponder() {
        return !this.isNonThreadedEventOnly && this.isResponder && !this.isPoster &&
            (this.response.status === 'New' || this.response.status === 'Accepted');
    }

    get showEditAmountButton() {
        return this.isResponder && !this.isPoster && this.tracksQuantity &&
            (this.response.status === 'New' || this.response.status === 'Accepted');
    }

    get isNonThreadedEvent() {
        if (this.post.type !== 'Event') return false;
        const et = this.post.eventType;
        return et === 'Open_Event' || et === 'Community_Event';
    }

    get nonThreadedEventMessage() {
        if (!this.isNonThreadedEvent) return '';
        if (this.post.eventType === 'Community_Event') {
            return 'Community Events use the detail page for interest — not a response thread like a Gathering.';
        }
        return 'Open Events use the detail page to join and message — not a response thread like a Gathering.';
    }

    get showNonThreadedNotice() {
        return this.isNonThreadedEvent && !this._allowEventMessaging;
    }

    get isNonThreadedEventOnly() {
        return this.isNonThreadedEvent && !this._allowEventMessaging;
    }

    get isAmountEditDisabled() {
        return !this.showEditAmountButton;
    }

    get responderName() {
        return this.response.responderName || this.response.contactName || 'Respondee';
    }

    get posterName() {
        return this.post.postedByName || 'Poster';
    }

    get otherPartyName() {
        return this.isPoster ? this.responderName : this.posterName;
    }

    get otherPartyInitials() {
        const name = this.otherPartyName;
        if (!name) return '?';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    _completeImageUrl(url) {
        if (!url) return null;
        if (url.startsWith('/resource/') || !url.startsWith('http')) {
            return url;
        }
        if (this.organizationId && !url.includes(this.organizationId)) {
            return url + this.organizationId;
        }
        return url;
    }

    _getInitials(name) {
        if (!name) return '?';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    get postStatusDisplay() {
        if (this.post.status === 'Expired' || this.post.status === 'Cancelled') {
            return this.post.status;
        }
        return this.post.status || 'Active';
    }

    get isPostInactive() {
        return this.post.status === 'Expired' || this.post.status === 'Cancelled' || this.post.status === 'Completed';
    }

    get thanksIconUrl() {
        return `${IMPACT_ICONS}/ThankYouActive.png`;
    }

    get postImageUrl() {
        const baseUrl = this.post.imageUrl;
        if (!baseUrl) return '';
        if (this.organizationId && !baseUrl.includes(this.organizationId)) {
            return baseUrl + this.organizationId;
        }
        return baseUrl;
    }

    get showShareContactPrompt() {
        return this.response.status === 'Accepted' && !this.contactShared;
    }

    get hasMiddleMessages() {
        return this._rawMiddle.length > 0 || (this.middleSystemMessages && this.middleSystemMessages.length > 0);
    }

    get middleCount() {
        return this._rawMiddle.length;
    }

    // --- Lifecycle ---

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this.hasMultipleIdentities = data.length > 0;
        } else if (error) {
            console.error('Error loading identities:', error);
            this.hasMultipleIdentities = false;
        }
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.myContactName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    async connectedCallback() {
        try {
            this.organizationId = await getOrganizationId();
        } catch (e) { /* non-critical */ }

        if (!this.responseId) {
            const params = new URLSearchParams(window.location.search);
            this.responseId = params.get('recordId') || '';
            this._allowEventMessaging = params.get('mode') === 'message';
        }
        if (this.responseId) {
            this.loadThread();
        } else {
            this.error = 'No response ID provided.';
            this.isLoading = false;
        }

        this._windowScrollHandler = () => {
            if (!this._scrollTicking) {
                requestAnimationFrame(() => {
                    this._handleScrollDirection();
                    this._scrollTicking = false;
                });
                this._scrollTicking = true;
            }
        };
        window.addEventListener('scroll', this._windowScrollHandler, { passive: true });
        requestAnimationFrame(() => this._measureHeaderHeight());
    }

    disconnectedCallback() {
        if (this._windowScrollHandler) {
            window.removeEventListener('scroll', this._windowScrollHandler);
        }
    }

    _measureHeaderHeight() {
        const header = document.querySelector('header.sticky-header');
        if (header) {
            const height = header.getBoundingClientRect().height;
            this.template.host.style.setProperty('--sticky-top', `${height}px`);
        }
    }

    _handleScrollDirection() {
        const currentY = window.scrollY || window.pageYOffset;
        const delta = currentY - this._lastScrollY;
        const isMobile = window.innerWidth < 768;

        if (isMobile) {
            if (delta > 10 && currentY > 80) {
                this.headerHidden = true;
            } else if (delta < -10) {
                this.headerHidden = false;
            }
        } else {
            this.headerHidden = false;
        }

        this._lastScrollY = currentY;
    }

    // --- Data Loading ---

    loadThread() {
        this.isLoading = true;
        this.error = null;
        this.middleRevealed = false;
        this.expandedIds = [];
        getThread({ responseId: this.responseId })
            .then(result => {
                if (result.success) {
                    this.response = result.response || {};
                    this.post = result.post || {};
                    this.isPoster = result.isPoster;
                    this.isResponder = result.isResponder;
                    this.myContactId = result.myContactId;
                    this.myContactName = result.myContactName;
                    this.myContactImageUrl = result.myContactImageUrl;
                    this.contactShared = result.contactShared;
                    this.messages = result.messages || [];
                    this.currentOffset = this.messages.length;
                    this.hasMoreMessages = this.messages.length >= PAGE_SIZE;
                    this.processMessages();
                    this.scrollToBottom();
                } else {
                    this.error = result.message || 'Unable to load thread.';
                }
            })
            .catch(err => {
                this.error = err.body?.message || err.message || 'Error loading thread.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleLoadMore() {
        if (this.isLoadingMore) return;
        this.isLoadingMore = true;
        getMessages({ responseId: this.responseId, pageSize: PAGE_SIZE, offset: this.currentOffset })
            .then(result => {
                if (result.success) {
                    const older = result.messages || [];
                    this.messages = [...this.messages, ...older];
                    this.currentOffset += older.length;
                    this.hasMoreMessages = older.length >= PAGE_SIZE;
                    this.middleRevealed = false;
                    this.expandedIds = [];
                    this.processMessages();
                }
            })
            .catch(() => {})
            .finally(() => {
                this.isLoadingMore = false;
            });
    }

    processMessages() {
        const items = [];
        let lastDate = null;

        const origDateKey = this.dateKey(this.response.createdDate);
        if (origDateKey) {
            items.push({
                id: 'date-' + origDateKey,
                isDateSeparator: true,
                dateText: this.formatDateLabel(this.response.createdDate)
            });
            lastDate = origDateKey;
        }

        const origIsFromMe = this.isResponder && !this.isPoster;
        const origDisplayName = origIsFromMe ? this.myContactName : this.responderName;
        const origAvatarUrl = origIsFromMe
            ? this._completeImageUrl(this.myContactImageUrl)
            : this._completeImageUrl(this.response.responderImageUrl);

        if (this.response.amountRequested) {
            items.push({
                id: 'amount-pill',
                isDateSeparator: false,
                isOriginalResponse: false,
                isSystemMessage: true,
                body: `${this.amountLabel}: ${this.response.amountRequested}`,
                formattedTime: this.formatTime(this.response.createdDate),
                formattedTimeShort: this.formatTimeShort(this.response.createdDate),
                formattedTimeRelative: this.formatTimeRelative(this.response.createdDate),
                systemMessageType: 'Amount_Request',
                cardClass: 'message-item system-message'
            });
        }

        const origIsOnBehalfOf = !!this.response.onBehalfOfId;
        const origCard = {
            id: 'original-response',
            isOriginalResponse: true,
            isDateSeparator: false,
            isSystemMessage: false,
            isFromCurrentUser: origIsFromMe,
            body: this.response.responseText,
            responderName: this.responderName,
            sentDate: this.response.createdDate,
            formattedDate: this.formatDate(this.response.createdDate),
            formattedTime: this.formatTime(this.response.createdDate),
            formattedTimeShort: this.formatTimeShort(this.response.createdDate),
            formattedTimeRelative: this.formatTimeRelative(this.response.createdDate),
            senderDisplayName: origDisplayName,
            senderInitials: this._getInitials(origDisplayName),
            senderAvatarUrl: origAvatarUrl,
            hasAvatarImage: !!origAvatarUrl,
            responderIsOrg: !!this.response.responderIsOrg,
            showViaLabel: origIsOnBehalfOf && !origIsFromMe && !this.response.responderIsOrg,
            viaLabel: origIsOnBehalfOf ? 'via ' + (this.response.contactName || '').split(' ')[0] : '',
            cardClass: 'message-card' + (origIsFromMe ? ' from-me' : ''),
            snippetText: this._getSnippet(this.response.responseText)
        };
        items.push(origCard);

        for (const msg of this.messages) {
            const dk = this.dateKey(msg.sentDate);
            if (dk && dk !== lastDate) {
                items.push({
                    id: 'date-' + dk,
                    isDateSeparator: true,
                    dateText: this.formatDateLabel(msg.sentDate)
                });
                lastDate = dk;
            }

            const isMe = msg.senderId === this.myContactId;
            const msgDisplayName = isMe ? this.myContactName : (msg.senderName || this.otherPartyName);
            const msgAvatarUrl = isMe
                ? this._completeImageUrl(this.myContactImageUrl)
                : this._completeImageUrl(msg.senderImageUrl);

            const isThanksMsg = msg.isSystemMessage && msg.systemMessageType === 'Thanks_Sent';

            items.push({
                id: msg.id,
                isDateSeparator: false,
                isOriginalResponse: false,
                isSystemMessage: msg.isSystemMessage,
                isThanksMessage: isThanksMsg,
                body: msg.body,
                senderId: msg.senderId,
                senderName: msg.senderName,
                isFromCurrentUser: isMe,
                senderIsOrg: !!msg.senderIsOrg,
                sentDate: msg.sentDate,
                formattedTime: this.formatTime(msg.sentDate),
                formattedTimeShort: this.formatTimeShort(msg.sentDate),
                formattedTimeRelative: this.formatTimeRelative(msg.sentDate),
                readDate: msg.readDate,
                systemMessageType: msg.systemMessageType,
                senderDisplayName: msgDisplayName,
                senderInitials: this._getInitials(msgDisplayName),
                senderAvatarUrl: msgAvatarUrl,
                hasAvatarImage: !!msgAvatarUrl,
                cardClass: msg.isSystemMessage
                    ? 'message-item system-message'
                    : 'message-card' + (isMe ? ' from-me' : ''),
                snippetText: this._getSnippet(msg.body)
            });
        }

        // Split into zones — only user messages count toward thresholds
        const realMessages = items.filter(m => !m.isDateSeparator);
        const userMessages = realMessages.filter(m => !m.isSystemMessage);

        if (userMessages.length < ZONE_THRESHOLD) {
            this.useZones = false;
            this.processedMessages = items;
            this.firstMessage = null;
            this.headerSystemMessages = [];
            this._rawMiddle = [];
            this._rawMiddleAll = [];
            this.middleMessages = [];
            this.middleSystemMessages = [];
            this.lastMessages = [];
        } else {
            this.useZones = true;

            const firstUser = userMessages[0];
            const firstUserIdx = realMessages.indexOf(firstUser);
            this.headerSystemMessages = realMessages.slice(0, firstUserIdx);
            this.firstMessage = { ...firstUser, cardClass: (firstUser.cardClass || 'message-card') + ' zone-first' };

            const usePill = userMessages.length >= PILL_THRESHOLD;
            const lastCount = usePill ? 2 : 1;
            const lastStart = realMessages.indexOf(userMessages[userMessages.length - lastCount]);
            const middleAll = realMessages.slice(firstUserIdx + 1, lastStart);

            this._rawMiddle = middleAll.filter(m => !m.isSystemMessage);
            this._rawMiddleAll = middleAll;
            this.middleSystemMessages = middleAll.filter(m => m.isSystemMessage);
            this.lastMessages = realMessages.slice(lastStart);

            this.middleRevealed = !usePill;
            this._recomputeMiddle();
            this.processedMessages = [];
        }
    }

    _recomputeMiddle() {
        this.middleMessages = (this._rawMiddleAll || []).map(m => ({
            ...m,
            isExpanded: m.isSystemMessage ? true : this.expandedIds.includes(m.id)
        }));
    }

    _getSnippet(body) {
        if (!body) return '';
        const cleaned = body.replace(/[\n\r]+/g, ' ').trim();
        return cleaned.length > SNIPPET_LENGTH
            ? cleaned.substring(0, SNIPPET_LENGTH) + '…'
            : cleaned;
    }

    // Collapse / expand handlers
    handleRevealMiddle() {
        this.middleRevealed = true;
    }

    handleRevealMiddleKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleRevealMiddle();
        }
    }

    handleExpandMessage(event) {
        const msgId = event.currentTarget.dataset.msgId;
        if (!msgId) return;
        if (this.expandedIds.includes(msgId)) {
            this.expandedIds = this.expandedIds.filter(id => id !== msgId);
        } else {
            this.expandedIds = [...this.expandedIds, msgId];
        }
        this._recomputeMiddle();
    }

    handleExpandMessageKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleExpandMessage(event);
        }
    }

    // --- Send Message ---

    handleMessageInput(event) {
        this.messageText = event.target.value;
        this.autoResizeTextarea(event.target);
    }

    handleShowCompose() {
        this.showCompose = true;
        setTimeout(() => {
            const textarea = this.template.querySelector('.compose-input');
            if (textarea) {
                textarea.scrollIntoView({ behavior: 'smooth', block: 'center' });
                textarea.focus();
            }
        }, 100);
    }

    handleCancelCompose() {
        this.showCompose = false;
        this.messageText = '';
    }

    handleSendMessage() {
        if (this.isSendDisabled) return;
        const body = this.messageText.trim();
        this.isSending = true;
        this.messageText = '';

        const textarea = this.template.querySelector('.message-input');
        if (textarea) {
            textarea.style.height = 'auto';
        }

        sendMessageApex({ responseId: this.responseId, body })
            .then(result => {
                if (result.success) {
                    this.messages.push({
                        id: result.messageId,
                        body: body,
                        senderId: this.myContactId,
                        senderName: this.myContactName,
                        sentDate: result.sentDate || new Date().toISOString(),
                        isSystemMessage: false
                    });
                    this.processMessages();
                    this.scrollToBottom();
                    this.showCompose = false;
                    this.messageText = '';
                }
            })
            .catch(() => {})
            .finally(() => {
                this.isSending = false;
            });
    }

    autoResizeTextarea(el) {
        el.style.height = 'auto';
        el.style.height = Math.min(el.scrollHeight, 120) + 'px';
    }

    // --- Status Actions ---

    handleAccept() {
        this.confirmAction = 'accept';
        this.confirmTitle = 'Accept this response?';
        this.confirmMessage = 'Accept this response from ' + this.responderName + '?';
        this.confirmButtonLabel = 'Accept';
        this.confirmButtonVariant = 'brand';
        this.showConfirmDialog = true;
    }

    handleDecline() {
        this.confirmAction = 'decline';
        this.confirmTitle = 'Decline this response?';
        this.confirmMessage = 'Decline this response from ' + this.responderName + '?';
        this.confirmButtonLabel = 'Decline';
        this.confirmButtonVariant = 'destructive';
        this.showConfirmDialog = true;
    }

    handleCancel() {
        this.confirmAction = 'cancel';
        this.confirmTitle = 'Cancel your response?';
        this.confirmMessage = 'This will release your reserved spot.';
        this.confirmButtonLabel = 'Yes, Cancel';
        this.confirmButtonVariant = 'destructive';
        this.showConfirmDialog = true;
    }

    handleComplete() {
        this.confirmAction = 'complete';
        this.confirmTitle = 'Mark as complete?';
        this.confirmMessage = 'Mark this response as complete?';
        this.confirmButtonLabel = 'Complete';
        this.confirmButtonVariant = 'brand';
        this.showConfirmDialog = true;
    }

    handleConfirmDialogClose() {
        this.showConfirmDialog = false;
        this.confirmAction = null;
    }

    handleConfirmDialogConfirm() {
        const action = this.confirmAction;
        this.showConfirmDialog = false;
        this.confirmAction = null;

        if (action === 'accept') this.executeAccept();
        else if (action === 'decline') this.executeDecline();
        else if (action === 'cancel') this.executeCancel();
        else if (action === 'complete') this.executeComplete();
    }

    executeAccept() {
        acceptResponseApex({ responseId: this.responseId })
            .then(result => {
                if (result.success) {
                    this.response = { ...this.response, status: result.newStatus };
                    this.appendSystemMessage(result.message);
                }
            })
            .catch(() => {});
    }

    executeDecline() {
        declineResponseApex({ responseId: this.responseId })
            .then(result => {
                if (result.success) {
                    this.response = { ...this.response, status: result.newStatus };
                    this.appendSystemMessage(result.message);
                }
            })
            .catch(() => {});
    }

    executeCancel() {
        cancelResponseApex({ responseId: this.responseId })
            .then(result => {
                if (result.success) {
                    this.response = { ...this.response, status: result.newStatus };
                    this.appendSystemMessage(result.message);
                }
            })
            .catch(() => {});
    }

    executeComplete() {
        completeResponseApex({ responseId: this.responseId })
            .then(result => {
                if (result.success) {
                    this.response = { ...this.response, status: result.newStatus };
                    this.appendSystemMessage(result.message);
                }
            })
            .catch(() => {});
    }

    appendSystemMessage(body) {
        this.messages.push({
            id: 'sys-' + Date.now(),
            body: body,
            senderId: this.myContactId,
            senderName: '',
            sentDate: new Date().toISOString(),
            isSystemMessage: true,
            systemMessageType: 'Status_Change'
        });
        this.processMessages();
        this.scrollToBottom();
    }

    // --- Edit Amount ---

    handleEditAmount() {
        this.editAmountValue = this.response.amountRequested;
        this.editAmountError = '';
        this.showEditAmount = true;
    }

    handleEditAmountInput(event) {
        this.editAmountValue = parseInt(event.target.value, 10);
        this.editAmountError = '';
    }

    handleEditAmountClose() {
        this.showEditAmount = false;
    }

    handleEditAmountSave() {
        if (!this.editAmountValue || this.editAmountValue < 1) {
            this.editAmountError = 'Must be at least 1.';
            return;
        }

        updateResponseAmount({ responseId: this.responseId, newAmount: this.editAmountValue })
            .then(result => {
                if (result.success) {
                    this.response = { ...this.response, amountRequested: result.newAmount };
                    this.showEditAmount = false;
                    this.appendSystemMessage(
                        this.myContactName + ' updated their request to ' + result.newAmount
                    );
                } else {
                    this.editAmountError = result.message || 'Unable to update amount.';
                }
            })
            .catch(err => {
                this.editAmountError = err.body?.message || 'Error updating amount.';
            });
    }

    // --- Contact Sharing ---

    handleShareContact() {
        this.shareContactError = '';
        getShareContactInfoData({ responseId: this.responseId })
            .then(result => {
                if (result.success) {
                    this.shareContactData = result;
                    const sc = result.sharingContact || {};
                    this.shareEmailValue = sc.email || '';
                    this.sharePhoneValue = sc.phone || '';
                    this.shareStreet = sc.street || '';
                    this.shareCity = sc.city || '';
                    this.shareState = sc.state || '';
                    this.sharePostalCode = sc.postalCode || '';
                    this.showShareContact = true;
                } else {
                    this.shareContactError = result.message || 'Unable to load contact info.';
                }
            })
            .catch(err => {
                this.shareContactError = err.body?.message || err.message || 'Error loading contact data.';
            });
    }

    handleShareContactClose() {
        this.showShareContact = false;
    }

    handleShareEmailToggle(event) { this.shareEmail = event.target.checked; }
    handleSharePhoneToggle(event) { this.sharePhone = event.target.checked; }
    handleShareAddressToggle(event) { this.shareAddress = event.target.checked; }
    handleShareEmailInput(event) { this.shareEmailValue = event.target.value; }
    handleSharePhoneInput(event) { this.sharePhoneValue = event.target.value; }
    handleShareStreetInput(event) { this.shareStreet = event.target.value; }
    handleShareCityInput(event) { this.shareCity = event.target.value; }
    handleShareStateInput(event) { this.shareState = event.target.value; }
    handleSharePostalCodeInput(event) { this.sharePostalCode = event.target.value; }

    handleShareContactSubmit() {
        if (this.isShareSubmitting) return;
        this.isShareSubmitting = true;
        this.shareContactError = '';

        const data = {
            responseId: this.responseId,
            sharingContactId: this.shareContactData.sharingContact.id,
            recipientContactId: this.shareContactData.recipient.id,
            shareEmail: this.shareEmail,
            sharePhone: this.sharePhone,
            shareAddress: this.shareAddress,
            email: this.shareEmailValue,
            phone: this.sharePhoneValue,
            street: this.shareStreet,
            city: this.shareCity,
            state: this.shareState,
            postalCode: this.sharePostalCode
        };

        shareContactInfoApex({ shareData: JSON.stringify(data) })
            .then(result => {
                if (result.success) {
                    this.contactShared = true;
                    this.showShareContact = false;
                    this.appendSystemMessage(this.myContactName + ' shared their contact info');
                } else {
                    this.shareContactError = result.message || 'Unable to share contact info.';
                }
            })
            .catch(err => {
                this.shareContactError = err.body?.message || err.message || 'Error sharing contact info. Please try again.';
            })
            .finally(() => {
                this.isShareSubmitting = false;
            });
    }

    handleDismissSharePrompt() {
        this.contactShared = true;
    }

    // --- Block / Report (A3: mirrors fimbyConversationView pattern) ---

    /**
     * Resolves the Contact Id of the other party in this thread. The poster
     * blocks the responder; the responder blocks the poster.
     */
    get otherPartyContactId() {
        if (this.isPoster && !this.isResponder) {
            return this.response.responderContactId
                || this.response.responderId
                || this.response.contactId
                || null;
        }
        return this.post.postedById || this.post.posterId || this.post.contactId || null;
    }

    get otherPartyFirstName() {
        const name = this.otherPartyName || '';
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
            // Single round-trip writes Blocked_Contact__c and (when isReport
            // is true) the moderator task via FimbyModeratorTaskService —
            // see FimbyConversationController.blockContactInternal for the
            // server-side branching. Same contract as fimbyConversationView.
            await blockContactApex({
                blockedContactId: this.otherPartyContactId,
                reason: this.blockReason,
                isReport: this.isReporting,
                reportDetails: this.reportDetails
            });
            this.showBlockModal = false;
            // Land back on Messages so the user is out of the thread they
            // just blocked, matching fimbyConversationView's redirect.
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

    // --- Navigation ---

    handleBack() {
        if (window.history.length > 1) {
            window.history.back();
        } else {
            window.location.href = '/messages';
        }
    }

    handlePostClick() {
        if (this.post.id) {
            window.location.href = '/asks-offers/' + this.post.id;
        }
    }

    handleTogglePostExpand() {
        this.postExpanded = !this.postExpanded;
    }

    // --- Utilities ---

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.template.querySelector('.messages-container');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 100);
    }

    formatTime(dt) {
        if (!dt) return '';
        const d = new Date(dt);
        const now = new Date();
        const isToday = d.toDateString() === now.toDateString();
        const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
        if (isToday) return time;
        const day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
        const diffDays = Math.floor((now - d) / 86400000);
        let relative = '';
        if (diffDays === 1) relative = ' (1 day ago)';
        else if (diffDays > 1 && diffDays < 30) relative = ` (${diffDays} days ago)`;
        return `${day}, ${time}${relative}`;
    }

    formatTimeShort(dt) {
        if (!dt) return '';
        const d = new Date(dt);
        const now = new Date();
        if (d.toDateString() === now.toDateString()) {
            return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
        }
        return d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
    }

    formatTimeRelative(dt) {
        if (!dt) return '';
        const d = new Date(dt);
        const now = new Date();
        if (d.toDateString() === now.toDateString()) return '';
        const diffDays = Math.floor((now - d) / 86400000);
        if (diffDays === 1) return ' (1 day ago)';
        if (diffDays > 1 && diffDays < 30) return ` (${diffDays} days ago)`;
        return '';
    }

    formatDate(dt) {
        if (!dt) return '';
        const d = new Date(dt);
        return d.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
    }

    formatDateLabel(dt) {
        if (!dt) return '';
        const d = new Date(dt);
        const today = new Date();
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);

        if (d.toDateString() === today.toDateString()) return 'Today';
        if (d.toDateString() === yesterday.toDateString()) return 'Yesterday';
        return d.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
    }

    dateKey(dt) {
        if (!dt) return null;
        const d = new Date(dt);
        return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
    }
}