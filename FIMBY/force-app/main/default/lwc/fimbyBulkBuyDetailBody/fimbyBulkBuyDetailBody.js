import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import cancelReservation from '@salesforce/apex/FimbyBulkBuyReservationController.cancelReservation';

/**
 * Detail page body for Bulk Buy posts.
 * Rendered inside c-fimby-need-offer-detail when recordType is Bulk_Buy.
 */
export default class FimbyBulkBuyDetailBody extends LightningElement {
    @api post;
    @api isOrganiser;
    @api reservations = [];
    @api contactId;
    @api followUpStatus = {};

    @track cancelConfirmVisible = false;
    @track isCancelling = false;
    @track cancelPostConfirmVisible = false;

    get displayStatus() {
        const display = this.post?.Display_Status__c;
        if (display) {
            return display;
        }
        const status = this.post?.Status__c || '';
        if (status === 'Completed (Offer Accepted / Need Met)') {
            return 'Completed';
        }
        if (status === 'Pickup_Ready') {
            return 'Pickup Ready';
        }
        if (status === 'Cancelled' || status === 'Expired') {
            return status;
        }
        return status;
    }

    get totalShares() {
        const v = this.post?.Total_Quantity__c;
        return v != null ? Number(v) : 0;
    }

    get ownerShares() {
        const v = this.post?.Owner_Shares__c;
        return v != null ? Number(v) : 0;
    }

    get reservedShares() {
        const fromList = (this.reservations || []).reduce(
            (sum, r) => sum + (Number(r.amount) || 0),
            0
        );
        const rollup = this.post?.Total_Reserved__c;
        const fromRollup = rollup != null ? Number(rollup) : 0;
        return Math.max(fromRollup, fromList);
    }

    get availableShares() {
        return Math.max(0, this.totalShares - this.ownerShares - this.reservedShares);
    }

    get showBuyerSegment() {
        return this.isOrganiser && this.ownerShares > 0;
    }

    get combinedReservedShares() {
        return this.ownerShares + this.reservedShares;
    }

    get legendReservedCount() {
        return this.isOrganiser ? this.reservedShares : this.combinedReservedShares;
    }

    get hasLegendReserved() {
        return this.legendReservedCount > 0;
    }

    get hasAvailableShares() {
        return this.availableShares > 0;
    }

    get buyerPillText() {
        return `${this.ownerShares} for buyer`;
    }

    get reservedPillText() {
        return `${this.legendReservedCount} reserved`;
    }

    get availablePillText() {
        return `${this.availableShares} available`;
    }

    get unitLabel() {
        const label = this.post?.Allocation_Unit_Label__c;
        return label && String(label).trim() ? String(label).trim() : 'share';
    }

    get hasCostInfo() {
        const cost = this.post?.Estimated_Cost_Per_Share__c;
        return cost != null && Number(cost) > 0;
    }

    get estimatedCostPerShare() {
        const v = this.post?.Estimated_Cost_Per_Share__c;
        return v != null ? Number(v) : 0;
    }

    get totalEstimatedCost() {
        const v = this.post?.Total_Estimated_Cost__c;
        return v != null ? Number(v) : 0;
    }

    get formattedCostPerShare() {
        const v = this.estimatedCostPerShare;
        return v > 0 ? '$' + (Math.round(v * 100) / 100).toFixed(2) : '$0.00';
    }

    get formattedTotalCost() {
        const v = this.totalEstimatedCost;
        return v > 0 ? '$' + (Math.round(v * 100) / 100).toFixed(2) : '$0.00';
    }

    get isPickupReady() {
        return this.displayStatus === 'Pickup Ready';
    }

    get isCompleted() {
        return this.displayStatus === 'Completed';
    }

    get isCancelled() {
        return this.displayStatus === 'Cancelled' || this.displayStatus === 'Expired';
    }

    get canReserve() {
        if (!this.post || this.isOrganiser) return false;
        if (this.isCancelled || this.isCompleted) return false;
        if (this.hasUserReservation) return false;
        return this.availableShares > 0;
    }

    get showReserveButton() {
        return this.post && !this.isOrganiser && !this.hasUserReservation;
    }

    get isReserveDisabled() {
        return this.isCancelled || this.isCompleted || this.isPickupReady || this.availableShares <= 0;
    }

    get reserveButtonLabel() {
        if (!this.isReserveDisabled) return 'Reserve A Share';
        if (this.isCompleted) return 'Completed';
        if (this.isCancelled) return this.displayStatus === 'Expired' ? 'Expired' : 'Cancelled';
        if (this.isPickupReady) return 'Reservations Closed';
        return 'Fully Reserved';
    }

    get reserveButtonClass() {
        return this.isReserveDisabled ? 'action-btn primary reserve-btn disabled' : 'action-btn primary reserve-btn';
    }

    get reserveAriaLabel() {
        if (!this.isReserveDisabled) return 'Reserve a share in this bulk buy';
        return `This bulk buy is ${this.reserveButtonLabel.toLowerCase()} and no longer accepting reservations`;
    }

