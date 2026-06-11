import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { toExperiencePath } from 'c/fimbyExperienceUrl';
import { decodeHtmlEntities } from 'c/fimbyTextUtils';

export default class FimbyCard extends LightningElement {
    // Layout properties
    @api cardType = 'default'; // default, story, askOffer, library
    @api layout = 'default'; // 'default', 'compact', or 'list'
    @api cardAccentColor = '';  // optional override for left border colour
    @api elevation = 'medium'; // low, medium, high
    @api borderRadius = 'medium'; // small, medium, large
    @api isClickable = false;

    // Compact badge props (rendered inline in compact mode)
    @api badgeLabel = '';
    @api badgeIconUrl = '';
    @api badgeStyle = '';

    // Header properties
    @api showHeader = false;
    @api showAvatar = false;
    @api avatarUrl = '';
    @api userName = '';
    @api timestamp = '';
    @api showMenu = false;

    @track menuOpen = false;

    // Org poster properties
    @api isOrgPoster = false;
    @api posterProfileUrl = '';

    // Media properties (legacy single-image API — still works)
    @api showMedia = false;
    @api imageUrl = '';
    @api imageAlt = '';
    @api imageAspectRatio = '16 / 9';
    @api showImageOverlay = false;
    @api overlayIcon = 'utility:play';

    // Multi-image API: array of { url, ratio, alt }
    @api images = [];

    /**
     * Normalised images array. Prefers the new `images` prop; falls back to
     * the legacy single-image `imageUrl`/`showMedia` props for backward compat.
     */
    get normalizedImages() {
        if (this.images && Array.isArray(this.images) && this.images.length > 0) {
            return this.images.filter(img => img && img.url && img.url.trim() !== '');
        }
        if (this.showMedia && this.imageUrl && this.imageUrl.trim() !== '') {
            return [{ url: this.imageUrl, ratio: null, alt: this.imageAlt || this.title }];
        }
        return [];
    }

    get hasAnyImages() {
        return this.normalizedImages.length > 0;
    }

    get hasMultipleImages() {
        return this.normalizedImages.length > 1;
    }

    get hasSingleImage() {
        return this.normalizedImages.length === 1;
    }

    // Legacy media section: only show when using old API and NO images array
    get showMediaSection() {
        return false; // replaced by showImageGrid
    }

    get showImageGrid() {
        return this.hasAnyImages;
    }

    get showCategoryMediaPlaceholder() {
        return this.cardType === 'library'
            && this.isCondensedLayout
            && !this.hasAnyImages
            && !!this.badgeIconUrl;
    }

    get categoryPlaceholderStyle() {
        const hex = (this.cardAccentColor || '').replace('#', '').trim();
        if (hex.length === 6) {
            const r = parseInt(hex.slice(0, 2), 16);
            const g = parseInt(hex.slice(2, 4), 16);
            const b = parseInt(hex.slice(4, 6), 16);
            if (!Number.isNaN(r) && !Number.isNaN(g) && !Number.isNaN(b)) {
                return `background-color: rgba(${r}, ${g}, ${b}, 0.12);`;
            }
        }
        return 'background-color: var(--fimby-surface-input);';
    }

    // Legacy style kept for backward compat with overlay
    get mediaContainerStyle() {
        return `aspect-ratio: ${this.imageAspectRatio}; max-height: 400px;`;
    }

    /**
     * Horizontal card layout on desktop: image left, content right.
     * Applies to any card with images — the CSS media query gates
     * this to ≥768px so mobile stays stacked.
     */
    get useHorizontalLayout() {
        return this.hasAnyImages;
    }

    // Content properties
    @api title = '';
    @api titleLeadLabel = '';
    @api description = '';
    @api eventDateTime = '';
    @api eventLocation = '';
    @api eventLinkUrl = '';

    get displayTitle() {
        if (!this.title) return '';
        return decodeHtmlEntities(this.title);
    }

    get showTitleLead() {
        return !!this.titleLeadLabel;
    }

    get cardTitleClass() {
        return this.showTitleLead ? 'card-title card-title-with-lead' : 'card-title';
    }

    get titleTextAriaLabel() {
        if (!this.showTitleLead) return null;
        return `${this.titleLeadLabel}: ${this.displayTitle}`;
    }

    get hasEventMeta() {
        return !!(this.eventDateTime || this.eventLocation || this.eventLinkUrl);
    }
    get hasEventLink() {
        return !!this.eventLinkUrl;
    }
    @api truncateDescription = false;
    @api descriptionMaxLines = 3;
    @api showTags = false;
    @api tags = [];
    @api showCustomContent = false;

    // Read-more state
    @track _isExpanded = false;
    @track _needsTruncation = false;

