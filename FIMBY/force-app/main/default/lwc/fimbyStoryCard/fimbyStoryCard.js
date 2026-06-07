import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { completeImageUrl } from 'c/fimbyImageUrl';

export default class FimbyStoryCard extends NavigationMixin(LightningElement) {
    @api storyId;
    @api storyTitle;
    @api storyMessage;
    @api storyType;
    @api storyAuthor;
    @api storyAuthorId;
    @api storyAuthorAvatar;
    @api storyImageUrl;
    @api createdDate;
    @api likeCount = 0;
    @api commentCount = 0;
    @api prayerCount = 0;
    @api isLiked = false;
    @api showQuickComment = false;
    @api showTags = false;
    @api tags = [];
    @api currentUserAvatar;
    @api currentUserId;

    @track quickCommentText = '';
    @track recentLikes = [];
    @track previewComments = [];
    @track showImageOverlay = false;
    @track showCommentModal = false;

    // Getter for recordId (alias for storyId, used by child components)
    get recordId() {
        return this.storyId;
    }

    get processedStoryImageUrl() {
        return completeImageUrl(this.storyImageUrl);
    }

    get formattedStoryType() {
        const typeMap = {
            'Thank You': '💝 Thank You',
            'God Story': '✨ God Story',
            'Prayer': '🙏 Prayer Request',
            'Bio': '👋 Introduction',
            'Lament': '💙 Support Needed',
            'Neighbourhood Moment': '🌷 Neighbourhood'
        };
        return typeMap[this.storyType] || this.storyType;
    }

    get formattedTime() {
        if (!this.createdDate) return '';

        const now = new Date();
        const time = new Date(this.createdDate);
        const diff = now - time;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(diff / 3600000);
        const days = Math.floor(diff / 86400000);

        if (minutes < 1) return 'Just now';
        if (minutes < 60) return `${minutes}m ago`;
        if (hours < 24) return `${hours}h ago`;
        if (days < 7) return `${days}d ago`;

        return time.toLocaleDateString();
    }

    get likeIcon() {
        return this.isLiked ? 'utility:favorite' : 'utility:favorite_alt';
    }

    get likeVariant() {
        return this.isLiked ? 'error' : 'neutral';
    }

    get showLikeLabel() {
        return this.likeCount > 0;
    }

    get likeLabel() {
        return this.likeCount === 1 ? 'like' : 'likes';
    }

    get isPrayerStory() {
        return this.storyType === 'Prayer';
    }

    get isThankYouStory() {
        return this.storyType === 'Thank You';
    }

    get showPrayerLabel() {
        return this.prayerCount > 0;
    }

    get prayerLabel() {
        return this.prayerCount === 1 ? 'prayer' : 'prayers';
    }

    get storyTags() {
        let tagList = [...(this.tags || [])];
        if (this.storyType && !tagList.includes(this.storyType)) {
            tagList.push(this.storyType);
        }
        return tagList;
    }

    get showRecentLikes() {
        return this.recentLikes.length > 0;
    }

    get hasMultipleLikes() {
        return this.recentLikes.length > 1;
    }

    get firstLiker() {
        return this.recentLikes[0]?.name || '';
    }

    get otherLikesCount() {
        return this.recentLikes.length - 1;
    }

    get showCommentsPreview() {
        return this.previewComments.length > 0;
    }

    get hasMoreComments() {
        return this.commentCount > this.previewComments.length;
    }

    connectedCallback() {
        this.loadRecentLikes();
        this.loadPreviewComments();
    }

