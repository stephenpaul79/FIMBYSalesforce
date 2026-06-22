import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fireToast } from 'c/fimbyToastHelper';
import { completeImageUrl, avatarImageUrl } from 'c/fimbyImageUrl';
import search from '@salesforce/apex/FimbySearchController.search';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { decodeHtmlEntities } from 'c/fimbyTextUtils';
import { navigate, profilePathForContact } from 'c/fimbyNavigation';
import {
    getCategoryIconUrl as getSkillCategoryIconUrl,
    getCategoryStyle as getSkillCategoryStyle,
    getCategoryColor as getSkillCategoryColor
} from 'c/fimbySkillCategoryConfig';
import {
    getCategoryIconUrl as getLibraryCategoryIconUrl,
    getCategoryStyle as getLibraryCategoryStyle,
    getCategoryColor as getLibraryCategoryColor
} from 'c/fimbyLibraryCategoryConfig';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';

const SORT_OPTIONS = [
    { value: 'relevance', label: 'Relevance' },
    { value: 'newest', label: 'Newest First' },
    { value: 'oldest', label: 'Oldest First' }
];

const FILTER_ICONS = {
    all:      { active: 'NeighborhoodActive.png',    inactive: 'NeighborhoodInactive.png' },
    stories:  { active: 'StoriesActive.png',          inactive: 'StoriesInactive.png' },
    askOffer: { active: 'BulletinBoardActive.png',    inactive: 'BulletinBoardInactive.png' },
    library:  { active: 'ToolboxActive.png',          inactive: 'ToolboxInactive.png' },
    skills:   { active: 'lightbulb.png',              inactive: 'lightbulb.png' },
    people:   { active: 'people.png',                 inactive: 'people.png' }
};

const BASE_FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'people', label: 'People' },
    { value: 'library', label: 'Library' },
    { value: 'skills', label: 'Skills' },
    { value: 'askOffer', label: 'Ask & Offer' },
    { value: 'stories', label: 'Shared Life' }
];

const STORY_TYPE_ICONS = {
    'Thank You':  'ThankYouActive.png',
    'God Story':  'GodStoryActive.png',
    'Prayer':     'PrayActive.png',
    'Lament':     'LamentActive.png',
    'Bio':        'BioActive.png',
    'Neighbourhood Moment': 'tulips.png'
};

const STORY_BADGE_STYLES = {
    'God Story': 'background-color: var(--fimby-badge-god-story); color: #ffffff;',
    'Thank You': 'background-color: var(--fimby-badge-thank-you); color: #ffffff;',
    'Lament': 'background-color: var(--fimby-badge-lament); color: #ffffff;',
    'Prayer': 'background-color: var(--fimby-badge-prayer); color: #ffffff;',
    'Bio': 'background-color: var(--fimby-badge-bio); color: #ffffff;',
    'Neighbourhood Moment': 'background-color: var(--fimby-badge-neighbourhood); color: #ffffff;'
};

const STORY_LABEL_MAP = {
    'Neighbourhood Moment': 'Neighbourhood'
};

const ASK_OFFER_TYPE_ICONS = {
    'Need':  'needsm.png',
    'Offer': 'giftsm.png'
};

const SYSTEM_PROFILE_EGG_TERMS = new Set(['knock', 'knock knock', 'fimby']);
const SYSTEM_PROFILE_EGG_ID = '__fimby_system_profile__';
const SYSTEM_PROFILE_PATH = '/system-profile';

export default class FimbySearch extends NavigationMixin(LightningElement) {
    @track searchTerm = '';
    @track selectedFilter = 'all';
    @track sortBy = 'relevance';
    @track searchResults = [];
    @track recentSearches = [];
    @track isSearching = false;
    @track resultsCount = 0;
    @track hasMore = false;
    @track countsByType = {};
    @track showSortDropdown = false;

    currentOffset = 0;
    pageSize = 20;
    _searchTimeout;
    currentContactId = null;

    get searchHintIconUrl()    { return `${IMPACT_ICONS}/Magnify.png`; }
    get noResultsIconUrl()     { return `${IMPACT_ICONS}/Magnify.png`; }
    get noProfilePhotoUrl()    { return `${IMPACT_ICONS}/NoProfilePhoto.png`; }
    get greenCircleUrl()       { return `${IMPACT_ICONS}/GreenCircle.png`; }

