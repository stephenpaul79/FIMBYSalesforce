import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import MEMES5 from '@salesforce/resourceUrl/Memes5';
import { CATEGORY_COLORS, getCategoryIconUrl, getCategoryStyle, getCategoryColor } from 'c/fimbyLibraryCategoryConfig';

import getLibraryItems from '@salesforce/apex/FimbyHomeController.getLibraryItems';
import getCategoryPicklistValues from '@salesforce/apex/FimbyLibraryController.getCategoryPicklistValues';
import { completeImageUrl, avatarImageUrl } from 'c/fimbyImageUrl';
import getCelebrationContext from '@salesforce/apex/FimbyProfileController.getCelebrationContext';
import isVouchedForBorrowing from '@salesforce/apex/FimbyLibraryController.isVouchedForBorrowing';

const INITIAL_FETCH_SIZE = 100;
const SCROLL_BATCH_SIZE = 50;
const LIB_CACHE_KEY = 'fimby-library-browser-v2';
const LIB_CACHE_MAX_AGE_MS = 15 * 60 * 1000;
const LIB_CACHE_MAX_ITEMS = 100;

export default class FimbyLibraryBrowser extends NavigationMixin(LightningElement) {

    // ======= Data =======
    @track allItems = [];
    @track filteredItems = [];
    @track isLoading = false;
    @track hasMoreContent = true;
    @track offset = 0;
    loadedIds = new Set();

    // ======= Meme preference =======
    @track _memesEnabled = false;

    // ======= Lightbox =======
    @track showLightbox = false;
    @track lightboxImages = [];
    @track lightboxStartIndex = 0;

    // ======= Categories =======
    @track categoryOptions = [];    // [{label, value}] from Apex
    @track selectedCategory = '';   // '' = All
    @track showDropdown = false;

    // ======= View mode =======
    @track viewMode = 'grid'; // 'grid' or 'list'

    // ======= Sticky header / scroll =======
    @track filterHidden = false;
    _lastScrollY = 0;
    _scrollTicking = false;

    // Vouching gate
    @track _isVouchedForBorrowing = null;
    @track isSettlingIn = false;

    // State persistence for back-navigation restore
    _pendingScrollY = null;
    _restoredFromCache = false;
    _saveThrottleTimer = null;

    // Auto-load for thin filters
    minFilteredItems = 5;
    maxFilterAutoLoadBatches = 3;
    filterAutoLoadCount = 0;

    // =============================================
    // LIFECYCLE
    // =============================================

    async connectedCallback() {
        try {
            const [celebCtx, vouched] = await Promise.all([
                getCelebrationContext(),
                isVouchedForBorrowing()
            ]);
            this._memesEnabled = celebCtx?.memesEnabled !== false;
            this._isVouchedForBorrowing = vouched === true;
            this.isSettlingIn = vouched === false;
        } catch (e) {
            console.error('Init error', e);
        }
        this._restoreViewPreference();
        this.loadCategories();

        if (!this._restoreLibraryState()) {
            this.loadInitialData();
        }

        this._windowScrollHandler = () => {
            if (!this._scrollTicking) {
                requestAnimationFrame(() => {
                    this._handleScrollDirection();
                    this._throttledSaveLibraryState();
                    this._scrollTicking = false;
                });
                this._scrollTicking = true;
            }
        };
        window.addEventListener('scroll', this._windowScrollHandler, { passive: true });

        this._pagehideHandler = () => this._saveLibraryState();
        window.addEventListener('pagehide', this._pagehideHandler);
    }

    disconnectedCallback() {
        if (this._windowScrollHandler) {
            window.removeEventListener('scroll', this._windowScrollHandler);
        }
        if (this._pagehideHandler) {
            window.removeEventListener('pagehide', this._pagehideHandler);
        }
    }

    _handleScrollDirection() {
        const currentY = window.scrollY || window.pageYOffset;
        const delta = currentY - this._lastScrollY;
        const isMobile = window.innerWidth < 768;

        if (isMobile) {
            if (delta > 10 && currentY > 80) {
                this.filterHidden = true;
            } else if (delta < -10) {
                this.filterHidden = false;
            }
        } else {
            this.filterHidden = false;
        }

        this._lastScrollY = currentY;
    }

