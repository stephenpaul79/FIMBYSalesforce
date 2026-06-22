import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecordPageReference, startNavTiming, navigate, profilePathForContact } from 'c/fimbyNavigation';
import { registerTourAnchorProvider } from 'c/fimbyGuidedTourAnchorRegistry';
import { fireToast } from 'c/fimbyToastHelper';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import MEMES5 from '@salesforce/resourceUrl/Memes5';
import { CATEGORY_COLORS, getCategoryIconUrl, getCategoryStyle, getCategoryColor } from 'c/fimbyLibraryCategoryConfig';
import { CATEGORY_COLORS as SKILL_CATEGORY_COLORS, getCategoryIconUrl as getSkillCategoryIconUrl, getCategoryStyle as getSkillCategoryStyle, getCategoryColor as getSkillCategoryColor } from 'c/fimbySkillCategoryConfig';

import getLibraryItems from '@salesforce/apex/FimbyHomeController.getLibraryItems';
import getSkills from '@salesforce/apex/FimbySkillsController.getSkills';
import getCategoryPicklistValues from '@salesforce/apex/FimbyLibraryController.getCategoryPicklistValues';
import getSkillCategoryPicklistValues from '@salesforce/apex/FimbySkillsController.getSkillCategoryPicklistValues';
import { completeImageUrl, avatarImageUrl } from 'c/fimbyImageUrl';
import getCelebrationContext from '@salesforce/apex/FimbyProfileController.getCelebrationContext';
import isVouchedForBorrowing from '@salesforce/apex/FimbyLibraryController.isVouchedForBorrowing';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';

const INITIAL_FETCH_SIZE = 100;
const SCROLL_BATCH_SIZE = 50;
const LIB_CACHE_KEY = 'fimby-library-browser-v3';
const LIB_CACHE_MAX_AGE_MS = 15 * 60 * 1000;
const LIB_CACHE_MAX_ITEMS = 100;

export default class FimbyLibraryBrowser extends NavigationMixin(LightningElement) {

    // ======= Data =======
    @track allItems = [];
    @track filteredItems = [];
    @track isLoading = true;
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
    @track viewContentMode = 'all'; // 'all', 'items', or 'skills'

    _itemsOffset = 0;
    _skillsOffset = 0;

    // ======= Sticky header / scroll =======
    @track filterHidden = false;
    _lastScrollY = 0;
    _scrollTicking = false;

    // Vouching gate
    @track _isVouchedForBorrowing = null;
    @track isSettlingIn = false;
    currentContactId = null;

    // State persistence for back-navigation restore
    _pendingScrollY = null;
    _restoredFromCache = false;
    _saveThrottleTimer = null;
    // Holds the feed invisible during a cache-resume scroll restore.
    @track _resumeHidden = false;

    // Auto-load for thin filters
    minFilteredItems = 5;
    maxFilterAutoLoadBatches = 3;
    filterAutoLoadCount = 0;

    // =============================================
    // LIFECYCLE
    // =============================================

