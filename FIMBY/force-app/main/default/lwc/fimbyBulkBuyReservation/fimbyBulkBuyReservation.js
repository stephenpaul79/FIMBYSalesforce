/**
 * @deprecated Replaced by fimbyQuickResponseModal (bulkBuy variant).
 * This full-page form and its /reserve-share route should be unpublished in Experience Builder and then deleted.
 */
import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';

import getReservationContext from '@salesforce/apex/FimbyBulkBuyReservationController.getReservationContext';
import createReservation from '@salesforce/apex/FimbyBulkBuyReservationController.createReservation';
import getBulkBuyHistory from '@salesforce/apex/FimbyFollowUpController.getBulkBuyHistory';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyBulkBuyReservation extends NavigationMixin(LightningElement) {
    recordId;

    // View states: 'loading', 'unavailable', 'alreadyReserved', 'fullyReserved', 'blocked', 'form', 'success', 'error'
    @track viewState = 'loading';
    @track amount = 1;
    @track isSubmitting = false;
    @track errorMessage = '';
    @track reservationResult = null;
    @track post = null;
    @track existingReservation = null;
    @track bulkBuyHistory = null;
    @track contactId = null;
    @track blockedMessage = '';
    @track actingAsContact = null;
    @track hasMultipleIdentities = false;

    defaultAvatarUrl = 'https://fimby.file.force.com/sfc/dist/version/renditionDownload?rendition=ORIGINAL_PNG&versionId=068OL00000A728z&operationContext=DELIVERY&contentId=05TOL00000CsvCQ&page=0&d=/a/OL000005rMIr/8p5CUUyFrdpAivDzkgUrn4DaBoudxfTwT4yVSF5lRSc&oid=00D5f000006NDkr';

    connectedCallback() {
        const urlParams = new URLSearchParams(window.location.search);
        this.recordId = urlParams.get('recordId');

        if (!this.recordId) {
            this.viewState = 'error';
            this.errorMessage = 'No bulk buy specified. Please select a share from the feed.';
            return;
        }

        this.loadContext();
    }

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading acting-as contact:', error);
        }
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this.hasMultipleIdentities = data.length > 0;
        } else if (error) {
            console.error('Error loading identities:', error);
            this.hasMultipleIdentities = false;
        }
    }

    get postingAsDisplayName() {
        return this.actingAsContact?.postingAsDisplayName
            || this.actingAsContact?.actingAsContactName
            || this.actingAsContact?.contactName
            || '';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.postingAsDisplayName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    async loadContext() {
        try {
            const result = await getReservationContext({ postId: this.recordId });

            if (!result.success) {
                this.viewState = 'error';
                this.errorMessage = 'Could not load reservation details.';
                return;
            }

            this.viewState = result.viewState;
            this.post = result.post;
            this.existingReservation = result.existingReservation;
            this.contactId = result.contactId;

            if (result.blocked) {
                this.blockedMessage = 'A few shares in a row weren\'t completed. Your neighbours are counting on you — let\'s chat about how to get back on track.';
            }

            if (this.viewState === 'blocked' && this.contactId) {
                await this.loadBulkBuyHistory();
            }

            if (this.viewState === 'form' && this.post) {
                this.amount = Math.min(Math.max(1, this.amount), this.maxAmount);
            }
        } catch (error) {
            console.error('Error loading context:', error);
            this.viewState = 'error';
            this.errorMessage = error.body?.message || 'An error occurred while loading.';
        }
    }

    async loadBulkBuyHistory() {
        try {
            const result = await getBulkBuyHistory({ contactId: this.contactId });
            if (result.success) {
                this.bulkBuyHistory = result;
            }
        } catch (e) {
            console.error('Error loading bulk buy history:', e);
        }
    }

    get maxAmount() {
        if (!this.post) return 1;
        const limit = this.post.Per_Response_Limit__c != null ? Number(this.post.Per_Response_Limit__c) : Infinity;
        const avail = this.availableShares;
        return Math.max(1, Math.min(limit, avail));
    }

    get buyIconUrl() {
        return `${IMPACT_ICONS}/buy.png`;
    }

    get completeIconUrl() {
        return `${IMPACT_ICONS}/complete.png`;
    }

    get costPerShareDisplay() {
        const cost = this.post?.Estimated_Cost_Per_Share__c;
        if (cost == null || Number(cost) <= 0) return null;
        return '$' + (Math.round(Number(cost) * 100) / 100).toFixed(2);
    }

    get availableShares() {
        const v = this.post?.Total_Available__c;
        return v != null ? Number(v) : 0;
    }

    get unitLabel() {
        const label = this.post?.Allocation_Unit_Label__c;
        return label && String(label).trim() ? String(label).trim() : 'share';
    }

    get unitLabelPlural() {
        const label = this.unitLabel;
        if (/s$/i.test(label)) return label;
        return label + 's';
    }

    get detailPageUrl() {
        return this.recordId ? `/asks-offers/${this.recordId}` : '/';
    }

    get reservedShares() {
        const v = this.post?.Total_Reserved__c;
        return v != null ? Number(v) : 0;
    }

    get totalShares() {
        const v = this.post?.Total_Quantity__c;
        return v != null ? Number(v) : 0;
    }

    get ownerShares() {
        const v = this.post?.Owner_Shares__c;
        return v != null ? Number(v) : 0;
    }

    get committedPercent() {
        const total = this.totalShares || 1;
        const committed = this.ownerShares + this.reservedShares;
        return Math.min(100, (committed / total) * 100);
    }

    get selectionPercent() {
        const total = this.totalShares || 1;
        const sel = (this.amount / total) * 100;
        return Math.min(100 - this.committedPercent, sel);
    }

    get committedStyle() {
        return `width: ${this.committedPercent}%`;
    }

    get selectionStyle() {
        return `width: ${this.selectionPercent}%`;
    }

    get thermometerFillStyle() {
        const total = this.totalShares || 1;
        const filled = this.ownerShares + this.reservedShares;
        const pct = Math.min(100, Math.round((filled / total) * 100));
        return `width: ${pct}%`;
    }

    get showBuyerPill() {
        return this.ownerShares > 0;
    }

    get buyerPillText() {
        return `${this.ownerShares} for buyer`;
    }

    get reservedPillText() {
        return `${this.reservedShares} reserved`;
    }

    get availablePillText() {
        return `${this.availableShares} available`;
    }

    get reservedPillClass() {
        return 'alloc-pill pill-reserved' + (this.reservedShares <= 0 ? ' pill-zero' : '');
    }

    get availablePillClass() {
        return 'alloc-pill pill-available' + (this.availableShares <= 0 ? ' pill-zero' : '');
    }

    get successReservedText() {
        const amt = this.amount;
        const label = this.unitLabel;
        const plural = this.unitLabelPlural;
        const unitText = amt === 1 ? label : plural;
        return `You've reserved ${amt} of the ${unitText}. The organiser will coordinate pickup with you.`;
    }

    get successPillText() {
        const amt = this.amount;
        const label = this.unitLabel;
        const plural = this.unitLabelPlural;
        return amt === 1 ? `${amt} ${label} reserved` : `${amt} ${plural} reserved`;
    }

    get successCommittedPercent() {
        const total = this.totalShares || 1;
        const priorCommitted = this.ownerShares + this.reservedShares - this.amount;
        return Math.max(0, (priorCommitted / total) * 100);
    }

    get successJustReservedPercent() {
        const total = this.totalShares || 1;
        return Math.min(100 - this.successCommittedPercent, (this.amount / total) * 100);
    }

    get successCommittedStyle() {
        return `width: ${this.successCommittedPercent}%`;
    }

    get successJustReservedStyle() {
        return `width: ${this.successJustReservedPercent}%`;
    }

    get alreadyReservedText() {
        const amt = this.existingReservation?.Amount_Requested__c;
        const label = this.unitLabel;
        const plural = this.unitLabelPlural;
        const unitText = (amt === 1) ? label : plural;
        return `You've reserved ${amt} ${unitText} for this bulk buy.`;
    }

    get groupChatUrl() {
        const id = this.reservationResult?.groupConversationId;
        return id ? '/conversation?id=' + id : '';
    }

    get hasGroupChat() {
        return !!this.reservationResult?.groupConversationId;
    }

    get historySlots() {
        const slots = this.bulkBuyHistory?.slots || [];
        return slots.map((color, idx) => ({ color, key: `slot-${idx}-${color}` }));
    }

    handleAmountChange(event) {
        const raw = parseInt(event.target.value, 10);
        if (isNaN(raw) || raw < 1) {
            this.amount = 1;
            return;
        }
        this.amount = Math.min(Math.max(1, raw), this.maxAmount);
    }

    handleDecrement() {
        if (this.amount > 1) {
            this.amount = this.amount - 1;
        }
    }

    handleIncrement() {
        if (this.amount < this.maxAmount) {
            this.amount = this.amount + 1;
        }
    }

    async handleSubmit() {
        if (this.isSubmitting || !this.recordId) return;
        if (this.amount < 1 || this.amount > this.maxAmount) return;

        this.isSubmitting = true;

        try {
            const result = await createReservation({
                postId: this.recordId,
                amount: this.amount
            });

            if (result.success) {
                this.reservationResult = result;
                this.viewState = 'success';
                if (this.post) {
                    this.post = {
                        ...this.post,
                        Total_Reserved__c: (this.post.Total_Reserved__c || 0) + this.amount,
                        Total_Available__c: (this.post.Total_Available__c || 0) - this.amount
                    };
                }
            } else if (result.blocked) {
                this.blockedMessage = result.message || this.blockedMessage;
                this.viewState = 'blocked';
                if (this.contactId) {
                    await this.loadBulkBuyHistory();
                }
            } else {
                this.errorMessage = result.message || 'Failed to create reservation.';
                this.viewState = 'error';
            }
        } catch (error) {
            console.error('Error creating reservation:', error);
            this.errorMessage = error.body?.message || 'Failed to create reservation.';
            this.viewState = 'error';
        } finally {
            this.isSubmitting = false;
        }
    }

    handleRetry() {
        this.viewState = 'loading';
        this.errorMessage = '';
        this.loadContext();
    }

    handleBackToFeed() {
        navigate(this, '/');
    }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    handleDone() {
        navigate(this, '/');
    }

    handleViewGroupChat() {
        const url = this.groupChatUrl;
        if (url) {
            navigate(this, url);
        }
    }

    handleTabChange(event) {
        const tab = event.detail?.tab;
        const routes = { home: '/', library: '/library-list', messages: '/messages', mine: '/my-stuff' };
        navigate(this, routes[tab] || '/');
    }

    // View state getters
    get isLoadingState() {
        return this.viewState === 'loading';
    }
    get isUnavailableState() {
        return this.viewState === 'unavailable';
    }
    get isAlreadyReservedState() {
        return this.viewState === 'alreadyReserved';
    }
    get isFullyReservedState() {
        return this.viewState === 'fullyReserved';
    }
    get isBlockedState() {
        return this.viewState === 'blocked';
    }
    get isFormState() {
        return this.viewState === 'form';
    }
    get isSuccessState() {
        return this.viewState === 'success';
    }
    get isErrorState() {
        return this.viewState === 'error';
    }

    get postImageUrl() {
        return this.resolveImageUrl(this.post?.Image_1_URL__c);
    }
    get hasPostImage() {
        const url = this.postImageUrl;
        return url && String(url).trim().length > 0;
    }
    get postTitle() {
        return this.post?.Name || 'Bulk Buy';
    }
    get organiserName() {
        const p = this.post?.Posted_By__r;
        if (!p) return 'Organiser';
        return p.Full_Name__c || `${p.FirstName || ''} ${p.LastName || ''}`.trim() || 'Organiser';
    }
    get organiserAvatarUrl() {
        const url = this.post?.Posted_By__r?.Image_URL__c;
        return url ? avatarImageUrl(url) : this.defaultAvatarUrl;
    }
}