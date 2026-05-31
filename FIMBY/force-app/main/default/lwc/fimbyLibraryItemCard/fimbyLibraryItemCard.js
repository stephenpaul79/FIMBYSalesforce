import { LightningElement, api, track, wire } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getCategoryIconUrl } from 'c/fimbyLibraryCategoryConfig';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';
import { formatLocalDate, parseLocalDate } from 'c/fimbyDateUtils';

export default class FimbyLibraryItemCard extends LightningElement {
    @api item = {};
    @api showActions = false;
    @track currentImageIndex = 0;
    @track isSaved = false;
    organizationId = null;

    // Wire Organization ID
    @wire(getOrganizationId)
    wiredOrgId({ data, error }) {
        if (data) {
            this.organizationId = data;
        } else if (error) {
            console.error('Error fetching Organization ID:', error);
        }
    }

    // Helper method to get complete image URL with Organization ID
    getCompleteImageUrl(imageUrl) {
        if (!imageUrl) {
            return null;
        }

        // If the URL already contains the organization ID or is a complete URL, return as-is
        if (imageUrl.includes('http') || (this.organizationId && imageUrl.includes(this.organizationId))) {
            return imageUrl;
        }

        // If we have the organization ID, append it
        if (this.organizationId) {
            return imageUrl + this.organizationId;
        }

        // Fallback: return the original URL
        return imageUrl;
    }

    get currentImage() {
        if (this.item.images && this.item.images.length > 0) {
            return this.getCompleteImageUrl(this.item.images[this.currentImageIndex]);
        }
        return null;
    }

    get borrowCountDisplay() {
        return this.item.borrowCount || 0;
    }

    get hasMultipleImages() {
        return this.item.images && this.item.images.length > 1;
    }

    get availabilityIcon() {
        if (this.item.isAvailable) {
            return 'utility:success';
        } else if (this.item.dueDate) {
            return 'utility:clock';
        } else {
            return 'utility:block_visitor';
        }
    }

    get availabilityText() {
        if (this.item.isAvailable) {
            return 'Available';
        } else if (this.item.dueDate) {
            return `Due ${this.formatShortDate(this.item.dueDate)}`;
        } else {
            return 'Not Available';
        }
    }

    get categoryIconUrl() {
        return getCategoryIconUrl(IMPACT_ICONS, this.item.category || 'Other');
    }

    get conditionIcon() {
        switch (this.item.condition?.toLowerCase()) {
            case 'excellent': return 'utility:success';
            case 'good': return 'utility:like';
            case 'fair': return 'utility:warning';
            case 'poor': return 'utility:error';
            default: return 'utility:info';
        }
    }

    get conditionClass() {
        const condition = this.item.condition?.toLowerCase();
        switch (condition) {
            case 'excellent': return 'condition-excellent';
            case 'good': return 'condition-good';
            case 'fair': return 'condition-fair';
            case 'poor': return 'condition-poor';
            default: return 'condition-unknown';
        }
    }

    get truncatedDescription() {
        if (!this.item.description) return '';
        return this.item.description.length > 100
            ? this.item.description.substring(0, 100) + '...'
            : this.item.description;
    }

    get loanPeriodText() {
        if (!this.item.loanPeriod) return '';

        switch (this.item.loanPeriod) {
            case '1': return '1 day';
            case '3': return '3 days';
            case '7': return '1 week';
            case '14': return '2 weeks';
            case '30': return '1 month';
            case 'flexible': return 'Flexible';
            default: return `${this.item.loanPeriod} days`;
        }
    }

    get ratingStars() {
        const rating = this.item.rating || 0;
        const stars = [];

        for (let i = 1; i <= 5; i++) {
            stars.push({
                id: i,
                icon: i <= rating ? 'utility:favorite' : 'utility:favorite_alt',
                class: i <= rating ? 'star filled' : 'star empty'
            });
        }

        return stars;
    }

    get ownerRatingStars() {
        const rating = this.item.ownerRating || 0;
        const stars = [];

        for (let i = 1; i <= 5; i++) {
            stars.push({
                id: i,
                icon: i <= rating ? 'utility:favorite' : 'utility:favorite_alt',
                class: i <= rating ? 'star filled' : 'star empty'
            });
        }

        return stars;
    }

    get borrowButtonText() {
        return this.item.requiresApproval ? 'Request' : 'Borrow';
    }

    get saveIcon() {
        return this.isSaved ? 'utility:bookmark' : 'utility:bookmark_alt';
    }

    get saveButtonClass() {
        return this.isSaved ? 'save-button saved' : 'save-button';
    }

    get showDueDate() {
        return this.item.dueDate && this.item.borrowedByCurrentUser;
    }

    get formattedDueDate() {
        return formatLocalDate(this.item.dueDate);
    }

    get isOverdue() {
        const due = parseLocalDate(this.item.dueDate);
        if (!due) return false;
        return due < new Date();
    }

    get getIndicatorClass() {
        return (index) => {
            return index === this.currentImageIndex
                ? 'indicator active'
                : 'indicator';
        };
    }

    connectedCallback() {
        this.isSaved = this.item.isSaved || false;
    }

    formatShortDate(dateString) {
        const date = parseLocalDate(dateString);
        if (!date) return '';
        const now = new Date();
        const diffDays = Math.ceil((date - now) / (1000 * 60 * 60 * 24));

        if (diffDays === 0) return 'today';
        if (diffDays === 1) return 'tomorrow';
        if (diffDays < 7) return `in ${diffDays} days`;

        return date.toLocaleDateString();
    }

    handleImageChange(event) {
        event.stopPropagation();
        this.currentImageIndex = parseInt(event.target.dataset.index, 10);
    }

    handleCardClick(event) {
        // Prevent card click when interacting with action buttons
        if (event.target.closest('.action-buttons') ||
            event.target.closest('.image-indicators')) {
            return;
        }

        this.dispatchEvent(new CustomEvent('itemselect', {
            detail: {
                itemId: this.item.id,
                item: this.item
            }
        }));
    }

    handleBorrow(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('itemborrow', {
            detail: {
                itemId: this.item.id,
                item: this.item,
                requiresApproval: this.item.requiresApproval
            }
        }));
    }

    handleNotifyAvailable(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('itemnotify', {
            detail: {
                itemId: this.item.id,
                item: this.item
            }
        }));
    }

    handleMessage(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('itemmessage', {
            detail: {
                itemId: this.item.id,
                ownerId: this.item.ownerId,
                ownerName: this.item.ownerName,
                item: this.item
            }
        }));
    }

    handleSave(event) {
        event.stopPropagation();
        this.isSaved = !this.isSaved;

        this.dispatchEvent(new CustomEvent('itemsave', {
            detail: {
                itemId: this.item.id,
                isSaved: this.isSaved,
                item: this.item
            }
        }));
    }

    // Report functionality
    @api
    showReportModal() {
        const reportModal = this.template.querySelector('c-fimby-report-content');
        if (reportModal) {
            reportModal.show(this.item.id, 'Library_Item');
        }
    }

    handleReportSubmitted(event) {
        this.dispatchEvent(new CustomEvent('contentreported', {
            detail: {
                contentId: event.detail.contentId,
                reason: event.detail.reason
            }
        }));
    }
}