import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import getMessages from '@salesforce/apex/FimbyMessageController.getMessages';
import sendMessage from '@salesforce/apex/FimbyMessageController.sendMessage';
import blockContact from '@salesforce/apex/FimbyConversationController.blockContact';
import checkConversationRevoked from '@salesforce/apex/FimbyConversationController.isConversationRevoked';
import prepareDirectConversation from '@salesforce/apex/FimbyConversationController.prepareDirectConversation';
import sendDirectMessage from '@salesforce/apex/FimbyConversationController.sendDirectMessage';
import getFollowUpByConversation from '@salesforce/apex/FimbyFollowUpController.getFollowUpByConversation';
import resolveFollowUp from '@salesforce/apex/FimbyFollowUpController.resolveFollowUp';
import escalateFollowUp from '@salesforce/apex/FimbyFollowUpController.escalateFollowUp';
import getLendingConversationContext from '@salesforce/apex/FimbyLendingController.getLendingConversationContext';
import getVouchContextForConversation from '@salesforce/apex/FimbyVouchController.getVouchContextForConversation';
import approveVouch from '@salesforce/apex/FimbyVouchController.approveVouch';
import withdrawVouchRequest from '@salesforce/apex/FimbyVouchController.withdrawVouchRequest';
import { getHeaderBadge } from 'c/fimbyThreadBadgeConfig';

function resolveAvatarUrl(url) {
    if (!url) return null;
    if (url.startsWith('/resource/') || !url.startsWith('http')) return url;
    return avatarImageUrl(url);
}

const PAGE_SIZE = 50;
const ZONE_THRESHOLD = 3;
const PILL_THRESHOLD = 5;
const SNIPPET_LENGTH = 80;

export default class FimbyConversationView extends NavigationMixin(LightningElement) {
    @api conversationId = '';
    @api targetContactId = '';
    @track isDraft = false;
    @track messages = [];
    @track processedMessages = [];
    @track messageText = '';
    @track hasMoreMessages = true;
    @track isLoadingMore = false;
    @track isLoading = true;
    @track isSending = false;
    @track showCompose = false;
    @track totalCount = 0;
    @track currentOffset = 0;

    @track otherParticipantName = '';
    @track otherParticipantFirstName = '';
    @track otherParticipantId = '';
    @track otherParticipantImageUrl = '';
    @track myContactId = '';
    @track myContactImageUrl = '';

    @track isOtherParticipantOrg = false;

    @track isActingAsSelf = true;
    @track actingAsContactName = '';
    @track hasMultipleIdentities = false;

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
        return this.hasMultipleIdentities && !!this.actingAsContactName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    @track showBlockModal = false;
    @track blockReason = '';
    @track isReporting = false;
    @track reportDetails = '';

    @track showNeighbourlyBanner = true;
    @track isConversationRevoked = false;
    @track isConversationLocked = false;

    get showDisconnectedBanner() {
        return this.isConversationRevoked && !this.isVouchContext;
    }

    get canReply() {
        return !this.isConversationRevoked && !this.isConversationLocked && !this.isVouchContext;
    }

    @track followUpId = null;
    @track followUpStatus = null;
    @track isFollowUpConversation = false;
    @track isResolvingFollowUp = false;

    // Related record context (header badge + title)
    @track contextType = '';
    @track relatedRecordId = '';
    @track relatedRecordTitle = '';

    // Lending lifecycle context
    @track lendingContext = null;
    @track isLendingConversation = false;
    @track isLendingHandoffProcessing = false;

    // Vouch context
    @track vouchContext = null;
    @track isVouchActionProcessing = false;
    @track vouchActionError = '';

    _composeAutoOpened = false;

    @track useZones = false;
    @track firstMessage = null;
    @track headerSystemMessages = [];
    @track middleMessages = [];
    @track middleSystemMessages = [];
    @track lastMessages = [];
    @track middleRevealed = false;
    @track expandedIds = [];