    async loadCategories() {
        try {
            const data = await getCategoryPicklistValues();
            if (data) {
                this.categoryOptions = data.map(c => ({
                    label: c.label || c.value,
                    value: c.value || c.label,
                    color: CATEGORY_COLORS[c.label || c.value] || CATEGORY_COLORS[c.value || c.label] || '#9CA3AF'
                }));
            }
        } catch (error) {
            console.error('Category picklist error', error);
        }
    }

    // =============================================
    // DATA LOADING (mirrors HomeFeed pattern)
    // =============================================

    async loadInitialData() {
        this.isLoading = true;
        this.offset = 0;
        this.allItems = [];
        this.filteredItems = [];
        this.hasMoreContent = true;
        this.loadedIds = new Set();
        this.filterAutoLoadCount = 0;
        this._clearLibraryCache();

        const scroll = this.template.querySelector('c-fimby-infinite-scroll');
        if (scroll && scroll.reset) scroll.reset();

        try {
            await this.loadNextBatch();
        } catch (e) {
            console.error('Initial load error', e);
            this.showToast('Error', 'Failed to load library items', 'error');
        } finally {
            this.isLoading = false;
            this.updateScrollContainer();
        }
    }

    async loadNextBatch() {
        const effectivePageSize = this.offset === 0 ? INITIAL_FETCH_SIZE : SCROLL_BATCH_SIZE;

        const result = await getLibraryItems({
            offset: this.offset,
            pageSize: effectivePageSize
        });

        if (result && result.length > 0) {
            const newItems = result.filter(item => {
                if (this.loadedIds.has(item.Id)) return false;
                return true;
            });

            newItems.forEach(item => this.loadedIds.add(item.Id));

            const processed = this.processItems(newItems);
            this.allItems = [...this.allItems, ...processed];
            this.offset += result.length;
            this.hasMoreContent = result.length >= effectivePageSize;
            this.applyFilter();
        } else {
            this.hasMoreContent = false;
        }
    }

    processItems(items) {
        return items.map(item => {
            const imageUrl = completeImageUrl(item.Image_URL__c);
            const category = item.Category__c || 'Other';
            const color = getCategoryColor(category);
            const hasValidImage = !!imageUrl && imageUrl.trim() !== '';

            const ownerAvatarRaw = item.ownerAvatar;

            return {
                id: item.Id,
                name: item.Name,
                description: item.Description__c || '',
                category: category,
                categoryColor: color,
                categoryStyle: getCategoryStyle(category),
                categoryIconUrl: getCategoryIconUrl(IMPACT_ICONS, category),
                status: item.Status__c || '',
                createdDate: item.CreatedDate,
                ownerName: item.ownerName || '',
                ownerAvatar: ownerAvatarRaw ? avatarImageUrl(ownerAvatarRaw) : '',
                showImage: hasValidImage,
                imageUrl: imageUrl,
                images: hasValidImage ? [{ url: imageUrl, ratio: item.Image_Ratio__c || '', alt: item.Name || '' }] : [],
                viewerState: item.viewerState,
                primaryAction: item.primaryAction,
                ctaLabel: item.ctaLabel,
                ctaPillClass: item.ctaPillClass,
                statusPillLabel: item.statusPillLabel,
                statusPillClass: item.statusPillClass,
                allocationPills: [{ key: 'status', label: item.statusPillLabel, cssClass: item.statusPillClass }],
                responseLabel: item.ctaLabel,
                responsePillClass: item.ctaPillClass,
                responseIconUrl: (item.primaryAction === 'borrow' || item.primaryAction === 'joinWaitlist')
                    ? `${IMPACT_ICONS}/borrow.png`
                    : `${IMPACT_ICONS}/Magnify.png`,
                showCardMenu: item.viewerState !== 'owner'
            };
        });
    }

    // =============================================
    // FILTERING
    // =============================================

