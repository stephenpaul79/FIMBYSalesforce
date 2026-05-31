import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyModeratorHealthPanel extends LightningElement {
    @api neighbourhoodId;
    @api overdueLoans = [];
    @api stalePosts = [];
    @api inactiveMembers = [];
    @api isLoading = false;

    @track _loansExpanded = true;
    @track _postsExpanded = true;
    @track _membersExpanded = true;

    _mediaQuery;

    /* ── Icons ────────────────────────────────────────────────────── */

    get searchIconUrl() { return `${IMPACT_ICONS}/Magnify.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get profileIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }

    /* ── Derived state ────────────────────────────────────────────── */

    get showContent() { return !this.isLoading; }

    get hasOverdueLoans() { return this.overdueLoans?.length > 0; }
    get noOverdueLoans() { return !this.hasOverdueLoans; }
    get overdueLoansCount() { return this.overdueLoans?.length || 0; }

    get hasStalePosts() { return this.stalePosts?.length > 0; }
    get noStalePosts() { return !this.hasStalePosts; }
    get stalePostsCount() { return this.stalePosts?.length || 0; }

    get hasInactiveMembers() { return this.inactiveMembers?.length > 0; }
    get noInactiveMembers() { return !this.hasInactiveMembers; }
    get inactiveMembersCount() { return this.inactiveMembers?.length || 0; }

    /* ── Expand / collapse ────────────────────────────────────────── */

    get loansChevron() { return this._loansExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get postsChevron() { return this._postsExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get membersChevron() { return this._membersExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }

    get loansExpanded() { return this._loansExpanded ? 'true' : 'false'; }
    get postsExpanded() { return this._postsExpanded ? 'true' : 'false'; }
    get membersExpanded() { return this._membersExpanded ? 'true' : 'false'; }

    toggleLoans() { this._loansExpanded = !this._loansExpanded; }
    togglePosts() { this._postsExpanded = !this._postsExpanded; }
    toggleMembers() { this._membersExpanded = !this._membersExpanded; }

    /* ── Lifecycle ────────────────────────────────────────────────── */

    connectedCallback() {
        this._mediaQuery = window.matchMedia('(min-width: 768px)');
        if (!this._mediaQuery.matches) {
            this._loansExpanded = true;
            this._postsExpanded = false;
            this._membersExpanded = false;
        }
        this._mediaQuery.addEventListener('change', this._handleMediaChange);
    }

    disconnectedCallback() {
        if (this._mediaQuery) {
            this._mediaQuery.removeEventListener('change', this._handleMediaChange);
        }
    }

    _handleMediaChange = (e) => {
        if (e.matches) {
            this._loansExpanded = true;
            this._postsExpanded = true;
            this._membersExpanded = true;
        }
    }

    /* ── Action handlers ──────────────────────────────────────────── */

    handleViewItem(event) {
        this._dispatchHealth('viewItem', event.currentTarget.dataset.recordId);
    }

    handleContactBorrower(event) {
        this._dispatchHealth('contactBorrower', null, event.currentTarget.dataset.contactId);
    }

    handleContactOwner(event) {
        this._dispatchHealth('contactOwner', null, event.currentTarget.dataset.contactId);
    }

    handleViewPost(event) {
        this._dispatchHealth('viewPost', event.currentTarget.dataset.recordId);
    }

    handleContactAuthor(event) {
        this._dispatchHealth('contactAuthor', null, event.currentTarget.dataset.contactId);
    }

    handleViewProfile(event) {
        this._dispatchHealth('viewProfile', event.currentTarget.dataset.recordId);
    }

    handleSendCheckin(event) {
        this._dispatchHealth('sendCheckin', null, event.currentTarget.dataset.contactId);
    }

    _dispatchHealth(action, recordId, contactId) {
        this.dispatchEvent(new CustomEvent('healthaction', {
            detail: { action, recordId, contactId },
            bubbles: true,
            composed: true
        }));
    }
}