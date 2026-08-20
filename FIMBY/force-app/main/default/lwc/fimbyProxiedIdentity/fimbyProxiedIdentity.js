import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';

/**
 * Shared answer to "am I currently acting as a parent-managed child?".
 *
 * Several surfaces need it — the library and skill composers, their entry points,
 * My Neighbours, and the neighbour profile — and every one of them would otherwise
 * repeat the same Apex import, the same null-safe read, and the same fail-open catch.
 *
 * The promise is cached per page load rather than per component, so a screen with a
 * browser and a composer on it asks the server once. Soft navigation keeps the module
 * alive, which is correct: switching identity does a full reload and clears it.
 */
let _identityPromise = null;

/**
 * @returns {Promise<boolean>} true when the acting identity is a parent-managed child.
 *          Resolves false on any failure — the server-side guard is the real
 *          enforcement, and failing closed here would strip an ordinary neighbour's
 *          own compose buttons on a network blip.
 */
export function isActingAsProxiedChild() {
    if (!_identityPromise) {
        _identityPromise = getActingAsContact()
            .then(identity => identity?.isActingAsProxiedChild === true)
            .catch(error => {
                console.error('Error resolving acting identity:', error);
                _identityPromise = null;
                return false;
            });
    }
    return _identityPromise;
}

/** Clears the cached answer. For tests and for anything that changes identity in place. */
export function resetProxiedIdentityCache() {
    _identityPromise = null;
}
