import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import searchContactsForOnBehalfOf from '@salesforce/apex/FimbyContactController.searchContactsForOnBehalfOf';
import searchOrganizations from '@salesforce/apex/FimbyContactController.searchOrganizations';
import submitRelationshipRequest from '@salesforce/apex/FimbySupportRelationshipController.submitRelationshipRequest';
import getNeighbourhoodsForOrganization from '@salesforce/apex/FimbySupportRelationshipController.getNeighbourhoodsForOrganization';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import createPaperDraft from '@salesforce/apex/FimbySupportRelationshipController.createPaperDraft';
import submitPaperUpload from '@salesforce/apex/FimbySupportRelationshipController.submitPaperUpload';
import getCurrentCgaVersion from '@salesforce/apex/FimbyTosController.getCurrentCgaVersion';
import getCurrentCgaEffectiveDate from '@salesforce/apex/FimbyTosController.getCurrentCgaEffectiveDate';

import createOrganizationRequest from '@salesforce/apex/FimbyOrganizationRequestService.createOrganizationRequest';
import { fireErrorToast } from 'c/fimbyToastHelper';

const STEPS = ['type', 'identity', 'neighbourhood', 'authorization', 'notes', 'review'];
const CG_CREATE_STEPS = ['type', 'identity', 'createOrg', 'authorization', 'notes', 'review'];
const PAPER_STEPS = ['type', 'paperIdentifiers', 'review'];

const TOS_URL = 'https://fimby.com/terms-of-service';
const CGA_URL = 'https://fimby.com/terms-of-service#community-group-agreement';

export default class FimbyRelationshipSetupModal extends LightningElement {
    @track isOpen = false;
    @track currentStep = 0;
    @track selectedType = '';
    @track searchTerm = '';
    @track searchResults = [];
    @track selectedIdentity = null;
    @track selectedNeighbourhood = null;
    @track neighbourhoodOptions = [];
    @track neighbourhoodsLoading = false;
    @track authImageUrl = '';
    @track authImageData = '';
    @track authImageFileName = '';
    @track authImageUploaded = false;
    @track authImageUploading = false;
    @track notes = '';
    @track isSubmitting = false;
    @track error = '';
    @track myNeighbourhoodId = '';

    @track usePaperPath = false;
    @track paperFirstName = '';
    @track paperLastName = '';
    @track paperBirthdate = '';
    @track paperStreet = '';
    @track paperCity = '';
    @track paperPostalCode = '';
    @track paperPhone = '';
    @track paperEmail = '';
    @track paperRelationship = '';
    @track paperDraftSubmitted = false;

    @track cgaVersion = '';
    @track cgaEffectiveDate = '';
    @track cgaLinkTapped = false;
    @track cgaChecked = false;
    @track tosLinkTapped = false;
    @track tosChecked = false;

    @track resumeMode = false;
    @track resumeSrId = null;
    @track uploadedContentVersionId = null;
    @track uploadSubmitted = false;

    @track createOrgMode = false;
    @track orgSubmitted = false;
    @track orgName = '';
    @track orgStreet = '';
    @track orgCity = '';
    @track orgState = 'BC';
    @track orgPostalCode = '';
    @track orgCountry = 'Canada';
    @track orgType = '';
    @track requesterOrgRole = '';
    @track isRegisteredCharity = false;
    @track charityVerificationUrl = '';
    @track charityRegistrationNumber = '';
    @track orgPhone = '';
    @track orgEmail = '';
    @track orgWebsite = '';
    @track orgDescription = '';
    @track verificationDocData = '';
    @track verificationDocFileName = '';
    @track verificationDocUploaded = false;