    _rawMiddle = [];

    get isFirstExpanded() {
        return this.firstMessage ? this.expandedIds.includes(this.firstMessage.id) : false;
    }

    get isSendDisabled() {
        return !this.messageText || !this.messageText.trim() || this.isSending;
    }

    get showOnBehalfHeader() {
        return !this.isActingAsSelf && this.actingAsContactName;
    }

    get onBehalfHeaderText() {
        return `Messaging as: ${this.actingAsContactName}`;
    }

    // ── Related record header (badge + title link) ──────────────────
    get hasRelatedRecord() {
        const badge = getHeaderBadge(this.contextType);
        if (!badge) return false;
        if (this.contextType === 'Library_Lending') return !!this.lendingItemName;
        if (this.contextType === 'Vouch_Request')   return false;
        return !!this.relatedRecordTitle;
    }

    // ── Vouch context getters ──────────────────────────────────────
    get isVouchContext() {
        return this.contextType === 'Vouch_Request';
    }

    get isVouchPending() {
        return this.isVouchContext
            && this.vouchContext
            && this.vouchContext.outcome === 'Pending';
    }

    get isVouchDecided() {
        return this.isVouchContext
            && this.vouchContext
            && this.vouchContext.outcome
            && this.vouchContext.outcome !== 'Pending';
    }

    get showVouchAcceptDecline() {
        return this.isVouchPending && this.vouchContext?.isRecipient === true;
    }

    get showVouchWithdraw() {
        return this.isVouchPending && this.vouchContext?.isRequester === true;
    }

    get vouchBannerMessage() {
        if (!this.vouchContext) return '';
        if (this.isVouchPending) {
            if (this.vouchContext.isRecipient) {
                const name = this.vouchContext.requesterFirstName || this.vouchContext.requesterName || 'A neighbour';
                return `${name} is asking you to vouch for them. Vouching means you know this person and they belong here. It unlocks the lending library for them.`;
            }
            if (this.vouchContext.isRequester) {
                const refName = this.vouchContext.referenceFirstName
                    || this.vouchContext.referenceName
                    || this.vouchContext.organizationName
                    || 'them';
                return `Waiting for ${refName} to respond. We will let you know.`;
            }
            return '';
        }
        if (this.isVouchDecided) {
            const decidedDate = this._formatVouchDate(this.vouchContext.decidedDate);
            const refName = this.vouchContext.referenceFirstName
                || this.vouchContext.referenceName
                || this.vouchContext.organizationName
                || 'they';
            const reqName = this.vouchContext.requesterFirstName || this.vouchContext.requesterName || 'this neighbour';
            switch (this.vouchContext.outcome) {
                case 'Approved':  return `Vouched on ${decidedDate} by ${refName}.`;
                case 'Declined':  return `Declined on ${decidedDate}.`;
                case 'Withdrawn': return `${reqName} withdrew this request on ${decidedDate}.`;
                case 'Expired':   return `This request expired on ${decidedDate}.`;
                default:          return '';
            }
        }
        return '';
    }

    get vouchOutcomeBannerClass() {
        switch (this.vouchContext?.outcome) {
            case 'Approved':  return 'lending-action-banner lending-banner-success';
            case 'Declined':  return 'lending-action-banner lending-banner-info';
            case 'Withdrawn': return 'lending-action-banner lending-banner-info';
            case 'Expired':   return 'lending-action-banner lending-banner-info';
            default:          return 'lending-action-banner lending-banner-info';
        }
    }

    _formatVouchDate(dtString) {
        if (!dtString) return '';
        try {
            const d = new Date(dtString);
            return d.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
        } catch (e) {
            return '';
        }
    }

    get headerBadgeLabel() {
        return getHeaderBadge(this.contextType)?.label || '';
    }

    get headerBadgeCssClass() {
        return getHeaderBadge(this.contextType)?.cssClass || '';
    }

