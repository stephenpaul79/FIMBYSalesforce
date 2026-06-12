import { LightningElement, api, track, wire } from 'lwc';
import { completeImageUrl } from 'c/fimbyImageUrl';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getProfileData from '@salesforce/apex/FimbyProfileController.getProfileData';
import createStory from '@salesforce/apex/FimbyStoriesController.createStory';
import useProfilePhotoForStory from '@salesforce/apex/FimbyStoriesController.useProfilePhotoForStory';
import markBioPostCompleted from '@salesforce/apex/FimbyOnboardingController.markBioPostCompleted';

const DEFAULT_TITLE = 'Say hi to your neighbours';
const STORY_TITLE = "Hi neighbours";

export default class FimbyIntroPostModal extends LightningElement {
    @track _isVisible = false;
    @track _isLoading = false;
    @track _isPosting = false;
    @track _showPhotoStep = false;
    @track _showCelebration = false;
    @track _errorMessage = '';
    @track _draftText = '';
    @track _firstName = '';
    @track _createdStoryId = null;
    @track _actingAsName = '';
    @track _hasMultipleIdentities = false;
    @track _profilePhotoUrl = '';
    @track _showFreshUploader = false;
    @track _isApplyingProfilePhoto = false;

    @api
    get isOpen() {
        return this._isVisible;
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this._hasMultipleIdentities = data.length > 0;
        } else if (error) {
            console.error('Error loading identities:', error);
            this._hasMultipleIdentities = false;
        }
    }

    get showIdentityBanner() {
        return this._hasMultipleIdentities && !!this._actingAsName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get postingAsDisplayName() {
        return this._actingAsName;
    }

    @api
    show() {
        this._isVisible = true;
        this._errorMessage = '';
        this._showPhotoStep = false;
        this._showCelebration = false;
        this._createdStoryId = null;
        this._showFreshUploader = false;
        this._isApplyingProfilePhoto = false;
        this._loadDraft();
        document.body.classList.add('fimby-modal-open');
    }

    @api
    hide() {
        this._isVisible = false;
        document.body.classList.remove('fimby-modal-open');
    }

    get showForm() {
        return !this._isLoading && !this._showPhotoStep && !this._showCelebration;
    }

    get storiesIconUrl() {
        return `${IMPACT_ICONS}/StoriesActive.png`;
    }

    get bioIconUrl() {
        return `${IMPACT_ICONS}/BioActive.png`;
    }

    get modalTitle() {
        if (this._showPhotoStep) return 'Add a photo (optional)';
        return DEFAULT_TITLE;
    }

    get modalSubtitle() {
        if (this._showPhotoStep) {
            return 'A photo helps neighbours put a face to the name. You can always add one later.';
        }
        return "Your neighbours will see this in the Shared Life feed. It's how they'll know who's new on the block.";
    }

    get modalHint() {
        if (this._showPhotoStep) return '';
        return 'You can edit it, or skip and do it later.';
    }

    get showModalHint() {
        return !this._showPhotoStep && !this._showCelebration;
    }

    get isPostDisabled() {
        return this._isPosting || !this._draftText || !this._draftText.trim();
    }

    get showProfilePhotoReuse() {
        return this._showPhotoStep && !!this._profilePhotoUrl && !this._showFreshUploader;
    }

    get showPhotoUploader() {
        return this._showPhotoStep && (!this._profilePhotoUrl || this._showFreshUploader);
    }

    get characterCount() {
        return this._draftText ? this._draftText.length : 0;
    }

    async _loadDraft() {
        this._isLoading = true;
        try {
            const [actingAs, profile] = await Promise.all([
                getActingAsContact(),
                getProfileData()
            ]);

            const firstName = profile?.firstName || actingAs?.actingAsContactName?.split(' ')[0] || 'there';
            this._firstName = firstName;
            this._actingAsName = actingAs?.postingAsDisplayName
                || actingAs?.actingAsContactName
                || actingAs?.contactName
                || '';

            this._profilePhotoUrl = completeImageUrl(profile?.imageUrl || '');

            const neighbourhoodName = profile?.neighbourhood || 'this neighbourhood';

            this._draftText = this._composeMadLib({
                firstName,
                pronouns: profile?.pronouns,
                neighbourhoodName,
                tenure: profile?.aboutNeighbourhoodTenure,
                broughtYou: profile?.aboutWhatBroughtYou,
                localPlace: profile?.aboutLocalPlace,
                enjoys: profile?.aboutEnjoysDoing,
                funFact: profile?.aboutFunFact
            });
        } catch (err) {
            console.error('fimbyIntroPostModal: error loading draft', err);
            this._errorMessage = 'We could not pre-fill your intro. You can still write something below.';
            this._draftText = '';
        } finally {
            this._isLoading = false;
        }
    }

    _composeMadLib({ firstName, pronouns, neighbourhoodName, tenure, broughtYou, localPlace, enjoys, funFact }) {
        const lines = [];

        const opener = pronouns
            ? `Hi, I'm ${firstName} (${pronouns}).`
            : `Hi, I'm ${firstName}.`;
        lines.push(opener);

        if (tenure && tenure.trim()) {
            lines.push(`I've lived in ${neighbourhoodName} for ${tenure.trim()}.`);
        } else {
            lines.push(`I'm new to ${neighbourhoodName}.`);
        }

        if (broughtYou && broughtYou.trim()) {
            lines.push(`What brought me here was ${broughtYou.trim()}.`);
        }
        if (localPlace && localPlace.trim()) {
            lines.push(`One spot I love is ${localPlace.trim()}.`);
        }
        if (enjoys && enjoys.trim()) {
            lines.push(`I enjoy ${enjoys.trim()}.`);
        }
        if (funFact && funFact.trim()) {
            lines.push(`A small thing about me: ${funFact.trim()}.`);
        }

        lines.push('Looking forward to meeting you all.');

        // Read as one natural paragraph rather than a list of fragments.
        return lines.join(' ');
    }

    handleTextChange(event) {
        // lightning-textarea's change event exposes the live value via detail.value
        this._draftText = event.detail?.value ?? event.target?.value ?? '';
    }

    async handlePost() {
        if (this.isPostDisabled) {
            return;
        }
        this._isPosting = true;
        this._errorMessage = '';

        try {
            const storyId = await createStory({
                title: STORY_TITLE,
                content: this._draftText,
                category: 'Bio',
                location: null,
                imageUrl: null,
                shareOnSocial: false
            });
            this._createdStoryId = storyId;

            await markBioPostCompleted({ posted: true, storyId });

            // The story is created. Move to the optional photo step (mirrors
            // fimbyStoryComposer). The celebration runs after the photo is
            // uploaded or skipped.
            this._isPosting = false;
            this._showPhotoStep = true;
        } catch (err) {
            console.error('fimbyIntroPostModal: error posting bio', err);
            this._errorMessage = err?.body?.message || err?.message || 'Something went wrong. Try again?';
            this._isPosting = false;
        }
    }

    handlePhotoUploaded() {
        this._goToCelebration();
    }

    async handleUseProfilePhoto() {
        if (this._isApplyingProfilePhoto) {
            return;
        }
        this._isApplyingProfilePhoto = true;
        this._errorMessage = '';
        try {
            await useProfilePhotoForStory({ storyId: this._createdStoryId });
            this._goToCelebration();
        } catch (err) {
            console.error('fimbyIntroPostModal: error reusing profile photo', err);
            this._errorMessage = err?.body?.message || err?.message || 'We could not reuse your photo. Try uploading one instead.';
            this._showFreshUploader = true;
        } finally {
            this._isApplyingProfilePhoto = false;
        }
    }

    handleUploadDifferent() {
        this._showFreshUploader = true;
    }

    handleSkipPhoto() {
        this._goToCelebration();
    }

    _goToCelebration() {
        this._showPhotoStep = false;
        this._showCelebration = true;
        window.setTimeout(() => {
            this._finishPost();
        }, 3500);
    }

    _finishPost() {
        this._isPosting = false;
        this._showPhotoStep = false;
        this._showCelebration = false;
        this.hide();
        this.dispatchEvent(new CustomEvent('bioposted', {
            detail: { storyId: this._createdStoryId }
        }));
    }

    async handleSkip() {
        if (this._isPosting) {
            return;
        }
        this._isPosting = true;
        this._errorMessage = '';

        try {
            await markBioPostCompleted({ posted: false, storyId: null });
        } catch (err) {
            console.error('fimbyIntroPostModal: error flipping skip flag', err);
        } finally {
            this._isPosting = false;
            this.hide();
            this.dispatchEvent(new CustomEvent('bioskipped'));
        }
    }

    handleBackdropClick(event) {
        if (!event.target.classList.contains('intro-modal-backdrop')) {
            return;
        }
        // Backdrop dismissal is only a "skip the whole thing" during the form
        // step. Once the story has been created, treat it as "skip the photo"
        // so we don't undo the markBioPostCompleted(posted: true) call.
        if (this._showPhotoStep) {
            this.handleSkipPhoto();
            return;
        }
        if (this._showCelebration || this._isPosting) {
            return;
        }
        this.handleSkip();
    }

    handleStopProp(event) {
        event.stopPropagation();
    }
}
