import { LightningElement, api, track } from 'lwc';

export default class FimbyResponsiveList extends LightningElement {
    // List configuration
    @api title = '';
    @api subtitle = '';
    @api objectApiName = '';
    @api records = [];
    @api columns = [];
    @api rowActions = [];

    // Header options
    @api showHeader = false;
    @api showSearch = false;
    @api searchPlaceholder = 'Search...';
    @api showViewToggle = false;
    @api showCreateButton = false;
    @api createButtonLabel = 'New';

    // Empty state options
    @api emptyStateIcon = 'utility:info';
    @api emptyStateTitle = 'No Records Found';
    @api emptyStateMessage = 'There are no records to display.';

    // View options
    @api defaultView = 'auto'; // auto, table, card
    @api primaryField = 'Name';
    @api statusField = '';
    @api imageFieldName = '';
    @api imagePlaceholderIcon = 'utility:user';

    // Pagination
    @api showLoadMore = false;
    @api totalRecords = 0;

    // Internal state
    @track isLoading = false;
    @track isLoadingMore = false;
    @track searchTerm = '';
    @track currentView = 'card';
    @track sortField = '';
    @track sortDirection = 'asc';
    @track windowWidth = 1024;

    connectedCallback() {
        this.updateWindowWidth();
        window.addEventListener('resize', this.handleResize.bind(this));
        this.determineDefaultView();
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this.handleResize.bind(this));
    }

    handleResize() {
        this.updateWindowWidth();
        if (this.defaultView === 'auto') {
            this.currentView = this.windowWidth <= 768 ? 'card' : 'table';
        }
    }

    updateWindowWidth() {
        this.windowWidth = window.innerWidth;
    }

    determineDefaultView() {
        if (this.defaultView === 'auto') {
            this.currentView = this.windowWidth <= 768 ? 'card' : 'table';
        } else {
            this.currentView = this.defaultView;
        }
    }

    // Computed properties
    get isTableView() {
        return this.currentView === 'table';
    }

    get isCardView() {
        return this.currentView === 'card';
    }

    get tableViewClass() {
        return `view-toggle-btn ${this.currentView === 'table' ? 'active' : ''}`;
    }

    get cardViewClass() {
        return `view-toggle-btn ${this.currentView === 'card' ? 'active' : ''}`;
    }

    get hasRowActions() {
        return this.rowActions && this.rowActions.length > 0;
    }

    get hasImageColumn() {
        return this.imageFieldName && this.imageFieldName.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && (!this.records || this.records.length === 0);
    }

    get recordCountLabel() {
        const count = this.processedRecords.length;
        const total = this.totalRecords || this.records.length;
        if (count === total) {
            return `${count} record${count !== 1 ? 's' : ''}`;
        }
        return `${count} of ${total} record${total !== 1 ? 's' : ''}`;
    }

    get processedColumns() {
        return this.columns.map((col, index) => {
            const processed = { ...col };
            processed.key = `col-${index}-${col.fieldName}`;
            processed.sortable = col.sortable !== false;

            // Sort indicator
            if (this.sortField === col.fieldName) {
                processed.sortIcon = this.sortDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
            } else {
                processed.sortIcon = 'utility:sort';
            }

            return processed;
        });
    }

    get processedRecords() {
        let filtered = [...this.records];

        // Apply search filter
        if (this.searchTerm) {
            const searchLower = this.searchTerm.toLowerCase();
            filtered = filtered.filter(record => {
                return this.columns.some(col => {
                    const fieldName = col.displayField || col.fieldName;
                    const value = this.getFieldValue(record, fieldName);
                    return value && String(value).toLowerCase().includes(searchLower);
                });
            });
        }

        // Apply sort
        if (this.sortField) {
            filtered.sort((a, b) => {
                const valA = this.getFieldValue(a, this.sortField) || '';
                const valB = this.getFieldValue(b, this.sortField) || '';
                const comparison = String(valA).localeCompare(String(valB));
                return this.sortDirection === 'asc' ? comparison : -comparison;
            });
        }

        // Process records for display
        return filtered.map((record, recordIndex) => {
            const processed = {
                _id: record.Id,
                _hasImage: this.hasImageColumn,
                _imageUrl: this.getFieldValue(record, this.imageFieldName),
                _primaryValue: this.getFieldValue(record, this.primaryField) || '—',
                _statusValue: this.statusField ? this.getFieldValue(record, this.statusField) : null,
                _statusBadgeClass: this.getStatusBadgeClass(this.getFieldValue(record, this.statusField)),
                _cells: this.buildCells(record, recordIndex),
                _cardFields: this.buildCardFields(record, recordIndex)
            };
            return processed;
        });
    }

    getFieldValue(record, fieldName) {
        if (!fieldName || !record) return null;

        // Handle nested fields like Account.Name
        if (fieldName.includes('.')) {
            const parts = fieldName.split('.');
            let value = record;
            for (const part of parts) {
                if (value && typeof value === 'object') {
                    value = value[part];
                } else {
                    return null;
                }
            }
            return value;
        }

        return record[fieldName];
    }

    buildCells(record, recordIndex) {
        return this.columns.map((col, colIndex) => {
            const fieldName = col.displayField || col.fieldName;
            const value = this.getFieldValue(record, fieldName);

            return {
                key: `cell-${recordIndex}-${colIndex}`,
                fieldName: col.fieldName,
                value: value != null ? value : '—',
                hasValue: value != null && value !== '',
                isImage: col.isImage === true,
                isLink: col.isLink === true,
                isBadge: col.isBadge === true,
                isStandard: !col.isImage && !col.isLink && !col.isBadge,
                placeholderIcon: col.placeholderIcon || 'utility:image',
                badgeClass: col.isBadge ? this.getStatusBadgeClass(value) : ''
            };
        });
    }

    buildCardFields(record, recordIndex) {
        // For card view, exclude primary field, image, and status fields
        const cardColumns = this.columns.filter(col =>
            col.fieldName !== this.primaryField &&
            col.fieldName !== this.imageFieldName &&
            col.fieldName !== this.statusField &&
            !col.isImage
        ).slice(0, 4); // Show max 4 fields in card

        return cardColumns.map((col, colIndex) => {
            const fieldName = col.displayField || col.fieldName;
            const value = this.getFieldValue(record, fieldName);
            return {
                key: `card-field-${recordIndex}-${colIndex}`,
                label: col.label,
                value: value != null ? value : '—'
            };
        });
    }

    getStatusBadgeClass(status) {
        if (!status) return 'status-badge';
        const statusLower = String(status).toLowerCase().replace(/\s+/g, '-');
        return `status-badge status-${statusLower}`;
    }

    // Event handlers
    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.dispatchEvent(new CustomEvent('search', {
            detail: { searchTerm: this.searchTerm }
        }));
    }

    handleTableView() {
        this.currentView = 'table';
        this.dispatchEvent(new CustomEvent('viewchange', { detail: { view: 'table' }}));
    }

    handleCardView() {
        this.currentView = 'card';
        this.dispatchEvent(new CustomEvent('viewchange', { detail: { view: 'card' }}));
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        const column = this.columns.find(c => c.fieldName === field);

        if (column && column.sortable !== false) {
            if (this.sortField === field) {
                this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
            } else {
                this.sortField = field;
                this.sortDirection = 'asc';
            }

            this.dispatchEvent(new CustomEvent('sort', {
                detail: { field: this.sortField, direction: this.sortDirection }
            }));
        }
    }

    handleRowClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('rowclick', {
            detail: { recordId }
        }));
    }

    handleRowKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleRowClick(event);
        }
    }

    handleCellClick(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        const fieldName = event.currentTarget.dataset.field;
        this.dispatchEvent(new CustomEvent('cellclick', {
            detail: { recordId, fieldName }
        }));
    }

    handleRowAction(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        const actionName = event.currentTarget.dataset.action;
        this.dispatchEvent(new CustomEvent('rowaction', {
            detail: { recordId, actionName }
        }));
    }

    handleCreate() {
        this.dispatchEvent(new CustomEvent('create'));
    }

    handleLoadMore() {
        this.dispatchEvent(new CustomEvent('loadmore'));
    }

    // Public API
    @api
    setLoading(loading) {
        this.isLoading = loading;
    }

    @api
    setLoadingMore(loading) {
        this.isLoadingMore = loading;
    }

    @api
    setView(view) {
        if (['table', 'card'].includes(view)) {
            this.currentView = view;
        }
    }

    @api
    clearSearch() {
        this.searchTerm = '';
    }
}