import { LightningElement, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getManagedRelationships from '@salesforce/apex/FimbySupportRelationshipController.getManagedRelationships';
import getMyPaperRelationships from '@salesforce/apex/FimbySupportRelationshipController.getMyPaperRelationships';
import switchIdentity from '@salesforce/apex/FimbySupportRelationshipController.switchIdentity';
import switchToSelf from '@salesforce/apex/FimbySupportRelationshipController.switchToSelf';
import revokeRelationship from '@salesforce/apex/FimbySupportRelationshipController.revokeRelationship';
import deactivateRelationship from '@salesforce/apex/FimbySupportRelationshipController.deactivateRelationship';
import dismissRelationship from '@salesforce/apex/FimbySupportRelationshipController.dismissRelationship';
import confirmRelationship from '@salesforce/apex/FimbySupportRelationshipController.confirmRelationship';
import requestCommunityGroupLifecycleAction from '@salesforce/apex/FimbySupportRelationshipController.requestCommunityGroupLifecycleAction';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';

const ICONS = {
    care: 'care.png',
    people: 'people.png',
    community: 'CommunityReps.png',
    switch: 'switch.png',
    trust: 'trust.png',
    noProfile: 'NoProfilePhoto.png',
    noOrg: 'NoOrgPhoto.png',
    add: 'add.png',
    greenDot: 'GreenCircle.png',
    yellowDot: 'YellowCircle.png',
    redDot: 'RedCircle.png'
};

export default class FimbyManageIdentities extends LightningElement {
    @track peopleISupport = [];
    @track peopleWhoSupportMe = [];
    @track communityGroups = [];
    @track paperRelationships = [];
    @track isLoading = true;
    @track error = null;

    @track showConfirmModal = false;
    @track confirmModalTitle = '';
    @track confirmModalBody = '';
    @track confirmModalAction = '';
    @track confirmModalDanger = false;
    @track _pendingRelId = null;

    @track showDetailModal = false;
    @track detailRecord = null;

    // A2: Community Group lifecycle modals — Close (request review) and
    // Delete (higher-friction, type-the-name confirmation). Both file a
    // Moderator_Task__c via FimbySupportRelationshipController; neither
    // mutates the Account directly.
    @track showCloseGroupModal = false;
    @track showDeleteGroupModal = false;
    @track lifecycleReason = '';
    @track deleteConfirmText = '';
    @track lifecycleError = '';
    @track isLifecycleSubmitting = false;
    @track _lifecycleRelId = null;
    @track _lifecycleGroupName = '';
    _organizationId = null;
    orgAvatarUrls = {};
    orgNames = {};

    get careIconUrl() { return `${IMPACT_ICONS}/${ICONS.care}`; }
    get peopleIconUrl() { return `${IMPACT_ICONS}/${ICONS.people}`; }
    get communityIconUrl() { return `${IMPACT_ICONS}/${ICONS.community}`; }
    get switchIconUrl() { return `${IMPACT_ICONS}/${ICONS.switch}`; }
    get addIconUrl() { return `${IMPACT_ICONS}/${ICONS.add}`; }

    get headerMenuItems() {
        return [
            { key: 'setup', label: 'New', icon: ICONS.add, display: 'inline', variant: 'primary' }
        ];
    }

    handleHeaderMenuAction(event) {
        if (event.detail.key === 'setup') {
            this.handleSetupNew();
        }
    }

    get hasPeopleISupport() { return this.peopleISupport.length > 0; }
    get hasPeopleWhoSupportMe() { return this.peopleWhoSupportMe.length > 0; }
    get hasCommunityGroups() { return this.communityGroups.length > 0; }
    get hasPaperRelationships() { return this.paperRelationships.length > 0; }

    get detailProfileUrl() {
        if (!this.detailRecord?.organizationId) return '#';
        return `/organization-profile?id=${this.detailRecord.organizationId}`;
    }

    connectedCallback() {
        this.loadRelationships();
        this._handleResumeIfRequested();
    }

    _handleResumeIfRequested() {
        try {
            const params = new URLSearchParams(window.location.search);
            const srId = params.get('continueSr');
            if (!srId) return;
            Promise.resolve().then(() => {
                const modal = this.template.querySelector('c-fimby-relationship-setup-modal');
                if (modal && typeof modal.openForUpload === 'function') {
                    modal.openForUpload(srId);
                }
            });
        } catch (e) { /* ignore */ }
    }

    loadRelationships() {
        this.isLoading = true;
        Promise.all([getManagedRelationships(), getOrganizationId()])
            .then(([result, orgId]) => {
                this._organizationId = orgId;
                this.orgAvatarUrls = result.orgAvatarUrls || {};
                this.orgNames = result.orgNames || {};
                this.peopleISupport = this._mapSupport(result.peopleISupport || []);
                this.peopleWhoSupportMe = this._mapSupportMe(result.peopleWhoSupportMe || []);
                this.communityGroups = this._mapGroups(result.communityGroups || []);
                this.isLoading = false;
            })
            .catch(err => {
                this.error = err?.body?.message || 'Something went wrong loading your connections.';
                this.isLoading = false;
            });
        this._loadPaperRelationships();
    }

    _completeImageUrl(url) {
        if (!url) return '';
        if (this._organizationId && !url.includes(this._organizationId)) {
            return url + this._organizationId;
        }
        return url;
    }

    _resolveAvatarUrl(rawUrl, fallbackIcon) {
        return this._completeImageUrl(rawUrl) || `${IMPACT_ICONS}/${fallbackIcon}`;
    }

    _loadPaperRelationships() {
        getMyPaperRelationships()
            .then(rows => {
                this.paperRelationships = (rows || []).map(r => ({
                    id: r.id,
                    status: r.status,
                    statusLabel: this._paperStatusLabel(r.status),
                    statusClass: this._paperStatusClass(r.status),
                    supporteeName: r.supporteeName,
                    supporteeCity: r.supporteeCity,
                    supporteeRelationship: r.supporteeRelationship,
                    sentDate: this._formatDate(r.day0Sent),
                    isDraft: r.status === 'Draft',
                    isPendingReview: r.status === 'Pending Paper Review',
                    isPendingVerification: r.status === 'Pending Verification',
                    isRejected: r.status === 'Rejected',
                    isExpired: r.status === 'Expired',
                    isApproved: r.status === 'Approved'
                })).filter(r => !r.isApproved);
            })
            .catch(() => { this.paperRelationships = []; });
    }

    _paperStatusLabel(status) {
        switch (status) {
            case 'Draft': return 'Awaiting your upload';
            case 'Pending Paper Review': return 'With our team for review';
            case 'Pending Verification': return 'Verifying with the supportee';
            case 'Rejected': return 'Not activated';
            case 'Expired': return 'Expired — re-start any time';
            default: return status;
        }
    }

    _paperStatusClass(status) {
        if (status === 'Pending Paper Review' || status === 'Pending Verification') return 'paper-pill paper-pill--pending';
        if (status === 'Rejected' || status === 'Expired') return 'paper-pill paper-pill--inactive';
        return 'paper-pill paper-pill--draft';
    }

    handlePaperResume(event) {
        const srId = event.currentTarget.dataset.id;
        if (srId) {
            location.href = `/manage-identities?continueSr=${encodeURIComponent(srId)}`;
        }
    }

    _mapSupport(records) {
        return records.map(r => ({
            id: r.Id,
            name: r.Related_Contact__r?.Name || 'Unknown',
            avatarUrl: this._resolveAvatarUrl(r.Related_Contact__r?.Image_URL__c, ICONS.noProfile),
            status: r.Status__c,
            statusClass: this._statusClass(r.Status__c),
            statusDotUrl: this._statusDot(r.Status__c),
            neighbourhood: r.Neighbourhood__r?.Name,
            since: r.Approved_Date__c,
            endedDate: r.Ended_Date__c,
            isApproved: r.Status__c === 'Approved',
            isInactive: r.Status__c === 'Inactive' || r.Status__c === 'Revoked',
            rowClass: (r.Status__c === 'Inactive' || r.Status__c === 'Revoked') ? 'identity-row muted' : 'identity-row',
            helperText: this._helperText(r)
        }));
    }

    _mapSupportMe(records) {
        return records.map(r => ({
            id: r.Id,
            name: r.Contact__r?.Name || 'Unknown',
            avatarUrl: this._resolveAvatarUrl(r.Contact__r?.Image_URL__c, ICONS.noProfile),
            status: r.Status__c,
            statusClass: this._statusClass(r.Status__c),
            statusDotUrl: this._statusDot(r.Status__c),
            neighbourhood: r.Neighbourhood__r?.Name,
            since: r.Approved_Date__c,
            endedDate: r.Ended_Date__c,
            isApproved: r.Status__c === 'Approved',
            isInactive: r.Status__c === 'Inactive' || r.Status__c === 'Revoked',
            rowClass: (r.Status__c === 'Inactive' || r.Status__c === 'Revoked') ? 'identity-row muted' : 'identity-row',
            confirmed: r.Subject_Confirmed__c,
            showConfirm: r.Status__c === 'Approved' && !r.Subject_Confirmed__c,
            helperText: this._helperText(r)
        }));
    }

    _mapGroups(records) {
        return records.map(r => ({
            id: r.Id,
            organizationId: r.Related_Organization__c,
            name: this.orgNames[r.Related_Organization__c] || r.Related_Organization__r?.Name || 'Unknown',
            avatarUrl: this._resolveAvatarUrl(this.orgAvatarUrls[r.Related_Organization__c], ICONS.noOrg),
            status: r.Status__c,
            statusClass: this._statusClass(r.Status__c),
            statusDotUrl: this._statusDot(r.Status__c),
            neighbourhood: r.Neighbourhood__r?.Name,
            since: r.Approved_Date__c,
            endedDate: r.Ended_Date__c,
            isApproved: r.Status__c === 'Approved',
            isInactive: r.Status__c === 'Inactive' || r.Status__c === 'Revoked',
            // A2: marker the Detail Modal uses to swap copy ("Stop representing
            // this group" instead of "Step Back") and to surface the Close +
            // Delete buttons. Anything mapped through _mapGroups is, by
            // definition, a Community_Group_Rep relationship.
            isCommunityGroup: true,
            rowClass: (r.Status__c === 'Inactive' || r.Status__c === 'Revoked') ? 'identity-row muted' : 'identity-row',
            helperText: this._helperText(r)
        }));
    }

    _statusClass(status) {
        if (status === 'Approved') return 'status-pill approved';
        if (status === 'Pending') return 'status-pill pending';
        return 'status-pill inactive';
    }

    _statusDot(status) {
        if (status === 'Approved') return `${IMPACT_ICONS}/${ICONS.greenDot}`;
        if (status === 'Pending') return `${IMPACT_ICONS}/${ICONS.yellowDot}`;
        return `${IMPACT_ICONS}/${ICONS.redDot}`;
    }

    _helperText(r) {
        if (r.Status__c === 'Pending') return 'Awaiting review by the neighbourhood team';
        if (r.Status__c === 'Inactive') return `This connection ended on ${this._formatDate(r.Ended_Date__c)}`;
        if (r.Status__c === 'Revoked') return `Access was revoked on ${this._formatDate(r.Ended_Date__c)}`;
        return '';
    }

    _formatDate(dt) {
        if (!dt) return '';
        try { return new Date(dt).toLocaleDateString(); }
        catch (e) { return ''; }
    }

    handleAccess(event) {
        const relId = event.currentTarget.dataset.id;
        switchIdentity({ relationshipId: relId })
            .then(() => {
                try {
                    sessionStorage.removeItem('fimby-home-feed-state');
                    sessionStorage.removeItem('fimby-library-state');
                } catch (e) { /* ignore */ }
                location.href = '/';
            })
            .catch(err => {
                this.error = err?.body?.message || 'We couldn\'t switch right now. Give it another try?';
            });
    }

    handleRevoke(event) {
        this._pendingRelId = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.confirmModalTitle = 'Update support preferences';
        this.confirmModalBody = `${name} will no longer be able to act on your behalf. Your account and content are unchanged. You can set this up again later if needed.`;
        this.confirmModalAction = 'Revoke Access';
        this.confirmModalDanger = true;
        this.showConfirmModal = true;
    }

    handleStepBack(event) {
        this._pendingRelId = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        const isGroup = event.currentTarget.dataset.isGroup === 'true';
        // A2: branch copy — "Stop representing this group" reads more
        // accurately for Community Groups than the support-person "Step Back"
        // language. Same Apex (deactivateRelationship) handles both paths.
        if (isGroup) {
            this.confirmModalTitle = `Stop representing ${name}?`;
            this.confirmModalBody = `You'll no longer be able to post or act on behalf of ${name}. The group itself stays active in FIMBY for any other approved representatives.`;
            this.confirmModalAction = 'Stop Representing';
        } else {
            this.confirmModalTitle = `Step back from supporting ${name}`;
            this.confirmModalBody = `You'll no longer be able to act on behalf of ${name}. Their account and content are unaffected. You can request to reconnect later.`;
            this.confirmModalAction = 'Step Back';
        }
        this.confirmModalDanger = false;
        this.showConfirmModal = true;
    }

    // ─── A2: Community Group lifecycle ────────────────────────────────

    /** Filter helper for the type-the-name confirm on Delete Group. */
    get isDeleteConfirmDisabled() {
        if (this.isLifecycleSubmitting) return true;
        if (!this._lifecycleGroupName) return true;
        return this.deleteConfirmText.trim().toLowerCase()
            !== this._lifecycleGroupName.toLowerCase();
    }

    /** Ack copy in both lifecycle modals — Always Show Identity. */
    get lifecycleActingAsLabel() {
        if (!this._lifecycleGroupName) return '';
        // The user IS acting as themselves (the rep). The "on behalf of"
        // names the group whose lifecycle they're requesting a change to.
        return `Requesting on behalf of ${this._lifecycleGroupName}`;
    }

    handleCloseGroup(event) {
        const relId = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        if (!relId || !name) return;
        this._lifecycleRelId = relId;
        this._lifecycleGroupName = name;
        this.lifecycleReason = '';
        this.lifecycleError = '';
        this.showCloseGroupModal = true;
    }

    handleDeleteGroup(event) {
        const relId = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        if (!relId || !name) return;
        this._lifecycleRelId = relId;
        this._lifecycleGroupName = name;
        this.lifecycleReason = '';
        this.deleteConfirmText = '';
        this.lifecycleError = '';
        this.showDeleteGroupModal = true;
    }

    handleLifecycleReasonInput(event) {
        this.lifecycleReason = event.target.value;
    }

    handleDeleteConfirmTextInput(event) {
        this.deleteConfirmText = event.target.value;
    }

    handleCloseGroupCancel() {
        if (this.isLifecycleSubmitting) return;
        this.showCloseGroupModal = false;
        this._resetLifecycleState();
    }

    handleDeleteGroupCancel() {
        if (this.isLifecycleSubmitting) return;
        this.showDeleteGroupModal = false;
        this._resetLifecycleState();
    }

    handleCloseGroupConfirm() {
        this._submitLifecycleAction('Close');
    }

    handleDeleteGroupConfirm() {
        if (this.isDeleteConfirmDisabled) return;
        this._submitLifecycleAction('Delete');
    }

    _submitLifecycleAction(action) {
        if (this.isLifecycleSubmitting || !this._lifecycleRelId) return;
        this.isLifecycleSubmitting = true;
        this.lifecycleError = '';

        requestCommunityGroupLifecycleAction({
            relationshipId: this._lifecycleRelId,
            action,
            reason: this.lifecycleReason
        })
            .then(() => {
                this.showCloseGroupModal = false;
                this.showDeleteGroupModal = false;
                this._resetLifecycleState();
                // Tell the user the request landed; nothing visible has changed
                // on their identity list (the Account is untouched until a
                // moderator/admin acts on the task).
                this.confirmModalTitle = action === 'Close'
                    ? 'Request received'
                    : 'Delete request received';
                this.confirmModalBody = action === 'Close'
                    ? "We've sent your request to a moderator. They'll review it and follow up. The group stays active in the meantime."
                    : "We've sent your delete request to a moderator. They'll review it and follow up. Posts and history may be retained for neighbourhood safety and record continuity.";
                this.confirmModalAction = 'OK';
                this.confirmModalDanger = false;
                this._pendingRelId = null;
                this.showConfirmModal = true;
            })
            .catch(err => {
                this.lifecycleError = err?.body?.message
                    || err?.message
                    || "Couldn't send the request. Please try again.";
            })
            .finally(() => {
                this.isLifecycleSubmitting = false;
            });
    }

    _resetLifecycleState() {
        this._lifecycleRelId = null;
        this._lifecycleGroupName = '';
        this.lifecycleReason = '';
        this.deleteConfirmText = '';
        this.lifecycleError = '';
    }

    handleConfirmAction() {
        this.showConfirmModal = false;
        if (!this._pendingRelId) return;

        const action = this.confirmModalDanger
            ? revokeRelationship({ relationshipId: this._pendingRelId })
            : deactivateRelationship({ relationshipId: this._pendingRelId });

        action
            .then(() => { this.loadRelationships(); })
            .catch(err => {
                this.error = err?.body?.message || 'Something went wrong.';
            });
        this._pendingRelId = null;
    }

    handleCancelConfirm() {
        this.showConfirmModal = false;
        this._pendingRelId = null;
    }

    handleDismiss(event) {
        const relId = event.currentTarget.dataset.id;
        const side = event.currentTarget.dataset.side;
        dismissRelationship({ relationshipId: relId, viewerSide: side })
            .then(() => { this.loadRelationships(); })
            .catch(() => {});
    }

    handleConfirmConnection(event) {
        const relId = event.currentTarget.dataset.id;
        confirmRelationship({ relationshipId: relId })
            .then(() => { this.loadRelationships(); })
            .catch(err => {
                this.error = err?.body?.message || 'Could not confirm the connection.';
            });
    }

    handleSetupNew() {
        this.dispatchEvent(new CustomEvent('opensetup'));
        const modal = this.template.querySelector('c-fimby-relationship-setup-modal');
        if (modal) {
            modal.open();
        }
    }

    handleSetupComplete() {
        window.location.reload();
    }

    handleViewDetails(event) {
        const relId = event.currentTarget.dataset.id;
        const section = event.currentTarget.dataset.section;
        let list;
        if (section === 'support') list = this.peopleISupport;
        else if (section === 'supportme') list = this.peopleWhoSupportMe;
        else list = this.communityGroups;
        this.detailRecord = list.find(r => r.id === relId) || null;
        this.showDetailModal = !!this.detailRecord;
    }

    handleCloseDetail() {
        this.showDetailModal = false;
        this.detailRecord = null;
    }
}