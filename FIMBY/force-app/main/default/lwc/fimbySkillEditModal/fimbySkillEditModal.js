import { LightningElement, api, track, wire } from 'lwc';

import { fireErrorToast } from 'c/fimbyToastHelper';

import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

import { decodeHtmlEntities } from 'c/fimbyTextUtils';



import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';

import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';

import getSkillOffer from '@salesforce/apex/FimbySkillsController.getSkillOffer';

import saveSkillOffers from '@salesforce/apex/FimbySkillsController.saveSkillOffers';



const TITLE_MAX = 80;

const DESCRIPTION_MAX = 255;

const AVAILABILITY_MAX = 255;



export default class FimbySkillEditModal extends LightningElement {

    @track isVisible = false;

    @track isLoading = false;

    @track isSaving = false;

    @track loadError = '';

    @track saveError = '';



    @track recordId = '';

    @track category = '';

    @track title = '';

    @track description = '';

    @track availabilityNote = '';



    @track actingAsContactName = '';

    @track hasMultipleIdentities = false;

    @track formReady = false;



    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }

    get saveIconUrl() { return `${IMPACT_ICONS}/save.png`; }

    get posterIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }



    get modalTitle() {

        return this.category

            ? `Edit your ${this.category} skill`

            : 'Edit skill offer';

    }



    get showFooter() { return !this.isLoading && !this.loadError && this.formReady; }

    get showIdentityBanner() { return this.hasMultipleIdentities && !!this.actingAsContactName; }

    get titleLength() { return this.title.length; }

    get descriptionLength() { return this.description.length; }

    get availabilityLength() { return this.availabilityNote.length; }



    get titleCountClass() { return this._countClass(this.titleLength, TITLE_MAX); }

    get descriptionCountClass() { return this._countClass(this.descriptionLength, DESCRIPTION_MAX); }

    get availabilityCountClass() { return this._countClass(this.availabilityLength, AVAILABILITY_MAX); }



    get isSaveDisabled() {

        return this.isSaving || !this.title.trim();

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



    @api

    show(recordId) {

        if (!recordId) return;

        this.recordId = recordId;

        this.isVisible = true;

        this.loadError = '';

        this.saveError = '';

        this.formReady = false;

        this.category = '';

        this.title = '';

        this.description = '';

        this.availabilityNote = '';

        this._loadSkill();

    }



    @api

    hide() {

        this.isVisible = false;

    }



    async _loadSkill() {

        this.isLoading = true;

        this.formReady = false;

        this.loadError = '';

        try {

            const skill = await getSkillOffer({ recordId: this.recordId });

            this.category = skill.category || '';

            this.title = decodeHtmlEntities(skill.title || this.category);

            this.description = decodeHtmlEntities(skill.description || '');

            this.availabilityNote = decodeHtmlEntities(skill.availabilityNote || '');

            this.formReady = true;

        } catch (e) {

            this.loadError = e.body?.message || e.message || 'Could not load skill.';

        } finally {

            this.isLoading = false;

        }

    }



    handleTitleChange(event) {

        this.title = event.target.value;

    }



    handleDescriptionChange(event) {

        this.description = event.detail.value;

    }



    handleAvailabilityChange(event) {

        this.availabilityNote = event.target.value;

    }



    handleRetry() {

        this._loadSkill();

    }



    handleBackdropClick() {

        if (!this.isSaving) {

            this.handleClose();

        }

    }



    handleModalClick(event) {

        event.stopPropagation();

    }



    handleClose() {

        if (this.isSaving) return;

        this.isVisible = false;

        this.dispatchEvent(new CustomEvent('close'));

    }



    async handleSave() {

        if (this.isSaveDisabled) return;

        this.isSaving = true;

        this.saveError = '';



        try {

            const payload = [{

                id: this.recordId,

                category: this.category,

                title: this.title.trim(),

                description: this.description?.trim() || null,

                availabilityNote: this.availabilityNote?.trim() || null

            }];



            const result = await saveSkillOffers({ skillsJson: JSON.stringify(payload) });

            if (result.success) {

                this.isVisible = false;

                this.dispatchEvent(new CustomEvent('saved', {

                    detail: { recordId: this.recordId }

                }));

            }

        } catch (e) {

            this.saveError = e.body?.message || e.message || 'We couldn\'t save your changes. Please try again.';

            fireErrorToast(e);

        } finally {

            this.isSaving = false;

        }

    }



    _countClass(len, max) {

        if (len >= max) return 'character-count at-limit';

        if (len >= Math.floor(max * 0.9)) return 'character-count near-limit';

        return 'character-count';

    }

}

