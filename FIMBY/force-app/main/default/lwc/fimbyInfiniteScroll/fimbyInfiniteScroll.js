import { LightningElement, api, track } from 'lwc';

const END_MESSAGE_BASE = "You're all caught up!";
const END_MESSAGE_VARIANTS = [
    "You're all caught up. Nice work!",
    "You're all caught up. See you around the neighbourhood.",
    "You're all caught up. IRL calls!",
    "You're all caught up. No more posts hiding down here.",
    "You're all caught up. That's the lot for now."
];

export default class FimbyInfiniteScroll extends LightningElement {
    // Configuration
    @api threshold = 300; // Distance from bottom to trigger load
    @api enablePullToRefresh = false;
    @api refreshThreshold = 100; // Pull distance to trigger refresh

    // States - use private tracked variables with public getters/setters
    _isLoading = false;
    _hasMoreData = true; // Default to true for auto-loading
    _showEmptyState = false;
    _showError = false;

    @api
    get isLoading() { return this._isLoading; }
    set isLoading(value) { this._isLoading = value; }

    @api
    get hasMoreData() { return this._hasMoreData; }
    set hasMoreData(value) {
        this._hasMoreData = value;
        if (value) {
            this._clearEndMessage();
        }
    }

    @api
    get showEmptyState() { return this._showEmptyState; }
    set showEmptyState(value) { this._showEmptyState = value; }

    @api
    get showError() { return this._showError; }
    set showError(value) { this._showError = value; }

    // Empty state
    @api emptyStateIcon = 'utility:inbox';
    @api emptyStateTitle = 'Nothing here yet';
    @api emptyStateMessage = 'Check back later for new content';
    @api emptyStateImageUrl;
    @api showEmptyAction = false;
    @api emptyActionLabel = 'Add Content';

    // Error state
    @api errorMessage = 'Unable to load content. Please check your connection.';

    // Internal state
    @track showPullRefresh = false;
    @track isPullingToRefresh = false;
    touchStartY = 0;
    currentPullDistance = 0;
    scrollPosition = 0;
    isLoadingMore = false;
    hasInitialLoadChecked = false;
    windowScrollHandler = null;
    _lastRefreshTime = 0;
    _refreshCooldownMs = 5000;
    @track _endMessageText = null;

    get pullRefreshClasses() {
        let classes = ['refresh-indicator'];
        if (this.isPullingToRefresh) {
            classes.push('active');
        }
        return classes.join(' ');
    }

    get pullRefreshText() {
        if (this.currentPullDistance >= this.refreshThreshold) {
            return 'Release to refresh';
        }
        return 'Pull to refresh';
    }

    get showEndMessage() {
        return !this._hasMoreData && !this._showEmptyState && !this._isLoading;
    }

    get endMessageText() {
        return this._endMessageText || END_MESSAGE_BASE;
    }

    connectedCallback() {
        // Add event listeners for better performance
        this.scrollHandler = this.throttle(this.handleScroll.bind(this), 100);

        // Also listen for window scroll (for desktop where container might not scroll)
        this.windowScrollHandler = this.throttle(this.handleWindowScroll.bind(this), 150);
        window.addEventListener('scroll', this.windowScrollHandler, { passive: true });
        console.log('📜 Infinite scroll: Added window scroll listener');
    }

    renderedCallback() {
        // Only check initial load once after first render
        // Don't keep auto-loading - let user scroll to trigger more loads
        if (!this.hasInitialLoadChecked && !this._isLoading && !this.isLoadingMore) {
            this.hasInitialLoadChecked = true;
            // Small delay to let initial content render
            setTimeout(() => {
                this.checkInitialLoad();
            }, 200);
        }

        if (this.showEndMessage && !this._endMessageText) {
            this._ensureEndMessage();
        }
    }

    disconnectedCallback() {
        // Cleanup if needed
        if (this.scrollTimeout) {
            clearTimeout(this.scrollTimeout);
        }
        // Remove window scroll listener
        if (this.windowScrollHandler) {
            window.removeEventListener('scroll', this.windowScrollHandler);
            console.log('📜 Infinite scroll: Removed window scroll listener');
        }
    }

