// Earth tones with white initials at >= 4.5:1 in light and dark themes.
// earth-teal is excluded: it reads as the CTA colour and its dark variant misses AA.
// Order and hashing must match FimbyAvatarTone.cls so email and app agree.
const TONE_NAMES = ['sage', 'ochre', 'slate', 'terracotta', 'dusty-violet', 'moss', 'driftwood'];

export const TONE_HEX = ['#476B4C', '#7D6234', '#4E6878', '#8A5936', '#625A76', '#566744', '#6B5E50'];

const TONES = TONE_NAMES.map((tone, i) => `var(--fimby-earth-${tone}, ${TONE_HEX[i]})`);

const SALESFORCE_ID = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

function normalizeId(id) {
    const value = (id || '').toString().trim();
    return SALESFORCE_ID.test(value) ? value.substring(0, 15) : null;
}

function toneKey(identity) {
    const source = typeof identity === 'string' ? { name: identity } : identity || {};
    const contactId = normalizeId(source.contactId);
    if (contactId) return `contact:${contactId}`;
    const accountId = normalizeId(source.organizationAccountId);
    if (source.isOrganization && accountId) return `account:${accountId}`;
    const name = (source.name || '').trim().replace(/\s+/g, ' ').toLowerCase();
    return `name:${name}`;
}

export function getInitials(name) {
    const words = (name || '').trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) return '?';
    return words
        .slice(0, 2)
        .map((word) => Array.from(word)[0])
        .join('')
        .toUpperCase();
}

export function getAvatarToneIndex(identity) {
    const key = toneKey(identity);
    let hash = 0;
    for (let i = 0; i < key.length; i++) {
        hash = (hash * 31 + key.charCodeAt(i)) % 2147483647;
    }
    return hash % TONES.length;
}

export function getAvatarTone(identity) {
    return TONES[getAvatarToneIndex(identity)];
}

export function getAvatarToneStyle(identity) {
    return `background-color: ${getAvatarTone(identity)};`;
}
