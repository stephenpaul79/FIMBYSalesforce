import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getFieldSetFields from '@salesforce/apex/FimbyFieldSetController.getFieldSetFields';
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyRecordDetailCard extends LightningElement {
    // Required properties
    @api recordId;
    @api objectApiName;

    // Display configuration
    @api cardType = 'default';
    @api displayFieldSetName = 'FIMBY_Display_Fields';
    @api editFieldSetName = 'FIMBY_Editable_Fields';
    @api primaryFieldCount = 4; // Number of fields to show before collapse

    // Header configuration
    @api showAvatar = false;
    @api avatarField = '';
    @api headerTitleField = 'Name';
    @api headerSubtitleField = '';
    @api timestampField = 'CreatedDate';

    // Image configuration
    @api showImage = false;
    @api imageField = '';
    @api imageAlt = 'Record Image';

    // Status configuration
    @api showStatus = false;
    @api statusField = 'Status__c';

    // Actions configuration
    @api canEdit = false;
    @api showMenu = false;
    @api customActions = [];

    // Internal state
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';
    @track record = {};
    @track displayFields = [];
    @track showSecondaryFields = false;
    @track objectInfo = {};

    currentUserId = Id;
    fieldsToLoad = [];
    _recordId = null;
    _wiredRecordResult;

    // Get object info
    @wire(getObjectInfo, { objectApiName: '$objectApiName' })
    handleObjectInfo({ error, data }) {
        if (data) {
            this.objectInfo = data;
        } else if (error) {
            console.error('Error getting object info:', error);
        }
    }

    // Load field set fields first
    connectedCallback() {
        // If recordId not set via @api or is empty, extract from URL
        if (!this.recordId || this.recordId.trim() === '') {
            const extractedId = this.extractRecordIdFromUrl();
            if (extractedId) {
                this._recordId = extractedId;
                console.log('📋 Extracted recordId from URL:', extractedId);
            }
        }
        this.loadDisplayFields();
    }

    // Override the recordId getter to use extracted ID if needed
    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }

    get effectiveRecordId() {
        return this.recordId || this._recordId;
    }

    // Extract record ID from URL path or query param
    extractRecordIdFromUrl() {
        try {
            const url = new URL(window.location.href);

            // First try query parameter (legacy support)
            const queryRecordId = url.searchParams.get('recordId');
            if (queryRecordId) {
                return queryRecordId;
            }

            // Then try path segment - URLs like /story/{id}, /needs-offers/{id}, /library-detail/{id}
            const pathParts = url.pathname.split('/').filter(part => part && part !== 's');

            // Look for known page patterns and get the ID after them
            const pagePatterns = ['story', 'asks-offers', 'needs-offers', 'library-item', 'library-detail', 'marketplace-detail', 'story-detail'];
            for (const pattern of pagePatterns) {
                const patternIndex = pathParts.findIndex(part => part === pattern);
                if (patternIndex !== -1 && pathParts.length > patternIndex + 1) {
                    const potentialId = pathParts[patternIndex + 1];
                    // Salesforce IDs are 15 or 18 characters
                    if (potentialId && (potentialId.length === 15 || potentialId.length === 18)) {
                        return potentialId;
                    }
                }
            }

            // Fallback: check if last path segment looks like a Salesforce ID
            const lastSegment = pathParts[pathParts.length - 1];
            if (lastSegment && (lastSegment.length === 15 || lastSegment.length === 18)) {
                return lastSegment;
            }

            console.warn('Could not extract recordId from URL:', url.href);
            return null;
        } catch (e) {
            console.error('Error extracting recordId from URL:', e);
            return null;
        }
    }

    async loadDisplayFields() {
        if (!this.objectApiName) {
            this.hasError = true;
            this.errorMessage = 'Object API Name is required.';
            this.isLoading = false;
            return;
        }

        try {
            // Try to get display fields from field set
            const fields = await getFieldSetFields({
                objectApiName: this.objectApiName,
                fieldSetName: this.displayFieldSetName
            });

            if (fields && fields.length > 0) {
                this.displayFields = fields;
                this.fieldsToLoad = fields.map(f => `${this.objectApiName}.${f.apiName}`);
            }

            // Add required fields for header/image/status
            this.addRequiredFields();

            // Now load the record
            await this.loadRecord();

        } catch (error) {
            console.error('Error loading field set:', error);
            // Fall back to standard fields
            this.addRequiredFields();
            await this.loadRecord();
        }
    }

    addRequiredFields() {
        const requiredFields = [
            this.headerTitleField,
            this.headerSubtitleField,
            this.timestampField,
            this.avatarField,
            this.imageField,
            this.statusField,
            'Name',
            'OwnerId',
            'CreatedDate',
            'LastModifiedDate'
        ].filter(f => f);

        requiredFields.forEach(field => {
            const fullField = `${this.objectApiName}.${field}`;
            if (!this.fieldsToLoad.includes(fullField)) {
                this.fieldsToLoad.push(fullField);
            }
        });
    }

    @wire(getRecord, { recordId: '$effectiveRecordId', fields: '$fieldsToLoad' })
    handleRecord(result) {
        this._wiredRecordResult = result;
        const { error, data } = result;
        if (data) {
            this.record = data;
            this.processRecordData();
            this.isLoading = false;
            this.hasError = false;
        } else if (error) {
            console.error('Error loading record:', error);
            this.hasError = true;
            this.errorMessage = error.body?.message || 'Failed to load record.';
            this.isLoading = false;
        }
    }

    async loadRecord() {
        // The @wire will handle this once fieldsToLoad is populated
        if (this.fieldsToLoad.length === 0) {
            this.isLoading = false;
        }
    }

    processRecordData() {
        // Process display fields with actual values
        this.displayFields = this.displayFields.map(field => {
            const fullFieldPath = `${this.objectApiName}.${field.apiName}`;
            const value = getFieldValue(this.record, fullFieldPath);
            return {
                ...field,
                displayValue: this.formatFieldValue(value, field.fieldType)
            };
        });
    }

    formatFieldValue(value, fieldType) {
        if (value === null || value === undefined) return '—';

        switch (fieldType) {
            case 'DATE':
                return new Date(value).toLocaleDateString();
            case 'DATETIME':
                return new Date(value).toLocaleString();
            case 'CURRENCY':
                return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
            case 'PERCENT':
                return `${value}%`;
            case 'BOOLEAN':
                return value ? 'Yes' : 'No';
            default:
                return String(value);
        }
    }

    // Computed properties
    get headerTitle() {
        if (!this.record.fields) return '';
        const field = this.record.fields[this.headerTitleField];
        return field ? field.value : '';
    }

    get headerSubtitle() {
        if (!this.headerSubtitleField || !this.record.fields) return '';
        const field = this.record.fields[this.headerSubtitleField];
        return field ? field.value : '';
    }

    get recordTimestamp() {
        if (!this.record.fields) return '';
        const field = this.record.fields[this.timestampField];
        return field ? field.value : '';
    }

    get recordTitle() {
        return this.headerTitle;
    }

    get avatarUrl() {
        if (!this.avatarField || !this.record.fields) return '';
        const field = this.record.fields[this.avatarField];
        return field ? field.value : '';
    }

    get imageUrl() {
        if (!this.imageField || !this.record.fields) return '';
        const field = this.record.fields[this.imageField];
        return field ? field.value : '';
    }

    get statusValue() {
        if (!this.statusField || !this.record.fields) return '';
        const field = this.record.fields[this.statusField];
        return field ? field.value : '';
    }

    get statusBadgeClass() {
        const status = this.statusValue.toLowerCase().replace(/\s+/g, '-');
        return `status-badge status-${status}`;
    }

    get primaryFields() {
        return this.displayFields.slice(0, this.primaryFieldCount);
    }

    get secondaryFields() {
        return this.displayFields.slice(this.primaryFieldCount);
    }

    get secondaryToggleIcon() {
        return this.showSecondaryFields ? 'utility:chevronup' : 'utility:chevrondown';
    }

    // Event handlers
    toggleSecondaryFields() {
        this.showSecondaryFields = !this.showSecondaryFields;
    }

    handleEdit() {
        const modal = this.template.querySelector('c-fimby-record-edit-modal');
        if (modal) {
            modal.show(this.recordId, this.objectApiName, this.editFieldSetName);
        }
    }

    async handleRecordSaved(event) {
        this.isLoading = true;
        if (event.detail?.recordId) {
            getRecordNotifyChange([{ recordId: event.detail.recordId }]);
        }
        if (this._wiredRecordResult) {
            await refreshApex(this._wiredRecordResult);
        }
        this.processRecordData();

        this.dispatchEvent(new CustomEvent('recordsaved', {
            detail: event.detail
        }));
    }

    handleMenuClick() {
        this.dispatchEvent(new CustomEvent('menuclick', {
            detail: { recordId: this.recordId }
        }));
    }

    handleCustomAction(event) {
        const actionName = event.currentTarget.dataset.action;
        this.dispatchEvent(new CustomEvent('customaction', {
            detail: {
                recordId: this.recordId,
                actionName: actionName
            }
        }));
    }

    handleRetry() {
        this.isLoading = true;
        this.hasError = false;
        this.loadDisplayFields();
    }
}