    // Actions properties
    @api showActions = false;
    @api showLike = false;
    @api isLiked = false;
    @api likeCount = 0;
    @api showComment = false;
    @api commentCount = 0;
    @api showShare = false;
    @api showCustomAction = false;
    @api customActionIcon = 'utility:add';
    @api customActionIconUrl = '';
    @api customActionVariant = 'neutral';
    @api customActionLabel = '';

    // Footer
    @api showFooter = false;

    // Built-in response pill (replaces custom-action for feed cards)
    @api responseLabel = '';
    @api responseIconUrl = '';
    @api responsePillClass = '';
    @api engagementCount = 0;
    @api engagementLabel = '';
    @api allocationPills = null;

    @track hasImageError = false;

    get showCardFooter() {
        return !!this.responseLabel;
    }

    get computedResponsePillClass() {
        return this.responsePillClass || 'response-pill';
    }

    get hasAllocationPills() {
        return Array.isArray(this.allocationPills) && this.allocationPills.length > 0;
    }

    get showEngagement() {
        if (this.hasAllocationPills) return false;
        return this.engagementLabel && this.engagementCount != null;
    }

    get engagementText() {
        const count = this.engagementCount || 0;
        const label = this.engagementLabel || '';
        const lower = label.toLowerCase();
        if (count === 0) {
            if (lower === 'going' || lower === 'interested') {
                return `No one ${lower} yet`;
            }
            return `No ${label} yet`;
        }
        if (count === 1) {
            const singular = label.endsWith('s') ? label.slice(0, -1) : label;
            return `1 ${singular}`;
        }
        return `${count} ${label}`;
    }

    get isCompactLayout() {
        return this.layout === 'compact';
    }

    get isListLayout() {
        return this.layout === 'list';
    }

    get isCondensedLayout() {
        return this.isCompactLayout || this.isListLayout;
    }

    get showDefaultHeader() {
        return this.showHeader && !this.isCondensedLayout;
    }

    get showCompactCardMenu() {
        return this.showMenu && this.isCompactLayout;
    }

    get showCompactTitleRow() {
        return this.isCompactLayout && !!this.title;
    }

    get showListCardMenu() {
        return this.showMenu && this.isListLayout;
    }

    get showCompactBadgeRow() {
        return this.isCondensedLayout && (this.badgeLabel || this.hasAllocationPills);
    }

    get showDefaultFooter() {
        return this.showCardFooter && !this.isCondensedLayout;
    }

    get showCompactFooter() {
        return this.isCompactLayout;
    }

    get showListOwnerRow() {
        return this.isListLayout && (
            this.showMenu ||
            !!this.avatarUrl ||
            !!this.userName ||
            !!this.responseLabel
        );
    }

    get imageGridLayout() {
        return this.isListLayout ? 'thumbnail' : 'auto';
    }


    get cardClasses() {
        let classes = ['fimby-card', `card-${this.cardType}`, `elevation-${this.elevation}`, `radius-${this.borderRadius}`];

        if (this.isClickable) {
            classes.push('clickable');
        }

        if (this.cardAccentColor) {
            classes.push('accent-override');
        }

        if (this.isCompactLayout) {
            classes.push('card-compact');
        } else if (this.isListLayout) {
            classes.push('card-list');
        } else if (this.useHorizontalLayout) {
            classes.push('card-horizontal');
        }

        return classes.join(' ');
    }

    get cardStyle() {
        if (this.cardAccentColor) {
            return `border-left-color: ${this.cardAccentColor};`;
        }
        return '';
    }

    get avatarAlt() {
        return this.isOrgPoster
            ? `${this.userName || 'Organization'} logo`
            : `${this.userName || 'User'} profile picture`;
    }

    get avatarWrapperClass() {
        return this.posterProfileUrl ? 'user-avatar clickable-avatar' : 'user-avatar';
    }

    get formattedTimestamp() {
        if (!this.timestamp) return '';

        const now = new Date();
        const time = new Date(this.timestamp);
        const diff = now - time;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(diff / 3600000);
        const days = Math.floor(diff / 86400000);

        if (minutes < 1) return 'Just now';
        if (minutes < 60) return `${minutes}m`;
        if (hours < 24) return `${hours}h`;
        if (days < 7) return `${days}d`;

        return time.toLocaleDateString();
    }

    /* --- Read-more / truncation --------------------------------------- */

    get descriptionClass() {
        if (this.truncateDescription && !this._isExpanded) {
            return 'card-description truncated';
        }
        return 'card-description';
    }

    get descriptionStyle() {
        if (this.truncateDescription && !this._isExpanded) {
            const lines = this._isDesktopHorizontal() ? 10 : this.descriptionMaxLines;
            return `-webkit-line-clamp: ${lines};`;
        }
        return '';
    }

    _isDesktopHorizontal() {
        return this.useHorizontalLayout && typeof window !== 'undefined' && window.innerWidth >= 768;
    }

    get showReadMore() {
        return this.truncateDescription && this._needsTruncation;
    }

    get readMoreLabel() {
        return this._isExpanded ? 'Show Less' : 'Read More';
    }