    get orgTypeOptions() {
        return [
            { label: 'Choose a type…', value: '' },
            { label: 'Church / Ministry', value: 'Church_Ministry' },
            { label: 'Community Group', value: 'Community_Group' },
            { label: 'Neighbourhood House', value: 'Neighbourhood_House' },
            { label: 'Food Program', value: 'Food_Program' },
            { label: 'Mutual Aid', value: 'Mutual_Aid' },
            { label: 'School', value: 'School' },
            { label: 'Foundation', value: 'Foundation' },
            { label: 'Government', value: 'Government' },
            { label: 'Nonprofit', value: 'Nonprofit' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get activeStepList() {
        if (this.usePaperPath) return PAPER_STEPS;
        if (this.isCommunityGroup && this.createOrgMode) return CG_CREATE_STEPS;
        return STEPS;
    }
    get communityIconUrl() { return `${IMPACT_ICONS}/CommunityReps.png`; }
    get trustIconUrl() { return `${IMPACT_ICONS}/trust.png`; }

    get careIconUrl() { return `${IMPACT_ICONS}/care.png`; }
    get stepName() { return this.activeStepList[this.currentStep]; }
    get isTypeStep() { return this.stepName === 'type'; }
    get isIdentityStep() { return this.stepName === 'identity'; }
    get isCreateOrgStep() { return this.stepName === 'createOrg'; }
    get isNeighbourhoodStep() { return this.stepName === 'neighbourhood'; }
    get isAuthStep() { return this.stepName === 'authorization'; }
    get isNotesStep() { return this.stepName === 'notes'; }
    get isReviewStep() { return this.stepName === 'review'; }
    get isPaperIdentifiersStep() { return this.stepName === 'paperIdentifiers'; }
    get isFirstStep() { return this.currentStep === 0; }
    get isNotFirstStep() { return !this.isFirstStep; }
    get isNotPaperPath() { return !this.usePaperPath; }
    get notPaperDraftSubmitted() { return !this.paperDraftSubmitted; }
    get notOrgSubmitted() { return !this.orgSubmitted; }
    get isSuccessScreen() { return this.orgSubmitted || this.paperDraftSubmitted; }
    get showFooterBack() { return this.isNotFirstStep && !this.isSuccessScreen; }
    get showFooterDone() { return this.isSuccessScreen; }
    get isLastStep() { return this.currentStep === this.activeStepList.length - 1; }
    get showNext() { return !this.isLastStep && !this.isSuccessScreen; }
    get showSubmit() { return this.isLastStep && !this.isSuccessScreen; }
    get showPaperPathToggle() { return this.isSupportPerson; }

    get isSupportPerson() { return this.selectedType === 'Support_Person'; }
    get isCommunityGroup() { return this.selectedType === 'Community_Group_Rep'; }
    get tosUrl() { return TOS_URL; }
    get cgaUrl() { return CGA_URL; }

    get supportTypeClass() {
        return this.selectedType === 'Support_Person' ? 'type-card selected' : 'type-card';
    }
    get groupTypeClass() {
        return this.selectedType === 'Community_Group_Rep' ? 'type-card selected' : 'type-card';
    }

    get documentUploadEnabled() {
        return true;
    }

    get showAddYourGroup() {
        return this.isCommunityGroup
            && !this.selectedIdentity
            && !this.createOrgMode
            && this.searchTerm.length >= 2
            && this.searchResults.length === 0;
    }

    get createOrgVerificationValid() {
        if (this.isRegisteredCharity) {
            return !!(this.charityVerificationUrl || this.charityRegistrationNumber);
        }
        return !!(this.verificationDocUploaded || this.orgPhone || this.orgEmail);
    }

    get canProceed() {
        if (this.isTypeStep) return !!this.selectedType;
        if (this.isPaperIdentifiersStep) {
            return (
                !!this.paperFirstName &&
                !!this.paperLastName &&
                !!(this.paperPhone || this.paperEmail) &&
                !!this.paperRelationship
            );
        }
        if (this.isCreateOrgStep) {
            return (
                !!this.orgName &&
                !!this.orgStreet &&
                !!this.orgCity &&
                !!this.orgPostalCode &&
                !!this.orgType &&
                !!this.requesterOrgRole &&
                this.createOrgVerificationValid
            );
        }
        if (this.isIdentityStep) return !!this.selectedIdentity;
        if (this.isNeighbourhoodStep) return !!this.selectedNeighbourhood;
        if (this.isAuthStep) return this.authImageUploaded;
        return true;
    }
    get cannotProceed() {
        return !this.canProceed;
    }

    get progressPercent() {
        return Math.round(((this.currentStep + 1) / this.activeStepList.length) * 100);
    }

    get selectedIdentityName() {
        return this.selectedIdentity?.name || '';
    }
    get selectedNeighbourhoodName() {
        return this.selectedNeighbourhood?.name || '';
    }

    get reviewSummary() {
        return {
            type: this.isSupportPerson ? 'Support a neighbour' : 'Represent a community group',
            identity: this.usePaperPath
                ? `${this.paperFirstName} ${this.paperLastName}`.trim()
                : (this.createOrgMode ? this.orgName : this.selectedIdentityName),
            neighbourhood: this.createOrgMode ? 'Your neighbourhood' : (this.selectedNeighbourhood?.name || ''),
            hasAuth: this.authImageUploaded,
            hasNotes: !!this.notes,
            paperPath: this.usePaperPath,
            createOrg: this.createOrgMode
        };
    }

    get effectiveCgaDateLabel() {
        if (!this.cgaEffectiveDate) return '';
        try {
            return new Date(this.cgaEffectiveDate).toLocaleDateString(undefined, {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
        } catch (e) {
            return this.cgaEffectiveDate;
        }
    }

    get cgaCheckboxDisabled() {
        return !this.cgaLinkTapped;
    }
    get tosCheckboxDisabled() {
        return !this.tosLinkTapped;
    }
    get submitDisabled() {
        if (this.isSubmitting) return true;
        if (this.isCommunityGroup) {
            return !(this.cgaLinkTapped && this.cgaChecked);
        }
        if (this.usePaperPath) {
            return !(this.tosLinkTapped && this.tosChecked);
        }
        return false;
    }
    get submitHint() {
        if (this.isCommunityGroup) {
            if (!this.cgaLinkTapped) return 'Tap the Community Group Agreement link first.';
            if (!this.cgaChecked) return 'Confirm the agreement to submit.';
        }
        if (this.usePaperPath) {
            if (!this.tosLinkTapped) return 'Tap the Terms of Service link first.';
            if (!this.tosChecked) return 'Confirm the supporter responsibilities to submit.';
        }
        return '';
    }

    @api
    openForUpload(srId) {
        if (!srId) return;
        this.isOpen = true;
        this.resumeMode = true;
        this.resumeSrId = srId;
        this.uploadedContentVersionId = null;
        this.uploadSubmitted = false;
        this.error = '';
    }

    @api
    open() {
        this.isOpen = true;
        this.currentStep = 0;
        this.selectedType = '';
        this.selectedIdentity = null;
        this.selectedNeighbourhood = null;
        this.neighbourhoodOptions = [];
        this.neighbourhoodsLoading = false;
        this.authImageUrl = '';
        this.authImageData = '';
        this.authImageFileName = '';
        this.authImageUploaded = false;
        this.authImageUploading = false;
        this.notes = '';
        this.error = '';
        this.searchTerm = '';
        this.searchResults = [];

        this.usePaperPath = false;
        this.paperFirstName = '';
        this.paperLastName = '';
        this.paperBirthdate = '';
        this.paperStreet = '';
        this.paperCity = '';
        this.paperPostalCode = '';
        this.paperPhone = '';
        this.paperEmail = '';
        this.paperRelationship = '';
        this.paperDraftSubmitted = false;
        this.cgaLinkTapped = false;
        this.cgaChecked = false;
        this.tosLinkTapped = false;
        this.tosChecked = false;
        this.createOrgMode = false;
        this.orgSubmitted = false;
        this._resetCreateOrgFields();

        getActingAsContact()
            .then(result => {
                this.myNeighbourhoodId = result.accountId;
            })
            .catch(() => {});

        getCurrentCgaVersion()
            .then(v => { this.cgaVersion = v || ''; })
            .catch(() => {});
        getCurrentCgaEffectiveDate()
            .then(d => { this.cgaEffectiveDate = d || ''; })
            .catch(() => {});
    }

    close() {
        if (this.isSuccessScreen) {
            this.handleSuccessDoneClose();
            return;
        }
        this.isOpen = false;
    }

    handleSelectType(event) {
        this.selectedType = event.currentTarget.dataset.type;
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        if (this.searchTerm.length < 2) {
            this.searchResults = [];
            return;
        }
        clearTimeout(this._searchTimeout);
        this._searchTimeout = setTimeout(() => this._doSearch(), 300);
    }

    _doSearch() {
        const action = this.isSupportPerson
            ? searchContactsForOnBehalfOf({ searchTerm: this.searchTerm })
            : searchOrganizations({ searchTerm: this.searchTerm });

        action
            .then(results => {
                this.searchResults = (results || []).slice(0, 10).map(r => ({
                    id: r.id || r.Id,
                    name: r.name || r.Name
                }));
            })
            .catch(() => { this.searchResults = []; });
    }

    handleSelectIdentity(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedIdentity = this.searchResults.find(r => r.id === id);
        this.searchResults = [];
        this.searchTerm = this.selectedIdentity?.name || '';

        if (this.isSupportPerson && this.myNeighbourhoodId) {
            this.selectedNeighbourhood = { id: this.myNeighbourhoodId, name: '' };
        }
    }

    handleClearIdentity() {
        this.selectedIdentity = null;
        this.searchTerm = '';
        this.searchResults = [];
        this.createOrgMode = false;
        if (this.isSupportPerson) {
            this.selectedNeighbourhood = null;
        }
    }

    handleAddYourGroup() {
        this.createOrgMode = true;
        this.orgName = this.searchTerm;
        this.currentStep = this.activeStepList.indexOf('createOrg');
    }

    handleOrgFieldChange(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        if (field === 'isRegisteredCharity') {
            this.isRegisteredCharity = !!event.target.checked;
            return;
        }
        this[field] = event.target.value;
    }

    async handleVerificationDocSelected(event) {
        const detail = event.detail || {};
        if (detail.base64 && detail.fileName) {
            this.verificationDocData = detail.base64;
            this.verificationDocFileName = detail.fileName;
            this.verificationDocUploaded = true;
        }
    }

    _resetCreateOrgFields() {
        this.orgName = '';
        this.orgStreet = '';
        this.orgCity = '';
        this.orgState = 'BC';
        this.orgPostalCode = '';
        this.orgCountry = 'Canada';
        this.orgType = '';
        this.requesterOrgRole = '';
        this.isRegisteredCharity = false;
        this.charityVerificationUrl = '';
        this.charityRegistrationNumber = '';
        this.orgPhone = '';
        this.orgEmail = '';
        this.orgWebsite = '';
        this.orgDescription = '';
        this.verificationDocData = '';
        this.verificationDocFileName = '';
        this.verificationDocUploaded = false;
    }

    handleNeighbourhoodSelect(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedNeighbourhood = this.neighbourhoodOptions.find(n => n.id === id);
    }
    handleClearNeighbourhood() {
        this.selectedNeighbourhood = null;
    }

    handleNotesInput(event) {
        this.notes = event.target.value;
    }

    handleImageUploaded(event) {
        const detail = event.detail || {};
        const base64 = detail.base64;
        const fileName = detail.fileName;
        if (base64 && fileName) {
            this.authImageData = base64;
            this.authImageFileName = fileName;
            this.authImageUploaded = true;
        }
    }

    handleImageSelected(event) {
        const detail = event.detail || {};
        const base64 = detail.base64;
        const fileName = detail.fileName;
        if (!base64 || !fileName) return;

        this.authImageData = base64;
        this.authImageFileName = fileName;
        this.authImageUploaded = true;
    }

    handleNext() {
        if (!this.canProceed) return;
        const steps = this.activeStepList;
        if (this.usePaperPath) {
            this.currentStep = Math.min(this.currentStep + 1, steps.length - 1);
            return;
        }
        let next = this.currentStep + 1;
        if (!this.createOrgMode && steps[next] === 'neighbourhood' && this.isSupportPerson) {
            next += 1;
        }
        this.currentStep = Math.min(next, steps.length - 1);
        if (steps[this.currentStep] === 'neighbourhood' && this.isCommunityGroup && this.selectedIdentity?.id) {
            this._loadNeighbourhoods();
        }
    }

    handleBack() {
        const steps = this.activeStepList;
        if (this.usePaperPath) {
            this.currentStep = Math.max(this.currentStep - 1, 0);
            return;
        }
        let prev = this.currentStep - 1;
        if (!this.createOrgMode && steps[prev] === 'neighbourhood' && this.isSupportPerson) {
            prev -= 1;
        }
        this.currentStep = Math.max(prev, 0);
        if (steps[this.currentStep] === 'neighbourhood' && this.isCommunityGroup && this.selectedIdentity?.id && !this.neighbourhoodOptions.length) {
            this._loadNeighbourhoods();
        }
    }

    handlePaperPathToggle(event) {
        this.usePaperPath = !!event.target.checked;
        this.selectedIdentity = null;
        this.selectedNeighbourhood = null;
    }

    handlePaperFieldChange(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        this[field] = event.target.value;
    }

    handleTosLinkTap() { this.tosLinkTapped = true; }
    handleTosCheckChange(event) { this.tosChecked = !!event.target.checked; }
    handleCgaLinkTap() { this.cgaLinkTapped = true; }
    handleCgaCheckChange(event) { this.cgaChecked = !!event.target.checked; }

    _loadNeighbourhoods() {
        const orgId = this.selectedIdentity?.id;
        if (!orgId) return;
        this.neighbourhoodsLoading = true;
        getNeighbourhoodsForOrganization({ organizationId: orgId })
            .then((results) => {
                this.neighbourhoodOptions = (results || []).map((r) => ({
                    id: r.id,
                    name: r.name
                }));
            })
            .catch(() => {
                this.neighbourhoodOptions = [];
            })
            .finally(() => {
                this.neighbourhoodsLoading = false;
            });
    }

    handleSubmit() {
        if (this.isSubmitting || this.submitDisabled) return;
        this.isSubmitting = true;
        this.error = '';

        if (this.usePaperPath) {
            this._submitPaperDraft();
            return;
        }

        if (this.createOrgMode) {
            this._submitCreateOrgRequest();
            return;
        }

        const params = {
            relationshipType: this.selectedType,
            relatedContactId: this.isSupportPerson ? this.selectedIdentity.id : null,
            relatedOrganizationId: this.isCommunityGroup ? this.selectedIdentity.id : null,
            neighbourhoodId: this.selectedNeighbourhood?.id || this.myNeighbourhoodId,
            authorizationImageData: this.authImageData,
            authorizationImageFileName: this.authImageFileName,
            notes: this.notes,
            cgaAccepted: this.isCommunityGroup ? this.cgaChecked : false,
            cgaVersion: this.isCommunityGroup ? this.cgaVersion : null
        };

        submitRelationshipRequest({ params })
            .then(() => {
                this.isSubmitting = false;
                this.isOpen = false;
                this.dispatchEvent(new CustomEvent('setupcomplete', { bubbles: true, composed: true }));
            })
            .catch(err => {
                this.isSubmitting = false;
                fireErrorToast(err);
            });
    }

    _submitCreateOrgRequest() {
        const params = {
            orgName: this.orgName,
            billingStreet: this.orgStreet,
            billingCity: this.orgCity,
            billingState: this.orgState,
            billingPostalCode: this.orgPostalCode,
            billingCountry: this.orgCountry,
            orgType: this.orgType,
            requesterOrgRole: this.requesterOrgRole,
            isRegisteredCharity: this.isRegisteredCharity,
            charityVerificationUrl: this.charityVerificationUrl,
            charityRegistrationNumber: this.charityRegistrationNumber,
            orgPhone: this.orgPhone,
            orgEmail: this.orgEmail,
            website: this.orgWebsite,
            description: this.orgDescription,
            verificationDocData: this.verificationDocData,
            verificationDocFileName: this.verificationDocFileName,
            authorizationImageData: this.authImageData,
            authorizationImageFileName: this.authImageFileName,
            notes: this.notes,
            cgaAccepted: this.cgaChecked,
            cgaVersion: this.cgaVersion
        };

        createOrganizationRequest({ params })
            .then(() => {
                this.isSubmitting = false;
                this.orgSubmitted = true;
            })
            .catch(err => {
                this.isSubmitting = false;
                fireErrorToast(err);
            });
    }

    handleOrgDoneClose() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('setupcomplete', { bubbles: true, composed: true }));
    }

    handleSuccessDoneClose() {
        if (this.orgSubmitted) {
            this.handleOrgDoneClose();
        } else if (this.paperDraftSubmitted) {
            this.handlePaperDoneClose();
        }
    }

    _submitPaperDraft() {
        const input = {
            firstName: this.paperFirstName,
            lastName: this.paperLastName,
            birthdate: this.paperBirthdate || null,
            mailingStreet: this.paperStreet,
            mailingCity: this.paperCity,
            mailingPostalCode: this.paperPostalCode,
            phone: this.paperPhone,
            email: this.paperEmail,
            supporteeRelationship: this.paperRelationship,
            notes: this.notes
        };

        createPaperDraft({ input })
            .then(() => {
                this.isSubmitting = false;
                this.paperDraftSubmitted = true;
            })
            .catch(err => {
                this.isSubmitting = false;
                fireErrorToast(err, 'Could not create the paper draft. Please try again.');
            });
    }

    handlePaperDoneClose() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('setupcomplete', { bubbles: true, composed: true }));
    }

    handleUploadSelected(event) {
        const detail = event.detail || {};
        if (detail.contentVersionId) {
            this.uploadedContentVersionId = detail.contentVersionId;
        } else if (detail.fileUrl || detail.url) {
            this.uploadedContentVersionId = detail.contentVersionId || null;
        }
    }

    handleUploadComplete(event) {
        const detail = event.detail || {};
        this.uploadedContentVersionId = detail.contentVersionId || detail.contentDocumentId || null;
    }

    async handleSubmitUpload() {
        if (this.isSubmitting) return;
        if (!this.uploadedContentVersionId) {
            this.error = 'Please attach the signed form first.';
            return;
        }
        this.isSubmitting = true;
        this.error = '';
        try {
            await submitPaperUpload({
                srId: this.resumeSrId,
                contentVersionId: this.uploadedContentVersionId
            });
            this.uploadSubmitted = true;
        } catch (err) {
            fireErrorToast(err, 'We could not submit your upload. Please try again.');
        } finally {
            this.isSubmitting = false;
        }
    }

    handleResumeDoneClose() {
        this.isOpen = false;
        this.resumeMode = false;
        this.resumeSrId = null;
        this.uploadedContentVersionId = null;
        this.uploadSubmitted = false;
        this.dispatchEvent(new CustomEvent('setupcomplete', { bubbles: true, composed: true }));
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close();
        }
    }
}