/**
 * Shared vocabulary for proxied presence in message surfaces. Three thread
 * components render the same attribution, so the tokens and the role words live
 * here — a thread should never call the same person a guardian in one view and a
 * support person in another.
 *
 * Tokens mirror FimbyProxiedPresenceGuard.PROXY_TYPE_*.
 */
export const PROXY_TYPE_PARENT_MANAGED = 'parent_managed';
export const PROXY_TYPE_SUPPORTED = 'supported';

const ROLE_WORDS = {
    [PROXY_TYPE_PARENT_MANAGED]: 'guardian',
    [PROXY_TYPE_SUPPORTED]: 'support person'
};

/**
 * Attribution for a message someone typed on another person's behalf.
 * Falls back to a bare "Sent by" when the relationship can't be resolved, so a
 * missing proxy type degrades to less detail rather than a wrong role.
 *
 * @param {string} name Who physically typed the message.
 * @param {string} proxyType A PROXY_TYPE_* token, or falsy when unknown.
 * @returns {string} e.g. "Sent by Sarah · guardian"
 */
export function buildSentByLabel(name, proxyType) {
    if (!name) {
        return '';
    }
    const role = ROLE_WORDS[proxyType];
    return role ? `Sent by ${name} \u00b7 ${role}` : `Sent by ${name}`;
}

/**
 * Plain-language explainer for a thread header, shown beside the proxy badge.
 *
 * @param {string} firstName The person whose profile is proxied.
 * @param {string} proxyType A PROXY_TYPE_* token.
 * @returns {string} Empty when the type isn't a known proxy.
 */
export function buildProxyExplainer(firstName, proxyType) {
    const who = firstName || 'this neighbour';
    if (proxyType === PROXY_TYPE_PARENT_MANAGED) {
        return `A parent or guardian looks after this profile and replies on ${who}'s behalf.`;
    }
    if (proxyType === PROXY_TYPE_SUPPORTED) {
        return `A support person helps ${who} use FIMBY and may reply on their behalf.`;
    }
    return '';
}