    get relatedRecordDisplayTitle() {
        if (this.contextType === 'Library_Lending') return this.lendingItemName;
        return this.relatedRecordTitle || '';
    }

    get relatedRecordHref() {
        if (this.contextType === 'Library_Lending') {
            const id = this.lendingContext?.libraryItemId;
            return id ? `/library-item/${id}/` : '#';
        }
        return this.relatedRecordId ? `/asks-offers/${this.relatedRecordId}/` : '#';
    }

    get showFollowUpBanner() {
        return this.isFollowUpConversation && this.followUpStatus === 'Pending';
    }

    get showFollowUpResolvedBanner() {
        return this.isFollowUpConversation && this.followUpStatus && this.followUpStatus !== 'Pending';
    }

    get followUpResolvedText() {
        const map = {
            'Resolved': 'This has been resolved.',
            'No_Response': 'No response was received. This has been recorded.',
            'Escalated': 'This has been escalated to an admin.',
            'Admin_Cleared': 'An admin has cleared this.',
            'Admin_Confirmed': 'An admin has confirmed this.',
            'Expired': 'This check-in has expired.'
        };
        return map[this.followUpStatus] || '';
    }

    get participantInitials() {
        if (!this.otherParticipantName) return '?';
        return this.otherParticipantName.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    get participantAvatarUrl() {
        return resolveAvatarUrl(this.otherParticipantImageUrl);
    }

    _getInitials(name) {
        if (!name) return '?';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    get hasMiddleMessages() {
        return this._rawMiddle.length > 0 || (this.middleSystemMessages && this.middleSystemMessages.length > 0);
    }

    get middleCount() {
        return this._rawMiddle.length;
    }

    connectedCallback() {
        if (this.conversationId) {
            this.loadMessages();
        } else if (this.targetContactId) {
            this.loadDraft();
        }

        if (sessionStorage.getItem('fimby_neighbourly_dismissed') === 'true') {
            this.showNeighbourlyBanner = false;
        }
    }

    _replaceConversationUrl(conversationId) {
        const url = new URL(window.location.href);
        url.searchParams.delete('contactId');
        url.searchParams.set('id', conversationId);
        window.history.replaceState({}, '', url.pathname + url.search);
    }

    async loadDraft() {
        this.isLoading = true;
        this.middleRevealed = false;
        this.expandedIds = [];
        try {
            const result = await prepareDirectConversation({ targetContactId: this.targetContactId });

            if (result.isExisting && result.conversationId) {
                this.conversationId = result.conversationId;
                this.targetContactId = '';
                this.isDraft = false;
                this._replaceConversationUrl(result.conversationId);
                await this.loadMessages();
                return;
            }

            this.otherParticipantName = result.otherParticipantName;
            this.otherParticipantFirstName = result.otherParticipantFirstName;
            this.otherParticipantId = result.otherParticipantId;
            this.otherParticipantImageUrl = result.otherParticipantImageUrl;
            this.myContactId = result.myContactId;
            this.myContactImageUrl = result.myContactImageUrl;
            this.isActingAsSelf = result.isActingAsSelf;
            this.actingAsContactName = result.actingAsContactName;
            this.isOtherParticipantOrg = result.isOtherParticipantOrg || false;
            this.contextType = 'Direct';
            this.messages = [];
            this.totalCount = 0;
            this.isDraft = true;
            this._maybeAutoOpenCompose();
        } catch (error) {
            console.error('Error preparing draft conversation:', error);
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }

    async loadMessages() {
        this.isLoading = true;
        this.middleRevealed = false;
        this.expandedIds = [];
        try {
            const result = await getMessages({
                conversationId: this.conversationId,
                pageSize: PAGE_SIZE,
                offset: this.currentOffset
            });

            this.otherParticipantName = result.otherParticipantName;
            this.otherParticipantFirstName = result.otherParticipantFirstName;
            this.otherParticipantId = result.otherParticipantId;
            this.otherParticipantImageUrl = result.otherParticipantImageUrl;
            this.myContactId = result.myContactId;
            this.myContactImageUrl = result.myContactImageUrl;
            this.isActingAsSelf = result.isActingAsSelf;
            this.actingAsContactName = result.actingAsContactName;
            this.isOtherParticipantOrg = result.isOtherParticipantOrg || false;
            this.totalCount = result.totalCount;
            this.contextType = result.contextType || '';
            this.relatedRecordId = result.relatedRecordId || '';
            this.relatedRecordTitle = result.relatedRecordTitle || '';
            this.isConversationLocked = result.isLocked === true;

            this.messages = result.messages || [];
            this.hasMoreMessages = this.messages.length < this.totalCount;
            this.processMessages();

            try {
                this.isConversationRevoked = await checkConversationRevoked({ conversationId: this.conversationId });
            } catch (e) {
                console.error('Error checking revoke status:', e);
            }

            this._checkForFollowUp();
            this._checkForLendingContext(result.contextType);
            this._checkForVouchContext(result.contextType);
        } catch (error) {
            console.error('Error loading messages:', error);
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
            this._maybeAutoOpenCompose();
        }
    }

    _maybeAutoOpenCompose() {
        if (this._composeAutoOpened) return;
        if (this.isConversationRevoked) return;
        if (this.isVouchContext) return;
        if (this.isConversationLocked) return;
        if (this.messages && this.messages.length > 0) return;
        this._composeAutoOpened = true;
        this.handleShowCompose();
    }

    async _checkForFollowUp() {
        try {
            const result = await getFollowUpByConversation({ conversationId: this.conversationId });
            if (result && result.followUpId) {
                this.followUpId = result.followUpId;
                this.followUpStatus = result.status;
                this.isFollowUpConversation = true;
            }
        } catch (e) {
            // Not a follow-up conversation, ignore
        }
    }

    async _checkForLendingContext(contextType) {
        if (contextType !== 'Library_Lending') return;
        try {
            const ctx = await getLendingConversationContext({ conversationId: this.conversationId });
            if (ctx && ctx.phase) {
                this.lendingContext = ctx;
                this.isLendingConversation = true;
            }
        } catch (e) {
            console.error('Error loading lending context:', e);
        }
    }

    async _checkForVouchContext(contextType) {
        if (contextType !== 'Vouch_Request') return;
        try {
            const ctx = await getVouchContextForConversation({ conversationId: this.conversationId });
            if (ctx) {
                this.vouchContext = ctx;
            }
        } catch (e) {
            console.error('Error loading vouch context:', e);
        }
    }

    // ── Vouch action handlers ──────────────────────────────────────

    async handleVouchApprove() {
        if (this.isVouchActionProcessing || !this.vouchContext?.vouchRecordId) return;
        this.isVouchActionProcessing = true;
        this.vouchActionError = '';
        try {
            await approveVouch({ vouchRecordId: this.vouchContext.vouchRecordId });
            await this.loadMessages();
        } catch (error) {
            console.error('Error approving vouch:', error);
            this.vouchActionError = error?.body?.message || error?.message || 'Could not record your vouch. Please try again.';
        } finally {
            this.isVouchActionProcessing = false;
        }
    }

    handleVouchDeclineClick() {
        if (this.isVouchActionProcessing || !this.vouchContext?.vouchRecordId) return;
        const modal = this.template.querySelector('c-fimby-vouch-decline-modal');
        if (modal) {
            modal.show(this.vouchContext.vouchRecordId);
        }
    }

    handleVouchDeclineSubmitted() {
        this.loadMessages();
    }

    async handleVouchWithdraw() {
        if (this.isVouchActionProcessing || !this.vouchContext?.vouchRecordId) return;
        if (!confirm('Withdraw this vouch request?')) return;
        this.isVouchActionProcessing = true;
        this.vouchActionError = '';
        try {
            await withdrawVouchRequest({ vouchRecordId: this.vouchContext.vouchRecordId });
            await this.loadMessages();
        } catch (error) {
            console.error('Error withdrawing vouch:', error);
            this.vouchActionError = error?.body?.message || error?.message || 'Could not withdraw the request. Please try again.';
        } finally {
            this.isVouchActionProcessing = false;
        }
    }

    // ── Lending banner getters ─────────────────────────────────────

    get showLendingBanner() {
        return this.isLendingConversation && this.lendingContext?.phase &&
               this.lendingContext.phase !== 'returned';
    }

    get lendingPhase() { return this.lendingContext?.phase || ''; }
    get lendingIsOwner() { return this.lendingContext?.isOwner === true; }
    get lendingItemName() { return this.lendingContext?.itemName || 'this item'; }
    get lendingOtherName() { return this.lendingContext?.otherParticipantName || ''; }

    get lendingBannerMessage() {
        const phase = this.lendingPhase;
        const item = this.lendingItemName;
        const other = this.lendingOtherName;
        if (phase === 'approved') {
            return this.lendingIsOwner
                ? `${other} picked up ${item}?`
                : `Picked up ${item}?`;
        }
        if (phase === 'onLoan' && !this.lendingIsOwner) return '';
        if (phase === 'overdue') return 'This item is overdue.';
        if (phase === 'extensionRequested') {
            return this.lendingIsOwner
                ? 'Extension requested'
                : 'Extension requested \u2014 waiting for the owner.';
        }
        if (phase === 'returnPending') {
            return this.lendingIsOwner
                ? 'Return reported'
                : 'Waiting for the owner to verify return.';
        }
        return '';
    }

    get lendingBannerClass() {
        const phase = this.lendingPhase;
        if (phase === 'approved') return 'lending-action-banner lending-banner-success';
        if (phase === 'overdue') return 'lending-action-banner lending-banner-warning';
        if (phase === 'extensionRequested' || phase === 'returnPending') return 'lending-action-banner lending-banner-info';
        return 'lending-action-banner lending-banner-info';
    }

    get showLendingHandoffAction() {
        return this.lendingPhase === 'approved';
    }

    get lendingHandoffLabel() {
        return this.lendingIsOwner ? 'Mark as Picked Up' : 'I Have the Item';
    }

    get showLendingCancelRequest() {
        return this.lendingPhase === 'approved' && !this.lendingIsOwner;
    }

    get showLendingReturnAction() {
        return !this.lendingIsOwner && (this.lendingPhase === 'onLoan' || this.lendingPhase === 'overdue');
    }

    get showLendingExtensionAction() {
        return !this.lendingIsOwner && this.lendingPhase === 'onLoan';
    }

    get showLendingApproveExtension() {
        return this.lendingIsOwner && this.lendingPhase === 'extensionRequested';
    }

    get showLendingVerifyReturn() {
        return this.lendingIsOwner && this.lendingPhase === 'returnPending';
    }

    handleReturnNavigate() {
        const libraryItemId = this.lendingContext?.libraryItemId;
        const loanId = this.lendingContext?.loanId;
        if (libraryItemId && loanId) {
            window.location.href = `/library-item/${libraryItemId}/?action=return&loanId=${loanId}`;
        }
    }

    get lendingExtensionUrl() {
        const libId = this.lendingContext?.libraryItemId;
        const loanId = this.lendingContext?.loanId;
        return (libId && loanId) ? `/library-item/${libId}/?action=requestExtension&loanId=${loanId}` : '#';
    }

    get lendingApproveExtensionUrl() {
        const libId = this.lendingContext?.libraryItemId;
        const loanId = this.lendingContext?.loanId;
        return (libId && loanId) ? `/library-item/${libId}/?action=approveExtension&loanId=${loanId}` : '#';
    }

    get lendingViewItemUrl() {
        const id = this.lendingContext?.libraryItemId;
        return id ? `/library-item/${id}/` : '#';
    }

    // Show banner content only when there's a message or actions
    get showLendingBannerContent() {
        if (this.lendingPhase === 'onLoan' && this.lendingIsOwner) return false;
        return true;
    }

    handleLendingHandoff() {
        const libId = this.lendingContext?.libraryItemId;
        const reqId = this.lendingContext?.requestId;
        if (libId && reqId) {
            window.location.href = `/library-item/${libId}/?action=confirmPickup&requestId=${reqId}`;
        }
    }

    async handleResolveFollowUp() {
        if (!this.followUpId || this.isResolvingFollowUp) return;
        this.isResolvingFollowUp = true;
        try {
            await resolveFollowUp({ followUpId: this.followUpId });
            this.followUpStatus = 'Resolved';
        } catch (error) {
            console.error('Error resolving follow-up:', error);
        } finally {
            this.isResolvingFollowUp = false;
        }
    }

    async handleEscalateFollowUp() {
        if (!this.followUpId || this.isResolvingFollowUp) return;
        this.isResolvingFollowUp = true;
        try {
            await escalateFollowUp({ followUpId: this.followUpId });
            this.followUpStatus = 'Escalated';
        } catch (error) {
            console.error('Error escalating follow-up:', error);
        } finally {
            this.isResolvingFollowUp = false;
        }
    }

    async handleLoadMore() {
        if (this.isLoadingMore || !this.hasMoreMessages) return;

        this.isLoadingMore = true;
        const newOffset = this.currentOffset + PAGE_SIZE;

        try {
            const result = await getMessages({
                conversationId: this.conversationId,
                pageSize: PAGE_SIZE,
                offset: newOffset
            });

            if (result.messages && result.messages.length > 0) {
                this.currentOffset = newOffset;
                this.messages = [...result.messages, ...this.messages];
                this.hasMoreMessages = this.messages.length < result.totalCount;
                this.middleRevealed = false;
                this.expandedIds = [];
                this.processMessages();
            } else {
                this.hasMoreMessages = false;
            }
        } catch (error) {
            console.error('Error loading more messages:', error);
        } finally {
            this.isLoadingMore = false;
        }
    }

    processMessages() {
        const processed = [];
        let lastDate = null;

        this.messages.forEach(msg => {
            const messageDate = new Date(msg.sentDate);
            const currentDate = messageDate.toDateString();

            if (currentDate !== lastDate) {
                processed.push({
                    id: `date-${currentDate}`,
                    isDateSeparator: true,
                    dateText: this.formatDateSeparator(messageDate)
                });
                lastDate = currentDate;
            }

            const isMine = msg.isMine;
            const isOnBehalfOf = msg.isOnBehalfOf;

            const displayName = isMine
                ? (this.actingAsContactName || 'You')
                : (msg.senderName || this.otherParticipantName);
            const avatarUrl = isMine
                ? resolveAvatarUrl(this.myContactImageUrl)
                : resolveAvatarUrl(msg.senderImageUrl || this.otherParticipantImageUrl);

            processed.push({
                ...msg,
                isDateSeparator: false,
                isFromCurrentUser: isMine,
                formattedTime: this.formatMessageTime(msg.sentDate),
                formattedTimeShort: this.formatTimeShort(msg.sentDate),
                formattedTimeRelative: this.formatTimeRelative(msg.sentDate),
                cardClass: 'message-card' + (isMine ? ' from-me' : ''),
                senderDisplayName: displayName,
                senderInitials: this._getInitials(displayName),
                senderAvatarUrl: avatarUrl,
                hasAvatarImage: !!avatarUrl,
                senderIsOrg: !!msg.senderIsOrg,
                showViaLabel: isOnBehalfOf && !isMine && !msg.senderIsOrg,
                viaLabel: isOnBehalfOf ? `via ${msg.sentByFirstName || msg.sentByName}` : '',
                snippetText: this._getSnippet(msg.body)
            });
        });

        const realMessages = processed.filter(m => !m.isDateSeparator);
        const userMessages = realMessages.filter(m => !m.isSystemMessage);

        if (userMessages.length < ZONE_THRESHOLD) {
            this.useZones = false;
            this.processedMessages = processed;
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
            const lastTwoStart = realMessages.indexOf(userMessages[userMessages.length - lastCount]);
            const middleAll = realMessages.slice(firstUserIdx + 1, lastTwoStart);

            this._rawMiddle = middleAll.filter(m => !m.isSystemMessage);
            this._rawMiddleAll = middleAll;
            this.middleSystemMessages = middleAll.filter(m => m.isSystemMessage);
            this.lastMessages = realMessages.slice(lastTwoStart);

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

    getReadStatusClass(msg) {
        if (msg.isRead) return 'read-indicator read';
        if (msg.status === 'Delivered') return 'read-indicator delivered';
        if (msg.status === 'Failed') return 'read-indicator failed';
        return 'read-indicator sent';
    }

    formatDateSeparator(date) {
        const today = new Date();
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);

        if (date.toDateString() === today.toDateString()) return 'Today';
        if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';
        return date.toLocaleDateString('en-US', {
            weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
        });
    }

    formatMessageTime(timestamp) {
        if (!timestamp) return '';
        const d = new Date(timestamp);
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

    scrollToBottom() {
        setTimeout(() => {
            const container = this.template.querySelector('.messages-container');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 100);
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

    // Compose handlers
    handleShowCompose() {
        this.showCompose = true;
        setTimeout(() => {
            this.scrollToBottom();
            const textarea = this.template.querySelector('.compose-input');
            if (textarea) {
                textarea.focus();
            }
        }, 100);
    }

    handleCancelCompose() {
        this.showCompose = false;
        this.messageText = '';
    }

    handleMessageInput(event) {
        this.messageText = event.target.value;
    }

    async handleSendMessage() {
        if (this.isSendDisabled) return;
        const body = this.messageText.trim();
        this.isSending = true;

        try {
            let result;
            if (this.isDraft) {
                result = await sendDirectMessage({
                    targetContactId: this.targetContactId,
                    body: body
                });
                if (result.success) {
                    this.conversationId = result.conversationId;
                    this.targetContactId = '';
                    this.isDraft = false;
                    this._replaceConversationUrl(result.conversationId);
                }
            } else {
                result = await sendMessage({
                    conversationId: this.conversationId,
                    body: body
                });
            }
            if (result.success) {
                this.messageText = '';
                this.showCompose = false;
                await this.loadMessages();
            }
        } catch (error) {
            console.error('Error sending message:', error);
        } finally {
            this.isSending = false;
        }
    }

    handleScroll(event) {
        const container = event.target;
        if (container.scrollTop === 0 && this.hasMoreMessages) {
            this.handleLoadMore();
        }
    }

    // Navigation
    handleBack() {
        location.href = '/messages';
    }

    // Block/Report
    handleMenuClick() {
        this.showBlockModal = true;
    }

    handleCloseBlockModal() {
        this.showBlockModal = false;
        this.blockReason = '';
        this.isReporting = false;
        this.reportDetails = '';
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
        try {
            await blockContact({
                blockedContactId: this.otherParticipantId,
                reason: this.blockReason,
                isReport: this.isReporting,
                reportDetails: this.reportDetails
            });
            this.showBlockModal = false;
            location.href = '/messages';
        } catch (error) {
            console.error('Error blocking contact:', error);
        }
    }

    // Neighbourly banner
    handleDismissBanner() {
        this.showNeighbourlyBanner = false;
        sessionStorage.setItem('fimby_neighbourly_dismissed', 'true');
    }
}