    get searchFilters() {
        return BASE_FILTERS.map(filter => {
            const count = this._getCountForFilter(filter.value);
            const hasCount = count !== null && count !== undefined && this.searchTerm.length > 2;
            const isActive = filter.value === this.selectedFilter;
            const icons = FILTER_ICONS[filter.value];
            const iconFile = isActive ? icons.active : icons.inactive;
            return {
                ...filter,
                iconUrl: `${IMPACT_ICONS}/${iconFile}`,
                countLabel: hasCount ? ` (${count})` : '',
                cssClass: isActive ? 'filter-button active' : 'filter-button'
            };
        });
    }

    get sortOptions() {
        return SORT_OPTIONS;
    }

    get currentSortLabel() {
        const opt = SORT_OPTIONS.find(o => o.value === this.sortBy);
        return opt ? opt.label : 'Relevance';
    }

    get showRecentSearches() {
        return !this.searchTerm && this.recentSearches.length > 0 && !this.showResults;
    }

    get showSearchHint() {
        return !this.searchTerm && !this.showResults && this.recentSearches.length === 0;
    }

    get showResults() {
        return this.searchResults.length > 0 && !this.isSearching;
    }

    get showNoResults() {
        return this.searchTerm.length > 2 && !this.isSearching && this.searchResults.length === 0 && this._hasSearched;
    }

    _hasSearched = false;

    async connectedCallback() {
        this.loadRecentSearches();
        this._applyUrlState();
        try {
            const identity = await getActingAsContact();
            this.currentContactId = identity?.contactId || identity?.actingAsContactId || null;
        } catch {
            this.currentContactId = null;
        }
    }

    // ========================================================
    // URL state management
    // ========================================================

    _applyUrlState() {
        try {
            const params = new URLSearchParams(window.location.search);
            const q = params.get('q');
            const f = params.get('filter');
            const s = params.get('sort');
            if (q) {
                this.searchTerm = q;
            }
            if (f && BASE_FILTERS.some(bf => bf.value === f)) {
                this.selectedFilter = f;
            }
            if (s && SORT_OPTIONS.some(so => so.value === s)) {
                this.sortBy = s;
            }
            if (this.searchTerm.length > 2) {
                this.performSearch();
            }
        } catch {
            // fail silently
        }
    }