    async connectedCallback() {
        try {
            const [celebCtx, vouched, identity] = await Promise.all([
                getCelebrationContext(),
                isVouchedForBorrowing(),
                getActingAsContact()
            ]);
            this.currentContactId = identity?.contactId || identity?.realContactId || null;
            this._memesEnabled = celebCtx?.memesEnabled !== false;
            this._isVouchedForBorrowing = vouched === true;
            this.isSettlingIn = vouched === false;
        } catch (e) {
            console.error('Init error', e);
        }
        this._restoreViewPreference();
        this.loadCategories();

        if (this._restoreLibraryState()) {
            this.isLoading = false;
            // Cache resume: hide the feed from the first paint so the upcoming
            // scroll-position restore happens while invisible (no top→saved
            // jump). Revealed in renderedCallback once scroll is set.
            this._resumeHidden = true;
        } else {
            this.loadInitialData();
        }

        this._windowScrollHandler = () => {
            if (!this._scrollTicking) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation -- scroll/focus after render
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
        this._unregisterTourAnchors = registerTourAnchorProvider(this);
    }

    @api
    getTourAnchorRect(name) {
        const el = this.template.querySelector(`[data-tour="${name}"]`);
        if (!el) {
            return null;
        }
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 ? rect : null;
    }

    disconnectedCallback() {
        if (this._windowScrollHandler) {
            window.removeEventListener('scroll', this._windowScrollHandler);
        }
        if (this._pagehideHandler) {
            window.removeEventListener('pagehide', this._pagehideHandler);
        }
        if (this._unregisterTourAnchors) {
            this._unregisterTourAnchors();
        }
        // Under the persistent shell this view remounts on every soft nav and
        // pagehide never fires, so flush any pending scroll-state save now;
        // otherwise back-navigation would restore a stale scroll position.
        if (this._saveThrottleTimer) {
            clearTimeout(this._saveThrottleTimer);
            this._saveThrottleTimer = null;
        }
        this._saveLibraryState();
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
            if (this.isAllMode) {
                this.categoryOptions = [];
                return;
            }

            const data = this.isSkillsMode
                ? await getSkillCategoryPicklistValues()
                : await getCategoryPicklistValues();
            if (data) {
                const mapped = data.map(c => {
                    const val = c.value || c.label;
                    const colorMap = this.isSkillsMode ? SKILL_CATEGORY_COLORS : CATEGORY_COLORS;
                    return {
                        label: c.label || c.value,
                        value: val,
                        color: colorMap[val] || '#9CA3AF'
                    };
                });
                mapped.sort((a, b) => a.label.localeCompare(b.label, undefined, { sensitivity: 'base' }));
                this.categoryOptions = mapped;
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
        this._itemsOffset = 0;
        this._skillsOffset = 0;
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
            fireToast({ message: 'We couldn’t load the library just now. Please try again.', variant: 'error' });
        } finally {
            this.isLoading = false;
            this.updateScrollContainer();
        }
    }

    async loadNextBatch() {
        const effectivePageSize = this.offset === 0 ? INITIAL_FETCH_SIZE : SCROLL_BATCH_SIZE;

        if (this.isAllMode) {
            const half = Math.ceil(effectivePageSize / 2);
            const [itemsResult, skillsResult] = await Promise.all([
                getLibraryItems({ offset: this._itemsOffset, pageSize: half }),
                getSkills({ offset: this._skillsOffset, pageSize: half })
            ]);
            const itemsArr = itemsResult || [];
            const skillsArr = skillsResult || [];

            const newLibraryItems = itemsArr.filter(item => !this.loadedIds.has(item.Id));
            const newSkillItems = skillsArr.filter(item => !this.loadedIds.has(item.id));

            newLibraryItems.forEach(item => this.loadedIds.add(item.Id));
            newSkillItems.forEach(item => this.loadedIds.add(item.id));

            const processed = [
                ...this.processItems(newLibraryItems),
                ...this.processSkillItems(newSkillItems)
            ].sort((a, b) => {
                const aTime = a.createdDate ? new Date(a.createdDate).getTime() : 0;
                const bTime = b.createdDate ? new Date(b.createdDate).getTime() : 0;
                return bTime - aTime;
            });

            if (processed.length > 0) {
                this.allItems = [...this.allItems, ...processed];
                this._itemsOffset += itemsArr.length;
                this._skillsOffset += skillsArr.length;
                this.offset += itemsArr.length + skillsArr.length;
                const itemsHasMore = itemsArr.length >= half;
                const skillsHasMore = skillsArr.length >= half;
                this.hasMoreContent = itemsHasMore || skillsHasMore;
                this._applyCategoryFilter();
            } else if (itemsArr.length === 0 && skillsArr.length === 0) {
                this.hasMoreContent = false;
            }
            return;
        }

        const result = this.isSkillsMode
            ? await getSkills({ offset: this.offset, pageSize: effectivePageSize })
            : await getLibraryItems({ offset: this.offset, pageSize: effectivePageSize });

        if (result && result.length > 0) {
            const newItems = result.filter(item => {
                const id = this.isSkillsMode ? item.id : item.Id;
                if (this.loadedIds.has(id)) return false;
                return true;
            });

            newItems.forEach(item => {
                const id = this.isSkillsMode ? item.id : item.Id;
                this.loadedIds.add(id);
            });

            const processed = this.isSkillsMode
                ? this.processSkillItems(newItems)
                : this.processItems(newItems);
            this.allItems = [...this.allItems, ...processed];
            this.offset += result.length;
            this.hasMoreContent = result.length >= effectivePageSize;
            this._applyCategoryFilter();
        } else {
            this.hasMoreContent = false;
        }
    }

    _applyCategoryFilter() {
        if (!this.selectedCategory) {
            this.filteredItems = [...this.allItems];
        } else {
            this.filteredItems = this.allItems.filter(i => i.category === this.selectedCategory);
        }
    }

    processSkillItems(items) {
        return items.map(item => {
            const category = item.category || 'Other / General Help';
            const color = getSkillCategoryColor(category);
            const ownerAvatarRaw = item.ownerImageUrl;

            return {
                id: item.id,
                name: item.title,
                titleLeadLabel: 'Skill',
                description: item.description || '',
                category,
                categoryColor: color,
                categoryStyle: getSkillCategoryStyle(category),
                categoryIconUrl: getSkillCategoryIconUrl(IMPACT_ICONS, category),
                createdDate: item.createdDate,
                ownerName: item.ownerName || '',
                ownerAvatar: ownerAvatarRaw ? avatarImageUrl(ownerAvatarRaw) : '',
                showImage: false,
                imageUrl: '',
                images: [],
                isSkill: true,
                ctaLabel: 'Ask for Help',
                ctaPillClass: 'response-pill primary',
                responseLabel: 'Ask for Help',
                responsePillClass: 'response-pill primary',
                responseIconUrl: `${IMPACT_ICONS}/lightbulb.png`,
                showCardMenu: true,
                primaryAction: 'skillHelp'
            };
        });
    }

    processItems(items) {
        return items.map(item => {
            const imageUrl = completeImageUrl(item.Image_URL__c);
            const category = item.Category__c || 'Other';
            const color = getCategoryColor(category);
            const hasValidImage = !!imageUrl && imageUrl.trim() !== '';

            const ownerAvatarRaw = item.ownerAvatar;

            const ownerContactId = item.ownerContactId || item.Owner_Contact__c;
            const isOrgContact = item.isOrgContact === true;
            const orgAccountId = item.orgAccountId;
            const posterProfileUrl = profilePathForContact({
                contactId: ownerContactId,
                isOrgContact,
                orgAccountId,
                currentContactId: this.currentContactId
            });

            return {
                id: item.Id,
                name: item.Name,
                titleLeadLabel: 'Item',
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
                showCardMenu: item.viewerState !== 'owner',
                isOrgPoster: isOrgContact,
                posterProfileUrl
            };
        });
    }

    // =============================================
    // FILTERING
    // =============================================

    applyFilter() {
        window.scrollTo({ top: 0, behavior: 'smooth' });
        this._applyCategoryFilter();
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
                this._applyCategoryFilter();
                if (this.filteredItems.length < this.minFilteredItems &&
                    this.hasMoreContent &&
                    this.filterAutoLoadCount < this.maxFilterAutoLoadBatches) {
                    // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce / delayed UI
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

    get scrollContainerClass() {
        return this._resumeHidden
            ? 'library-scroll-container is-resume-hidden'
            : 'library-scroll-container';
    }

    get refreshIconUrl() {
        return `${IMPACT_ICONS}/refresh.png`;
    }

    get refreshButtonClass() {
        return this.isLoading ? 'refresh-button refreshing' : 'refresh-button';
    }

    get allChipClass() {
        return this.isAllMode ? 'filter-chip mode-chip active' : 'filter-chip mode-chip';
    }

    get showCategoryFilter() {
        return this.isItemsMode || this.isSkillsMode;
    }

    get showSelectedCategoryChip() {
        return this.showCategoryFilter && !!this.selectedCategory;
    }

    get hasSelectedCategory() {
        return !!this.selectedCategory;
    }

    get selectedCategoryLabel() {
        return this.selectedCategory || '';
    }

    get selectedCategoryStyle() {
        const color = CATEGORY_COLORS[this.selectedCategory]
            || SKILL_CATEGORY_COLORS[this.selectedCategory]
            || '#9CA3AF';
        return `background-color: ${color}; color: #ffffff; border-color: ${color};`;
    }

    get isAllMode() {
        return this.viewContentMode === 'all';
    }

    get isSkillsMode() {
        return this.viewContentMode === 'skills';
    }

    get isItemsMode() {
        return this.viewContentMode === 'items';
    }

    get itemsToggleClass() {
        return this.isItemsMode ? 'filter-chip mode-chip active' : 'filter-chip mode-chip';
    }

    get skillsToggleClass() {
        return this.isSkillsMode ? 'filter-chip mode-chip active' : 'filter-chip mode-chip';
    }

    get showSettlingInBanner() {
        return this.isSettlingIn && this.isItemsMode;
    }

    get emptyStateTitle() {
        if (this.isSkillsMode) return 'No skills listed yet';
        if (this.isAllMode) return 'The library is quiet';
        return 'The shelves are bare!';
    }

    get emptyStateMessage() {
        if (this.isSkillsMode) {
            return 'Be the first to offer a skill your neighbours can count on.';
        }
        if (this.isAllMode) {
            return 'Items and skills from your neighbours will show up here.';
        }
        return 'Got something to lend? Your neighbours are waiting.';
    }

    get emptyActionLabel() {
        if (this.isSkillsMode) return 'Offer a Skill';
        if (this.isAllMode) return 'Add to Library';
        return 'Add Item';
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
        this.showDropdown = false;
        if (this.viewContentMode !== 'all') {
            this.viewContentMode = 'all';
            this.selectedCategory = '';
            this.filterAutoLoadCount = 0;
            this._clearLibraryCache();
            this.loadCategories();
            this.loadInitialData();
            return;
        }
        if (this.selectedCategory) {
            this.selectedCategory = '';
            this.filterAutoLoadCount = 0;
            this._clearLibraryCache();
            this.applyFilter();
        }
    }

    handleClearCategory(event) {
        event.stopPropagation();
        this.selectedCategory = '';
        this.filterAutoLoadCount = 0;
        this.showDropdown = false;
        this._clearLibraryCache();
        this.applyFilter();
    }

    handleToggleDropdown() {
        if (!this.showCategoryFilter) return;
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
        try { localStorage.setItem('fimby-library-view', this.viewMode); } catch { /* ignore */ }
    }

    _restoreViewPreference() {
        try {
            if (typeof window !== 'undefined' && window.innerWidth < 768) {
                this.viewMode = 'grid';
                return;
            }
            const saved = localStorage.getItem('fimby-library-view');
            if (saved === 'grid' || saved === 'list') this.viewMode = saved;
        } catch { /* ignore */ }
    }

    // =============================================
    // HANDLERS – feed interactions
    // =============================================

    handleAvatarNavigation(event) {
        event.stopPropagation();
        const url = event.detail?.url;
        if (url) navigate(this, url);
    }

    handleCardClick(event) {
        const wrapper = event.currentTarget.closest('[data-record-id]');
        const itemId = wrapper?.dataset?.recordId;
        if (!itemId) return;
        this._navigateToItemDetail(itemId);
    }

    _navigateToItemDetail(itemId) {
        const item = this.allItems.find(i => i.id === itemId)
            || this.filteredItems.find(i => i.id === itemId);
        if (item?.isSkill) {
            this._navigateToRecord('Skill_Offer__c', itemId);
        } else {
            this._navigateToRecord('Library_Item__c', itemId);
        }
    }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    // Soft-nav to an object detail page (keeps the persistent shell mounted).
    _navigateToRecord(objectApiName, recordId) {
        const ref = getRecordPageReference(objectApiName, recordId);
        if (!ref) return;
        startNavTiming('detail');
        this[NavigationMixin.Navigate](ref);
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

        const item = this.allItems.find(i => i.id === itemId);
        if (!item) return;

        if (item.primaryAction === 'skillHelp') {
            const modal = this.template.querySelector('c-fimby-quick-response-modal');
            if (modal) modal.show(itemId, 'skill');
            return;
        }

        // Vouching gate: settling-in members cannot borrow.
        if (!(await this._ensureVouched())) {
            this._openVouchingRequiredModal();
            return;
        }

        if (item.primaryAction === 'borrow' || item.primaryAction === 'joinWaitlist') {
            const modal = this.template.querySelector('c-fimby-quick-response-modal');
            if (modal) modal.show(itemId, 'library');
        } else {
            this._navigateToRecord('Library_Item__c', itemId);
        }
    }

    async handleResponseSaved() {
        await this.loadInitialData();
    }

    handleAddItem() {
        if (this.isSkillsMode) {
            navigate(this, '/library-item-post?type=skill');
        } else {
            navigate(this, '/library-item-post');
        }
    }

    _switchContentMode(mode) {
        if (this.viewContentMode === mode) return;
        this.viewContentMode = mode;
        this.selectedCategory = '';
        this.showDropdown = false;
        this.filterAutoLoadCount = 0;
        this._clearLibraryCache();
        this.loadCategories();
        this.loadInitialData();
    }

    handleItemsMode() {
        this._switchContentMode('items');
    }

    handleSkillsMode() {
        this._switchContentMode('skills');
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
            fireToast({ message: 'We couldn’t load more items just now. Please try again.', variant: 'error' });
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
            const item = this.allItems.find(i => i.id === itemId);
            const contentType = item?.isSkill ? 'Skill_Offer' : 'Library_Item';
            modal.show(itemId, contentType);
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

            // eslint-disable-next-line @lwc/lwc/no-async-operation -- scroll/focus after render
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
                viewContentMode: this.viewContentMode,
                itemsOffset: this._itemsOffset,
                skillsOffset: this._skillsOffset,
                hasMoreContent: this.hasMoreContent,
                scrollY: window.scrollY,
                timestamp: Date.now()
            };
            sessionStorage.setItem(LIB_CACHE_KEY, JSON.stringify(state));
        } catch { /* storage unavailable or full */ }
    }

    _throttledSaveLibraryState() {
        if (this._saveThrottleTimer) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce / delayed UI
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
            this.viewContentMode = state.viewContentMode || 'all';
            this._itemsOffset = state.itemsOffset || 0;
            this._skillsOffset = state.skillsOffset || 0;
            this.hasMoreContent = state.hasMoreContent;
            this._applyCategoryFilter();
            this.loadCategories();

            this._pendingScrollY = state.scrollY || 0;
            this._restoredFromCache = true;
            return true;
        } catch {
            return false;
        }
    }

    _clearLibraryCache() {
        try { sessionStorage.removeItem(LIB_CACHE_KEY); } catch { /* ignore */ }
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
            // eslint-disable-next-line @lwc/lwc/no-async-operation -- scroll/focus after render
            requestAnimationFrame(() => {
                window.scrollTo(0, savedY);
                // Reveal only after scroll is positioned, so the jump is unseen.
                // eslint-disable-next-line @lwc/lwc/no-async-operation -- scroll/focus after render
                requestAnimationFrame(() => {
                    this._resumeHidden = false;
                });
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