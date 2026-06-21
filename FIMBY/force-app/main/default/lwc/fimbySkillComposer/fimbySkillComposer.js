import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fireErrorToast } from 'c/fimbyToastHelper';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getCategoryIconUrl, getCategoryColor } from 'c/fimbySkillCategoryConfig';
import { decodeHtmlEntities } from 'c/fimbyTextUtils';
import { navigate } from 'c/fimbyNavigation';

import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getSkillCategoryPicklistValues from '@salesforce/apex/FimbySkillsController.getSkillCategoryPicklistValues';
import getMyOfferedCategories from '@salesforce/apex/FimbySkillsController.getMyOfferedCategories';
import getSkillOffer from '@salesforce/apex/FimbySkillsController.getSkillOffer';
import saveSkillOffers from '@salesforce/apex/FimbySkillsController.saveSkillOffers';

const TITLE_MAX = 80;
const DESCRIPTION_MAX = 255;
const AVAILABILITY_MAX = 255;

export default class FimbySkillComposer extends NavigationMixin(LightningElement) {
    @api mode = 'create';
    @api editSkillId;

    @track step = 1;
    @track isLoading = true;
    @track isSaving = false;
    @track error = '';
    @track showSuccess = false;
    @track showFirstSkillCelebration = false;

    @track actingAsContactName = '';
    @track hasMultipleIdentities = false;

    @track categoryChips = [];
    @track selectedCategories = [];
    @track skillCards = [];

    _offeredByCategory = {};

    get isCreateMode() {
        return this.mode !== 'edit';
    }

    get isEditMode() {
        return this.mode === 'edit';
    }

    get showStep1() {
        return this.isCreateMode && this.step === 1 && !this.showSuccess;
    }

    get showStep2() {
        return (this.isCreateMode && this.step === 2 && !this.showSuccess) || (this.isEditMode && !this.showSuccess);
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.actingAsContactName;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get sectionIconUrl() {
        return `${IMPACT_ICONS}/lightbulb.png`;
    }

    get pageTitle() {
        return this.isEditMode ? 'Edit Skill Offer' : 'Offer a Skill';
    }

    get stepTitle() {
        if (this.isEditMode) return 'Update your skill offer';
        return this.step === 1 ? 'What can you help with?' : 'Tell neighbours about your skills';
    }

    get isPostDisabled() {
        return this.selectedCategories.length === 0 || this.isSaving;
    }

    get isSubmitDisabled() {
        if (this.isSaving) return true;
        return !this.skillCards.some(card => card.title.trim());
    }

    get submitLabel() {
        return this.isSaving ? 'Saving...' : (this.isEditMode ? 'Save Changes' : 'Post Skills');
    }

    get showBackButton() {
        return this.isEditMode || this.step === 2;
    }

    get formNavigationClass() {
        return this.showBackButton ? 'form-navigation' : 'form-navigation form-navigation-end';
    }

    @wire(getActingAsContact)
    wiredActingAs({ error, data }) {
        if (data) {
            this.actingAsContactName = data.postingAsDisplayName || data.actingAsContactName || data.contactName;
        } else if (error) {
            console.error('Error loading identity:', error);
        }
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ error, data }) {
        if (data) {
            this.hasMultipleIdentities = data.length > 0;
        } else if (error) {
            this.hasMultipleIdentities = false;
        }
    }

    async connectedCallback() {
        try {
            if (this.isEditMode && this.editSkillId) {
                await this._loadEditSkill();
            } else {
                await this._loadCreateData();
            }
        } catch (e) {
            this.error = e.body?.message || e.message || 'Failed to load skill form.';
        } finally {
            this.isLoading = false;
        }
    }

    async _loadCreateData() {
        const [picklist, offered] = await Promise.all([
            getSkillCategoryPicklistValues(),
            getMyOfferedCategories()
        ]);

        this._offeredByCategory = {};
        (offered || []).forEach(row => {
            if (row.category) {
                this._offeredByCategory[row.category] = row;
            }
        });

        const sorted = [...(picklist || [])].sort((a, b) =>
            (a.label || a.value).localeCompare(b.label || b.value, undefined, { sensitivity: 'base' })
        );

        this.categoryChips = sorted.map(opt => {
            const value = opt.value || opt.label;
            const existing = this._offeredByCategory[value];
            const label = opt.label || value;
            return {
                key: value,
                value,
                label,
                iconUrl: getCategoryIconUrl(IMPACT_ICONS, value),
                isOffered: !!existing,
                existingId: existing?.id,
                editAriaLabel: `Edit your ${label} skill`,
                isSelected: false,
                chipClass: 'category-chip'
            };
        });
    }

    async _loadEditSkill() {
        const skill = await getSkillOffer({ recordId: this.editSkillId });
        const category = skill.category;
        this.skillCards = [this._buildCardRow({
            key: skill.id,
            id: skill.id,
            category,
            categoryLocked: true,
            title: decodeHtmlEntities(skill.title || category),
            description: decodeHtmlEntities(skill.description || ''),
            availabilityNote: decodeHtmlEntities(skill.availabilityNote || '')
        })];
    }

