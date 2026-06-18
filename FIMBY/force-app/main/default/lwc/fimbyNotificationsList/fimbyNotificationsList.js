import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getNotifications from '@salesforce/apex/FimbyNotificationController.getNotifications';
import markAsRead from '@salesforce/apex/FimbyNotificationController.markAsRead';
import markAllAsRead from '@salesforce/apex/FimbyNotificationController.markAllAsRead';
import markAsUnread from '@salesforce/apex/FimbyNotificationController.markAsUnread';
import deleteNotification from '@salesforce/apex/FimbyNotificationController.deleteNotification';
import deleteAllNotifications from '@salesforce/apex/FimbyNotificationController.deleteAllNotifications';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { isKnownExperienceHost, toExperiencePath } from 'c/fimbyExperienceUrl';
import { navigate } from 'c/fimbyNavigation';
import { avatarImageUrl } from 'c/fimbyImageUrl';

const PAGE_SIZE = 20;
const SWIPE_THRESHOLD = 40;
const SWIPE_ACTION_WIDTH = 80;
const UNDO_TIMEOUT_MS = 5000;

// Glyph avatars for system/token actors (no human actor Contact). Keyed by
// Notification__c.Type__c. Human actors render a photo or initials instead.
const TYPE_ICON_MAP = {
    Response: 'reply.png',
    Comment: 'comment.png',
    Lending_Request: 'borrow.png',
    Loan_Approved: 'BorrowActive.png',
    Extension_Request: 'borrow.png',
    Extension_Approved: 'BorrowActive.png',
    Overdue_Reminder: 'warning.png',
    Item_Returned: 'borrow.png',
    Vouch_Request_Received: 'Waving.png',
    Vouch_Request_Reminder: 'Waving.png',
    Vouch_Approved: 'Sapling.png',
    Vouch_Declined: 'Sapling.png',
    Vouch_Revoked: 'warning.png',
    Voucher_Paused: 'warning.png'
};

// Actor_Name__c values that are team/icon tokens, not real neighbour names
// (notification-contract §4). Mirrors FimbyPushBatchJob.NON_PERSON_ACTORS.
const TOKEN_ACTORS = new Set(['FIMBY', 'Neighbourhood team', 'care', 'system']);

const GENERIC_PERSON_GLYPH = 'NoProfilePhoto.png';
const DEFAULT_GLYPH = 'BellInactive.png';

function resolveAvatarUrl(url) {
    if (!url) return '';
    if (url.startsWith('/resource/') || !url.startsWith('http')) return url;
    return avatarImageUrl(url);
}


export default class FimbyNotificationsList extends NavigationMixin(LightningElement) {
    allNotifications = [];
    totalCount = 0;
    currentOffset = 0;
    showConfirmation = false;
    statusMessage = '';

    showUndoToast = false;
    _undoNotification = null;
    _undoTimeout = null;

    // Id of a card that just moved Unread -> Read, so it can fade its tint out
    // gently on arrival in the Read section instead of snapping.
    @track _justReadId = null;
    _justReadTimeout = null;

    // Last-render row positions, keyed by notification id, for the FLIP reflow.
    _prevRowTops = null;

    // Mobile swipe state
    _swipeId = null;
    _swipeStartX = 0;
    _swipeStartY = 0;
    _swipeDeltaX = 0;
    _swiping = false;
    _openSwipeId = null;

    // Desktop kebab menu state
    @track _menuNotificationId = null;
    @track _menuIsUnread = false;
    @track _menuTop = 0;
    @track _menuRight = 0;

    _escapeHandler = null;

    connectedCallback() {
        this.loadInitial();
        this._escapeHandler = (e) => {
            if (e.key === 'Escape') this._closeKebabMenu();
        };
        window.addEventListener('keydown', this._escapeHandler);
    }

