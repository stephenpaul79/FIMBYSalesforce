import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getCategoryIconUrl, getCategoryStyle } from 'c/fimbySkillCategoryConfig';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import { decodeHtmlEntities } from 'c/fimbyTextUtils';

import getSkillOffer from '@salesforce/apex/FimbySkillsController.getSkillOffer';
import setSkillStatus from '@salesforce/apex/FimbySkillsController.setSkillStatus';

export default class FimbySkillOfferDetail extends LightningElement {
    _recordId;
    @track _extractedRecordId = null;
    @track isLoading = true;
    @track skill = null;
    @track error = '';
    @track showRemoveConfirm = false;
    @track showPauseConfirm = false;
    @track isUpdatingStatus = false;
    @track detailsExpanded = true;
    _pendingEditOpen = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const next = value && String(value).trim() ? value : null;
        if (next === this._recordId) return;
        this._recordId = next;
        this._loadSkill();
    }

    connectedCallback() {
        if (!this._recordId) {
            const id = this._extractRecordIdFromUrl();
            if (id) {
                this._extractedRecordId = id;
                this._recordId = id;
            }
        }
        this._pendingEditOpen = this._urlRequestsEdit();

        if (this._recordId) {
            this._loadSkill();
        } else {
            this.isLoading = false;
            this.error = 'Skill not found.';
        }
    }

    renderedCallback() {
        if (!this._pendingEditOpen || this.isLoading || !this.skill?.isOwner) return;
        this._pendingEditOpen = false;
        const modal = this.template.querySelector('c-fimby-skill-edit-modal');
        if (modal) {
            modal.show(this.effectiveRecordId);
        }
        this._clearEditActionFromUrl();
    }

    get effectiveRecordId() {
        return this._recordId || this._extractedRecordId;
    }

    get isOwner() {
        return this.skill?.isOwner === true;
    }

    get isPosterPersona() {
        return this.isOwner;
    }

    get isResponderPersona() {
        return !this.isOwner && this.skill?.status === 'Active';
    }

    get showLoadingState() {
        return this.isLoading;
    }

    get showErrorState() {
        return !this.isLoading && (!this.skill || this.error);
    }

    get showContent() {
        return !this.isLoading && this.skill;
    }

    get headerMenuItems() {
        if (this.isPosterPersona) {
            const items = [
                { key: 'edit', label: 'Edit', icon: 'edit.png', display: 'responsive' }
            ];
            if (this.skill?.status === 'Active') {
                items.push({ key: 'pause', label: 'Pause', icon: 'gear.png', display: 'responsive' });
            } else if (this.skill?.status === 'Paused') {
                items.push({ key: 'reactivate', label: 'Reactivate', icon: 'add.png', display: 'responsive' });
            }
            items.push({ key: 'remove', label: 'Remove', icon: 'trash.png', display: 'responsive', variant: 'danger' });
            return items;
        }
        return [{ key: 'flag', label: 'Report', icon: 'warning.png', display: 'kebab' }];
    }

    get heroIconUrl() {
        if (!this.skill?.category) return `${IMPACT_ICONS}/lightbulb.png`;
        return getCategoryIconUrl(IMPACT_ICONS, this.skill.category);
    }

    get categoryBadgeStyle() {
        return getCategoryStyle(this.skill?.category);
    }

    get ownerAvatarUrl() {
        return this.skill?.ownerImageUrl ? avatarImageUrl(this.skill.ownerImageUrl) : `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get decodedDescription() {
        return decodeHtmlEntities(this.skill?.description || '');
    }

    get decodedAvailability() {
        return decodeHtmlEntities(this.skill?.availabilityNote || '');
    }

    get descriptionDisplay() {
        return this.decodedDescription || 'Not provided';
    }

    get availabilityDisplay() {
        return this.decodedAvailability || 'Not provided';
    }

    get statusLabel() {
        const status = this.skill?.status;
        if (status === 'Paused') return 'Paused';
        if (status === 'Removed') return 'Removed';
        return 'Active';
    }

    get detailsToggleIcon() {
        return this.detailsExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get detailsIconUrl() {
        return `${IMPACT_ICONS}/BulletinBoardActive.png`;
    }

    get askHelpIconUrl() {
        return `${IMPACT_ICONS}/lightbulb.png`;
    }

    async _loadSkill() {
        const id = this.effectiveRecordId;
        if (!id) return;

        this.isLoading = true;
        this.error = '';
        try {
            this.skill = await getSkillOffer({ recordId: id });
        } catch (e) {
            this.skill = null;
            this.error = e.body?.message || e.message || 'Failed to load skill.';
        } finally {
            this.isLoading = false;
        }
    }

    _urlRequestsEdit() {
        try {
            return new URL(window.location.href).searchParams.get('action') === 'edit';
        } catch (e) {
            return false;
        }
    }

    _clearEditActionFromUrl() {
        try {
            const url = new URL(window.location.href);
            if (!url.searchParams.has('action')) return;
            url.searchParams.delete('action');
            window.history.replaceState({}, '', url.pathname + url.search + url.hash);
        } catch (e) {
            /* ignore */
        }
    }

    _extractRecordIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            const queryId = url.searchParams.get('recordId');
            if (queryId) return queryId;

            const parts = url.pathname.split('/').filter(p => p && p !== 's');
            const idx = parts.findIndex(p => p === 'skill-offer');
            if (idx !== -1 && parts.length > idx + 1) {
                const potential = parts[idx + 1];
                if (/^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(potential)) {
                    return potential;
                }
            }
            return null;
        } catch (e) {
            return null;
        }
    }

    handleHeaderMenuAction(event) {
        const key = event.detail?.key;
        const actions = {
            edit: () => {
                const modal = this.template.querySelector('c-fimby-skill-edit-modal');
                if (modal) {
                    modal.show(this.effectiveRecordId);
                }
            },
            pause: () => { this.showPauseConfirm = true; },
            reactivate: () => { this._updateStatus('Active'); },
            remove: () => { this.showRemoveConfirm = true; },
            flag: () => { this._openReportModal(); }
        };
        actions[key]?.();
    }

    handleToggleDetails() {
        this.detailsExpanded = !this.detailsExpanded;
    }

    async handleSkillSaved() {
        await this._loadSkill();
    }

    handleAskForHelp() {
        const modal = this.template.querySelector('c-fimby-quick-response-modal');
        if (modal) {
            modal.show(this.effectiveRecordId, 'skill');
        }
    }

    handleResponseSaved(event) {
        const conversationId = event.detail?.responseData?.conversationId;
        if (conversationId) {
            location.href = `/conversation?id=${conversationId}`;
        }
    }

    handleCancelPause() {
        this.showPauseConfirm = false;
    }

    async handleConfirmPause() {
        this.showPauseConfirm = false;
        await this._updateStatus('Paused');
    }

    handleCancelRemove() {
        this.showRemoveConfirm = false;
    }

    async handleConfirmRemove() {
        this.showRemoveConfirm = false;
        await this._updateStatus('Removed');
    }

    async _updateStatus(status) {
        if (!this.effectiveRecordId || this.isUpdatingStatus) return;
        this.isUpdatingStatus = true;
        try {
            await setSkillStatus({ recordId: this.effectiveRecordId, status });
            if (status === 'Removed') {
                location.href = '/my-stuff/my-skills';
                return;
            }
            await this._loadSkill();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Updated',
                message: status === 'Paused' ? 'Your skill is paused for now.' : 'Your skill is active again.',
                variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: e.body?.message || e.message || 'Could not update skill.',
                variant: 'error'
            }));
        } finally {
            this.isUpdatingStatus = false;
        }
    }

    _openReportModal() {
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) {
            modal.show(this.effectiveRecordId, 'Skill_Offer');
        }
    }

    handleOwnerClick() {
        if (this.skill?.ownerContactId) {
            location.href = `/neighbour?id=${this.skill.ownerContactId}`;
        }
    }
}
