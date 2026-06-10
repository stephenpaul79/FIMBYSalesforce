import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import getCategoryPicklistValues from '@salesforce/apex/FimbyLibraryController.getCategoryPicklistValues';
import updateNeedsOffersPost from '@salesforce/apex/FimbyAskOfferController.updateNeedsOffersPost';
import updateBulkBuyPost from '@salesforce/apex/FimbyBulkBuyController.updateBulkBuyPost';
import updateStory from '@salesforce/apex/FimbyStoriesController.updateStory';
import updateLibraryItem from '@salesforce/apex/FimbyLibraryController.updateLibraryItem';

const NEEDS_OFFERS_FIELDS = [
    'Needs_Offers__c.Name',
    'Needs_Offers__c.Full_Details__c',
    'Needs_Offers__c.End_Date__c',
    'Needs_Offers__c.Total_Quantity__c',
    'Needs_Offers__c.Per_Response_Limit__c',
    'Needs_Offers__c.Is_Urgent__c',
    'Needs_Offers__c.Auto_Accept_Responses__c',
    'Needs_Offers__c.Auto_Share_Contact_Info__c',
    'Needs_Offers__c.Start_Date__c',
    'Needs_Offers__c.Start_Time__c',
    'Needs_Offers__c.End_Time__c',
    'Needs_Offers__c.Location__c',
    'Needs_Offers__c.Event_Type__c',
    'Needs_Offers__c.Expected_Attendance__c',
    'Needs_Offers__c.Event_Notes__c',
    'Needs_Offers__c.Event_Link__c',
    'Needs_Offers__c.Owner_Shares__c',
    'Needs_Offers__c.Allocation_Unit_Label__c',
    'Needs_Offers__c.Availability_Rule__c',
    'Needs_Offers__c.Expiry_DateTime__c',
    'Needs_Offers__c.Total_Estimated_Cost__c',
    'Needs_Offers__c.Auto_Lock_Days__c',
    'Needs_Offers__c.RecordType.DeveloperName',
    'Needs_Offers__c.Series_Parent__c',
    'Needs_Offers__c.Recurrence_Frequency__c',
    'Needs_Offers__c.Recurrence_Interval__c',
    'Needs_Offers__c.Recurrence_End_Mode__c',
    'Needs_Offers__c.Recurrence_End_Date__c',
    'Needs_Offers__c.Recurrence_Max_Occurrences__c',
    'Needs_Offers__c.Reinvite_Prior_Attendees__c',
    'Needs_Offers__c.Series_Parent__r.Recurrence_Frequency__c',
    'Needs_Offers__c.Series_Parent__r.Recurrence_Interval__c',
    'Needs_Offers__c.Series_Parent__r.Recurrence_End_Mode__c',
    'Needs_Offers__c.Series_Parent__r.Recurrence_End_Date__c',
    'Needs_Offers__c.Series_Parent__r.Recurrence_Max_Occurrences__c',
    'Needs_Offers__c.Series_Parent__r.Reinvite_Prior_Attendees__c'
];

const STORY_FIELDS = [
    'Story__c.Name',
    'Story__c.Message__c',
    'Story__c.Type__c',
    'Story__c.Share_on_Social_Media__c'
];

const LIBRARY_FIELDS = [
    'Library_Item__c.Name',
    'Library_Item__c.Description__c',
    'Library_Item__c.Category__c',
    'Library_Item__c.Max_Lending_Time_In_Days__c',
    'Library_Item__c.Auto_Accept_Requests__c',
    'Library_Item__c.Auto_Share_Contact_Info__c'
];

const STORY_TYPE_OPTIONS = [
    { label: 'Thank You', value: 'Thank You' },
    { label: 'God Story', value: 'God Story' },
    { label: 'Prayer Request', value: 'Prayer' },
    { label: 'Introduction', value: 'Bio' },
    { label: 'Support Needed', value: 'Lament' },
    { label: 'Neighbourhood Moment', value: 'Neighbourhood Moment' }
];

export default class FimbyPostEditModal extends LightningElement {
    @api recordId;
    @track postKind = '';
    @track isVisible = false;
    @track isSaving = false;
    @track isLoading = true;
    @track errorMessage = '';
    @track actingAsContact = null;
    @track hasMultipleIdentities = false;
    @track libraryCategoryOptions = [];

