import { LightningElement, api, track, wire } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import searchVouchers from '@salesforce/apex/FimbyVouchController.searchVouchers';
import submitVoucherRequest from '@salesforce/apex/FimbyVouchController.submitVoucherRequest';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import { fireErrorToast, fireToast } from 'c/fimbyToastHelper';

const STATE_EXPLAINER = 'explainer';
const STATE_FORM = 'form';

const TYPE_PEER = 'peer';
const TYPE_COMMUNITY_GROUP = 'community_group';

const SEARCH_DEBOUNCE_MS = 250;
const SEARCH_MIN_CHARS = 2;

export default class FimbyVouchingRequiredModal extends LightningElement {
    @track isOpen = false;
    @track state = STATE_EXPLAINER;

    @track voucherType = TYPE_PEER;
    @track searchTerm = '';
    @track searchResults = [];
    @track selectedVoucher = null;
    @track isSearching = false;
    @track hasSearched = false;

    @track isSubmitting = false;
    @track submitMessage = '';

    _searchTimeout = null;
    _searchSeq = 0;

    @track actingAsContact = null;

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading acting-as contact:', error);
        }
    }

    get isActingAsSelf() {
        // Treat as self when identity not yet loaded to avoid false blocks.
        return !this.actingAsContact || this.actingAsContact.isActingAsSelf !== false;
    }

    get isBlockedByActingAs() {
        return !this.isActingAsSelf;
    }

    get actingAsBlockMessage() {
        const name = this.actingAsContact?.postingAsDisplayName
            || this.actingAsContact?.actingAsContactName
            || 'another identity';
        return `You're currently acting as ${name}. Vouching is tied to your own identity — please switch back to yourself before requesting an introduction.`;
    }

    @api
    show() {
        this.state = STATE_EXPLAINER;
        this.resetForm();
        this.submitMessage = '';
        this.isOpen = true;
    }

    @api
    close() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    resetForm() {
        this.voucherType = TYPE_PEER;
        this.searchTerm = '';
        this.searchResults = [];
        this.selectedVoucher = null;
        this.isSearching = false;
        this.hasSearched = false;
        clearTimeout(this._searchTimeout);
    }

    get saplingIconUrl() {
        return `${IMPACT_ICONS}/Sapling.png`;
    }

    get waveIconUrl() {
        return `${IMPACT_ICONS}/Waving.png`;
    }

    get isExplainer() {
        return this.state === STATE_EXPLAINER;
    }

    get isForm() {
        return this.state === STATE_FORM;
    }

    get isPeerType() {
        return this.voucherType === TYPE_PEER;
    }

    get isCommunityGroupType() {
        return this.voucherType === TYPE_COMMUNITY_GROUP;
    }

    get peerToggleClass() {
        return this.isPeerType ? 'toggle-option toggle-option_active' : 'toggle-option';
    }

    get cgToggleClass() {
        return this.isCommunityGroupType ? 'toggle-option toggle-option_active' : 'toggle-option';
    }

    get searchPlaceholder() {
        return this.isPeerType
            ? 'Start typing a neighbour\u2019s name\u2026'
            : 'Start typing a community group or church\u2026';
    }

    get showResults() {
        return !this.selectedVoucher && this.searchResults.length > 0;
    }

    get showNoResults() {
        return !this.selectedVoucher
            && this.hasSearched
            && !this.isSearching
            && this.searchResults.length === 0
            && this.searchTerm.trim().length >= SEARCH_MIN_CHARS;
    }

    get isSubmitDisabled() {
        return this.isSubmitting || !this.selectedVoucher || this.isBlockedByActingAs;
    }

    handleRequestVouchClick() {
        if (this.isBlockedByActingAs) {
            fireToast({ message: this.actingAsBlockMessage, variant: 'warning' });
            return;
        }
        this.state = STATE_FORM;
        this.submitMessage = '';
        this.resetForm();
    }

    handleBackToExplainer() {
        this.state = STATE_EXPLAINER;
    }

    handleClose() {
        this.close();
    }

    handleBackdrop(event) {
        if (event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleClose();
        }
    }

    handleSelectType(event) {
        const nextType = event.currentTarget.dataset.type;
        if (!nextType || nextType === this.voucherType) return;
        this.voucherType = nextType;
        this.searchTerm = '';
        this.searchResults = [];
        this.selectedVoucher = null;
        this.hasSearched = false;
        clearTimeout(this._searchTimeout);
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;

        clearTimeout(this._searchTimeout);
        if (this.searchTerm.trim().length < SEARCH_MIN_CHARS) {
            this.searchResults = [];
            this.hasSearched = false;
            this.isSearching = false;
            return;
        }

        this.isSearching = true;
        this._searchTimeout = setTimeout(() => this._doSearch(), SEARCH_DEBOUNCE_MS);
    }

    _doSearch() {
        const seq = ++this._searchSeq;
        searchVouchers({ searchTerm: this.searchTerm.trim(), voucherType: this.voucherType })
            .then(results => {
                if (seq !== this._searchSeq) return;
                this.searchResults = Array.isArray(results) ? results : [];
                this.hasSearched = true;
                this.isSearching = false;
            })
            .catch(() => {
                if (seq !== this._searchSeq) return;
                this.searchResults = [];
                this.hasSearched = true;
                this.isSearching = false;
            });
    }

    handleSelectResult(event) {
        const id = event.currentTarget.dataset.id;
        const match = this.searchResults.find(r => r.id === id);
        if (!match) return;
        this.selectedVoucher = match;
        this.searchResults = [];
        this.searchTerm = match.name;
    }

    handleClearSelection() {
        this.selectedVoucher = null;
        this.searchTerm = '';
        this.searchResults = [];
        this.hasSearched = false;
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) return;
        if (this.isBlockedByActingAs) {
            fireToast({ message: this.actingAsBlockMessage, variant: 'warning' });
            return;
        }
        this.isSubmitting = true;
        this.submitMessage = '';
        try {
            const result = await submitVoucherRequest({
                voucherType: this.selectedVoucher.voucherType,
                referenceId: this.selectedVoucher.id
            });
            this.submitMessage = result?.message || '';
            if (result?.delivered === true || result?.alreadyHasPending === true) {
                setTimeout(() => this.close(), 1500);
            }
        } catch (error) {
            fireErrorToast(error, 'Something went wrong sending your introduction. Please try again.');
        } finally {
            this.isSubmitting = false;
        }
    }
}
