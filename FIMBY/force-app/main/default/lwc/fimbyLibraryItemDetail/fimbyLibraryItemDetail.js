import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { getCategoryIconUrl } from 'c/fimbyLibraryCategoryConfig';
import { formatLocalDate, parseLocalDate } from 'c/fimbyDateUtils';
import getOrganizationId from '@salesforce/apex/FimbyHomeController.getOrganizationId';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import deleteLibraryItem from '@salesforce/apex/FimbyLibraryController.deleteLibraryItem';
import getLibraryItemUserContext from '@salesforce/apex/FimbyLibraryController.getLibraryItemUserContext';
import getLibraryItemAdmin from '@salesforce/apex/FimbyLibraryController.getLibraryItemAdmin';
import getLibraryItemVisibility from '@salesforce/apex/FimbyLibraryController.getLibraryItemVisibility';
import cancelLendingRequest from '@salesforce/apex/FimbyLendingController.cancelLendingRequest';
import declineLendingRequest from '@salesforce/apex/FimbyLendingController.declineLendingRequest';
import isVouchedForBorrowing from '@salesforce/apex/FimbyLibraryController.isVouchedForBorrowing';
import { getModeratorContext } from 'c/fimbyModeratorContext';
import flagContent from '@salesforce/apex/FimbyModeratorDashboardController.flagContent';
import getOrCreateModeratorConversation from '@salesforce/apex/FimbyModeratorDashboardController.getOrCreateModeratorConversation';

const FIELDS = [
    'Library_Item__c.Id',
    'Library_Item__c.Name',
    'Library_Item__c.Description__c',
    'Library_Item__c.Image_URL__c',
    'Library_Item__c.Image_Ratio__c',
    'Library_Item__c.Status__c',
    'Library_Item__c.Category__c',
    'Library_Item__c.Owner_Contact__c',
    'Library_Item__c.Owner_Contact__r.Name',
    'Library_Item__c.Owner_Contact__r.Full_Name__c',
    'Library_Item__c.Owner_Contact__r.Image_URL__c',
    'Library_Item__c.Owner_Organization__c',
    'Library_Item__c.Owner_Organization__r.Name',
    'Library_Item__c.OwnerId',
    'Library_Item__c.Owned_By__c',
    'Library_Item__c.Neighbourhood__c',
    'Library_Item__c.Max_Lending_Time_In_Days__c',
    'Library_Item__c.Expected_Return_Date__c',
    'Library_Item__c.On_Loan_Return_Date__c',
    'Library_Item__c.Auto_Accept_Requests__c',
    'Library_Item__c.Auto_Share_Contact_Info__c'
];

export default class FimbyLibraryItemDetail extends NavigationMixin(LightningElement) {
    @api recordId;
    @track _extractedRecordId = null;
    @track isLoading = true;
    @track showImageModal = false;
    @track showPhotoUploader = false;
    @track showDeleteConfirm = false;
    @track isDeleting = false;

    // Removal modal state
    @track showRemoveConfirm = false;
    @track removeTargetId = null;
    @track removeTargetName = '';
    @track removeReason = '';
    @track isRemoving = false;

    record;
    error;
    currentUserId = Id;
    organizationId = null;
    @track actingAsContactId = null;
    @track _isModeratorForNeighbourhood = false;
    @track isRemoved = false;
    @track removedMessage = '';
    _wiredRecordResult;

    // Requester context
    @track userContext = null;
    @track userContextLoaded = false;

    // Owner admin data
    @track adminData = null;
    @track adminDataLoaded = false;

    // ============================================
    // LIFECYCLE
    // ============================================