    // Shared / Needs_Offers form state
    @track title = '';
    @track description = '';
    @track endDate = '';
    @track quantity = '';
    @track perResponseLimit = '';
    @track isUrgent = false;
    @track autoAcceptResponses = false;
    @track autoShareContactInfo = false;
    @track eventStart = '';
    @track eventEnd = '';
    @track location = '';
    @track eventType = '';
    @track expectedAttendance = '';
    @track eventNotes = '';
    @track eventLink = '';

    @track recurrenceEnabled = false;
    @track recurrenceInterval = 1;
    @track recurrenceFrequency = 'Week';
    @track recurrenceEndMode = 'Never';
    @track recurrenceEndDate = '';
    @track recurrenceMaxOccurrences = '';
    @track reinvitePriorAttendees = false;
    @track recurrenceScope = 'thisOnly';
    @track isSeriesMember = false;

    // Bulk buy
    @track totalQuantity = '';
    @track ownerShares = '';
    @track unitLabel = '';
    @track availabilityRule = 'Open_Until_Full_Or_Closed';
    @track expiryDateTime = '';
    @track totalEstimatedCost = '';
    @track autoLockDays = '7';

    // Story
    @track storyType = '';
    @track storyMessage = '';
    @track shareOnSocial = false;

    // Library
    @track libraryCategory = '';
    @track maxLendingDays = 7;

    _formPopulated = false;
    _needsDomSync = false;

