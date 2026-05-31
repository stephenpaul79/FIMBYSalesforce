import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import createBulkBuyPost from '@salesforce/apex/FimbyBulkBuyController.createBulkBuyPost';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyBulkBuyForm extends LightningElement {
    @track actingAsContact = null;
    @track hasMultipleIdentities = false;

    @track title = '';
    @track description = '';
    @track totalQuantity = '';
    @track ownerShares = 1;
    @track unitLabel = '';
    @track perResponseLimit = '';
    @track availabilityRule = 'Open_Until_Full_Or_Closed';
    @track expiryDateTime = '';
    @track totalEstimatedCost = '';
    @track autoLockDays = '7';

    @track isPosting = false;

    // ============================================
    // SECTION HEADER ICONS
    // ============================================

    @wire(getActingAsContact)
    wiredContact({ error, data }) {
        if (data) {
            this.actingAsContact = data;
        } else if (error) {
            console.error('Error loading contact:', error);
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

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get postDetailsIconUrl() {
        return `${IMPACT_ICONS}/BulletinBoardActive.png`;
    }

    get sharesIconUrl() {
        return `${IMPACT_ICONS}/giftsm.png`;
    }

    get availabilityIconUrl() {
        return `${IMPACT_ICONS}/plannersm.png`;
    }

    get costIconUrl() {
        return `${IMPACT_ICONS}/lightbulb.png`;
    }

    get settingsIconUrl() {
        return `${IMPACT_ICONS}/gear.png`;
    }

    // ============================================
    // COMPUTED PROPERTIES
    // ============================================

    get parsedTotal() {
        const v = parseInt(this.totalQuantity, 10);
        return Number.isFinite(v) && v >= 1 ? v : 0;
    }

    get parsedOwnerShares() {
        const v = parseInt(this.ownerShares, 10);
        return Number.isFinite(v) && v >= 0 ? v : 0;
    }

    get availableForNeighbours() {
        return Math.max(0, this.parsedTotal - this.parsedOwnerShares);
    }

    get sharesPreviewText() {
        const total = this.parsedTotal;
        const avail = this.availableForNeighbours;
        if (total < 1) return '';
        const unit = this.unitLabel.trim() || 'share';
        const plural = avail === 1 || unit.endsWith('s') ? unit : unit + 's';
        return `${avail} of ${total} ${plural} available for neighbours to reserve`;
    }

    get showSharesPreview() {
        return this.parsedTotal >= 1;
    }

    get ownerSharesMax() {
        const t = this.parsedTotal;
        return t >= 1 ? t - 1 : 0;
    }

    get estimatedCostPerShare() {
        const cost = parseFloat(this.totalEstimatedCost);
        const qty = this.parsedTotal;
        if (!Number.isFinite(cost) || qty < 1) return null;
        return (cost / qty).toFixed(2);
    }

    get isExpiryVisible() {
        return this.availabilityRule === 'Expires_At_Date';
    }

    get descriptionCharacterCount() {
        return `${this.description.length}/2000`;
    }

    get titleCharacterCount() {
        return `${this.title.length}/80`;
    }

    get titleCountClass() {
        const len = this.title.length;
        if (len >= 80) return 'character-count at-limit';
        if (len >= 72) return 'character-count near-limit';
        return 'character-count';
    }

    get descriptionCountClass() {
        const len = this.description.length;
        if (len >= 2000) return 'character-count at-limit';
        if (len >= 1800) return 'character-count near-limit';
        return 'character-count';
    }

    get availabilityOptions() {
        return [
            { label: 'Expires At Date', value: 'Expires_At_Date', selected: this.availabilityRule === 'Expires_At_Date', pillClass: this.availabilityRule === 'Expires_At_Date' ? 'pill-btn selected' : 'pill-btn' },
            { label: 'Open Until Full Or Closed', value: 'Open_Until_Full_Or_Closed', selected: this.availabilityRule === 'Open_Until_Full_Or_Closed', pillClass: this.availabilityRule === 'Open_Until_Full_Or_Closed' ? 'pill-btn selected' : 'pill-btn' }
        ];
    }

    get autoLockOptions() {
        return [
            { label: '3 days', value: '3', selected: this.autoLockDays === '3', pillClass: this.autoLockDays === '3' ? 'pill-btn selected' : 'pill-btn' },
            { label: '7 days', value: '7', selected: this.autoLockDays === '7', pillClass: this.autoLockDays === '7' ? 'pill-btn selected' : 'pill-btn' },
            { label: '14 days', value: '14', selected: this.autoLockDays === '14', pillClass: this.autoLockDays === '14' ? 'pill-btn selected' : 'pill-btn' }
        ];
    }

    get submitLabel() {
        return this.isPosting ? 'Posting...' : '  Next >';
    }

    get parsedPerResponseLimit() {
        const v = parseInt(this.perResponseLimit, 10);
        return Number.isFinite(v) && v >= 1 ? v : null;
    }

    get perPersonLimitOverflowMessage() {
        const avail = this.availableForNeighbours;
        const unit = this.unitLabel.trim() || 'share';
        const plural = avail === 1 || unit.endsWith('s') ? unit : unit + 's';
        return `Can't exceed ${avail} ${plural} available for neighbours`;
    }

    get isSubmitDisabled() {
        if (this.isPosting) return true;
        if (!this.title.trim()) return true;
        if (this.parsedTotal < 1) return true;
        if (this.availableForNeighbours < 1) return true;
        if (this.isExpiryVisible && !this.expiryDateTime) return true;
        const limit = this.parsedPerResponseLimit;
        if (limit != null && limit > this.availableForNeighbours) return true;
        return false;
    }

    get estimatedCostDisplay() {
        const perShare = this.estimatedCostPerShare;
        return perShare != null ? `~$${perShare} per share` : '';
    }

    get postingAsDisplayName() {
        return this.actingAsContact?.postingAsDisplayName || this.actingAsContact?.contactName || 'Loading...';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsContact;
    }

    // ============================================
    // CHANGE HANDLERS
    // ============================================

    handleTitleChange(event) {
        this.title = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleTotalQuantityChange(event) {
        this.totalQuantity = event.target.value;
        if (this.parsedOwnerShares > this.parsedTotal - 1 && this.parsedTotal >= 1) {
            this.ownerShares = String(this.parsedTotal - 1);
        }
        const avail = this.availableForNeighbours;
        if (avail >= 1 && this.parsedPerResponseLimit != null && this.parsedPerResponseLimit > avail) {
            this.perResponseLimit = String(avail);
        }
    }

    handleOwnerSharesChange(event) {
        const val = parseInt(event.target.value, 10);
        if (Number.isFinite(val) && val >= 0) {
            this.ownerShares = Math.min(val, this.ownerSharesMax);
        } else {
            this.ownerShares = event.target.value;
        }
        const avail = this.availableForNeighbours;
        if (avail >= 1 && this.parsedPerResponseLimit != null && this.parsedPerResponseLimit > avail) {
            this.perResponseLimit = String(avail);
        }
    }

    handleUnitLabelChange(event) {
        this.unitLabel = event.target.value;
    }

    handlePerResponseLimitChange(event) {
        const raw = event.target.value;
        if (raw === '' || raw === null) {
            this.perResponseLimit = '';
            return;
        }
        const val = parseInt(raw, 10);
        if (!Number.isFinite(val) || val < 1) {
            this.perResponseLimit = raw;
            return;
        }
        const max = this.availableForNeighbours;
        const clamped = max >= 1 ? Math.min(val, max) : 0;
        const clampedStr = max >= 1 ? String(clamped) : '';
        if (val !== clamped) {
            event.target.value = clampedStr;
        }
        this.perResponseLimit = clampedStr;
    }

    handleAvailabilityRuleChange(event) {
        this.availabilityRule = event.target.value;
    }

    handleExpiryDateTimeChange(event) {
        this.expiryDateTime = event.target.value;
    }

    handleTotalEstimatedCostChange(event) {
        this.totalEstimatedCost = event.target.value;
    }

    handleAutoLockDaysChange(event) {
        this.autoLockDays = event.target.value;
    }

    handleAvailabilityPillClick(event) {
        this.availabilityRule = event.currentTarget.dataset.value;
    }

    handleAutoLockPillClick(event) {
        this.autoLockDays = event.currentTarget.dataset.value;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    // ============================================
    // SUBMIT HANDLER
    // ============================================

    async handleSubmit() {
        if (this.isSubmitDisabled) return;

        // Validation
        if (!this.title.trim()) {
            this.showErrorToast('Title is required.');
            return;
        }
        if (this.parsedTotal < 1) {
            this.showErrorToast('Total units you\'re purchasing must be at least 1.');
            return;
        }
        if (this.parsedOwnerShares >= this.parsedTotal) {
            this.showErrorToast('You must make at least 1 share available for neighbours.');
            return;
        }
        if (this.isExpiryVisible && !this.expiryDateTime) {
            this.showErrorToast('Expiry date and time are required when using "Expires At Date".');
            return;
        }
        const limit = this.parsedPerResponseLimit;
        if (limit != null && limit > this.availableForNeighbours) {
            this.showErrorToast(`Per person limit can't exceed the ${this.availableForNeighbours} shares available for neighbours.`);
            return;
        }

        this.isPosting = true;

        try {
            let expiryVal = null;
            if (this.isExpiryVisible && this.expiryDateTime) {
                let dt = this.expiryDateTime;
                if (dt.length === 16) dt += ':00';
                expiryVal = dt;
            }

            const postData = {
                title: this.title.trim(),
                description: this.description.trim(),
                totalQuantity: this.parsedTotal,
                ownerShares: this.parsedOwnerShares,
                unitLabel: this.unitLabel || null,
                perResponseLimit: this.perResponseLimit ? parseInt(this.perResponseLimit, 10) : null,
                availabilityRule: this.availabilityRule,
                expiryDateTime: expiryVal,
                totalEstimatedCost: this.totalEstimatedCost ? parseFloat(this.totalEstimatedCost) : null,
                autoLockDays: this.autoLockDays || '7'
            };

            const result = await createBulkBuyPost({ postData: JSON.stringify(postData) });

            if (result.success) {
                this.dispatchEvent(new CustomEvent('submit', {
                    detail: {
                        recordId: result.recordId,
                        postUrl: result.postUrl,
                        title: this.title.trim()
                    }
                }));
            } else {
                this.showErrorToast(result.message || 'Failed to create bulk buy post.');
            }
        } catch (error) {
            console.error('Bulk buy post error:', error);
            this.showErrorToast(error.body?.message || 'Failed to create bulk buy post. Please try again.');
        } finally {
            this.isPosting = false;
        }
    }

    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: message,
            variant: 'error'
        }));
    }
}