    // Check if we need to load more initially (content doesn't fill the screen)
    // Only runs once on initial render - does NOT auto-fill the screen with multiple loads
    checkInitialLoad() {
        const container = this.template.querySelector('.scroll-container');
        if (container && !this._isLoading && this._hasMoreData && !this.isLoadingMore) {
            const scrollHeight = container.scrollHeight;
            const clientHeight = container.clientHeight;

            // If content doesn't fill the container, load ONE more batch
            // (user will need to scroll to load additional batches)
            if (scrollHeight <= clientHeight + this.threshold) {
                console.log('📜 Initial content does not fill screen, loading one more batch');
                this.loadMore();
            }
        }
    }

    // Scroll handling for container scroll (mobile/embedded)
    handleScroll(event) {
        const container = event.target;
        const scrollTop = container.scrollTop;
        const scrollHeight = container.scrollHeight;
        const clientHeight = container.clientHeight;

        // Update scroll position for pull-to-refresh
        this.scrollPosition = scrollTop;

        // Check if we need to load more data
        if (!this._isLoading && !this.isLoadingMore && this._hasMoreData) {
            const distanceFromBottom = scrollHeight - scrollTop - clientHeight;

            if (distanceFromBottom <= this.threshold) {
                console.log('📜 Container scroll: Triggering load more - distance from bottom:', distanceFromBottom);
                this.loadMore();
            }
        }

        // Hide pull refresh indicator if scrolling down
        if (scrollTop > 0 && this.showPullRefresh) {
            this.showPullRefresh = false;
            this.isPullingToRefresh = false;
            this.currentPullDistance = 0;
        }
    }

    // Window scroll handling (for desktop where document scrolls instead of container)
    handleWindowScroll() {
        // Don't trigger if already loading or no more data
        if (this._isLoading || this.isLoadingMore || !this._hasMoreData) {
            return;
        }

        // Calculate distance from bottom of page
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const scrollHeight = document.documentElement.scrollHeight;
        const clientHeight = window.innerHeight;
        const distanceFromBottom = scrollHeight - scrollTop - clientHeight;

        // Also check if this component is visible (in viewport)
        const container = this.template.querySelector('.scroll-container');
        if (!container) return;

        const rect = container.getBoundingClientRect();
        const isVisible = rect.top < clientHeight && rect.bottom > 0;

        if (isVisible && distanceFromBottom <= this.threshold) {
            console.log('📜 Window scroll: Triggering load more - distance from bottom:', distanceFromBottom);
            this.loadMore();
        }
    }

    // Touch handling for pull-to-refresh
    handleTouchStart(event) {
        if (!this.enablePullToRefresh) return;

        const container = this.template.querySelector('.scroll-container');
        if (container && container.scrollTop > 0) return;

        this.touchStartY = event.touches[0].clientY;
    }

    handleTouchMove(event) {
        if (!this.enablePullToRefresh) return;

        const container = this.template.querySelector('.scroll-container');
        if (!container || container.scrollTop > 0) return;

        const currentY = event.touches[0].clientY;
        const pullDistance = currentY - this.touchStartY;

        if (pullDistance > 0) {
            // Only prevent default if we're actually pulling down
            if (pullDistance > 10) {
                event.preventDefault();
            }

            this.currentPullDistance = Math.min(pullDistance, this.refreshThreshold * 1.5);
            this.showPullRefresh = true;

            // Update container transform for visual feedback
            const translateY = Math.min(pullDistance * 0.5, this.refreshThreshold);
            container.style.transform = `translateY(${translateY}px)`;
        }
    }

    handleTouchEnd() {
        if (!this.enablePullToRefresh) return;

        const container = this.template.querySelector('.scroll-container');
        if (container) {
            container.style.transform = '';
            container.style.transition = 'transform 0.3s ease';
            setTimeout(() => {
                container.style.transition = '';
            }, 300);
        }

        if (this.currentPullDistance >= this.refreshThreshold) {
            this.isPullingToRefresh = true;
            this.refresh();
        } else {
            this.showPullRefresh = false;
            this.isPullingToRefresh = false;
        }

        this.currentPullDistance = 0;
    }

