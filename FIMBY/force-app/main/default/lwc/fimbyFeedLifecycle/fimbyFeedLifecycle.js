import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

/**
 * Shared Ask/Offer/Event/Bulk Buy card lifecycle contract for feed surfaces
 * (home feed, profile activity). Pills are inert labels; the CTA rules mirror
 * the detail page so a card never offers an action the post can't take.
 */

export const COMPLETED_STATUS = 'Completed (Offer Accepted / Need Met)';
export const PICKUP_READY_STATUS = 'Pickup_Ready';

function num(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
}

export function replyCountLabel(count) {
    return count === 1 ? '1 neighbour replied' : `${count} neighbours replied`;
}

/**
 * @param {object} item raw FimbyFeedItem DTO
 * @param {object} flags { isEvent, isBulkBuy, isPoster, viewerResponded }
 * @returns {{ statusPills: Array|null, responseDisabled: boolean, isCompleted: boolean, ctaOverride: object|null }}
 */
export function feedLifecycleState(item, flags) {
    const { isEvent, isBulkBuy, isPoster, viewerResponded } = flags;
    const state = { statusPills: null, responseDisabled: false, isCompleted: false, ctaOverride: null };

    if (item.status === COMPLETED_STATUS) {
        state.isCompleted = true;
        if (item.closedOutcome) {
            state.statusPills = [{ key: 'outcome', label: item.closedOutcome, tone: 'outcome' }];
        }
        return state;
    }

    const viewPost = {
        label: 'View Post',
        iconUrl: `${IMPACT_ICONS}/Magnify.png`,
        pillClass: 'response-pill-responded'
    };

    if (isBulkBuy) {
        const fullyReserved = item.totalAvailable != null && num(item.totalQuantity) > 0 && num(item.totalAvailable) <= 0;
        if (item.status === PICKUP_READY_STATUS) {
            state.statusPills = [{ key: 'pickup', label: 'Pickup Ready', tone: 'matched' }];
        } else if (fullyReserved) {
            state.statusPills = [{ key: 'full', label: 'Fully reserved', tone: 'matched' }];
        }
        if (state.statusPills && !isPoster && !viewerResponded) {
            state.ctaOverride = viewPost;
        }
        return state;
    }

    if (isEvent) {
        const full = item.eventType === 'Gathering'
            && item.totalAvailable != null
            && num(item.totalQuantity) > 0
            && num(item.totalAvailable) <= 0;
        if (full) {
            state.statusPills = [{ key: 'full', label: 'Full', tone: 'matched' }];
            if (!isPoster && !viewerResponded) {
                state.responseDisabled = true;
                state.ctaOverride = {
                    label: 'Event Full',
                    iconUrl: `${IMPACT_ICONS}/dining-table.png`,
                    pillClass: ''
                };
            }
        }
        return state;
    }

    const matched = num(item.totalQuantity) > 0 && num(item.totalAccepted) >= num(item.totalQuantity);
    if (matched) {
        const label = item.itemType === 'Need' ? 'Help Found' : 'Spoken for';
        state.statusPills = [{ key: 'matched', label, tone: 'matched' }];
    } else if (num(item.replyCount) > 0) {
        state.statusPills = [{ key: 'replies', label: replyCountLabel(num(item.replyCount)), tone: 'active' }];
    }
    return state;
}