    @wire(getActingAsContact)
    wiredContact({ data }) {
        if (data) {
            this.actingAsContact = data;
        }
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ data }) {
        this.hasMultipleIdentities = Array.isArray(data) && data.length > 0;
    }

    @wire(getCategoryPicklistValues)
    wiredCategories({ data }) {
        if (data) {
            this.libraryCategoryOptions = data.map((c) => ({
                label: c.label,
                value: c.value
            }));
            if (this.isLibrary && this._formPopulated && this.isVisible && !this.isLoading) {
                this._needsDomSync = true;
            }
        }
    }

    @wire(getRecord, { recordId: '$wiredRecordId', fields: '$wiredFields' })
    wiredRecord({ error, data }) {
        if (!this.isVisible || !this.wiredRecordId) {
            return;
        }
        if (data) {
            this.populateForm(data);
            this._needsDomSync = true;
            this.isLoading = false;
            this.errorMessage = '';
        } else if (error) {
            this.isLoading = false;
            this.errorMessage = error.body?.message || 'Failed to load post data.';
        }
    }

    get wiredRecordId() {
        return this.isVisible && this.recordId ? this.recordId : undefined;
    }

    get wiredFields() {
        if (!this.postKind) return [];
        if (this.postKind === 'story') return STORY_FIELDS;
        if (this.postKind === 'library') return LIBRARY_FIELDS;
        return NEEDS_OFFERS_FIELDS;
    }

    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }
    get saveIconUrl() { return `${IMPACT_ICONS}/save.png`; }
    get posterIconUrl() { return `${IMPACT_ICONS}/ProfileActive.png`; }
    get postDetailsIconUrl() { return `${IMPACT_ICONS}/BulletinBoardActive.png`; }
    get eventDetailsIconUrl() { return `${IMPACT_ICONS}/plannersm.png`; }
    get settingsIconUrl() { return `${IMPACT_ICONS}/gear.png`; }
    get quantityIconUrl() { return `${IMPACT_ICONS}/giftsm.png`; }
    get sharesIconUrl() { return `${IMPACT_ICONS}/giftsm.png`; }
    get availabilityIconUrl() { return `${IMPACT_ICONS}/plannersm.png`; }
    get costIconUrl() { return `${IMPACT_ICONS}/lightbulb.png`; }
    get storyIconUrl() { return `${IMPACT_ICONS}/StoriesActive.png`; }

    get showFooter() { return !this.isLoading && !this.errorMessage; }
    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.postingAsDisplayName;
    }
    get postingAsDisplayName() {
        return this.actingAsContact?.postingAsDisplayName
            || this.actingAsContact?.actingAsContactName
            || this.actingAsContact?.contactName
            || '';
    }

    get modalTitle() {
        const titles = {
            ask: 'Edit Ask',
            offer: 'Edit Offer',
            event: 'Edit Event',
            bulkBuy: 'Edit Bulk Buy',
            story: 'Edit Story',
            library: 'Edit Library Item'
        };
        return titles[this.postKind] || 'Edit Post';
    }

    get isAsk() { return this.postKind === 'ask'; }
    get isOffer() { return this.postKind === 'offer'; }
    get isEvent() { return this.postKind === 'event'; }
    get isBulkBuy() { return this.postKind === 'bulkBuy'; }
    get isStory() { return this.postKind === 'story'; }
    get isLibrary() { return this.postKind === 'library'; }
    get isNeedsOffers() { return this.isAsk || this.isOffer || this.isEvent; }

    get isGathering() { return this.isEvent && this.eventType === 'Gathering'; }
    get isOpenEvent() { return this.isEvent && this.eventType === 'Open_Event'; }
    get isCommunityEvent() { return this.isEvent && this.eventType === 'Community_Event'; }

    get postDetailsSectionTitle() {
        if (this.isBulkBuy) return 'Your Bulk Buy';
        if (this.isEvent) return 'Post Details';
        if (this.isAsk) return 'Post Details';
        if (this.isOffer) return 'Post Details';
        if (this.isStory) return 'Story Details';
        if (this.isLibrary) return 'Item Details';
        return 'Post Details';
    }

    get showQuantityField() { return this.isGathering; }
    get showPerResponseLimit() {
        const qty = parseInt(this.quantity, 10);
        return (this.isOffer || this.isGathering) && qty > 1;
    }
    get showExpectedAttendance() { return this.isOpenEvent; }
    get showEventNotes() { return this.isOpenEvent || this.isCommunityEvent; }
    get showEventLink() { return this.isCommunityEvent; }
    get showWhenWhereSection() { return this.isEvent; }
    get showRecurrenceSection() { return this.isEvent; }
    get showRecurrenceScopeChooser() { return this.isEvent && this.isSeriesMember && this.recurrenceEnabled; }
    get showRecurrenceEndDate() { return this.recurrenceEnabled && this.recurrenceEndMode === 'On_Date'; }
    get showRecurrenceMaxOccurrences() { return this.recurrenceEnabled && this.recurrenceEndMode === 'After_N'; }

    get recurrenceEndModeOptions() {
        return [
            { label: 'Never', value: 'Never', selected: this.recurrenceEndMode === 'Never', pillClass: this.recurrenceEndMode === 'Never' ? 'pill-btn selected' : 'pill-btn' },
            { label: 'On date', value: 'On_Date', selected: this.recurrenceEndMode === 'On_Date', pillClass: this.recurrenceEndMode === 'On_Date' ? 'pill-btn selected' : 'pill-btn' },
            { label: 'After', value: 'After_N', selected: this.recurrenceEndMode === 'After_N', pillClass: this.recurrenceEndMode === 'After_N' ? 'pill-btn selected' : 'pill-btn' }
        ];
    }

    get recurrenceScopeOptions() {
        return [
            { label: 'This occurrence only', value: 'thisOnly', selected: this.recurrenceScope === 'thisOnly', pillClass: this.recurrenceScope === 'thisOnly' ? 'pill-btn selected' : 'pill-btn' },
            { label: 'This and future occurrences', value: 'thisAndFuture', selected: this.recurrenceScope === 'thisAndFuture', pillClass: this.recurrenceScope === 'thisAndFuture' ? 'pill-btn selected' : 'pill-btn' }
        ];
    }
    get showAvailabilitySection() { return this.isOffer; }
    get showPostSettingsSection() {
        return this.isAsk || this.isOffer || this.isGathering || this.isOpenEvent;
    }
    get showAutoAcceptSection() { return this.isAsk || this.isOffer || this.isGathering; }
    get showAutoShareSection() {
        return this.isAsk || this.isOffer || this.isGathering || this.isOpenEvent;
    }
    get showUrgentToggle() { return this.isAsk; }

    get quantityLabel() {
        return this.isGathering ? 'Spots Available' : 'Quantity Available';
    }
    get perResponseLimitLabel() {
        return this.isGathering ? 'Max RSVPs per Person' : 'Per Response Limit';
    }
    get autoAcceptLabel() {
        return this.isGathering ? 'Auto-Accept RSVPs' : 'Auto-Accept Responses';
    }
    get endDateLabel() {
        return this.isEvent ? 'Post Expires' : 'Post Expiration Date';
    }
    get eventNotesLabel() {
        return this.isOpenEvent ? 'What to Bring' : 'Additional Info';
    }
    get eventNotesPlaceholder() {
        return this.isOpenEvent
            ? 'e.g., Bring a lawn chair and a dish to share'
            : 'Venue details, parking, anything not in the link';
    }

    get titleCharacterCount() { return `${(this.title || '').length}/80`; }
    get descriptionCharacterCount() { return `${(this.description || '').length}/2000`; }
    get storyMessageCount() { return `${(this.storyMessage || '').length}/2000`; }
    get libraryDescriptionCount() { return `${(this.description || '').length}/255`; }

    get titleCountClass() { return this._countClass((this.title || '').length, 80); }
    get descriptionCountClass() { return this._countClass((this.description || '').length, 2000); }
    get storyMessageCountClass() { return this._countClass((this.storyMessage || '').length, 2000); }
    get libraryDescriptionCountClass() { return this._countClass((this.description || '').length, 255); }

    get parsedTotal() {
        const v = parseInt(this.totalQuantity, 10);
        return Number.isFinite(v) && v >= 1 ? v : 0;
    }
    get parsedOwnerShares() {
        const v = parseInt(this.ownerShares, 10);
        return Number.isFinite(v) && v >= 0 ? v : 0;
    }
    get availableForNeighbours() {
        return Math.max(0, this.parsedTotal - this.parsedOwnerShares);
    }
    get ownerSharesMax() {
        const t = this.parsedTotal;
        return t >= 1 ? t - 1 : 0;
    }
    get isExpiryVisible() { return this.availabilityRule === 'Expires_At_Date'; }
    get estimatedCostPerShare() {
        const cost = parseFloat(this.totalEstimatedCost);
        const qty = this.parsedTotal;
        if (!Number.isFinite(cost) || qty < 1) return null;
        return (cost / qty).toFixed(2);
    }
    get estimatedCostDisplay() {
        const perShare = this.estimatedCostPerShare;
        return perShare != null ? `~$${perShare} per share` : '';
    }
    get showSharesPreview() { return this.isBulkBuy && this.parsedTotal >= 1; }
    get sharesPreviewText() {
        const total = this.parsedTotal;
        const avail = this.availableForNeighbours;
        const unit = (this.unitLabel || '').trim() || 'share';
        const plural = avail === 1 || unit.endsWith('s') ? unit : `${unit}s`;
        return `${avail} of ${total} ${plural} available for neighbours to reserve`;
    }

    get availabilityOptions() {
        return [
            { label: 'Expires At Date', value: 'Expires_At_Date', selected: this.availabilityRule === 'Expires_At_Date', pillClass: this.availabilityRule === 'Expires_At_Date' ? 'pill-btn selected' : 'pill-btn' },
            { label: 'Open Until Full Or Closed', value: 'Open_Until_Full_Or_Closed', selected: this.availabilityRule === 'Open_Until_Full_Or_Closed', pillClass: this.availabilityRule === 'Open_Until_Full_Or_Closed' ? 'pill-btn selected' : 'pill-btn' }
        ];
    }

    get autoLockOptions() {
        return ['3', '7', '14'].map((v) => ({
            label: `${v} days`,
            value: v,
            selected: this.autoLockDays === v,
            pillClass: this.autoLockDays === v ? 'pill-btn selected' : 'pill-btn'
        }));
    }

    get storyTypeOptions() {
        return STORY_TYPE_OPTIONS.map((opt) => ({
            ...opt,
            selected: this.storyType === opt.value
        }));
    }

    get libraryCategorySelectOptions() {
        return (this.libraryCategoryOptions || []).map((cat) => ({
            ...cat,
            selected: this.libraryCategory === cat.value
        }));
    }

    get eventEndValidationError() {
        if (!this.eventStart || !this.eventEnd) return '';
        if (new Date(this.eventEnd) <= new Date(this.eventStart)) {
            return 'The end time needs to come after the start time.';
        }
        return '';
    }

    get isSaveDisabled() {
        if (this.isSaving) return true;
        if (this.isBulkBuy) {
            if (!this.title.trim() || this.parsedTotal < 1) return true;
            if (this.isExpiryVisible && !this.expiryDateTime) return true;
        }
        if (this.isStory && (!this.title.trim() || !this.storyMessage.trim() || !this.storyType)) return true;
        if (this.isLibrary && (!this.title.trim() || !this.description.trim() || !this.libraryCategory)) return true;
        if (this.isNeedsOffers && !this.title.trim()) return true;
        if (this.isEvent && this.eventEndValidationError) return true;
        return false;
    }

    @api
    show(recordId, postKind) {
        if (recordId) this.recordId = recordId;
        if (postKind) this.postKind = postKind;
        this._resetFormState();
        this._formPopulated = false;
        this.isVisible = true;
        this.isLoading = true;
        this.errorMessage = '';
        this.isSaving = false;
    }

    @api
    hide() {
        this.isVisible = false;
        this.isSaving = false;
    }

    renderedCallback() {
        if (!this._needsDomSync || this.isLoading || !this.isVisible) {
            return;
        }
        this._syncNativeFieldValues();
        this._needsDomSync = false;
    }

    _syncNativeFieldValues() {
        this.template.querySelectorAll('textarea[data-field]').forEach((el) => {
            const field = el.dataset.field;
            const val = this[field];
            if (field && val != null && el.value !== val) {
                el.value = val;
            }
        });

        const storySelect = this.template.querySelector('#story-type');
        if (storySelect && this.storyType) {
            storySelect.value = this.storyType;
        }

        const categorySelect = this.template.querySelector('#lib-category');
        if (categorySelect && this.libraryCategory) {
            categorySelect.value = this.libraryCategory;
        }
    }

    populateForm(data) {
        if (this._formPopulated) return;
        this._formPopulated = true;

        if (this.isStory) {
            this.title = getFieldValue(data, 'Story__c.Name') || '';
            this.storyMessage = getFieldValue(data, 'Story__c.Message__c') || '';
            this.storyType = getFieldValue(data, 'Story__c.Type__c') || '';
            this.shareOnSocial = getFieldValue(data, 'Story__c.Share_on_Social_Media__c') === true;
            return;
        }

        if (this.isLibrary) {
            this.title = getFieldValue(data, 'Library_Item__c.Name') || '';
            this.description = getFieldValue(data, 'Library_Item__c.Description__c') || '';
            this.libraryCategory = getFieldValue(data, 'Library_Item__c.Category__c') || '';
            const maxDays = getFieldValue(data, 'Library_Item__c.Max_Lending_Time_In_Days__c');
            this.maxLendingDays = maxDays != null ? maxDays : 7;
            this.autoAcceptResponses = getFieldValue(data, 'Library_Item__c.Auto_Accept_Requests__c') === true;
            this.autoShareContactInfo = getFieldValue(data, 'Library_Item__c.Auto_Share_Contact_Info__c') === true;
            return;
        }

        this.title = getFieldValue(data, 'Needs_Offers__c.Name') || '';
        this.description = getFieldValue(data, 'Needs_Offers__c.Full_Details__c') || '';
        this.endDate = getFieldValue(data, 'Needs_Offers__c.End_Date__c') || '';
        this.quantity = this._toStr(getFieldValue(data, 'Needs_Offers__c.Total_Quantity__c'));
        this.perResponseLimit = this._toStr(getFieldValue(data, 'Needs_Offers__c.Per_Response_Limit__c'));
        this.isUrgent = getFieldValue(data, 'Needs_Offers__c.Is_Urgent__c') === true;
        this.autoAcceptResponses = getFieldValue(data, 'Needs_Offers__c.Auto_Accept_Responses__c') === true;
        this.autoShareContactInfo = getFieldValue(data, 'Needs_Offers__c.Auto_Share_Contact_Info__c') === true;
        this.location = getFieldValue(data, 'Needs_Offers__c.Location__c') || '';
        this.eventType = getFieldValue(data, 'Needs_Offers__c.Event_Type__c') || '';
        this.expectedAttendance = this._toStr(getFieldValue(data, 'Needs_Offers__c.Expected_Attendance__c'));
        this.eventNotes = getFieldValue(data, 'Needs_Offers__c.Event_Notes__c') || '';
        this.eventLink = getFieldValue(data, 'Needs_Offers__c.Event_Link__c') || '';

        const startDate = getFieldValue(data, 'Needs_Offers__c.Start_Date__c');
        const startTime = getFieldValue(data, 'Needs_Offers__c.Start_Time__c');
        const endTime = getFieldValue(data, 'Needs_Offers__c.End_Time__c');
        const endDateVal = getFieldValue(data, 'Needs_Offers__c.End_Date__c');
        this.eventStart = this._toDatetimeLocal(startDate, startTime);
        this.eventEnd = this._toDatetimeLocal(endDateVal, endTime);

        const seriesParentId = getFieldValue(data, 'Needs_Offers__c.Series_Parent__c');
        const freq = seriesParentId
            ? getFieldValue(data, 'Needs_Offers__c.Series_Parent__r.Recurrence_Frequency__c')
            : getFieldValue(data, 'Needs_Offers__c.Recurrence_Frequency__c');
        this.isSeriesMember = !!seriesParentId || !!freq;
        this.recurrenceEnabled = !!freq;
        if (this.recurrenceEnabled) {
            const interval = seriesParentId
                ? getFieldValue(data, 'Needs_Offers__c.Series_Parent__r.Recurrence_Interval__c')
                : getFieldValue(data, 'Needs_Offers__c.Recurrence_Interval__c');
            this.recurrenceInterval = interval != null ? interval : 1;
            this.recurrenceFrequency = (freq === 'Day' ? 'Week' : freq) || 'Week';
            const endMode = seriesParentId
                ? getFieldValue(data, 'Needs_Offers__c.Series_Parent__r.Recurrence_End_Mode__c')
                : getFieldValue(data, 'Needs_Offers__c.Recurrence_End_Mode__c');
            this.recurrenceEndMode = endMode || 'Never';
            const endDate = seriesParentId
                ? getFieldValue(data, 'Needs_Offers__c.Series_Parent__r.Recurrence_End_Date__c')
                : getFieldValue(data, 'Needs_Offers__c.Recurrence_End_Date__c');
            this.recurrenceEndDate = endDate || '';
            const maxOcc = seriesParentId
                ? getFieldValue(data, 'Needs_Offers__c.Series_Parent__r.Recurrence_Max_Occurrences__c')
                : getFieldValue(data, 'Needs_Offers__c.Recurrence_Max_Occurrences__c');
            this.recurrenceMaxOccurrences = maxOcc != null ? String(maxOcc) : '';
            const reinvite = seriesParentId
                ? getFieldValue(data, 'Needs_Offers__c.Series_Parent__r.Reinvite_Prior_Attendees__c')
                : getFieldValue(data, 'Needs_Offers__c.Reinvite_Prior_Attendees__c');
            this.reinvitePriorAttendees = reinvite === true;
        }
        this.recurrenceScope = 'thisOnly';

        if (this.isBulkBuy) {
            this.totalQuantity = this._toStr(getFieldValue(data, 'Needs_Offers__c.Total_Quantity__c'));
            this.ownerShares = this._toStr(getFieldValue(data, 'Needs_Offers__c.Owner_Shares__c'));
            this.unitLabel = getFieldValue(data, 'Needs_Offers__c.Allocation_Unit_Label__c') || '';
            this.perResponseLimit = this._toStr(getFieldValue(data, 'Needs_Offers__c.Per_Response_Limit__c'));
            this.availabilityRule = getFieldValue(data, 'Needs_Offers__c.Availability_Rule__c') || 'Open_Until_Full_Or_Closed';
            this.expiryDateTime = this._datetimeToLocal(getFieldValue(data, 'Needs_Offers__c.Expiry_DateTime__c'));
            const cost = getFieldValue(data, 'Needs_Offers__c.Total_Estimated_Cost__c');
            this.totalEstimatedCost = cost != null ? String(cost) : '';
            this.autoLockDays = this._toStr(getFieldValue(data, 'Needs_Offers__c.Auto_Lock_Days__c')) || '7';
        }
    }

    _countClass(len, max) {
        if (len >= max) return 'character-count at-limit';
        if (len >= Math.floor(max * 0.9)) return 'character-count near-limit';
        return 'character-count';
    }

    _toStr(val) {
        return val != null && val !== '' ? String(val) : '';
    }

    _timeToHHmm(timeMs) {
        if (timeMs == null) return '00:00';
        const totalMinutes = Math.floor(timeMs / 60000);
        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
    }

    _toDatetimeLocal(dateStr, timeMs) {
        if (!dateStr) return '';
        const hhmm = this._timeToHHmm(timeMs);
        return `${dateStr}T${hhmm}`;
    }

    _datetimeToLocal(dtValue) {
        if (!dtValue) return '';
        const d = new Date(dtValue);
        if (Number.isNaN(d.getTime())) return '';
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget && !this.isSaving) {
            this.hide();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        if (!this.isSaving) this.hide();
    }

    handleCancel() {
        if (!this.isSaving) this.hide();
    }

    handleRetry() {
        this._formPopulated = false;
        this.isLoading = true;
        this.errorMessage = '';
        const rid = this.recordId;
        this.recordId = undefined;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.recordId = rid;
        });
    }

    _resetFormState() {
        this.title = '';
        this.description = '';
        this.endDate = '';
        this.quantity = '';
        this.perResponseLimit = '';
        this.isUrgent = false;
        this.autoAcceptResponses = false;
        this.autoShareContactInfo = false;
        this.eventStart = '';
        this.eventEnd = '';
        this.location = '';
        this.eventType = '';
        this.expectedAttendance = '';
        this.eventNotes = '';
        this.eventLink = '';
        this.totalQuantity = '';
        this.ownerShares = '';
        this.unitLabel = '';
        this.availabilityRule = 'Open_Until_Full_Or_Closed';
        this.expiryDateTime = '';
        this.totalEstimatedCost = '';
        this.autoLockDays = '7';
        this.storyType = '';
        this.storyMessage = '';
        this.shareOnSocial = false;
        this.libraryCategory = '';
        this.maxLendingDays = 7;
        this.recurrenceEnabled = false;
        this.recurrenceInterval = 1;
        this.recurrenceFrequency = 'Week';
        this.recurrenceEndMode = 'Never';
        this.recurrenceEndDate = '';
        this.recurrenceMaxOccurrences = '';
        this.reinvitePriorAttendees = false;
        this.recurrenceScope = 'thisOnly';
        this.isSeriesMember = false;
    }

    handleRecurrenceEnabledChange(event) { this.recurrenceEnabled = event.target.checked; }
    handleRecurrenceIntervalChange(event) {
        const val = parseInt(event.target.value, 10);
        this.recurrenceInterval = Number.isFinite(val) && val >= 1 ? val : 1;
    }
    handleRecurrenceFrequencyChange(event) { this.recurrenceFrequency = event.target.value; }
    handleRecurrenceEndModeClick(event) { this.recurrenceEndMode = event.currentTarget.dataset.value; }
    handleRecurrenceEndDateChange(event) { this.recurrenceEndDate = event.target.value; }
    handleRecurrenceMaxOccurrencesChange(event) { this.recurrenceMaxOccurrences = event.target.value; }
    handleReinvitePriorAttendeesChange(event) { this.reinvitePriorAttendees = event.target.checked; }
    handleRecurrenceScopeClick(event) { this.recurrenceScope = event.currentTarget.dataset.value; }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        if (field) {
            this[field] = value;
        }
    }

    handleUrgentChange(event) { this.isUrgent = event.target.checked; }
    handleAutoAcceptChange(event) { this.autoAcceptResponses = event.target.checked; }
    handleAutoShareChange(event) { this.autoShareContactInfo = event.target.checked; }
    handleShareOnSocialChange(event) { this.shareOnSocial = event.target.checked; }

    handleQuantityChange(event) {
        this.quantity = event.target.value;
        const qty = parseInt(this.quantity, 10);
        if (!Number.isFinite(qty) || qty <= 1) {
            this.perResponseLimit = '1';
        }
    }

    handleTotalQuantityChange(event) {
        this.totalQuantity = event.target.value;
        if (this.parsedOwnerShares > this.parsedTotal - 1 && this.parsedTotal >= 1) {
            this.ownerShares = String(this.parsedTotal - 1);
        }
    }

    handleAvailabilityPillClick(event) {
        this.availabilityRule = event.currentTarget.dataset.value;
    }

    handleAutoLockPillClick(event) {
        this.autoLockDays = event.currentTarget.dataset.value;
    }

    async handleSave() {
        if (this.isSaveDisabled) return;
        this.isSaving = true;
        try {
            if (this.isBulkBuy) {
                await this._saveBulkBuy();
            } else if (this.isStory) {
                await this._saveStory();
            } else if (this.isLibrary) {
                await this._saveLibrary();
            } else {
                await this._saveNeedsOffers();
            }

            getRecordNotifyChange([{ recordId: this.recordId }]);
            this.dispatchEvent(new CustomEvent('recordsaved', {
                detail: { recordId: this.recordId, postKind: this.postKind }
            }));
            this.hide();
        } catch (error) {
            const msg = error.body?.message || error.message || 'Failed to save changes.';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: msg,
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    async _saveNeedsOffers() {
        const payload = {
            recordId: this.recordId,
            title: this.title.trim(),
            description: this.description,
            endDate: this.endDate || null,
            autoAcceptResponses: this.autoAcceptResponses,
            autoShareContactInfo: this.autoShareContactInfo
        };

        if (this.isAsk) {
            payload.isUrgent = this.isUrgent;
        }
        if (this.isOffer || this.isGathering) {
            payload.quantity = this.quantity ? parseInt(this.quantity, 10) : null;
            payload.perResponseLimit = this.perResponseLimit ? parseInt(this.perResponseLimit, 10) : null;
        }
        if (this.isEvent) {
            payload.eventStart = this.eventStart || null;
            payload.eventEnd = this.eventEnd || null;
            payload.location = this.location;
            if (this.isOpenEvent && this.expectedAttendance) {
                payload.expectedAttendance = parseInt(this.expectedAttendance, 10);
            }
            if (this.showEventNotes) {
                payload.eventNotes = this.eventNotes;
            }
            if (this.isCommunityEvent) {
                payload.eventLink = this.eventLink;
            }
            if (this.isGathering) {
                payload.quantity = this.quantity ? parseInt(this.quantity, 10) : null;
                payload.perResponseLimit = this.perResponseLimit ? parseInt(this.perResponseLimit, 10) : null;
            }

            payload.recurrenceEnabled = this.recurrenceEnabled;
            if (this.recurrenceEnabled) {
                payload.recurrenceFrequency = this.recurrenceFrequency;
                payload.recurrenceInterval = parseInt(this.recurrenceInterval, 10) || 1;
                payload.recurrenceEndMode = this.recurrenceEndMode;
                payload.recurrenceEndDate = this.recurrenceEndMode === 'On_Date' ? (this.recurrenceEndDate || null) : null;
                payload.recurrenceMaxOccurrences = this.recurrenceEndMode === 'After_N' && this.recurrenceMaxOccurrences
                    ? parseInt(this.recurrenceMaxOccurrences, 10) : null;
                payload.reinvitePriorAttendees = this.reinvitePriorAttendees;
                payload.recurrenceScope = this.recurrenceScope;
            } else if (this.isSeriesMember) {
                payload.recurrenceEnabled = false;
            }
        }

        await updateNeedsOffersPost({ postData: JSON.stringify(payload) });
    }

    async _saveBulkBuy() {
        const payload = {
            recordId: this.recordId,
            title: this.title.trim(),
            description: this.description,
            totalQuantity: parseInt(this.totalQuantity, 10),
            ownerShares: parseInt(this.ownerShares, 10) || 0,
            unitLabel: this.unitLabel,
            perResponseLimit: this.perResponseLimit ? parseInt(this.perResponseLimit, 10) : null,
            availabilityRule: this.availabilityRule,
            expiryDateTime: this.isExpiryVisible ? this.expiryDateTime : null,
            totalEstimatedCost: this.totalEstimatedCost ? parseFloat(this.totalEstimatedCost) : null,
            autoLockDays: this.autoLockDays
        };
        await updateBulkBuyPost({ postData: JSON.stringify(payload) });
    }

    async _saveStory() {
        const payload = {
            recordId: this.recordId,
            title: this.title.trim(),
            content: this.storyMessage,
            category: this.storyType,
            shareOnSocial: this.shareOnSocial
        };
        await updateStory({ storyData: JSON.stringify(payload) });
    }

    async _saveLibrary() {
        const payload = {
            recordId: this.recordId,
            title: this.title.trim(),
            description: this.description,
            category: this.libraryCategory,
            maxLendingDays: parseInt(this.maxLendingDays, 10) || 7,
            autoAcceptRequests: this.autoAcceptResponses,
            autoShareContactInfo: this.autoShareContactInfo
        };
        await updateLibraryItem({ itemData: JSON.stringify(payload) });
    }
}
