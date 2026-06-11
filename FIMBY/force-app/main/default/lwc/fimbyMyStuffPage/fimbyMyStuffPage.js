import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getMyPosts from '@salesforce/apex/FimbyMyStuffController.getMyPosts';
import getMyStories from '@salesforce/apex/FimbyMyStuffController.getMyStories';
import getMyLibraryItems from '@salesforce/apex/FimbyMyStuffController.getMyLibraryItems';
import getMySkills from '@salesforce/apex/FimbyMyStuffController.getMySkills';
import getMyBorrowedItems from '@salesforce/apex/FimbyMyStuffController.getMyBorrowedItems';
import getMyContacts from '@salesforce/apex/FimbyMyStuffController.getMyContacts';
import searchNeighbourhoodContacts from '@salesforce/apex/FimbyMyStuffController.searchNeighbourhoodContacts';
import getMyContactDetailsForSharing from '@salesforce/apex/FimbyMyStuffController.getMyContactDetailsForSharing';
import shareContactInfoDirect from '@salesforce/apex/FimbyMyStuffController.shareContactInfoDirect';
import revokeSharedContactInfo from '@salesforce/apex/FimbyMyStuffController.revokeSharedContactInfo';
import undoRevokeSharedContactInfo from '@salesforce/apex/FimbyMyStuffController.undoRevokeSharedContactInfo';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getCategoryIconUrl, getCategoryStyle } from 'c/fimbyLibraryCategoryConfig';
import { getCategoryIconUrl as getSkillCategoryIconUrl, getCategoryStyle as getSkillCategoryStyle } from 'c/fimbySkillCategoryConfig';

const PATH_TO_SECTION = {
    'my-contacts': 'contacts',
    'my-posts': 'posts',
    'my-shared-life': 'stories',
    'my-library-items': 'library',
    'my-skills': 'skills',
    'my-borrowing': 'borrowed'
};

const SECTION_TITLES = {
    contacts: 'My Neighbours',
    posts: 'My Posts',
    stories: 'My Shared Life',
    library: 'My Library Items',
    skills: 'My Skills',
    borrowed: 'My Borrowing'
};

const STORY_TYPE_CLASSES = {
    'Thank You': 'type-badge thankyou-type',
    'God Story': 'type-badge godstory-type',
    'Prayer':    'type-badge prayer-type',
    'Lament':    'type-badge lament-type',
    'Bio':       'type-badge bio-type',
    'Neighbourhood Moment': 'type-badge neighbourhood-type'
};

const STORY_ICON_MAP = {
    'Thank You': 'ThankYouActive.png',
    'God Story': 'GodStoryActive.png',
    'Prayer':    'PrayActive.png',
    'Lament':    'LamentActive.png',
    'Bio':       'BioActive.png',
    'Neighbourhood Moment': 'tulips.png'
};

const STORY_DISPLAY_NAMES = {
    'Neighbourhood Moment': 'Neighbourhood'
};

const POST_ICON_MAP = {
    'Need':     'BulletinBoardActive.png',
    'Offer':    'BulletinBoardActive.png',
    'Bulk_Buy': 'bulkbuy.png'
};

const EVENT_ICON_MAP = {
    'Community_Event': 'cityscape.png',
    'Open_Event':      'people.png',
    'Gathering':       'dining-table.png'
};

const POST_STATUS_CLASSES = {
    'Posted':          'status-badge status-active',
    'Reply Received':  'status-badge status-replied',
    'Reply Accepted':  'status-badge status-accepted',
    'Completed':       'status-badge status-completed',
    'Expired':         'status-badge status-expired'
};

const LIBRARY_STATUS_CLASSES = {
    'Available':    'status-badge status-available',
    'On Loan':      'status-badge status-on-loan',
    'Unavailable':  'status-badge status-unavailable'
};

const SKILL_STATUS_CLASSES = {
    'Active':  'status-badge status-available',
    'Paused':  'status-badge status-unavailable',
    'Removed': 'status-badge status-expired'
};

export default class FimbyMyStuffPage extends LightningElement {
    @track activeFilter = null;
    @track isLoading = true;

