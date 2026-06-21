import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate, navigateToRoute, profilePathForContact } from 'c/fimbyNavigation';
import { toExperiencePath } from 'c/fimbyExperienceUrl';
import getThreads from '@salesforce/apex/FimbyCommunicationController.getThreads';
import getUnifiedUnreadCount from '@salesforce/apex/FimbyCommunicationController.getUnifiedUnreadCount';
import markThreadUnread from '@salesforce/apex/FimbyCommunicationController.markThreadUnread';
import markThreadRead from '@salesforce/apex/FimbyCommunicationController.markThreadRead';
import archiveThread from '@salesforce/apex/FimbyCommunicationController.archiveThread';
import unarchiveThread from '@salesforce/apex/FimbyCommunicationController.unarchiveThread';
import getRetentionDaysForDisclaimer from '@salesforce/apex/FimbyCommunicationController.getRetentionDaysForDisclaimer';
import getMessageableContacts from '@salesforce/apex/FimbyConversationController.getMessageableContacts';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { applyStickyHeaderOffset } from 'c/fimbyDomUtils';
import {
    getInboxBadge,
    getThreadAvatarIcon,
    getGroupAvatarVariant
} from 'c/fimbyThreadBadgeConfig';

function resolveAvatarUrl(url) {
    if (!url) return '';
    if (url.startsWith('/resource/') || !url.startsWith('http')) return url;
    return avatarImageUrl(url);
}

const PAGE_SIZE = 20;
const SWIPE_THRESHOLD = 40;
const SWIPE_ACTION_WIDTH = 80;

