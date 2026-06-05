import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';
import getStoryDetail from '@salesforce/apex/FimbyStoriesController.getStoryDetail';
import deleteStory from '@salesforce/apex/FimbyStoriesController.deleteStory';
import getStoryComments from '@salesforce/apex/FimbyStoryCommentController.getStoryComments';
import softDeleteStoryComment from '@salesforce/apex/FimbyStoryCommentController.softDeleteStoryComment';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import { decodeHtmlEntities } from 'c/fimbyTextUtils';
import { getModeratorContext } from 'c/fimbyModeratorContext';
import flagContent from '@salesforce/apex/FimbyModeratorDashboardController.flagContent';
import getOrCreateModeratorConversation from '@salesforce/apex/FimbyModeratorDashboardController.getOrCreateModeratorConversation';

const STORY_SUB_ICONS = {
    'Thank You': 'ThankYouActive.png',
    'God Story': 'GodStoryActive.png',
    'Prayer':    'PrayActive.png',
    'Lament':    'LamentActive.png',
    'Bio':       'BioActive.png',
    'Neighbourhood Moment': 'tulips.png'
};

/**
 * Map of Story Type__c values to FIMBY badge CSS class. Backed by
 * --fimby-badge-* tokens for light/dark mode swap. Replaces the inline
 * ACCENT_COLORS rgba lookup (per the Story LWC rule pass).
 */
const BADGE_CLASSES = {
    'God Story':            'godstory-badge',
    'Thank You':            'thankyou-badge',
    'Lament':               'lament-badge',
    'Prayer':               'prayer-badge',
    'Bio':                  'bio-badge',
    'Neighbourhood Moment': 'neighbourhood-badge'
};

const BADGE_LABELS = {
    'Neighbourhood Moment': 'Neighbourhood'
};