    handleReadMoreClick(event) {
        if (this._isDesktopHorizontal()) {
            // Let native click bubble to feed wrapper for navigation
            return;
        }
        event.stopPropagation();
        this._isExpanded = !this._isExpanded;
    }

    renderedCallback() {
        if (this.truncateDescription && this.description) {
            const el = this.template.querySelector('.card-description');
            if (el) {
                const newVal = el.scrollHeight > el.clientHeight || this._isExpanded;
                if (this._needsTruncation !== newVal) {
                    this._needsTruncation = newVal;
                }
            }
        }
    }

    get likeIcon() {
        return this.isLiked ? 'utility:favorite' : 'utility:favorite_alt';
    }

    get likeVariant() {
        return this.isLiked ? 'error' : 'neutral';
    }

    // Event handlers
    handleAvatarClick(event) {
        if (!this.posterProfileUrl) return;
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('avatarclick', {
            detail: { url: toExperiencePath(this.posterProfileUrl) || this.posterProfileUrl }
        }));
    }

    handleAvatarKeydown(event) {
        if (!this.posterProfileUrl) return;
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleAvatarClick(event);
        }
    }

    handleCardClick(event) {
        if (!this.isClickable) return;

        // Don't trigger card navigation when clicking on action buttons, menu, images, avatar links, or footer
        if (event.target.closest('.action-button') ||
            event.target.closest('.card-menu') ||
            event.target.closest('.card-menu-dropdown') ||
            event.target.closest('.card-menu-backdrop') ||
            event.target.closest('.card-media') ||
            event.target.closest('.clickable-avatar') ||
            event.target.closest('.card-footer-bar') ||
            event.target.closest('.card-footer-compact') ||
            event.target.closest('.list-owner-row')) {
            return;
        }

        const clickEvent = new CustomEvent('cardclick', {
            bubbles: true,
            composed: true,
            detail: {
                cardType: this.cardType,
                title: this.title,
                userName: this.userName
            }
        });
        this.dispatchEvent(clickEvent);
    }

    get reportIconUrl() {
        return `${IMPACT_ICONS}/warning.png`;
    }

    get showMenuDropdown() {
        return this.showMenu && this.menuOpen;
    }

    handleMenuClick(event) {
        event.stopPropagation();
        this.menuOpen = !this.menuOpen;
    }

    handleMenuBackdropClick(event) {
        event.stopPropagation();
        this.menuOpen = false;
    }

    handleReportClick(event) {
        event.stopPropagation();
        this.menuOpen = false;
        this.dispatchEvent(new CustomEvent('cardreport', {
            bubbles: true,
            composed: true,
            detail: {
                cardType: this.cardType,
                title: this.title
            }
        }));
    }

    handleLikeClick(event) {
        event.stopPropagation();

        // Toggle like state
        this.isLiked = !this.isLiked;
        this.likeCount = this.isLiked ? this.likeCount + 1 : this.likeCount - 1;

        const likeEvent = new CustomEvent('cardlike', {
            detail: {
                isLiked: this.isLiked,
                likeCount: this.likeCount,
                cardType: this.cardType
            }
        });
        this.dispatchEvent(likeEvent);
    }

    handleCommentClick(event) {
        event.stopPropagation();
        const commentEvent = new CustomEvent('cardcomment', {
            detail: {
                cardType: this.cardType,
                title: this.title
            }
        });
        this.dispatchEvent(commentEvent);
    }

    handleShareClick(event) {
        event.stopPropagation();
        const shareEvent = new CustomEvent('cardshare', {
            detail: {
                cardType: this.cardType,
                title: this.title,
                description: this.description
            }
        });
        this.dispatchEvent(shareEvent);
    }

    handleCustomAction(event) {
        event.stopPropagation();
        const customEvent = new CustomEvent('cardcustomaction', {
            detail: {
                cardType: this.cardType,
                customActionIcon: this.customActionIcon
            }
        });
        this.dispatchEvent(customEvent);
    }

    handleResponseClick(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('cardrespond', {
            detail: { cardType: this.cardType }
        }));
    }

    handleEventLinkClick(event) {
        event.stopPropagation();
    }

    handleImageGridClick(event) {
        event.stopPropagation();
        const detail = event.detail;
        this.dispatchEvent(new CustomEvent('imageclick', {
            detail: {
                index: detail.index,
                images: this.normalizedImages,
                cardType: this.cardType
            },
            bubbles: true,
            composed: true
        }));
    }

    handleImageError(event) {
        this.hasImageError = true;
        event.target.style.display = 'none';
    }

    // Public methods
    @api
    updateLikeCount(count, isLiked = false) {
        this.likeCount = count;
        this.isLiked = isLiked;
    }

    @api
    updateCommentCount(count) {
        this.commentCount = count;
    }

    @api
    setTimestamp(timestamp) {
        this.timestamp = timestamp;
    }
}