    _pendingAction = null;
    _pendingActionId = null;
    _lastAutoOpenedActionKey = null;

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (!pageRef?.state?.action) return;
        const action = pageRef.state.action;
        const actionId = pageRef.state.loanId || pageRef.state.requestId || '';
        const actionKey = `${action}:${actionId}`;
        if (actionKey === this._lastAutoOpenedActionKey) return;
        this._pendingAction = action;
        this._pendingActionId = actionId;
        this._tryAutoOpenActionModal();
    }

    async connectedCallback() {
        await this.loadOrganizationId();
        if (!this.recordId || String(this.recordId).trim() === '') {
            const id = this.extractRecordIdFromUrl();
            this._extractedRecordId = id;
            if (id) {
                this.recordId = id;
            }
        }
        this._checkModeratorStatus();
    }

    async _checkModeratorStatus() {
        try {
            const ctx = await getModeratorContext();
            this._isModeratorForNeighbourhood = ctx.isModerator;
        } catch (e) { /* noop */ }
    }

    renderedCallback() {
        this._tryAutoOpenActionModal();
    }

    async loadOrganizationId() {
        try {
            this.organizationId = await getOrganizationId();
        } catch (error) {
            console.error('Error fetching Organization ID:', error);
        }
    }

    get effectiveRecordId() {
        return this.recordId || this._extractedRecordId;
    }

    extractRecordIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            const queryRecordId = url.searchParams.get('recordId');
            if (queryRecordId) return queryRecordId;

            const pathParts = url.pathname.split('/').filter(part => part && part !== 's');
            const idx = pathParts.findIndex(part => part === 'library-item' || part === 'library-detail');
            if (idx !== -1 && pathParts.length > idx + 1) {
                const potentialId = pathParts[idx + 1];
                if (potentialId && /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(potentialId)) {
                    return potentialId;
                }
            }
            return null;
        } catch (e) {
            return null;
        }
    }

    // ============================================
    // WIRE ADAPTERS
    // ============================================

    @wire(getActingAsContact)
    wiredActingAs({ data }) {
        if (data?.success) {
            this.actingAsContactId = data.actingAsContactId || data.contactId;
            if (this.record && !this.adminDataLoaded) {
                this.loadAdminDataIfOwner();
            }
        }
    }

    @wire(getLibraryItemVisibility, { recordId: '$effectiveRecordId' })
    wiredVisibility({ data, error }) {
        if (data) {
            if (data.removed) {
                this.isRemoved = true;
                this.removedMessage = data.message || 'This item is no longer available.';
                this.isLoading = false;
                this.record = undefined;
            } else {
                this.isRemoved = false;
                this.removedMessage = '';
            }
        } else if (error) {
            console.error('Error checking content visibility:', error);
            this.isRemoved = true;
            this.removedMessage = 'This item is no longer available.';
            this.isLoading = false;
            this.record = undefined;
        }
    }

    @wire(getRecord, { recordId: '$recordIdIfVisible', fields: FIELDS })
    wiredRecord(result) {
        this._wiredRecordResult = result;
        const { error, data } = result;
        if (this.isRemoved) {
            return;
        }
        this.isLoading = false;
        if (data) {
            this.record = data;
            this.error = undefined;
            this.loadContextData();
        } else if (error) {
            console.error('Error loading library item record:', error);
            this.error = error;
            this.record = undefined;
        }
    }

    get recordIdIfVisible() {
        return this.isRemoved ? null : this.effectiveRecordId;
    }

    get shouldRenderRecord() {
        return !!this.record && !this.isRemoved;
    }

    async loadContextData() {
        if (!this.recordId) return;
        try {
            const ctx = await getLibraryItemUserContext({ itemId: this.recordId });
            if (ctx?.success) {
                this.userContext = ctx;
            }
        } catch (e) {
            console.error('Error loading user context:', e);
        }
        this.userContextLoaded = true;
        await this.loadAdminDataIfOwner();
    }

    async loadAdminDataIfOwner() {
        if (this.adminDataLoaded || !this.isOwner || !this.recordId) return;
        try {
            const admin = await getLibraryItemAdmin({ itemId: this.recordId });
            if (admin?.success) {
                this.adminData = admin;
            }
        } catch (e) {
            console.error('Error loading admin data:', e);
        }
        this.adminDataLoaded = true;
    }

    // ============================================
    // ICONS
    // ============================================

    get ownerInfoIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }
    get availabilityIconUrl() { return `${IMPACT_ICONS}/ToolboxActive.png`; }
    get settingsIconUrl() { return `${IMPACT_ICONS}/gear.png`; }
    get borrowIconUrl() { return `${IMPACT_ICONS}/borrow.png`; }
    get flagIconUrl() { return `${IMPACT_ICONS}/red-flag.png`; }
    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }
    get photoIconUrl() { return `${IMPACT_ICONS}/photo.png`; }
    get trashIconUrl() { return `${IMPACT_ICONS}/trash.png`; }
    get noProfilePhotoUrl() { return `${IMPACT_ICONS}/NoProfilePhoto.png`; }
    get historyIconUrl() { return `${IMPACT_ICONS}/plannersm.png`; }
    get messageIconUrl() { return `${IMPACT_ICONS}/chat.png`; }

    get headerMenuItems() {
        if (this.isOwner) {
            return [
                { key: 'edit', label: 'Edit', icon: 'edit.png', display: 'responsive' },
                { key: 'photo', label: 'Photo', icon: 'photo.png', display: 'responsive' },
                { key: 'delete', label: 'Delete', icon: 'trash.png', display: 'responsive', variant: 'danger' }
            ];
        }
        const items = [
            { key: 'flag', label: 'Report', icon: 'warning.png', display: 'kebab' }
        ];
        if (this._isModeratorForNeighbourhood) {
            items.push(
                { key: 'mod-flag', label: 'Review as Moderator', icon: 'analysis.png', display: 'kebab' },
                { key: 'mod-hide', label: 'Hide Content', icon: 'protection.png', display: 'kebab' },
                { key: 'mod-contact', label: 'Contact Owner', icon: 'chat.png', display: 'kebab' }
            );
        }
        return items;
    }

    handleHeaderMenuAction(event) {
        const actions = {
            edit: () => this.handleEdit(),
            photo: () => this.handleUploadPhoto(),
            delete: () => this.handleDeleteClick(),
            flag: () => this.handleFlag(),
            'mod-flag': () => this._handleModeratorFlag(),
            'mod-hide': () => this._handleModeratorHide(),
            'mod-contact': () => this._handleModeratorContact()
        };
        const handler = actions[event.detail.key];
        if (handler) handler();
    }
    get noPhotoUrl() { return `${IMPACT_ICONS}/NoPhoto.png`; }

    // ============================================
    // BASIC GETTERS
    // ============================================

    get detailPageTitle() { return 'Item Details'; }

    get ownerLabel() {
        return this.ownerName ? `by ${this.ownerName}` : 'Owner';
    }

    get itemName() {
        const raw = this.record ? getFieldValue(this.record, 'Library_Item__c.Name') : '';
        return this.decodeHtmlEntities(raw);
    }

    get description() {
        const raw = this.record ? getFieldValue(this.record, 'Library_Item__c.Description__c') : '';
        return this.decodeHtmlEntities(raw);
    }

    decodeHtmlEntities(text) {
        if (!text) return text;
        const textarea = document.createElement('textarea');
        textarea.innerHTML = text;
        return textarea.value;
    }

    get hasDescription() { return !!this.description; }

    get showCardLeft() {
        return this.hasImage || this.isOwner;
    }

    get showStatusInRight() {
        return !this.showCardLeft;
    }

    get cardLayoutClass() {
        return this.showCardLeft ? 'card-layout card-layout-horizontal' : 'card-layout';
    }

    get imageUrl() {
        const baseUrl = this.record ? getFieldValue(this.record, 'Library_Item__c.Image_URL__c') : '';
        if (!baseUrl) return '';
        if (this.organizationId && !baseUrl.includes(this.organizationId)) {
            return baseUrl + this.organizationId;
        }
        return baseUrl;
    }

    get hasImage() {
        const baseUrl = this.record ? getFieldValue(this.record, 'Library_Item__c.Image_URL__c') : '';
        return !!baseUrl && baseUrl.trim() !== '';
    }

    get imageAspectRatio() {
        const ratioString = this.record ? getFieldValue(this.record, 'Library_Item__c.Image_Ratio__c') : '';
        if (!ratioString) return '16 / 9';
        try {
            const parts = ratioString.toUpperCase().split('X');
            const w = parseInt(parts[0], 10);
            const h = parseInt(parts[1], 10);
            if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) return '16 / 9';
            return `${w} / ${h}`;
        } catch (e) { return '16 / 9'; }
    }

    get imageContainerStyle() {
        return `aspect-ratio: ${this.imageAspectRatio}; max-height: 400px;`;
    }

    get status() {
        return this.record ? getFieldValue(this.record, 'Library_Item__c.Status__c') : '';
    }

    get category() {
        return this.record ? getFieldValue(this.record, 'Library_Item__c.Category__c') : '';
    }

    get categoryIconUrl() {
        return this.category ? getCategoryIconUrl(IMPACT_ICONS, this.category) : '';
    }

    get isAvailable() { return this.status === 'Available'; }

    // ============================================
    // OWNER INFO
    // ============================================

    get ownerName() {
        if (!this.record) return '';
        return getFieldValue(this.record, 'Library_Item__c.Owner_Contact__r.Full_Name__c') ||
               getFieldValue(this.record, 'Library_Item__c.Owner_Contact__r.Name') || '';
    }

    get ownerAvatar() {
        const baseUrl = this.record ? getFieldValue(this.record, 'Library_Item__c.Owner_Contact__r.Image_URL__c') : '';
        if (!baseUrl) return '';
        if (this.organizationId && !baseUrl.includes(this.organizationId)) {
            return baseUrl + this.organizationId;
        }
        return baseUrl;
    }

    _completeAvatarUrl(url) {
        if (!url) return '';
        if (this.organizationId && !url.includes(this.organizationId)) {
            return url + this.organizationId;
        }
        return url;
    }

    get ownerOrganizationName() {
        return this.record ? getFieldValue(this.record, 'Library_Item__c.Owner_Organization__r.Name') : '';
    }

    get ownedBy() {
        return this.record ? getFieldValue(this.record, 'Library_Item__c.Owned_By__c') : '';
    }

    // ============================================
    // AVAILABILITY
    // ============================================

    get neighbourhood() {
        return this.record ? getFieldValue(this.record, 'Library_Item__c.Neighbourhood__c') : '';
    }

    get maxLendingDays() {
        const v = this.record ? getFieldValue(this.record, 'Library_Item__c.Max_Lending_Time_In_Days__c') : null;
        return v != null ? v : '';
    }

    get expectedReturnDate() {
        const d = this.record ? getFieldValue(this.record, 'Library_Item__c.Expected_Return_Date__c') : '';
        return formatLocalDate(d);
    }

    get onLoanReturnDate() {
        const d = this.record ? getFieldValue(this.record, 'Library_Item__c.On_Loan_Return_Date__c') : '';
        return formatLocalDate(d);
    }

    // ============================================
    // SETTINGS
    // ============================================

    get autoAcceptRequests() {
        return this.record ? getFieldValue(this.record, 'Library_Item__c.Auto_Accept_Requests__c') : false;
    }

    get autoShareContactInfo() {
        return this.record ? getFieldValue(this.record, 'Library_Item__c.Auto_Share_Contact_Info__c') : false;
    }

    get autoAcceptLabel() { return this.autoAcceptRequests ? 'Yes' : 'No'; }
    get autoShareLabel() { return this.autoShareContactInfo ? 'Yes' : 'No'; }

    // ============================================
    // AUTHOR CHECK (with acting-as contact support)
    // ============================================

    get isOwner() {
        if (!this.record) return false;
        const ownerId = getFieldValue(this.record, 'Library_Item__c.OwnerId');
        const ownerContactId = getFieldValue(this.record, 'Library_Item__c.Owner_Contact__c');
        if (this.currentUserId && ownerId && this.currentUserId === ownerId) return true;
        if (this.actingAsContactId && ownerContactId && this.actingAsContactId === ownerContactId) return true;
        return false;
    }

    get isNotOwner() { return !this.isOwner; }
    get deleteButtonLabel() { return this.isDeleting ? 'Deleting...' : 'Delete'; }

    // eslint-disable-next-line no-unused-vars
    stopPropagation(event) { event.stopPropagation(); }

    // ============================================
    // REQUESTER CONTEXT BANNERS — full lifecycle
    // ============================================

    get showRequesterBanner() {
        return this.isNotOwner && this.userContextLoaded && (this.hasActiveRequest || this.hasActiveLoan);
    }

    get hasActiveRequest() { return this.userContext?.hasActiveRequest === true; }
    get hasActiveLoan() { return this.userContext?.hasActiveLoan === true; }
    get requestStatus() { return this.userContext?.request?.status || ''; }
    get requestWaitlistPosition() { return this.userContext?.request?.waitlistPosition; }
    get loanDueDate() {
        return formatLocalDate(this.userContext?.loan?.dueDate);
    }
    get loanStatus() { return this.userContext?.loan?.status || ''; }
    get loanStatusDerived() { return this.userContext?.loan?.loanStatusDerived || 'onLoan'; }

    get isOverdue() {
        return this.hasActiveLoan && this.loanStatusDerived === 'overdue';
    }

    get daysOverdue() {
        const due = parseLocalDate(this.userContext?.loan?.dueDate);
        if (!due) return 0;
        const now = new Date();
        due.setHours(0, 0, 0, 0);
        now.setHours(0, 0, 0, 0);
        const diff = Math.floor((now - due) / (1000 * 60 * 60 * 24));
        return diff > 0 ? diff : 0;
    }

    get overduePillLabel() {
        const days = this.daysOverdue;
        if (days === 0) return 'Overdue';
        return `${days} ${days === 1 ? 'Day' : 'Days'} Overdue`;
    }

    get bannerMessage() {
        if (this.hasActiveLoan) {
            const phase = this.loanStatusDerived;
            if (phase === 'overdue') return 'Please return it as soon as you can.';
            if (phase === 'extensionRequested') return 'Extension requested \u2014 waiting for the owner.';
            if (phase === 'returnPending') return "You've confirmed return \u2014 waiting for the owner to verify.";
            return `You have this item \u2014 due ${this.loanDueDate}`;
        }
        const status = this.requestStatus;
        if (status === 'Pending Approval') return 'Your request is waiting for the owner to review it.';
        if (status === 'Waitlisted') {
            const pos = this.requestWaitlistPosition;
            return pos ? `You're on the waitlist \u2014 #${pos} in line.` : "You're on the waitlist.";
        }
        if (status === 'Requesting Confirmation') return "It's your turn \u2014 confirm you still want this item.";
        if (status === 'Approved') return 'Approved \u2014 Pickup Pending';
        return '';
    }

    get bannerVariant() {
        if (this.hasActiveLoan) {
            const phase = this.loanStatusDerived;
            if (phase === 'overdue') return 'warning';
            return 'success';
        }
        const status = this.requestStatus;
        if (status === 'Approved') return 'info';
        if (status === 'Requesting Confirmation') return 'info';
        return 'neutral';
    }

    get attentionTier() {
        if (this.hasActiveLoan) {
            const phase = this.loanStatusDerived;
            if (phase === 'overdue') return 'urgent';
            if (phase === 'onLoan') return 'strong';
            return 'subtle';
        }
        const status = this.requestStatus;
        if (status === 'Requesting Confirmation' || status === 'Approved') return 'strong';
        return 'subtle';
    }

    get requesterSectionClass() {
        return `info-section requester-section requester-section-${this.bannerVariant} cta-strip-${this.attentionTier}`;
    }

    // Loan-phase action visibility
    get showBannerReturnAction() {
        if (!this.hasActiveLoan) return false;
        const phase = this.loanStatusDerived;
        return phase === 'onLoan' || phase === 'overdue';
    }

    get showBannerExtensionAction() {
        return this.hasActiveLoan && this.loanStatusDerived === 'onLoan';
    }

    get showBannerMessageOwner() {
        if (this.hasActiveLoan) {
            return !!this.userContext?.loan?.conversationId;
        }
        return this.requestStatus === 'Approved' && !!this.userContext?.request?.conversationId;
    }

    get messageOwnerUrl() {
        const convId = this.hasActiveLoan
            ? this.userContext?.loan?.conversationId
            : this.userContext?.request?.conversationId;
        return convId ? `/conversation?id=${convId}` : '#';
    }

    // Request-phase action visibility
    get showBannerConfirmAction() {
        return this.requestStatus === 'Requesting Confirmation';
    }

    get showBannerConfirmPickup() {
        return this.requestStatus === 'Approved';
    }

    get showBannerCancelRequest() {
        if (!this.hasActiveRequest) return false;
        const status = this.requestStatus;
        return ['Waitlisted', 'Requesting Confirmation', 'Pending Approval', 'Approved'].includes(status);
    }

    handleBannerRequestExtension() {
        const loanId = this.userContext?.loan?.id;
        if (!loanId) return;
        const modal = this.template.querySelector('c-fimby-loan-extension-modal');
        if (modal) modal.show(loanId);
    }

    handleBannerConfirmWaitlist() {
        const reqId = this.userContext?.request?.id;
        if (!reqId) return;
        const modal = this.template.querySelector('c-fimby-lending-confirmation-modal');
        if (modal) modal.show(reqId);
    }

    get showBorrowAction() {
        if (this.isOwner) return false;
        if (this.hasActiveLoan || this.hasActiveRequest) return false;
        return this.isAvailable;
    }

    get showOnLoanInfo() {
        if (this.isOwner) return false;
        if (this.hasActiveLoan || this.hasActiveRequest) return false;
        return !this.isAvailable && this.expectedReturnDate;
    }

    get showJoinWaitlist() {
        if (this.isOwner) return false;
        if (this.hasActiveLoan || this.hasActiveRequest) return false;
        return !this.isAvailable;
    }

    // ============================================
    // BORROWER HISTORY
    // ============================================

    get hasBorrowerHistory() {
        const hist = this.userContext?.borrowerHistory;
        return Array.isArray(hist) && hist.length > 0;
    }

    get borrowerHistory() {
        const hist = this.userContext?.borrowerHistory;
        if (!Array.isArray(hist)) return [];
        return hist.map(h => ({
            ...h,
            lenderAvatar: this._completeAvatarUrl(h.lenderAvatar),
            displayStartDate: formatLocalDate(h.startDate),
            displayEndDate: h.endDate ? formatLocalDate(h.endDate) : 'Ongoing',
            hasConversation: !!h.conversationId,
            conversationUrl: h.conversationId ? `/conversation?id=${h.conversationId}` : ''
        }));
    }

    // ============================================
    // NAVIGATION
    // ============================================

    handleTabChange(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: event.detail.tab }
        });
    }

    // ============================================
    // ACTION HANDLERS
    // ============================================

    handleEdit() {
        const modal = this.template.querySelector('c-fimby-record-edit-modal');
        if (modal) modal.show();
    }

    async handleEditSave() {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Item updated', variant: 'success' }));
        if (this._wiredRecordResult) {
            await refreshApex(this._wiredRecordResult);
        }
    }

    handleEditCancel() {}

    async handleBorrow() {
        // Vouching gate: settling-in members cannot borrow.
        const vouched = await this._checkVouched();
        if (vouched === false) {
            const gateModal = this.template.querySelector('c-fimby-vouching-required-modal');
            if (gateModal) gateModal.show();
            return;
        }
        const modal = this.template.querySelector('c-fimby-quick-response-modal');
        if (modal) modal.show(this.recordId, 'library', { isItemAvailable: this.isAvailable });
    }

    async _checkVouched() {
        try {
            const result = await isVouchedForBorrowing();
            return result === true;
        } catch (e) {
            console.error('Vouching check error', e);
            return false;
        }
    }

    handleDetailResponseSaved() {
        this._responseSavedPending = true;
    }

    handleResponseModalClosed() {
        if (this._responseSavedPending) {
            this._responseSavedPending = false;
            window.location.reload();
        }
    }

    handleUploadPhoto() {
        this.showPhotoUploader = !this.showPhotoUploader;
    }

    handleClosePhotoUploader() {
        this.showPhotoUploader = false;
    }

    handlePhotoUploaded() {
        this.showPhotoUploader = false;
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Photo uploaded', variant: 'success' }));
        window.location.reload();
    }

    handleFlag() {
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) modal.show(this.recordId, 'Library_Item__c');
    }

    // ============================================
    // DELETE HANDLERS
    // ============================================

    handleDeleteClick() {
        this.showDeleteConfirm = true;
    }

    handleDeleteCancel() {
        this.showDeleteConfirm = false;
    }

    async handleDeleteConfirm() {
        this.isDeleting = true;
        try {
            await deleteLibraryItem({ recordId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', message: 'Item has been deleted', variant: 'success' }));
            window.location.href = '/library-list/';
        } catch (error) {
            console.error('Delete error:', error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Failed to delete item',
                variant: 'error'
            }));
        } finally {
            this.isDeleting = false;
            this.showDeleteConfirm = false;
        }
    }

    // ============================================
    // IMAGE MODAL
    // ============================================

    handleImageClick() {
        if (this.hasImage) {
            this.showImageModal = true;
            document.body.style.overflow = 'hidden';
        }
    }

    handleCloseImageModal() {
        this.showImageModal = false;
        document.body.style.overflow = '';
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape') this.handleCloseImageModal();
    }

    // ============================================
    // LENDING APPROVAL MODAL
    // ============================================

    handleReviewRequest(event) {
        const { requestId } = event.detail;
        const modal = this.template.querySelector('c-fimby-lending-approval-modal');
        if (modal) modal.show(requestId);
    }

    async handleApprovalComplete() {
        this.adminDataLoaded = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.loadContextData();
    }

    // ============================================
    // ITEM RETURN MODAL
    // ============================================

    handleVerifyReturn(event) {
        const { loanId } = event.detail;
        const modal = this.template.querySelector('c-fimby-item-return-modal');
        if (modal) modal.show(loanId);
    }

    handleBorrowerReturn() {
        const loanId = this.userContext?.loan?.id;
        if (!loanId) return;
        const modal = this.template.querySelector('c-fimby-item-return-modal');
        if (modal) modal.show(loanId);
    }

    async handleReturnComplete() {
        this.userContextLoaded = false;
        this.adminDataLoaded = false;
        this.userContext = null;
        this.adminData = null;
        if (this.recordId) {
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }
        await this.loadContextData();
        this._cleanUpUrlParams();
    }

    _tryAutoOpenActionModal() {
        if (!this._pendingAction || !this._pendingActionId) return;
        const actionKey = `${this._pendingAction}:${this._pendingActionId}`;
        if (actionKey === this._lastAutoOpenedActionKey) return;

        const action = this._pendingAction;
        const id = this._pendingActionId;

        if (!this._isActionDataReady(action)) return;

        if (!this._isActionStillValid(action)) {
            this._consumePendingAction(actionKey);
            return;
        }

        let modal;

        switch (action) {
            case 'return':
            case 'verifyReturn':
            case 'confirmReturn':
                modal = this.template.querySelector('c-fimby-item-return-modal');
                if (modal) { modal.show(id); }
                break;
            case 'reviewRequest':
                modal = this.template.querySelector('c-fimby-lending-approval-modal');
                if (modal) { modal.show(id); }
                break;
            case 'confirmPickup':
                modal = this.template.querySelector('c-fimby-pickup-confirmation-modal');
                if (modal) { modal.show(id); }
                break;
            case 'confirmWaitlist':
                modal = this.template.querySelector('c-fimby-lending-confirmation-modal');
                if (modal) { modal.show(id); }
                break;
            case 'requestExtension':
                modal = this.template.querySelector('c-fimby-loan-extension-modal');
                if (modal) { modal.show(id); }
                break;
            case 'approveExtension':
                modal = this.template.querySelector('c-fimby-loan-extension-approval-modal');
                if (modal) { modal.show(id); }
                break;
            default:
                return;
        }

        if (modal) {
            this._consumePendingAction(actionKey);
        }
    }

    _isActionDataReady(action) {
        switch (action) {
            case 'confirmPickup':
            case 'confirmWaitlist':
            case 'requestExtension':
            case 'return':
                return this.userContextLoaded;
            case 'reviewRequest':
            case 'verifyReturn':
            case 'confirmReturn':
            case 'approveExtension':
                return this.adminDataLoaded;
            default:
                return true;
        }
    }

    _isActionStillValid(action) {
        switch (action) {
            case 'confirmPickup':
                return this.userContext?.request?.status === 'Approved';
            case 'confirmWaitlist':
                return this.userContext?.request?.status === 'Requesting Confirmation';
            case 'requestExtension':
            case 'return':
                return this.userContext?.hasActiveLoan === true;
            case 'verifyReturn':
            case 'confirmReturn':
                return this.adminData?.currentLoan?.returnConfirmedByBorrower === true
                    || this.adminData?.currentLoan?.loanStatusDerived === 'returnPending';
            default:
                return true;
        }
    }

    _consumePendingAction(actionKey) {
        this._lastAutoOpenedActionKey = actionKey;
        this._pendingAction = null;
        this._pendingActionId = null;
        this._cleanUpUrlParams();
    }

    _cleanUpUrlParams() {
        try {
            const url = new URL(window.location.href);
            let changed = false;
            for (const key of ['action', 'requestId', 'loanId']) {
                if (url.searchParams.has(key)) {
                    url.searchParams.delete(key);
                    changed = true;
                }
            }
            if (changed) {
                window.history.replaceState({}, '', url.toString());
            }
        } catch (_e) { /* ignore in non-browser contexts */ }
    }

    // ============================================
    // HANDOFF + CANCEL + REMOVE HANDLERS
    // ============================================

    handleConfirmPickup() {
        const reqId = this.userContext?.request?.id;
        if (!reqId) return;
        const modal = this.template.querySelector('c-fimby-pickup-confirmation-modal');
        if (modal) modal.show(reqId);
    }

    async handlePickupComplete() {
        this.adminDataLoaded = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.loadContextData();
    }

    async handleCancelRequest() {
        const reqId = this.userContext?.request?.id;
        if (!reqId) return;
        try {
            await cancelLendingRequest({ recordId: reqId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Request cancelled',
                message: 'Your borrow request has been cancelled.',
                variant: 'success'
            }));
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.loadContextData();
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Failed to cancel request.',
                variant: 'error'
            }));
        }
    }

    async handleHandoffComplete() {
        this.adminDataLoaded = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.loadContextData();
    }

    // ============================================
    // NEW MODAL HANDLERS
    // ============================================

    handleAdminConfirmPickup(event) {
        const { requestId } = event.detail;
        const modal = this.template.querySelector('c-fimby-pickup-confirmation-modal');
        if (modal) modal.show(requestId);
    }

    handleAdminApproveExtension(event) {
        const { loanId } = event.detail;
        const modal = this.template.querySelector('c-fimby-loan-extension-approval-modal');
        if (modal) modal.show(loanId);
    }

    async handleConfirmationComplete() {
        this.adminDataLoaded = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.loadContextData();
    }

    async handleExtensionComplete() {
        this.adminDataLoaded = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.loadContextData();
    }

    async handleExtensionApprovalComplete() {
        this.adminDataLoaded = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.loadContextData();
    }

    // ── Removal modal handlers (owner removes from waitlist) ──────

    handleRemoveRequest(event) {
        const { requestId, requesterName } = event.detail;
        this.removeTargetId = requestId;
        this.removeTargetName = requesterName;
        this.removeReason = '';
        this.showRemoveConfirm = true;
    }

    handleRemoveReasonChange(event) {
        this.removeReason = event.target.value;
    }

    handleRemoveCancel() {
        this.showRemoveConfirm = false;
        this.removeTargetId = null;
        this.removeTargetName = '';
        this.removeReason = '';
    }

    async handleRemoveConfirm() {
        if (!this.removeTargetId || !this.removeReason.trim()) return;
        this.isRemoving = true;
        try {
            await declineLendingRequest({
                recordId: this.removeTargetId,
                declineReason: this.removeReason.trim()
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Removed',
                message: `${this.removeTargetName || 'Request'} removed from the waitlist.`,
                variant: 'success'
            }));
            this.handleRemoveCancel();
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.loadContextData();
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Failed to remove request.',
                variant: 'error'
            }));
        } finally {
            this.isRemoving = false;
        }
    }

    get removeConfirmDisabled() {
        return this.isRemoving || !this.removeReason.trim();
    }

    get removeButtonLabel() {
        return this.isRemoving ? 'Removing...' : 'Remove';
    }

    // ============================================
    // MODERATOR ACTIONS
    // ============================================

    async _handleModeratorFlag() {
        try {
            await flagContent({ recordId: this.effectiveRecordId, recordType: 'Library_Item__c', flagValue: 'Moderator_Review' });
            this.dispatchEvent(new ShowToastEvent({ title: 'Content flagged', message: 'This item is now under review.', variant: 'success' }));
            window.location.href = '/moderator-dashboard';
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error?.body?.message || 'Could not flag content.', variant: 'error' }));
        }
    }

    async _handleModeratorHide() {
        try {
            await flagContent({ recordId: this.effectiveRecordId, recordType: 'Library_Item__c', flagValue: 'Moderator_Hidden' });
            this.dispatchEvent(new ShowToastEvent({ title: 'Content hidden', message: 'This item has been hidden from the library.', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error?.body?.message || 'Could not hide content.', variant: 'error' }));
        }
    }

    async _handleModeratorContact() {
        try {
            const ownerContactId = this._getOwnerContactId();
            if (!ownerContactId) return;
            const conversationId = await getOrCreateModeratorConversation({ targetContactId: ownerContactId });
            window.location.href = `/conversation?id=${conversationId}`;
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error?.body?.message || 'Could not start conversation.', variant: 'error' }));
        }
    }

    _getOwnerContactId() {
        if (!this.record) return null;
        return getFieldValue(this.record, 'Library_Item__c.Owner_Contact__c');
    }
}