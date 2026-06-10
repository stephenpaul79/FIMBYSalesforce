import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { decodeHtmlEntities } from 'c/fimbyTextUtils';
import { completeImageUrl, avatarImageUrl, buildSrcset, thumbnailUrl, SIZES } from 'c/fimbyImageUrl';
import getResponsesForNeedOffer from '@salesforce/apex/FimbyAskOfferController.getResponsesForNeedOffer';
import deleteNeedsOffersPost from '@salesforce/apex/FimbyAskOfferController.deleteNeedsOffersPost';
import getNeedOfferVisibility from '@salesforce/apex/FimbyAskOfferController.getNeedOfferVisibility';
import getGroupConversationIdForPost from '@salesforce/apex/FimbyAskOfferController.getGroupConversationIdForPost';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getBulkBuyDetail from '@salesforce/apex/FimbyBulkBuyController.getBulkBuyDetail';
import getFollowUpStatus from '@salesforce/apex/FimbyFollowUpController.getFollowUpStatus';
import completeBulkBuy from '@salesforce/apex/FimbyBulkBuyController.completeBulkBuy';
import cancelBulkBuy from '@salesforce/apex/FimbyBulkBuyController.cancelBulkBuy';
import quickEventResponse from '@salesforce/apex/FimbyResponseController.quickEventResponse';
import createEventGroupChat from '@salesforce/apex/FimbyGroupConversationController.createEventGroupChat';
import declineResponseApex from '@salesforce/apex/FimbyResponseThreadController.declineResponse';
import blockContactApex from '@salesforce/apex/FimbyConversationController.blockContact';
import { getModeratorContext } from 'c/fimbyModeratorContext';
import { formatShortDate, formatLocalDate } from 'c/fimbyDateUtils';
import flagContent from '@salesforce/apex/FimbyModeratorDashboardController.flagContent';
import getOrCreateModeratorConversation from '@salesforce/apex/FimbyModeratorDashboardController.getOrCreateModeratorConversation';

const FIELDS = [
    'Needs_Offers__c.Id',
    'Needs_Offers__c.Name',
    'Needs_Offers__c.Portal_Title__c',
    'Needs_Offers__c.Details__c',
    'Needs_Offers__c.Full_Details__c',
    'Needs_Offers__c.Image_1_URL__c',
    'Needs_Offers__c.Image_1_Ratio__c',
    'Needs_Offers__c.Image_2_URL__c',
    'Needs_Offers__c.Image_2_Ratio__c',
    'Needs_Offers__c.Image_3_URL__c',
    'Needs_Offers__c.Image_3_Ratio__c',
    'Needs_Offers__c.Image_4_URL__c',
    'Needs_Offers__c.Image_4_Ratio__c',
    'Needs_Offers__c.Status__c',
    'Needs_Offers__c.Category__c',
    'Needs_Offers__c.Type__c',
    'Needs_Offers__c.RecordType.Name',
    'Needs_Offers__c.Posted_By__c',
    'Needs_Offers__c.Posted_By__r.Name',
    'Needs_Offers__c.Posted_By__r.Full_Name__c',
    'Needs_Offers__c.Posted_By__r.Image_URL__c',
    'Needs_Offers__c.CreatedDate',
    'Needs_Offers__c.OwnerId',
    // Post Information
    'Needs_Offers__c.Start_Date__c',
    'Needs_Offers__c.End_Date__c',
    'Needs_Offers__c.Start_Time_Text__c',
    'Needs_Offers__c.End_Time_Text__c',
    'Needs_Offers__c.Location__c',
    'Needs_Offers__c.Event_Details__c',
    'Needs_Offers__c.of_Days_Old__c',
    // Posted By / Giver-Recipient
    'Needs_Offers__c.Contact__c',
    'Needs_Offers__c.Contact__r.Name',
    'Needs_Offers__c.Contact__r.Full_Name__c',
    'Needs_Offers__c.Contact__r.Image_URL__c',
    // Quantity
    'Needs_Offers__c.Total_Quantity__c',
    'Needs_Offers__c.Total_Available__c',
    'Needs_Offers__c.Per_Response_Limit__c',
    'Needs_Offers__c.Total_Accepted__c',
    // Post Settings
    'Needs_Offers__c.Auto_Accept_Responses__c',
    'Needs_Offers__c.Auto_Share_Contact_Info__c',
    // Event type fields
    'Needs_Offers__c.Event_Type__c',
    'Needs_Offers__c.Expected_Attendance__c',
    'Needs_Offers__c.Event_Notes__c',
    'Needs_Offers__c.Event_Link__c',
    // Bulk Buy fields
    'Needs_Offers__c.Display_Status__c',
    'Needs_Offers__c.Total_Reserved__c',
    'Needs_Offers__c.Allocation_Unit_Label__c',
    'Needs_Offers__c.Availability_Rule__c',
    'Needs_Offers__c.Expiry_DateTime__c',
    'Needs_Offers__c.Total_Estimated_Cost__c',
    'Needs_Offers__c.Estimated_Cost_Per_Share__c',
    'Needs_Offers__c.Pickup_Notified__c',
    'Needs_Offers__c.Pickup_Notified_Date__c',
    'Needs_Offers__c.Receipt_Image_URL__c',
    'Needs_Offers__c.Auto_Lock_Days__c',
    'Needs_Offers__c.Group_Conversation__c',
    'Needs_Offers__c.Recurrence_Frequency__c',
    'Needs_Offers__c.Series_Parent__c',
    'Needs_Offers__c.Series_Parent__r.Recurrence_Frequency__c'
];

const EVENT_TYPE_CONFIG = {
    Gathering: {
        ctaLabel: 'RSVP',
        ctaDisabledLabel: 'Event Full',
        ctaExpiredLabel: 'Event Ended',
        ctaIcon: 'dining-table.png',
        respondedLabel: 'Your RSVP',
        countLabel: (n) => `${n} spot${n === 1 ? '' : 's'} left`,
        identityLabel: 'Hosted by',
        badgeLabel: 'EVENT',
        usesCapacity: true,
        usesResponseThreads: true,
        usesQuickResponse: false,
        usesOnDemandEventChat: false,
        usesAttendeeList: false,
        showMessagePoster: false,
        showGuestStepper: false,
        showModeration: false,
        showEventLink: false,
    },
    Open_Event: {
        ctaLabel: "I'm Going",
        ctaRespondedLabel: "You're Going!",
        ctaWithdrawLabel: 'Not Going',
        ctaIcon: 'people.png',
        countLabel: (n) => `${n} going`,
        identityLabel: 'Hosted by',
        badgeLabel: 'EVENT',
        usesCapacity: false,
        usesResponseThreads: false,
        usesQuickResponse: true,
        usesOnDemandEventChat: true,
        usesAttendeeList: true,
        showMessagePoster: true,
        showGuestStepper: true,
        showModeration: true,
        showEventLink: false,
    },
    Community_Event: {
        ctaLabel: "I'm Interested",
        ctaRespondedLabel: "You're Interested",
        ctaWithdrawLabel: 'Not Interested',
        ctaIcon: 'cityscape.png',
        countLabel: (n) => `${n} interested`,
        identityLabel: 'Shared by',
        badgeLabel: 'COMMUNITY EVENT',
        usesCapacity: false,
        usesResponseThreads: false,
        usesQuickResponse: true,
        usesOnDemandEventChat: false,
        usesAttendeeList: true,
        showMessagePoster: true,
        showGuestStepper: false,
        showModeration: false,
        showEventLink: true,
    },
};