    // Event Handlers
    _animateReaction(event) {
        const btn = event.currentTarget;
        btn.classList.add('reacting');
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => btn.classList.remove('reacting'), 400);
    }

    handleLikeClick(event) {
        this._animateReaction(event);
        const wasLiked = this.isLiked;
        this.isLiked = !this.isLiked;
        this.likeCount = this.isLiked ? this.likeCount + 1 : this.likeCount - 1;

        const likeEvent = new CustomEvent('storylike', {
            detail: {
                storyId: this.storyId,
                isLiked: this.isLiked,
                likeCount: this.likeCount
            }
        });
        this.dispatchEvent(likeEvent);

        // Update recent likes
        if (this.isLiked) {
            this.addCurrentUserToRecentLikes();
        } else {
            this.removeCurrentUserFromRecentLikes();
        }
    }

    handleCommentClick() {
        // Show comment modal instead of navigating
        this.showCommentModal = true;

        // Wait for render then show the modal
        setTimeout(() => {
            const commentComposer = this.template.querySelector('c-fimby-comment-composer');
            if (commentComposer) {
                commentComposer.show(this.storyId);
            }
        }, 0);
    }

    handleCommentModalClose() {
        this.showCommentModal = false;
    }

    handleCommentPosted(event) {
        // Update comment count
        this.commentCount++;
        this.showCommentModal = false;

        // Dispatch event to parent if needed
        const commentEvent = new CustomEvent('storycomment', {
            detail: {
                storyId: this.storyId,
                commentId: event.detail.commentId
            }
        });
        this.dispatchEvent(commentEvent);
    }

    handleShareClick() {
        const shareEvent = new CustomEvent('storyshare', {
            detail: {
                storyId: this.storyId,
                storyTitle: this.storyTitle,
                storyAuthor: this.storyAuthor
            }
        });
        this.dispatchEvent(shareEvent);
    }

    handlePrayerClick(event) {
        this._animateReaction(event);
        this.prayerCount = this.prayerCount + 1;

        const prayerEvent = new CustomEvent('storypray', {
            detail: {
                storyId: this.storyId,
                prayerCount: this.prayerCount
            }
        });
        this.dispatchEvent(prayerEvent);
    }

    handleThankClick(event) {
        this._animateReaction(event);
        const thankEvent = new CustomEvent('storythank', {
            detail: {
                storyId: this.storyId,
                authorId: this.storyAuthorId
            }
        });
        this.dispatchEvent(thankEvent);
    }

    handleMenuClick() {
        const menuEvent = new CustomEvent('storymenu', {
            detail: {
                storyId: this.storyId,
                isOwnStory: this.storyAuthorId === this.currentUserId
            }
        });
        this.dispatchEvent(menuEvent);
    }

    // Report functionality
    showReportModal() {
        const reportModal = this.template.querySelector('c-fimby-report-content');
        if (reportModal) {
            reportModal.show(this.storyId, 'Story');
        }
    }

    handleReportSubmitted(event) {
        // Dispatch event to parent for toast/notification
        this.dispatchEvent(new CustomEvent('contentreported', {
            detail: {
                contentId: event.detail.contentId,
                reason: event.detail.reason
            }
        }));
    }

    handleImageClick() {
        // Open image in modal/full view
        const imageEvent = new CustomEvent('storyimageclick', {
            detail: {
                imageUrl: this.storyImageUrl,
                storyTitle: this.storyTitle
            }
        });
        this.dispatchEvent(imageEvent);
    }

    handleTagClick(event) {
        const tag = event.currentTarget.dataset.tag;
        const tagEvent = new CustomEvent('storytagclick', {
            detail: { tag: tag }
        });
        this.dispatchEvent(tagEvent);
    }

    handleQuickCommentChange(event) {
        this.quickCommentText = event.target.value;
    }

    handleQuickCommentKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSendQuickComment();
        }
    }

    handleSendQuickComment() {
        if (!this.quickCommentText.trim()) return;

        const commentEvent = new CustomEvent('storycomment', {
            detail: {
                storyId: this.storyId,
                commentText: this.quickCommentText.trim()
            }
        });
        this.dispatchEvent(commentEvent);

        // Clear input and add to preview
        this.addCommentToPreview(this.quickCommentText.trim());
        this.quickCommentText = '';
        this.commentCount++;
    }

    handleViewAllComments() {
        this.navigateToStoryDetail('comments');
    }

    // Helper Methods
    navigateToStoryDetail(focus = '') {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.storyId,
                objectApiName: 'Story__c',
                actionName: 'view'
            },
            state: { focus: focus }
        });
    }

    addCurrentUserToRecentLikes() {
        // Add current user to front of recent likes
        const currentUserLike = {
            id: this.currentUserId,
            name: 'You',
            avatar: this.currentUserAvatar
        };

        this.recentLikes = [currentUserLike, ...this.recentLikes.slice(0, 4)];
    }

    removeCurrentUserFromRecentLikes() {
        this.recentLikes = this.recentLikes.filter(like => like.id !== this.currentUserId);
    }

    addCommentToPreview(commentText) {
        const newComment = {
            id: Date.now().toString(),
            authorName: 'You',
            authorAvatar: this.currentUserAvatar,
            text: commentText,
            createdDate: new Date()
        };

        this.previewComments = [...this.previewComments.slice(-2), newComment];
    }

    loadRecentLikes() {
        // Mock recent likes data
        this.recentLikes = [
            { id: '1', name: 'Sarah J.', avatar: '/resource/avatar1.jpg' },
            { id: '2', name: 'Mike C.', avatar: '/resource/avatar2.jpg' },
            { id: '3', name: 'Emma W.', avatar: '/resource/avatar3.jpg' }
        ].slice(0, Math.min(this.likeCount, 3));
    }

    loadPreviewComments() {
        // Mock preview comments
        if (this.commentCount > 0) {
            this.previewComments = [
                {
                    id: '1',
                    authorName: 'Lisa M.',
                    authorAvatar: '/resource/avatar4.jpg',
                    text: 'This is so inspiring! Thank you for sharing.',
                    createdDate: new Date()
                }
            ].slice(0, Math.min(this.commentCount, 2));
        }
    }

    @api
    updateLikeCount(count, isLiked) {
        this.likeCount = count;
        this.isLiked = isLiked;
    }

    @api
    updateCommentCount(count) {
        this.commentCount = count;
    }
}