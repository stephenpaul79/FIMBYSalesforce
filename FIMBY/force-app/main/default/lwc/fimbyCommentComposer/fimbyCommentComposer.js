import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getStoryForComment from '@salesforce/apex/FimbyStoryCommentController.getStoryForComment';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import searchContactsForMention from '@salesforce/apex/FimbyStoryCommentController.searchContactsForMention';
import postStoryComment from '@salesforce/apex/FimbyStoryCommentController.postStoryComment';
import updateStoryComment from '@salesforce/apex/FimbyStoryCommentController.updateStoryComment';

export default class FimbyCommentComposer extends NavigationMixin(LightningElement) {
    @api recordId; // Story__c Id
    @api commentId; // Story_Comment__c Id (edit mode only)
    _recordId = '';
    _commentId = null;

    get activeRecordId() {
        return this._recordId || this.recordId;
    }

    get activeCommentId() {
        return this._commentId ?? this.commentId ?? null;
    }

    // Story display data
    @track storyTitle = '';
    @track storyImageUrl = '';
    @track storyMessage = '';
    @track storyOwnerId = '';
    @track storyOwnerName = '';

    // Acting as contact data
    @track actingAsContactId = '';
    @track actingAsContactName = '';

    // Form state
    @track commentText = '';
    @track isFocused = false;
    @track showCancel = false;
    @track mentionContactIds = []; // Contact Ids resolved from @mentions

    // Mention state
    @track mentionSuggestions = [];
    @track showMentionSuggestions = false;
    @track cursorPosition = 0;

    // Loading/error state
    @track isLoading = true;
    @track isSubmitting = false;
    @track errorMessage = '';

    // Modal state - start hidden, only show when show() is called
    @track isModalMode = true; // Always use modal mode when embedded
    @track _isModalVisible = false;

    // Character limit
    maxCharacters = 1000;

    get showIdentityBanner() {
        return !!this.actingAsContactName;
    }

    get isEditMode() {
        return !!this.activeCommentId;
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit Comment' : 'Add Comment';
    }

    get submitButtonLabel() {
        return this.isEditMode ? 'Save Changes' : 'Post Comment';
    }

    get showStoryContext() {
        return !this.isEditMode && !!this.storyTitle;
    }

    // Modal API methods
    @api
    show(storyId, commentId, existingText) {
        this.isModalMode = true;
        this._isModalVisible = true;
        if (storyId) {
            this._recordId = storyId;
        }
        this._commentId = commentId || null;
        this.commentText = existingText || '';
        this.mentionContactIds = [];
        this.loadInitialData();
    }

    @api
    hide() {
        this._isModalVisible = false;
        this.isModalMode = false;
        this.resetForm();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.hide();
    }

    resetForm() {
        this.commentText = '';
        this.errorMessage = '';
        this.isLoading = false;
        this._commentId = null;
        this.mentionContactIds = [];
    }

    async loadInitialData() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            // Load story data first
            const storyResult = await getStoryForComment({ recordId: this.activeRecordId });

            if (storyResult.success) {
                this.storyTitle = storyResult.story.name || '';
                this.storyImageUrl = storyResult.story.imageUrl || '';
                this.storyMessage = storyResult.story.message || '';
                this.storyOwnerId = storyResult.story.ownerId || '';
                this.storyOwnerName = storyResult.story.ownerName || '';
            } else {
                this.errorMessage = 'Could not load story details.';
                this.isLoading = false;
                return;
            }