    get reserveHelperText() {
        if (this.isCancelled || this.isCompleted || this.isPickupReady) return null;
        if (this.availableShares <= 0) {
            return 'All shares have been reserved \u2014 check back in case one is released.';
        }
        return null;
    }

    get showReserveHelperText() {
        return this.reserveHelperText != null;
    }

    get reserveHelperId() {
        return this.showReserveHelperText ? 'reserve-helper' : undefined;
    }

    get showOrganiserActions() {
        return this.isOrganiser && !this.isCompleted && !this.isCancelled;
    }

    get showNotifyPickupButton() {
        return !this.isPickupReady && !this.isCompleted && !this.isCancelled;
    }

    get isNotifyPickupDisabled() {
        return this.availableShares > 0;
    }

    get notifyPickupLabel() {
        return 'Notify for Pickup';
    }

    get notifyPickupClass() {
        if (this.isNotifyPickupDisabled) {
            return 'action-btn organiser-btn disabled';
        }
        return 'action-btn primary';
    }

    get showCancelPost() {
        return !this.isPickupReady && !this.isCompleted && !this.isCancelled;
    }

    get canComplete() {
        return this.isOrganiser && this.isPickupReady;
    }

    get receiptImageUrl() {
        return this.post?.Receipt_Image_URL__c ?? '';
    }

    get hasReceiptImage() {
        const url = this.receiptImageUrl;
        return url && String(url).trim().length > 0;
    }

    get groupConversationId() {
        return this.post?.Group_Conversation__c ?? '';
    }

    get hasGroupConversation() {
        return !!this.groupConversationId;
    }

    get groupChatUrl() {
        const id = this.groupConversationId;
        return id ? '/conversation?id=' + id : '';
    }

    get buyIconUrl() {
        return `${IMPACT_ICONS}/buy.png`;
    }

    get pickupIconUrl() {
        return `${IMPACT_ICONS}/pickup.png`;
    }

    get completeIconUrl() {
        return `${IMPACT_ICONS}/complete.png`;
    }

    get chatIconUrl() {
        return `${IMPACT_ICONS}/chat.png`;
    }

    get cancelIconUrl() {
        return `${IMPACT_ICONS}/XFilled.png`;
    }

    get userReservation() {
        if (!this.reservations || !this.contactId) return null;
        return this.reservations.find(
            r => r.contactId === this.contactId
                || r.onBehalfOfContactId === this.contactId
        ) || null;
    }

    get hasUserReservation() {
        return !!this.userReservation;
    }

    get userReservationAmount() {
        return this.userReservation?.amount || 0;
    }

    get canCancelReservation() {
        if (!this.hasUserReservation) return false;
        return this.displayStatus === 'Shares Available' || this.displayStatus === 'Available';
    }

    // ============================================
    // PERSONA: ORGANISER EMPTY STATE
    // ============================================

    get showOrganiserEmptyState() {
        return this.isOrganiser && (!this.reservations || this.reservations.length === 0);
    }

    get organiserEmptyStateMessage() {
        return 'No reservations yet \u2014 your neighbours will see this!';
    }

    get organiserPostHealthText() {
        const parts = [];
        const status = this.displayStatus;
        if (status === 'Shares Available' || status === 'Available') parts.push('Buy is active');
        else parts.push(status || 'Active');
        if (this.hasExpiry) parts.push(`Expires ${this.formattedExpiry}`);
        return parts.join(' \u00B7 ');
    }

    // ============================================
    // PERSONA: RESERVER CARD DATA
    // ============================================

    get reserverStatusContext() {
        const status = this.displayStatus;
        if (status === 'Shares Available' || status === 'Available') return 'Your share is reserved \u2014 waiting for all spots to fill';
        if (status === 'Fully Reserved') return 'All shares reserved \u2014 waiting for organiser to confirm pickup';
        if (status === 'Pickup Ready') return 'Ready for pickup!';
        if (status === 'Completed') return 'This bulk buy is complete';
        return '';
    }

    get reserverAmountDisplay() {
        const amt = this.userReservationAmount;
        const unit = this.unitLabel;
        return amt === 1 ? `1 ${unit} reserved` : `${amt} ${unit}s reserved`;
    }

    // ============================================
    // PERSONA: NEW VISITOR CONTEXT
    // ============================================

    get visitorActionContext() {
        return 'Reserve a share to join this bulk buy. The organiser will confirm pickup details.';
    }

    get cancelModalMessage() {
        const amt = this.userReservationAmount;
        const unit = this.unitLabel;
        const plural = amt === 1 ? '' : 's';
        return `Your ${amt} ${unit}${plural} will be released back to the pool. This bulk buy still has shares available, so you can re-reserve later if you change your mind.`;
    }

    get hasExpiry() {
        const d = this.post?.Expiry_DateTime__c;
        return !!d;
    }

    get formattedExpiry() {
        const d = this.post?.Expiry_DateTime__c;
        return d ? new Date(d).toLocaleString() : '';
    }

