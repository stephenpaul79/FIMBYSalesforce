import { LightningElement, api } from 'lwc';

export default class FimbyAllocationThermometer extends LightningElement {
    @api totalShares = 0;
    @api reservedShares = 0;
    @api ownerShares = 0;
    @api perReservationLimit = 1;
    @api unitLabel = 'share';
    @api compact = false;
    @api myReservation = 0;

    get _total() { return Number(this.totalShares) || 0; }
    get _reserved() { return Number(this.reservedShares) || 0; }
    get _owner() { return Number(this.ownerShares) || 0; }
    get _mine() { return Number(this.myReservation) || 0; }
    get _taken() { return this._owner + this._reserved; }

    get availableShares() {
        return Math.max(0, this._total - this._taken);
    }

    get percentFilled() {
        if (this._total <= 0) return 0;
        return Math.min(100, Math.round((this._taken / this._total) * 100));
    }

    get filledSegments() {
        const total = this._total;
        const owner = this._owner;
        const reserved = this._reserved;
        const mine = this._mine;
        if (total <= 0) return [];

        const segments = [];
        for (let i = 0; i < total; i++) {
            const isOwner = i < owner;
            const isReserved = !isOwner && i < owner + reserved;
            const filled = isOwner || isReserved;
            const mineStart = owner + reserved - mine;
            const isMine = isReserved && mine > 0 && i >= mineStart;
            segments.push({
                index: i,
                filled,
                isOwner,
                isMine,
                segmentClass: isOwner ? 'segment segment-owner' :
                    isMine ? 'segment segment-filled segment-mine' :
                    filled ? 'segment segment-filled' : 'segment'
            });
        }
        return segments;
    }

    get isFullyReserved() {
        return this._total > 0 && this._taken >= this._total;
    }

    get reservedLabel() {
        const label = this.unitLabel || 'share';
        const plural = this._total === 1 || label.endsWith('s') ? label : label + 's';
        if (this._owner > 0) {
            return `${this._reserved} reserved + ${this._owner} for buyer of ${this._total} ${plural}`;
        }
        return `${this._reserved} of ${this._total} ${plural} reserved`;
    }

    get displayMode() {
        return this.compact ? 'compact' : 'expanded';
    }

    get compactFillStyle() {
        return `width: ${this.percentFilled}%;`;
    }
}