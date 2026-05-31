import { LightningElement, api, track } from 'lwc';
import getBulkBuyHistory from '@salesforce/apex/FimbyFollowUpController.getBulkBuyHistory';

const ARIA_LABELS = {
    neutral: 'No recorded event',
    green: 'Completed shared purchase',
    red: 'Did not follow through',
    amber: 'Restored by admin'
};

export default class FimbyBulkBuyHistory extends LightningElement {
    @api contactId;

    @track slots = ['neutral', 'neutral', 'neutral'];
    @track isBlocked = false;
    @track hasActiveAmber = false;
    @track isLoaded = false;

    connectedCallback() {
        if (this.contactId) {
            this.loadHistory();
        } else {
            this.isLoaded = true;
        }
    }

    loadHistory() {
        getBulkBuyHistory({ contactId: this.contactId })
            .then((result) => {
                if (result?.success && Array.isArray(result.slots)) {
                    // Apex returns newest-first (leftmost). Pad empty slots on the right.
                    this.slots = result.slots.slice(0, 3);
                    while (this.slots.length < 3) {
                        this.slots.push('neutral');
                    }
                    this.isBlocked = Boolean(result.isBlocked);
                    this.hasActiveAmber = Boolean(result.hasActiveAmber);
                }
            })
            .catch(() => {
                this.slots = ['neutral', 'neutral', 'neutral'];
                this.isBlocked = false;
                this.hasActiveAmber = false;
            })
            .finally(() => {
                this.isLoaded = true;
            });
    }

    get hasHistory() {
        return this.slots.some((s) => s !== 'neutral');
    }

    get showSection() {
        // Always show on owner's own profile (private view) so the strip is
        // discoverable. Empty = 3 neutral slots; users see where history will appear.
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