    applyFilter() {
        window.scrollTo({ top: 0, behavior: 'smooth' });

        if (!this.selectedCategory) {
            this.filteredItems = [...this.allItems];
        } else {
            this.filteredItems = this.allItems.filter(i => i.category === this.selectedCategory);
        }
        this.checkAndLoadMoreForFilter();
    }

    async checkAndLoadMoreForFilter() {
        if (this.selectedCategory &&
            this.filteredItems.length < this.minFilteredItems &&
            this.hasMoreContent &&
            !this.isLoading &&
            this.filterAutoLoadCount < this.maxFilterAutoLoadBatches) {

            this.filterAutoLoadCount++;
            this.isLoading = true;
            try {
                await this.loadNextBatch();
                if (!this.selectedCategory) {
                    this.filteredItems = [...this.allItems];
                } else {
                    this.filteredItems = this.allItems.filter(i => i.category === this.selectedCategory);
                }
                if (this.filteredItems.length < this.minFilteredItems &&
                    this.hasMoreContent &&
                    this.filterAutoLoadCount < this.maxFilterAutoLoadBatches) {
                    setTimeout(() => this.checkAndLoadMoreForFilter(), 100);
                }
            } catch (e) {
                console.error('Filter auto-load error', e);
            } finally {
                this.isLoading = false;
                this.updateScrollContainer();
            }
        }
    }

    // =============================================
    // GETTERS – sticky header & filter bar
    // =============================================

    get stickyHeaderClass() {
        return this.filterHidden
            ? 'library-sticky-header filter-hidden'
            : 'library-sticky-header';
    }

    get filterIconUrl() {
        return `${IMPACT_ICONS}/ToolboxActive.png`;
    }

    get refreshIconUrl() {
        return `${IMPACT_ICONS}/refresh.png`;
    }

    get refreshButtonClass() {
        return this.isLoading ? 'refresh-button refreshing' : 'refresh-button';
    }

    get allChipClass() {
        return !this.selectedCategory ? 'filter-chip active' : 'filter-chip';
    }

    get hasSelectedCategory() {
        return !!this.selectedCategory;
    }

    get selectedCategoryLabel() {
        return this.selectedCategory || '';
    }

    get selectedCategoryStyle() {
        const color = CATEGORY_COLORS[this.selectedCategory] || '#9CA3AF';
        return `background-color: ${color}; color: #ffffff; border-color: ${color};`;
    }

    get dropdownButtonClass() {
        let cls = 'filter-chip dropdown-trigger';
        if (this.showDropdown) cls += ' open';
        if (this.hasSelectedCategory) cls += ' filter-active';
        return cls;
    }

    // Dropdown items with colour dot
    get dropdownCategories() {
        return this.categoryOptions.map(c => ({
            ...c,
            dotStyle: `background-color: ${c.color};`,
            isSelected: c.value === this.selectedCategory
        }));
    }

    // =============================================
    // GETTERS – view mode
    // =============================================

    get isGridView() {
        return this.viewMode === 'grid';
    }

    get isListView() {
        return this.viewMode === 'list';
    }

    get cardLayout() {
        return this.isGridView ? 'compact' : 'list';
    }

    get feedSectionClass() {
        let cls = this.isGridView ? 'feed-section feed-grid' : 'feed-section feed-list';
        if (this.isGridView) {
            const count = this.displayItems.length;
            if (count === 1) cls += ' grid-single';
            else if (count === 2) cls += ' grid-pair';
        }
        return cls;
    }

    get gridToggleClass() {
        return this.isGridView ? 'view-toggle-btn active' : 'view-toggle-btn';
    }

    get listToggleClass() {
        return this.isListView ? 'view-toggle-btn active' : 'view-toggle-btn';
    }

    // =============================================
    // GETTERS – feed
    // =============================================

    get displayItems() {
        return this.filteredItems;
    }

    get showEmptyState() {
        return !this.isLoading && this.allItems.length === 0;
    }

    get emptyStateGifUrl() {
        return this._memesEnabled ? `${MEMES5}/still-waiting.gif` : null;
    }

