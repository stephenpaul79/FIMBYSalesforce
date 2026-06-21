import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';
import { fireErrorToast } from 'c/fimbyToastHelper';

// Static resources
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getCategoryIconUrl } from 'c/fimbyLibraryCategoryConfig';

// Apex methods
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getCategoryPicklistValues from '@salesforce/apex/FimbyLibraryController.getCategoryPicklistValues';
import createLibraryItem from '@salesforce/apex/FimbyLibraryController.createLibraryItem';

export default class FimbyAddLibraryItem extends NavigationMixin(LightningElement) {
    // Current user/contact info
    @track actingAsContactId = '';
    @track actingAsContactName = '';
    @track hasMultipleIdentities = false;

    // Form state
    @track title = '';
    @track description = '';
    @track selectedCategory = '';
    @track maxLendingDays = 7;
    @track autoAcceptRequests = false;
    @track autoShareContactInfo = false;
    @track damageWaiverConfirmed = false;

    // Content mode: item | skill
    @track postMode = 'item';
    @track editSkillId = '';
    @track skillCelebrationActive = false;

    // UI state
    @track categories = [];
    @track isSaving = false;
    @track isLoading = true;
    @track showPhotoStep = false;
    @track showSuccess = false;
    @track createdItemId = '';

    // Error state
    @track error = '';

    // Section header icon URLs
    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get itemDetailsIconUrl() {
        return `${IMPACT_ICONS}/ToolboxActive.png`;
    }

    get settingsIconUrl() {
        return `${IMPACT_ICONS}/gear.png`;
    }

    get warningIconUrl() {
        return `${IMPACT_ICONS}/warning.png`;
    }

    // Computed properties
    get titleLength() {
        return this.title.length;
    }

    get descriptionLength() {
        return this.description.length;
    }

    get titleCountClass() {
        if (this.titleLength >= 80) return 'character-count at-limit';
        if (this.titleLength >= 72) return 'character-count near-limit';
        return 'character-count';
    }

    get descriptionCountClass() {
        if (this.descriptionLength >= 255) return 'character-count at-limit';
        if (this.descriptionLength >= 230) return 'character-count near-limit';
        return 'character-count';
    }

    get titleLengthError() {
        return this.title.length > 80
            ? `Please reduce the title by ${this.title.length - 80} characters.`
            : '';
    }

    get descriptionLengthError() {
        return this.description.length > 255
            ? `Please reduce the description by ${this.description.length - 255} characters.`
            : '';
    }

    get isFormValid() {
        return this.title.trim() !== '' &&
               this.title.length <= 80 &&
               this.description.trim() !== '' &&
               this.description.length <= 255 &&
               this.selectedCategory !== '' &&
               this.maxLendingDays > 0 &&
               this.damageWaiverConfirmed;
    }

    get isFormInvalid() {
        return !this.isFormValid;
    }

