import { LightningElement, api, track, wire } from 'lwc';
import getGroupMessages from '@salesforce/apex/FimbyGroupConversationController.getGroupMessages';
import sendGroupMessage from '@salesforce/apex/FimbyGroupConversationController.sendGroupMessage';
import getGroupMembers from '@salesforce/apex/FimbyGroupConversationController.getGroupMembers';
import toggleMute from '@salesforce/apex/FimbyGroupConversationController.toggleMute';
import getMyGroupConversations from '@salesforce/apex/FimbyGroupConversationController.getMyGroupConversations';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import {
    getBadgeTypeFromContext,
    getThreadAvatarIcon
} from 'c/fimbyThreadBadgeConfig';

const PAGE_SIZE = 50;
const ZONE_THRESHOLD = 3;
const PILL_THRESHOLD = 5;
const SNIPPET_LENGTH = 80;

export default class FimbyGroupConversation extends LightningElement {
    @api conversationId = '';

    @track messages = [];
    @track messageText = '';
    @track isLoading = true;
    @track isSending = false;
    @track conversationName = '';
    @track contextType = '';
    @track loadError = '';
    @track members = [];
    @track isLocked = false;
    @track isMuted = false;
    @track showMembersPanel = false;
    @track hasMoreMessages = true;
    @track isLoadingMore = false;
    @track currentOffset = 0;
    @track myContactId = '';
    @track organizationId = null;
    @track showCompose = false;
    @track actingAsContact = null;
    @track hasMultipleIdentities = false;
    @track headerHidden = false;

    @track processedMessages = [];

    @track useZones = false;
    @track firstMessage = null;
    @track headerSystemMessages = [];
    @track middleMessages = [];
    @track middleSystemMessages = [];
    @track lastMessages = [];
    @track middleRevealed = false;
    @track expandedIds = [];
    _rawMiddle = [];
    _rawMiddleAll = [];

    get isSendDisabled() {
        return !this.messageText || !this.messageText.trim() || this.isSending;
    }

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading acting-as contact:', error);
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