    get displayHasMoreContent() {
        if (this.selectedCategory &&
            this.filteredItems.length === 0 &&
            !this.isLoading) {
            return false;
        }
        return this.hasMoreContent;
    }

    // =============================================
    // HANDLERS – filter chips
    // =============================================

    handleAllChip() {
        this.selectedCategory = '';
        this.filterAutoLoadCount = 0;
        this.showDropdown = false;
        this._clearLibraryCache();
        this.applyFilter();
    }

    handleClearCategory(event) {
        event.stopPropagation();
        this.handleAllChip();
    }

    handleToggleDropdown() {
        this.showDropdown = !this.showDropdown;
    }

    handleCloseDropdown() {
        this.showDropdown = false;
    }

    handleSelectCategory(event) {
        const category = event.currentTarget.dataset.value;
        this.selectedCategory = category;
        this.filterAutoLoadCount = 0;
        this.showDropdown = false;
        this._clearLibraryCache();
        this.applyFilter();
    }

    // =============================================
    // HANDLERS – view toggle
    // =============================================

    handleGridView() {
        this.viewMode = 'grid';
        this._saveViewPreference();
    }

    handleListView() {
        this.viewMode = 'list';
        this._saveViewPreference();
    }

    _saveViewPreference() {
        try { localStorage.setItem('fimby-library-view', this.viewMode); } catch (e) { /* ignore */ }
    }

    _restoreViewPreference() {
        try {
            if (typeof window !== 'undefined' && window.innerWidth < 768) {
                this.viewMode = 'grid';
                return;
            }
            const saved = localStorage.getItem('fimby-library-view');
            if (saved === 'grid' || saved === 'list') this.viewMode = saved;
        } catch (e) { /* ignore */ }
    }

    // =============================================
    // HANDLERS – feed interactions
    // =============================================

    handleCardClick(event) {
        const itemId = event.currentTarget.dataset.recordId;
        if (itemId) {
            location.href = `/library-item/${itemId}`;
        }
    }

    handleCardKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleCardClick(event);
        }
    }

    async handleCardRespond(event) {
        event.stopPropagation();
        const wrapper = event.target.closest('[data-record-id]');
        const itemId = wrapper?.dataset?.recordId;
        if (!itemId) return;

        // Vouching gate: settling-in members cannot borrow.
        if (!(await this._ensureVouched())) {
            this._openVouchingRequiredModal();
            return;
        }

        const item = this.allItems.find(i => i.id === itemId);
        if (!item) return;

        if (item.primaryAction === 'borrow' || item.primaryAction === 'joinWaitlist') {
            const modal = this.template.querySelector('c-fimby-quick-response-modal');
            if (modal) modal.show(itemId, 'library');
        } else {
            location.href = `/library-item/${itemId}`;
        }
    }

    async handleResponseSaved() {
        await this.loadInitialData();
    }

    handleAddItem() {
        location.href = '/add-library-item';
    }

    handleLoadMore() {
        if (!this.hasMoreContent || this.isLoading) return;
        this.loadMoreContent();
    }

    async loadMoreContent() {
        if (this.isLoading) return;
        this.isLoading = true;
        try {
            await this.loadNextBatch();
        } catch (e) {
            console.error('Load more error', e);
            this.showToast('Error', 'Failed to load more items', 'error');
        } finally {
            this.isLoading = false;
            this.updateScrollContainer();
        }
    }

    handleRefresh() {
        this.loadInitialData();
    }

    handleCardReport(event) {
        event.stopPropagation();
        const wrapper = event.target.closest('[data-record-id]');
        const itemId = wrapper?.dataset?.recordId;
        if (!itemId) return;
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) {
            modal.show(itemId, 'Library_Item');
        }
    }

    handleTabChange(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: event.detail.tab }
        });
    }

    // =============================================
    // LIGHTBOX
    // =============================================

    handleImageClick(event) {
        const detail = event.detail;
        if (detail && detail.images && detail.images.length > 0) {
            this.lightboxImages = detail.images;
            this.lightboxStartIndex = detail.index || 0;
            this.showLightbox = true;

            requestAnimationFrame(() => {
                const lb = this.template.querySelector('c-fimby-lightbox');
                if (lb) lb.open(this.lightboxStartIndex);
            });
        }
    }

    handleLightboxClose() {
        this.showLightbox = false;
        this.lightboxImages = [];
        this.lightboxStartIndex = 0;
    }

    // =============================================
    // STATE PERSISTENCE (sessionStorage)
    // =============================================

    _saveLibraryState() {
        if (!this.allItems || this.allItems.length === 0) return;
        try {
            const state = {
                allItems: this.allItems.slice(0, LIB_CACHE_MAX_ITEMS),
                offset: this.offset,
                loadedIds: [...this.loadedIds],
                selectedCategory: this.selectedCategory,
                hasMoreContent: this.hasMoreContent,
                scrollY: window.scrollY,
                timestamp: Date.now()
            };
            sessionStorage.setItem(LIB_CACHE_KEY, JSON.stringify(state));
        } catch (e) { /* storage unavailable or full */ }
    }

    _throttledSaveLibraryState() {
        if (this._saveThrottleTimer) return;
        this._saveThrottleTimer = setTimeout(() => {
            this._saveThrottleTimer = null;
            this._saveLibraryState();
        }, 2000);
    }

    _restoreLibraryState() {
        try {
            const raw = sessionStorage.getItem(LIB_CACHE_KEY);
            if (!raw) return false;

            const state = JSON.parse(raw);
            if (Date.now() - state.timestamp > LIB_CACHE_MAX_AGE_MS) {
                sessionStorage.removeItem(LIB_CACHE_KEY);
                return false;
            }

            this.allItems = state.allItems;
            this.offset = state.offset;
            this.loadedIds = new Set(state.loadedIds);
            this.selectedCategory = state.selectedCategory || '';
            this.hasMoreContent = state.hasMoreContent;

            if (!this.selectedCategory) {
                this.filteredItems = [...this.allItems];
            } else {
                this.filteredItems = this.allItems.filter(i => i.category === this.selectedCategory);
            }

            this._pendingScrollY = state.scrollY;
            this._restoredFromCache = true;
            return true;
        } catch (e) {
            return false;
        }
    }

    _clearLibraryCache() {
        try { sessionStorage.removeItem(LIB_CACHE_KEY); } catch (e) { /* ignore */ }
    }

    renderedCallback() {
        if (this._pendingScrollY != null && this._restoredFromCache) {
            const scroll = this.template.querySelector('c-fimby-infinite-scroll');
            if (scroll && scroll.restoreState) {
                scroll.restoreState(this.hasMoreContent);
            }

            const savedY = this._pendingScrollY;
            this._pendingScrollY = null;
            this._restoredFromCache = false;
            requestAnimationFrame(() => {
                window.scrollTo(0, savedY);
            });
        }
    }

    // =============================================
    // HELPERS
    // =============================================

    updateScrollContainer() {
        const scroll = this.template.querySelector('c-fimby-infinite-scroll');
        if (scroll && scroll.finishLoading) {
            scroll.finishLoading(this.hasMoreContent);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: 'pester' }));
    }

    /* --- Vouching gate ---------------------------------------------- */

    get saplingIconUrl() {
        return `${IMPACT_ICONS}/Sapling.png`;
    }

    async _ensureVouched() {
        if (this._isVouchedForBorrowing === true) return true;
        if (this._isVouchedForBorrowing === false) return false;
        try {
            const vouched = await isVouchedForBorrowing();
            this._isVouchedForBorrowing = vouched === true;
            this.isSettlingIn = vouched === false;
        } catch (e) {
            console.error('Vouching check error', e);
            this._isVouchedForBorrowing = false;
            this.isSettlingIn = true;
        }
        return this._isVouchedForBorrowing === true;
    }

    _openVouchingRequiredModal() {
        const modal = this.template.querySelector('c-fimby-vouching-required-modal');
        if (modal) modal.show();
    }

    handleOpenVouchingRequiredModal(event) {
        if (event && event.preventDefault) event.preventDefault();
        this._openVouchingRequiredModal();
    }
}