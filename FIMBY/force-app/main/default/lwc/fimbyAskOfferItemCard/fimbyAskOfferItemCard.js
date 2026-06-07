import { LightningElement, api, track } from 'lwc';
import { completeImageUrl } from 'c/fimbyImageUrl';

export default class FimbyAskOfferItemCard extends LightningElement {
    @api item = {};
    @track currentImageIndex = 0;
    @track isSaved = false;

    get currentImage() {
        if (this.item.images && this.item.images.length > 0) {
            return completeImageUrl(this.item.images[this.currentImageIndex]);
        }
        return null;
    }

    get hasMultipleImages() {
        return this.item.images && this.item.images.length > 1;
    }

    get typeIcon() {
        switch (this.item.type?.toLowerCase()) {
            case 'need': return 'utility:help';
            case 'offer': return 'utility:gift';
            case 'service': return 'utility:settings';
            case 'skill': return 'utility:knowledge_base';
            default: return 'utility:apps';
        }
    }

    get typeLabel() {
        return this.item.type || 'Item';
    }

    get statusClass() {
        const status = this.item.status?.toLowerCase();
        switch (status) {
            case 'active': return 'status-badge active';
            case 'pending': return 'status-badge pending';
            case 'fulfilled': return 'status-badge fulfilled';
            case 'expired': return 'status-badge expired';
            default: return 'status-badge';
        }
    }

    get truncatedDescription() {
        if (!this.item.description) return '';
        return this.item.description.length > 120
            ? this.item.description.substring(0, 120) + '...'
            : this.item.description;
    }

    get formattedTime() {
        if (!this.item.createdDate) return '';

        const now = new Date();
        const created = new Date(this.item.createdDate);
        const diff = now - created;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(diff / 3600000);
        const days = Math.floor(diff / 86400000);

        if (minutes < 1) return 'Just now';
        if (minutes < 60) return `${minutes}m ago`;
        if (hours < 24) return `${hours}h ago`;
        if (days < 7) return `${days}d ago`;
        return created.toLocaleDateString();
    }

    get ratingStars() {
        const rating = this.item.posterRating || 0;
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

    get responseIcon() {
        switch (this.item.type?.toLowerCase()) {
            case 'need': return 'utility:help';
            case 'offer': return 'utility:check';
            case 'service': return 'utility:bookmark';
            default: return 'utility:like';
        }
    }

    get responseLabel() {
        switch (this.item.type?.toLowerCase()) {
            case 'need': return 'Help';
            case 'offer': return 'Want';
            case 'service': return 'Book';
            default: return 'Respond';
        }
    }

    get saveIcon() {
        return this.isSaved ? 'utility:bookmark' : 'utility:bookmark_alt';
    }

    get saveButtonClass() {
        return this.isSaved ? 'save-button saved' : 'save-button';
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

    handleImageChange(event) {
        event.stopPropagation();
        this.currentImageIndex = parseInt(event.target.dataset.index, 10);
    }

    handleCardClick(event) {
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

    handleRespond(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('itemrespond', {
            detail: {
                itemId: this.item.id,
                item: this.item,
                action: 'respond'
            }
        }));
    }

    handleMessage(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('itemmessage', {
            detail: {
                itemId: this.item.id,
                posterId: this.item.posterId,
                posterName: this.item.posterName,
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

    @api
    showReportModal() {
        const reportModal = this.template.querySelector('c-fimby-report-content');
        if (reportModal) {
            reportModal.show(this.item.id, 'Need_Offer');
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
