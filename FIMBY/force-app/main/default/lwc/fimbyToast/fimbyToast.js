import { LightningElement, track } from 'lwc';
import { FIMBY_TOAST_EVENT } from 'c/fimbyToastHelper';

const DEFAULT_DURATION = {
    error: 7000,
    warning: 6000,
    info: 5000
};

const VARIANT_ICON = {
    error: 'utility:error',
    warning: 'utility:warning',
    info: 'utility:info'
};

// Errors must be announced immediately (assertive); info/warning politely.
const VARIANT_LIVE = {
    error: 'assertive',
    warning: 'assertive',
    info: 'polite'
};

/**
 * Shell-mounted toast host for the FIMBY feedback standard. Mounted once in the
 * persistent shell (fimbyUniversalHeader) so it survives soft navigation.
 * Listens on `window` for `fimbytoast` events fired by `fimbyToastHelper`.
 *
 * Reserved for OPERATION FAILURES (server/FLS/network). In-form validation and
 * success do not use this — see the feedback standard in the fimby-lwc skill.
 */
export default class FimbyToast extends LightningElement {
    @track _toasts = [];
    _seq = 0;
    _timers = {};

    connectedCallback() {
        this._handleToast = this._handleToast.bind(this);
        window.addEventListener(FIMBY_TOAST_EVENT, this._handleToast);
    }

    disconnectedCallback() {
        window.removeEventListener(FIMBY_TOAST_EVENT, this._handleToast);
        Object.values(this._timers).forEach((t) => clearTimeout(t));
        this._timers = {};
    }

    get hasToasts() {
        return this._toasts.length > 0;
    }

    _handleToast(event) {
        const { message, variant = 'error', title = '', duration } = event.detail || {};
        if (!message) return;

        const id = ++this._seq;
        const toast = {
            id,
            message,
            title,
            hasTitle: !!title,
            variant,
            iconName: VARIANT_ICON[variant] || VARIANT_ICON.error,
            ariaLive: VARIANT_LIVE[variant] || 'assertive',
            ariaRole: variant === 'info' ? 'status' : 'alert',
            cssClass: `toast toast--${variant}`
        };
        this._toasts = [...this._toasts, toast];

        const ms = duration || DEFAULT_DURATION[variant] || DEFAULT_DURATION.error;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timers[id] = setTimeout(() => this._dismiss(id), ms);
    }

    handleDismiss(event) {
        const id = parseInt(event.currentTarget.dataset.id, 10);
        this._dismiss(id);
    }

    _dismiss(id) {
        if (this._timers[id]) {
            clearTimeout(this._timers[id]);
            delete this._timers[id];
        }
        this._toasts = this._toasts.filter((t) => t.id !== id);
    }
}