    // Data
    @track myPosts = [];
    @track myStories = [];
    @track myLibraryItems = [];
    @track mySkills = [];
    @track myBorrowedItems = [];
    @track myContacts = [];
    @track expandedContactId = null;
    @track contactSearchTerm = '';
    @track activeContactsSubFilter = 'received';

    // Share Contact modal state
    @track showShareModal = false;
    @track shareSearchTerm = '';
    @track shareSearchResults = [];
    @track shareSearching = false;
    @track selectedRecipientId = null;
    @track selectedRecipientName = '';
    @track shareEmail = false;
    @track sharePhone = false;
    @track shareAddress = false;
    @track shareEmailValue = '';
    @track sharePhoneValue = '';
    @track shareStreetValue = '';
    @track shareCityValue = '';
    @track shareStateValue = '';
    @track sharePostalCodeValue = '';
    @track shareCountryValue = '';
    @track shareAdditionalInfoValue = '';
    @track shareSubmitting = false;
    @track shareModalEditMode = false;

    _shareSearchTimeout;

    // Data loaded flags
    _postsLoaded = false;
    _storiesLoaded = false;
    _libraryLoaded = false;
    _skillsLoaded = false;
    _borrowedLoaded = false;
    _contactsLoaded = false;

    /* ===============================================================
     * Lifecycle
     * =============================================================== */
    async connectedCallback() {
        this.activeFilter = this._parseSectionFromPath();
        if (!this.activeFilter) {
            location.href = '/my-stuff';
            return;
        }
        this.isLoading = true;
        try {
            await this._loadActiveSection();
        } catch (error) {
            console.error('Error initializing My Stuff section:', error);
        } finally {
            this.isLoading = false;
        }
    }

    _parseSectionFromPath() {
        const path = window.location.pathname || '';
        const segments = path.split('/').filter(s => s && s !== 's');
        for (const seg of segments) {
            if (PATH_TO_SECTION[seg]) return PATH_TO_SECTION[seg];
        }
        return null;
    }

    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get shareIconUrl() { return `${IMPACT_ICONS}/sign.png`; }
    get archiveIconUrl() { return `${IMPACT_ICONS}/box.png`; }


    get sectionTitle() {
        return this.activeFilter ? SECTION_TITLES[this.activeFilter] : '';
    }

    get headerCardClass() {
        return this.activeFilter === 'contacts' ? 'header-card header-card-has-filters' : 'header-card';
    }

    /* ===============================================================
     * Data loaders
     * =============================================================== */
    async _loadActiveSection() {
        switch (this.activeFilter) {
            case 'contacts':
                await this._loadContacts();
                break;
            case 'posts':
                await this._loadPosts();
                break;
            case 'stories':
                await this._loadStories();
                break;
            case 'library':
                await this._loadLibraryItems();
                break;
            case 'skills':
                await this._loadSkills();
                break;
            case 'borrowed':
                await this._loadBorrowedItems();
                break;
            default:
                break;
        }
    }

    async _loadPosts() {
        if (this._postsLoaded) return;
        try {
            const posts = await getMyPosts({ pageSize: 20 });
            const activeStatuses = new Set(['Posted', 'Reply Received', 'Reply Accepted', 'Available', 'Shares Available', 'Pickup Ready']);
            this.myPosts = posts.map(p => {
                const rtName = p.RecordType?.Name;
                const evtType = p.Event_Type__c;
                let displayTypeName, typeBadgeClass, badgeIconFile;

                if (rtName === 'Need') {
                    displayTypeName = 'Ask';
                    typeBadgeClass = 'type-badge need-type';
                    badgeIconFile = POST_ICON_MAP['Need'];
                } else if (rtName === 'Bulk_Buy' || rtName === 'Bulk Buy') {
                    displayTypeName = 'Bulk Buy';
                    typeBadgeClass = 'type-badge bulkbuy-type';
                    badgeIconFile = POST_ICON_MAP['Bulk_Buy'];
                } else if (rtName === 'Event' || p.Type__c === 'Event') {
                    if (evtType === 'Community_Event') {
                        displayTypeName = 'Community Event';
                        typeBadgeClass = 'type-badge community-event-type';
                    } else {
                        displayTypeName = 'Event';
                        typeBadgeClass = 'type-badge event-type';
                    }
                    badgeIconFile = EVENT_ICON_MAP[evtType] || 'dining-table.png';
                } else {
                    displayTypeName = rtName || 'Offer';
                    typeBadgeClass = 'type-badge offer-type';
                    badgeIconFile = POST_ICON_MAP['Offer'];
                }

                return {
                    ...p,
                    displayTypeName,
                    typeBadgeClass,
                    badgeIconUrl: `${IMPACT_ICONS}/${badgeIconFile}`,
                    statusBadgeClass: POST_STATUS_CLASSES[p.Status__c] || 'status-badge',
                    formattedDate: this._formatDate(p.CreatedDate)
                };
            }).filter(p => activeStatuses.has(p.Status__c));
            this._postsLoaded = true;
        } catch (error) {
            console.error('Error loading posts:', error);
        }
    }