            try {
                const contactResult = await getActingAsContact();
                if (contactResult && contactResult.success) {
                    this.actingAsContactId = contactResult.actingAsContactId || contactResult.contactId;
                    this.actingAsContactName = contactResult.postingAsDisplayName
                        || contactResult.actingAsContactName
                        || contactResult.contactName;
                } else {
                    this.actingAsContactName = 'you';
                }
            } catch {
                this.actingAsContactName = 'you';
            }
        } catch (error) {
            this.errorMessage = error.body?.message || 'We could not open the comment form. Try again in a moment.';
        } finally {
            this.isLoading = false;
        }
    }

    // Getters
    get characterCount() {
        return this.commentText.length;
    }

    get characterCountDisplay() {
        return `${this.characterCount}/${this.maxCharacters}`;
    }

    get isNearLimit() {
        return this.characterCount > this.maxCharacters * 0.9;
    }

    get isOverLimit() {
        return this.characterCount >= this.maxCharacters;
    }

    get isSubmitDisabled() {
        return !this.commentText.trim() || this.isOverLimit || this.isSubmitting;
    }

    get hasStoryImage() {
        return this.storyImageUrl && this.storyImageUrl.length > 0;
    }

    get characterCountClass() {
        if (this.isOverLimit) {
            return 'character-count over-limit';
        } else if (this.isNearLimit) {
            return 'character-count near-limit';
        }
        return 'character-count';
    }

    get showForm() {
        return !this.isLoading;
    }

    handleCommentChange(event) {
        this.commentText = event.target.value;
        const inputEl = event.target.querySelector('textarea') || event.target;
        this.cursorPosition = inputEl.selectionStart || this.commentText.length;
        this._lastMentionSearchStart = null;
        this.checkForMentions();
        this.pruneStaleMentions();
    }

    handleInputFocus() {
        this.isFocused = true;
        this.showCancel = true;
    }

    handleInputBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce / delayed UI
        setTimeout(() => {
            if (!this.showMentionSuggestions) {
                this.isFocused = false;
                if (!this.commentText.trim()) {
                    this.showCancel = false;
                }
            }
        }, 200);
    }

    handleCancel() {
        this.commentText = '';
        this.showCancel = false;
        this.isFocused = false;
        this.closeMentionSuggestions();
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) return;

        this.isSubmitting = true;
        this.errorMessage = '';

        try {
            const payload = {
                storyId: this.activeRecordId,
                commentText: this.commentText.trim(),
                commentContactId: this.actingAsContactId || null,
                mentionContactIds: this.mentionContactIds
            };

            let result;
            if (this.isEditMode) {
                payload.commentId = this.activeCommentId;
                result = await updateStoryComment({
                    commentData: JSON.stringify(payload)
                });
            } else {
                result = await postStoryComment({
                    commentData: JSON.stringify(payload)
                });
            }

            if (result && result.success) {
                this.commentText = '';
                this.showCancel = false;

                this.dispatchEvent(new CustomEvent('commentposted', {
                    detail: {
                        storyId: this.activeRecordId,
                        commentId: result.commentId,
                        isEdit: this.isEditMode,
                        editCount: result.editCount,
                        editedDate: result.editedDate
                    }
                }));

                // Success is confirmed by the comment appearing in the parent
                // thread — close the composer immediately (no success banner).
                this.hide();
            } else {
                this.errorMessage = (result && result.message)
                    || (this.isEditMode
                        ? 'We could not save your changes. Try again.'
                        : 'We could not share your comment. Try again.');
            }
        } catch (error) {
            this.errorMessage = error.body?.message
                || (this.isEditMode
                    ? 'We could not save your changes. Try again.'
                    : 'We could not share your comment. Try again.');
        } finally {
            this.isSubmitting = false;
        }
    }

    navigateToStory() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.activeRecordId,
                objectApiName: 'Story__c',
                actionName: 'view'
            }
        });
    }

    handleViewStory() {
        this.navigateToStory();
    }

    checkForMentions() {
        const text = this.commentText;
        const cursorPos = this.cursorPosition || text.length;
        const beforeCursor = text.substring(0, cursorPos);
        const atIndex = beforeCursor.lastIndexOf('@');

        if (atIndex !== -1) {
            const mentionText = beforeCursor.substring(atIndex + 1);
            if (mentionText.indexOf(' ') === -1) {
                this._mentionAtIndex = atIndex;
                this._mentionSearchText = mentionText;
                this.searchPeople(mentionText);
            } else {
                this.closeMentionSuggestions();
            }
        } else {
            this.closeMentionSuggestions();
        }
    }

    async searchPeople(searchTerm) {
        try {
            const results = await searchContactsForMention({ searchTerm: searchTerm });

            if (results && results.length > 0) {
                this.mentionSuggestions = results.map(contact => ({
                    id: contact.id,
                    name: contact.name,
                    neighbourhood: contact.neighbourhood || ''
                }));
                this.showMentionSuggestions = true;
            } else {
                this.closeMentionSuggestions();
            }
        } catch {
            this.closeMentionSuggestions();
        }
    }

    handleMentionSelect(event) {
        const personId = event.currentTarget.dataset.personId;
        const personName = event.currentTarget.dataset.personName;

        this.insertMention(personName);
        this.recordMentionId(personId);
        this.closeMentionSuggestions();
    }

    insertMention(name) {
        const text = this.commentText;
        const atIndex = this._mentionAtIndex;
        const searchText = this._mentionSearchText || '';

        if (atIndex !== undefined && atIndex !== -1) {
            const beforeAt = text.substring(0, atIndex);
            const afterMention = text.substring(atIndex + 1 + searchText.length);
            this.commentText = `${beforeAt}@${name} ${afterMention.trimStart()}`;
            this.cursorPosition = beforeAt.length + name.length + 2;

            this._mentionAtIndex = undefined;
            this._mentionSearchText = undefined;
        }
    }

    recordMentionId(contactId) {
        if (!contactId) return;
        if (this.mentionContactIds.indexOf(contactId) === -1) {
            this.mentionContactIds = [...this.mentionContactIds, contactId];
        }
    }

    /**
     * Keep mentionContactIds aligned with text. If a previously-inserted
     * mention name was removed from the body, drop its id from the list so
     * we don't notify someone who is no longer referenced.
     */
    pruneStaleMentions() {
        // Cheap heuristic: if the @ char count drops to zero, clear mentions.
        if (this.commentText.indexOf('@') === -1) {
            this.mentionContactIds = [];
        }
    }

    closeMentionSuggestions() {
        this.showMentionSuggestions = false;
        this.mentionSuggestions = [];
    }

    @api
    focusInput() {
        const textarea = this.template.querySelector('.comment-textarea');
        if (textarea) {
            textarea.focus();
        }
    }

    @api
    clearInput() {
        this.commentText = '';
        this.showCancel = false;
        this.isFocused = false;
        this.closeMentionSuggestions();
    }
}