export default class FimbyStoryDetail extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = true;
    @track _extractedRecordId = null;
    @track showImageModal = false;
    @track isContentExpanded = false;
    @track comments = [];
    @track isLoadingComments = false;
    @track showPhotoUploader = false;
    @track showDeleteConfirm = false;
    @track isDeleting = false;
    @track _isModeratorForNeighbourhood = false;
    @track isRemoved = false;
    @track removedMessage = '';

    // Identity (real Contact and acting-as Contact). Powers the
    // author dual-check (Contact__c === realContactId OR Posted_By__c === actingAsContactId).
    @track realContactId = null;
    @track actingAsContactId = null;

    // Per-comment menu state. Only one open at a time.
    @track openCommentMenuId = null;

    // Per-comment delete-confirmation modal state.
    @track pendingDeleteCommentId = null;
    @track isDeletingComment = false;

    record;
    currentUserId = Id;
    organizationId = null;
    _wiredStoryDetailResult;

    contentCharLimit = 300;

    get commentIconUrl() {
        return `${IMPACT_ICONS}/comment.png`;
    }

    get menuIconUrl() {
        return `${IMPACT_ICONS}/KebabBeige.png`;
    }

    get headerMenuItems() {
        if (this.isAuthor) {
            return [
                { key: 'edit', label: 'Edit', icon: 'edit.png', display: 'responsive' },
                { key: 'photo', label: 'Photo', icon: 'photo.png', display: 'responsive' },
                { key: 'delete', label: 'Delete', icon: 'trash.png', display: 'responsive', variant: 'danger' }
            ];
        }
        const items = [
            { key: 'flag', label: 'Flag for follow-up', icon: 'warning.png', display: 'kebab' }
        ];
        if (this._isModeratorForNeighbourhood) {
            items.push(
                { key: 'mod-flag', label: 'Review as Moderator', icon: 'analysis.png', display: 'kebab' },
                { key: 'mod-hide', label: 'Hide Content', icon: 'protection.png', display: 'kebab' },
                { key: 'mod-contact', label: 'Contact Author', icon: 'chat.png', display: 'kebab' }
            );
        }
        return items;
    }

    handleHeaderMenuAction(event) {
        const actions = {
            edit: () => this.handleEdit(),
            photo: () => this.handleUploadPhoto(),
            delete: () => this.handleDeleteClick(),
            flag: () => this.handleFlag(),
            'mod-flag': () => this._handleModeratorFlag(),
            'mod-hide': () => this._handleModeratorHide(),
            'mod-contact': () => this._handleModeratorContact()
        };
        const handler = actions[event.detail.key];
        if (handler) handler();
    }

    async connectedCallback() {
        await this.loadOrganizationId();
        await this.loadIdentity();

        if (!this.recordId || this.recordId.trim() === '') {
            this._extractedRecordId = this.extractRecordIdFromUrl();
        }
        this._checkModeratorStatus();
    }

    async loadIdentity() {
        try {
            const ident = await getActingAsContact();
            if (ident && ident.success) {
                this.realContactId = ident.contactId || null;
                this.actingAsContactId = ident.actingAsContactId || ident.contactId || null;
            }
        } catch (e) {
            // Quiet: feed/detail still works without identity (no edit/delete affordance)
        }
    }

    async _checkModeratorStatus() {
        try {
            const ctx = await getModeratorContext();
            this._isModeratorForNeighbourhood = ctx.isModerator;
        } catch (e) { /* noop */ }
    }

    async loadOrganizationId() {
        try {
            this.organizationId = await getOrganizationId();
            if (this.comments && this.comments.length) {
                this.comments = this.comments.map(c => this.decorateComment(c));
            }
        } catch (error) {
            // Image URLs fall back to base path without org suffix
        }
    }

    // Effective record ID - either from @api or extracted from URL
    get effectiveRecordId() {
        const id = this.recordId || this._extractedRecordId;
        return id;
    }

    // Extract record ID from URL path (/story/{recordId}) or query param (?recordId=xxx)
    extractRecordIdFromUrl() {
        try {
            const url = new URL(window.location.href);

            const queryRecordId = url.searchParams.get('recordId');
            if (queryRecordId) {
                return queryRecordId;
            }

            const pathParts = url.pathname.split('/').filter(part => part && part !== 's');
            const prefixIndex = pathParts.findIndex(part => part === 'sharedlife' || part === 'story');
            if (prefixIndex !== -1 && pathParts.length > prefixIndex + 1) {
                const potentialId = pathParts[prefixIndex + 1];
                if (potentialId && /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(potentialId)) {
                    return potentialId;
                }
            }

            const lastSegment = pathParts[pathParts.length - 1];
            if (lastSegment && (lastSegment.length === 15 || lastSegment.length === 18)) {
                return lastSegment;
            }

            return null;
        } catch (e) {
            return null;
        }
    }

    @wire(getStoryDetail, { storyId: '$effectiveRecordId' })
    wiredStoryDetail(result) {
        this._wiredStoryDetailResult = result;
        const { error, data } = result;
        this.isLoading = false;
        if (data) {
            if (data.removed) {
                this.isRemoved = true;
                this.removedMessage = data.message || 'This story is no longer available.';
                this.record = null;
                return;
            }
            this.isRemoved = false;
            this.removedMessage = '';
            this.record = data.story;
            this.loadComments();
        }
        if (error) {
            this.isRemoved = true;
            this.removedMessage = 'This story is no longer available.';
            this.record = null;
        }
    }

    async loadComments() {
        if (!this.effectiveRecordId) {
            return;
        }

        this.isLoadingComments = true;
        try {
            const result = await getStoryComments({ storyId: this.effectiveRecordId });

            if (result && result.length > 0) {
                this.comments = result.map(comment => this.decorateComment(comment));
            } else {
                this.comments = [];
            }
        } catch (error) {
            // Quiet: empty-state copy explains the missing data path
        } finally {
            this.isLoadingComments = false;
        }
    }

    decorateComment(comment) {
        const editCount = Number(comment.editCount || 0);
        const canManage = !!comment.isAuthor;
        return {
            ...comment,
            authorPhotoUrl: this._completeImageUrl(comment.authorPhotoUrl),
            formattedDate: this.formatCommentDate(comment.createdDate),
            isEdited: editCount > 0,
            editedSuffix: editCount > 0 ? ' · edited' : '',
            canManage,
            canReport: !canManage,
            menuOpen: this.openCommentMenuId === comment.id,
            menuContainerClass: this.openCommentMenuId === comment.id
                ? 'comment-menu-container is-open'
                : 'comment-menu-container'
        };
    }

    _completeImageUrl(url) {
        if (!url) return '';
        if (this.organizationId && !url.includes(this.organizationId)) {
            return url + this.organizationId;
        }
        return url;
    }

    formatCommentDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / (1000 * 60));
        const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

        if (diffMins < 1) return 'Just now';
        if (diffMins < 60) return `${diffMins}m ago`;
        if (diffHours < 24) return `${diffHours}h ago`;
        if (diffDays < 7) return `${diffDays}d ago`;
        return date.toLocaleDateString();
    }

    get commentCount() {
        return this.comments.length;
    }

    get hasComments() {
        return this.comments.length > 0;
    }

    get storyName() {
        const raw = this.record ? this.record.Name : '';
        return decodeHtmlEntities(raw);
    }

    get message() {
        const raw = this.record ? this.record.Message__c : '';
        return decodeHtmlEntities(raw);
    }

    // Check if message is long enough to need truncation
    get isLongContent() {
        return this.message && this.message.length > this.contentCharLimit;
    }

    // Get truncated or full message based on expansion state
    get displayMessage() {
        if (!this.message) return '';

        if (this.isContentExpanded || !this.isLongContent) {
            return this.message;
        }

        // Truncate at word boundary
        const truncated = this.message.substring(0, this.contentCharLimit);
        const lastSpace = truncated.lastIndexOf(' ');
        return (lastSpace > 0 ? truncated.substring(0, lastSpace) : truncated) + '...';
    }

    // Show "Read more" only if content is long and not expanded
    get showReadMore() {
        return this.isLongContent && !this.isContentExpanded;
    }

    // Show "Show less" only if content is expanded
    get showReadLess() {
        return this.isLongContent && this.isContentExpanded;
    }

    // Construct complete image URL with Organization ID
    get imageUrl() {
        const baseUrl = this.record ? this.record.Image_URL__c : '';
        if (!baseUrl) return '';

        // Append Organization ID to complete the URL (pattern: URL ends with &oid=)
        if (this.organizationId && !baseUrl.includes(this.organizationId)) {
            return baseUrl + this.organizationId;
        }
        return baseUrl;
    }

    // Check if image exists
    get hasImage() {
        const baseUrl = this.record ? this.record.Image_URL__c : '';
        return !!baseUrl && baseUrl.trim() !== '';
    }

    // Get image aspect ratio from Image_Ratio__c (format: "WIDTHxHEIGHT")
    get imageAspectRatio() {
        const ratioString = this.record ? this.record.Image_Ratio__c : '';
        if (!ratioString) return '16 / 9'; // Default

        try {
            const parts = ratioString.toUpperCase().split('X');
            const width = parseInt(parts[0], 10);
            const height = parseInt(parts[1], 10);

            if (isNaN(width) || isNaN(height) || width <= 0 || height <= 0) {
                return '16 / 9';
            }
            return `${width} / ${height}`;
        } catch (e) {
            return '16 / 9';
        }
    }

    // Style for image container with dynamic aspect ratio
    get imageContainerStyle() {
        return `aspect-ratio: ${this.imageAspectRatio}; max-height: 500px;`;
    }

    get detailPageTitle() {
        const type = this.record ? this.record.Type__c : '';
        return type || 'Story Details';
    }

    get category() {
        return this.record ? this.record.Type__c : '';
    }

    get hasBadge() {
        return !!this.category;
    }

    get badgeLabel() {
        return BADGE_LABELS[this.category] || this.category;
    }

    get badgeIconUrl() {
        const icon = STORY_SUB_ICONS[this.category];
        if (icon) return `${IMPACT_ICONS}/${icon}`;
        return `${IMPACT_ICONS}/StoriesActive.png`;
    }

    get badgeClass() {
        const tokenClass = BADGE_CLASSES[this.category] || 'story-badge';
        return `card-type-badge ${tokenClass}`;
    }

    get authorName() {
        if (!this.record || !this.record.Posted_By__r) return '';
        // Try Full_Name__c first, fall back to Name
        return this.record.Posted_By__r.Full_Name__c ||
               this.record.Posted_By__r.Name || '';
    }

    // Construct complete avatar URL with Organization ID
    get authorAvatar() {
        const baseUrl = this.record && this.record.Posted_By__r ? this.record.Posted_By__r.Image_URL__c : '';
        if (!baseUrl) return '';

        if (this.organizationId && !baseUrl.includes(this.organizationId)) {
            return baseUrl + this.organizationId;
        }
        return baseUrl;
    }

    get formattedDate() {
        if (!this.record) return '';
        const date = this.record.CreatedDate;
        if (!date) return '';

        // Format as relative time or date
        const now = new Date();
        const posted = new Date(date);
        const diffMs = now - posted;
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

        if (diffDays === 0) {
            const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
            if (diffHours === 0) {
                const diffMins = Math.floor(diffMs / (1000 * 60));
                return diffMins <= 1 ? 'Just now' : `${diffMins} minutes ago`;
            }
            return diffHours === 1 ? '1 hour ago' : `${diffHours} hours ago`;
        } else if (diffDays === 1) {
            return 'Yesterday';
        } else if (diffDays < 7) {
            return `${diffDays} days ago`;
        }

        return posted.toLocaleDateString();
    }


    // True when the viewer is the author of THIS story under the FIMBY
    // dual-stamping model: real Contact wrote it OR they are the represented
    // identity it was posted as. Uses Contact Ids, not the running User Id.
    get isAuthor() {
        if (!this.record) return false;
        const realMatch = this.realContactId && this.record.Contact__c === this.realContactId;
        const actingMatch = this.actingAsContactId && this.record.Posted_By__c === this.actingAsContactId;
        return !!(realMatch || actingMatch);
    }

    handleBack() {
        // Go back in history or navigate to stories page
        if (window.history.length > 1) {
            window.history.back();
        } else {
            this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'home' }});
        }
    }

    handleEdit() {
        if (!this.isAuthor) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Only the post owner can edit this',
                message: 'You can only edit stories you have posted.',
                variant: 'warning'
            }));
            return;
        }

        const modal = this.template.querySelector('c-fimby-record-edit-modal');
        if (modal) modal.show();
    }

    async handleEditSave() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Saved',
            message: 'Your story is updated.',
            variant: 'success'
        }));
        if (this._wiredStoryDetailResult) {
            await refreshApex(this._wiredStoryDetailResult);
        }
    }

    handleEditCancel() {}

    handleUploadPhoto() {
        this.showPhotoUploader = true;
    }

    handleClosePhotoUploader() {
        this.showPhotoUploader = false;
    }

    handlePhotoUploaded() {
        this.showPhotoUploader = false;
        this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Your photo is updated.', variant: 'success' }));
        window.location.reload();
    }

    handleDeleteClick() {
        this.showDeleteConfirm = true;
    }

    handleDeleteCancel() {
        this.showDeleteConfirm = false;
    }

    async handleDeleteConfirm() {
        this.isDeleting = true;
        try {
            await deleteStory({ storyId: this.effectiveRecordId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Removed', message: 'Your story has been removed.', variant: 'success' }));
            window.location.href = '/my-stuff/my-shared-life';
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Something went sideways',
                message: err?.body?.message || 'We could not remove the story. Try again in a moment.',
                variant: 'error'
            }));
        } finally {
            this.isDeleting = false;
            this.showDeleteConfirm = false;
        }
    }

    handleFlag() {
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) modal.show(this.effectiveRecordId, 'Story__c');
    }

    handleComment() {
        const composer = this.template.querySelector('c-fimby-comment-composer');
        if (composer) {
            composer.show(this.effectiveRecordId);
        }
    }

    handleCommentPosted() {
        this.loadComments();
    }

    handleCommentClose() {
        // Reserved: ensures any parent listeners can hook in
    }

    // ============================================
    // COMMENT PER-ROW MENU + ACTIONS
    // ============================================

    handleCommentMenuToggle(event) {
        const commentId = event.currentTarget.dataset.commentId;
        if (!commentId) return;
        this.openCommentMenuId = this.openCommentMenuId === commentId ? null : commentId;
        this.comments = this.comments.map(c => this.decorateComment(c));
    }

    closeCommentMenu() {
        if (this.openCommentMenuId !== null) {
            this.openCommentMenuId = null;
            this.comments = this.comments.map(c => this.decorateComment(c));
        }
    }

    handleCommentEdit(event) {
        const commentId = event.currentTarget.dataset.commentId;
        const comment = this.comments.find(c => c.id === commentId);
        this.closeCommentMenu();
        if (!comment) return;
        const composer = this.template.querySelector('c-fimby-comment-composer');
        if (composer) {
            composer.show(this.effectiveRecordId, commentId, comment.body || '');
        }
    }

    handleCommentReport(event) {
        const commentId = event.currentTarget.dataset.commentId;
        this.closeCommentMenu();
        if (!commentId) return;
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) modal.show(commentId, 'Story_Comment__c');
    }

    handleCommentDeleteClick(event) {
        this.pendingDeleteCommentId = event.currentTarget.dataset.commentId;
        this.closeCommentMenu();
    }

    handleCommentDeleteCancel() {
        this.pendingDeleteCommentId = null;
    }

    async handleCommentDeleteConfirm() {
        if (!this.pendingDeleteCommentId) return;
        this.isDeletingComment = true;
        try {
            await softDeleteStoryComment({ commentId: this.pendingDeleteCommentId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Removed',
                message: 'Your comment has been removed.',
                variant: 'success'
            }));
            await this.loadComments();
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Something went sideways',
                message: err?.body?.message || 'We could not remove the comment. Try again in a moment.',
                variant: 'error'
            }));
        } finally {
            this.isDeletingComment = false;
            this.pendingDeleteCommentId = null;
        }
    }

    get showCommentDeleteConfirm() {
        return !!this.pendingDeleteCommentId;
    }

    // Toggle content expansion
    handleToggleContent() {
        this.isContentExpanded = !this.isContentExpanded;
    }

    // Image modal handlers
    handleImageClick() {
        if (this.hasImage) {
            this.showImageModal = true;
            // Prevent body scroll when modal is open
            document.body.style.overflow = 'hidden';
        }
    }

    handleCloseImageModal() {
        this.showImageModal = false;
        // Restore body scroll
        document.body.style.overflow = '';
    }

    // Close modal on escape key
    handleModalKeydown(event) {
        if (event.key === 'Escape') {
            this.handleCloseImageModal();
        }
    }

    handleTabChange(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: event.detail.tab }});
    }

    // ============================================
    // MODERATOR ACTIONS
    // ============================================

    async _handleModeratorFlag() {
        try {
            await flagContent({ recordId: this.effectiveRecordId, recordType: 'Story__c', flagValue: 'Moderator_Review' });
            this.dispatchEvent(new ShowToastEvent({ title: 'Flagged for review', message: 'This story is now under review.', variant: 'success' }));
            window.location.href = '/moderator-dashboard';
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Something went sideways',
                message: error?.body?.message || 'We could not flag this content. Try again in a moment.',
                variant: 'error'
            }));
        }
    }

    async _handleModeratorHide() {
        try {
            await flagContent({ recordId: this.effectiveRecordId, recordType: 'Story__c', flagValue: 'Moderator_Hidden' });
            this.dispatchEvent(new ShowToastEvent({ title: 'Hidden', message: 'This story is no longer in the feed.', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Something went sideways',
                message: error?.body?.message || 'We could not hide this content. Try again in a moment.',
                variant: 'error'
            }));
        }
    }

    async _handleModeratorContact() {
        try {
            const authorContactId = this._getAuthorContactId();
            if (!authorContactId) return;
            const conversationId = await getOrCreateModeratorConversation({ targetContactId: authorContactId });
            window.location.href = `/conversation?id=${conversationId}`;
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Something went sideways',
                message: error?.body?.message || 'We could not open the conversation. Try again in a moment.',
                variant: 'error'
            }));
        }
    }

    _getAuthorContactId() {
        if (!this.record) return null;
        return this.record.Posted_By__c;
    }
}