    async _loadStories() {
        if (this._storiesLoaded) return;
        try {
            const stories = await getMyStories({ pageSize: 10 });
            this.myStories = stories.map(s => ({
                ...s,
                typeBadgeClass: STORY_TYPE_CLASSES[s.Type__c] || 'type-badge',
                displayTypeName: STORY_DISPLAY_NAMES[s.Type__c] || s.Type__c,
                badgeIconUrl: STORY_ICON_MAP[s.Type__c] ? `${IMPACT_ICONS}/${STORY_ICON_MAP[s.Type__c]}` : null,
                formattedDate: this._formatDate(s.CreatedDate)
            }));
            this._storiesLoaded = true;
        } catch (error) {
            console.error('Error loading stories:', error);
        }
    }

    async _loadLibraryItems() {
        if (this._libraryLoaded) return;
        try {
            const items = await getMyLibraryItems({ pageSize: 20 });
            this.myLibraryItems = items.map(item => ({
                ...item,
                statusBadgeClass: LIBRARY_STATUS_CLASSES[item.status] || 'status-badge',
                loanInfo: item.loanedToName ? `Borrowed by ${item.loanedToName}` : null,
                categoryIconUrl: getCategoryIconUrl(IMPACT_ICONS, item.category || 'Other'),
                categoryBadgeStyle: getCategoryStyle(item.category || 'Other')
            }));
            this._libraryLoaded = true;
        } catch (error) {
            console.error('Error loading library items:', error);
        }
    }

    async _loadSkills() {
        if (this._skillsLoaded) return;
        try {
            const skills = await getMySkills({ pageSize: 20 });
            this.mySkills = skills.map(skill => ({
                ...skill,
                statusBadgeClass: SKILL_STATUS_CLASSES[skill.status] || 'status-badge',
                categoryIconUrl: getSkillCategoryIconUrl(IMPACT_ICONS, skill.category || 'Other / General Help'),
                categoryBadgeStyle: getSkillCategoryStyle(skill.category || 'Other / General Help'),
                formattedDate: this._formatDate(skill.CreatedDate)
            }));
            this._skillsLoaded = true;
        } catch (error) {
            console.error('Error loading skills:', error);
        }
    }

    async _loadBorrowedItems() {
        if (this._borrowedLoaded) return;
        try {
            const items = await getMyBorrowedItems();
            this.myBorrowedItems = items.map(item => ({
                ...item,
                dueBadgeClass: this._getDueBadgeClass(item.dueDate),
                formattedDueDate: this._formatDate(item.dueDate),
                categoryIconUrl: getCategoryIconUrl(IMPACT_ICONS, item.category || 'Other'),
                categoryBadgeStyle: getCategoryStyle(item.category || 'Other')
            }));
            this._borrowedLoaded = true;
        } catch (error) {
            console.error('Error loading borrowed items:', error);
        }
    }

    async _loadContacts(searchTerm) {
        if (this._contactsLoaded && !searchTerm) return;
        try {
            const contacts = await getMyContacts({ searchTerm: searchTerm || null });
            this.myContacts = contacts.map(c => ({
                ...c,
                initials: this._getInitials(c.name),
                formattedDate: this._formatDate(c.connectedDate),
                isExpanded: c.contactId === this.expandedContactId,
                hasAddress: (c.street || c.city || c.provinceState),
                fullAddress: [c.street, c.city, c.provinceState, c.postalCode].filter(Boolean).join(', ')
            }));
            if (!searchTerm) this._contactsLoaded = true;
        } catch (error) {
            console.error('Error loading contacts:', error);
        }
    }

