const BADGE_VARIANTS = {
    direct: { label: 'Direct Msg', variant: 'direct' },
    response: { label: 'Ask / Offer', variant: 'response' },
    library: { label: 'Lending', variant: 'library' },
    bulkbuy: { label: 'Bulk Buy', variant: 'bulkbuy' },
    checkin: { label: 'Check In', variant: 'checkin' },
    event: { label: 'Event', variant: 'event' },
    gathering: { label: 'Gathering', variant: 'gathering' },
    'community-event': { label: 'Community Event', variant: 'community-event' },
    vouch: { label: 'Vouch', variant: 'vouch' }
};

const CONTEXT_TO_VARIANT = {
    Library_Lending: 'library',
    Bulk_Buy: 'bulkbuy',
    Missed_Pickup: 'checkin',
    Event: 'event',
    Vouch_Request: 'vouch',
    Direct: 'direct'
};

const AVATAR_ICON_BY_BADGE = {
    bulkbuy: 'bulkbuy.png',
    event: 'people.png',
    gathering: 'dining-table.png',
    'community-event': 'cityscape.png',
    library: 'borrow.png',
    checkin: 'checkin.png',
    vouch: 'care.png',
    response: 'reply.png',
    direct: 'chat.png'
};

export function getInboxBadge(badgeType) {
    const key = badgeType || 'direct';
    const entry = BADGE_VARIANTS[key] || BADGE_VARIANTS.direct;
    return {
        label: entry.label,
        cssClass: `inbox-badge badge-${entry.variant}`
    };
}

export function getHeaderBadge(contextType) {
    if (!contextType || contextType === 'Direct') {
        return null;
    }
    const variant = CONTEXT_TO_VARIANT[contextType];
    if (!variant) {
        return null;
    }
    const entry = BADGE_VARIANTS[variant] || BADGE_VARIANTS.direct;
    return {
        label: entry.label,
        cssClass: `header-badge badge-${entry.variant}`
    };
}

export function getThreadAvatarIcon(badgeType) {
    return AVATAR_ICON_BY_BADGE[badgeType] || AVATAR_ICON_BY_BADGE.direct;
}

/** Maps Conversation__c.Context_Type__c to inbox/thread badge slug. */
export function getBadgeTypeFromContext(contextType) {
    if (!contextType) {
        return 'direct';
    }
    return CONTEXT_TO_VARIANT[contextType] || 'direct';
}

export function getGroupAvatarVariant(badgeType) {
    const entry = BADGE_VARIANTS[badgeType] || BADGE_VARIANTS.direct;
    return entry.variant;
}