    handleCategoryToggle(event) {
        const value = event.currentTarget.dataset.value;
        const existing = this._offeredByCategory[value];
        if (existing) return;

        const selected = new Set(this.selectedCategories);
        if (selected.has(value)) {
            selected.delete(value);
        } else {
            selected.add(value);
        }
        this.selectedCategories = [...selected];
        this.categoryChips = this.categoryChips.map(chip => ({
            ...chip,
            isSelected: selected.has(chip.value),
            chipClass: selected.has(chip.value) ? 'category-chip selected' : 'category-chip'
        }));
    }

    handleEditExisting(event) {
        event.stopPropagation();
        const skillId = event.currentTarget.dataset.skillId;
        const modal = this.template.querySelector('c-fimby-skill-edit-modal');
        if (skillId && modal) {
            modal.show(skillId);
        }
    }

    async handleSkillEditSaved() {
        await this._loadCreateData();
    }

    _buildCardsFromSelection() {
        return this.selectedCategories.map(category => this._buildCardRow({
            key: category,
            category,
            title: category
        }));
    }

    async handlePostSelected() {
        if (this.isPostDisabled) return;
        this.skillCards = this._buildCardsFromSelection();
        await this.handleSubmit();
    }

    handleAddDetails() {
        if (this.selectedCategories.length === 0) return;
        this.skillCards = this._buildCardsFromSelection();
        this.step = 2;
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    handleBack() {
        if (this.isEditMode) {
            if (this.editSkillId) {
                navigate(this, `/skill-offer/${this.editSkillId}`);
            } else {
                navigate(this, '/library-list');
            }
            return;
        }
        if (this.step === 2) {
            this.step = 1;
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }
    }

    handleTitleChange(event) {
        const category = event.target.dataset.category;
        const value = event.target.value;
        this._updateCard(category, { title: value, titleCountClass: this._countClass(value.length, TITLE_MAX) });
    }

    handleDescriptionChange(event) {
        const category = event.currentTarget.dataset.category;
        const value = event.detail.value;
        this._updateCard(category, { description: value, descriptionCountClass: this._countClass(value.length, DESCRIPTION_MAX) });
    }

    handleAvailabilityChange(event) {
        const category = event.target.dataset.category;
        const value = event.target.value;
        this._updateCard(category, { availabilityNote: value, availabilityCountClass: this._countClass(value.length, AVAILABILITY_MAX) });
    }

    _updateCard(category, updates) {
        this.skillCards = this.skillCards.map(card => (
            card.category === category ? { ...card, ...updates } : card
        ));
    }

    _buildCardRow(row) {
        const category = row.category;
        const key = row.key || category;
        const title = row.title || category;
        const description = row.description || '';
        const availabilityNote = row.availabilityNote || '';
        const slug = String(key).replace(/[^a-zA-Z0-9]/g, '');
        return {
            key,
            id: row.id || null,
            category,
            categoryLocked: row.categoryLocked === true,
            title,
            description,
            availabilityNote,
            iconUrl: getCategoryIconUrl(IMPACT_ICONS, category),
            headerStyle: `background-color: ${getCategoryColor(category)};`,
            titleInputId: `skill-title-${slug}`,
            descInputId: `skill-desc-${slug}`,
            availInputId: `skill-avail-${slug}`,
            titleCountClass: this._countClass(title.length, TITLE_MAX),
            descriptionCountClass: this._countClass(description.length, DESCRIPTION_MAX),
            availabilityCountClass: this._countClass(availabilityNote.length, AVAILABILITY_MAX)
        };
    }

    _countClass(len, max) {
        if (len >= max) return 'character-count at-limit';
        if (len >= Math.floor(max * 0.9)) return 'character-count near-limit';
        return 'character-count';
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) return;
        this.isSaving = true;
        this.error = '';

        try {
            const payload = this.skillCards
                .filter(card => card.title.trim())
                .map(card => ({
                    id: card.id || null,
                    category: card.category,
                    title: card.title.trim(),
                    description: card.description?.trim() || null,
                    availabilityNote: card.availabilityNote?.trim() || null
                }));

            const result = await saveSkillOffers({ skillsJson: JSON.stringify(payload) });

            if (result.success) {
                this.showFirstSkillCelebration = result.firstSkill === true;
                this.showSuccess = true;
                this._notifyCelebration(true);
                window.scrollTo({ top: 0, behavior: 'smooth' });
            }
        } catch (e) {
            fireErrorToast(e);
        } finally {
            this.isSaving = false;
        }
    }

    handleViewMySkills() {
        navigate(this, '/my-stuff/my-skills');
    }

    _notifyCelebration(active) {
        this.dispatchEvent(new CustomEvent('celebrationchange', {
            detail: { active },
            bubbles: true,
            composed: true
        }));
    }

    disconnectedCallback() {
        if (this.showSuccess) {
            this._notifyCelebration(false);
        }
    }
}
