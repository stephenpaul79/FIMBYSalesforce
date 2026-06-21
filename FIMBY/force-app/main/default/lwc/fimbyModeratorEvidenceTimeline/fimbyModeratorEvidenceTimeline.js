import { LightningElement, api } from 'lwc';

const SOURCE_LABELS = {
    Content_Report: 'Content Report',
    Bulk_Buy_Escalation: 'Bulk Buy Escalation',
    Block_Report: 'Block Report',
    Feedback: 'Feedback',
    Support_Concern: 'Support Concern',
    Moderator_Action: 'Moderator Action',
    System: 'System'
};

export default class FimbyModeratorEvidenceTimeline extends LightningElement {
    _items = [];

    @api
    get evidenceItems() { return this._items; }
    set evidenceItems(value) {
        this._items = (value || []).map(item => ({
            ...item,
            _sourceLabel: SOURCE_LABELS[item.Source_Type__c] || item.Source_Type__c || 'Report',
            _sourceClass: 'source-badge source-' + (item.Source_Type__c || 'default').toLowerCase().replace(/_/g, '-'),
            _formattedDate: this._formatDate(item.Reported_Date__c)
        }));
    }

    get hasItems() { return this._items.length > 0; }
    get isEmpty() { return this._items.length === 0; }

    _formatDate(dateStr) {
        if (!dateStr) return '';
        try {
            const d = new Date(dateStr);
            const now = new Date();
            const diffMs = now - d;
            const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
            if (diffHours < 1) return 'Just now';
            if (diffHours < 24) return `${diffHours}h ago`;
            const diffDays = Math.floor(diffHours / 24);
            if (diffDays < 7) return `${diffDays}d ago`;
            return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short' });
        } catch {
            return dateStr;
        }
    }
}