    _getInitials(name) {
        if (!name) return '?';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    handleContactsSubFilter(event) {
        const filter = event.currentTarget.dataset.filter;
        if (filter === 'received' || filter === 'shared' || filter === 'revoked') {
            this.activeContactsSubFilter = filter;
            this.expandedContactId = null;
            this.myContacts = this.myContacts.map(c => ({
                ...c,
                isExpanded: false
            }));
        }
    }

    get receivedFilterClass() {
        return this.activeContactsSubFilter === 'received' ? 'filter-button sub-filter active' : 'filter-button sub-filter';
    }
    get sharedFilterClass() {
        return this.activeContactsSubFilter === 'shared' ? 'filter-button sub-filter active' : 'filter-button sub-filter';
    }
    get revokedFilterClass() {
        return this.activeContactsSubFilter === 'revoked' ? 'filter-button sub-filter active' : 'filter-button sub-filter';
    }

    get showPosts()    { return this.activeFilter === 'posts'; }
    get showStories()  { return this.activeFilter === 'stories'; }
    get showLibrary()  { return this.activeFilter === 'library'; }
    get showSkills()   { return this.activeFilter === 'skills'; }
    get showBorrowed() { return this.activeFilter === 'borrowed'; }
    get showContacts() { return this.activeFilter === 'contacts'; }

    get hasPosts()         { return this.myPosts.length > 0; }
    get hasStories()       { return this.myStories.length > 0; }
    get hasLibraryItems()  { return this.myLibraryItems.length > 0; }
    get hasSkills()        { return this.mySkills.length > 0; }
    get hasBorrowedItems() { return this.myBorrowedItems.length > 0; }
    get loanedItems() {
        return this.myLibraryItems.filter(item => item.loanInfo);
    }
    get availableItems() {
        return this.myLibraryItems.filter(item => !item.loanInfo && item.status === 'Available');
    }
    get hasLoanedItems() {
        return this.loanedItems.length > 0;
    }
    get hasAvailableItems() {
        return this.availableItems.length > 0;
    }
    get filteredContacts() {
        if (this.activeFilter !== 'contacts') return [];
        const sub = this.activeContactsSubFilter;
        let filtered;
        if (sub === 'received') {
            filtered = this.myContacts.filter(c => c.theySharedWithMe);
        } else if (sub === 'shared') {
            filtered = this.myContacts.filter(c => c.iSharedWithThem && !c.isRevoked);
        } else {
            filtered = this.myContacts.filter(c => c.isRevoked === true);
        }
        return filtered.map(c => ({
            ...c,
            isNotRevoked: !c.isRevoked,
            showReciprocatePill: sub === 'received',
            showReciprocatedLabel: sub === 'received' && c.iSharedWithThem && !c.isRevoked,
            showReciprocateAction: sub === 'received' && (!c.iSharedWithThem || c.isRevoked),
            iSharedWithThemFalse: !c.iSharedWithThem,
            showRevokeBtn: sub === 'shared' && c.iSharedWithThem && !c.isRevoked,
            showUndoRevokeBtn: sub === 'revoked' && c.isRevoked,
            showEditBtn: c.iSharedWithThem && !c.isRevoked,
            chevronIcon: c.isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            cardClass: 'contact-card-wrapper' + (c.isExpanded ? ' contact-card-expanded' : '')
        }));
    }
    get hasContacts()      { return this.filteredContacts.length > 0; }

    get contactsEmptyMessage() {
        switch (this.activeContactsSubFilter) {
            case 'received': return 'No one has shared their contact info with you yet.';
            case 'shared': return 'You haven\'t shared your contact info with anyone yet.';
            case 'revoked': return 'You haven\'t revoked sharing with anyone.';
            default: return 'No shared contacts yet.';
        }
    }

    get shareModalTitle()  { return this.shareModalEditMode ? 'Update Shared Info' : 'Share Contact Info'; }

    get showManageAllLink() {
        return this.myLibraryItems.length > 10;
    }

    /* ===============================================================
     * Navigation handlers
     * =============================================================== */
    handlePostClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (recordId) location.href = `/asks-offers/${recordId}`;
    }

    handleStoryClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (recordId) location.href = `/story/${recordId}`;
    }

    handleLibraryItemClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (recordId) location.href = `/library-item/${recordId}`;
    }

    handleSkillClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (recordId) location.href = `/skill-offer/${recordId}`;
    }

    handleBorrowedItemClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (recordId) location.href = `/library-item/${recordId}`;
    }

    /* ===============================================================
     * Contact handlers
     * =============================================================== */
    handleContactClick(event) {
        const contactId = event.currentTarget.dataset.contactId;
        if (this.expandedContactId === contactId) {
            this.expandedContactId = null;
        } else {
            this.expandedContactId = contactId;
        }
        // Refresh expanded state on all contacts
        this.myContacts = this.myContacts.map(c => ({
            ...c,
            isExpanded: c.contactId === this.expandedContactId
        }));
    }

    async handleContactSearch(event) {
        this.contactSearchTerm = event.target.value;
        // Debounce
        clearTimeout(this._contactSearchTimeout);
        this._contactSearchTimeout = setTimeout(async () => {
            this._contactsLoaded = false;
            await this._loadContacts(this.contactSearchTerm);
        }, 300);
    }

    handleViewNeighbourProfile(event) {
        event.stopPropagation();
        const contactId = event.currentTarget.dataset.contactId;
        if (contactId) {
            location.href = '/neighbour?id=' + contactId;
        }
    }

    handleMessageContact(event) {
        event.stopPropagation();
        const contactId = event.currentTarget.dataset.contactId;
        if (!contactId) return;
        location.href = '/conversation?contactId=' + contactId;
    }

    handleEditSharedInfo(event) {
        event.stopPropagation();
        const contactId = event.currentTarget.dataset.contactId;
        const contactName = event.currentTarget.dataset.contactName;
        const contact = this.myContacts.find(c => c.contactId === contactId);
        if (!contact) return;

        this._shareModalTrigger = event.currentTarget || this.template.activeElement || document.activeElement;
        this.shareModalEditMode = true;
        this.selectedRecipientId = contactId;
        this.selectedRecipientName = contactName;
        this.shareEmailValue = contact.mySharedEmail ?? '';
        this.sharePhoneValue = contact.mySharedPhone ?? '';
        this.shareStreetValue = contact.mySharedStreet ?? '';
        this.shareCityValue = contact.mySharedCity ?? '';
        this.shareStateValue = contact.mySharedProvinceState ?? '';
        this.sharePostalCodeValue = contact.mySharedPostalCode ?? '';
        this.shareCountryValue = contact.mySharedCountry ?? '';
        this.shareAdditionalInfoValue = contact.mySharedAdditionalInfo ?? '';
        this.shareEmail = !!contact.mySharedEmail;
        this.sharePhone = !!contact.mySharedPhone;
        this.shareAddress = !!(
            contact.mySharedStreet || contact.mySharedCity || contact.mySharedProvinceState
            || contact.mySharedPostalCode || contact.mySharedCountry
        );
        this.showShareModal = true;
    }

    /* ===============================================================
     * Share Contact Modal handlers
     * =============================================================== */
    _shareModalTrigger = null;

    async handleOpenShareModal() {
        this._shareModalTrigger = this.template.activeElement || document.activeElement;
        this.showShareModal = true;
        this._resetShareModal();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const closeBtn = this.template.querySelector('.share-contact-modal .slds-modal__close');
            if (closeBtn) closeBtn.focus();
        }, 50);
        try {
            const details = await getMyContactDetailsForSharing();
            this.shareEmailValue = details.email || '';
            this.sharePhoneValue = details.phone || '';
            this.shareStreetValue = details.street || '';
            this.shareCityValue = details.city || '';
            this.shareStateValue = details.state || '';
            this.sharePostalCodeValue = details.postalCode || '';
            this.shareCountryValue = details.country || '';
            this.shareEmail = !!details.email;
            this.sharePhone = !!details.phone;
            this.shareAddress = !!(details.street || details.city || details.state || details.postalCode || details.country);
        } catch (e) {
            console.error('Error loading contact details:', e);
        }
    }

    handleCloseShareModal() {
        this.showShareModal = false;
        this._resetShareModal();
        this._contactsLoaded = false;
        this._loadContacts();
        if (this._shareModalTrigger && typeof this._shareModalTrigger.focus === 'function') {
            this._shareModalTrigger.focus();
        }
        this._shareModalTrigger = null;
    }

    _resetShareModal() {
        this.shareModalEditMode = false;
        this.shareSearchTerm = '';
        this.shareSearchResults = [];
        this.shareSearching = false;
        this.selectedRecipientId = null;
        this.selectedRecipientName = '';
        this.shareEmail = false;
        this.sharePhone = false;
        this.shareAddress = false;
        this.shareAdditionalInfoValue = '';
        this.shareSubmitting = false;
    }

    handleShareSearch(event) {
        this.shareSearchTerm = event.target.value;
        clearTimeout(this._shareSearchTimeout);
        this._shareSearchTimeout = setTimeout(() => this._doShareSearch(), 350);
    }

    async _doShareSearch() {
        const term = (this.shareSearchTerm || '').trim();
        if (term.length < 2) {
            this.shareSearchResults = [];
            return;
        }
        this.shareSearching = true;
        try {
            const results = await searchNeighbourhoodContacts({ searchTerm: term });
            this.shareSearchResults = (results || []).map(r => ({
                contactId: r.contactId,
                contactName: r.contactName,
                email: r.email,
                resultClass: r.contactId === this.selectedRecipientId
                    ? 'share-result-item selected' : 'share-result-item'
            }));
        } catch (e) {
            console.error('Search error:', e);
            this.shareSearchResults = [];
        } finally {
            this.shareSearching = false;
        }
    }

    handleSelectRecipient(event) {
        const contactId = event.currentTarget.dataset.contactId;
        const contactName = event.currentTarget.dataset.contactName;
        this.selectedRecipientId = contactId;
        this.selectedRecipientName = contactName || '';
        this.shareSearchResults = this.shareSearchResults.map(r => ({
            ...r,
            resultClass: r.contactId === contactId ? 'share-result-item selected' : 'share-result-item'
        }));
    }

    handleDeselectRecipient() {
        this.selectedRecipientId = null;
        this.selectedRecipientName = '';
        this.shareSearchResults = [];
        this.shareSearchTerm = '';
    }

    async handleReciprocateShare(event) {
        event.stopPropagation();
        const contactId = event.currentTarget.dataset.contactId;
        const contactName = event.currentTarget.dataset.contactName;
        this._shareModalTrigger = event.currentTarget || this.template.activeElement || document.activeElement;
        this.showShareModal = true;
        this._resetShareModal();
        this.selectedRecipientId = contactId;
        this.selectedRecipientName = contactName || '';
        try {
            const details = await getMyContactDetailsForSharing();
            this.shareEmailValue = details.email || '';
            this.sharePhoneValue = details.phone || '';
            this.shareStreetValue = details.street || '';
            this.shareCityValue = details.city || '';
            this.shareStateValue = details.state || '';
            this.sharePostalCodeValue = details.postalCode || '';
            this.shareCountryValue = details.country || '';
            this.shareEmail = !!details.email;
            this.sharePhone = !!details.phone;
            this.shareAddress = !!(details.street || details.city || details.state || details.postalCode || details.country);
        } catch (e) {
            console.error('Error loading contact details:', e);
        }
    }

    handleShareEmailChange(event) { this.shareEmail = event.target.checked; }
    handleSharePhoneChange(event) { this.sharePhone = event.target.checked; }
    handleShareAddressChange(event) { this.shareAddress = event.target.checked; }
    handleShareEmailValueChange(event) { this.shareEmailValue = event.target.value; }
    handleSharePhoneValueChange(event) { this.sharePhoneValue = event.target.value; }
    handleShareStreetChange(event) { this.shareStreetValue = event.target.value; }
    handleShareCityChange(event) { this.shareCityValue = event.target.value; }
    handleShareStateChange(event) { this.shareStateValue = event.target.value; }
    handleSharePostalCodeChange(event) { this.sharePostalCodeValue = event.target.value; }
    handleShareCountryChange(event) { this.shareCountryValue = event.target.value; }

    get shareRecipientSelected() {
        return !!this.selectedRecipientId;
    }

    get shareRecipientNotSelected() {
        return !this.selectedRecipientId;
    }

    get isNotShareModalEditMode() {
        return !this.shareModalEditMode;
    }

    get isShareValid() {
        if (!this.selectedRecipientId) return false;
        if (!this.shareEmail && !this.sharePhone && !this.shareAddress) return false;
        if (this.shareEmail && !this.shareEmailValue) return false;
        if (this.sharePhone && !this.sharePhoneValue) return false;
        return true;
    }

    get isShareSubmitDisabled() {
        return this.shareSubmitting || !this.isShareValid;
    }

    get shareSubmitLabel() {
        if (this.shareSubmitting) return this.shareModalEditMode ? 'Updating...' : 'Sharing...';
        return this.shareModalEditMode ? 'Update' : 'Share';
    }

    async handleShareSubmit() {
        if (!this.isShareValid || this.shareSubmitting) return;
        this.shareSubmitting = true;
        try {
            const shareData = {
                recipientContactId: this.selectedRecipientId,
                shareEmail: this.shareEmail,
                sharePhone: this.sharePhone,
                shareAddress: this.shareAddress,
                email: this.shareEmailValue,
                phone: this.sharePhoneValue,
                street: this.shareStreetValue,
                city: this.shareCityValue,
                state: this.shareStateValue,
                postalCode: this.sharePostalCodeValue,
                country: this.shareCountryValue,
                additionalInfo: this.shareAdditionalInfoValue || null
            };
            const result = await shareContactInfoDirect({ shareDataJson: JSON.stringify(shareData) });
            if (result && result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Shared',
                    message: result.message || 'Contact info shared successfully.',
                    variant: 'success'
                }));
                this.handleCloseShareModal();
            }
        } catch (error) {
            const msg = error.body?.message || error.message || 'Failed to share.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
        } finally {
            this.shareSubmitting = false;
        }
    }

    /* ===============================================================
     * Revoke / Undo Revoke handlers
     * =============================================================== */
    async handleRevokeSharedInfo(event) {
        event.stopPropagation();
        const sharedInfoId = event.currentTarget.dataset.sharedInfoId;
        const contactName = event.currentTarget.dataset.contactName;
        if (!confirm(`Are you sure you want to revoke sharing with ${contactName}? They will no longer see your contact info.`)) {
            return;
        }
        try {
            await revokeSharedContactInfo({ sharedContactInfoId: sharedInfoId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Revoked',
                message: `Sharing with ${contactName} has been revoked.`,
                variant: 'success'
            }));
            this._contactsLoaded = false;
            await this._loadContacts();
        } catch (error) {
            const msg = error.body?.message || error.message || 'Failed to revoke.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
        }
    }

    async handleUndoRevoke(event) {
        event.stopPropagation();
        const sharedInfoId = event.currentTarget.dataset.sharedInfoId;
        const contactName = event.currentTarget.dataset.contactName;
        try {
            await undoRevokeSharedContactInfo({ sharedContactInfoId: sharedInfoId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Restored',
                message: `Sharing with ${contactName} has been restored.`,
                variant: 'success'
            }));
            this._contactsLoaded = false;
            await this._loadContacts();
        } catch (error) {
            const msg = error.body?.message || error.message || 'Failed to restore.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
        }
    }

    _formatDate(dateValue) {
        if (!dateValue) return '';
        try {
            const d = new Date(dateValue);
            return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' });
        } catch (e) {
            return '';
        }
    }

    _getDueBadgeClass(dueDate) {
        if (!dueDate) return 'status-badge';
        const now = new Date();
        const due = new Date(dueDate);
        const daysUntilDue = Math.ceil((due - now) / (1000 * 60 * 60 * 24));

        if (daysUntilDue < 0) return 'status-badge status-overdue';
        if (daysUntilDue <= 3) return 'status-badge status-due-soon';
        return 'status-badge status-active';
    }
}