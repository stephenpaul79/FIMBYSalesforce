import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fireErrorToast } from 'c/fimbyToastHelper';
import { navigate } from 'c/fimbyNavigation';

// Static resources
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import MEMES1 from '@salesforce/resourceUrl/Memes1';
import MEMES2 from '@salesforce/resourceUrl/Memes2';

// Apex methods
import createStory from '@salesforce/apex/FimbyStoriesController.createStory';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

const MEME_GIFS = [
    { resource: 'MEMES1', file: 'ohyeahdance.gif' },
    { resource: 'MEMES1', file: 'Oprah.gif' },
    { resource: 'MEMES1', file: 'TomHanks.gif' },
    { resource: 'MEMES1', file: 'YouDidIt.gif' },
    { resource: 'MEMES2', file: 'FingerHeart.gif' },
    { resource: 'MEMES2', file: 'NailedIt.gif' },
    { resource: 'MEMES2', file: 'Proud.gif' },
    { resource: 'MEMES2', file: 'SpongeBob.gif' },
    { resource: 'MEMES2', file: 'Superstar.gif' }
];

export default class FimbyStoryComposer extends NavigationMixin(LightningElement) {
    // Form state
    @track selectedStoryType = '';
    @track storyTitle = '';
    @track storyMessage = '';
    @track shareOnSocial = false;

    // UI State
    @track isPosting = false;
    @track showPhotoStep = false;
    @track showSuccess = false;
    @track createdStoryId = '';
    @track _preloadedGifUrl = null;
    @track actingAsContact = null;
    @track hasMultipleIdentities = false;

    _preloadTriggered = false;

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

    get actingAsName() {
        return this.actingAsContact?.postingAsDisplayName || this.actingAsContact?.actingAsContactName || '';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    // ============================================
    // SECTION HEADER ICONS
    // ============================================

    get storyTypeIconUrl() {
        return `${IMPACT_ICONS}/StoriesActive.png`;
    }

    get storyDetailsIconUrl() {
        return `${IMPACT_ICONS}/BulletinBoardActive.png`;
    }

    get optionsIconUrl() {
        return `${IMPACT_ICONS}/gear.png`;
    }

    // ============================================
    // STORY TYPES CONFIGURATION (with Impact_Icons)
    // ============================================

    get storyTypesList() {
        const types = [
            { value: 'Thank You',            label: 'Thank You',            description: 'Express gratitude to someone',   icon: 'ThankYouActive.png' },
            { value: 'God Story',            label: 'God Story',            description: 'Share a faith experience',       icon: 'GodStoryActive.png' },
            { value: 'Prayer',               label: 'Prayer Request',       description: 'Ask for prayers and support',    icon: 'PrayActive.png' },
            { value: 'Bio',                  label: 'Introduction',         description: 'Introduce yourself to neighbors',icon: 'BioActive.png' },
            { value: 'Lament',               label: 'Support Needed',       description: 'Share struggles, seek comfort',  icon: 'LamentActive.png' },
            { value: 'Neighbourhood Moment', label: 'Neighbourhood Moment', description: 'Share a moment you noticed',     icon: 'tulips.png' }
        ];
        return types.map((t) => {
            const selected = this.selectedStoryType === t.value;
            return {
                value: t.value,
                label: t.label,
                description: t.description,
                iconUrl: `${IMPACT_ICONS}/${t.icon}`,
                selected,
                cssClass: selected ? 'story-type active' : 'story-type'
            };
        });
    }

    _scrollTop() {
        const reduced = typeof window !== 'undefined'
            && window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        window.scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' });
    }

    // ============================================
    // COMPUTED PROPERTIES
    // ============================================

    get showForm() {
        return !this.showPhotoStep && !this.showSuccess;
    }

    get storyTitleCharacterCount() {
        return `${this.storyTitle.length}/80`;
    }

    get messageCharacterCount() {
        return `${this.storyMessage.length}/2000`;
    }

    get titleCountClass() {
        const len = this.storyTitle.length;
        if (len >= 80) return 'character-count at-limit';
        if (len >= 72) return 'character-count near-limit';
        return 'character-count';
    }

    get messageCountClass() {
        const len = this.storyMessage.length;
        if (len >= 2000) return 'character-count at-limit';
        if (len >= 1800) return 'character-count near-limit';
        return 'character-count';
    }

    get isPostDisabled() {
        return !this.selectedStoryType || !this.storyTitle.trim() ||
               !this.storyMessage.trim() || this.isPosting;
    }

    get submitLabel() {
        return this.isPosting ? 'Submitting...' : 'Next';
    }

    // ============================================
    // EVENT HANDLERS - Form
    // ============================================

    handleTypeSelection(event) {
        this.selectedStoryType = event.currentTarget.dataset.type;
        this._preloadMemeGif();
    }

    _preloadMemeGif() {
        if (this._preloadTriggered) return;
        this._preloadTriggered = true;
        const entry = MEME_GIFS[Math.floor(Math.random() * MEME_GIFS.length)];
        const baseUrl = entry.resource === 'MEMES1' ? MEMES1 : MEMES2;
        const url = `${baseUrl}/${entry.file}`;
        this._preloadedGifUrl = url;
        const img = new Image();
        img.src = url;
    }

    handleTitleChange(event) {
        this.storyTitle = event.target.value;
    }

    handleMessageChange(event) {
        this.storyMessage = event.target.value;
    }

    handleShareOnSocialChange(event) {
        this.shareOnSocial = event.detail.checked;
    }

    // ============================================
    // SUBMIT HANDLER
    // ============================================

    async handlePost() {
        if (this.isPostDisabled) return;

        this.isPosting = true;

        try {
            const storyId = await createStory({
                title: this.storyTitle.trim(),
                content: this.storyMessage.trim(),
                category: this.selectedStoryType,
                location: '',
                imageUrl: '',
                shareOnSocial: this.shareOnSocial
            });

            if (storyId) {
                this.createdStoryId = storyId;
                this.showPhotoStep = true;
                this._scrollTop();
            }

        } catch (error) {
            fireErrorToast(error);
        } finally {
            this.isPosting = false;
        }
    }

    handlePhotoUploaded() {
        this.showPhotoStep = false;
        this.showSuccess = true;
        this._scrollTop();
    }

    handleSkipPhoto() {
        this.showPhotoStep = false;
        this.showSuccess = true;
        this._scrollTop();
    }

    handleViewStory() {
        if (this.createdStoryId) {
            navigate(this, '/sharedlife/' + this.createdStoryId);
        }
    }

}