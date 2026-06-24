import { LightningElement, api, wire } from 'lwc';
import getLinkedUser from '@salesforce/apex/FimbyContactUserAdminController.getLinkedUser';

export default class FimbyContactLinkedUserPanel extends LightningElement {
    @api recordId;

    linkedUser;
    isLoading = true;
    loadError;

    collapsedSections = {};

    @wire(getLinkedUser, { contactId: '$recordId' })
    wiredLinkedUser({ data, error }) {
        this.isLoading = false;
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

    isSectionCollapsed(sectionId) {
        return this.collapsedSections[sectionId] === true;
    }

    sectionOpenClass(sectionId) {
        return this.isSectionCollapsed(sectionId) ? 'slds-section' : 'slds-section slds-is-open';
    }

    get accountSectionClass() {
        return this.sectionOpenClass('account');
    }
    get walkthroughSectionClass() {
        return this.sectionOpenClass('walkthrough');
    }
    get emailSectionClass() {
        return this.sectionOpenClass('email');
    }
    get pushSectionClass() {
        return this.sectionOpenClass('push');
    }
    get activitySectionClass() {
        return this.sectionOpenClass('activity');
    }

    handleToggleSection(event) {
        const sectionId = event.currentTarget.dataset.section;
        this.collapsedSections = {
            ...this.collapsedSections,
            [sectionId]: !this.isSectionCollapsed(sectionId)
        };
    }
}