    // ========================================================
    // Search input handlers
    // ========================================================

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        if (this.searchTerm.length > 2) {
            this.debounceSearch();
        } else {
            this.searchResults = [];
            this.resultsCount = 0;
            this.countsByType = {};
            this._hasSearched = false;
        }
    }

    handleFilterSelect(event) {
        const filter = event.currentTarget.dataset.filter;
        this.selectedFilter = filter;
        this.currentOffset = 0;
        this.searchResults = [];
        if (this.searchTerm.length > 2) {
            this.performSearch();
        }
    }

    handleSearchSubmit() {
        if (this.searchTerm.length > 2) {
            this.currentOffset = 0;
            this.searchResults = [];
            this.performSearch();
        }
    }

    // ========================================================
    // Sort handlers
    // ========================================================

    handleSortToggle() {
        this.showSortDropdown = !this.showSortDropdown;
    }

    handleSortSelect(event) {
        const value = event.currentTarget.dataset.value;
        if (value !== this.sortBy) {
            this.sortBy = value;
            this.currentOffset = 0;
            this.searchResults = [];
            this.performSearch();
        }
        this.showSortDropdown = false;
    }

    handleSortBackdropClick() {
        this.showSortDropdown = false;
    }

    // ========================================================
    // Recent searches
    // ========================================================

    handleRecentClick(event) {
        const term = event.currentTarget.dataset.term;
        this.searchTerm = term;
        const input = this.template.querySelector('lightning-input');
        if (input) input.value = term;
        this.performSearch();
    }

    handleRecentKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleRecentClick(event);
        }
    }

    handleClearRecent() {
        this.recentSearches = [];
        localStorage.removeItem('fimby_recent_searches');
    }

    handleRemoveRecent(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.recentSearches = this.recentSearches.filter(s => s.id !== id);
        this.saveRecentSearches();
    }

    // ========================================================
    // Search execution
    // ========================================================

    debounceSearch() {
        clearTimeout(this._searchTimeout);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimeout = setTimeout(() => {
            this.currentOffset = 0;
            this.searchResults = [];
            this.performSearch();
        }, 300);
    }

    async performSearch(loadMore = false) {
        if (this.searchTerm.length < 3) return;

        this.isSearching = true;

        try {
            const result = await search({
                searchTerm: this.searchTerm,
                filterType: this.selectedFilter,
                sortBy: this.sortBy,
                pageSize: this.pageSize,
                offset: this.currentOffset
            });

            if (result) {
                const processed = this.processResults(result.items || []);

                if (loadMore) {
                    this.searchResults = [...this.searchResults, ...processed];
                } else {
                    this.searchResults = this._prependSystemProfileEgg(processed);
                    this.addToRecentSearches(this.searchTerm, this.selectedFilter);
                }

                this.resultsCount = result.totalCount || 0;
                this.hasMore = result.hasMore || false;
                this.countsByType = result.countsByType || {};
                this.currentOffset += (result.items || []).length;
            }

            this._hasSearched = true;
        } catch (error) {
            console.error('Search error:', error);
            fireToast({ message: 'Something went wrong with your search. Please try again.', variant: 'error' });
        } finally {
            this.isSearching = false;
        }
    }

    handleLoadMoreResults() {
        if (this.hasMore && !this.isSearching) {
            this.performSearch(true);
        }
    }

    // ========================================================
    // Result processing
    // ========================================================

    processResults(items) {
        return items.map(item => {
            const badge = this._buildBadge(item);
            const cardMeta = this._buildCardMeta(item);
            const imageUrl = completeImageUrl(item.imageUrl);
            const hasImage = !!imageUrl && imageUrl.trim() !== '';
            const isPeople = item.resultType === 'people';

            return {
                ...item,
                isPeople,
                showContactBadge: isPeople,
                processedImageUrl: imageUrl,
                processedAvatarUrl: avatarImageUrl(item.postedByImageUrl),
                shortDescription: this.truncate(item.description, 120),
                formattedDate: this.formatRelativeDate(item.createdDate),
                badgeLabel: badge.label,
                badgeIconUrl: badge.iconUrl,
                badgeStyle: badge.badgeStyle || '',
                cardType: cardMeta.cardType,
                accentColor: cardMeta.accentColor,
                images: hasImage
                    ? [{ url: imageUrl, ratio: item.imageRatio || '', alt: item.name || '' }]
                    : [],
                peopleAriaLabel: isPeople ? `View profile for ${item.name}` : 'View result'
            };
        });
    }

    _buildCardMeta(item) {
        if (item.resultType === 'story') {
            return { cardType: 'story', accentColor: '' };
        }
        if (item.resultType === 'askOffer') {
            return { cardType: 'askOffer', accentColor: '' };
        }
        if (item.resultType === 'library') {
            const category = item.subType || 'Other';
            return { cardType: 'library', accentColor: getLibraryCategoryColor(category) };
        }
        if (item.resultType === 'skill') {
            const category = item.subType || 'Other / General Help';
            return { cardType: 'library', accentColor: getSkillCategoryColor(category) };
        }
        return { cardType: 'default', accentColor: '' };
    }

    _buildBadge(item) {
        if (item.resultType === 'story') {
            const storyType = item.subType || 'Shared Life';
            const iconFile = STORY_TYPE_ICONS[storyType] || 'StoriesActive.png';
            const label = STORY_LABEL_MAP[storyType] || storyType;
            return {
                label,
                iconUrl: `${IMPACT_ICONS}/${iconFile}`,
                badgeStyle: STORY_BADGE_STYLES[storyType] || 'background-color: var(--fimby-badge-story); color: #ffffff;'
            };
        }

        if (item.resultType === 'askOffer') {
            const aoType = item.subType || 'Ask & Offer';
            if (aoType === 'Event' || aoType === 'Services') {
                return {
                    label: aoType,
                    iconUrl: `${IMPACT_ICONS}/plannersm.png`,
                    badgeStyle: 'background-color: var(--fimby-badge-event); color: #ffffff;'
                };
            }
            const iconFile = ASK_OFFER_TYPE_ICONS[aoType] || 'BulletinBoardActive.png';
            return {
                label: aoType,
                iconUrl: `${IMPACT_ICONS}/${iconFile}`,
                badgeStyle: 'background-color: var(--fimby-badge-ask-offer); color: #ffffff;'
            };
        }

        if (item.resultType === 'library') {
            const category = item.subType || 'Other';
            return {
                label: category,
                iconUrl: getLibraryCategoryIconUrl(IMPACT_ICONS, category),
                badgeStyle: getLibraryCategoryStyle(category)
            };
        }

        if (item.resultType === 'skill') {
            const category = item.subType || 'Other / General Help';
            return {
                label: category,
                iconUrl: getSkillCategoryIconUrl(IMPACT_ICONS, category),
                badgeStyle: getSkillCategoryStyle(category)
            };
        }

        return { label: '', iconUrl: '', badgeStyle: '' };
    }

    _shouldShowSystemProfileEgg() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!SYSTEM_PROFILE_EGG_TERMS.has(term)) {
            return false;
        }
        return this.selectedFilter === 'all' || this.selectedFilter === 'people';
    }

    _buildSystemProfileEggRow() {
        const description = 'Up in the bamboo, passing notes between neighbours.';
        return {
            recordId: SYSTEM_PROFILE_EGG_ID,
            resultType: 'systemProfile',
            name: 'FIMBY',
            subType: 'The Cloud',
            description,
            isPeople: true,
            isSystemProfileEgg: true,
            showContactBadge: false,
            processedImageUrl: `${IMPACT_ICONS}/systempanda.png`,
            processedAvatarUrl: '',
            shortDescription: description,
            formattedDate: '',
            badgeLabel: '',
            badgeIconUrl: '',
            badgeStyle: '',
            cardType: 'default',
            accentColor: '',
            images: [],
            peopleAriaLabel: 'View FIMBY profile'
        };
    }

    _prependSystemProfileEgg(items) {
        if (!this._shouldShowSystemProfileEgg()) {
            return items;
        }
        return [this._buildSystemProfileEggRow(), ...items];
    }

    // ========================================================
    // Navigation
    // ========================================================

    handleResultClick(event) {
        const host = event.currentTarget.closest('[data-record-id]');
        if (!host) return;
        const recordId = host.dataset.recordId;
        const resultType = host.dataset.resultType;
        this.navigateToResult(recordId, resultType);
    }

    handleResultKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleResultClick(event);
        }
    }

    navigateToResult(recordId, resultType) {
        if (resultType === 'systemProfile') {
            navigate(this, SYSTEM_PROFILE_PATH);
            return;
        }

        if (resultType === 'people') {
            const item = this.searchResults.find(r => r.recordId === recordId);
            const path = profilePathForContact({
                contactId: recordId,
                isOrgContact: item?.isOrgContact === true,
                orgAccountId: item?.orgAccountId,
                currentContactId: this.currentContactId
            });
            if (path) {
                navigate(this, path);
            }
            return;
        }

        const routes = {
            'story': `/sharedlife/${recordId}`,
            'askOffer': `/asks-offers/${recordId}`,
            'library': `/library-item/${recordId}`,
            'skill': `/skill-offer/${recordId}`
        };

        const route = routes[resultType];
        if (route) {
            navigate(this, route);
        }
    }

    // ========================================================
    // Formatting helpers
    // ========================================================

    truncate(text, maxLength) {
        if (!text) return '';
        const stripped = text.replace(/<[^>]*>/g, '');
        const decoded = decodeHtmlEntities(stripped);
        if (decoded.length <= maxLength) return decoded;
        return decoded.substring(0, maxLength) + '...';
    }

    formatRelativeDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        const diffHrs = Math.floor(diffMs / 3600000);
        const diffDays = Math.floor(diffMs / 86400000);

        if (diffMins < 1) return 'Just now';
        if (diffMins < 60) return `${diffMins}m ago`;
        if (diffHrs < 24) return `${diffHrs}h ago`;
        if (diffDays < 7) return `${diffDays}d ago`;
        return date.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' });
    }

    _getCountForFilter(filterValue) {
        if (!this.countsByType) return null;
        const map = {
            'all': null,
            'stories': this.countsByType.stories,
            'askOffer': this.countsByType.askOffer,
            'library': this.countsByType.library,
            'skills': this.countsByType.skills,
            'people': this.countsByType.people
        };
        return map[filterValue];
    }

    // ========================================================
    // Recent searches (localStorage)
    // ========================================================

    addToRecentSearches(term, type) {
        const newSearch = {
            id: Date.now().toString(),
            term: term,
            type: type,
            timestamp: new Date()
        };
        this.recentSearches = this.recentSearches.filter(s => s.term !== term);
        this.recentSearches.unshift(newSearch);
        this.recentSearches = this.recentSearches.slice(0, 10);
        this.saveRecentSearches();
    }

    loadRecentSearches() {
        try {
            const saved = localStorage.getItem('fimby_recent_searches');
            if (saved) {
                this.recentSearches = JSON.parse(saved);
            }
        } catch {
            this.recentSearches = [];
        }
    }

    saveRecentSearches() {
        try {
            localStorage.setItem('fimby_recent_searches', JSON.stringify(this.recentSearches));
        } catch {
            // storage full or unavailable
        }
    }

}