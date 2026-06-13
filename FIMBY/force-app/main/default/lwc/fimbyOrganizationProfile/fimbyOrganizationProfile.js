import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate } from 'c/fimbyNavigation';
import getOrganizationProfile from '@salesforce/apex/FimbyOrganizationProfileController.getOrganizationProfile';
import canEditOrganization from '@salesforce/apex/FimbyOrganizationProfileController.canEditOrganization';
import updateOrganizationProfile from '@salesforce/apex/FimbyOrganizationProfileController.updateOrganizationProfile';
import uploadOrganizationLogo from '@salesforce/apex/FimbyOrganizationProfileController.uploadOrganizationLogo';
import removeOrganizationLogo from '@salesforce/apex/FimbyOrganizationProfileController.removeOrganizationLogo';
import { completeImageUrl, avatarImageUrl } from 'c/fimbyImageUrl';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
export default class FimbyOrganizationProfile extends NavigationMixin(LightningElement) {
    @track org = null;
    @track neighbourhoods = [];
    @track people = [];
    @track canEdit = false;
    @track isLoading = true;
    @track error = null;

    @track showImageUploader = false;
    @track isEditing = false;
    @track isSaving = false;
    @track logoUploading = false;
    @track editName = '';
    @track editDescription = '';
    @track editWebsite = '';
    @track editPhone = '';
    @track editBillingStreet = '';
    @track editBillingCity = '';
    @track editBillingState = '';
    @track editBillingPostalCode = '';
    @track editEmail = '';
    @track isMessaging = false;

    actingAsContactId = null;
    orgContactId = null;