    disconnectedCallback() {
        if (this._escapeHandler) window.removeEventListener('keydown', this._escapeHandler);
        if (this._justReadTimeout) clearTimeout(this._justReadTimeout);
    }

    renderedCallback() {
        this._playReflowFlip();
    }

    /**
     * FLIP reflow: when the list reorders (a card moves Unread -> Read), let the
     * remaining cards glide from their previous position to their new one instead
     * of snapping. We record each card's top before the re-render (in the prior
     * pass) and, on the new render, invert the delta then release it so the
     * browser tweens the gap closing. Honours prefers-reduced-motion.
     */
    _playReflowFlip() {
        const rows = this.template.querySelectorAll('.swipe-wrapper[data-notification-id]');
        const newTops = new Map();
        rows.forEach(row => {
            newTops.set(row.dataset.notificationId, row.getBoundingClientRect().top);
        });

        const prev = this._prevRowTops;
        this._prevRowTops = newTops;

        if (!prev || this._reduceMotion()) {
            return;
        }

        rows.forEach(row => {
            const id = row.dataset.notificationId;
            const oldTop = prev.get(id);
            if (oldTop === undefined) return;
            const delta = oldTop - newTops.get(id);
            if (!delta) return;

            row.style.transition = 'none';
            row.style.transform = `translateY(${delta}px)`;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => {
                row.style.transition = 'transform 0.32s ease';
                row.style.transform = '';
            });
        });
    }

    _reduceMotion() {
        return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }

    /* ---------------------------------------------------------------
     * Getters
     * --------------------------------------------------------------- */

    get emptyIconUrl() {
        return `${IMPACT_ICONS}/BellInactive.png`;
    }

    get settingsIconUrl() {
        return `${IMPACT_ICONS}/gear.png`;
    }

    get trashIconUrl() {
        return `${IMPACT_ICONS}/trash.png`;
    }

    get readIconUrl() {
        return `${IMPACT_ICONS}/read.png`;
    }

    get unreadIconUrl() {
        return `${IMPACT_ICONS}/unread.png`;
    }

    get hasUnread() {
        return this.allNotifications.some(n => n.isUnread);
    }

    get notHasUnread() {
        return !this.hasUnread;
    }

    get hasMoreData() {
        return this.currentOffset < this.totalCount;
    }

    // Desktop kebab menu computed properties
    get showKebabMenu() {
        return !!this._menuNotificationId;
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

    // Two sections — Unread then Read — each newest-first (the controller orders
    // CreatedDate DESC within each group). Partitioning here in a getter means a
    // card marked read flips groups immediately on the next render, with no page
    // refresh. A section is omitted entirely when it has no rows. The section
    // heading is the non-colour cue for unread state (WCAG 1.4.1), so no dot.
    get notificationSections() {
        const unread = [];
        const read = [];
        this.allNotifications.forEach(n => {
            (n.isUnread ? unread : read).push(this._enrichNotification(n));
        });
        const sections = [];
        if (unread.length) {
            sections.push({ key: 'unread', label: 'Unread', items: unread });
        }
        if (read.length) {
            sections.push({ key: 'read', label: 'Read', items: read });
        }
        return sections;
    }

    /* ---------------------------------------------------------------
     * Data loading
     * --------------------------------------------------------------- */

    async loadInitial() {
        this.currentOffset = 0;
        this.allNotifications = [];
        const scroller = this.template.querySelector('c-fimby-infinite-scroll');
        if (scroller) {
            scroller.reset();
            scroller.isLoading = true;
        }
        await this._fetchPage();
    }

    async _fetchPage() {
        try {
            const result = await getNotifications({
                pageSize: PAGE_SIZE,
                offset: this.currentOffset,
                typeFilter: null
            });

            this.totalCount = result.totalCount;
            const newItems = result.items.map(n => ({ ...n }));

            if (this.currentOffset === 0) {
                this.allNotifications = newItems;
            } else {
                this.allNotifications = [...this.allNotifications, ...newItems];
            }
            this.currentOffset += newItems.length;

            const scroller = this.template.querySelector('c-fimby-infinite-scroll');
            if (scroller) {
                if (this.allNotifications.length === 0) {
                    scroller.showEmptyState = true;
                    scroller.finishLoading(false);
                } else {
                    scroller.showEmptyState = false;
                    scroller.finishLoading(this.currentOffset < this.totalCount);
                }
            }
        } catch (error) {
            console.error('Error loading notifications:', error);
            const scroller = this.template.querySelector('c-fimby-infinite-scroll');
            if (scroller) {
                scroller.showErrorState('Unable to load notifications. Please try again.');
            }
        }
    }

    /* ---------------------------------------------------------------
     * Notification enrichment
     * --------------------------------------------------------------- */

    _enrichNotification(n) {
        const isUnread = !!n.isUnread;
        const title = (n.title || '').trim();
        const body = (n.body || '').trim();

        // A human actor is present iff the controller stamped an Actor_Contact__c.
        // Token/system actors (FIMBY, team, care, system) have no Contact and
        // render a glyph avatar; their titles are self-contained sentences.
        const hasHumanActor = !!n.actorContactId && !TOKEN_ACTORS.has((n.actorName || '').trim());
        const actorName = (n.actorDisplayName || n.actorName || '').trim();

        const photoUrl = hasHumanActor ? resolveAvatarUrl(n.actorPhotoUrl) : '';
        const hasPhoto = !!photoUrl;
        const initials = hasHumanActor ? this._getInitials(actorName) : '';
        const showInitials = hasHumanActor && !hasPhoto;
        const showGlyph = !hasHumanActor;
        const glyphUrl = `${IMPACT_ICONS}/${TYPE_ICON_MAP[n.type] || DEFAULT_GLYPH}`;
        const genericGlyphUrl = `${IMPACT_ICONS}/${GENERIC_PERSON_GLYPH}`;

        const relativeTime = this._formatTime(n.createdDate);
        const absoluteTime = this._formatAbsoluteTime(n.createdDate);
        const isoTime = n.createdDate ? new Date(n.createdDate).toISOString() : '';

        // Row aria-label conveys the whole card: actor, message, body, time, state.
        const ariaParts = [];
        if (hasHumanActor && actorName) ariaParts.push(actorName);
        if (title) ariaParts.push(title);
        const ariaLabel =
            ariaParts.join(' ') +
            (body ? `. ${body}` : '') +
            (absoluteTime ? `. ${absoluteTime}` : '') +
            `. ${isUnread ? 'Unread' : 'Read'}.`;

        const justRead = (this._justReadId === n.id);
        return {
            ...n,
            navigationUrl: this._resolveNavigationUrl(n),
            containerClass: 'notification-item'
                + (isUnread ? ' unread' : '')
                + (justRead ? ' just-read' : ''),
            displayTitle: title,
            displayActorName: hasHumanActor ? actorName : '',
            displayBody: body,
            hasHumanActor,
            hasBody: !!body,
            actorPhotoSrc: photoUrl,
            actorInitials: initials,
            showActorPhoto: hasPhoto,
            showActorInitials: showInitials,
            showActorGlyph: showGlyph,
            glyphIconUrl: glyphUrl,
            genericGlyphUrl,
            formattedTime: relativeTime,
            formattedAbsoluteTime: absoluteTime,
            isoTime,
            ariaLabel,
            readToggleLabel: isUnread ? 'Mark as read' : 'Mark as unread',
            readStatusLabel: isUnread ? 'Read' : 'Unread',
            readStatusIconUrl: isUnread ? this.readIconUrl : this.unreadIconUrl,
            readSwipeClass: 'swipe-action swipe-action-left ' + (isUnread ? 'swipe-mark-read' : 'swipe-mark-unread')
        };
    }

    _getInitials(name) {
        const trimmed = (name || '').trim();
        if (!trimmed) return '';
        const parts = trimmed.split(/\s+/).filter(Boolean);
        if (parts.length === 0) return '';
        if (parts.length === 1) return parts[0][0].toUpperCase();
        return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }

    _formatTime(timestamp) {
        if (!timestamp) return '';
        const now = new Date();
        const time = new Date(timestamp);
        const diff = now - time;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(diff / 3600000);
        const days = Math.floor(diff / 86400000);

        if (minutes < 1) return 'now';
        if (minutes < 60) return `${minutes}m`;
        if (hours < 24) return `${hours}h`;
        if (days < 7) return `${days}d`;
        return time.toLocaleDateString();
    }

    // Accessible, unambiguous time used in the aria-label, the <time> tooltip,
    // and as the truth source the relative "2h" text is a shorthand for.
    _formatAbsoluteTime(timestamp) {
        if (!timestamp) return '';
        const time = new Date(timestamp);
        if (isNaN(time.getTime())) return '';
        return time.toLocaleString(undefined, {
            year: 'numeric', month: 'short', day: 'numeric',
            hour: 'numeric', minute: '2-digit'
        });
    }

    handleAvatarError(event) {
        const img = event.target;
        img.style.display = 'none';
        const parent = img.parentElement;
        if (parent) {
            const initials = parent.querySelector('.notif-avatar-initials');
            if (initials) initials.style.display = '';
        }
    }

    /* ---------------------------------------------------------------
     * Infinite scroll + pull-to-refresh handlers
     * --------------------------------------------------------------- */

    handleLoadMore() {
        if (this.currentOffset < this.totalCount) {
            this._fetchPage();
        }
    }

    handleRefresh() {
        this.loadInitial();
    }

    handleSettingsClick() {
        navigate(this, '/settings');
    }

    /* ---------------------------------------------------------------
     * Mark all as read
     * --------------------------------------------------------------- */

    async handleMarkAllRead() {
        if (!this.hasUnread) return;

        const previousState = this.allNotifications.map(n => ({ ...n }));
        this.allNotifications = this.allNotifications.map(n => ({
            ...n,
            isUnread: false
        }));
        this.statusMessage = 'All notifications marked as read';

        try {
            await markAllAsRead();
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
        } catch (error) {
            console.error('Error marking all as read:', error);
            this.allNotifications = previousState;
            this.statusMessage = 'Failed to mark notifications as read';
        }
    }

    /* ---------------------------------------------------------------
     * Clear all (with confirmation)
     * --------------------------------------------------------------- */

    handleClearAllClick() {
        if (this.allNotifications.length === 0) return;
        this.showConfirmation = true;
    }

    handleConfirmCancel() {
        this.showConfirmation = false;
    }

    async handleConfirmClearAll() {
        this.showConfirmation = false;

        try {
            await deleteAllNotifications();
            this.allNotifications = [];
            this.totalCount = 0;
            this.currentOffset = 0;
            this.statusMessage = 'All notifications cleared';
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));

            const scroller = this.template.querySelector('c-fimby-infinite-scroll');
            if (scroller) {
                scroller.showEmptyState = true;
                scroller.finishLoading(false);
            }
        } catch (error) {
            console.error('Error clearing notifications:', error);
            this.statusMessage = 'Failed to clear notifications';
        }
    }

    /* ---------------------------------------------------------------
     * Notification click (navigate + mark read)
     * --------------------------------------------------------------- */

    async handleNotificationClick(event) {
        const notificationId = event.currentTarget.dataset.notificationId;

        if (this._openSwipeId === notificationId) {
            this._closeSwipe();
            return;
        }

        const notification = this.allNotifications.find(n => n.id === notificationId);
        if (!notification) return;

        if (notification.isUnread) {
            this.allNotifications = this.allNotifications.map(n =>
                n.id === notificationId ? { ...n, isUnread: false } : n
            );
            try {
                await markAsRead({ notificationId });
                window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
            } catch (error) {
                console.error('Error marking as read:', error);
            }
        }

        const target = this._resolveSafeUrl(notification);
        if (target) {
            navigate(this, target);
        }
    }

    handleNotificationKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleNotificationClick(event);
        }
    }

    /**
     * Decide which URL to send the user to when they tap a notification.
     * Trust order:
     *   1. notification.actionUrl, if it resolves to a site-relative path or
     *      a known Experience host (CMDT absolute URLs are stripped to paths).
     *   2. Fallback URL derived from related-record type when the action
     *      URL is missing or untrusted.
     *   3. /notifications (no-op refresh) as a last resort.
     */
    _resolveNavigationUrl(notification) {
        const raw = (notification && notification.actionUrl) ? notification.actionUrl.trim() : '';
        if (!raw) {
            return this._buildFallbackUrl(notification);
        }

        const relative = toExperiencePath(raw);
        if (relative.startsWith('/')) {
            return relative;
        }

        if (/^https?:\/\//i.test(relative)) {
            try {
                const parsed = new URL(relative);
                if (isKnownExperienceHost(parsed.host)) {
                    return toExperiencePath(relative);
                }
                console.warn('FimbyNotificationsList: blocked off-host actionUrl', parsed.host);
            } catch (err) {
                console.warn('FimbyNotificationsList: unparseable actionUrl', raw);
            }
        }

        return this._buildFallbackUrl(notification);
    }

    _resolveSafeUrl(notification) {
        return this._resolveNavigationUrl(notification);
    }

    _buildFallbackUrl(notification) {
        if (!notification) return '/notifications';
        const recordId = notification.relatedRecordId;
        const recordType = notification.relatedRecordType;
        if (recordId && recordType) {
            switch (recordType) {
                case 'Library_Item__c':
                case 'Loaned_Item__c':
                case 'Lending_Request__c':
                    return `/library-item/${recordId}`;
                case 'Needs_Offers__c':
                    return `/asks-offers/${recordId}`;
                case 'Story__c':
                case 'Story_Comment__c':
                    return `/story/${recordId}`;
                case 'Conversation__c':
                    return `/conversation?id=${recordId}`;
                case 'Response__c':
                    return `/response-reply?recordId=${recordId}`;
                case 'Vouch_Record__c':
                    return '/manage-identities';
                case 'Moderator_Task__c':
                    return '/moderator-dashboard';
                case 'Support_Relationship__c':
                    return '/manage-identities';
                default:
                    return '/notifications';
            }
        }
        return '/notifications';
    }

    /* ---------------------------------------------------------------
     * Individual toggle read / unread
     * --------------------------------------------------------------- */

    // Tag a card so it carries `just-read` for one beat after moving to the Read
    // section. CSS uses that to fade the unread tint/accent out gently on arrival
    // (calm settle) instead of the card snapping to its plain read style.
    _flagJustRead(notificationId) {
        if (this._justReadTimeout) {
            clearTimeout(this._justReadTimeout);
        }
        this._justReadId = notificationId;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._justReadTimeout = setTimeout(() => {
            this._justReadId = null;
            this._justReadTimeout = null;
        }, 600);
    }

    async _toggleReadState(notificationId) {
        const notification = this.allNotifications.find(n => n.id === notificationId);
        if (!notification) return;

        const wasUnread = notification.isUnread;
        this.allNotifications = this.allNotifications.map(n =>
            n.id === notificationId ? { ...n, isUnread: !wasUnread } : n
        );
        if (wasUnread) {
            this._flagJustRead(notificationId);
        }
        this.statusMessage = wasUnread ? 'Notification marked as read' : 'Notification marked as unread';

        try {
            if (wasUnread) {
                await markAsRead({ notificationId });
            } else {
                await markAsUnread({ notificationId });
            }
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
        } catch (error) {
            console.error('Error toggling read state:', error);
            this.allNotifications = this.allNotifications.map(n =>
                n.id === notificationId ? { ...n, isUnread: wasUnread } : n
            );
            this.statusMessage = 'Failed to update notification';
        }
    }

    /* ---------------------------------------------------------------
     * Delete individual notification (with undo)
     * --------------------------------------------------------------- */

    _softDelete(notificationId) {
        const notification = this.allNotifications.find(n => n.id === notificationId);
        if (!notification) return;

        if (this._undoTimeout) {
            this._commitDelete();
        }

        this._undoNotification = { ...notification };
        this.allNotifications = this.allNotifications.filter(n => n.id !== notificationId);
        this.totalCount = Math.max(0, this.totalCount - 1);
        this.showUndoToast = true;
        this.statusMessage = 'Notification deleted';

        if (this.allNotifications.length === 0) {
            const scroller = this.template.querySelector('c-fimby-infinite-scroll');
            if (scroller) {
                scroller.showEmptyState = true;
                scroller.finishLoading(false);
            }
        }

        this._undoTimeout = setTimeout(() => {
            this._commitDelete();
        }, UNDO_TIMEOUT_MS);
    }

    async _commitDelete() {
        this.showUndoToast = false;
        if (this._undoTimeout) {
            clearTimeout(this._undoTimeout);
            this._undoTimeout = null;
        }
        if (!this._undoNotification) return;

        const toDelete = this._undoNotification;
        this._undoNotification = null;

        try {
            await deleteNotification({ notificationId: toDelete.id });
            window.dispatchEvent(new CustomEvent('fimbyrequestbadgerefresh'));
        } catch (error) {
            console.error('Error deleting notification:', error);
        }
    }

    handleUndo() {
        if (this._undoTimeout) {
            clearTimeout(this._undoTimeout);
            this._undoTimeout = null;
        }
        this.showUndoToast = false;

        if (this._undoNotification) {
            this.allNotifications = [...this.allNotifications, this._undoNotification]
                .sort((a, b) => {
                    if (a.isUnread && !b.isUnread) return -1;
                    if (!a.isUnread && b.isUnread) return 1;
                    return new Date(b.createdDate) - new Date(a.createdDate);
                });
            this.totalCount += 1;
            this._undoNotification = null;
            this.statusMessage = 'Notification restored';

            const scroller = this.template.querySelector('c-fimby-infinite-scroll');
            if (scroller) {
                scroller.showEmptyState = false;
            }
        }
    }

    /* ---------------------------------------------------------------
     * Swipe gestures (mobile)
     * --------------------------------------------------------------- */

    handleSwipeStart(event) {
        if (!event.touches || event.touches.length !== 1) return;
        if (event.target.closest('.swipe-action')) return;

        const wrapper = event.currentTarget;
        const notificationId = wrapper.dataset.notificationId;

        if (this._openSwipeId && this._openSwipeId !== notificationId) {
            this._closeSwipe();
        }

        this._swipeId = notificationId;
        this._swipeStartX = event.touches[0].clientX;
        this._swipeStartY = event.touches[0].clientY;
        this._swipeDeltaX = 0;
        this._swiping = false;
    }

    handleSwipeMove(event) {
        if (!this._swipeId || !event.touches || event.touches.length !== 1) return;

        const dx = event.touches[0].clientX - this._swipeStartX;
        const dy = event.touches[0].clientY - this._swipeStartY;

        if (!this._swiping && Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy)) {
            this._swiping = true;
        }
        if (!this._swiping) return;

        event.preventDefault();

        if (this._openSwipeId === this._swipeId) {
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
        if (!this._swipeId) return;
        if (this._swiping) {
            event.preventDefault();
        }

        const wrapper = event.currentTarget;
        const fg = wrapper.querySelector('.swipe-foreground');
        const notificationId = this._swipeId;
        const delta = this._swipeDeltaX;

        this._swipeId = null;
        this._swiping = false;

        if (!fg) return;

        fg.style.transition = 'transform 0.2s ease';

        const wasOpen = (this._openSwipeId === notificationId);

        if (wasOpen) {
            if (delta > -SWIPE_ACTION_WIDTH / 2) {
                this._closeSwipeElement(fg, notificationId);
                return;
            }
            fg.style.transform = `translateX(-${SWIPE_ACTION_WIDTH}px)`;
            return;
        }

        if (delta >= SWIPE_THRESHOLD) {
            // Right swipe: auto-commit read/unread toggle, animate back
            fg.style.transform = `translateX(${SWIPE_ACTION_WIDTH}px)`;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                fg.style.transition = 'transform 0.2s ease';
                fg.style.transform = 'translateX(0)';
            }, 200);
            this._toggleReadState(notificationId);
        } else if (delta <= -SWIPE_THRESHOLD) {
            // Left swipe: reveal delete, stay open
            fg.style.transform = `translateX(-${SWIPE_ACTION_WIDTH}px)`;
            this._openSwipeId = notificationId;
        } else {
            fg.style.transform = 'translateX(0)';
        }
    }

    _closeSwipe() {
        if (!this._openSwipeId) return;
        const wrapper = this.template.querySelector(`.swipe-wrapper[data-notification-id="${this._openSwipeId}"]`);
        if (wrapper) {
            const fg = wrapper.querySelector('.swipe-foreground');
            if (fg) {
                fg.style.transition = 'transform 0.2s ease';
                fg.style.transform = 'translateX(0)';
            }
        }
        this._openSwipeId = null;
    }

    _closeSwipeElement(fg, notificationId) {
        fg.style.transform = 'translateX(0)';
        if (this._openSwipeId === notificationId) {
            this._openSwipeId = null;
        }
    }

    handleSwipeActionClick(event) {
        event.stopPropagation();
        const notificationId = event.currentTarget.dataset.notificationId;
        const wrapper = event.currentTarget.closest('.swipe-wrapper');
        const isDeleteAction = event.currentTarget.classList.contains('swipe-action-right');

        this._closeSwipe();

        if (isDeleteAction) {
            this._softDelete(notificationId);
        } else {
            this._toggleReadState(notificationId);
        }

        if (wrapper) {
            const fg = wrapper.querySelector('.swipe-foreground');
            if (fg) {
                fg.style.transition = 'transform 0.2s ease';
                fg.style.transform = 'translateX(0)';
            }
        }
    }

    /* ---------------------------------------------------------------
     * Desktop kebab menu
     * --------------------------------------------------------------- */

    handleKebabClick(event) {
        event.preventDefault();
        event.stopPropagation();

        const notificationId = event.currentTarget.dataset.notificationId;
        if (!notificationId) return;

        const notification = this.allNotifications.find(n => n.id === notificationId);
        const btn = event.currentTarget;
        const rect = btn.getBoundingClientRect();

        this._menuNotificationId = notificationId;
        this._menuIsUnread = !!notification?.isUnread;
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
        const notificationId = this._menuNotificationId;
        this._closeKebabMenu();

        if (action === 'delete') {
            this._softDelete(notificationId);
        } else if (action === 'mark-read' || action === 'mark-unread') {
            this._toggleReadState(notificationId);
        }
    }

    _closeKebabMenu() {
        this._menuNotificationId = null;
    }

    /* ---------------------------------------------------------------
     * Navigation
     * --------------------------------------------------------------- */

    handleTabChange(event) {
        const selectedTab = event.detail.tab;
        const routes = {
            home: '/',
            library: '/library-list',
            messages: '/messages',
            myStuff: '/my-stuff'
        };
        if (routes[selectedTab]) {
            navigate(this, routes[selectedTab]);
        }
    }
}