    get thermometerBarStyle() {
        const total = this.totalShares || 1;
        const teal = 'var(--fimby-brand-teal, #3A7D8C)';
        const light = '#C1DFE5';

        if (this.isOrganiser && this.ownerShares > 0) {
            const buyerEnd = Math.round((this.ownerShares / total) * 100);
            const reservedEnd = Math.min(100, buyerEnd + Math.round((this.reservedShares / total) * 100));
            return `background: linear-gradient(to right, #8B8178 ${buyerEnd}%, ${teal} ${buyerEnd}%, ${teal} ${reservedEnd}%, ${light} ${reservedEnd}%)`;
        }
        const combinedPct = Math.min(100, Math.round((this.combinedReservedShares / total) * 100));
        return `background: linear-gradient(to right, ${teal} ${combinedPct}%, ${light} ${combinedPct}%)`;
    }

    get showOrganiserReservationsList() {
        return this.isOrganiser && (this.reservations?.length || 0) > 0;
    }

    get showOrganiserReservationActions() {
        return this.showOrganiserReservationsList && !this.isCompleted && !this.isCancelled;
    }

    get showFooterGroupChat() {
        return this.hasGroupConversation && !this.isCompleted && !this.isCancelled;
    }

    get reservationsWithButtonState() {
        const list = this.reservations || [];
        const followUp = this.followUpStatus || {};
        const readOnly = this.isCompleted || this.isCancelled;
        return list.map((r) => {
            const status = followUp[r.id];
            let label = readOnly ? '' : 'Check In — Send Private Message';
            let buttonClass = '';
            let disabled = readOnly;
            if (status === 'Pending') {
                label = 'Mark Resolved';
                buttonClass = 'btn-pending';
            } else if (status === 'Escalated') {
                label = 'Under Review';
                buttonClass = 'btn-escalated';
                disabled = true;
            } else if (status === 'No_Response' || status === 'Admin_Confirmed') {
                label = 'Check In';
                buttonClass = 'btn-disabled';
                disabled = true;
            }
            const fn = r.firstName || '';
            const avatarInitial = fn ? fn.charAt(0).toUpperCase() : (r.lastName ? String(r.lastName).charAt(0).toUpperCase() : '?');
            const displayName = [fn, r.lastName || ''].filter(Boolean).join(' ') || 'Reserver';
            return { ...r, buttonLabel: label, buttonClass, buttonDisabled: disabled, avatarInitial, displayName };
        });
    }

    getButtonStateForReserver(reservationId) {
        const status = this.followUpStatus && this.followUpStatus[reservationId];
        if (!status) {
            return { label: 'Check In — Send Private Message', icon: '', disabled: false, buttonClass: '' };
        }
        if (status === 'Pending') {
            return { label: 'Mark Resolved', icon: '', disabled: false, buttonClass: 'btn-pending' };
        }
        if (status === 'Escalated') {
            return { label: 'Under Review', icon: '', disabled: true, buttonClass: 'btn-escalated' };
        }
        if (status === 'No_Response' || status === 'Admin_Confirmed') {
            return { label: 'Check In', icon: '', disabled: true, buttonClass: 'btn-disabled' };
        }
        return { label: 'Check In — Send Private Message', icon: '', disabled: false, buttonClass: '' };
    }

    handleReserve() {
        if (this.isReserveDisabled) return;
        this.dispatchEvent(new CustomEvent('reserve'));
    }

    handleNotifyPickup() {
        if (this.isNotifyPickupDisabled) return;
        this.dispatchEvent(new CustomEvent('notifypickup'));
    }

    handleComplete() {
        this.dispatchEvent(new CustomEvent('complete'));
    }

    handleCancel() {
        this.cancelPostConfirmVisible = true;
    }

    handleCancelPostDismiss() {
        this.cancelPostConfirmVisible = false;
    }

    handleCancelPostConfirm() {
        this.cancelPostConfirmVisible = false;
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleCheckIn(event) {
        const reservationId = event.currentTarget?.dataset?.reservationId;
        const reserverName = event.currentTarget?.dataset?.reserverName || '';
        if (reservationId) {
            this.dispatchEvent(new CustomEvent('checkin', { detail: { reservationId, reserverName } }));
        }
    }

    handleOpenGroupChat() {
        if (this.groupChatUrl) {
            window.location.href = this.groupChatUrl;
        }
    }

    handleCancelClick() {
        this.cancelConfirmVisible = true;
    }

    handleCancelDismiss() {
        this.cancelConfirmVisible = false;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    async handleCancelConfirm() {
        if (!this.userReservation?.id) return;
        this.isCancelling = true;
        try {
            await cancelReservation({ responseId: this.userReservation.id });
            this.cancelConfirmVisible = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Reservation cancelled',
                message: 'Your shares have been released.',
                variant: 'success'
            }));
        } catch (error) {
            console.error('Error cancelling reservation:', error);
            this.cancelConfirmVisible = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Something went wrong',
                message: error.body?.message || 'Could not cancel your reservation.',
                variant: 'error'
            }));
        } finally {
            this.isCancelling = false;
            this.dispatchEvent(new CustomEvent('cancelreservation'));
        }
    }
}