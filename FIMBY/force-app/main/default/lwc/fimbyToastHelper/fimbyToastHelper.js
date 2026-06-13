/**
 * FIMBY feedback standard — operation-failure toasts.
 *
 * `ShowToastEvent` does not render in LWR Experience Cloud sites, so all
 * transient, global feedback goes through this helper instead. It dispatches a
 * bubbling/composed DOM CustomEvent that the shell-mounted `c-fimby-toast`
 * (in `fimbyUniversalHeader`) listens for and renders.
 *
 * Use this for OPERATION FAILURES (server/FLS/network: "Couldn't save").
 * Do NOT use it for in-form validation ("Name is required") — those belong
 * inline next to the field — or for success — success is an inline banner when
 * the user stays, or nothing when the action navigates away.
 */

const TOAST_EVENT = 'fimbytoast';

const VALID_VARIANTS = ['error', 'warning', 'info'];

/**
 * Fire a toast.
 * @param {object} opts
 * @param {string} opts.message     Required. Human, non-punitive copy.
 * @param {string} [opts.variant]   'error' (default) | 'warning' | 'info'.
 * @param {string} [opts.title]     Optional short heading above the message.
 * @param {number} [opts.duration]  Override auto-dismiss ms. Defaults by variant.
 */
export function fireToast({ message, variant = 'error', title = '', duration } = {}) {
    if (!message) return;
    const safeVariant = VALID_VARIANTS.includes(variant) ? variant : 'error';
    window.dispatchEvent(
        new CustomEvent(TOAST_EVENT, {
            detail: { message, variant: safeVariant, title, duration }
        })
    );
}

/**
 * Convenience for the common case — surface an Apex/JS error as a toast.
 * Pulls the user-facing message out of an AuraHandledException or Error.
 * @param {*} error              The caught error.
 * @param {string} [fallback]    Shown when the error carries no message.
 */
export function fireErrorToast(error, fallback = 'Something went wrong. Please try again.') {
    const message = error?.body?.message || error?.message || fallback;
    fireToast({ message, variant: 'error' });
}

export const FIMBY_TOAST_EVENT = TOAST_EVENT;
