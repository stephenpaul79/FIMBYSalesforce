import { LightningElement, api } from 'lwc';

const VARIANT_ICON = {
    success: 'utility:success',
    error: 'utility:error',
    warning: 'utility:warning',
    info: 'utility:info'
};

const VARIANT_ICON_VARIANT = {
    success: 'success',
    error: 'error',
    warning: 'warning',
    info: ''
};

/**
 * Canonical inline banner for the FIMBY feedback standard.
 *
 * Use for SUCCESS confirmation when the user stays on the surface, and for
 * IN-FORM VALIDATION errors that belong next to the action. Operation failures
 * (server/FLS/network) use `c/fimbyToast` via `fireToast` instead.
 *
 * Success → role="status" / aria-live="polite" (don't interrupt).
 * Error/warning → role="alert" / aria-live="assertive" (announce now).
 * Icon + text always — colour is never the sole signal (WCAG 1.4.1).
 */
export default class FimbyInlineBanner extends LightningElement {
    /** 'success' | 'error' | 'warning' | 'info' */
    @api variant = 'error';
    /** The message to show. Banner renders nothing when empty. */
    @api message = '';

    get hasMessage() {
        return !!this.message;
    }

    get bannerClass() {
        return `inline-banner inline-banner--${this.variant}`;
    }

    get iconName() {
        return VARIANT_ICON[this.variant] || VARIANT_ICON.info;
    }

    get iconVariant() {
        return VARIANT_ICON_VARIANT[this.variant] || '';
    }

    get ariaRole() {
        return this.variant === 'error' || this.variant === 'warning' ? 'alert' : 'status';
    }

    get ariaLive() {
        return this.variant === 'error' || this.variant === 'warning' ? 'assertive' : 'polite';
    }
}