export default class FimbyNeedOfferDetail extends NavigationMixin(LightningElement) {
    _recordId;
    _activeRecordId = null;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const next = value && String(value).trim() ? value : null;
        if (next === this._recordId) {
            return;
        }
        this._recordId = next;
        this._syncActiveRecordId();
    }

    @track _extractedRecordId = null;
    @track isLoading = true;
    @track showLightbox = false;
    @track lightboxImages = [];
    @track lightboxStartIndex = 0;
    @track showPhotoUploader = false;
    @track showDeleteConfirm = false;
    @track isDeleting = false;
    @track seriesDeleteScope = 'THIS_EVENT';
    @track responses = [];
    @track isLoadingResponses = false;
    @track detailsExpanded = false;
    @track availabilityExpanded = false;
    @track settingsExpanded = false;

    // Quick event response state (Open Event / Community Event)
    @track quickResponseProcessing = false;
    @track quickResponseId = null;
    @track quickResponseStatus = null;
    @track quickGuestCount = 1;
    @track showGuestStepper = false;
    @track quickResponseCelebration = false;

    record;
    error;
    currentUserId = Id;
    @track actingAsContactId = null;
    @track realContactId = null;
    @track _isModeratorForNeighbourhood = false;
    @track isRemoved = false;
    @track removedMessage = '';
    @track _eventGroupConversationId = null;
    _wiredRecordResult;

    // ============================================
    // AUTO-OPEN ACTION MODAL FROM URL PARAMS
    // ============================================

    _pendingAction = null;
    _pendingActionId = null;
    _lastAutoOpenedActionKey = null;

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (!pageRef?.state?.action) return;
        const action = pageRef.state.action;
        const actionId = pageRef.state.reservationId || '';
        const actionKey = `${action}:${actionId}`;
        if (actionKey === this._lastAutoOpenedActionKey) return;
        this._pendingAction = action;
        this._pendingActionId = actionId;
        this._tryAutoOpenActionModal();
    }

    // ============================================
    // LIFECYCLE
    // ============================================

    async connectedCallback() {
        this._resolveRecordIdFromPage();
        if (window.matchMedia('(min-width: 768px)').matches) {
            this.detailsExpanded = true;
        }
        this._checkModeratorStatus();
        this._refreshGroupConversationId();
    }

    async _refreshGroupConversationId() {
        const recordId = this.effectiveRecordId;
        if (!recordId) return;
        try {
            const convId = await getGroupConversationIdForPost({ recordId });
            this._eventGroupConversationId = convId || null;
        } catch (e) {
            console.error('Error loading group conversation id:', e);
        }
    }

    async _checkModeratorStatus() {
        try {
            const ctx = await getModeratorContext();
            this._isModeratorForNeighbourhood = ctx.isModerator;
        } catch (e) {
            // Non-moderators won't see extra menu items
        }
    }

    renderedCallback() {
        this._tryAutoOpenActionModal();
    }

    get effectiveRecordId() {
        return this._recordId || this._extractedRecordId;
    }

    get wiredRecordId() {
        return this.effectiveRecordId || undefined;
    }

    get showLoadingState() {
        if (this.showRemovedState) {
            return false;
        }
        return this.isLoading || !this.effectiveRecordId;
    }

    get showRemovedState() {
        return this.isRemoved && !!this.effectiveRecordId;
    }

    _resolveRecordIdFromPage() {
        if (!this._recordId) {
            const id = this.extractRecordIdFromUrl();
            if (id) {
                this._extractedRecordId = id;
                this._recordId = id;
            }
        }
        this._syncActiveRecordId();
    }

    _syncActiveRecordId() {
        const id = this.effectiveRecordId || null;
        if (id === this._activeRecordId) {
            return;
        }
        this._activeRecordId = id;
        this._resetDetailLoadState();
    }

    _resetDetailLoadState() {
        this.isLoading = true;
        this.isRemoved = false;
        this.removedMessage = '';
        this.record = undefined;
        this.error = undefined;
        this.responses = [];
        this.bulkBuyData = null;
    }

    extractRecordIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            const queryRecordId = url.searchParams.get('recordId');
            if (queryRecordId) return queryRecordId;

            const pathParts = url.pathname.split('/').filter(part => part && part !== 's');
            const idx = pathParts.findIndex(part => part === 'asks-offers' || part === 'needs-offers');
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
    wiredActingAs({ data, error }) {
        if (data?.success) {
            this.actingAsContactId = data.actingAsContactId || data.contactId;
            this.realContactId = data.realContactId;
            this._syncQuickResponseState();
        }
    }

    @wire(getNeedOfferVisibility, { recordId: '$wiredRecordId' })
    wiredVisibility(result) {
        const { data, error, loading } = result;
        if (loading || !this.wiredRecordId) {
            return;
        }
        if (data) {
            if (data.removed) {
                this.isRemoved = true;
                this.removedMessage = data.message || 'This post is no longer available.';
                this._eventGroupConversationId = null;
                this.isLoading = false;
                this.record = undefined;
            } else {
                this.isRemoved = false;
                this.removedMessage = '';
                this._eventGroupConversationId = data.groupConversationId || null;
            }
        } else if (error) {
            console.error('Error checking content visibility:', error);
            this.isRemoved = true;
            this.removedMessage = 'This post is no longer available.';
            this.isLoading = false;
            this.record = undefined;
        }
    }

    @wire(getRecord, { recordId: '$recordIdIfVisible', fields: FIELDS })
    wiredRecord(result) {
        this._wiredRecordResult = result;
        const { error, data, loading } = result;
        if (loading || this.isRemoved || !this.wiredRecordId) {
            return;
        }
        this.isLoading = false;
        if (data) {
            this.record = data;
            this.error = undefined;
            this.bulkBuyData = null;
            this.loadResponses();
            this.loadBulkBuyDetail();
            this._refreshGroupConversationId();
        } else if (error) {
            console.error('Error loading needs/offers record:', error);
            this.error = error;
            this.record = undefined;
        }
    }

    get recordIdIfVisible() {
        if (!this.effectiveRecordId || this.isRemoved) {
            return undefined;
        }
        return this.effectiveRecordId;
    }

    get shouldRenderRecord() {
        return !!this.record && !this.isRemoved;
    }

    async loadResponses() {
        const needOfferId = this.effectiveRecordId;
        if (!needOfferId) return;
        this.isLoadingResponses = true;
        try {
            this.responses = await getResponsesForNeedOffer({ needOfferId });
            this._syncQuickResponseState();
        } catch (error) {
            console.error('Error loading responses:', error);
            this.responses = [];
        } finally {
            this.isLoadingResponses = false;
        }
    }

    _syncQuickResponseState() {
        if (!this.isOpenEvent && !this.isCommunityEvent) return;
        if (!this.actingAsContactId || !this.responses?.length) {
            this.quickResponseId = null;
            this.quickResponseStatus = null;
            this.quickGuestCount = 1;
            return;
        }
        const myResp = this.responses.find(r => r.contactId === this.actingAsContactId);
        if (myResp && (myResp.status === 'New' || myResp.status === 'Accepted')) {
            this.quickResponseId = myResp.id;
            this.quickResponseStatus = myResp.status;
            this.quickGuestCount = myResp.amountRequested || 1;
        } else {
            this.quickResponseId = null;
            this.quickResponseStatus = null;
            this.quickGuestCount = 1;
        }
    }

    get processedResponses() {
        if (!this.responses || !this.responses.length) return [];

        const mapped = this.responses.map(resp => {
            const canReply = this.isAuthor ||
                (this.actingAsContactId && resp.contactId === this.actingAsContactId) ||
                (resp.ownerId && resp.ownerId === this.currentUserId);
            const hasUnread = resp.unreadCount > 0;
            let rowClass = canReply ? 'response-row response-row-clickable' : 'response-row';
            if (hasUnread) rowClass += ' response-row-unread';

            let preview = resp.lastMessagePreview || '';
            if (preview.length > 60) preview = preview.substring(0, 60) + '...';

            let timeAgo = '';
            if (resp.lastActivityDate) {
                const d = new Date(resp.lastActivityDate);
                const now = new Date();
                const diffMs = now - d;
                const diffMins = Math.floor(diffMs / 60000);
                if (diffMins < 60) timeAgo = diffMins <= 1 ? 'Just now' : diffMins + 'm ago';
                else {
                    const diffHrs = Math.floor(diffMins / 60);
                    if (diffHrs < 24) timeAgo = diffHrs + 'h ago';
                    else {
                        const diffDays = Math.floor(diffHrs / 24);
                        timeAgo = diffDays === 1 ? '1d ago' : diffDays + 'd ago';
                    }
                }
            }

            const isThanksEligible = ['Accepted', 'Completed'].includes(resp.status);
            const posterThanked = resp.posterThanked || false;

            return {
                ...resp,
                canReply,
                rowClass,
                hasUnread,
                lastMessageDisplay: preview,
                timeAgo,
                amountDisplay: resp.amountRequested != null ? resp.amountRequested : null,
                posterThanked,
                showThanksAction: isThanksEligible && !posterThanked
            };
        });

        return mapped.sort((a, b) => {
            if (a.hasUnread && !b.hasUnread) return -1;
            if (!a.hasUnread && b.hasUnread) return 1;
            const dateA = a.lastActivityDate ? new Date(a.lastActivityDate) : new Date(0);
            const dateB = b.lastActivityDate ? new Date(b.lastActivityDate) : new Date(0);
            return dateB - dateA;
        });
    }

    get responseSummaryStats() {
        if (!this.responses || !this.responses.length) return null;
        let newCount = 0, acceptedCount = 0, declinedCount = 0, unreadCount = 0;
        for (const r of this.responses) {
            if (r.status === 'New') newCount++;
            else if (r.status === 'Accepted') acceptedCount++;
            else if (r.status === 'Declined') declinedCount++;
            if (r.unreadCount > 0) unreadCount++;
        }
        return {
            total: this.responses.length,
            newCount,
            acceptedCount,
            declinedCount,
            unreadCount,
            hasUnread: unreadCount > 0
        };
    }

    get hasResponseSummary() {
        return this.responseSummaryStats != null;
    }

    get tracksQuantityForResponses() {
        const v = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Total_Quantity__c') : null;
        return v != null && v > 0;
    }

    get responseAmountLabel() {
        if (this.isGathering) return 'Attending';
        if (this.isOpenEvent) return 'Guests';
        if (this.isCommunityEvent) return null;
        const rt = this.postType;
        if (rt && (rt.toLowerCase().includes('need') || rt.toLowerCase().includes('ask'))) return 'Offering';
        if (rt && rt.toLowerCase().includes('offer')) return 'Requesting';
        return 'Amount';
    }

    // ============================================
    // SECTION HEADER ICONS
    // ============================================

    get postInfoIconUrl() {
        return `${IMPACT_ICONS}/BulletinBoardActive.png`;
    }
    get postedByIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }
    get quantityIconUrl() {
        return `${IMPACT_ICONS}/ToolboxActive.png`;
    }
    get thanksIconUrl() {
        return `${IMPACT_ICONS}/ThankYouActive.png`;
    }
    get eventDetailsIconUrl() {
        return `${IMPACT_ICONS}/plannersm.png`;
    }
    get settingsIconUrl() {
        return `${IMPACT_ICONS}/gear.png`;
    }

    get isPostActive() {
        const active = new Set(['Posted', 'Available', 'Reply Received', 'Reply Accepted']);
        return active.has(this.status);
    }

    get isQuantityExhausted() {
        if (!this.isGathering && this.isEventType) return false;
        if (!this.tracksQuantityForResponses) return false;
        const avail = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Total_Available__c') : null;
        return avail != null && avail <= 0;
    }

    get isRespondDisabled() {
        if (this.isEventType && !this.isGathering) return !this.isPostActive;
        return !this.isPostActive || this.isQuantityExhausted;
    }

    get respondButtonLabel() {
        const cfg = this.eventTypeConfig;
        if (this.isPostActive && !this.isQuantityExhausted) {
            return cfg ? cfg.ctaLabel : 'Respond';
        }
        if (!this.isPostActive) {
            const s = this.status;
            if (s === 'Cancelled') return 'Cancelled';
            if (s === 'Expired') return cfg?.ctaExpiredLabel || (this.isEventType ? 'Event Ended' : 'Expired');
            if (cfg) return cfg.ctaDisabledLabel || cfg.ctaExpiredLabel || 'Event Ended';
            return 'Fulfilled';
        }
        return cfg?.ctaDisabledLabel || 'All Spoken For';
    }

    get respondButtonClass() {
        return this.isRespondDisabled ? 'action-btn primary disabled' : 'action-btn primary';
    }

    get respondAriaLabel() {
        const cfg = this.eventTypeConfig;
        if (!this.isRespondDisabled) {
            return cfg ? `${cfg.ctaLabel} to this event` : 'Respond to this post';
        }
        if (!this.isPostActive) {
            return `This post is ${this.respondButtonLabel.toLowerCase()} and no longer accepting responses`;
        }
        return this.isGathering
            ? 'All spots have been claimed'
            : 'All available spots have been claimed';
    }

    get respondHelperText() {
        if (!this.isGathering) return null;
        if (!this.isPostActive || !this.isQuantityExhausted) return null;
        return 'All spots have been claimed \u2014 check back in case one opens up!';
    }

    get showRespondHelperText() {
        return this.respondHelperText != null;
    }

    get respondHelperId() {
        return this.showRespondHelperText ? 'respond-helper' : undefined;
    }

    get chatIconUrl() {
        return `${IMPACT_ICONS}/chat.png`;
    }

    get showPosterMessageButton() {
        return this.isPosterPersona && (this.isOpenEvent || this.isCommunityEvent);
    }

    get attendeeMessageButtonClass() {
        return this.isCommunityEvent
            ? 'attendee-msg-btn attendee-msg-btn-muted'
            : 'attendee-msg-btn';
    }

    get respondButtonIconUrl() {
        const cfg = this.eventTypeConfig;
        if (cfg) return `${IMPACT_ICONS}/${cfg.ctaIcon}`;
        return this.isEventType ? `${IMPACT_ICONS}/rsvp.png` : `${IMPACT_ICONS}/reply.png`;
    }

    get communityEventBadgeIconUrl() {
        return `${IMPACT_ICONS}/cityscape.png`;
    }

    get flagIconUrl() {
        return `${IMPACT_ICONS}/red-flag.png`;
    }
    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }
    get photoIconUrl() { return `${IMPACT_ICONS}/photo.png`; }
    get trashIconUrl() { return `${IMPACT_ICONS}/trash.png`; }
    get noProfilePhotoUrl() { return `${IMPACT_ICONS}/NoProfilePhoto.png`; }

    resolveContactAvatarUrl(rawUrl) {
        if (!rawUrl || typeof rawUrl !== 'string') return '';
        return avatarImageUrl(rawUrl.trim());
    }

    get headerMenuItems() {
        if (this.isPosterPersona) {
            const items = [
                { key: 'edit', label: 'Edit', icon: 'edit.png', display: 'responsive' },
                { key: 'photo', label: 'Photo', icon: 'photo.png', display: 'responsive' },
                { key: 'delete', label: 'Delete', icon: 'trash.png', display: 'responsive', variant: 'danger' }
            ];
            if (this.isOpenEvent && this.eventTypeConfig?.usesOnDemandEventChat) {
                const hasChat = this._hasEventGroupChat;
                items.unshift(hasChat
                    ? { key: 'openEventChat', label: 'Event Chat', icon: 'chat.png', display: 'responsive' }
                    : { key: 'createEventChat', label: 'Create Event Chat', icon: 'chat.png', display: 'responsive' }
                );
            }
            return items;
        }
        const items = [
            { key: 'flag', label: 'Report', icon: 'warning.png', display: 'kebab' }
        ];
        if (this._isModeratorForNeighbourhood) {
            items.push(
                { key: 'mod-flag', label: 'Review as Moderator', icon: 'analysis.png', display: 'kebab' },
                { key: 'mod-hide', label: 'Hide Content', icon: 'protection.png', display: 'kebab' },
                { key: 'mod-contact', label: 'Contact Author', icon: 'chat.png', display: 'kebab' }
            );
        }
        return items;
    }

    get _resolvedEventGroupConversationId() {
        return this._eventGroupConversationId
            || getFieldValue(this.record, 'Needs_Offers__c.Group_Conversation__c')
            || null;
    }

    get _hasEventGroupChat() {
        return !!this._resolvedEventGroupConversationId;
    }

    handleHeaderMenuAction(event) {
        const actions = {
            edit: () => this.handleEdit(),
            photo: () => this.handleUploadPhoto(),
            delete: () => this.handleDeleteClick(),
            flag: () => this.handleFlag(),
            createEventChat: () => this.handleCreateEventChat(),
            openEventChat: () => this.handleOpenEventChat(),
            'mod-flag': () => this._handleModeratorFlag(),
            'mod-hide': () => this._handleModeratorHide(),
            'mod-contact': () => this._handleModeratorContact()
        };
        const handler = actions[event.detail.key];
        if (handler) handler();
    }

    // ============================================
    // EXISTING GETTERS (post card)
    // ============================================

    get detailPageTitle() {
        if (this.isEventType) return 'Event Details';
        const rt = this.postType;
        if (!rt) return 'Post Details';
        const label = rt === 'Need' ? 'Ask' : rt;
        return `${label} Details`;
    }

    get breadcrumbLabel() {
        return '';
    }

    get breadcrumbUrl() {
        return '';
    }

    get postTitle() {
        if (!this.record) return '';
        const raw = getFieldValue(this.record, 'Needs_Offers__c.Portal_Title__c')
                  || getFieldValue(this.record, 'Needs_Offers__c.Name')
                  || '';
        const stripped = raw.replace(/<[^>]*>/g, '').trim();
        return decodeHtmlEntities(stripped);
    }

    get postDetails() {
        if (!this.record) return '';
        const raw = getFieldValue(this.record, 'Needs_Offers__c.Full_Details__c') || getFieldValue(this.record, 'Needs_Offers__c.Details__c') || '';
        return decodeHtmlEntities(raw);
    }

    get hasPostDetails() {
        return !!this.postDetails || this.hasCategory;
    }

    get showCardLeft() {
        return this.hasImage;
    }

    get showStatusInRight() {
        return !this.showCardLeft;
    }

    get cardLayoutClass() {
        return this.showCardLeft ? 'card-layout card-layout-horizontal' : 'card-layout';
    }

    get imageUrl() {
        const baseUrl = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Image_1_URL__c') : '';
        return completeImageUrl(baseUrl);
    }

    get imageDisplayUrl() {
        const baseUrl = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Image_1_URL__c') : '';
        return thumbnailUrl(baseUrl);
    }

    get imageSrcset() {
        const baseUrl = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Image_1_URL__c') : '';
        const ratio = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Image_1_Ratio__c') : '';
        return buildSrcset(baseUrl, ratio, { includeOriginal: true });
    }

    get detailImageSizes() {
        return SIZES.feedColumn;
    }

    get hasImage() {
        const baseUrl = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Image_1_URL__c') : '';
        return !!baseUrl && baseUrl.trim() !== '';
    }

    get allImages() {
        if (!this.record) return [];
        const imgs = [];
        for (let i = 1; i <= 4; i++) {
            const url = getFieldValue(this.record, `Needs_Offers__c.Image_${i}_URL__c`);
            const ratio = getFieldValue(this.record, `Needs_Offers__c.Image_${i}_Ratio__c`);
            if (url && url.trim()) {
                imgs.push({ url: completeImageUrl(url), ratio: ratio || '' });
            }
        }
        return imgs;
    }

    get hasMultipleImages() {
        return this.allImages.length > 1;
    }

    get imageAspectRatio() {
        const ratioString = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Image_1_Ratio__c') : '';
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

    get quantityLabel() {
        return this.isGathering ? 'Spots Available' : 'Total Quantity';
    }

    get perResponseLimitLabel() {
        return this.isGathering ? 'Max RSVPs per Person' : 'Per Response Limit';
    }

    get autoAcceptLabelText() {
        return this.isGathering ? 'Auto-Accept RSVPs' : 'Auto-Accept Responses';
    }

    get organizationFieldLabel() {
        return 'Community Group';
    }

    get posterName() {
        if (!this.record) return '';
        const contactName = getFieldValue(this.record, 'Needs_Offers__c.Contact__r.Full_Name__c')
            || getFieldValue(this.record, 'Needs_Offers__c.Contact__r.Name');
        if (contactName) return contactName;
        return getFieldValue(this.record, 'Needs_Offers__c.Posted_By__r.Full_Name__c') ||
               getFieldValue(this.record, 'Needs_Offers__c.Posted_By__r.Name') || '';
    }

    get posterAvatar() {
        if (!this.record) return '';
        const contactImg = getFieldValue(this.record, 'Needs_Offers__c.Contact__r.Image_URL__c');
        const baseUrl = contactImg || getFieldValue(this.record, 'Needs_Offers__c.Posted_By__r.Image_URL__c') || '';
        return avatarImageUrl(baseUrl);
    }

    get postedByName() {
        if (!this.record) return '';
        return getFieldValue(this.record, 'Needs_Offers__c.Posted_By__r.Full_Name__c') ||
               getFieldValue(this.record, 'Needs_Offers__c.Posted_By__r.Name') || '';
    }

    get showPostedBy() {
        if (!this.record) return false;
        const contactId = getFieldValue(this.record, 'Needs_Offers__c.Contact__c');
        const postedById = getFieldValue(this.record, 'Needs_Offers__c.Posted_By__c');
        return contactId && postedById && contactId !== postedById;
    }

    get postType() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.RecordType.Name') : '';
    }

    get postTypeDisplay() {
        const cfg = this.eventTypeConfig;
        if (cfg) return cfg.badgeLabel || 'Event';
        const rt = this.postType;
        return rt === 'Need' ? 'Ask' : rt;
    }

    get formattedDate() {
        if (!this.record) return '';
        const date = getFieldValue(this.record, 'Needs_Offers__c.CreatedDate');
        if (!date) return '';
        const now = new Date();
        const posted = new Date(date);
        const diffMs = now - posted;
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
        if (diffDays === 0) {
            const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
            if (diffHours === 0) {
                const diffMins = Math.floor(diffMs / (1000 * 60));
                return diffMins <= 1 ? 'Posted just now' : `Posted ${diffMins} minutes ago`;
            }
            return diffHours === 1 ? 'Posted 1 hour ago' : `Posted ${diffHours} hours ago`;
        } else if (diffDays === 1) return 'Posted yesterday';
        else if (diffDays < 7) return `Posted ${diffDays} days ago`;
        return 'Posted ' + posted.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    }

    get category() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Category__c') : '';
    }
    get hasCategory() { return !!this.category; }

    // ============================================
    // POST INFORMATION SECTION
    // ============================================

    get status() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Status__c') : '';
    }
    get typeValue() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Type__c') : '';
    }
    get startDate() {
        const d = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Start_Date__c') : '';
        return formatShortDate(d);
    }
    get endDate() {
        const d = this.record ? getFieldValue(this.record, 'Needs_Offers__c.End_Date__c') : '';
        return formatShortDate(d);
    }
    get daysOld() {
        const v = this.record ? getFieldValue(this.record, 'Needs_Offers__c.of_Days_Old__c') : null;
        return v != null ? Math.round(v) : '';
    }
    get formattedExpiration() {
        // End_Date__c serves as expiration date for non-event posts
        const d = this.record ? getFieldValue(this.record, 'Needs_Offers__c.End_Date__c') : '';
        return formatLocalDate(d);
    }
    get hasExpiration() {
        const d = this.record ? getFieldValue(this.record, 'Needs_Offers__c.End_Date__c') : '';
        return !!d;
    }

    // Event-specific fields
    get isEventType() {
        return this.typeValue === 'Event';
    }
    get eventTypeValue() {
        if (!this.record) return null;
        return getFieldValue(this.record, 'Needs_Offers__c.Event_Type__c');
    }
    get eventTypeConfig() {
        if (!this.isEventType) return null;
        return EVENT_TYPE_CONFIG[this.eventTypeValue] || EVENT_TYPE_CONFIG.Gathering;
    }
    get isGathering() {
        return this.isEventType && (!this.eventTypeValue || this.eventTypeValue === 'Gathering');
    }
    get isOpenEvent() {
        return this.isEventType && this.eventTypeValue === 'Open_Event';
    }
    get isCommunityEvent() {
        return this.isEventType && this.eventTypeValue === 'Community_Event';
    }
    get expectedAttendance() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Expected_Attendance__c') : null;
    }
    get eventNotes() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Event_Notes__c') : '';
    }
    get eventLinkUrl() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Event_Link__c') : '';
    }
    get hasEventLink() {
        return !!this.eventLinkUrl;
    }
    get eventNotesDetailLabel() {
        if (this.isOpenEvent) return 'What to Bring';
        if (this.isCommunityEvent) return 'Additional Info';
        return 'Notes';
    }
    get startTime() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Start_Time_Text__c') : '';
    }
    get endTime() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.End_Time_Text__c') : '';
    }
    get location() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Location__c') : '';
    }
    get eventDetails() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Event_Details__c') : '';
    }

    // ============================================
    // BULK BUY SUPPORT
    // ============================================

    @track bulkBuyData = null;
    @track bulkBuyFollowUpStatus = null;

    get isBulkBuyType() {
        return this.postType === 'Bulk Buy';
    }

    get bulkBuyPost() {
        return this.bulkBuyData?.post;
    }

    get bulkBuyIsOrganiser() {
        return this.bulkBuyData?.isOrganiser || false;
    }

    get bulkBuyReservations() {
        return this.bulkBuyData?.reservations || [];
    }

    get bulkBuyDisplayStatus() {
        return this.bulkBuyData?.post?.Display_Status__c || this.status || 'Available';
    }

    get userHasBulkBuyReservation() {
        if (!this.actingAsContactId || !this.bulkBuyReservations.length) return false;
        return this.bulkBuyReservations.some(r => r.contactId === this.actingAsContactId);
    }

    get userBulkBuyReservationAmount() {
        if (!this.actingAsContactId || !this.bulkBuyReservations.length) return 0;
        const r = this.bulkBuyReservations.find(r => r.contactId === this.actingAsContactId);
        return r?.amount || 0;
    }

    get bulkBuyStatusBadgeText() {
        if (this.userHasBulkBuyReservation) {
            const amt = this.userBulkBuyReservationAmount;
            return amt === 1 ? '1 Share Reserved' : `${amt} Shares Reserved`;
        }
        return this.bulkBuyDisplayStatus;
    }

    get bulkBuyStatusBadgeClass() {
        if (this.userHasBulkBuyReservation) {
            return 'status-badge status-badge-reserved';
        }
        return 'status-badge';
    }

    async loadBulkBuyDetail() {
        if (!this.isBulkBuyType || !this.recordId) return;
        try {
            this.bulkBuyData = await getBulkBuyDetail({ recordId: this.recordId });
            const fuResult = await getFollowUpStatus({ bulkBuyId: this.recordId });
            this.bulkBuyFollowUpStatus = fuResult?.statusByReservation || {};
        } catch (error) {
            console.error('Error loading bulk buy detail:', error);
        }
    }

    handleBulkBuyReserve() {
        const modal = this.template.querySelector('c-fimby-quick-response-modal');
        if (modal) modal.show(this.recordId, 'bulkBuy');
    }

    handleNotifyPickup() {
        this.template.querySelector('c-fimby-bulk-buy-pickup-modal')?.show();
    }

    handlePickupNotified() {
        this.loadBulkBuyDetail();
    }

    async handleBulkBuyComplete() {
        try {
            await completeBulkBuy({ postId: this.recordId });
            this.loadBulkBuyDetail();
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error', message: error.body?.message || 'Could not complete.', variant: 'error'
            }));
        }
    }

    async handleBulkBuyCancel() {
        try {
            await cancelBulkBuy({ postId: this.recordId });
            this.loadBulkBuyDetail();
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error', message: error.body?.message || 'Could not cancel.', variant: 'error'
            }));
        }
    }

    handleCheckIn(event) {
        const reservationId = event.detail?.reservationId;
        const reserverName = event.detail?.reserverName || '';
        if (reservationId) {
            this._openCheckInModal(reservationId, reserverName);
        }
    }

    _openCheckInModal(reservationId, reserverName) {
        const modal = this.template.querySelector('c-fimby-not-responding-modal');
        if (modal) {
            modal.show(reservationId, reserverName);
        }
    }

    _tryAutoOpenActionModal() {
        if (!this._pendingAction) return;
        const actionKey = `${this._pendingAction}:${this._pendingActionId}`;
        if (actionKey === this._lastAutoOpenedActionKey) return;

        const action = this._pendingAction;
        const id = this._pendingActionId;

        if (!this._isActionDataReady(action)) return;

        if (!this._isActionStillValid(action, id)) {
            this._consumePendingAction(actionKey);
            return;
        }

        let opened = false;

        switch (action) {
            case 'checkIn':
                if (id) {
                    const modal = this.template.querySelector('c-fimby-not-responding-modal');
                    if (modal) { modal.show(id, ''); opened = true; }
                }
                break;
            case 'reserve': {
                const modal = this.template.querySelector('c-fimby-quick-response-modal');
                if (modal) { modal.show(this.recordId, 'bulkBuy'); opened = true; }
                break;
            }
            case 'notifyPickup': {
                const modal = this.template.querySelector('c-fimby-bulk-buy-pickup-modal');
                if (modal) { modal.show(); opened = true; }
                break;
            }
            default:
                break;
        }

        if (opened) {
            this._consumePendingAction(actionKey);
        }
    }

    _isActionDataReady(action) {
        switch (action) {
            case 'checkIn':
                return this.bulkBuyData !== null;
            case 'reserve':
            case 'notifyPickup':
                return !!this.record;
            default:
                return true;
        }
    }

    _isActionStillValid(action, id) {
        switch (action) {
            case 'checkIn':
                return !this.bulkBuyFollowUpStatus?.[id];
            case 'reserve':
                return this.isBulkBuyType && !this.userHasBulkBuyReservation;
            case 'notifyPickup':
                return !getFieldValue(this.record, 'Needs_Offers__c.Pickup_Notified__c');
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
            for (const key of ['action', 'reservationId']) {
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

    handleCheckInSubmitted(event) {
        const conversationId = event.detail?.conversationId;
        this.loadBulkBuyDetail();
        if (conversationId) {
            window.location.href = `/conversation?id=${conversationId}`;
        }
    }

    handleCancelReservation() {
        this.loadBulkBuyDetail();
    }

    // ============================================
    // POSTED BY / CONTACT IDENTITY
    // ============================================

    get contactDisplayName() {
        if (!this.record) return '';
        return getFieldValue(this.record, 'Needs_Offers__c.Contact__r.Full_Name__c')
            || getFieldValue(this.record, 'Needs_Offers__c.Contact__r.Name')
            || '';
    }
    get contactLabel() {
        const cfg = this.eventTypeConfig;
        if (cfg) return cfg.identityLabel;
        const rt = this.postType;
        if (rt && rt.toLowerCase().includes('offer')) return 'Offered by';
        return 'Asked by';
    }

    // ============================================
    // QUANTITY SECTION
    // ============================================

    get totalQuantity() {
        const v = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Total_Quantity__c') : null;
        return v != null ? v : '';
    }
    get totalAvailable() {
        const v = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Total_Available__c') : null;
        return v != null ? v : '';
    }
    get perResponseLimit() {
        const v = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Per_Response_Limit__c') : null;
        return v != null ? v : '';
    }
    get totalAccepted() {
        const v = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Total_Accepted__c') : null;
        return v != null ? v : '';
    }
    get totalReserved() {
        const v = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Total_Reserved__c') : null;
        return v != null ? v : '';
    }
    get allocationUnitLabel() {
        const raw = this.record ? getFieldValue(this.record, 'Needs_Offers__c.Allocation_Unit_Label__c') : null;
        const label = raw && String(raw).trim() ? String(raw).trim() : 'share';
        return label.toLowerCase();
    }

    // ============================================
    // POST SETTINGS SECTION
    // ============================================

    get autoAcceptResponses() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Auto_Accept_Responses__c') : false;
    }
    get autoShareContactInfo() {
        return this.record ? getFieldValue(this.record, 'Needs_Offers__c.Auto_Share_Contact_Info__c') : false;
    }
    get autoAcceptLabel() { return this.autoAcceptResponses ? 'Yes' : 'No'; }
    get autoShareLabel() { return this.autoShareContactInfo ? 'Yes' : 'No'; }

    // ============================================
    // RESPONSES SECTION
    // ============================================

    get responseCount() { return this.responses ? this.responses.length : 0; }
    get hasResponses() { return this.responseCount > 0; }

    // ============================================
    // AUTHOR CHECK
    // ============================================

    get isAuthor() {
        if (!this.record) return false;
        const ownerId = getFieldValue(this.record, 'Needs_Offers__c.OwnerId');
        const postedById = getFieldValue(this.record, 'Needs_Offers__c.Posted_By__c');
        const contactId = getFieldValue(this.record, 'Needs_Offers__c.Contact__c');
        if (this.currentUserId && ownerId && this.currentUserId === ownerId) return true;
        if (this.realContactId && postedById && this.realContactId === postedById) return true;
        if (this.actingAsContactId && contactId && this.actingAsContactId === contactId) return true;
        return false;
    }
    get isNotAuthor() { return !this.isAuthor; }
    get deleteButtonLabel() { return this.isDeleting ? 'Deleting...' : 'Delete'; }

    get isSeriesMember() {
        if (!this.record || !this.isEventType) return false;
        const parentId = getFieldValue(this.record, 'Needs_Offers__c.Series_Parent__c');
        const freq = getFieldValue(this.record, 'Needs_Offers__c.Recurrence_Frequency__c')
            || getFieldValue(this.record, 'Needs_Offers__c.Series_Parent__r.Recurrence_Frequency__c');
        return !!parentId || !!freq;
    }

    get showSeriesDeleteChooser() {
        return this.isSeriesMember;
    }

    get deleteModalTitle() {
        return this.isSeriesMember ? 'Delete recurring event?' : 'Delete Post?';
    }

    get deleteModalMessage() {
        if (!this.isSeriesMember) {
            return 'This action cannot be undone. All responses will also be affected.';
        }
        if (this.seriesDeleteScope === 'THIS_AND_FOLLOWING') {
            return 'This removes the current event and stops future dates. Past events stay as history.';
        }
        if (this.seriesDeleteScope === 'ALL_EVENTS') {
            return 'This removes every event in the series, including past dates. This cannot be undone.';
        }
        return 'This removes only the current event. The series will continue with the next scheduled date.';
    }

    get seriesDeleteOptions() {
        return [
            { label: 'This event only', value: 'THIS_EVENT', selected: this.seriesDeleteScope === 'THIS_EVENT', pillClass: this.seriesDeleteScope === 'THIS_EVENT' ? 'pill-btn selected' : 'pill-btn' },
            { label: 'This and following', value: 'THIS_AND_FOLLOWING', selected: this.seriesDeleteScope === 'THIS_AND_FOLLOWING', pillClass: this.seriesDeleteScope === 'THIS_AND_FOLLOWING' ? 'pill-btn selected' : 'pill-btn' },
            { label: 'All events', value: 'ALL_EVENTS', selected: this.seriesDeleteScope === 'ALL_EVENTS', pillClass: this.seriesDeleteScope === 'ALL_EVENTS' ? 'pill-btn selected' : 'pill-btn' }
        ];
    }

    // eslint-disable-next-line no-unused-vars
    stopPropagation(event) { event.stopPropagation(); }

    // ============================================
    // PERSONA MODEL
    // ============================================

    get hasUserResponse() {
        if (!this.responses?.length) return false;
        if (this.actingAsContactId) {
            return this.responses.some(r => r.contactId === this.actingAsContactId);
        }
        if (!this.currentUserId) return false;
        return this.responses.some(r => r.ownerId === this.currentUserId);
    }

    get currentUserResponse() {
        if (!this.processedResponses?.length) return null;
        if (this.actingAsContactId) {
            return this.processedResponses.find(r => r.contactId === this.actingAsContactId) || null;
        }
        if (!this.currentUserId) return null;
        return this.processedResponses.find(r => r.ownerId === this.currentUserId) || null;
    }

    get isPosterPersona() { return this.isAuthor; }
    get isResponderPersona() { return !this.isAuthor && !this.hasUserResponse; }
    get isRespondedPersona() { return !this.isAuthor && this.hasUserResponse; }

    // ============================================
    // PERSONA: SECTION VISIBILITY
    // ============================================

    get showPosterResponseInbox() {
        if (this.isOpenEvent || this.isCommunityEvent) return false;
        return this.isPosterPersona && this.hasResponses;
    }
    get showPosterEmptyState() {
        if (this.isOpenEvent || this.isCommunityEvent) return false;
        return this.isPosterPersona && !this.hasResponses && !this.isLoadingResponses;
    }
    get showPotentialResponderActionContext() {
        if (this.isOpenEvent || this.isCommunityEvent) return false;
        return this.isResponderPersona;
    }
    get showRespondedStatusCard() {
        if (this.isOpenEvent || this.isCommunityEvent) return false;
        return this.isRespondedPersona && !!this.currentUserResponse;
    }
    get showManagePostSection() { return this.isPosterPersona; }
    get showSecondaryDetails() { return true; }

    // Open Event / Community Event section visibility
    get usesQuickResponse() {
        const cfg = this.eventTypeConfig;
        return cfg && cfg.usesQuickResponse;
    }
    get showQuickResponseSection() {
        return this.usesQuickResponse && !this.isPosterPersona;
    }
    get hasQuickResponse() {
        return !!this.quickResponseId && (this.quickResponseStatus === 'New' || this.quickResponseStatus === 'Accepted');
    }
    get showQuickResponseCTA() {
        return this.showQuickResponseSection && !this.hasQuickResponse;
    }
    get showQuickResponseStatus() {
        return this.showQuickResponseSection && this.hasQuickResponse;
    }
    get showAttendeeList() {
        const cfg = this.eventTypeConfig;
        return cfg && cfg.usesAttendeeList && this.hasResponses;
    }
    get showMessagePosterButton() {
        const cfg = this.eventTypeConfig;
        return cfg && cfg.showMessagePoster && this.hasQuickResponse && !this.isPosterPersona;
    }
    get showEventLinkButton() {
        const cfg = this.eventTypeConfig;
        return cfg && cfg.showEventLink && this.hasEventLink && !this.isCommunityEvent;
    }
    get showHeaderEventLink() {
        return this.isCommunityEvent && this.hasEventLink;
    }
    get showOpenEventContext() {
        return this.isOpenEvent && (!!this.expectedAttendance || !!this.eventNotes);
    }
    get showOpenEventPosterEmptyState() {
        return (this.isOpenEvent || this.isCommunityEvent) && this.isPosterPersona && !this.hasResponses && !this.isLoadingResponses;
    }
    get showOpenEventPosterAttendees() {
        return (this.isOpenEvent || this.isCommunityEvent) && this.isPosterPersona && this.hasResponses;
    }

    get showEventChatCard() {
        return this.isOpenEvent && this._hasEventGroupChat && (this.isPosterPersona || this.hasQuickResponse);
    }

    get eventChatMemberCount() {
        return this.attendeeList.length + 1;
    }

    // Quick response getters
    get quickResponseCtaLabel() {
        const cfg = this.eventTypeConfig;
        if (!this.isPostActive) return cfg?.ctaExpiredLabel || 'Event Ended';
        return cfg?.ctaLabel || 'Respond';
    }
    get quickResponseRespondedLabel() {
        const cfg = this.eventTypeConfig;
        return cfg?.ctaRespondedLabel || "You're Going!";
    }
    get quickResponseWithdrawLabel() {
        const cfg = this.eventTypeConfig;
        return cfg?.ctaWithdrawLabel || 'Not Going';
    }
    get quickResponseCountLabel() {
        const cfg = this.eventTypeConfig;
        if (!cfg) return '';
        const count = this.eventResponseCount;
        return cfg.countLabel(count);
    }
    get eventResponseCount() {
        if (!this.responses?.length) return 0;
        return this.responses.filter(r => r.status === 'New' || r.status === 'Accepted').length;
    }
    get quickResponseCtaDisabled() {
        return !this.isPostActive || this.quickResponseProcessing;
    }
    get quickResponseCtaClass() {
        return this.quickResponseCtaDisabled ? 'action-btn primary disabled' : 'action-btn primary';
    }
    get showGuestStepperOption() {
        const cfg = this.eventTypeConfig;
        return cfg && cfg.showGuestStepper;
    }

    // Attendee list for poster
    get attendeeList() {
        if (!this.responses?.length) return [];
        return this.responses
            .filter(r => r.status === 'New' || r.status === 'Accepted')
            .map(r => {
                const resolved = this.resolveContactAvatarUrl(r.avatarUrl);
                return {
                    id: r.id,
                    contactId: r.contactId || null,
                    name: r.responderName || 'Neighbour',
                    avatarUrl: resolved || this.noProfilePhotoUrl,
                    guestCount: r.amountRequested || 1,
                    timeAgo: r.timeAgo || '',
                    removeLabel: `Remove ${r.responderName || 'attendee'}`,
                    blockLabel: `Block ${r.responderName || 'attendee'}`
                };
            });
    }

    // ============================================
    // PERSONA: POSTER EMPTY STATE
    // ============================================

    get posterEmptyStateMessage() {
        return 'No responses yet \u2014 hang tight, your neighbours will see this!';
    }

    get posterPostHealthText() {
        const parts = [];
        if (this.isPostActive) parts.push('Post is active');
        else parts.push(`Post is ${this.status?.toLowerCase() || 'inactive'}`);
        if (this.hasExpiration) parts.push(`Expires ${this.formattedExpiration}`);
        return parts.join(' \u00B7 ');
    }

    // ============================================
    // PERSONA: COMPACT META (max 2 facts)
    // ============================================

    get compactForContextText() {
        return null;
    }

    get compactAvailabilityText() {
        const cfg = this.eventTypeConfig;
        if (cfg && !cfg.usesCapacity) return null;
        if (!this.tracksQuantityForResponses) return null;
        const total = this.totalQuantity;
        const avail = this.totalAvailable;
        if (total === '' || avail === '') return null;
        if (this.isGathering) {
            return cfg.countLabel(avail);
        }
        return `${avail} of ${total} available`;
    }

    get compactEventLogisticsText() {
        if (!this.isEventType) return null;
        const parts = [];
        if (this.startDate) {
            let datePart = this.startDate;
            if (this.startTime) datePart += ', ' + this.startTime;
            parts.push(datePart);
        }
        if (this.location) parts.push(this.location);
        return parts.length > 0 ? parts.join(' \u00B7 ') : null;
    }

    get compactMetaSecondaryItems() {
        const items = [];
        if (this.isEventType) {
            const logistics = this.compactEventLogisticsText;
            if (logistics) items.push(logistics);
            if (items.length < 2) {
                const ctx = this.compactForContextText;
                if (ctx) items.push(ctx);
            }
        } else {
            const ctx = this.compactForContextText;
            if (ctx) items.push(ctx);
        }
        return items.slice(0, 2);
    }

    get showCompactMetaSecondary() { return this.compactMetaSecondaryItems.length > 0; }

    // ============================================
    // PERSONA: HEADER IDENTITY
    // ============================================

    get headerIdentityLabel() {
        const cfg = this.eventTypeConfig;
        if (cfg) return cfg.identityLabel;
        const rt = this.postType;
        if (rt && rt.toLowerCase().includes('offer')) return 'From';
        return 'For';
    }

    get headerIdentityName() {
        return this.posterName;
    }

    // ============================================
    // PERSONA: CTA LABELS
    // ============================================

    get primaryActionLabel() {
        if (this.isPosterPersona) return 'Edit Post';
        if (this.isRespondedPersona) return 'Open Conversation';
        return this.respondButtonLabel;
    }

    // ============================================
    // PERSONA: RESPONDED USER CARD DATA
    // ============================================

    get yourResponseStatus() { return this.currentUserResponse?.status || ''; }
    get yourResponseTimeAgo() { return this.currentUserResponse?.timeAgo || ''; }
    get yourResponseUnread() { return this.currentUserResponse?.unreadCount || 0; }
    get yourResponseHasUnread() { return this.yourResponseUnread > 0; }

    get yourResponseAmountDisplay() {
        const resp = this.currentUserResponse;
        if (!resp || resp.amountDisplay == null) return null;
        if (this.isEventType) return `Attending: ${resp.amountDisplay}`;
        const rt = this.postType;
        if (rt === 'Need' || rt === 'Ask') return `Offering: ${resp.amountDisplay}`;
        if (rt === 'Offer') return `Requesting: ${resp.amountDisplay}`;
        return `Amount: ${resp.amountDisplay}`;
    }

    get showYourResponseAmount() { return this.yourResponseAmountDisplay != null; }

    get showResponderThanksAction() {
        const r = this.currentUserResponse;
        if (!r) return false;
        return ['Accepted', 'Completed'].includes(r.status) && !r.responderThanked;
    }

    get yourResponseResponderThanked() {
        return this.currentUserResponse?.responderThanked || false;
    }

    // ============================================
    // PERSONA: POSTER ATTENTION STRIP
    // ============================================
    // Capacity rollups when quantity is tracked; workflow-only when not.
    // Unread / per-row status stay on each response row.

    get attentionItems() {
        const stats = this.responseSummaryStats;
        if (!stats) return [];

        if (this.tracksQuantityForResponses) {
            return this._buildCapacityAttentionItems();
        }

        if (stats.newCount > 0) {
            const n = stats.newCount;
            return [{
                key: 'awaiting-review',
                label: n === 1 ? '1 awaiting review' : `${n} awaiting review`,
                pillClass: 'pill-new'
            }];
        }
        return [];
    }

    _buildCapacityAttentionItems() {
        const items = [];
        const fulfilled = this._inboxStripFulfilledLabel();
        const remaining = this._inboxStripRemainingLabel();
        if (fulfilled != null) {
            items.push({ key: 'fulfilled', label: fulfilled, pillClass: 'pill-accepted' });
        }
        if (remaining != null) {
            items.push({ key: 'remaining', label: remaining, pillClass: 'pill-available' });
        }
        return items;
    }

    _inboxStripFulfilledLabel() {
        if (this.isBulkBuyType) {
            if (this.totalReserved === '') return null;
            const n = Number(this.totalReserved);
            return n === 1 ? '1 reserved' : `${n} reserved`;
        }
        if (this.totalAccepted === '') return null;
        const n = Number(this.totalAccepted);
        if (this.isGathering) {
            return n === 1 ? '1 attending' : `${n} attending`;
        }
        return n === 1 ? '1 accepted' : `${n} accepted`;
    }

    _inboxStripRemainingLabel() {
        if (this.totalAvailable === '') return null;
        const n = Number(this.totalAvailable);
        if (this.isGathering) {
            const cfg = this.eventTypeConfig;
            return cfg ? cfg.countLabel(n) : (n === 1 ? '1 spot left' : `${n} spots left`);
        }
        if (this.isBulkBuyType) {
            const unit = this.allocationUnitLabel;
            const unitWord = n === 1 ? unit : (unit.endsWith('s') ? unit : `${unit}s`);
            return n === 1 ? `1 ${unitWord} left` : `${n} ${unitWord} left`;
        }
        return n === 1 ? '1 available' : `${n} available`;
    }

    get showAttentionStrip() { return this.isPosterPersona && this.attentionItems.length > 0; }

    // ============================================
    // PERSONA: COLLAPSIBLE SECTIONS
    // ============================================

    get detailsToggleIcon() { return this.detailsExpanded ? 'utility:chevronup' : 'utility:chevrondown'; }
    get availabilityToggleIcon() { return this.availabilityExpanded ? 'utility:chevronup' : 'utility:chevrondown'; }
    get settingsToggleIcon() { return this.settingsExpanded ? 'utility:chevronup' : 'utility:chevrondown'; }

    toggleDetails() { this.detailsExpanded = !this.detailsExpanded; }
    toggleAvailability() { this.availabilityExpanded = !this.availabilityExpanded; }
    toggleSettings() { this.settingsExpanded = !this.settingsExpanded; }

    get showAvailabilitySection() {
        if (this.isEventType && !this.isGathering) return false;
        return this.tracksQuantityForResponses;
    }

    // ============================================
    // PERSONA: DESKTOP LAYOUT
    // ============================================
    // Single-column layout at all viewports. The former two-column split was removed
    // because it cramped both the post card and response inbox on desktop.

    // ============================================
    // PERSONA: RESPONDED HANDLER
    // ============================================

    handleOpenMyResponseThread() {
        if (!this.currentUserResponse?.id) return;
        window.location.href = '/response-reply?recordId=' + this.currentUserResponse.id;
    }

    handleSayThanks(event) {
        const responseId = event.currentTarget.dataset.responseId;
        const recipientId = event.currentTarget.dataset.recipientId;
        const recipientName = event.currentTarget.dataset.recipientName;
        const modal = this.template.querySelector('c-fimby-thanks-giving');
        if (modal) {
            modal.show(recipientId, recipientName, responseId);
        }
    }

    handleSayThanksToPoster() {
        if (!this.record || !this.currentUserResponse) return;
        const posterId = getFieldValue(this.record, 'Needs_Offers__c.Contact__c');
        const posterDisplayName = this.posterName;
        const responseId = this.currentUserResponse.id;
        const modal = this.template.querySelector('c-fimby-thanks-giving');
        if (modal && posterId) {
            modal.show(posterId, posterDisplayName, responseId);
        }
    }

    handleThanksSent(event) {
        const recipientId = event?.detail?.recipientId;
        if (recipientId && this.responses?.length) {
            const isResponder = this.responses.some(r => r.contactId === recipientId);
            if (isResponder) {
                this.responses = this.responses.map(r =>
                    r.contactId === recipientId ? { ...r, posterThanked: true } : r
                );
            } else {
                this.responses = this.responses.map(r => ({ ...r, responderThanked: true }));
            }
        }
        this.loadResponses();
    }

    // ============================================
    // NAVIGATION
    // ============================================

    handleBack() {
        if (window.history.length > 1) {
            window.history.back();
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'ask-offer-list' }
            });
        }
    }

    handleTabChange(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: event.detail.tab }
        });
    }

    // ============================================
    // ACTION HANDLERS
    // ============================================

    get editPostKind() {
        if (this.isBulkBuyType) return 'bulkBuy';
        if (this.isEventType) return 'event';
        if (this.postType === 'Offer') return 'offer';
        return 'ask';
    }

    handleEdit() {
        const modal = this.template.querySelector('c-fimby-post-edit-modal');
        if (modal) {
            modal.show(this.recordId, this.editPostKind);
        }
    }

    async handleEditSave() {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Post updated successfully', variant: 'success' }));
        if (this._wiredRecordResult) {
            await refreshApex(this._wiredRecordResult);
        }
    }
    handleEditCancel() {}

    handleRespond() {
        if (this.isRespondDisabled) return;
        const type = this.isGathering ? 'gathering' : 'askOffer';
        const modal = this.template.querySelector('c-fimby-quick-response-modal');
        if (modal) modal.show(this.recordId, type);
    }

    handleDetailResponseSaved() {
        if (this.isBulkBuyType) {
            this.loadBulkBuyDetail();
        }
        this.loadResponses();
    }

    // ============================================
    // QUICK EVENT RESPONSE HANDLERS
    // ============================================

    async handleQuickRespond() {
        if (this.quickResponseProcessing || !this.isPostActive) return;
        this.quickResponseProcessing = true;
        try {
            const result = await quickEventResponse({
                eventId: this.recordId,
                action: 'respond',
                guestCount: 1
            });
            if (result.success) {
                this.quickResponseId = result.responseId;
                this.quickResponseStatus = result.status;
                this.quickGuestCount = result.guestCount || 1;
                this.quickResponseCelebration = true;
                setTimeout(() => { this.quickResponseCelebration = false; }, 2000);
                await this.loadResponses();
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Something went wrong',
                variant: 'error'
            }));
        } finally {
            this.quickResponseProcessing = false;
        }
    }

    async handleQuickWithdraw() {
        if (this.quickResponseProcessing) return;
        this.quickResponseProcessing = true;
        try {
            const result = await quickEventResponse({
                eventId: this.recordId,
                action: 'withdraw',
                guestCount: null
            });
            if (result.success) {
                this.quickResponseId = null;
                this.quickResponseStatus = null;
                this.quickGuestCount = 1;
                this.showGuestStepper = false;
                await this.loadResponses();
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Something went wrong',
                variant: 'error'
            }));
        } finally {
            this.quickResponseProcessing = false;
        }
    }

    toggleGuestStepper() {
        this.showGuestStepper = !this.showGuestStepper;
    }

    async handleGuestIncrement() {
        const newCount = this.quickGuestCount + 1;
        this.quickGuestCount = newCount;
        await this._updateGuestCount(newCount);
    }

    async handleGuestDecrement() {
        if (this.quickGuestCount <= 1) return;
        const newCount = this.quickGuestCount - 1;
        this.quickGuestCount = newCount;
        await this._updateGuestCount(newCount);
    }

    async _updateGuestCount(count) {
        try {
            await quickEventResponse({
                eventId: this.recordId,
                action: 'updateGuests',
                guestCount: count
            });
        } catch (error) {
            console.error('Error updating guest count:', error);
        }
    }

    handleMessagePoster() {
        if (this.quickResponseId) {
            window.location.href = '/response-reply?recordId=' + this.quickResponseId + '&mode=message';
        }
    }

    handleMessageAttendee(event) {
        const responseId = event.currentTarget.dataset.responseId;
        if (responseId) {
            window.location.href = '/response-reply?recordId=' + responseId + '&mode=message';
        }
    }

    async handleCreateEventChat() {
        try {
            const convId = await createEventGroupChat({ eventId: this.recordId });
            if (convId) {
                this._eventGroupConversationId = convId;
                window.location.href = '/conversation?id=' + convId;
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Unable to create event chat',
                message: error.body?.message || 'Something went wrong',
                variant: 'error'
            }));
        }
    }

    handleOpenEventChat() {
        const convId = this._resolvedEventGroupConversationId;
        if (convId) {
            window.location.href = '/conversation?id=' + convId;
        }
    }

    get showAttendeeModeration() {
        const cfg = this.eventTypeConfig;
        return this.isPosterPersona && cfg?.showModeration === true;
    }

    async handleRemoveAttendee(event) {
        event.stopPropagation();
        const responseId = event.currentTarget.dataset.responseId;
        if (!responseId) return;
        try {
            const result = await declineResponseApex({ responseId });
            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Removed',
                    message: 'Attendee removed from the event',
                    variant: 'success'
                }));
                await this.loadResponses();
            } else {
                throw new Error(result.message || 'Unable to remove attendee');
            }
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || error.message || 'Unable to remove attendee',
                variant: 'error'
            }));
        }
    }

    async handleBlockAttendee(event) {
        event.stopPropagation();
        const contactId = event.currentTarget.dataset.contactId;
        const responseId = event.currentTarget.dataset.responseId;
        if (!contactId) return;
        try {
            await blockContactApex({
                blockedContactId: contactId,
                reason: 'Blocked from Open Event attendee list',
                isReport: false,
                reportDetails: ''
            });
            if (responseId) {
                await declineResponseApex({ responseId });
            }
            this.dispatchEvent(new ShowToastEvent({
                title: 'Blocked',
                message: 'This neighbour has been blocked and removed from the event',
                variant: 'success'
            }));
            await this.loadResponses();
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || error.message || 'Unable to block attendee',
                variant: 'error'
            }));
        }
    }

    handleEventLinkClick() {
        const url = this.eventLinkUrl;
        if (url) window.open(url, '_blank', 'noopener,noreferrer');
    }

    handleFlag() {
        const modal = this.template.querySelector('c-fimby-report-content');
        if (modal) modal.show(this.recordId, 'Needs_Offers__c');
    }

    handleUploadPhoto() {
        this.showPhotoUploader = !this.showPhotoUploader;
        if (this.showPhotoUploader) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const section = this.template.querySelector('.photo-uploader-section');
                if (section) section.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }, 100);
        }
    }

    handleClosePhotoUploader() {
        this.showPhotoUploader = false;
    }

    handlePhotoUploaded() {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Photo updated', variant: 'success' }));
        window.location.reload();
    }

    handleImagesChanged() {
        window.location.reload();
    }

    handleDeleteClick() {
        this.seriesDeleteScope = 'THIS_EVENT';
        this.showDeleteConfirm = true;
    }

    handleDeleteCancel() {
        this.showDeleteConfirm = false;
    }

    handleSeriesDeleteScopeClick(event) {
        this.seriesDeleteScope = event.currentTarget.dataset.value;
    }

    async handleDeleteConfirm() {
        this.isDeleting = true;
        try {
            const params = { recordId: this.recordId };
            if (this.isSeriesMember) {
                params.seriesDeleteScope = this.seriesDeleteScope;
            }
            await deleteNeedsOffersPost(params);
            this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', message: 'Post has been deleted', variant: 'success' }));
            window.location.href = '/';
        } catch (error) {
            console.error('Delete error:', error);
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error.body?.message || 'Failed to delete post', variant: 'error' }));
        } finally {
            this.isDeleting = false;
            this.showDeleteConfirm = false;
        }
    }

    // Image modal
    handleResponseClick(event) {
        const responseId = event.currentTarget.dataset.responseId;
        if (!responseId) return;
        window.location.href = '/response-reply?recordId=' + responseId;
    }

    handleImageClick() {
        if (!this.hasImage) return;
        this.lightboxImages = [{ url: this.imageUrl, alt: this.postTitle }];
        this.lightboxStartIndex = 0;
        this.showLightbox = true;
        requestAnimationFrame(() => {
            const lb = this.template.querySelector('c-fimby-lightbox');
            if (lb) lb.open(0);
        });
    }

    handleImageGridClick(event) {
        const detail = event.detail;
        if (!detail?.images?.length) return;
        this.lightboxImages = detail.images;
        this.lightboxStartIndex = detail.index || 0;
        this.showLightbox = true;
        requestAnimationFrame(() => {
            const lb = this.template.querySelector('c-fimby-lightbox');
            if (lb) lb.open(this.lightboxStartIndex);
        });
    }

    handleLightboxClose() {
        this.showLightbox = false;
        this.lightboxImages = [];
        this.lightboxStartIndex = 0;
    }

    // ============================================
    // MODERATOR ACTIONS
    // ============================================

    async _handleModeratorFlag() {
        try {
            await flagContent({ recordId: this.effectiveRecordId, recordType: 'Needs_Offers__c', flagValue: 'Moderator_Review' });
            this.dispatchEvent(new ShowToastEvent({ title: 'Content flagged', message: 'This content is now under review.', variant: 'success' }));
            window.location.href = '/moderator-dashboard';
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error?.body?.message || 'Could not flag content.', variant: 'error' }));
        }
    }

    async _handleModeratorHide() {
        try {
            await flagContent({ recordId: this.effectiveRecordId, recordType: 'Needs_Offers__c', flagValue: 'Moderator_Hidden' });
            this.dispatchEvent(new ShowToastEvent({ title: 'Content hidden', message: 'This content has been hidden from the feed.', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error?.body?.message || 'Could not hide content.', variant: 'error' }));
        }
    }

    async _handleModeratorContact() {
        try {
            const authorContactId = this._getAuthorContactId();
            if (!authorContactId) return;
            const conversationId = await getOrCreateModeratorConversation({ targetContactId: authorContactId });
            window.location.href = `/conversation?id=${conversationId}`;
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error?.body?.message || 'Could not start conversation.', variant: 'error' }));
        }
    }

    _getAuthorContactId() {
        if (!this.record?.data) return null;
        return getFieldValue(this.record.data, 'Needs_Offers__c.Contact__c');
    }
}