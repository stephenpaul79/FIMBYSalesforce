import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLinkedUser from '@salesforce/apex/FimbyContactUserAdminController.getLinkedUser';

const SECTION_ACCOUNT = 'account';
const SECTION_WALKTHROUGH = 'walkthrough';
const SECTION_EMAIL = 'email';
const SECTION_PUSH = 'push';
const SECTION_ACTIVITY = 'activity';

export default class FimbyContactLinkedUserPanel extends LightningElement {
    @api recordId;

    linkedUser;
    wiredLinkedUserResult;
    isLoading = true;
    loadError;

    editingSection = null;
    viewFormKey = 0;

    collapsedSections = {};

    @wire(getLinkedUser, { contactId: '$recordId' })
    wiredLinkedUser(result) {
        this.wiredLinkedUserResult = result;
        this.isLoading = false;
        const { data, error } = result;
        if (data) {
            this.linkedUser = data;
            this.loadError = undefined;
        } else if (error) {
            this.linkedUser = undefined;
            this.loadError = error;
        } else {
            this.linkedUser = undefined;
            this.loadError = undefined;
        }
    }

    get hasLinkedUser() {
        return !!this.linkedUser?.userId;
    }

    get userId() {
        return this.linkedUser?.userId;
    }

    get userRecordUrl() {
        return this.userId ? `/${this.userId}` : '#';
    }

    get userStatusLabel() {
        return this.linkedUser?.isActive ? 'Active' : 'Inactive';
    }

    get userStatusClass() {
        return this.linkedUser?.isActive
            ? 'slds-badge slds-badge_success'
            : 'slds-badge';
    }

    get viewFormKeyAttr() {
        return String(this.viewFormKey);
    }

    isSectionEditing(sectionId) {
        return this.editingSection === sectionId;
    }

    isSectionCollapsed(sectionId) {
        return this.collapsedSections[sectionId] === true;
    }

    sectionOpenClass(sectionId) {
        return this.isSectionCollapsed(sectionId) ? 'slds-section' : 'slds-section slds-is-open';
    }

    isEditingAccount = false;
    isEditingWalkthrough = false;
    isEditingEmail = false;
    isEditingPush = false;
    isEditingActivity = false;

    get accountSectionClass() {
        return this.sectionOpenClass(SECTION_ACCOUNT);
    }
    get walkthroughSectionClass() {
        return this.sectionOpenClass(SECTION_WALKTHROUGH);
    }
    get emailSectionClass() {
        return this.sectionOpenClass(SECTION_EMAIL);
    }
    get pushSectionClass() {
        return this.sectionOpenClass(SECTION_PUSH);
    }
    get activitySectionClass() {
        return this.sectionOpenClass(SECTION_ACTIVITY);
    }

    handleToggleSection(event) {
        const sectionId = event.currentTarget.dataset.section;
        this.collapsedSections = {
            ...this.collapsedSections,
            [sectionId]: !this.isSectionCollapsed(sectionId)
        };
    }

    handleEditSection(event) {
        const sectionId = event.currentTarget.dataset.section;
        this.editingSection = sectionId;
        this.isEditingAccount = sectionId === SECTION_ACCOUNT;
        this.isEditingWalkthrough = sectionId === SECTION_WALKTHROUGH;
        this.isEditingEmail = sectionId === SECTION_EMAIL;
        this.isEditingPush = sectionId === SECTION_PUSH;
        this.isEditingActivity = sectionId === SECTION_ACTIVITY;
    }

    handleCancelEdit() {
        this.editingSection = null;
        this.isEditingAccount = false;
        this.isEditingWalkthrough = false;
        this.isEditingEmail = false;
        this.isEditingPush = false;
        this.isEditingActivity = false;
    }

    async handleSaveSuccess() {
        this.handleCancelEdit();
        this.viewFormKey += 1;
        if (this.wiredLinkedUserResult) {
            await refreshApex(this.wiredLinkedUserResult);
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'User updated',
                message: 'Linked user settings were saved.',
                variant: 'success'
            })
        );
    }

    handleSaveError(event) {
        const message =
            event?.detail?.message ||
            event?.detail?.detail ||
            'We could not save those changes. Please try again.';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Save failed',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    handleSubmit(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        event.target.submit(fields);
    }
}