const TYPE_FILTERS = [
    { key: 'all', label: 'All' },
    { key: 'unread', label: 'Unread' },
    { key: 'archived', label: 'Archived' }
];

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export default class FimbyMessagesList extends NavigationMixin(LightningElement) {
    @api showFilters = false;
    @api enableTypingIndicators = false;
    @api enablePullToRefresh = false;
    @api pageSize = PAGE_SIZE;

    @track threads = [];
    @track selectedFilter = 'all';
    @track isLoading = false;
    @track totalCount = 0;
    @track currentOffset = 0;
    @track hasMore = false;
    @track searchTerm = '';
    @track hasUnreadMessages = false;

    @track isActingAsSelf = true;
    @track actingAsContactName = '';
    @track actingAsAvatarUrl = '';
    @track isActingAsOrg = false;
    @track hasMultipleIdentities = false;
    @track currentContactId = null;

    @track showNewMessageModal = false;
    @track messageableContacts = [];
    @track contactSearchTerm = '';
    @track isLoadingContacts = false;

    @track retentionDisclaimerText = '';

    // Desktop kebab menu state
    @track _menuThreadId = null;
    @track _menuThreadType = null;
    @track _menuIsUnread = false;
    @track _menuTop = 0;
    @track _menuRight = 0;

    // Mobile swipe state (imperative, not tracked)
    _openSwipeThreadId = null;
    _swipeThreadId = null;
    _swipeStartX = 0;
    _swipeStartY = 0;
    _swipeDeltaX = 0;
    _swiping = false;


    _badgeCountHandler;
    @track headerHidden = false;
    _lastScrollY = 0;
    _scrollTicking = false;
    _escapeHandler = null;

    // ── Icon getters ──────────────────────────────────

    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get trashIconUrl() { return `${IMPACT_ICONS}/trash.png`; }
    get unreadIconUrl() { return `${IMPACT_ICONS}/unread.png`; }
    get readIconUrl() { return `${IMPACT_ICONS}/read.png`; }

    get headerMenuItems() {
        return [
            { key: 'compose', label: 'Compose', icon: 'SpeechBubbleActive.png', display: 'inline', variant: 'primary' }
        ];
    }

    handleHeaderMenuAction(event) {
        if (event.detail.key === 'compose') {
            this.handleNewMessage();
        }
    }

    // ── Computed getters ──────────────────────────────

    get stickyHeaderClass() {
        return this.headerHidden ? 'header-row header-hidden' : 'header-row';
    }

    get showSearchHint() {
        return !this.isLoadingContacts &&
               this.contactSearchTerm.length < 3 &&
               this.messageableContacts.length === 0;
    }

    get typeFilters() {
        return TYPE_FILTERS.map(f => ({
            ...f,
            cssClass: this.selectedFilter === f.key ? 'filter-chip active' : 'filter-chip'
        }));
    }

    get showActingAsBanner() {
        return this.hasMultipleIdentities && !!this.actingAsContactName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get hasThreads() {
        return this.threads.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && this.threads.length === 0;
    }

    get isArchivedView() {
        return this.selectedFilter === 'archived';
    }

    get archiveActionLabel() {
        return this.isArchivedView ? 'Unarchive' : 'Archive';
    }

    // Desktop kebab menu computed properties
    get showKebabMenu() {
        return !!this._menuThreadId;
    }

    get kebabMenuStyle() {
        return `top: ${this._menuTop}px; right: ${this._menuRight}px;`;
    }

    get kebabMenuReadAction() {
        return this._menuIsUnread ? 'mark-read' : 'mark-unread';
    }

    get kebabMenuReadLabel() {
        return this._menuIsUnread ? 'Mark as read' : 'Mark as unread';
    }

    get kebabMenuReadIconUrl() {
        return this._menuIsUnread ? this.readIconUrl : this.unreadIconUrl;
    }

    get kebabMenuArchiveAction() {
        return this.isArchivedView ? 'unarchive' : 'archive';
    }

    get kebabMenuArchiveLabel() {
        return this.isArchivedView ? 'Unarchive' : 'Archive';
    }

    // ── Lifecycle ─────────────────────────────────────

    connectedCallback() {
        this.loadThreads();
        this.refreshUnreadCount();
        this._loadRetentionDisclaimer();
        this._loadActingAs();

        this._badgeCountHandler = (e) => {
            this.hasUnreadMessages = !!e.detail?.hasUnread;
        };
        window.addEventListener('fimbybadgecounts', this._badgeCountHandler);
        window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));

        this._windowScrollHandler = () => {
            if (!this._scrollTicking) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation -- scroll/focus after render
                requestAnimationFrame(() => {
                    this._handleScrollDirection();
                    this._scrollTicking = false;
                });
                this._scrollTicking = true;
            }
        };
        window.addEventListener('scroll', this._windowScrollHandler, { passive: true });

        this._escapeHandler = (e) => {
            if (e.key === 'Escape') this._closeKebabMenu();
        };
        window.addEventListener('keydown', this._escapeHandler);

        // eslint-disable-next-line @lwc/lwc/no-async-operation -- scroll/focus after render
        requestAnimationFrame(() => this._measureHeaderHeight());
    }

    disconnectedCallback() {
        if (this._badgeCountHandler) window.removeEventListener('fimbybadgecounts', this._badgeCountHandler);
        if (this._windowScrollHandler) window.removeEventListener('scroll', this._windowScrollHandler);
        if (this._escapeHandler) window.removeEventListener('keydown', this._escapeHandler);
    }

    _measureHeaderHeight() {
        applyStickyHeaderOffset(this.template.host);
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

    // ── Data loading ──────────────────────────────────

    async loadThreads() {
        this.isLoading = true;
        try {
            const result = await getThreads({
                pageSize: this.pageSize,
                offset: this.currentOffset,
                filter: this.selectedFilter,
                searchTerm: this.searchTerm || null
            });

            const processed = result.threads.map(t => this.processThread(t));

            if (this.currentOffset === 0) {
                this.threads = processed;
            } else {
                this.threads = [...this.threads, ...processed];
            }

            this.totalCount = result.totalCount;
            this.hasMore = this.threads.length < this.totalCount;
        } catch (error) {
            console.error('Error loading threads:', error);
        } finally {
            this.isLoading = false;
            this._updateScrollContainer();
        }
    }

    _updateScrollContainer() {
        const scrollContainer = this.template.querySelector('c-fimby-infinite-scroll');
        if (scrollContainer) scrollContainer.finishLoading(this.hasMore);
    }

    processThread(thread) {
        const badgeType = thread.badgeType || thread.threadType || 'direct';
        const badge = getInboxBadge(badgeType);
        const isUnread = !!thread.isUnread;
        const count = thread.messageCount || 0;
        const isGroup = !!thread.isGroup;
        const completedImageUrl = resolveAvatarUrl(thread.participantImageUrl);
        const hasPostImage = isGroup && !!completedImageUrl;
        const showGroupIconAvatar = isGroup && !hasPostImage;
        const hasParticipantImage = !isGroup && !!thread.participantImageUrl;
        const archiveAction = this.isArchivedView ? 'unarchive' : 'archive';
        const archiveLabel = this.isArchivedView ? 'Unarchive' : 'Archive';

        const subjectLine = thread.contextLabel || '';
        const showPreview = !subjectLine;
        const previewText = showPreview ? (thread.lastMessagePreview || '') : '';
        const hasSecondLine = !!(subjectLine || previewText);

        const groupVariant = showGroupIconAvatar ? getGroupAvatarVariant(badgeType) : '';
        const rowAriaLabel = isGroup
            ? `${badge.label} group: ${thread.participantName || 'conversation'}`
            : `Open conversation with ${thread.participantName || 'neighbour'}`;

        const profilePath = !isGroup && thread.participantContactId
            ? profilePathForContact({
                contactId: thread.participantContactId,
                isOrgContact: !!thread.isOrgContact,
                orgAccountId: thread.participantOrgAccountId,
                currentContactId: this.currentContactId
            })
            : '';

        return {
            ...thread,
            actionUrl: thread.actionUrl,
            formattedDate: this.formatGmailDate(thread.lastActivityDate),
            rowClass: 'inbox-row' + (isUnread ? ' unread' : '') + ' has-kebab',
            rowAriaLabel,
            badgeLabel: badge.label,
            badgeCssClass: badge.cssClass,
            messageCountDisplay: count > 1 ? String(count) : '',
            showMessageCount: count > 1,
            readStatusAction: isUnread ? 'mark-read' : 'mark-unread',
            readStatusLabel: isUnread ? 'Read' : 'Unread',
            readStatusAriaLabel: isUnread ? 'Mark as read' : 'Mark as unread',
            readStatusIconUrl: isUnread ? this.readIconUrl : this.unreadIconUrl,
            readSwipeClass: 'swipe-action swipe-action-left ' + (isUnread ? 'swipe-mark-read' : 'swipe-mark-unread'),
            participantImageUrl: completedImageUrl,
            isOrgContact: !!thread.isOrgContact,
            hasParticipantImage,
            hasPostImage,
            showGroupIconAvatar,
            groupAvatarIconUrl: `${IMPACT_ICONS}/${getThreadAvatarIcon(badgeType)}`,
            groupAvatarClass: showGroupIconAvatar
                ? `thread-avatar group-avatar group-avatar-${groupVariant}`
                : 'thread-avatar',
            participantInitials: this.getInitials(thread.participantName),
            profilePath,
            avatarClickable: !!profilePath,
            avatarClass: isGroup
                ? (hasPostImage ? 'thread-avatar thread-avatar-group' : `thread-avatar group-avatar group-avatar-${groupVariant}`)
                : ('thread-avatar' + (thread.isOrgContact ? ' thread-avatar-org' : '') + (profilePath ? ' thread-avatar-clickable' : '')),
            archiveAction,
            archiveLabel,
            subjectLine,
            showPreview,
            previewText,
            hasSecondLine
        };
    }

    formatGmailDate(timestamp) {
        if (!timestamp) return '';
        const now = new Date();
        const date = new Date(timestamp);

        const isToday = now.toDateString() === date.toDateString();
        if (isToday) {
            return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
        }

        const startOfWeek = new Date(now);
        startOfWeek.setDate(now.getDate() - now.getDay());
        startOfWeek.setHours(0, 0, 0, 0);
        if (date >= startOfWeek) {
            return DAY_NAMES[date.getDay()];
        }

        return MONTH_NAMES[date.getMonth()] + ' ' + date.getDate();
    }

    getInitials(name) {
        if (!name) return '?';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    handleAvatarError(event) {
        const img = event.target;
        img.style.display = 'none';
        const parent = img.parentElement;
        if (parent) {
            const initials = parent.querySelector('.thread-avatar-initials, .banner-avatar-initials, .contact-avatar-initials');
            if (initials) initials.style.display = '';
        }
    }

    handleGroupPostImageError(event) {
        const img = event.target;
        img.style.display = 'none';
        const parent = img.parentElement;
        if (parent) {
            const fallback = parent.querySelector('.group-avatar-fallback');
            if (fallback) fallback.style.display = '';
        }
    }

    // ── Filter / navigation ───────────────────────────

    handleFilterChange(event) {
        const filterKey = event.currentTarget.dataset.filterKey;
        if (filterKey && filterKey !== this.selectedFilter) {
            this.selectedFilter = filterKey;
            this.currentOffset = 0;
            this.loadThreads();
        }
    }

    handleThreadClick(event) {
        if (event.target.closest('.thread-kebab-container')) return;
        if (event.target.closest('.thread-avatar-clickable')) return;

        const threadId = event.currentTarget.dataset.threadId;

        // If this row has a swipe open, close it instead of navigating
        if (this._openSwipeThreadId === threadId) {
            this._closeSwipe();
            return;
        }

        const actionUrl = event.currentTarget.dataset.actionUrl;
        if (actionUrl) {
            navigate(this, toExperiencePath(actionUrl));
        }
    }

    handleParticipantAvatarClick(event) {
        event.stopPropagation();
        const path = event.currentTarget.dataset.profilePath;
        if (path) {
            navigate(this, path);
        }
    }

    handleThreadKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleThreadClick(event);
        }
    }

    // ── Mobile swipe-to-reveal ────────────────────────

    handleSwipeStart(event) {
        if (!event.touches || event.touches.length !== 1) return;
        if (event.target.closest('.swipe-action')) return;
        const wrapper = event.currentTarget;
        const threadId = wrapper.dataset.threadId;

        // Close any other open row
        if (this._openSwipeThreadId && this._openSwipeThreadId !== threadId) {
            this._closeSwipe();
        }

        this._swipeThreadId = threadId;
        this._swipeStartX = event.touches[0].clientX;
        this._swipeStartY = event.touches[0].clientY;
        this._swipeDeltaX = 0;
        this._swiping = false;
    }

    handleSwipeMove(event) {
        if (!this._swipeThreadId || !event.touches || event.touches.length !== 1) return;

        const dx = event.touches[0].clientX - this._swipeStartX;
        const dy = event.touches[0].clientY - this._swipeStartY;

        if (!this._swiping && Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy)) {
            this._swiping = true;
        }
        if (!this._swiping) return;

        event.preventDefault();

        // If left-swipe drawer is open, allow closing drag
        if (this._openSwipeThreadId === this._swipeThreadId) {
            this._swipeDeltaX = Math.max(-SWIPE_ACTION_WIDTH, Math.min(0, -SWIPE_ACTION_WIDTH + dx));
        } else {
            this._swipeDeltaX = Math.max(-SWIPE_ACTION_WIDTH, Math.min(SWIPE_ACTION_WIDTH, dx));
        }

        const wrapper = event.currentTarget;
        const fg = wrapper.querySelector('.swipe-foreground');
        if (fg) {
            fg.style.transform = `translateX(${this._swipeDeltaX}px)`;
            fg.style.transition = 'none';
        }
    }

    handleSwipeEnd(event) {
        if (!this._swipeThreadId) return;
        if (this._swiping) {
            event.preventDefault();
        }

        const wrapper = event.currentTarget;
        const fg = wrapper.querySelector('.swipe-foreground');
        const threadId = this._swipeThreadId;
        const delta = this._swipeDeltaX;

        this._swipeThreadId = null;
        this._swiping = false;

        if (!fg) return;

        fg.style.transition = 'transform 0.2s ease';

        const wasOpen = (this._openSwipeThreadId === threadId);

        if (wasOpen) {
            if (delta > -SWIPE_ACTION_WIDTH / 2) {
                this._closeSwipeElement(fg, threadId);
                return;
            }
            fg.style.transform = `translateX(-${SWIPE_ACTION_WIDTH}px)`;
            return;
        }

        if (delta >= SWIPE_THRESHOLD) {
            // Right swipe: auto-commit read/unread toggle, animate back
            const thread = this.threads.find(t => t.threadId === threadId);
            const action = thread?.readStatusAction;
            const threadType = thread?.threadType;

            fg.style.transform = `translateX(${SWIPE_ACTION_WIDTH}px)`;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                fg.style.transition = 'transform 0.2s ease';
                fg.style.transform = 'translateX(0)';
            }, 200);

            if (action && threadType) {
                this._executeAction(action, threadId, threadType);
            }
        } else if (delta <= -SWIPE_THRESHOLD) {
            // Left swipe: reveal archive, stay open
            fg.style.transform = `translateX(-${SWIPE_ACTION_WIDTH}px)`;
            this._openSwipeThreadId = threadId;
        } else {
            fg.style.transform = 'translateX(0)';
        }
    }

    _closeSwipe() {
        if (!this._openSwipeThreadId) return;
        const wrapper = this.template.querySelector(`.thread-row-wrapper[data-thread-id="${this._openSwipeThreadId}"]`);
        if (wrapper) {
            const fg = wrapper.querySelector('.swipe-foreground');
            if (fg) {
                fg.style.transition = 'transform 0.2s ease';
                fg.style.transform = 'translateX(0)';
            }
        }
        this._openSwipeThreadId = null;
    }

    _closeSwipeElement(fg, threadId) {
        fg.style.transform = 'translateX(0)';
        if (this._openSwipeThreadId === threadId) {
            this._openSwipeThreadId = null;
        }
    }

    handleSwipeActionClick(event) {
        event.stopPropagation();
        const { threadId, threadType, action } = event.currentTarget.dataset;
        this._closeSwipe();
        this._executeAction(action, threadId, threadType);
    }

    // ── Desktop kebab menu ────────────────────────────

    handleKebabClick(event) {
        event.preventDefault();
        event.stopPropagation();

        const { threadId, threadType } = event.currentTarget.dataset;
        if (!threadId) return;

        const thread = this.threads.find(t => t.threadId === threadId);
        const btn = event.currentTarget;
        const rect = btn.getBoundingClientRect();

        this._menuThreadId = threadId;
        this._menuThreadType = threadType;
        this._menuIsUnread = !!thread?.isUnread;
        this._menuTop = rect.bottom + 4;
        this._menuRight = window.innerWidth - rect.right;
    }

    handleMenuBackdropClick(event) {
        event.preventDefault();
        event.stopPropagation();
        this._closeKebabMenu();
    }

    handleMenuActionClick(event) {
        event.preventDefault();
        event.stopPropagation();
        const action = event.currentTarget.dataset.action;
        const threadId = this._menuThreadId;
        const threadType = this._menuThreadType;
        this._closeKebabMenu();
        this._executeAction(action, threadId, threadType);
    }

    _closeKebabMenu() {
        this._menuThreadId = null;
        this._menuThreadType = null;
    }

    // ── Shared action dispatcher ──────────────────────

    _executeAction(action, threadId, threadType) {
        if (action === 'archive') {
            this._doArchive(threadId, threadType);
        } else if (action === 'unarchive') {
            this._doUnarchive(threadId, threadType);
        } else if (action === 'mark-unread') {
            this._doMarkUnread(threadId, threadType);
        } else if (action === 'mark-read') {
            this._doMarkRead(threadId, threadType);
        }
    }

    async _doArchive(threadId, threadType) {
        try {
            await archiveThread({ threadType, threadId });
            this.threads = this.threads.filter(t => t.threadId !== threadId);
            this.totalCount = Math.max(0, this.totalCount - 1);
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
        } catch (err) {
            console.error('Error archiving thread:', err);
        }
    }

    async _doUnarchive(threadId, threadType) {
        try {
            await unarchiveThread({ threadType, threadId });
            this.threads = this.threads.filter(t => t.threadId !== threadId);
            this.totalCount = Math.max(0, this.totalCount - 1);
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
        } catch (err) {
            console.error('Error unarchiving thread:', err);
        }
    }

    async _doMarkUnread(threadId, threadType) {
        try {
            await markThreadUnread({ threadType, threadId });
            this.threads = this.threads.map(t =>
                (t.threadId === threadId
                    ? this.processThread({ ...t, isUnread: true })
                    : t)
            );
            this.hasUnreadMessages = true;
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
        } catch (err) {
            console.error('Error marking thread unread:', err);
        }
    }

    async _doMarkRead(threadId, threadType) {
        try {
            await markThreadRead({ threadType, threadId });
            this.threads = this.threads.map(t =>
                (t.threadId === threadId
                    ? this.processThread({ ...t, isUnread: false })
                    : t)
            );
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
        } catch (err) {
            console.error('Error marking thread read:', err);
        }
    }

    // ── Compose / contacts ────────────────────────────

    handleNewMessage() {
        this.showNewMessageModal = true;
        this.contactSearchTerm = '';
        this.messageableContacts = [];
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const input = this.template.querySelector('.contact-search-input');
            if (input) input.focus();
        }, 100);
    }

    handleCloseNewMessage() {
        this.showNewMessageModal = false;
        this.contactSearchTerm = '';
        this.messageableContacts = [];
    }

    async handleContactSearch(event) {
        this.contactSearchTerm = event.target.value;
        if (this.contactSearchTerm.length < 3) {
            this.messageableContacts = [];
            return;
        }
        this.isLoadingContacts = true;
        try {
            const raw = await getMessageableContacts({ searchTerm: this.contactSearchTerm });
            this.messageableContacts = raw.map(c => ({
                ...c,
                initials: this.getInitials(c.contactName),
                isOrgContact: !!c.isOrgContact,
                avatarUrl: resolveAvatarUrl(c.avatarUrl),
                hasAvatar: !!c.avatarUrl,
                contactAvatarClass: 'contact-avatar-sm' + (c.isOrgContact ? ' contact-avatar-org' : '')
            }));
        } catch (error) {
            console.error('Error searching contacts:', error);
        } finally {
            this.isLoadingContacts = false;
        }
    }

    handleContactSearchKeydown(event) {
        if (event.key === 'Enter' && this.messageableContacts.length > 0) {
            event.preventDefault();
            this.selectContact(this.messageableContacts[0].contactId);
        }
    }

    handleContactSelect(event) {
        this.selectContact(event.currentTarget.dataset.contactId);
    }

    selectContact(contactId) {
        if (!contactId) return;
        this.showNewMessageModal = false;
        this.contactSearchTerm = '';
        this.messageableContacts = [];
        navigate(this, '/conversation?contactId=' + contactId);
    }

    // ── Search / pagination / nav ─────────────────────

    handleSearch(event) {
        this.searchTerm = event.detail?.searchTerm || '';
        this.currentOffset = 0;
        this.loadThreads();
    }

    handleLoadMore() {
        if (this.hasMore && !this.isLoading) {
            this.currentOffset += this.pageSize;
            this.loadThreads();
        }
    }

    handleRefresh() {
        this.currentOffset = 0;
        this.loadThreads();
        this.refreshUnreadCount();
    }

    handleTabChange(event) {
        const selectedTab = event.detail.tab;
        navigateToRoute(this, selectedTab);
    }

    async refreshUnreadCount() {
        try {
            const count = await getUnifiedUnreadCount();
            this.hasUnreadMessages = (count || 0) > 0;
        } catch {
            // Silently ignore
        }
    }

    get actingAsInitials() {
        return this.getInitials(this.actingAsContactName);
    }

    get hasActingAsAvatar() {
        return !!this.actingAsAvatarUrl;
    }

    async _loadActingAs() {
        try {
            const result = await getActingAsContact();
            if (result?.success) {
                this.currentContactId = result.contactId || result.realContactId || null;
                this.isActingAsSelf = !!result.isActingAsSelf;
                this.actingAsContactName = result.postingAsDisplayName || result.actingAsContactName || '';
                this.actingAsAvatarUrl = resolveAvatarUrl(result.actingAsAvatarUrl);
                this.isActingAsOrg = !!result.isActingAsOrg;
            }
        } catch {
            // Non-critical — banner just won't show
        }
        try {
            const identities = await getAvailableIdentities();
            this.hasMultipleIdentities = Array.isArray(identities) && identities.length > 0;
        } catch {
            this.hasMultipleIdentities = false;
        }
    }

    async _loadRetentionDisclaimer() {
        try {
            const days = await getRetentionDaysForDisclaimer();
            const dm = days?.dmDays ?? 90;
            const response = days?.responseDays ?? 180;
            const library = days?.libraryDays ?? 180;
            if (response === library) {
                this.retentionDisclaimerText = `We remove conversations that haven't been used in ${dm} days (direct messages) or ${response} days (Ask/Offer and Lending).`;
            } else {
                this.retentionDisclaimerText = `We remove conversations that haven't been used in ${dm} days (direct messages), ${response} days (Ask/Offer), or ${library} days (Lending).`;
            }
        } catch {
            this.retentionDisclaimerText = 'We remove conversations that haven\'t been used in 90 days (direct messages) or 180 days (Ask/Offer and Lending).';
        }
    }
}