    get messagingAsName() {
        return this.actingAsContact?.postingAsDisplayName
            || this.actingAsContact?.actingAsContactName
            || this.actingAsContact?.contactName
            || '';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.messagingAsName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get memberCount() {
        return this.members.length;
    }

    get hasMessages() {
        return (this.messages && this.messages.length > 0);
    }

    get showZonedThread() {
        return this.useZones && !!this.firstMessage;
    }

    get showFlatThread() {
        return this.hasMessages && !this.useZones;
    }

    get groupIconUrl() {
        const badgeType = getBadgeTypeFromContext(this.contextType);
        return `${IMPACT_ICONS}/${getThreadAvatarIcon(badgeType)}`;
    }

    get muteIconUrl() {
        return `${IMPACT_ICONS}/mute.png`;
    }

    get muteButtonLabel() {
        return this.isMuted ? 'Unmute' : 'Mute';
    }

    get stickyHeaderClass() {
        return this.headerHidden ? 'conversation-header header-hidden' : 'conversation-header';
    }

    get isFirstExpanded() {
        return this.firstMessage ? this.expandedIds.includes(this.firstMessage.id) : false;
    }

    get hasMiddleMessages() {
        return this._rawMiddle.length > 0 || (this.middleSystemMessages && this.middleSystemMessages.length > 0);
    }

    get middleCount() {
        return this._rawMiddle.length;
    }

    _getInitials(firstName, lastName) {
        const parts = [firstName, lastName].filter(Boolean);
        if (parts.length === 0) return '?';
        return parts
            .map(n => String(n).charAt(0))
            .join('')
            .substring(0, 2)
            .toUpperCase();
    }

    _getInitialsFromName(name) {
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

    async connectedCallback() {
        try {
            this.organizationId = await getOrganizationId();
        } catch (e) {
            /* non-critical */
        }

        if (this.conversationId) {
            await this.loadConversationMetadata();
            await this.loadMessages();
            await this.loadMembers();
        } else {
            this.isLoading = false;
        }
    }

    async loadConversationMetadata() {
        try {
            const list = await getMyGroupConversations();
            const match = list.find(c => c.conversationId === this.conversationId);
            if (match) {
                this.conversationName = match.groupName || 'Group Chat';
                this.contextType = match.contextType || '';
                this.isLocked = !!match.locked;
                this.isMuted = !!match.muted;
            } else {
                this.conversationName = 'Group Chat';
            }
        } catch (e) {
            console.error('Error loading conversation metadata:', e);
            this.conversationName = 'Group Chat';
        }
    }

    async loadMessages() {
        this.isLoading = true;
        this.loadError = '';
        this.currentOffset = 0;
        this.middleRevealed = false;
        this.expandedIds = [];

        try {
            const result = await getGroupMessages({
                conversationId: this.conversationId,
                pageSize: PAGE_SIZE,
                offset: 0
            });

            this.messages = result.messages || [];
            this.hasMoreMessages = !!result.hasMore;
            if (result.groupName) {
                this.conversationName = result.groupName;
            }
            if (result.contextType) {
                this.contextType = result.contextType;
            }
            this.processMessages();
        } catch (error) {
            this.messages = [];
            this.processedMessages = [];
            this.loadError = error?.body?.message || error?.message
                || 'We could not load this conversation. Please try again.';
            console.error('Error loading messages:', error);
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }

    processMessages() {
        const processed = [];
        let lastDate = null;
        const senderToColorIndex = new Map();
        let nextColorIndex = 0;

        this.messages.forEach((msg) => {
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

            const isSystemMessage = !!msg.isSystem;
            const isMine = !!msg.isMine;
            const isOrgSender = !!msg.senderIsOrg;

            const senderName = isOrgSender && msg.senderDisplayName
                ? msg.senderDisplayName
                : [msg.senderFirstName, msg.senderLastName].filter(Boolean).join(' ') || 'Unknown';

            const senderInitials = isOrgSender
                ? this._getInitialsFromName(msg.senderDisplayName)
                : this._getInitials(msg.senderFirstName, msg.senderLastName);

            const avatarUrl = this._completeImageUrl(msg.senderAvatarUrl);

            let senderColorIndex = 0;
            if (!isMine && msg.senderId) {
                if (!senderToColorIndex.has(msg.senderId)) {
                    senderToColorIndex.set(msg.senderId, nextColorIndex % 6);
                    nextColorIndex += 1;
                }
                senderColorIndex = senderToColorIndex.get(msg.senderId);
            }

            const viaLabel = isOrgSender && msg.sentByFirstName
                ? `via ${msg.sentByFirstName}`
                : '';

            processed.push({
                ...msg,
                id: msg.id,
                isDateSeparator: false,
                isSystemMessage,
                isFromCurrentUser: isMine,
                formattedTime: this.formatMessageTime(msg.sentDate),
                formattedTimeShort: this.formatTimeShort(msg.sentDate),
                formattedTimeRelative: this.formatTimeRelative(msg.sentDate),
                cardClass: isSystemMessage
                    ? 'message-card system-message'
                    : 'message-card' + (isMine ? ' from-me' : '') + (isOrgSender ? ' from-org' : ''),
                senderDisplayName: isMine ? 'You' : senderName,
                senderInitials,
                senderAvatarUrl: avatarUrl,
                hasAvatarImage: !!avatarUrl,
                isOrgSender,
                showViaLabel: isOrgSender && !!viaLabel && !isMine,
                viaLabel,
                senderColorIndex,
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
            if (firstUserIdx < 0) {
                this.useZones = false;
                this.processedMessages = processed;
                this.firstMessage = null;
                this.headerSystemMessages = [];
                this._rawMiddle = [];
                this._rawMiddleAll = [];
                this.middleMessages = [];
                this.middleSystemMessages = [];
                this.lastMessages = [];
                return;
            }

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

    async handleSendMessage() {
        if (this.isSendDisabled) return;
        const body = this.messageText.trim();
        this.isSending = true;

        try {
            await sendGroupMessage({
                conversationId: this.conversationId,
                body
            });
            this.messageText = '';
            this.showCompose = false;
            await this.loadMessages();
        } catch (error) {
            console.error('Error sending message:', error);
        } finally {
            this.isSending = false;
        }
    }

    async handleToggleMute() {
        try {
            const result = await toggleMute({ conversationId: this.conversationId });
            this.isMuted = !!result.muted;
        } catch (error) {
            console.error('Error toggling mute:', error);
        }
    }

    handleToggleMembers() {
        this.showMembersPanel = !this.showMembersPanel;
    }

    handleBack() {
        location.href = '/messages';
    }

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

    handleMessageInput(event) {
        this.messageText = event.target.value;
    }

    async loadMembers() {
        try {
            const list = await getGroupMembers({ conversationId: this.conversationId });
            this.members = (list || []).map(m => {
                const isOrg = !!m.isOrgContact;
                const name = isOrg && m.displayName
                    ? m.displayName
                    : [m.firstName, m.lastName].filter(Boolean).join(' ') || 'Unknown';
                const shortName = isOrg
                    ? (m.displayName || 'Org').split(' ')[0]
                    : (m.firstName || name.split(' ')[0] || 'Unknown');
                const avatarUrl = this._completeImageUrl(m.avatarUrl);
                return {
                    ...m,
                    displayName: name,
                    shortName,
                    initials: isOrg ? this._getInitialsFromName(m.displayName) : this._getInitials(m.firstName, m.lastName),
                    isOwner: m.role === 'Owner',
                    isOrgContact: isOrg,
                    avatarUrl,
                    hasAvatarImage: !!avatarUrl
                };
            });
        } catch (e) {
            console.error('Error loading members:', e);
        }
    }

    handleCloseMembers() {
        this.showMembersPanel = false;
    }

    handleScroll(event) {
        const container = event.target;
        if (container.scrollTop === 0 && this.hasMoreMessages) {
            this.handleLoadMore();
        }
    }

    async handleLoadMore() {
        if (this.isLoadingMore || !this.hasMoreMessages) return;
        this.isLoadingMore = true;
        const newOffset = this.currentOffset + PAGE_SIZE;

        try {
            const result = await getGroupMessages({
                conversationId: this.conversationId,
                pageSize: PAGE_SIZE,
                offset: newOffset
            });

            if (result.messages && result.messages.length > 0) {
                this.currentOffset = newOffset;
                this.messages = [...result.messages, ...this.messages];
                this.hasMoreMessages = !!result.hasMore;
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
}