    // Public methods
    @api
    loadMore() {
        if (this._isLoading || this.isLoadingMore || !this._hasMoreData) {
            console.log('📜 Skipping loadMore - isLoading:', this._isLoading, 'isLoadingMore:', this.isLoadingMore, 'hasMoreData:', this._hasMoreData);
            return;
        }

        console.log('📜 Dispatching loadmore event');
        this.isLoadingMore = true;

        const loadMoreEvent = new CustomEvent('loadmore', {
            detail: {
                scrollPosition: this.scrollPosition
            }
        });
        this.dispatchEvent(loadMoreEvent);
    }

    @api
    refresh() {
        const now = Date.now();
        if (this._isLoading || (now - this._lastRefreshTime) < this._refreshCooldownMs) {
            this.showPullRefresh = false;
            this.isPullingToRefresh = false;
            return;
        }

        this._lastRefreshTime = now;
        this._isLoading = true;
        this.hasInitialLoadChecked = false;
        this._clearEndMessage();

        this.dispatchEvent(new CustomEvent('refresh'));

        setTimeout(() => {
            this.showPullRefresh = false;
            this.isPullingToRefresh = false;
        }, 1000);
    }

    @api
    reset() {
        this.hasInitialLoadChecked = false;
        this._hasMoreData = true;
        this._isLoading = false;
        this.isLoadingMore = false;
        this._clearEndMessage();
    }

    @api
    restoreState(hasMoreData) {
        this.hasInitialLoadChecked = true;
        this._hasMoreData = hasMoreData;
        this._isLoading = false;
        this.isLoadingMore = false;
    }

    @api
    finishLoading(hasMoreData = true) {
        console.log('📜 finishLoading called with hasMoreData:', hasMoreData);
        this._isLoading = false;
        this.isLoadingMore = false;
        this._hasMoreData = hasMoreData;
        this._showError = false;
        // Note: We deliberately do NOT auto-load more here.
        // Users must scroll to trigger additional loads (standard infinite scroll behavior)
    }

    @api
    showErrorState(message = '') {
        this._isLoading = false;
        this.isLoadingMore = false;
        this._showError = true;
        if (message) {
            this.errorMessage = message;
        }
    }

    @api
    scrollToTop(smooth = true) {
        const container = this.template.querySelector('.scroll-container');
        if (container) {
            container.scrollTo({
                top: 0,
                behavior: smooth ? 'smooth' : 'auto'
            });
        }
    }

    @api
    scrollToElement(selector, smooth = true) {
        const element = this.template.querySelector(selector);
        if (element) {
            element.scrollIntoView({
                behavior: smooth ? 'smooth' : 'auto',
                block: 'start'
            });
        }
    }

    // Event handlers
    handleEmptyAction() {
        const emptyActionEvent = new CustomEvent('emptyaction');
        this.dispatchEvent(emptyActionEvent);
    }

    handleRetry() {
        this.showError = false;
        this.loadMore();
    }

    _ensureEndMessage() {
        if (!this._endMessageText) {
            this._endMessageText = this._pickEndMessage();
        }
    }

    _clearEndMessage() {
        this._endMessageText = null;
    }

    _pickEndMessage() {
        const pool = [
            END_MESSAGE_BASE,
            END_MESSAGE_BASE,
            END_MESSAGE_BASE,
            END_MESSAGE_BASE,
            END_MESSAGE_BASE,
            ...END_MESSAGE_VARIANTS
        ];
        return pool[Math.floor(Math.random() * pool.length)];
    }

    // Utility functions
    throttle(func, limit) {
        let inThrottle;
        return function() {
            const args = arguments;
            const context = this;
            if (!inThrottle) {
                func.apply(context, args);
                inThrottle = true;
                setTimeout(() => inThrottle = false, limit);
            }
        }
    }
}