    get noOrgPhotoUrl() { return `${IMPACT_ICONS}/NoOrgPhoto.png`; }
    get shieldIconUrl() { return `${IMPACT_ICONS}/shield.png`; }
    get globeIconUrl() { return `${IMPACT_ICONS}/globe.png`; }
    get communityIconUrl() { return `${IMPACT_ICONS}/CommunityReps.png`; }
    get noProfilePhotoUrl() { return `${IMPACT_ICONS}/NoProfilePhoto.png`; }
    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }
    get photoIconUrl() { return `${IMPACT_ICONS}/photo.png`; }
    get emailIconUrl() { return `${IMPACT_ICONS}/email.png`; }

    get orgLogoUrl() {
        const base = this.org?.Logo_URL__c;
        if (!base) return this.noOrgPhotoUrl;
        return completeImageUrl(base) || this.noOrgPhotoUrl;
    }
    get orgName() { return this.org?.Name || ''; }
    get orgType() { return this.org?.Type || 'Organization'; }
    get orgDescription() { return this.org?.Description || this.org?.Description__c || ''; }
    get orgWebsite() { return this.org?.Website || ''; }
    get isApproved() { return this.org?.Is_Approved_Community_Group__c === true; }
    get hasWebsite() { return !!this.orgWebsite; }
    get hasDescription() { return !!this.orgDescription; }
    get hasNeighbourhoods() { return this.neighbourhoods.length > 0; }
    get hasPeople() { return this.people.length > 0; }
    get hasLogo() { return !!this.org?.Logo_URL__c; }

    get orgEmail() { return this.org?.Email || ''; }
    get orgPhone() { return this.org?.Phone || ''; }
    get orgAddress() {
        const parts = [
            this.org?.BillingStreet,
            this.org?.BillingCity,
            this.org?.BillingState,
            this.org?.BillingPostalCode
        ].filter(Boolean);
        return parts.join(', ');
    }
    get orgEmailHref() { return 'mailto:' + this.orgEmail; }
    get orgPhoneHref() { return 'tel:' + this.orgPhone; }
    get hasEmail() { return !!this.orgEmail; }
    get hasPhone() { return !!this.orgPhone; }
    get hasAddress() { return !!this.orgAddress; }
    get hasContactInfo() { return this.hasEmail || this.hasPhone || this.hasAddress; }
    get showMessageButton() {
        return !!this.orgContactId && this.actingAsContactId !== this.orgContactId;
    }

    get peopleWithAvatarUrls() {
        if (!this.people || !this.people.length) return [];
        return this.people.map(p => ({
            ...p,
            avatarUrl: p.avatarUrl ? avatarImageUrl(p.avatarUrl) : this.noProfilePhotoUrl
        }));
    }

    connectedCallback() {
        this._loadProfile();
    }

    async _loadProfile() {
        const urlParams = new URLSearchParams(window.location.search);
        const orgId = urlParams.get('id') || this._extractIdFromPath();

        if (!orgId) {
            this.error = 'Organization not found.';
            this.isLoading = false;
            return;
        }

        this.error = null;
        this.isLoading = true;

        try {
            const [profileResult, canEditResult, identityResult] = await Promise.all([
                getOrganizationProfile({ organizationId: orgId }),
                canEditOrganization({ organizationId: orgId }),
                getActingAsContact()
            ]);

            if (!profileResult?.success) {
                this.error = 'Could not load organization.';
                return;
            }

            this.org = profileResult.org;
            this.neighbourhoods = profileResult.neighbourhoods || [];
            this.people = profileResult.people || [];
            this.canEdit = canEditResult === true;
            this.orgContactId = this.org?.Organization_Contact__c || null;
            this.actingAsContactId = identityResult?.actingAsContactId || null;
        } catch (err) {
            this.error = err?.body?.message || 'Could not load organization.';
        } finally {
            this.isLoading = false;
        }
    }

    _extractIdFromPath() {
        const path = window.location.pathname;
        const parts = path.split('/');
        const orgIndex = parts.indexOf('organization');
        if (orgIndex >= 0 && parts.length > orgIndex + 1) {
            return parts[orgIndex + 1];
        }
        return null;
    }

    // ============================================
    // EDIT HANDLERS
    // ============================================
    handleEditClick() {
        this.editName = this.org?.Name || '';
        this.editDescription = this.org?.Description || '';
        this.editWebsite = this.org?.Website || '';
        this.editPhone = this.org?.Phone || '';
        this.editBillingStreet = this.org?.BillingStreet || '';
        this.editBillingCity = this.org?.BillingCity || '';
        this.editBillingState = this.org?.BillingState || '';
        this.editBillingPostalCode = this.org?.BillingPostalCode || '';
        this.editEmail = this.org?.Email || '';
        this.isEditing = true;
    }

    handleCancelEdit() {
        this.isEditing = false;
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;
    }

    async handleSaveEdit() {
        if (!this.org?.Id) return;
        this.isSaving = true;
        try {
            await updateOrganizationProfile({
                organizationId: this.org.Id,
                fieldValues: {
                    Name: this.editName,
                    Description: this.editDescription,
                    Website: this.editWebsite,
                    Phone: this.editPhone,
                    BillingStreet: this.editBillingStreet,
                    BillingCity: this.editBillingCity,
                    BillingState: this.editBillingState,
                    BillingPostalCode: this.editBillingPostalCode,
                    Email: this.editEmail
                }
            });
            this.isEditing = false;
            this.showToast('Saved', 'Organization updated.', 'success');
            await this._loadProfile();
        } catch (err) {
            this.showToast('Error', err?.body?.message || 'Could not save changes.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ============================================
    // LOGO HANDLERS
    // ============================================
    handleLogoClick() {
        if (!this.canEdit) return;
        this.showImageUploader = !this.showImageUploader;
    }

    async handleImageSelected(event) {
        const detail = event.detail || {};
        const base64 = detail.base64;
        const fileName = detail.fileName;
        const width = detail.width || 0;
        const height = detail.height || 0;
        if (!base64 || !fileName || !this.org?.Id) return;

        this.logoUploading = true;
        try {
            await uploadOrganizationLogo({
                organizationId: this.org.Id,
                fileData: base64,
                fileName,
                imageWidth: width,
                imageHeight: height
            });
            this.showImageUploader = false;
            this.showToast('Success', 'Logo updated.', 'success');
            await this._loadProfile();
        } catch (err) {
            this.showToast('Error', err?.body?.message || 'Could not upload logo.', 'error');
        } finally {
            this.logoUploading = false;
        }
    }

    async handleRemoveLogo() {
        if (!this.org?.Id || !this.canEdit) return;
        try {
            await removeOrganizationLogo({ organizationId: this.org.Id });
            this.showImageUploader = false;
            this.showToast('Success', 'Logo removed.', 'success');
            await this._loadProfile();
        } catch (err) {
            this.showToast('Error', err?.body?.message || 'Could not remove logo.', 'error');
        }
    }

    handleMessage() {
        if (!this.orgContactId) return;
        navigate(this, '/conversation?contactId=' + this.orgContactId);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}