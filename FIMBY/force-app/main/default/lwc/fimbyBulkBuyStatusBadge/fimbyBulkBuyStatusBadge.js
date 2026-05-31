import { LightningElement, api } from 'lwc';

/** Status configuration: badgeClass, badgeLabel, statusIcon */
const STATUS_CONFIG = {
    'Available':       { badgeClass: 'badge-green',  badgeLabel: 'Available',       statusIcon: 'utility:success' },
    'Shares Available': { badgeClass: 'badge-teal',   badgeLabel: 'Shares Available', statusIcon: 'utility:adduser' },
    'Fully Reserved':  { badgeClass: 'badge-amber',  badgeLabel: 'Fully Reserved', statusIcon: 'utility:lock' },
    'Pickup Ready':    { badgeClass: 'badge-blue',   badgeLabel: 'Pickup Ready',   statusIcon: 'utility:package' },
    'Completed':       { badgeClass: 'badge-green',  badgeLabel: 'Completed',      statusIcon: 'utility:check' },
    'Cancelled':       { badgeClass: 'badge-grey',   badgeLabel: 'Cancelled',      statusIcon: 'utility:close' },
    'Expired':         { badgeClass: 'badge-grey',   badgeLabel: 'Expired',        statusIcon: 'utility:warning' }
};

/**
 * Renders a status badge for Bulk Buy posts using Display_Status__c formula field value.
 */
export default class FimbyBulkBuyStatusBadge extends LightningElement {
    /** Display status value from Display_Status__c formula field */
    @api displayStatus;

    get badgeClass() {
        const config = STATUS_CONFIG[this.displayStatus];
        const cls = config ? config.badgeClass : 'badge-grey';
        return `fimby-badge ${cls}`;
    }

    get badgeLabel() {
        const config = STATUS_CONFIG[this.displayStatus];
        return config ? config.badgeLabel : (this.displayStatus || '');
    }

    get statusIcon() {
        const config = STATUS_CONFIG[this.displayStatus];
        return config ? config.statusIcon : '';
    }

    get hasDisplayStatus() {
        return this.displayStatus && typeof this.displayStatus === 'string' && this.displayStatus.trim().length > 0;
    }
}