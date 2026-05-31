import { LightningElement, api, track } from 'lwc';
import getVouchingHistory from '@salesforce/apex/FimbyVouchController.getVouchingHistory';

const ARIA_LABELS = {
    neutral: 'No vouch yet',
    green: 'Active vouch',
    red: 'Vouch revoked'
};

const SLOT_COUNT = 5;

export default class FimbyVouchingHistory extends LightningElement {
    @api contactId;
    @api isPaused = false;

    @track slots = Array(SLOT_COUNT).fill('neutral');
    @track isLoaded = false;
    @track hasError = false;

    connectedCallback() {
        if (this.contactId) {
            this.loadHistory();
        } else {
            this.isLoaded = true;
        }
    }

    loadHistory() {
        getVouchingHistory({ contactId: this.contactId })
            .then((records) => {
                // Records arrive newest-first. Map directly so the newest event lands in the
                // leftmost slot. Server-side filter has already removed exempted revokes
                // (Revoked + Counts_Toward_Voucher_Pause__c = false), so any Revoked here counts.
                const colors = (records || []).map((r) => {
                    if (r.status === 'Approved') return 'green';
                    if (r.status === 'Revoked') return 'red';
                    return 'neutral';
                });
                // Pad empty slots on the right.
                while (colors.length < SLOT_COUNT) {
                    colors.push('neutral');
                }
                this.slots = colors.slice(0, SLOT_COUNT);
                this.hasError = false;
            })
            .catch(() => {
                this.slots = Array(SLOT_COUNT).fill('neutral');
                this.hasError = true;
            })
            .finally(() => {
                this.isLoaded = true;
            });
    }

    get hasHistory() {
        return this.slots.some(s => s !== 'neutral');
    }

    get showSection() {
        // Always show on owner's own profile (private view) so the strip is
        // discoverable. Empty = 5 neutral slots with "no vouches given yet" aria text.
        return this.isLoaded;
    }

    get slotData() {
        return this.slots.map((color, index) => ({
            index,
            color,
            cssClass: `slot slot-${color}`,
            ariaLabel: ARIA_LABELS[color] || ARIA_LABELS.neutral
        }));
    }
}
