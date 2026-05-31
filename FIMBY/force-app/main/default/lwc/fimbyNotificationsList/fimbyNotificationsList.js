import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getNotifications from '@salesforce/apex/FimbyNotificationController.getNotifications';
import markAsRead from '@salesforce/apex/FimbyNotificationController.markAsRead';
import markAllAsRead from '@salesforce/apex/FimbyNotificationController.markAllAsRead';
import markAsUnread from '@salesforce/apex/FimbyNotificationController.markAsUnread';
import deleteNotification from '@salesforce/apex/FimbyNotificationController.deleteNotification';
import deleteAllNotifications from '@salesforce/apex/FimbyNotificationController.deleteAllNotifications';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const PAGE_SIZE = 20;
const SWIPE_THRESHOLD = 40;
const SWIPE_ACTION_WIDTH = 80;
const UNDO_TIMEOUT_MS = 5000;

// Hosts the LWC may navigate to. Anything else is treated as untrusted and
// routed back to /notifications. Keep in sync with the FIMBY_URL__mdt base
// URLs and any future app.fimby.com host swap.
const ALLOWED_HOSTS = ['our.fimby.com', 'app.fimby.com'];

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


export default class FimbyNotificationsList extends NavigationMixin(LightningElement) {
    allNotifications = [];
    totalCount = 0;
    currentOffset = 0;
    showConfirmation = false;
    statusMessage = '';

    showUndoToast = false;
    _undoNotification = null;
    _undoTimeout = null;

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

    get groupedNotifications() {
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);
        const weekAgo = new Date(today);
        weekAgo.setDate(weekAgo.getDate() - 7);

        const buckets = new Map([
            ['Today', []],
            ['Yesterday', []],
            ['This Week', []],
            ['Older', []]
        ]);

        this.allNotifications.forEach(n => {
            const d = new Date(n.createdDate);
            if (d >= today) buckets.get('Today').push(n);
            else if (d >= yesterday) buckets.get('Yesterday').push(n);
            else if (d >= weekAgo) buckets.get('This Week').push(n);
            else buckets.get('Older').push(n);
        });

        const groups = [];
        buckets.forEach((items, label) => {
            if (items.length > 0) {
                groups.push({
                    label,
                    key: label,
                    items: items.map(n => this._enrichNotification(n))
                });
            }
        });
        return groups;
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
        const actor = (n.actorName || '').trim();
        const body = (n.body || '').trim();
        const hasActor = !!actor;
        const hasBody = !!body;
        return {
            ...n,
            typeIconUrl: `${IMPACT_ICONS}/${TYPE_ICON_MAP[n.type] || 'BellInactive.png'}`,
            formattedTime: this._formatTime(n.createdDate),
            containerClass: 'notification-item' + (isUnread ? ' unread' : ''),
            displayTitle: n.title || '',
            displayActor: actor,
            displayBody: body,
            hasActor,
            hasBody,
            readToggleLabel: isUnread ? 'Mark as read' : 'Mark as unread',
            readStatusLabel: isUnread ? 'Read' : 'Unread',
            readStatusIconUrl: isUnread ? this.readIconUrl : this.unreadIconUrl,
            readSwipeClass: 'swipe-action swipe-action-left ' + (isUnread ? 'swipe-mark-read' : 'swipe-mark-unread')
        };
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
        window.location.href = '/settings';
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
        event.preventDefault();
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
            window.location.href = target;
        }
    }

    /**
     * Decide which URL to send the user to when they tap a notification.
     * Trust order:
     *   1. notification.actionUrl, if it points to a FIMBY host (or is
     *      relative).
     *   2. Fallback URL derived from related-record type when the action
     *      URL is missing or untrusted.
     *   3. /notifications (no-op refresh) as a last resort.
     */
    _normalizeLegacyActionUrl(url) {
        if (!url) return url;
        const legacyMessages = url.match(
            /^(?:https:\/\/[^/]+)?(\/messages\/([a-zA-Z0-9]{15,18}))(?:\/|$|\?|#)/
        );
        if (legacyMessages) {
            return `/conversation?id=${legacyMessages[2]}`;
        }
        return url;
    }

    _resolveSafeUrl(notification) {
        const raw = (notification && notification.actionUrl) ? notification.actionUrl.trim() : '';
        if (raw) {
            const normalized = this._normalizeLegacyActionUrl(raw);
            if (normalized.startsWith('/')) return normalized;
            try {
                const parsed = new URL(normalized);
                if (ALLOWED_HOSTS.includes(parsed.host)) {
                    return this._normalizeLegacyActionUrl(normalized);
                }
                console.warn('FimbyNotificationsList: blocked off-host actionUrl', parsed.host);
            } catch (err) {
                console.warn('FimbyNotificationsList: unparseable actionUrl', raw);
            }
        }
        return this._buildFallbackUrl(notification);
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

    async _toggleReadState(notificationId) {
        const notification = this.allNotifications.find(n => n.id === notificationId);
        if (!notification) return;

        const wasUnread = notification.isUnread;
        this.allNotifications = this.allNotifications.map(n =>
            n.id === notificationId ? { ...n, isUnread: !wasUnread } : n
        );
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
            window.location.href = routes[selectedTab];
        }
    }
}