    get submitButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Next';
    }

    get submitIconUrl() {
        return `${IMPACT_ICONS}/photo.png`;
    }

    get viewItemIconUrl() {
        return getCategoryIconUrl(IMPACT_ICONS, this.selectedCategory);
    }

    get isItemMode() {
        return this.postMode === 'item';
    }

    get isSkillMode() {
        return this.postMode === 'skill';
    }

    get itemsIconUrl() {
        return `${IMPACT_ICONS}/Items.png`;
    }

    get skillsIconUrl() {
        return `${IMPACT_ICONS}/Skills.png`;
    }

    get itemTypeClass() {
        return this.isItemMode ? 'library-type-option active' : 'library-type-option';
    }

    get skillTypeClass() {
        return this.isSkillMode ? 'library-type-option active' : 'library-type-option';
    }

    get pageHeaderTitle() {
        if (this.isSkillMode) {
            return this.editSkillId ? 'Edit Skill Offer' : 'Offer a Skill';
        }
        return 'Post Library Item';
    }

    get composerMode() {
        return this.editSkillId ? 'edit' : 'create';
    }

    get showModeSelector() {
        return !this.skillCelebrationActive && !this.editSkillId;
    }

    handleSkillCelebrationChange(event) {
        this.skillCelebrationActive = event.detail?.active === true;
    }

    connectedCallback() {
        this._parseUrlParams();
    }

    _parseUrlParams() {
        try {
            const url = new URL(window.location.href);
            const type = url.searchParams.get('type');
            const editId = url.searchParams.get('edit');
            if (type === 'skill') {
                this.postMode = 'skill';
                this.isLoading = false;
            }
            if (editId) {
                navigate(this, `/skill-offer/${editId}?action=edit`);
                
            }
        } catch {
            /* ignore */
        }
    }

    handleItemMode() {
        if (this.postMode !== 'item') {
            this.postMode = 'item';
            this.editSkillId = '';
        }
    }

    handleSkillMode() {
        if (this.postMode !== 'skill') {
            this.postMode = 'skill';
        }
    }

    // Wire adapters to load initial data
    @wire(getActingAsContact)
    wiredActingAs({ error, data }) {
        if (data) {
            this.actingAsContactId = data.actingAsContactId || data.contactId;
            this.actingAsContactName = data.postingAsDisplayName || data.actingAsContactName || data.contactName;
            this.isLoading = false;
        } else if (error) {
            this.error = error.body?.message || 'Error loading user information';
            this.isLoading = false;
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

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsContactName;
    }

    @wire(getCategoryPicklistValues)
    wiredCategories({ error, data }) {
        if (data) {
            this.categories = data;
        } else if (error) {
            console.error('Error loading categories:', error);
        }
    }

    handleTitleChange(event) {
        this.title = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleCategoryChange(event) {
        this.selectedCategory = event.target.value;
    }

    handleMaxLendingDaysChange(event) {
        this.maxLendingDays = parseInt(event.target.value, 10) || 7;
    }

    handleAutoAcceptChange(event) {
        this.autoAcceptRequests = event.target.checked;
    }

    handleAutoShareChange(event) {
        this.autoShareContactInfo = event.target.checked;
    }

    handleDamageWaiverChange(event) {
        this.damageWaiverConfirmed = event.target.checked;
    }

    handleBack() {
        if (this.hasUnsavedChanges()) {
            // eslint-disable-next-line no-alert -- unsaved-changes guard until modal refactor
            if (window.confirm('You have unsaved changes. Are you sure you want to go back?')) {
                this.navigateToLibrary();
            }
        } else {
            this.navigateToLibrary();
        }
    }

    hasUnsavedChanges() {
        return this.title.trim() !== '' ||
               this.description.trim() !== '' ||
               this.selectedCategory !== '';
    }

    navigateToLibrary() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Library__c'
            }
        });
    }

    async handlePostNow() {
        if (!this.isFormValid || this.isSaving) return;

        this.isSaving = true;
        this.error = '';

        try {
            const itemData = {
                title: this.title.trim(),
                description: this.description.trim(),
                category: this.selectedCategory,
                maxLendingDays: this.maxLendingDays,
                autoAcceptRequests: this.autoAcceptRequests,
                autoShareContactInfo: this.autoShareContactInfo,
                damageWaiverConfirmed: this.damageWaiverConfirmed
            };

            const result = await createLibraryItem({ itemData: JSON.stringify(itemData) });

            if (result.success) {
                this.createdItemId = result.recordId;
                this.showPhotoStep = true;
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        } catch (error) {
            console.error('Error creating library item:', error);
            fireErrorToast(error);
        } finally {
            this.isSaving = false;
        }
    }

    handlePhotoUploaded() {
        this.showPhotoStep = false;
        this.showSuccess = true;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    handleSkipPhoto() {
        this.showPhotoStep = false;
        this.showSuccess = true;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    handleGoToItem() {
        this.navigateToItem();
    }

    navigateToItem() {
        if (this.createdItemId) {
            navigate(this, `/library-item/${this.createdItemId}`);
        }
    }

    handlePostAnother() {
        // Reset form for another post
        this.resetForm();
        this.showPhotoStep = false;
        this.showSuccess = false;
    }

    resetForm() {
        this.title = '';
        this.description = '';
        this.selectedCategory = '';
        this.maxLendingDays = 7;
        this.autoAcceptRequests = false;
        this.autoShareContactInfo = false;
        this.damageWaiverConfirmed = false;
        this.createdItemId = '';
    }
}